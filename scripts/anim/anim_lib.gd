class_name AnimLib
extends RefCounted
## Builds the single humanoid AnimationLibrary shared by every character.
## Clips are Mixamo FBX files retargeted at import time to SkeletonProfileHumanoid ("GeneralSkeleton").
## Locomotion clips are converted to in-place and their native travel velocity is recorded, so gameplay
## speeds and blend-space positions come from the animation itself (no foot sliding).

const SRC := "res://assets/source/mixamo/animations/%s.fbx"
## Quaternius Universal Animation Library (CC0, retargeted to the same humanoid skeleton): sources "ual:Clip".
const UAL := "res://assets/source/quaternius/ual_standard.glb"
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
	# surface stroke with the head up, and treading water (the Mixamo library has neither)
	"swim": ["ual:Swim_Fwd", true, Root.IN_PLACE],
	"swim_idle": ["ual:Swim_Idle", true, Root.IN_PLACE],
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
	# Milestone 4
	"pilot": ["pilot_flies_helicopter", true, Root.IN_PLACE],
	"passenger": ["passenger_jostled_while_sitting_in_a_vehicle", true, Root.IN_PLACE],
	"carjack": ["pull_pilot_out_of_seat_and_take_the_controls", false, Root.KEEP],
	"jacked": ["pulled_out_of_pilot_seat", false, Root.KEEP],
	"thrown": ["being_thrown_to_the_side", false, Root.EXTRACT],
	# Milestone 5: long guns (aim strafe set + relaxed carry), reloads, throws, melee weapons, hits
	"rifle_idle": ["rifle_standing_aiming_idle", true, Root.IN_PLACE],
	"rifle_fwd": ["rifle_walk_forward", true, Root.IN_PLACE],
	"rifle_back": ["rifle_walk_backward", true, Root.IN_PLACE],
	"rifle_left": ["rifle_walk_left", true, Root.IN_PLACE],
	"rifle_right": ["rifle_walk_right", true, Root.IN_PLACE],
	"rifle_run": ["running_with_rifle_aimed", true, Root.IN_PLACE],
	"rifle_run_back": ["rifle_run_backward", true, Root.IN_PLACE],
	"rifle_hold": ["rifle_standing_idle", true, Root.IN_PLACE],
	"rifle_walk": ["walking_with_rifle_at_waist_level", true, Root.IN_PLACE],
	"rifle_sprint": ["rifle_sprint_forward", true, Root.IN_PLACE],
	"rifle_reload": ["reloading_rifle_while_standing", false, Root.IN_PLACE],
	"pistol_reload": ["gun_reload_while_walking", false, Root.IN_PLACE],
	"throw": ["throwing_an_object_from_a_standard_pose", false, Root.IN_PLACE],
	"knife_stab": ["male_knife_stab_with_the_rear_hand_and_fore_grip", false, Root.IN_PLACE],
	"knife_stab2": ["male_knife_stab_with_lead_hand_and_fore_grip", false, Root.IN_PLACE],
	"bat_swing": ["two_handed_heavy_weapon_swing", false, Root.IN_PLACE],
	"bat_swing2": ["baseball_swinging_strike", false, Root.IN_PLACE],
	"hit_small": ["small_hit_reaction_from_the_front", false, Root.IN_PLACE],
	"hit_react": ["hit_reaction", false, Root.IN_PLACE],
	"death_back": ["death_falling_backwards", false, Root.EXTRACT],
	"death_head": ["dying_shot_to_the_head_falling_on_two_knees", false, Root.EXTRACT],
	# Milestone 6: street life
	"f_walk": ["female_walk_forward", true, Root.IN_PLACE],
	"f_idle": ["female_standing_idle", true, Root.IN_PLACE],
	"f_run": ["female_run_forward", true, Root.IN_PLACE],
	"phone_m": ["male_talking_on_the_cell_phone", true, Root.IN_PLACE],
	"phone_f": ["female_standing_talking_on_phone", true, Root.IN_PLACE],
	"texting": ["texting_on_a_smart_phone_while_standing", true, Root.IN_PLACE],
	"walk_text": ["male_walking_while_texting_on_a_smartphone", true, Root.IN_PLACE],
	"smoke": ["idle_smoking", true, Root.IN_PLACE],
	"sit": ["sitting_with_breathing_idle", true, Root.IN_PLACE],
	"sit_talk": ["sitting_and_talking_to_another_person", true, Root.IN_PLACE],
	"talk": ["talking_finding_something_funny", true, Root.IN_PLACE],
	"argue": ["standing_arguing_with_another_person", true, Root.IN_PLACE],
	"terrified": ["being_terrified_while_standing", true, Root.IN_PLACE],
	"cower": ["duck_and_look_around_apprehensively", true, Root.IN_PLACE],
	"panic_run": ["clumsily_running_to_evade_a_threat", true, Root.IN_PLACE],
	"nervous": ["look_around_nervously", true, Root.IN_PLACE],
	"call_police": ["male_standing_while_talking_on_a_cell_phone", true, Root.IN_PLACE],
	"kneel": ["kneeling_idle", true, Root.IN_PLACE],
	"kneel_down": ["standing_to_kneeling_down", false, Root.IN_PLACE],
	"happy_idle": ["happy_idle_variation_1", true, Root.IN_PLACE],
}

