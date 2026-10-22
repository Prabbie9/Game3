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
	playback = tree.get("parameters/playback")
	tree.animation_finished.connect(func(a: StringName): action_finished.emit(a))


func _link(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float, at_end := false) -> void:
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


func clip_yaw(clip: String) -> float:
	return AnimLib.yaw_change.get(clip, 0.0)


func clip_length(clip: String) -> float:
	var a := anim_player.get_animation(clip)
	return a.length if a else 0.0


func bone_global(bone: String) -> Transform3D:
	var i := skeleton.find_bone(bone)
	return skeleton.global_transform * skeleton.get_bone_global_pose(i) if i >= 0 else global_transform
