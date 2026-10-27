class_name NPCDriver
extends Node3D
## Someone sitting at the wheel of an idling car. When carjacked they are pulled out (Mixamo "Pulled Out Of
## Pilot Seat", synced with the jacker's clip) and, while still on their feet, break into a run and disappear
## once out of sight. Population and
## traffic AI (Milestone 6) build on this; for now drivers wait in parked cars with the engine running.

enum State { SEATED, PULLED, FLEEING }

const CHARACTERS := ["ch02_nonpbr", "ch21_nonpbr", "ch33_nonpbr"]
const RUN := 4.4

var vehicle: Vehicle
var state := State.SEATED
var visual: HumanoidVisual
var _t := 0.0
var _flee_dir := Vector3.FORWARD
# pulled out: the clip's root (hips on the seat at the start), how far it drops to the road, when the driver is
# up on their feet (the cut into the run), and the hand-over from there
var _from := Transform3D()
var _root := Transform3D()
var _lift := 0.0
var _cut := 1.0
var _cut_from := Transform3D()
var _cut_hips := Vector3.ZERO
const CUT_BLEND := 0.3


static var _scenes := {}   # character -> PackedScene, kept so the loader cache never drops them


## Start loading the NPC characters on background threads (they take ~1 s each to load from disk).
static func preload_characters() -> void:
	for c: String in CHARACTERS + Population.CHARACTERS.keys():
		var path := HumanoidVisual.CHAR_PATH % c
		if not _scenes.has(c) and ResourceLoader.load_threaded_request(path) == OK:
			_scenes[c] = null


## True once a character is in memory (spawning before that would stall the frame).
static func is_ready(character: String) -> bool:
	if _scenes.get(character) != null:
		return true
	var path := HumanoidVisual.CHAR_PATH % character
	if not _scenes.has(character):
		return false
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		_scenes[character] = ResourceLoader.load_threaded_get(path)
		return true
	if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(path)  # try again
	return false


static func release() -> void:
	_scenes.clear()


static func seat_in(v: Vehicle, character: String) -> NPCDriver:
	var n := NPCDriver.new()
	n.vehicle = v
	n.visual = HumanoidVisual.new()
	n.visual.character_file = character
	if Population.CHARACTERS.get(character, false):
		n.visual.clip_swap = {"walk": "f_walk", "idle": "f_idle", "run": "f_run"}
	n.add_child(n.visual)
	v.add_child(n)
	if v.model in ["police", "heli"] and n.visual.skeleton:
		Uniform.dress(n.visual, "police")
	n.visual.jump_to.call_deferred("drive")
	n._place.call_deferred()
	v.reserve(n)
	v.set_driver(n)
	v.set_driver_input_enabled(false)
	return n


func _place() -> void:
	if state != State.SEATED or not is_instance_valid(vehicle):
		return
	var s := vehicle.seat_transform()
	s.origin -= s.basis.y * visual.clip_hip_height("drive")
	global_transform = s


## The jacker has started pulling: play the pulled-out clip from the seat, then flee.
func pull_out(from: Node3D) -> void:
	state = State.PULLED
	_t = 0.0
	var at := global_transform
	var parent := get_parent()
	parent.remove_child(self)
	vehicle.get_parent().add_child(self)
	global_transform = at
	visual.travel("jacked")
	# hips stay on the seat as the clip takes over from the seated pose; then the clip carries the body out and
	# the root drops by however much this seat is higher than the one the clip was made for
	var seat := vehicle.seat_transform()
	_from = at
	_root = Transform3D(seat.basis, seat.origin - seat.basis * visual.clip_hips("jacked", false))
	_cut = visual.clip_peak_time("jacked", 0.35, 0.8)
	var up := _root * visual.clip_hips_at("jacked", _cut)
	_lift = vehicle.ground_height_at(up) - _root.origin.y
	var away := up - from.global_position
	away.y = 0
	_flee_dir = away.normalized() if away.length() > 0.1 else -vehicle.global_basis.x
	vehicle = null


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		State.SEATED:
			if is_instance_valid(vehicle):
				_place()
		State.PULLED:
			var r := _root
			r.origin.y += _lift * smoothstep(0.25 * _cut, _cut, _t)
			global_transform = _from.interpolate_with(r, clampf(_t / 0.15, 0.0, 1.0))
			if _t >= _cut:
				# up on their feet: into the run, turning about the hips as the poses crossfade
				_cut_from = r
				_cut_hips = visual.clip_hips_at("jacked", _t)
				visual.set_locomotion(RUN)
				visual.travel("ground")
				state = State.FLEEING
				_t = 0.0
		State.FLEEING when _t < CUT_BLEND:
			# the pulled-out clip plays on under the crossfade: keep its hips offset (fading) and carry the hips off
			# from where they were at the cut, speeding up to a run
			var faded := _t
			if visual.current_state() == &"ground":
				faded = maxf(faded, visual.playback.get_current_play_position())
			var k := minf(faded / CUT_BLEND, 1.0)
			var hips := _cut_from * _cut_hips
			var face := Basis.looking_at(_flee_dir, Vector3.UP)
			var b := _cut_from.basis.slerp(face, k)
			var h := visual.clip_hips_at("jacked", _cut + _t) * (1.0 - k)
			var run := _flee_dir * RUN * _t * _t / (2.0 * CUT_BLEND)   # speeding up to a run over the crossfade
			global_transform = Transform3D(b, Vector3(hips.x, _cut_from.origin.y, hips.z) + run - b * Vector3(h.x, 0, h.z))
			visual.set_locomotion(RUN)
		State.FLEEING:
			# run away from the jacker, following the ground, and vanish once far
			global_basis = Basis.looking_at(_flee_dir, Vector3.UP) if _flee_dir.length() > 0.1 else global_basis
			global_position += _flee_dir * RUN * delta
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), global_position + Vector3(0, -3, 0), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit:
				global_position.y = lerpf(global_position.y, hit.position.y, minf(1.0, delta * 14.0))   # up a kerb in a stride, not a pop
			visual.set_locomotion(RUN)
			if _t > 9.0:
				queue_free()
