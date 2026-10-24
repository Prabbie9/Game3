extends Node
## Places to go: walking in through the safehouse door (it swings open and lets the player in), sleeping in the
## safehouse bed, a meal at the diner, and the lucky coins: thirty spread across the island, each settled on open
## ground (not inside a building), one picked up pays out, and found ones stay found after a load.
## godot --headless --path . res://tests/runner.tscn -- res://tests/places_check.gd

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


func _face(d: Vector3) -> void:
	p.rotation.y = atan2(-d.x, -d.z)
	p.cam.yaw = p.rotation.y


func _run() -> void:
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
	world.time_of_day = 23.0
	world.traffic.budget = 0
	world.wanted.process_mode = Node.PROCESS_MODE_DISABLED
	Game.controls_enabled = true
	p = world.player
	await _secs(3.0)
	_check(Game.money == 500 and Game.collected.is_empty() and Game.stats.get("shots", 0) == 0, "a new career: $%d, no coins found" % Game.money)
	# --- the safehouse: walk in through the door
	var sh := world.safehouse
	var inward := sh.global_basis * Vector3(0, 0, -1)
	var door_mid := sh.world(Vector3(sh.door_x, 0, 0))
	p._respawn(Transform3D(Basis(), door_mid - inward * 3.0 + Vector3(0, 0.1, 0)), "")
	await _secs(0.5)
	_face(inward)
	Input.action_press("move_forward")
	var widest := 0.0
	for i in 60 * 4:
		await get_tree().physics_frame
		_face(inward)
		widest = maxf(widest, sh.door._angle)
	Input.action_release("move_forward")
	var local := sh.to_local(p.global_position)
	_check(widest > deg_to_rad(80.0), "the safehouse door swings open (%.0f°)" % rad_to_deg(widest))
	_check(local.z < -2.0 and absf(local.x) < sh.width * 0.5, "walked inside the safehouse (local %s)" % local.snapped(Vector3.ONE * 0.1))
	await _secs(2.5)
	_check(sh.door._angle < 0.05, "the door closes behind (%.0f°)" % rad_to_deg(sh.door._angle))
	# --- sleep in the bed
	p._respawn(Transform3D(Basis(), sh.interact_point() + Vector3(0, 0.1, 0)), "")
	await _secs(0.5)
	p.health = 40.0
	var it := p.nearest_interactable()
	_check(it == sh and sh.interact_prompt(p) == "Sleep and save", "the bed offers sleep and save (%s)" % (it.interact_prompt(p) if it else "nothing"))
	if it == sh:
		sh.interact(p)
		_check(p.health == 100.0 and absf(world.time_of_day - 8.0) < 0.01, "slept to the morning (%.1f h), health %.0f" % [world.time_of_day, p.health])
	# --- the diner: order a meal
	var dn := world.diner
	await _secs(0.5)
	p._respawn(Transform3D(Basis(), dn.interact_point() + Vector3(0, 0.1, 0)), "")
	await _secs(1.0)
	p.health = 30.0
	Game.money = 50
	it = p.nearest_interactable()
	_check(it == dn and dn.is_open(), "the waitress takes orders (%s)" % (it.interact_prompt(p) if it else "nothing"))
	if it == dn:
		dn.interact(p)
		_check(Game.money == 50 - Diner.MEAL and p.health == 100.0, "a meal: $%d left, health %.0f" % [Game.money, p.health])
	# --- lucky coins
	var col := world.collectibles
	_check(col.spots.size() == Collectibles.COUNT and col._coins.size() == Collectibles.COUNT, "%d coins out (%d spots)" % [col._coins.size(), col.spots.size()])
	var districts := {}
	var close := 0
	for i in col.spots.size():
		districts[SaveGame.district_at(col.spots[i])] = true
		for j in i:
			if col.spots[i].distance_to(col.spots[j]) < 15.0:
				close += 1
	_check(districts.size() >= 5 and close == 0, "spread over %d districts, %d pairs bunched together" % [districts.size(), close])
	var data := WorldData.get_data()
	var bad := []
	var space := world.get_world_3d().direct_space_state
	for i in col.spots.size():
		var c: Area3D = col._coins[i]
		p._respawn(Transform3D(Basis(), col.spots[i] + Vector3(6.0, data.height_at(col.spots[i].x + 6.0, col.spots[i].z) + 1.0, 0)), "")
		var t := 0.0
		while t < 4.0 and not c.get_meta("settled"):
			await _secs(0.25)
			t += 0.25
		var ground := data.height_at(c.position.x, c.position.z)
		var q := PhysicsShapeQueryParameters3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.4
		q.shape = ball
		q.transform = Transform3D(Basis(), c.position + Vector3(0, 0.2, 0))
		q.collision_mask = 1 | 16
		var inside := space.intersect_shape(q, 4)
		var ok: bool = c.get_meta("settled") and inside.is_empty() and c.position.y - ground < 3.5
		print("      coin %d at %s (%s) ground %.1f settled %s overlaps %d" % [i, c.position.snapped(Vector3.ONE * 0.1), SaveGame.district_at(c.position), ground, c.get_meta("settled"), inside.size()])
		if not ok:
			bad.append(i)
	_check(bad.is_empty(), "every coin sits on open ground (bad: %s)" % [bad])
	# pick one up
	Game.money = 0
	var c0: Area3D = col._coins[0]
	p._respawn(Transform3D(Basis(), c0.position - Vector3(0, 0.7, 0)), "")
	await _secs(0.5)
	_check(Game.collected == [0] and Game.money == Collectibles.REWARD and not col._coins.has(0), "picked up a coin: $%d, found %s" % [Game.money, Game.collected])
	_check(Game.stat_text("lucky_coins") == "1 / %d" % Collectibles.COUNT, "stats count it (%s)" % Game.stat_text("lucky_coins"))
	# found coins stay found after loading a save (stepping away first, or coin 0 is picked up again at once)
	p._respawn(Transform3D(Basis(), c0.position + Vector3(30.0, 0, 0)), "")
	await _secs(0.3)
	Game.collected = [3, 4]
	col.refresh()
	await _secs(0.1)
	_check(col._coins.size() == Collectibles.COUNT - 2 and col._coins.has(0) and not col._coins.has(3), "a load puts back the coins not found (%d out)" % col._coins.size())
	print("PLACES CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
