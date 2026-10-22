class_name AnimLib
extends RefCounted
## Builds the single humanoid AnimationLibrary shared by every character.
## Clips are Mixamo FBX files retargeted at import time to SkeletonProfileHumanoid ("GeneralSkeleton").
## Locomotion clips are converted to in-place and their native travel velocity is recorded, so gameplay
## speeds and blend-space positions come from the animation itself (no foot sliding).

const SRC := "res://assets/source/mixamo/animations/%s.fbx"
const HIPS := "%GeneralSkeleton:Hips"

enum Root { KEEP, IN_PLACE, NO_RISE, EXTRACT, EXTRACT_Y }

## logical name -> [source file (snake_case), loop, root handling]
const CLIPS := {
	"idle": ["breathing_idle", true, Root.IN_PLACE],
	"idle_alt": ["standing_idle", true, Root.IN_PLACE],
	"walk": ["male_standard_walk", true, Root.IN_PLACE],
	"run": ["standard_running", true, Root.IN_PLACE],
	"jog": ["jogging", true, Root.IN_PLACE],
	"sprint": ["running_fast", true, Root.IN_PLACE],
	"jump": ["jump_up", false, Root.NO_RISE],
	"jump_run": ["jumping_while_running", false, Root.NO_RISE],
	"fall": ["mid_air_falling_idle", true, Root.NO_RISE],
	"land": ["landing_from_falling_idle", false, Root.NO_RISE],
	"pistol_idle": ["idle_with_aimed_pistol", true, Root.IN_PLACE],
	"pistol_fwd": ["walking_with_an_aimed_pistol", true, Root.IN_PLACE],
	"pistol_back": ["walking_backward_with_an_aimed_pistol", true, Root.IN_PLACE],
	"pistol_left": ["strafe_left_with_an_aimed_pistol", true, Root.IN_PLACE],
	"pistol_right": ["strafe_right_with_an_aimed_pistol", true, Root.IN_PLACE],
	"pistol_run": ["running_with_aimed_pistol", true, Root.IN_PLACE],
	"car_enter": ["entering_into_the_driverside_of_a_car", false, Root.KEEP],
	"car_exit": ["exiting_out_of_the_driverside_of_a_car", false, Root.KEEP],
	"drive": ["male_driving_a_car", true, Root.IN_PLACE],
	# Milestone 2
	"crouch_idle": ["crouch_idle_1", true, Root.IN_PLACE],
	"crouch_walk": ["crouched_walk", true, Root.IN_PLACE],
	"get_up_back": ["getting_up_from_back", false, Root.EXTRACT],
	"get_up_front": ["getting_up_from_stomach", false, Root.EXTRACT],
	"vault": ["male_jumping_over_an_obstacle_with_1_hand_planted", false, Root.EXTRACT],
	"vault_high": ["male_jumping_over_an_obstacle_with_2_hands_planted", false, Root.EXTRACT],
	"jump_hang": ["jump_to_a_braced_hang_from_standing_idle", false, Root.EXTRACT],
	"climb": ["climb_wall_from_braced_hang_to_crouch", false, Root.EXTRACT_Y],
	"swim": ["swimming_underwater", true, Root.IN_PLACE],
	"swim_idle": ["floating", true, Root.IN_PLACE],
	"cover_idle": ["standing_cover_against_object", true, Root.IN_PLACE],
	"cover_left": ["left_standing_sneak_behind_cover", true, Root.IN_PLACE],
	"cover_right": ["right_standing_sneak_behind_cover", true, Root.IN_PLACE],
	"cover_low_idle": ["crouched_for_cover_against_object", true, Root.IN_PLACE],
	"cover_low_left": ["crouched_cover_sneaking_left", true, Root.IN_PLACE],
	"cover_low_right": ["crouched_cover_sneaking_right", true, Root.IN_PLACE],
	"punch_jab": ["jab_punch", false, Root.IN_PLACE],
	"punch_cross": ["cross_punch", false, Root.IN_PLACE],
	"punch_hook": ["a_hook_punch", false, Root.IN_PLACE],
	"fight_idle": ["male_fight_idle_boxing_stance", true, Root.IN_PLACE],
	"turn_left": ["standing_left_turn", false, Root.EXTRACT],
	"turn_right": ["standing_right_turn", false, Root.EXTRACT],
	"turn_180": ["standing_180_left_turn", false, Root.EXTRACT],
	"run_stop": ["fast_stop_from_full_run", false, Root.EXTRACT],
	"hard_land": ["mid_air_falling_to_a_hard_landing", false, Root.NO_RISE],
	"hit_head": ["receiving_a_big_hit_from_a_right_punch", false, Root.IN_PLACE],
	"hit_body": ["receive_punch_to_the_body", false, Root.IN_PLACE],
}

