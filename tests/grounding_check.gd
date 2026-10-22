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
		var contacts := 0
		for w in v._wheels:
			if w.is_in_contact():
				contacts += 1
		var lowest := INF
		for w in v._wheels:
			lowest = minf(lowest, w.global_position.y - w.wheel_radius)
		_check("%s wheels on road" % v.model, contacts == 4, "%d/4 contact, wheel bottom %.3f" % [contacts, lowest])
	print("GROUNDING CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)
