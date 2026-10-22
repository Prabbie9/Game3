class_name HumanoidVisual
extends Node3D
## Mixamo character model + shared animation set, driven by a code-built AnimationTree.
## Used by the player and (later) every NPC. Faces -Z like every other Godot node.

signal action_finished(state: StringName)

const CHAR_PATH := "res://assets/source/mixamo/characters/%s.fbx"

@export var character_file := "ch08_nonpbr"

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var motion_scale := 1.0

## Native speeds (m/s) for this character's proportions.
var walk_speed := 1.4
var run_speed := 3.6
var sprint_speed := 6.0
var aim_walk_speed := 1.3
var aim_run_speed := 3.2

var _aim_points := {}

## One-shot actions: clip -> playback speed (they return to "ground" when finished).
const ACTIONS := {
	"vault": 1.1, "vault_high": 1.1, "jump_hang": 1.25, "climb": 1.1, "get_up_back": 1.35, "get_up_front": 1.5, "turn_left": 1.35, "turn_right": 1.35,
	"turn_180": 1.3, "run_stop": 1.0, "punch_jab": 1.25, "punch_cross": 1.2, "punch_hook": 1.2, "hit_head": 1.3,
	"hit_body": 1.3, "hard_land": 1.0
}
## Looping base states the player can sit in, each with its own 1D blend: state -> [[clip, position], ...]
var crouch_speed := 1.4
var swim_speed := 0.5
var cover_speed := 1.15


func _ready() -> void:
	_build_model()
	_build_tree()


func _build_model() -> void:
	model = load(CHAR_PATH % character_file).instantiate()
	model.rotation.y = PI  # Mixamo characters face +Z
	add_child(model)
	skeleton = model.get_node("GeneralSkeleton")
	motion_scale = skeleton.motion_scale
	var imported := model.get_node_or_null("AnimationPlayer")
	if imported:
		imported.free()
	for mi in skeleton.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	model.add_child(anim_player)
	anim_player.root_node = NodePath("..")
	anim_player.add_animation_library("", AnimLib.get_library())
	walk_speed = AnimLib.speed_of("walk", motion_scale)
	run_speed = AnimLib.speed_of("run", motion_scale)
	sprint_speed = AnimLib.speed_of("sprint", motion_scale)
	aim_walk_speed = AnimLib.speed_of("pistol_fwd", motion_scale)
	aim_run_speed = AnimLib.speed_of("pistol_run", motion_scale)
	crouch_speed = AnimLib.speed_of("crouch_walk", motion_scale)
	swim_speed = AnimLib.speed_of("swim", motion_scale)
	cover_speed = AnimLib.speed_of("cover_right", motion_scale)


