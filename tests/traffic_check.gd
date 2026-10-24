extends Node
## Traffic in the real world: cars spawn around the player, drive along their lanes (stay near the lane centre,
## move on), stop at red lights, don't pile into each other.
## godot --headless --path . res://tests/runner.tscn -- res://tests/traffic_check.gd

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
	var tm: TrafficManager = world.traffic
	var t := 0.0
	while tm.cars.size() < tm.budget and t < 40.0:
		await _secs(0.5)
		t += 0.5
	_check(tm.cars.size() >= tm.budget * 0.6, "traffic spawned (%d / %d in %.0f s)" % [tm.cars.size(), tm.budget, t])
	var start := {}
	for c in tm.cars:
		var v: Vehicle = c.v
		v.contact_monitor = true
		v.max_contacts_reported = 4
		v.body_entered.connect(func(b: Node):
			if true:
				print("      contact %s (%.1f m/s) with %s %s at %s" % [v.model, v.linear_velocity.length(), b.name, b.get_groups().filter(func(g): return not String(g).begins_with("_")), v.global_position.snapped(Vector3.ONE * 0.1)]))
		start[c] = c.v.global_position
	var worst_off := 0.0
	var red_runs := 0
	var crashes := 0
	var damaged := {}
	var reasons := {}
	var dist_sum := 0.0
	var samples := 0.0
	var turn_samples := 0
	var turn_signalled := 0
	var off_run := {}      # car -> consecutive samples well off its lane
	var worst_run := 0
	for step in 60:
		await _secs(0.5)
		for c in tm.cars:
			if not is_instance_valid(c.v):
				continue
			var ln: Dictionary = tm.graph.lanes[c.lane]
			var on: Vector3 = tm.graph.sample(c.lane, c.s)[0]
			var off := Vector2(on.x - c.v.global_position.x, on.z - c.v.global_position.z).length()
			if ln.node < 0 and c.change_t < 0.0 and c.pass_t <= -1.0 and c.yield_t <= -1.0 and not c.emergency:
				worst_off = maxf(worst_off, off)
				off_run[c] = int(off_run.get(c, 0)) + 1 if off > 2.5 else 0
				worst_run = maxi(worst_run, int(off_run[c]))
				if off > 2.2 and worst_off < 9.0:
					print("      off lane %.2f: %s lane %d (%s idx %d/%d) s %.1f speed %.1f block %s" % [off, c.v.model, c.lane, ln.kind, ln.index, ln.lanes, c.s, c.v.linear_velocity.length(), c.block])
			if ln.node >= 0 and int(ln.turn) != 0:
				turn_samples += 1
				if c.v.indicator == (Vehicle.Blinker.LEFT if int(ln.turn) < 0 else Vehicle.Blinker.RIGHT):
					turn_signalled += 1
			dist_sum += c.v.linear_velocity.length() * 0.5
			var rk: String = c.reason.split(" ")[0] if c.reason != "" else ("free" if c.v.linear_velocity.length() > 2.0 else "stopped?")
			reasons[rk] = int(reasons.get(rk, 0)) + 1
			samples += 0.5
			# crossing a stop line on red: on a connector of a signalled junction whose phase is red, at speed, early
			if ln.node >= 0 and int(ln.group) >= 0 and c.s < 2.0 and tm.graph.signal_state(int(ln.node), int(ln.group), tm.clock) == 2 \
					and c.v.linear_velocity.length() > 6.0 and c.panic <= 0.0:
				red_runs += 1
			if c.v.damage.health < 850.0 and not damaged.has(c):
				damaged[c] = true
				crashes += 1
				print("      damaged: %s health %.0f at %s lane %s s %.1f speed %.1f" % [c.v.model, c.v.damage.health, c.v.global_position, ln.kind, c.s, c.v.linear_velocity.length()])
	for c in tm.cars:
		if is_instance_valid(c.v):
			print("      %s %s lane %s s %.0f/%.0f speed %.1f stuck %.1f %s" % [c.v.model, c.v.global_position.snapped(Vector3.ONE * 0.1), tm.graph.lanes[c.lane].kind, c.s, tm.graph.lanes[c.lane].len, c.v.linear_velocity.length(), c.stuck, c.reason])
	var moved := 0
	for c in start:
		if is_instance_valid(c.v) and c.v.global_position.distance_to(start[c]) > 40.0:
			moved += 1
	print("      reasons: %s" % reasons)
	var mean := dist_sum / maxf(samples, 0.001)
	_check(mean > 4.5, "traffic flows (mean speed %.1f m/s incl. waiting at lights; %d of %d first cars moved > 40 m)" % [mean, moved, start.size()])
	_check(worst_run < 3, "cars stay in lane (worst %.2f m off, longest %.1f s more than 2.5 m off)" % [worst_off, worst_run * 0.5])
	_check(red_runs <= 1, "no red-light running (%d)" % red_runs)
	_check(turn_samples == 0 or turn_signalled == turn_samples, "turning cars indicate (%d / %d)" % [turn_signalled, turn_samples])
	_check(crashes <= 1, "no pile-ups (%d damaged)" % crashes)
	print("TRAFFIC CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
