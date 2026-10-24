extends Node
## Escalation: two stars and officers open fire; patrol cars close in on a player in a car; three stars and a
## fast player meets a roadblock across the road ahead; four stars bring a SWAT van; five the helicopter, which
## holds above the player.
## godot --headless --path . res://tests/runner.tscn -- res://tests/police_chase_check.gd

var fails := 0
var world: World
var p: Player


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
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
	Game.controls_enabled = false
	p = world.player
	await _secs(2.0)
	while not NPCDriver.is_ready("ch31_nonpbr"):
		await _secs(0.5)
	var w: Wanted = world.wanted
	# two stars on foot: officers shoot
	Game.crime("kill_police", p.global_position)
	_check(w.stars == 2, "killing an officer: two stars (%d)" % w.stars)
	var cop := w._make_cop("pistol")
	world.add_child(cop)
	cop.global_position = p.global_position + Vector3(12, 0.05, 0)
	var hp := p.health
	var t := 0.0
	while t < 8.0 and p.health >= hp:
		await _secs(0.25)
		t += 0.25
		if int(t * 4) % 4 == 0:
			print("      cop state %s at %.1f m seen %.2f stars %d armed %s" % [cop.state, cop.global_position.distance_to(p.global_position), cop._seen_t, w.stars, p.weapon.current])
	_check(p.health < hp, "officers open fire (hit after %.1f s, health %.0f)" % [t, p.health])
	_check(cop.visual.skeleton.has_node("UniformVest"), "officers wear the uniform")
	p.health = 100.0
	# in a car: patrol cars close in
	for c in get_tree().get_nodes_in_group("police"):
		c.queue_free()
	w.cops.clear()
	var tl := world.traffic.nearest_lane(p.global_position)
	var at: Array = world.traffic.graph.sample(int(tl[0]), float(tl[1]))
	var car := Vehicle.new()
	car.model = "sport"
	world.add_child(car)
	car.global_position = (at[0] as Vector3) + Vector3(0, 0.7, 0)
	var dir: Vector3 = at[1]
	car.rotation.y = atan2(-dir.x, -dir.z)
	await _secs(1.0)
	p.debug_seat_in(car)
	await _secs(1.0)
	t = 0.0
	var closest := INF
	while t < 45.0 and closest > 25.0:
		await _secs(0.5)
		t += 0.5
		w.report_sighting(car.global_position)   # keep the chase on while the player sits still
		for u: Dictionary in w.units:
			var v: Vehicle = (u.car as TrafficManager.TrafficCar).v
			if is_instance_valid(v) and u.kind == "police":
				closest = minf(closest, v.global_position.distance_to(car.global_position))
	var on_foot := get_tree().get_nodes_in_group("police").size()
	_check(closest <= 25.0 or on_foot >= 2, "a patrol car reaches the player (%d officers out)" % on_foot)
	print("      patrol car (%.0f m after %.0f s, %d units)" % [closest, t, w.units.size()])
	# three stars at speed: a roadblock ahead
	Game.crime("kill_police", p.global_position)
	_check(w.stars >= 3, "three stars (%d)" % w.stars)
	# the arrived patrol cars box the player in: clear them for a fresh run down the road
	for u: Dictionary in w.units:
		if is_instance_valid((u.car as TrafficManager.TrafficCar).v):
			(u.car as TrafficManager.TrafficCar).v.queue_free()
	w.units.clear()
	for c in get_tree().get_nodes_in_group("police"):
		c.queue_free()
	w.cops.clear()
	w._spawn_t = 6.0
	await _secs(0.3)
	w._roadblock_t = 0.0
	car.set_driver_input_enabled(false)
	car.ai_drive = true
	var placed := false
	t = 0.0
	while t < 12.0 and not placed:
		car.ai_throttle = 1.0 if car.linear_velocity.length() < 16.0 else 0.2
		car.ai_brake = 0.0
		# follow the road (pure pursuit on a point along the lane ahead)
		var fw := -car.global_basis.z
		var la := world.traffic.lane_ahead(car.global_position, fw, 14.0)
		car.ai_steer = 0.0
		if int(la[0]) >= 0:
			var aim: Vector3 = world.traffic.graph.sample(int(la[0]), float(la[1]))[0]
			var lo := car.global_transform.affine_inverse() * aim
			car.ai_steer = clampf(atan2(-lo.x, -lo.z) * 2.0, -1.0, 1.0)
		w.report_sighting(car.global_position)
		await _secs(0.25)
		t += 0.25
		placed = not w.roadblocks.is_empty()
		if int(t * 4) % 4 == 0:
			var la2 := world.traffic.lane_ahead(car.global_position, -car.global_basis.z, 120.0)
			print("      driving %.1f m/s at %s stars %d rb_t %.1f lane ahead %s" % [car.linear_velocity.length(), car.global_position.snapped(Vector3.ONE), w.stars, w._roadblock_t, la2])
	var on_road := false
	if placed:
		var rb: Vehicle = w.roadblocks[0]
		var near := world.traffic.nearest_lane(rb.global_position)
		on_road = float(near[2]) < 6.0
	_check(placed and on_road, "a roadblock is set up across the road ahead (%s)" % ("on the road" if on_road else "missing" if not placed else "off the road"))
	car.ai_throttle = 0.0
	car.ai_brake = 1.0
	# four stars: SWAT; five: the helicopter
	Game.crime("kill_police", p.global_position)
	Game.crime("kill_police", p.global_position)
	_check(w.stars >= 4, "four stars (%d)" % w.stars)
	t = 0.0
	var swat := false
	while t < 20.0 and not swat:
		await _secs(0.5)
		t += 0.5
		w.report_sighting(car.global_position)
		swat = w.units.any(func(u): return u.kind == "swat")
	_check(swat, "a SWAT van is sent (%.0f s)" % t)
	Game.crime("kill_police", p.global_position)
	Game.crime("kill_police", p.global_position)
	_check(w.stars == 5, "five stars (%d)" % w.stars)
	t = 0.0
	var hover := INF
	while t < 40.0 and hover > 40.0:
		await _secs(0.5)
		t += 0.5
		w.report_sighting(car.global_position)
		if is_instance_valid(w.heli):
			hover = Vector2(w.heli.global_position.x - car.global_position.x, w.heli.global_position.z - car.global_position.z).length()
			if not w.heli.contact_monitor:
				w.heli.contact_monitor = true
				w.heli.max_contacts_reported = 4
			if int(t * 2) % 4 == 0:
				print("      heli touching %s grounded %s " % [w.heli.get_colliding_bodies().map(func(b): return "%s@%s" % [b.name, (b as Node3D).global_position.snapped(Vector3.ONE)]), w.heli._grounded])
				print("      heli at %s (car %s) vel %s lift %.2f thr %.2f steer %.2f rotor %.2f frozen %s" % [w.heli.global_position.snapped(Vector3.ONE), car.global_position.snapped(Vector3.ONE), w.heli.linear_velocity.snapped(Vector3.ONE * 0.1), w.heli.ai_lift, w.heli.ai_throttle, w.heli.ai_steer, w.heli.rotor, w.heli.freeze])
	_check(hover <= 40.0, "the helicopter arrives overhead (%.0f m off after %.0f s)" % [hover, t])
	if is_instance_valid(w.heli):
		var hx := w.heli.global_position
		await _secs(5.0)
		var drift := Vector2(w.heli.global_position.x - car.global_position.x, w.heli.global_position.z - car.global_position.z).length()
		_check(drift < 45.0 and w.heli.global_position.y > car.global_position.y + 15.0, "the helicopter holds above the player (%.0f m off, %.0f m up, moved %.0f m)" % [drift, w.heli.global_position.y - car.global_position.y, hx.distance_to(w.heli.global_position)])
	print("POLICE CHASE CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