func _anim(clip: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	if AnimLib.WINDOWS.has(clip):
		var w: Array = AnimLib.WINDOWS[clip]
		a.use_custom_timeline = true
		a.start_offset = w[0]
		a.timeline_length = w[1]
		a.stretch_time_scale = false
		a.loop_mode = Animation.LOOP_NONE
	return a


func _build_tree() -> void:
	var ground := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_anim("idle"), 0.0, -1, &"idle")
	loco.add_blend_point(_anim("walk"), walk_speed, -1, &"walk")
	loco.add_blend_point(_anim("run"), run_speed, -1, &"run")
	loco.add_blend_point(_anim("sprint"), sprint_speed, -1, &"sprint")
	loco.min_space = 0.0
	loco.max_space = sprint_speed * 1.5
	loco.sync = true
	ground.add_node("loco", loco, Vector2(0, 0))
	ground.add_node("loco_ts", AnimationNodeTimeScale.new(), Vector2(200, 0))
	ground.connect_node("loco_ts", 0, "loco")

	# Aiming: full-body strafe set, positioned at each clip's own travel velocity (local x = right, y = forward).
	var aim := AnimationNodeBlendSpace2D.new()
	aim.min_space = Vector2(-4, -4)
	aim.max_space = Vector2(4, 4)
	aim.sync = true
	for clip in ["pistol_idle", "pistol_fwd", "pistol_back", "pistol_left", "pistol_right", "pistol_run"]:
		var v: Vector3 = AnimLib.velocity.get(clip, Vector3.ZERO) * motion_scale
		# Mixamo +Z is forward, +X is the character's left
		var p := Vector2(-v.x, v.z)
		_aim_points[clip] = p
		aim.add_blend_point(_anim(clip), p, -1, StringName(clip))
	ground.add_node("aim", aim, Vector2(0, 200))
	ground.add_node("aim_blend", AnimationNodeBlend2.new(), Vector2(400, 100))
	ground.connect_node("aim_blend", 0, "loco_ts")
	ground.connect_node("aim_blend", 1, "aim")
	ground.connect_node("output", 0, "aim_blend")

	var sm := AnimationNodeStateMachine.new()
	sm.add_node("ground", ground)
	for s in ["jump", "jump_run", "fall", "land", "car_enter", "car_exit", "drive"]:
		sm.add_node(s, _anim(s))
	# looping base states with a 1D blend (speed, or lateral speed for cover)
	sm.add_node("crouch", _blend1d("crouch", [["crouch_idle", 0.0], ["crouch_walk", crouch_speed]]))
	sm.add_node("swim", _blend1d("swim", [["swim_idle", 0.0], ["swim", swim_speed]]))
	sm.add_node("cover", _blend1d("cover", [["cover_left", -cover_speed], ["cover_idle", 0.0], ["cover_right", cover_speed]]))
	sm.add_node("cover_low", _blend1d("cover_low", [["cover_low_left", -cover_speed], ["cover_low_idle", 0.0], ["cover_low_right", cover_speed]]))
	var bases := ["ground", "crouch", "swim", "cover", "cover_low"]
	for a in bases:
		for b in bases:
			if a != b:
				_link(sm, a, b, 0.3)
	for act in ACTIONS:
		var bt := AnimationNodeBlendTree.new()
		bt.add_node("clip", _anim(act), Vector2(0, 0))
		var ts := AnimationNodeTimeScale.new()
		bt.add_node("speed", ts, Vector2(200, 0))
		bt.connect_node("speed", 0, "clip")
		bt.connect_node("output", 0, "speed")
		sm.add_node(act, bt)
		for b in bases:
			_link(sm, b, act, 0.12 if act.begins_with("punch") or act.begins_with("hit") else 0.2)
		_link(sm, act, "ground", 0.2, true)
		_link(sm, act, "ground", 0.2)
		_link(sm, act, "crouch", 0.2)
		_link(sm, act, "fall", 0.2)
	for a in ["punch_jab", "punch_cross", "punch_hook"]:
		for b in ["punch_jab", "punch_cross", "punch_hook"]:
			if a != b:
				_link(sm, a, b, 0.1)
	_link(sm, "jump_hang", "climb", 0.0)  # both start/end in the same braced hang
	for b in ["crouch", "cover", "cover_low", "swim"]:
		_link(sm, "fall", b, 0.3)
		_link(sm, b, "fall", 0.25)
		_link(sm, b, "jump", 0.15)
	_link(sm, "Start", "ground", 0.0)
	(sm.get_transition(0) as AnimationNodeStateMachineTransition).advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	for s in ["jump", "jump_run", "fall"]:
		_link(sm, "ground", s, 0.15)
	_link(sm, "jump", "fall", 0.25, true)
	_link(sm, "jump_run", "fall", 0.3, true)
	for s in ["jump", "jump_run", "fall"]:
		_link(sm, s, "land", 0.08)
		_link(sm, s, "ground", 0.2)
	_link(sm, "land", "ground", 0.25, true)
	_link(sm, "land", "fall", 0.15)
	_link(sm, "ground", "car_enter", 0.2)
	_link(sm, "car_enter", "drive", 0.25, true)
	_link(sm, "drive", "car_exit", 0.2)
	_link(sm, "car_exit", "ground", 0.3, true)
	_link(sm, "car_enter", "ground", 0.2)
	_link(sm, "drive", "ground", 0.2)
	_link(sm, "ground", "drive", 0.2)

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = sm
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
	for act in ACTIONS:
		tree.set("parameters/%s/speed/scale" % act, ACTIONS[act])
	playback = tree.get("parameters/playback")
	tree.animation_finished.connect(func(a: StringName): action_finished.emit(a))