## Sub-ranges of clips used by the state machine: name -> [start_offset, length] (seconds)
const WINDOWS := {
	"jump": [0.62, 0.5],
	"jump_run": [0.55, 0.45],
	"land": [0.22, 0.75],
	"get_up_back": [3.6, 2.5],
	"get_up_front": [1.8, 4.0],
	"vault": [0.3, 0.87],
	"vault_high": [0.12, 1.08],
	"jump_hang": [0.0, 1.0],
	"punch_hook": [0.0, 1.0],
	"hard_land": [1.35, 1.1],
	"run_stop": [0.0, 0.9],
}

## Traversal clips: the obstacle/ledge height the clip was authored for (metres for the player character, top
## surface under the planted hands; 0 = use the clip's extracted ledge), and how the runtime height difference
## is blended in (action seconds): ["ramp", t0, t1] eases the offset in between t0 and t1 and keeps it;
## ["bump", t0, peak, t1] rises to the full offset at the hand plant and back to zero for the landing;
## ["const"] applies it from the start.
const TRAVERSE := {
	"vault": [0.84, "bump", 0.0, 0.24, 0.55],
	"vault_high": [0.92, "bump", 0.0, 0.4, 0.75],
	"jump_hang": [2.08, "ramp", 0.28, 0.48],
	"climb": [0.0, "const"],
}
## EXTRACT_Y clips whose end pose isn't a standing one: hips height above the ledge at the end (normalized units).
const END_HIPS := {"climb": 0.74}
## Clips whose root keeps its facing: hips twist during vaults/climbs is part of the pose, not a turn.
const NO_YAW := ["vault", "vault_high", "jump_hang", "climb"]

## Root paths of EXTRACT clips: clip -> {"pos": PackedVector3Array, "yaw": PackedFloat32Array} sampled at PATH_HZ
## (normalized skeleton units, Mixamo axes: +Z forward). Player roots follow these instead of the hips.
const PATH_HZ := 30.0
static var paths := {}

static var _lib: AnimationLibrary
## Native travel velocity of each in-place clip in normalized skeleton units / s (multiply by Skeleton3D.motion_scale).
static var velocity := {}
## Total hips displacement of KEEP clips (normalized units), used to align car entry/exit.
static var displacement := {}
## Yaw change (radians) of the hips over KEEP clips.
static var yaw_change := {}
## Average hips height of each clip (normalized units).
static var hip_height := {}


static func get_library() -> AnimationLibrary:
	if _lib:
		return _lib
	_lib = AnimationLibrary.new()
	for clip_name: String in CLIPS:
		var c: Array = CLIPS[clip_name]
		var src = load(SRC % c[0])
		if not src is AnimationLibrary or src.get_animation_list().is_empty():
			push_error("AnimLib: missing clip %s (%s)" % [clip_name, c[0]])
			continue
		var anim: Animation = src.get_animation(src.get_animation_list()[0]).duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR if c[1] else Animation.LOOP_NONE
		_process_root(clip_name, anim, c[2])
		_lib.add_animation(clip_name, anim)
	return _lib


## Native speed in m/s of a clip for a skeleton with the given motion scale.
static func speed_of(clip_name: String, motion_scale: float) -> float:
	var v: Vector3 = velocity.get(clip_name, Vector3.ZERO)
	return Vector2(v.x, v.z).length() * motion_scale


