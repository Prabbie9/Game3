extends Node
## Helicopter: spins up, climbs, holds a hover, flies forward, yaws, stays upright, and sinks to a safe landing with
## the engine off. Boat (at the pier in the real world): floats upright on the swell, gets up to speed, turns.
## godot --headless --path . res://tests/runner.tscn -- res://tests/air_sea_check.gd

var fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(s: float) -> void:
	await _frames(int(s * 60.0))


func _run() -> void:
	await _heli()
	await _boat()
	print("AIR/SEA CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)


func _heli() -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(3000, 2, 3000)
	cs.shape = b
	sb.add_child(cs)
	sb.position.y = -1.0
	root.add_child(sb)
	var h := Helicopter.new()
	h.position = Vector3(0, 0.3, 0)
	root.add_child(h)
	await _secs(1.0)
	_check(h.global_position.y < 0.6, "rests on its skids (y %.2f)" % h.global_position.y)
	h.set_driver(self)
	Input.action_press("ascend")
	await _secs(1.5)
	_check(h.global_position.y < 0.8, "doesn't lift before the rotor is up to speed (y %.2f, rotor %.2f)" % [h.global_position.y, h.rotor])
	await _secs(5.0)
	Input.action_release("ascend")
	var alt := h.global_position.y
	_check(alt > 8.0, "climbs (%.1f m)" % alt)
	await _secs(3.0)
	_check(absf(h.linear_velocity.y) < 1.0 and absf(h.global_position.y - alt) < 5.0, "holds a hover (vy %.2f, drift %.1f m)" % [h.linear_velocity.y, h.global_position.y - alt])
	var p0 := h.global_position
	Input.action_press("accelerate")
	await _secs(5.0)
	var spd := Vector2(h.linear_velocity.x, h.linear_velocity.z).length()
	Input.action_release("accelerate")
	_check(spd > 12.0 and spd < 65.0, "flies forward (%.0f km/h)" % (spd * 3.6))
	var fwd_move := (h.global_position - p0).dot(-h.global_basis.z)
	_check(fwd_move > 20.0, "moves the way the nose points (%.0f m)" % fwd_move)
	var yaw0 := h.rotation.y
	Input.action_press("steer_left")
	await _secs(2.0)
	Input.action_release("steer_left")
	_check(absf(wrapf(h.rotation.y - yaw0, -PI, PI)) > 1.2, "yaws (%.2f rad)" % wrapf(h.rotation.y - yaw0, -PI, PI))
	await _secs(2.0)
	_check(h.global_basis.y.y > 0.8, "levels out (up %.2f)" % h.global_basis.y.y)
	# engine off: the rotor winds down and it settles to the ground in one piece
	h.set_driver(null)
	var t := 0.0
	while t < 40.0 and h.global_position.y > 0.8:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await _secs(2.0)
	_check(h.global_position.y < 1.0, "comes down without power (%.0f s)" % t)
	_check(not h.damage.wrecked, "survives the landing (health %.0f)" % h.damage.health)
	root.queue_free()
	await _frames(2)


func _boat() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	world.time_scale = 0.0
	world.weather.auto_change = false
	world.weather.set_weather(Weather.Kind.CLEAR, true)
	var boat: Boat = null
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v is Boat:
			boat = v
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = boat.global_position + Vector3(0, 10, 20)
	cam.make_current()
	await _secs(6.0)
	var sea := world.data.sea
	_check(boat.in_water and absf(boat.global_position.y - sea) < 1.5, "floats (y %.2f, sea %.1f)" % [boat.global_position.y, sea])
	_check(boat.global_basis.y.y > 0.95, "sits upright (up %.2f)" % boat.global_basis.y.y)
	boat.set_driver(self)
	Input.action_press("accelerate")
	var p0 := boat.global_position
	for i in 480:
		await get_tree().physics_frame
		cam.global_position = boat.global_position + Vector3(0, 10, 20)
	var spd := boat.linear_velocity.length()
	_check(spd > 12.0, "gets up to speed (%.0f km/h)" % (spd * 3.6))
	_check((boat.global_position - p0).dot(-boat.global_basis.z) > 40.0, "goes where the bow points")
	var yaw0 := boat.rotation.y
	Input.action_press("steer_right")
	for i in 150:
		await get_tree().physics_frame
		cam.global_position = boat.global_position + Vector3(0, 10, 20)
	Input.action_release("steer_right")
	Input.action_release("accelerate")
	_check(wrapf(boat.rotation.y - yaw0, -PI, PI) < -0.8, "turns (%.2f rad)" % wrapf(boat.rotation.y - yaw0, -PI, PI))
	_check(boat.global_basis.y.y > 0.85 and boat.in_water, "stays upright and afloat (up %.2f)" % boat.global_basis.y.y)
	_check(not boat.damage.wrecked and boat.damage.health > 900.0, "the swell doesn't damage it (health %.0f)" % boat.damage.health)
	boat.set_driver(null)
