extends Node
## Drive check: enter a car, accelerate, steer, brake, exit — car must move, turn, stay upright, stop.
## godot --headless --path . res://tests/runner.tscn -- res://tests/drive_check.gd

var fails := 0


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %-30s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	await _phys(30)
	Game.controls_enabled = true
	var p: Player = world.player
	var v: Vehicle
	# the empty showcase compact by the start (parked with a long clear lane ahead), not a passing one in traffic
	var bd := INF
	for c in world.get_tree().get_nodes_in_group("vehicles"):
		if c.model == "compact" and c.driver == null and c.global_position.distance_to(p.global_position) < bd:
			v = c
			bd = c.global_position.distance_to(p.global_position)
	p.global_position = v.driver_door_position()
	await _phys(5)
	Input.action_press("interact")
	await _phys(2)
	Input.action_release("interact")
	await _phys(int(60 * 6.5))
	_check("entered vehicle", p.state == Player.State.DRIVING, "state %s" % Player.State.keys()[p.state])
	var start := v.global_position
	Input.action_press("accelerate")
	await _phys(60 * 3)
	var spd := v.speed_kmh()
	_check("accelerates", spd > 45.0, "%.0f km/h after 3 s, moved %.1f m" % [spd, start.distance_to(v.global_position)])
	Input.action_release("accelerate")
	Input.action_press("brake")
	var b0 := v.global_position
	var t := 0
	while v.speed_kmh() > 3.0 and t < 60 * 5:
		await _phys(1)
		t += 1
	Input.action_release("brake")
	_check("brakes to stop", v.speed_kmh() <= 3.0, "%.1f s, %.1f m from %.0f km/h" % [t / 60.0, b0.distance_to(v.global_position), spd])
	await _phys(30)
	# low-speed turn
	var yaw0 := v.rotation.y
	Input.action_press("accelerate")
	Input.action_press("steer_left")
	await _phys(90)
	Input.action_release("steer_left")
	Input.action_release("accelerate")
	var turned := absf(wrapf(v.rotation.y - yaw0, -PI, PI))
	_check("steers", turned > 0.3, "yaw change %.2f rad at %.0f km/h" % [turned, v.speed_kmh()])
	_check("upright", v.global_basis.y.dot(Vector3.UP) > 0.9, "up·Y %.2f" % v.global_basis.y.dot(Vector3.UP))
	Input.action_press("brake")
	var guard := 0
	while v.speed_kmh() > 1.5 and guard < 300:
		await _phys(1)
		guard += 1
	Input.action_release("brake")
	await _phys(20)
	var car_before := v.global_position
	Input.action_press("interact")
	await _phys(2)
	Input.action_release("interact")
	await _phys(int(60 * 7))
	_check("car stays put while exiting", car_before.distance_to(v.global_position) < 0.5, "car moved %.2f m" % car_before.distance_to(v.global_position))
	_check("exited vehicle", p.state == Player.State.ON_FOOT and p.is_on_floor(), "state %s on_floor %s" % [Player.State.keys()[p.state], p.is_on_floor()])
	var d := p.global_position.distance_to(v.global_position)
	_check("player beside car", d > 1.0 and d < 3.5, "dist %.2f m" % d)
	print("DRIVE CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)
