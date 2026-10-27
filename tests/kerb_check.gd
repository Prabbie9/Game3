extends Node
## Pavement edges: walking from a lawn onto the road and driving from the grass up onto the road, nobody gets
## stuck at the pavement's outer edge (it used to be a bare 15 cm ledge the player could only jump).
## godot --headless --path . res://tests/runner.tscn -- res://tests/kerb_check.gd

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
	world.parked.max_active = 0
	world.wanted.process_mode = Node.PROCESS_MODE_DISABLED
	Game.controls_enabled = true
	await _secs(2.0)
	var p := world.player
	var d := WorldData.get_data()
	# residential streets in Las Lomas, a few metres off each street's middle point (clear of the lamp posts)
	var spots := []
	for rd: Dictionary in d.roads:
		if not rd.walk or rd.kind != "residential":
			continue
		var pts: Array = rd.pts
		var i := pts.size() / 2
		var a := Vector3(pts[i - 1][0], pts[i - 1][1], pts[i - 1][2])
		var b := Vector3(pts[i][0], pts[i][1], pts[i][2])
		var dir := (b - a).normalized()
		var c := b + dir * 3.0
		c.y = b.y + (b.y - a.y) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.01) * 3.0
		spots.append([c, Vector3(-dir.z, 0, dir.x), float(rd.w) * 0.5])
	spots = spots.slice(0, 24)
	var outer := CityCell.SIDEWALK
	var at_edge := 0
	var reached := 0
	var tries := 0
	for s: Array in spots:
		var c: Vector3 = s[0]
		var side: Vector3 = s[1]
		var half: float = s[2]
		for sgn: float in [-1.0, 1.0]:
			var start := c + side * sgn * (half + outer + 1.6)   # on the grass just past the pavement
			var yaw := atan2(side.x * sgn, side.z * sgn)        # facing the road
			p._respawn(Transform3D(Basis(Vector3.UP, yaw), Vector3(start.x, d.height_at(start.x, start.z) + 0.3, start.z)), "")
			p.cam.yaw = yaw
			world.warm_up(start)
			await _secs(2.0)
			if p.state != Player.State.ON_FOOT:
				continue
			Input.action_press("move_forward")
			await _secs(3.0)
			Input.action_release("move_forward")
			var out := (p.global_position - c).dot(side * sgn)   # metres out on the starting side
			tries += 1
			if out < half:
				reached += 1
			elif out > half + outer - 0.3 and out < half + outer + 1.0:
				at_edge += 1
				print("  stuck at the pavement edge near %s (%.1f m out)" % [start.snapped(Vector3.ONE * 0.1), out])
	_check(tries >= 30, "walked from the grass towards the road %d times" % tries)
	_check(at_edge == 0, "never stopped at the pavement's outer edge (%d times)" % at_edge)
	_check(reached >= tries * 0.85, "reached the road %d of %d times (the rest met a lamp post or a tree)" % [reached, tries])
	# drive off a lawn, up over the pavement and onto the road
	# (somewhere the run-up crosses no front yard)
	var c := Vector3.ZERO
	var side := Vector3.ZERO
	var start := Vector3.ZERO
	for s: Array in spots:
		for sgn: float in [-1.0, 1.0]:
			var st: Vector3 = s[0] + s[1] * sgn * (float(s[2]) + outer + 7.0)
			var clear := true
			for l: Dictionary in d.lots:
				var r := Rect2(l.x0, l.z0, l.x1 - l.x0, l.z1 - l.z0).grow(1.5)
				for k in 8:
					var q: Vector3 = s[0].lerp(st, k / 7.0)
					if r.has_point(Vector2(q.x, q.z)):
						clear = false
			if clear and start == Vector3.ZERO:
				c = s[0]
				side = s[1] * sgn
				start = st
	_check(start != Vector3.ZERO, "found a lawn to drive off")
	world.warm_up(start)
	var car := Vehicle.new()
	car.model = "sedan"
	world.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(side.x, side.z)), Vector3(start.x, d.height_at(start.x, start.z) + 0.7, start.z))
	await _secs(1.0)
	p.debug_seat_in(car)
	car.set_driver_input_enabled(false)
	car.ai_drive = true
	car.ai_throttle = 0.45
	var t := 0.0
	while t < 8.0 and (car.global_position - c).dot(side) > 0.0:
		await _secs(0.25)
		t += 0.25
	_check((car.global_position - c).dot(side) <= 0.5, "a car drives off the lawn, over the pavement and onto the road (%.1f s)" % t)
	print("KERB CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
