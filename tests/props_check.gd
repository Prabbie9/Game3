extends Node
## Street furniture: a car knocks a lamp post over (its light goes out), a hydrant bursts into a jet that lifts a
## car, the player kicks a bin over, a blast throws props, an ATM gives up cash after a beating; using a vending
## machine, sitting on a bench (and getting up), paying a payphone favour to drop a star.
## godot --headless --path . res://tests/runner.tscn -- res://tests/props_check.gd

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


## Nearest live instance of a city prop: [StaticBody3D, shape index, global transform] or [].
func _find(name: String, near: Vector3, maxd := 200.0, skip := []) -> Array:
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
				var xf: Transform3D = (cs as CollisionShape3D).global_transform
				var d := xf.origin.distance_to(near)
				if not cs.disabled and d < bd and not skip.has(xf.origin):
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
	_check(props != null, "props system in the world")
	# --- lamp post: drive into it
	var lamp := _find("street_lamp_01", p.global_position)
	_check(not lamp.is_empty(), "a lamp post near the start")
	if not lamp.is_empty():
		var base: Vector3 = (lamp[2] as Transform3D).origin
		var cell: Node = (lamp[0] as Node).get_parent()
		var lamp_lights := func() -> int:
			return (cell.get_meta("lights", []) as Array).filter(func(lp): return Vector2(lp.x - base.x, lp.z - base.z).length() < 0.8).size()
		var lights_before: int = lamp_lights.call()
		var car := Vehicle.new()
		car.model = "sedan"
		world.add_child(car)
		var side := (lamp[2] as Transform3D).basis.z
		side.y = 0.0
		side = side.normalized()   # lamps face the road
		var along := Vector3(-side.z, 0, side.x)
		# in the road beside the kerb, the car's flank lined up with the post, driven straight at speed
		car.global_position = base + side * 0.85 - along * 22.0 + Vector3(0, 0.8, 0)
		car.rotation.y = atan2(-along.x, -along.z)
		await _secs(0.5)
		p.debug_seat_in(car)
		await _secs(0.5)
		car.set_driver_input_enabled(false)
		car.ai_drive = true
		car.ai_throttle = 1.0
		var t := 0.0
		while t < 5.0 and not _broken(lamp):
			await _secs(0.1)
			t += 0.1
			if int(t * 10) % 5 == 0:
				print("      car %s speed %.1f lamp %s" % [car.global_position.snapped(Vector3.ONE * 0.1), car.linear_velocity.length(), base.snapped(Vector3.ONE * 0.1)])
		_check(_broken(lamp), "a car knocks the lamp post over (%.1f s)" % t)
		car.ai_throttle = 0.0
		car.ai_brake = 1.0
		await _secs(1.0)
		_check(lights_before == 1 and lamp_lights.call() == 0, "its light goes out (%d -> %d)" % [lights_before, lamp_lights.call()])
		p._respawn(p.spawn_point, "")
		car.queue_free()
		await _secs(0.5)
	# --- hydrant: shoot it, then park a car over the jet
	var hyd := _find("fire_hydrant", p.global_position)
	if hyd.is_empty():
		hyd = _find("fire_hydrant_aged", p.global_position)
	_check(not hyd.is_empty(), "a hydrant near the start")
	if not hyd.is_empty():
		var hp: Vector3 = (hyd[2] as Transform3D).origin
		props.on_hit({"collider": hyd[0], "shape": hyd[1], "position": hp + Vector3(0, 0.5, 0)}, Vector3.FORWARD, 30.0)
		await _secs(0.3)
		var jets := props.get_children().filter(func(n): return n is HydrantJet)
		_check(_broken(hyd) and jets.size() == 1, "a shot hydrant bursts into a jet")
		var car2 := Vehicle.new()
		car2.model = "compact"
		world.add_child(car2)
		car2.global_position = hp + Vector3(0, 1.2, 0)
		await _secs(2.5)
		_check(car2.global_position.y > hp.y + 2.0, "the jet lifts a car (%.1f m up)" % (car2.global_position.y - hp.y))
		car2.queue_free()
	# --- bin: walk into it
	var bin := _find("metal_trash_can", p.global_position)
	if bin.is_empty():
		bin = _find("metal_trash_can_rust", p.global_position)
	_check(not bin.is_empty(), "a bin near the start")
	if not bin.is_empty():
		var bp: Vector3 = (bin[2] as Transform3D).origin
		p.global_position = bp + Vector3(2.0, 0.1, 0)
		p.rotation.y = PI * 0.5
		p.cam.yaw = p.rotation.y
		print("      teleported to %s state %s vehicle %s" % [p.global_position, p.state, p.vehicle])
		await get_tree().physics_frame
		print("      one frame later %s" % p.global_position)
		await _secs(0.3)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		var t2 := 0.0
		while t2 < 3.0 and not _broken(bin):
			await _secs(0.1)
			t2 += 0.1
			if int(t2 * 10) % 5 == 0:
				print("      player %s vel %s bin %s slides %d" % [p.global_position.snapped(Vector3.ONE * 0.1), p.velocity.snapped(Vector3.ONE * 0.1), bp.snapped(Vector3.ONE * 0.1), p.get_slide_collision_count()])
		Input.action_release("move_forward")
		Input.action_release("sprint")
		_check(_broken(bin), "running into a bin knocks it over (%.1f s)" % t2)
	# --- blast
	var target := _find("metal_trash_can", p.global_position + Vector3(60, 0, 0), 400.0)
	if not target.is_empty():
		Explosion.blast(world, (target[2] as Transform3D).origin + Vector3(1.0, 0.3, 0), 8.0, 10.0, null)
		await _secs(0.2)
		_check(_broken(target), "an explosion throws props")
	# --- ATM
	var atm := _find("atm", p.global_position, 600.0)
	_check(not atm.is_empty(), "ATMs in the city")
	if not atm.is_empty():
		var ap: Vector3 = (atm[2] as Transform3D).origin
		var cash_before := get_tree().get_nodes_in_group("pickups").size() + world.get_children().filter(func(n): return n is Pickup).size()
		for i in 5:
			props.on_hit({"collider": atm[0], "shape": atm[1], "position": ap + Vector3(0, 1, 0)}, Vector3.FORWARD, 30.0)
		await _secs(0.3)
		var cash := world.get_children().filter(func(n): return n is Pickup and n.kind == Pickup.Kind.CASH and n.global_position.distance_to(ap) < 4.0)
		_check(_broken(atm) and cash.size() >= 2, "a battered ATM spills cash (%d bundles)" % cash.size())
	# --- using things: vending machine, bench, payphone
	for kind: String in ["vending_machine", "bench", "payphone"]:
		var f := _find(kind, p.global_position, 600.0)
		if f.is_empty():
			_check(false, "a %s in the city" % kind)
			continue
		var xf: Transform3D = f[2]
		var front := xf.basis.z
		front.y = 0.0
		p.global_position = xf.origin + front.normalized() * 0.9 + Vector3(0, 0.3, 0)
		await _secs(1.0)
		print("      %s at %s player %s uses %d" % [kind, xf.origin.snapped(Vector3.ONE * 0.1), p.global_position.snapped(Vector3.ONE * 0.1), props._uses.size()])
		match kind:
			"vending_machine":
				Game.money = 100
				p.health = 50.0
				var it := p.nearest_interactable()
				_check(it is PropUse and it.kind == kind, "vending machine offers a drink (%s)" % (it.interact_prompt(p) if it else "nothing"))
				if it:
					it.interact(p)
				_check(Game.money == 95 and p.health > 60.0, "a drink: $%d left, health %.0f" % [Game.money, p.health])
			"bench":
				var it := p.nearest_interactable()
				_check(it is PropUse and it.kind == kind, "bench: sit down")
				if it:
					it.interact(p)
				await _secs(1.0)
				_check(p.state == Player.State.ACTION and p.current_action() == "sit", "sitting on the bench")
				Input.action_press("move_forward")
				await _secs(0.3)
				Input.action_release("move_forward")
				await _secs(0.5)
				_check(p.current_action() != "sit", "gets up when moving off (%s)" % p.current_action())
				await _secs(1.5)
			"payphone":
				world.wanted.process_mode = Node.PROCESS_MODE_INHERIT
				Game.crime("kill_police", p.global_position)
				var stars := world.wanted.stars
				Game.money = 2000
				var it := p.nearest_interactable()
				_check(it is PropUse, "payphone offers a favour while wanted (%s)" % (it.interact_prompt(p) if it else "nothing"))
				if it:
					it.interact(p)
				_check(world.wanted.stars == stars - 1 and Game.money == 2000 - PropUse.FAVOUR * stars, "a star dropped (%d -> %d, $%d)" % [stars, world.wanted.stars, Game.money])
				world.wanted.clear()
				world.wanted.process_mode = Node.PROCESS_MODE_DISABLED
	print("PROPS CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
