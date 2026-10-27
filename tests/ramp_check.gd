extends Node
## Stunt ramps: they're where the map says, a car driven at the quay ramp flies across the gap, and you can walk
## up a beach ramp. godot --headless --path . res://tests/runner.tscn -- res://tests/ramp_check.gd

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	_run.call_deferred()


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame


func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.traffic.budget = 0
	world.population.enabled = false
	world.wanted.process_mode = Node.PROCESS_MODE_DISABLED
	Game.controls_enabled = true
	await _secs(1.0)
	var ramps := get_tree().get_nodes_in_group("stunt_ramps")
	_check(ramps.size() == World.RAMPS.size(), "%d stunt ramps in the world" % ramps.size())
	var d := WorldData.get_data()
	for r: StuntRamp in ramps:
		var g := d.height_at(r.global_position.x, r.global_position.z)
		if absf(r.global_position.y - g) > 0.2:
			_check(false, "ramp at %s sits on the ground (ground %.2f)" % [r.global_position, g])
	# the quay gap jump: run up from the west, fly off the launch ramp, land beyond the far one's top
	var p := world.player
	var start := Vector3(205.0, 0.0, 834.0)
	world.warm_up(start)
	p._respawn(Transform3D(Basis.IDENTITY, start + Vector3(0, 1, 6)), "")
	await _secs(2.0)
	var car := Vehicle.new()
	car.model = "sport"
	world.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(start.x, d.height_at(start.x, start.z) + 0.7, start.z))
	await _secs(1.0)
	p.debug_seat_in(car)
	car.set_driver_input_enabled(false)
	car.ai_drive = true
	car.ai_throttle = 1.0
	var top := -INF
	var air := 0.0
	var t := 0.0
	while t < 12.0 and car.global_position.x < 330.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var under := car.global_position.y - d.height_at(car.global_position.x, car.global_position.z)
		top = maxf(top, under)
		if under > 3.0:
			air += 1.0 / 60.0
	car.ai_throttle = 0.0
	car.ai_brake = 1.0
	await _secs(2.0)
	_check(top > 3.5 and air > 0.4, "the car flies off the quay ramp (%.1f m up, %.1f s in the air)" % [top, air])
	_check(car.global_position.x > 318.0 and car.global_basis.y.y > 0.7, "and comes down past the far ramp, wheels down (x %.0f, upright %.2f)" % [car.global_position.x, car.global_basis.y.y])
	# on foot up a beach ramp
	var r0: StuntRamp = ramps[0]
	var up := r0.global_basis.z   # the low end is at +Z
	var foot := r0.global_position + up * (r0.length * 0.5 + 3.0)
	world.warm_up(foot)
	p._respawn(Transform3D(Basis(Vector3.UP, r0.rotation.y), Vector3(foot.x, d.height_at(foot.x, foot.z) + 0.3, foot.z)), "")
	p.cam.yaw = r0.rotation.y
	await _secs(2.0)
	Input.action_press("move_forward")
	var best := 0.0
	for i in 300:
		await get_tree().physics_frame
		best = maxf(best, p.global_position.y - r0.global_position.y)
	Input.action_release("move_forward")
	_check(best > r0.height * 0.8, "you can walk up a ramp (%.1f m of %.1f)" % [best, r0.height])
	print("RAMP CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
