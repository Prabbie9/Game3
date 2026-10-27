extends Node
## Carjacking and passenger-side entry in the real world: the player pulls a waiting driver out and drives off,
## the driver runs away; entering an empty car through the passenger door ends behind the wheel. Every move is
## smooth: the hips of the player and of the driver never jump between frames (no snaps between clips).
## godot --headless --path . res://tests/runner.tscn -- res://tests/carjack_check.gd

var fails := 0
## hips trackers: name -> {visual, last, worst, at}
var _track := {}
const MAX_SPEED := 7.0   # m/s of hips travel between two physics ticks: beyond any of these clips (a snap is 15+)


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _hips(v: HumanoidVisual) -> Vector3:
	var sk := v.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin


func _follow(name: String, v: HumanoidVisual) -> void:
	_track[name] = {"visual": v, "last": _hips(v), "worst": 0.0, "at": 0.0, "t": 0.0, "where": ""}


func _worst(name: String) -> String:
	var e: Dictionary = _track[name]
	_track.erase(name)
	_check(float(e.worst) < MAX_SPEED, "%s: smooth, the hips never jump (fastest %.1f m/s, at %.2f s%s)" % [name, e.worst, e.at, e.where])
	return name


func _physics_process(delta: float) -> void:
	for name: String in _track:
		var e: Dictionary = _track[name]
		if not is_instance_valid(e.visual):
			continue
		var h := _hips(e.visual)
		e.t = float(e.t) + delta
		var speed := h.distance_to(e.last) / delta
		if speed > float(e.worst):
			e.worst = speed
			e.at = e.t
			var pl := Game.player as Player
			e.where = "" if speed < MAX_SPEED else ", %s -> %s; player state %d at %s, clip %s, t %.2f" % [e.last, h, pl.state, pl.global_position, pl.visual.current_state(), pl._seq_time]
		e.last = h


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame


func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
	world.traffic.budget = 0   # nothing passing by to knock the player over at a door
	Game.controls_enabled = false
	await _secs(1.0)
	var p: Player = world.player
	# a car with someone waiting at the wheel, on the street by the start
	var v := Vehicle.new()
	v.model = "sedan"
	v.position = Vector3(60.0, 0.6, -5.2)
	v.rotation.y = PI * 0.5
	world.add_child(v)
	await _secs(1.0)
	var npc := NPCDriver.seat_in(v, NPCDriver.CHARACTERS[0])
	await _secs(1.0)
	_check(v.driver == npc and npc.state == NPCDriver.State.SEATED, "driver waits at the wheel")
	p.global_position = v.driver_door_position() + Vector3(0, 0.1, 0)
	await _secs(0.5)
	var near := p._nearest_vehicle()
	_check(near == v and p._enter_side == 0, "the occupied car can be entered from the driver door")
	p.enter_vehicle(v)
	_follow("carjacker", p.visual)
	_follow("jacked driver", npc.visual)
	_check(p._enter_clip == "carjack", "uses the carjack clip")
	var t := 0.0
	while t < 12.0 and p.state != Player.State.DRIVING:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(p.state == Player.State.DRIVING and v.driver == p, "player ends up driving (%.1f s)" % t)
	await _secs(2.5)
	_worst("carjacker")
	_worst("jacked driver")
	var sit := v.global_transform.affine_inverse() * _hips(p.visual)
	var want := v.global_transform.affine_inverse() * v.seat_transform().origin
	_check(sit.distance_to(want) < 0.15, "the jacker's hips are on the seat (%.2f m off)" % sit.distance_to(want))
	_check(is_instance_valid(npc) and npc.state == NPCDriver.State.FLEEING, "the driver runs off")
	if is_instance_valid(npc):
		_check(npc.global_position.distance_to(v.global_position) > 3.0, "away from the car (%.1f m)" % npc.global_position.distance_to(v.global_position))
	p.exit_vehicle()
	_follow("getting out", p.visual)
	t = 0.0
	while t < 8.0 and p.state != Player.State.ON_FOOT:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(p.state == Player.State.ON_FOOT, "gets out again")
	await _secs(0.5)
	_worst("getting out")
	var gy := v.ground_height_at(p.global_position)
	_check(absf(p.global_position.y - gy) < 0.2, "standing on the road (%.2f above it)" % (p.global_position.y - gy))
	# passenger door of an empty car
	var c := Vehicle.new()
	c.model = "hatchback"
	c.position = Vector3(60.0, 0.6, 5.2)
	c.rotation.y = -PI * 0.5
	world.add_child(c)
	await _secs(1.5)
	p.global_position = c.passenger_door_position() + Vector3(0, 0.1, 0)
	await _secs(0.5)
	var n2 := p._nearest_vehicle()
	_check(n2 == c and p._enter_side == 1, "picks the passenger door when standing at it")
	p.enter_vehicle(c)
	_follow("passenger-side entry", p.visual)
	_check(p._enter_clip == "car_enter_r", "mirrored entry clip")
	t = 0.0
	while t < 12.0 and p.state != Player.State.DRIVING:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(p.state == Player.State.DRIVING and c.driver == p, "slides across and takes the wheel (%.1f s)" % t)
	await _secs(1.0)
	_worst("passenger-side entry")
	# and in an empty car through the driver's door, in a tall cab
	p.exit_vehicle()
	t = 0.0
	while t < 8.0 and p.state != Player.State.ON_FOOT:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var tk := Vehicle.new()
	tk.model = "boxtruck"
	tk.position = Vector3(40.0, 0.6, -5.2)
	tk.rotation.y = PI * 0.5
	world.add_child(tk)
	await _secs(1.5)
	p.global_position = tk.driver_door_position() + Vector3(0, 0.1, 0)
	await _secs(0.5)
	p._enter_side = 0
	p.enter_vehicle(tk)
	_follow("climbing into a box truck", p.visual)
	t = 0.0
	while t < 12.0 and p.state != Player.State.DRIVING:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await _secs(1.0)
	_worst("climbing into a box truck")
	p.exit_vehicle()
	_follow("climbing down from a box truck", p.visual)
	t = 0.0
	while t < 8.0 and p.state != Player.State.ON_FOOT:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await _secs(0.5)
	_worst("climbing down from a box truck")
	p.debug_seat_in(c)
	await _secs(0.5)
	var hips := p.global_transform.origin
	var seat := c.global_transform.affine_inverse() * hips
	_check(seat.x < 0.0, "ends on the driver's side (x %.2f)" % seat.x)
	print("CARJACK CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
