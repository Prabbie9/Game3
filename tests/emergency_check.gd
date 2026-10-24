extends Node
## Emergency services: a pedestrian killed near the player brings an ambulance whose paramedic revives them;
## a burning car brings a fire engine that puts it out.
## godot --headless --path . res://tests/runner.tscn -- res://tests/emergency_check.gd

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
	world.time_scale = 0.0
	Game.controls_enabled = false
	await _secs(3.0)
	print("      world up")
	while not NPCDriver.is_ready("ch02_nonpbr"):
		await _secs(0.5)
	print("      characters ready")
	var ped := Pedestrian.new()
	ped.character_file = "ch02_nonpbr"
	world.add_child(ped)
	ped.global_position = Vector3(50.0, CityCell.CURB_H + 0.05, 9.0)
	await _secs(0.5)
	ped.take_damage(500.0)
	for n in get_tree().get_nodes_in_group("pedestrians"):
		n.died.connect(func(pp): print("      DIED %s at %s (killer %s)" % [pp.character_file, pp.global_position.snapped(Vector3.ONE), pp._killer]))
	var t := 0.0
	var amb: Vehicle = null
	while t < 90.0 and is_instance_valid(ped) and not ped.is_alive():
		await _secs(1.0)
		t += 1.0
		for c in world.traffic.cars:
			if c.emergency and is_instance_valid(c.v) and not c.v.contact_monitor:
				var vv: Vehicle = c.v
				vv.contact_monitor = true
				vv.max_contacts_reported = 4
				vv.body_entered.connect(func(b: Node): print("      CONTACT %s with %s (%s) at %s" % [vv.model, b.name, b.get_class(), vv.global_position.snapped(Vector3.ONE * 0.1)]))
			if c.emergency and is_instance_valid(c.v) and int(t) % 5 == 0:
				print("      unit %s at %s lane %d -> target %d (route %d) s %.1f/%.1f speed %.1f reason '%s' arrived %s" % [c.v.model, c.v.global_position.snapped(Vector3.ONE), c.lane, c.target_lane, c.route.size(), c.s, c.target_s, c.v.linear_velocity.length(), c.reason, c.arrived])
				var lnd: Dictionary = world.traffic.graph.lanes[c.lane]
				print("        lane kind %s node %s turn %s target_pos %s next %s want %.1f thr %.2f brk %.2f stuck %.1f rev %.1f revs %d seen %s" % [lnd.kind, lnd.node, lnd.turn, c.target_pos.snapped(Vector3.ONE), c.next, c.want, c.v.ai_throttle, c.v.ai_brake, c.stuck, c.reverse_t, c.reverses, world.traffic._seen(c.v.global_position)])
				if c.block is Vehicle:
					var bc = null
					for o in world.traffic.cars:
						if o.v == c.block:
							bc = o
					print("        blocker %s at %s speed %.1f %s" % [(c.block as Vehicle).model, (c.block as Vehicle).global_position.snapped(Vector3.ONE * 0.1), (c.block as Vehicle).linear_velocity.length(), ("traffic lane %d reason '%s' parked %s panic %.1f" % [bc.lane, bc.reason, bc.parked, bc.panic]) if bc else "not traffic (player/parked)"])
		if is_instance_valid(ped) and int(t) % 5 == 0:
			print("      t %.0f real %d ped %s incidents %d jobs %d cars %d" % [t, Time.get_ticks_msec() / 1000, ped.state, world.traffic.get_node("Emergency")._incidents.size(), world.traffic.get_node("Emergency")._jobs.size(), world.traffic.cars.size()])
		for c in world.traffic.cars:
			if c.emergency and is_instance_valid(c.v) and c.v.model == "ambulance":
				amb = c.v
	_check(amb != null, "an ambulance was sent")
	_check(is_instance_valid(ped) and ped.is_alive(), "the paramedic revived them (%.0f s)" % t)
	# a car on fire 30 m along the street
	var car := Vehicle.new()
	car.model = "sedan"
	car.position = Vector3(64.0, 0.6, -5.2)
	car.rotation.y = PI * 0.5
	world.add_child(car)
	await _secs(1.5)
	car.damage._damage(car.damage.health + 1.0)
	_check(car.damage.burning(), "the car burns")
	t = 0.0
	var ft: Vehicle = null
	while t < 100.0 and car.damage.burning():
		await _secs(1.0)
		t += 1.0
		for c in world.traffic.cars:
			if c.emergency and is_instance_valid(c.v) and c.v.model == "firetruck":
				ft = c.v
	_check(ft != null, "a fire engine was sent")
	_check(not car.damage.burning(), "the fire is out (%.0f s, wrecked %s)" % [t, car.damage.wrecked])
	print("EMERGENCY CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