func _blend1d(prefix: String, points: Array) -> AnimationNodeBlendTree:
	var bs := AnimationNodeBlendSpace1D.new()
	var lo := 0.0
	var hi := 0.0
	for pt in points:
		bs.add_blend_point(_anim(pt[0]), pt[1], -1, StringName(pt[0]))
		lo = minf(lo, pt[1])
		hi = maxf(hi, pt[1])
	bs.min_space = lo * 1.5 - 0.01
	bs.max_space = hi * 1.5 + 0.01
	bs.sync = true
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("blend", bs, Vector2(0, 0))
	bt.add_node("ts", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("ts", 0, "blend")
	bt.connect_node("output", 0, "ts")
	return bt


## Drive a looping base state's blend: value = speed (or lateral speed for cover); playback speeds up beyond
## the fastest clip so strides keep matching the ground.
func set_state_blend(state: String, value: float, fastest: float) -> void:
	tree.set("parameters/%s/blend/blend_position" % state, value)
	tree.set("parameters/%s/ts/scale" % state, maxf(1.0, absf(value) / maxf(fastest, 0.01)))


## Duration (seconds of real time) of a one-shot action at its playback speed.
func action_duration(act: String) -> float:
	var w: Array = AnimLib.WINDOWS.get(act, [])
	var length := float(w[1]) if w.size() == 2 else clip_length(act)
	return length / float(ACTIONS.get(act, 1.0))


## Root-motion of an EXTRACT clip at action time t (real seconds since the action started), relative to the
## action start, in this node's space (Godot -Z forward).
func path_transform(act: String, t: float) -> Transform3D:
	if not AnimLib.paths.has(act):
		return Transform3D.IDENTITY
	var w: Array = AnimLib.WINDOWS.get(act, [0.0, 0.0])
	var speed: float = ACTIONS.get(act, 1.0)
	var t0: float = w[0]
	var a := AnimLib.sample_path(act, t0)
	var b := AnimLib.sample_path(act, t0 + t * speed)
	var d: Vector3 = (b[0] - a[0]) * motion_scale
	var yaw0: float = a[1]
	var dl := Basis(Vector3.UP, -yaw0) * d  # into the frame the root had at the action start
	return Transform3D(Basis(Vector3.UP, b[1] - yaw0), Vector3(-dl.x, dl.y, -dl.z))


## Clip's built-in ledge height in metres (EXTRACT_Y clips), for scaling to real obstacles.
func path_ledge(act: String) -> float:
	return float(AnimLib.paths.get(act, {}).get("ledge", 0.0)) * motion_scale


func _link(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float, at_end := false) -> void:
	if sm.has_transition(from, to):
		return
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	if at_end:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(from, to, t)


## Ground locomotion: horizontal speed in m/s. Speeds above the sprint clip speed up playback.
func set_locomotion(speed: float) -> void:
	tree.set("parameters/ground/loco/blend_position", speed)
	tree.set("parameters/ground/loco_ts/scale", maxf(1.0, speed / maxf(sprint_speed, 0.1)))


## Aim strafing: local velocity (x = right, y = forward) in m/s; weight 0..1 blends the aim set in.
func set_aim(local_velocity: Vector2, weight: float) -> void:
	tree.set("parameters/ground/aim/blend_position", local_velocity)
	tree.set("parameters/ground/aim_blend/blend_amount", weight)


func travel(state: StringName) -> void:
	playback.travel(state)


func jump_to(state: StringName) -> void:
	playback.start(state, true)


func current_state() -> StringName:
	return playback.get_current_node()


## Hips displacement of a root-motion clip in metres, in this node's space (Mixamo +Z flipped to -Z).
func clip_displacement(clip: String) -> Vector3:
	var d: Vector3 = AnimLib.displacement.get(clip, Vector3.ZERO) * motion_scale
	return Vector3(-d.x, d.y, -d.z)


## Average hips height of a clip in metres for this character.
func clip_hip_height(clip: String) -> float:
	return AnimLib.hip_height.get(clip, 0.9) * motion_scale


func clip_yaw(clip: String) -> float:
	return AnimLib.yaw_change.get(clip, 0.0)


func clip_length(clip: String) -> float:
	var a := anim_player.get_animation(clip)
	return a.length if a else 0.0


## Left-hand support grip: a TwoBoneIK3D on the left arm reaching for `target` (e.g. a marker on a pistol).
func install_hand_ik(target: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = "LeftHandIK"
	skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "LeftUpperArm")
	ik.set_middle_bone_name(0, "LeftLowerArm")
	ik.set_end_bone_name(0, "LeftHand")
	ik.set_target_node(0, ik.get_path_to(target))
	var pole := Marker3D.new()
	pole.name = "ElbowPole"
	target.add_child(pole)
	pole.position = Vector3(-0.35, -0.45, 0.25)  # elbow down and out, like a two-handed grip
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 0.0
	return ik


func bone_global(bone: String) -> Transform3D:
	var i := skeleton.find_bone(bone)
	return skeleton.global_transform * skeleton.get_bone_global_pose(i) if i >= 0 else global_transform
