extends Node
## Grounding check: feet on the ground through idle/walk/run, pistol in the right hand, car wheels on the road.
## godot --headless --path . res://tests/runner.tscn -- res://tests/grounding_check.gd

var fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %-34s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	Game.controls_enabled = false
	await _frames(60)
	var p: Player = world.player
	var sk := p.visual.skeleton
	var ground := p.global_position.y
	_check("player on floor", p.is_on_floor(), "y=%.3f" % ground)

	# feet: sample the toe bones over a locomotion cycle; the lowest point each cycle must touch the ground
	for speed in [0.0, p.visual.walk_speed, p.visual.run_speed, p.visual.sprint_speed]:
		p.visual.set_locomotion(speed)
		await _frames(30)
		var min_l := 9.0
		var min_r := 9.0
		var max_drop := -9.0
		for i in 60:
			await get_tree().physics_frame
			var lt := p.visual.bone_global("LeftToes").origin.y - ground
			var rt := p.visual.bone_global("RightToes").origin.y - ground
			var lf := p.visual.bone_global("LeftFoot").origin.y - ground
			min_l = minf(min_l, minf(lt, lf))
			min_r = minf(min_r, minf(rt, p.visual.bone_global("RightFoot").origin.y - ground))
			max_drop = maxf(max_drop, -minf(lt, rt))
		var ok := absf(min_l) < 0.07 and absf(min_r) < 0.07
		_check("feet grounded @ %.1f m/s" % speed, ok, "lowest L %.3f  R %.3f m" % [min_l, min_r])

	# pistol in hand
	var hand := p.visual.bone_global("RightHand").origin
	var gun := p.weapon._model.global_position if p.weapon._model else Vector3.INF
	_check("pistol attached to hand", hand.distance_to(gun) < 0.25, "dist %.3f m" % hand.distance_to(gun))

	# vehicles: all wheels in contact, body not sunk
	await _frames(60)
	for v: Vehicle in world.get_tree().get_nodes_in_group("vehicles"):
		if v._wheels.size() != 4:
			continue  # helicopters and boats: air_sea_check
		var contacts := 0
		for w in v._wheels:
			if w.is_in_contact():
				contacts += 1
		# each tyre's visible bottom against the ground right under it
		var space := v.get_world_3d().direct_space_state
		var worst := 0.0
		var lowest := INF
		var road := 0.0
		for w: VehicleWheel3D in v._wheels:
			var bottom := w.global_position.y + Vehicle.WHEEL_SINK - w.wheel_radius   # the drawn tyre's bottom
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(w.global_position, w.global_position - Vector3(0, 2.0, 0), 1 | 16))
			var gy: float = (hit.position as Vector3).y if hit else bottom
			if absf(bottom - gy) > absf(worst):
				worst = bottom - gy
				lowest = bottom
				road = gy
		_check("%s wheels on road" % v.model, contacts == 4 and absf(worst) < 0.025, "%d/4 contact, worst tyre bottom %.3f vs ground %.3f" % [contacts, lowest, road])
	print("GROUNDING CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)
