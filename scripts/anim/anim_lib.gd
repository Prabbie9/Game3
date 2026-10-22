class_name AnimLib
extends RefCounted
## Builds the single humanoid AnimationLibrary shared by every character.
## Clips are Mixamo FBX files retargeted at import time to SkeletonProfileHumanoid ("GeneralSkeleton").
## Locomotion clips are converted to in-place and their native travel velocity is recorded, so gameplay
## speeds and blend-space positions come from the animation itself (no foot sliding).

const SRC := "res://assets/source/mixamo/animations/%s.fbx"
const HIPS := "%GeneralSkeleton:Hips"

enum Root { KEEP, IN_PLACE, NO_RISE }

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
}

## Sub-ranges of clips used by the state machine: name -> [start_offset, length] (seconds)
const WINDOWS := {
	"jump": [0.62, 0.5],
	"jump_run": [0.55, 0.45],
	"land": [0.22, 0.75],
}

static var _lib: AnimationLibrary
## Native travel velocity of each in-place clip in normalized skeleton units / s (multiply by Skeleton3D.motion_scale).
static var velocity := {}
## Total hips displacement of KEEP clips (normalized units), used to align car entry/exit.
static var displacement := {}
## Yaw change (radians) of the hips over KEEP clips.
static var yaw_change := {}


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
		Root.NO_RISE:
			# physics owns vertical motion: keep crouch/compression, drop any rise above the start height
			for i in n:
				var p: Vector3 = anim.track_get_key_value(t, i)
				anim.track_set_key_value(t, i, Vector3(0.0, minf(p.y, p0.y), 0.0))
