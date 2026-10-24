extends Node
## Police in the real world: a crime in front of an officer gives stars, officers and cars come, the stars
## climb with more crimes, hiding out of sight outside the search area loses them, an officer next to an
## unresisting player arrests (BUSTED -> police station, weapons gone), dying ends WASTED at the hospital,
## and the respray clears the wanted level.
## godot --headless --path . res://tests/runner.tscn -- res://tests/police_check.gd

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
	Game.controls_enabled = true
	p = world.player
	await _secs(2.0)
	while not NPCDriver.is_ready("ch33_nonpbr"):
		await _secs(0.5)
	var w: Wanted = world.wanted
	_check(w.stars == 0, "starts clean")
	# an officer on the corner sees the player shoot
	var cop := w._make_cop("pistol")
	world.add_child(cop)
	cop.global_position = p.global_position + Vector3(8, 0.05, 0)
	await _secs(0.5)
	Game.crime("shooting", p.global_position)
	_check(w.stars >= 1, "shooting in front of an officer: %d star(s)" % w.stars)
	# put the gun away: one-star officers come to arrest rather than shoot
	p.weapon.select("fists")
	await _secs(3.0)
	var police := get_tree().get_nodes_in_group("police").size()
	var cars := w.units.size()
	_check(police >= 2 or cars >= 1, "the police respond (%d officers, %d cars)" % [police, cars])
	# arrest: stand still next to an officer, no gun out
	for c: Cop in w.cops:
		if is_instance_valid(c) and not world.game_over.running:
			c.global_position = p.global_position + Vector3(1.0, 0.05, 0.4)
	var t := 0.0
	while t < 10.0 and not world.game_over.running:
		await _secs(0.25)
		t += 0.25
	_check(world.game_over.running, "an officer arrests the player (BUSTED after %.1f s)" % t)
	await _secs(7.0)
	var station := world.respawn_point("police").origin
	_check(p.global_position.distance_to(station) < 4.0 and p.state == Player.State.ON_FOOT, "walks out of the police station (%.1f m)" % p.global_position.distance_to(station))
	_check(not p.weapon.has("pistol"), "weapons confiscated")
	_check(w.stars == 0, "the wanted level is gone after the arrest")
	Game.crime("attack_police", p.global_position)
	Game.crime("kill_police", p.global_position)
	_check(w.stars >= 2, "more crimes, more stars (%d)" % w.stars)
	# losing the police: out of sight far away (no new officers turn up while the test hides the player)
	for c in get_tree().get_nodes_in_group("police"):
		c.queue_free()
	for u in w.units:
		if is_instance_valid(u.car.v):
			u.car.v.queue_free()
	w.cops.clear()
	w.units.clear()
	w._spawn_t = 999.0
	w.last_seen = p.global_position + Vector3(400, 0, 0)
	w.unseen = 0.0
	t = 0.0
	while t < 40.0 and w.stars > 0:
		await _secs(0.5)
		t += 0.5
		# keep new officers from seeing the player
		w._spawn_t = 999.0
		for c in get_tree().get_nodes_in_group("police"):
			c.queue_free()
		w.cops.clear()
	_check(w.stars == 0, "out of sight and outside the search area: lost them (%.0f s)" % t)
	# wasted -> hospital
	p.take_damage(500.0)
	t = 0.0
	while t < 14.0 and p.state != Player.State.ON_FOOT:
		await _secs(0.5)
		t += 0.5
	var hosp := world.respawn_point("hospital").origin
	_check(p.state == Player.State.ON_FOOT and p.global_position.distance_to(hosp) < 4.0, "WASTED: comes round at the hospital (%.1f m, %.0f s)" % [p.global_position.distance_to(hosp), t])
	# respray: drive into the garage while wanted (nobody watching)
	Game.crime("attack_police", p.global_position)
	for c in get_tree().get_nodes_in_group("police"):
		c.queue_free()
	w.cops.clear()
	var car := Vehicle.new()
	car.model = "sedan"
	world.add_child(car)
	var r: Respray = world.get_node("Respray")
	car.global_position = Vector3(r.rect.get_center().x, 0.7, r.rect.get_center().y)
	car.rotation.y = 0.0
	await _secs(1.0)
	p.debug_seat_in(car)
	w.unseen = 5.0
	Game.money = 1000
	await _secs(2.5)
	_check(w.stars == 0 and Game.money == 1000 - Respray.PRICE, "respray clears the wanted level ($%d left)" % Game.money)
	print("POLICE CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