## In-place clips authored without travel: the speed (normalized units / s) their cycle reads as.
const NATIVE_SPEED := {"swim": Vector3(0, 0, 0.47)}

## Clips played faster than authored (the Mixamo carjack takes its time settling into the seat).
const RETIME := {"carjack": 1.6, "jacked": 1.3}

## Mirror images (left/right swapped) of clips: passenger-side entry and exit from the driver-side ones.
const MIRRORS := {"car_enter_r": "car_enter", "car_exit_r": "car_exit", "carjack_r": "carjack", "jacked_r": "jacked"}

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
const NO_YAW := ["vault", "vault_high", "jump_hang", "climb", "run_stop"]

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
		var ual := String(c[0]).begins_with("ual:")
		var src = load(UAL if ual else SRC % c[0])
		var src_anim := String(c[0]).substr(4) if ual else ""
		if not src is AnimationLibrary or src.get_animation_list().is_empty() or (ual and not src.has_animation(src_anim)):
			push_error("AnimLib: missing clip %s (%s)" % [clip_name, c[0]])
			continue
		var anim: Animation = src.get_animation(src_anim if ual else src.get_animation_list()[0]).duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR if c[1] else Animation.LOOP_NONE
		if RETIME.has(clip_name):
			_retime(anim, RETIME[clip_name])
		_process_root(clip_name, anim, c[2])
		if NATIVE_SPEED.has(clip_name):
			velocity[clip_name] = NATIVE_SPEED[clip_name]
		_lib.add_animation(clip_name, anim)
	for m: String in MIRRORS:
		var src_name: String = MIRRORS[m]
		if _lib.has_animation(src_name):
			_lib.add_animation(m, _mirror(_lib.get_animation(src_name)))
			if displacement.has(src_name):
				var d: Vector3 = displacement[src_name]
				displacement[m] = Vector3(-d.x, d.y, d.z)
			if yaw_change.has(src_name):
				yaw_change[m] = -float(yaw_change[src_name])
			hip_height[m] = hip_height.get(src_name, 0.98)
	return _lib


static func _retime(a: Animation, speed: float) -> void:
	for t in a.get_track_count():
		for k in range(a.track_get_key_count(t) - 1, -1, -1):
			var value: Variant = a.track_get_key_value(t, k)
			var time := a.track_get_key_time(t, k) / speed
			a.track_remove_key(t, k)
			a.track_insert_key(t, time, value)
	a.length /= speed


## Left/right mirror of a humanoid clip (reflection across the character's YZ plane): Left*/Right* bone tracks
## swap, rotations q -> (x, -y, -z, w), positions x -> -x. Relies on the retargeted skeleton's rests being
## mirror-symmetric, which SkeletonProfileHumanoid's normalized axes are.
static func _mirror(src: Animation) -> Animation:
	var a: Animation = src.duplicate(true)
	for t in a.get_track_count():
		var path := String(a.track_get_path(t))
		var swapped := path
		if path.contains(":Left"):
			swapped = path.replace(":Left", ":Right")
		elif path.contains(":Right"):
			swapped = path.replace(":Right", ":Left")
		a.track_set_path(t, NodePath(swapped))
		var ty := a.track_get_type(t)
		for k in a.track_get_key_count(t):
			if ty == Animation.TYPE_ROTATION_3D:
				var q: Quaternion = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, Quaternion(q.x, -q.y, -q.z, q.w))
			elif ty == Animation.TYPE_POSITION_3D:
				var p: Vector3 = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, Vector3(-p.x, p.y, p.z))
	return a


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
