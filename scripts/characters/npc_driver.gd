class_name NPCDriver
extends Node3D
## Someone sitting at the wheel of an idling car. When carjacked they are pulled out (Mixamo "Pulled Out Of
## Pilot Seat", synced with the jacker's clip), then run off and disappear once out of sight. Population and
## traffic AI (Milestone 6) build on this; for now drivers wait in parked cars with the engine running.

enum State { SEATED, PULLED, FLEEING }

const CHARACTERS := ["ch02_nonpbr", "ch21_nonpbr", "ch33_nonpbr"]
const RUN := 4.4

var vehicle: Vehicle
var state := State.SEATED
var visual: HumanoidVisual
var _t := 0.0
var _end := Transform3D()
var _flee_dir := Vector3.FORWARD


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
	var seat := global_transform
	var parent := get_parent()
	parent.remove_child(self)
	vehicle.get_parent().add_child(self)
	global_transform = seat
	visual.travel("jacked")
	var d := visual.clip_displacement("jacked")
	var turn := visual.clip_yaw("jacked")
	var end_basis := seat.basis * Basis(Vector3.UP, turn)
	_end = Transform3D(end_basis, seat.origin + seat.basis * Vector3(d.x, 0, d.z))
	_end.origin.y = vehicle.ground_height_at(_end.origin)
	var away := _end.origin - from.global_position
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
			if _t >= visual.clip_length("jacked") - 0.05:
				global_transform = _end
				state = State.FLEEING
				_t = 0.0
				visual.jump_to("ground")
		State.FLEEING:
			# run away from the jacker, following the ground, and vanish once far
			global_basis = Basis.looking_at(_flee_dir, Vector3.UP) if _flee_dir.length() > 0.1 else global_basis
			global_position += _flee_dir * RUN * delta
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), global_position + Vector3(0, -3, 0), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit:
				global_position.y = hit.position.y
			visual.set_locomotion(RUN)
			if _t > 9.0:
				queue_free()
