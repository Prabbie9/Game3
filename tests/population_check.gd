extends Node
## Pedestrians in the real world: people appear around the player, walk along the pavements (not the road),
## wait at crossings, and react to gunfire (run, cower, spread the panic, call the police).
## godot --headless --path . res://tests/runner.tscn -- res://tests/population_check.gd

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
	world.time_of_day = 13.0
	Game.controls_enabled = false
	var pop: Population = world.population
	var want := pop.target_count(world.player.global_position)
	var t := 0.0
	while pop.people.size() < want and t < 60.0:
		await _secs(0.5)
		t += 0.5
	_check(pop.people.size() >= want * 0.7, "people appear (%d / %d in %.0f s)" % [pop.people.size(), want, t])
	var kinds := {}
	for p: Pedestrian in pop.people:
		kinds[p.character_file] = true
	_check(kinds.size() >= mini(6, pop.people.size()), "varied characters (%d different)" % kinds.size())
	var start := {}
	for p: Pedestrian in pop.people:
		start[p] = p.global_position
	var on_road := 0
	var samples := 0
	var waited := false
	var police_calls := [0]
	Game.police_call.connect(func(_a, _b): police_calls[0] += 1)
	for i in 30:
		await _secs(0.5)
		for p: Pedestrian in pop.people:
			if not is_instance_valid(p):
				continue
			if p.state == Pedestrian.State.WAIT:
				waited = true
			if p.state == Pedestrian.State.WALK and p.edge >= 0 and not pop.walk.edges[p.edge].cross:
				var r: int = pop.walk.edges[p.edge].road
				if r >= 0:
					samples += 1
					# distance from the road's centre line against its half width
					var pts: Array = world.data.roads[r].pts
					var best := INF
					for k in pts.size() - 1:
						var a2 := Vector2(pts[k][0], pts[k][2])
						var b2 := Vector2(pts[k + 1][0], pts[k + 1][2])
						var q := Geometry2D.get_closest_point_to_segment(Vector2(p.global_position.x, p.global_position.z), a2, b2)
						best = minf(best, q.distance_to(Vector2(p.global_position.x, p.global_position.z)))
					if best < float(world.data.roads[r].w) * 0.5 - 0.2:
						on_road += 1
						if on_road < 4:
							print("      on road: %s state %s edge %d s %.1f lateral %.2f dist %.2f half %.1f" % [p.global_position, p.state, p.edge, p.s, p.lateral, best, float(world.data.roads[r].w) * 0.5])
	var walked := 0
	var walkers := 0
	for p in start:
		if is_instance_valid(p) and p.state == Pedestrian.State.WALK:
			walkers += 1
			if p.global_position.distance_to(start[p]) > 8.0:
				walked += 1
			else:
				var e: Dictionary = pop.walk.edges[p.edge]
				var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 0.8, 0), p.global_position + Vector3(0, 0.8, 0) - p.global_basis.z * 1.2, 1 | 4 | 8 | 16)
				q.exclude = [p.get_rid()]
				var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
				print("      slow walker at %s edge %d (len %.1f cross %s) s %.1f speed %.2f ahead %s" % [p.global_position.snapped(Vector3.ONE * 0.1), p.edge, e.len, e.cross, p.s, p.velocity.length(), hit.collider if hit else "-"])
	_check(walkers > 0 and walked >= walkers * 0.6, "walkers move along (%d of %d moved > 8 m in 15 s)" % [walked, walkers])
	_check(samples > 0 and on_road <= samples * 0.05, "they keep to the pavement (%d of %d samples on the road)" % [on_road, samples])
	print("      someone waited at a crossing: %s" % waited)
	# gunfire next to the crowd
	var near: Pedestrian = null
	var bd := INF
	for p: Pedestrian in pop.people:
		if is_instance_valid(p) and p.global_position.distance_to(world.player.global_position) < bd:
			bd = p.global_position.distance_to(world.player.global_position)
			near = p
	if near:
		Game.noise(near.global_position + Vector3(2, 0, 0), 60.0, world.player)
		await _secs(1.0)
		var reacting := 0
		for p: Pedestrian in pop.people:
			if is_instance_valid(p) and p.state in [Pedestrian.State.FLEE, Pedestrian.State.COWER, Pedestrian.State.CALL]:
				reacting += 1
		_check(reacting >= 1, "gunfire: %d react (run / cower)" % reacting)
		await _secs(12.0)
		print("      police calls after 12 s: %d" % police_calls[0])
	print("POPULATION CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
