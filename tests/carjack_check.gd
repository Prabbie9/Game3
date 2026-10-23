extends Node
## Carjacking and passenger-side entry in the real world: the player pulls a waiting driver out and drives off,
## the driver runs away; entering an empty car through the passenger door ends behind the wheel.
## godot --headless --path . res://tests/runner.tscn -- res://tests/carjack_check.gd

var fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame


func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
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
	_check(p._enter_clip == "carjack", "uses the carjack clip")
	var t := 0.0
	while t < 12.0 and p.state != Player.State.DRIVING:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(p.state == Player.State.DRIVING and v.driver == p, "player ends up driving (%.1f s)" % t)
	await _secs(2.5)
	_check(is_instance_valid(npc) and npc.state == NPCDriver.State.FLEEING, "the driver runs off")
	if is_instance_valid(npc):
		_check(npc.global_position.distance_to(v.global_position) > 3.0, "away from the car (%.1f m)" % npc.global_position.distance_to(v.global_position))
	p.exit_vehicle()
	t = 0.0
	while t < 8.0 and p.state != Player.State.ON_FOOT:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(p.state == Player.State.ON_FOOT, "gets out again")
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
	_check(p._enter_clip == "car_enter_r", "mirrored entry clip")
	t = 0.0
	while t < 12.0 and p.state != Player.State.DRIVING:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(p.state == Player.State.DRIVING and c.driver == p, "slides across and takes the wheel (%.1f s)" % t)
	var hips := p.global_transform.origin
	var seat := c.global_transform.affine_inverse() * hips
	_check(seat.x < 0.0, "ends on the driver's side (x %.2f)" % seat.x)
	print("CARJACK CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
