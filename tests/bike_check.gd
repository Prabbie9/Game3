extends Node
## Two-wheelers: parked on the side stand, upright with a rider, accelerates, leans into turns and turns, stays up
## at speed, and a crash into a wall knocks it down and throws the rider off.
## godot --headless --path . res://tests/runner.tscn -- res://tests/bike_check.gd

var fails := 0
var thrown := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame


func thrown_off(v: Vehicle, _vel: Vector3) -> void:
	thrown = true
	v.set_driver(null)


func _run() -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2000, 2, 2000)
	cs.shape = b
	sb.add_child(cs)
	sb.position.y = -1.0
	root.add_child(sb)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(40, 4, 1)
	wcs.shape = wb
	wall.add_child(wcs)
	wall.position = Vector3(0, 2, -260)
	root.add_child(wall)
	for spec: Array in [["dirtbike", 60.0], ["bicycle", 16.0]]:
		var model: String = spec[0]
		print("-- ", model)
		var v := Bike.new()
		v.model = model
		v.position = Vector3(0, 0.1, 0)
		root.add_child(v)
		await _secs(2.0)
		var roll := asin(v.global_basis.x.y)
		_check(not v.down and roll > 0.1 and roll < 0.35, "parked on its stand (lean %.2f, sleeping %s, down %s)" % [roll, v.sleeping, v.down])
		_check(v._wheels.size() == 2, "two wheels")
		var low := INF
		for w in v._wheels:
			low = minf(low, w.global_position.y - w.wheel_radius)
		_check(absf(low) < 0.06, "wheels on the ground, not sunk (wheel bottom %.3f)" % low)
		v.set_driver(self)
		await _secs(1.5)
		_check(absf(asin(v.global_basis.x.y)) < 0.08, "upright with a rider (lean %.2f)" % asin(v.global_basis.x.y))
		Input.action_press("accelerate")
		await _secs(6.0)
		var kmh := v.speed_kmh()
		_check(kmh > spec[1] and not v.down, "accelerates (%.0f km/h, down %s, lean %.2f, contacts %d)" % [kmh, v.down, asin(v.global_basis.x.y), v._wheels.filter(func(w): return w.is_in_contact()).size()])
		var yaw0 := v.rotation.y
		Input.action_press("steer_left")
		var max_lean := 0.0
		var turned := 0.0
		for i in 120:
			await get_tree().physics_frame
			max_lean = maxf(max_lean, asin(v.global_basis.x.y))
			turned += v.angular_velocity.y / 60.0
		Input.action_release("steer_left")
		_check(max_lean > 0.12, "leans into the turn (%.2f)" % max_lean)
		_check(turned > 0.5, "turns (%.2f rad)" % turned)
		await _secs(2.0)
		_check(not v.down and absf(asin(v.global_basis.x.y)) < 0.15, "straightens up (down %s, lean %.2f, yaw rate %.2f, %.0f km/h)" % [v.down, asin(v.global_basis.x.y), v.angular_velocity.y, v.speed_kmh()])
		Input.action_release("accelerate")
		# crash: point it at the wall and let it run in
		v.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -230))
		v.linear_velocity = Vector3(0, 0, -16)
		v.angular_velocity = Vector3.ZERO
		thrown = false
		Input.action_press("accelerate")
		await _secs(4.0)
		Input.action_release("accelerate")
		await _secs(2.0)
		_check(thrown, "crash throws the rider off")
		_check(v.down or absf(asin(v.global_basis.x.y)) > 0.7, "crashed bike falls over")
		v.queue_free()
		await _secs(0.2)
	print("BIKE CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
