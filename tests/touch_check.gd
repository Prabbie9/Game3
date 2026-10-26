extends Node
## Breakable fences and glass, pushable objects: shop windows shatter when shot or caught in a blast (and are
## glazed again later); a car ploughs through a picket fence (it splinters) and gunfire wears one down; a blast
## tears out a chain-link bay; crates, drums and boxes lie in the industrial yards, rest on the ground, can be
## walked into and shoved, kicked, and are still where they were left after the player goes away and comes back.
## godot --headless --path . res://tests/runner.tscn -- res://tests/touch_check.gd

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


func _go(pos: Vector3) -> void:
	p._respawn(Transform3D(Basis(), pos), "")
	await _secs(0.5)
	var t := 0.0
	while t < 30.0 and not world.city.is_settled():
		await _secs(0.25)
		t += 0.25
	await _secs(1.0)


## Nearest live instance of a city prop: [StaticBody3D, shape index, global transform, CollisionShape3D] or [].
func _find(name: String, near: Vector3, maxd := 200.0) -> Array:
	var best := []
	var bd := maxd
	for cell in world.city._cells.values():
		if not is_instance_valid(cell):
			continue
		for sb in (cell as Node).get_children():
			if not (sb is StaticBody3D) or String(sb.get_meta("prop", "")) != name:
				continue
			var idx := 0
			for cs in sb.get_children():
				if not (cs is CollisionShape3D):
					continue
				var d := (cs as CollisionShape3D).global_position.distance_to(near)
				if not cs.disabled and d < bd:
					bd = d
					var mmi: MultiMeshInstance3D = sb.get_meta("mmi")
					var ixf := mmi.global_transform * ((mmi.get_meta("xfs") as Array)[int(cs.get_meta("inst"))] as Transform3D)
					best = [sb, idx, ixf, cs]
				idx += 1
	return best


func _broken(found: Array) -> bool:
	return (found[3] as CollisionShape3D).disabled


