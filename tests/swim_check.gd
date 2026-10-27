extends Node
## Swimming in the world: wading out from the beach the player starts swimming with the head above the sea, swims
## forward offshore and treads water; the plaza pool works the same way.
## godot --headless --path . res://tests/runner.tscn -- res://tests/swim_check.gd

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
	p._respawn(Transform3D(Basis(Vector3.UP, PI * 0.5), pos), "")
	p.cam.yaw = PI * 0.5
	await _secs(0.5)
	var t := 0.0
	while t < 30.0 and not world.city.is_settled():
		await _secs(0.25)
		t += 0.25
	await _secs(0.5)


func _head() -> float:
	var sk: Skeleton3D = p.visual.skeleton
	var i := sk.find_bone("Head")
	return (sk.global_transform * sk.get_bone_global_pose(i)).origin.y


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
	var data := WorldData.get_data()
	var sea := data.sea
	# wade out from the sand west of the boardwalk (facing west, -X)
	var z := 120.0
	var x := -800.0
	while x > -1100.0 and data.height_at(x, z) > sea + 0.3:
		x -= 2.0
	var start := Vector3(x + 25.0, data.height_at(x + 25.0, z) + 0.2, z)
	await _go(start)
	_check(p.state == Player.State.ON_FOOT, "standing on the beach at %s (state %s, depth %.2f)" % [start.snapped(Vector3.ONE * 0.1), Player.State.keys()[p.state], p._water_depth()])
	Input.action_press("move_forward")
	var t := 0.0
	while t < 40.0 and p.state != Player.State.SWIM:
		await _secs(0.25)
		t += 0.25
	var at_entry := data.height_at(p.global_position.x, p.global_position.z)
	_check(p.state == Player.State.SWIM, "wading out into the sea the player starts swimming (%.0f s, water %.2f m deep)" % [t, sea - at_entry])
	await _secs(1.5)
	var wv := world.ocean.wave_height(p.global_position.x, p.global_position.z)
	_check(_head() > wv + 0.05, "head above the waves while swimming (head %.2f, water %.2f)" % [_head(), wv])
	var x0 := p.global_position.x
	await _secs(3.0)
	_check(p.state == Player.State.SWIM and absf(p.global_position.x - x0) > 1.5, "swims on offshore (%.1f m in 3 s)" % absf(p.global_position.x - x0))
	Input.action_release("move_forward")
	await _secs(2.0)
	wv = world.ocean.wave_height(p.global_position.x, p.global_position.z)
	_check(p.state == Player.State.SWIM and _head() > wv + 0.15, "treads water with the head out (head %.2f, water %.2f)" % [_head(), wv])
	# dropped into deep water offshore
	await _go(Vector3(-1150.0, sea + 1.0, 200.0))
	await _secs(1.5)
	_check(p.state == Player.State.SWIM and absf(p.global_position.y - (sea - 1.4)) < 1.0, "falls into the deep sea and swims (y %.2f)" % p.global_position.y)
	# the plaza pool
	if data.pool.size() == 4:
		var c := Vector3((float(data.pool[0]) + float(data.pool[2])) * 0.5, 0.5, (float(data.pool[1]) + float(data.pool[3])) * 0.5)
		await _go(c)
		await _secs(1.5)
		_check(p.state == Player.State.SWIM, "swims in the plaza pool (state %s)" % Player.State.keys()[p.state])
	print("SWIM CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
