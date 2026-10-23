extends Node
## Parked cars: slots exist, cars fill in around the player, sit upright on the road, don't overlap the world or
## each other, go to sleep, and are released when the player moves on.
## godot --headless --path . res://tests/runner.tscn -- res://tests/parked_check.gd

var fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	world.time_scale = 0.0
	var pc := world.parked
	print("PARKED: %d slots" % pc.slot_count())
	_check(pc.slot_count() > 800, "slots generated (%d)" % pc.slot_count())
	for i in 240:
		await get_tree().physics_frame
	var cars := get_tree().get_nodes_in_group("parked")
	_check(pc.active_count() >= pc.max_active * 0.6, "cars around the spawn (%d of %d)" % [pc.active_count(), pc.max_active])
	var asleep := 0
	var upright := 0
	var grounded := 0
	var overlaps := 0
	var space := world.get_world_3d().direct_space_state
	for v: Vehicle in cars:
		if v.sleeping:
			asleep += 1
		else:
			print("    awake %s v=%.3f w=%.3f idle=%s t=%.1f freeze=%s" % [v.model, v.linear_velocity.length(), v.angular_velocity.length(), v._idle, v._idle_time, v.freeze])
		if v.global_basis.y.dot(Vector3.UP) > 0.97:
			upright += 1
		var contact := 0
		for w in v._wheels:
			if w.is_in_contact():
				contact += 1
		if contact == 4:
			grounded += 1
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 0.6, 3.8)
		q.shape = box
		q.transform = Transform3D(v.global_basis, v.global_position + v.global_basis.y * 1.0)
		q.collision_mask = 1 | 16
		if not space.intersect_shape(q, 1).is_empty():
			overlaps += 1
			print("    overlap at %s" % v.global_position.snapped(Vector3.ONE * 0.1))
	var n := maxf(cars.size(), 1)
	_check(upright == cars.size(), "all upright (%d/%d)" % [upright, cars.size()])
	_check(grounded >= cars.size() * 0.95, "wheels on the ground (%d/%d)" % [grounded, cars.size()])
	_check(overlaps == 0, "none inside buildings or props (%d)" % overlaps)
	_check(asleep >= n * 0.8, "at rest and asleep (%d/%d)" % [asleep, cars.size()])
	# build cost of one parked car
	var t0 := Time.get_ticks_usec()
	var probe := Vehicle.new()
	probe.model = "suv"
	probe.paint = Color(0.8, 0.8, 0.8)
	probe.position = Vector3(0, -500, 0)
	world.add_child(probe)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	probe.free()
	print("PARKED: one car costs %.2f ms to create" % ms)
	_check(ms < 6.0, "cheap to create")
	# drive the camera far away: the parked cars must be released
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(-745, 30, 240)
	for i in 120:
		await get_tree().process_frame
	var left := 0
	for v: Node in get_tree().get_nodes_in_group("parked"):
		if is_instance_valid(v) and (v as Node3D).global_position.distance_to(Vector3(26, 0, 9)) < 200.0:
			left += 1
	_check(left == 0, "released after leaving (%d left)" % left)
	print("PARKED CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