func _run() -> void:
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
	world.traffic.budget = 0
	world.wanted.process_mode = Node.PROCESS_MODE_DISABLED
	Game.controls_enabled = true
	p = world.player
	await _secs(3.0)
	var props: PropWorld = PropWorld.get_props()
	var data := WorldData.get_data()
	# --- glass: shoot a window near the start, blast another
	var panes := get_tree().get_nodes_in_group("glass_panes")
	panes.sort_custom(func(a, b): return a.global_position.distance_to(p.global_position) < b.global_position.distance_to(p.global_position))
	_check(panes.size() >= 4, "window panes near the start (%d)" % panes.size())
	if panes.size() >= 2:
		var g: GlassPane = panes[0]
		var dir := (g.global_position - p.global_position).normalized()
		Weapon.apply_hit(world, {"collider": g, "position": g.global_position, "normal": -dir}, dir, 34.0, p)
		await _secs(0.2)
		var shards := g.get_children().filter(func(n): return n is CPUParticles3D).size()
		_check(g.broken and not g._mesh.visible and shards == 1, "a shot window shatters (shards %d)" % shards)
		var q := PhysicsRayQueryParameters3D.create(g.global_position - dir * 1.0, g.global_position + dir * 1.0, 1)
		_check(world.get_world_3d().direct_space_state.intersect_ray(q).get("collider") != g, "the empty frame lets things through")
		var g2: GlassPane = panes[1]
		Explosion.blast(world, g2.global_position + Vector3(0, 0, 2.0), 6.0, 10.0, null)
		await _secs(0.2)
		_check(g2.broken, "a blast blows a window in")
		# glazed again once the player is away
		g._since = GlassPane.REGLAZE + 1.0
		var home := p.global_position
		p.global_position = g.global_position + Vector3(0, 0, 120.0)
		await _secs(0.3)
		_check(not g.broken and g._mesh.visible, "the window is glazed again later")
		p._respawn(Transform3D(Basis(), home), "")
		await _secs(0.5)
	# --- picket fence: drive through one, shoot another
	var house: Dictionary = data.lots.filter(func(l): return l.kind == "house")[6]
	var hb := Basis(Vector3.UP, float(house.get("yaw", 0.0)))
	var hc := Vector3((float(house.x0) + float(house.x1)) * 0.5, 0, (float(house.z0) + float(house.z1)) * 0.5)
	var street := hc + hb * Vector3(0, 0, -16.0)
	street.y = data.height_at(street.x, street.z) + 1.0
	await _go(street)
	var fence := _find("picket_fence", hc + hb * Vector3(-6.0, 0, -8.6), 6.0)
	_check(not fence.is_empty(), "a picket fence along a front yard")
	if not fence.is_empty():
		var fxf: Transform3D = fence[2]
		var out := -fxf.basis.z.normalized()   # the fence's front faces the street
		out.y = 0.0
		out = out.normalized()
		var car := Vehicle.new()
		car.model = "sedan"
		world.add_child(car)
		car.global_position = fxf.origin + out * 16.0 + Vector3(0, 1.2, 0)
		car.rotation.y = atan2(out.x, out.z)
		await _secs(0.5)
		p.debug_seat_in(car)
		await _secs(0.5)
		car.set_driver_input_enabled(false)
		car.ai_drive = true
		car.ai_throttle = 0.8
		var debris_before := props._debris.size()
		var t := 0.0
		while t < 6.0 and not _broken(fence):
			await _secs(0.1)
			t += 0.1
		_check(_broken(fence), "a car drives through the picket fence (%.1f s, %.1f m/s)" % [t, car.linear_velocity.length()])
		_check(props._debris.size() - debris_before >= 8, "it splinters into pickets and rails (%d pieces)" % (props._debris.size() - debris_before))
		car.ai_throttle = 0.0
		car.ai_brake = 1.0
		await _secs(1.0)
		p._respawn(Transform3D(Basis(), street), "")
		car.queue_free()
		await _secs(0.5)
		var f2 := _find("picket_fence", hc + hb * Vector3(6.5, 0, -8.6), 8.0)
		if f2.is_empty() or _broken(f2):
			f2 = _find("picket_fence", street, 60.0)
		if not f2.is_empty():
			var at: Vector3 = (f2[2] as Transform3D).origin + Vector3(0, 0.6, 0)
			props.on_hit({"collider": f2[0], "shape": f2[1], "position": at}, Vector3.FORWARD, 34.0)
			props.on_hit({"collider": f2[0], "shape": f2[1], "position": at}, Vector3.FORWARD, 34.0)
			var holds := not _broken(f2)
			props.on_hit({"collider": f2[0], "shape": f2[1], "position": at}, Vector3.FORWARD, 34.0)
			await _secs(0.2)
			_check(holds and _broken(f2), "three pistol rounds break a fence bay (two don't)")
	# --- industrial yard: chain-link and the loose stuff
	var ind: Dictionary = data.lots.filter(func(l): return l.kind == "industrial")[4]
	var ir := Rect2(float(ind.x0), float(ind.z0), float(ind.x1) - float(ind.x0), float(ind.z1) - float(ind.z0))
	await _go(Vector3(ir.position.x - 4.0, 1.0, ir.get_center().y))
	var chain := _find("chainlink_fence", Vector3(ir.position.x - 1.7, 0, ir.get_center().y), 30.0)
	_check(not chain.is_empty(), "chain-link fence along the yard")
	if not chain.is_empty():
		Explosion.blast(world, (chain[2] as Transform3D).origin + Vector3(1.5, 0.5, 0), 7.0, 10.0, null)
		await _secs(0.2)
		_check(_broken(chain), "a blast tears out a chain-link bay")
	var push := world.pushables
	_check(push != null, "pushables in the world")
	await _go(Vector3(ir.get_center().x, 1.0, ir.end.y - 6.0))
	await _secs(1.0)
	var near: Array = []
	for n in push.get_children():
		if n is Pushable and (n as Node3D).global_position.distance_to(p.global_position) < 60.0:
			near.append(n)
	_check(near.size() >= 3, "crates, drums or boxes lie in the yard (%d within 60 m, %d spots live)" % [near.size(), push._live.size()])
	await _secs(2.0)
	var resting := near.filter(func(b): return is_instance_valid(b) and (b as RigidBody3D).linear_velocity.length() < 0.3)
	_check(near.size() > 0 and resting.size() == near.size(), "they rest on the ground (%d of %d still)" % [resting.size(), near.size()])
	var under := 0
	for b in near:
		var gy := world.city.ground_y((b as Node3D).global_position.x, (b as Node3D).global_position.z)
		if (b as Node3D).global_position.y < gy:
			under += 1
	_check(under == 0, "none sunk into the ground (%d)" % under)
	# walk into a light one
	var light := near.filter(func(b): return (b as Pushable).kind in ["box", "plastic_crate", "drum", "crate"] and (b as Node3D).global_position.y < world.city.ground_y((b as Node3D).global_position.x, (b as Node3D).global_position.z) + 0.6)
	if not light.is_empty():
		var b: Pushable = light[0]
		var b0 := b.global_position
		var from := b0 + Vector3(-3.0, 0, 0)
		from.y = world.city.ground_y(from.x, from.z) + 0.1
		p._respawn(Transform3D(Basis(Vector3.UP, -PI * 0.5), from), "")
		p.cam.yaw = -PI * 0.5
		await _secs(0.5)
		Input.action_press("move_forward")
		await _secs(2.0)
		Input.action_release("move_forward")
		await _secs(0.5)
		_check(b.global_position.distance_to(b0) > 0.4, "walking into a %s shoves it (%.2f m)" % [b.kind, b.global_position.distance_to(b0)])
		# kicked
		var b1 := b.global_position
		b.melee_hit(30.0, p, Vector3(1, 0, 0))
		await _secs(1.0)
		_check(b.global_position.distance_to(b1) > 0.2, "a kick moves it (%.2f m)" % b.global_position.distance_to(b1))
		# remembered where it was left
		var left := b.global_position
		var spot_id := -1
		for id: int in push._live:
			if (push.spots[id].bodies as Array).has(b):
				spot_id = id
		await _go(Vector3(ir.get_center().x + 400.0, 1.0, ir.get_center().y))
		_check(spot_id >= 0 and not push._live.has(spot_id), "put away when the player leaves")
		await _go(Vector3(ir.get_center().x, 1.0, ir.end.y - 6.0))
		await _secs(1.0)
		var back: Array = push.spots[spot_id].bodies if spot_id >= 0 else []
		var found := false
		for nb in back:
			if is_instance_valid(nb) and (nb as Node3D).global_position.distance_to(left) < 0.25:
				found = true
		_check(found, "still where it was left on coming back")
	print("TOUCH CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