static func _process_root(clip_name: String, anim: Animation, mode: int) -> void:
	var t := anim.find_track(NodePath(HIPS), Animation.TYPE_POSITION_3D)
	if t < 0:
		return
	var n := anim.track_get_key_count(t)
	if n < 2:
		return
	var p0: Vector3 = anim.track_get_key_value(t, 0)
	var p1: Vector3 = anim.track_get_key_value(t, n - 1)
	var t0 := anim.track_get_key_time(t, 0)
	var t1 := anim.track_get_key_time(t, n - 1)
	var span := maxf(t1 - t0, 0.001)
	var hy := 0.0
	for i in n:
		hy += (anim.track_get_key_value(t, i) as Vector3).y
	hip_height[clip_name] = hy / n
	match mode:
		Root.KEEP:
			displacement[clip_name] = p1 - p0
			var r := anim.find_track(NodePath(HIPS), Animation.TYPE_ROTATION_3D)
			if r >= 0 and anim.track_get_key_count(r) > 1:
				var q0: Quaternion = anim.track_get_key_value(r, 0)
				var q1: Quaternion = anim.track_get_key_value(r, anim.track_get_key_count(r) - 1)
				var f := Basis(q1 * q0.inverse()) * Vector3(0, 0, 1)
				yaw_change[clip_name] = atan2(f.x, f.z)
		Root.IN_PLACE:
			var drift := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
			velocity[clip_name] = drift / span
			for i in n:
				var k: float = (anim.track_get_key_time(t, i) - t0) / span
				var p: Vector3 = anim.track_get_key_value(t, i)
				# remove linear travel and the start offset, keep sway/bob around the rest position
				anim.track_set_key_value(t, i, Vector3(p.x - p0.x - drift.x * k, p.y, p.z - p0.z - drift.z * k))
		Root.EXTRACT, Root.EXTRACT_Y:
			_extract_root(clip_name, anim, t, mode == Root.EXTRACT_Y)
		Root.NO_RISE:
			# physics owns vertical motion: keep crouch/compression, drop any rise above the start height
			for i in n:
				var p: Vector3 = anim.track_get_key_value(t, i)
				anim.track_set_key_value(t, i, Vector3(0.0, minf(p.y, p0.y), 0.0))


## Moves the hips' travel (XZ, and for EXTRACT_Y a vertical ramp) and yaw onto a root path, leaving the hips
## track relative to that root. Vertical: the root rises in proportion to the hips' rise, by the clip's ledge
## height (end hips height minus standing hips height), so it can be scaled to any obstacle at runtime.
static func _extract_root(clip_name: String, anim: Animation, pt: int, with_y: bool) -> void:
	var rt := anim.find_track(NodePath(HIPS), Animation.TYPE_ROTATION_3D)
	var length := anim.length
	var p0 := anim.position_track_interpolate(pt, 0.0)
	var p_end := anim.position_track_interpolate(pt, length)
	var q0 := anim.rotation_track_interpolate(rt, 0.0) if rt >= 0 else Quaternion()
	var stand_y: float = END_HIPS.get(clip_name, hip_height.get("idle", 0.98))
	var ledge := maxf(p_end.y - stand_y, 0.0) if with_y else 0.0
	var rise := p_end.y - p0.y
	var n := int(ceil(length * PATH_HZ)) + 1
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	pos.resize(n)
	yaw.resize(n)
	for i in n:
		var t := minf(i / PATH_HZ, length)
		var p := anim.position_track_interpolate(pt, t)
		var y := 0.0
		if with_y and absf(rise) > 0.01:
			y = clampf((p.y - p0.y) / rise, 0.0, 1.0) * ledge
		pos[i] = Vector3(p.x - p0.x, y, p.z - p0.z)
		if rt >= 0 and not clip_name in NO_YAW:
			var f := Basis(anim.rotation_track_interpolate(rt, t) * q0.inverse()) * Vector3(0, 0, 1)
			yaw[i] = atan2(f.x, f.z)
	# unwrap yaw so 180° turns interpolate continuously
	for i in range(1, n):
		while yaw[i] - yaw[i - 1] > PI:
			yaw[i] -= TAU
		while yaw[i] - yaw[i - 1] < -PI:
			yaw[i] += TAU
	paths[clip_name] = {"pos": pos, "yaw": yaw, "ledge": ledge}
	# rewrite hips keys relative to the moving/turning root
	for i in anim.track_get_key_count(pt):
		var t := anim.track_get_key_time(pt, i)
		var r := sample_path(clip_name, t)
		var p: Vector3 = anim.track_get_key_value(pt, i)
		var local: Vector3 = Basis(Vector3.UP, -float(r[1])) * (p - (r[0] as Vector3))
		anim.track_set_key_value(pt, i, local)
	if rt >= 0:
		for i in anim.track_get_key_count(rt):
			var t := anim.track_get_key_time(rt, i)
			var r := sample_path(clip_name, t)
			var q: Quaternion = anim.track_get_key_value(rt, i)
			anim.track_set_key_value(rt, i, Quaternion(Vector3.UP, -float(r[1])) * q)


## [position (normalized, Mixamo axes), yaw] of a clip's root path at time t.
static func sample_path(clip_name: String, t: float) -> Array:
	var d: Dictionary = paths[clip_name]
	var pos: PackedVector3Array = d.pos
	var yaw: PackedFloat32Array = d.yaw
	var f := clampf(t * PATH_HZ, 0.0, pos.size() - 1.0)
	var i := int(f)
	var j := mini(i + 1, pos.size() - 1)
	var k := f - i
	return [pos[i].lerp(pos[j], k), lerpf(yaw[i], yaw[j], k)]
