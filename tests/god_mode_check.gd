extends Node
## God Mode (debug menu): every tab builds, the cheats hold, and spawning / teleporting / time / weather work.
## godot --headless --path . res://tests/runner.tscn -- res://tests/god_mode_check.gd

var fails := 0
var world: World
var p: Player
var god: GodMode


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
	world.traffic.budget = 0
	Game.controls_enabled = true
	p = world.player
	god = world.get_node("GodMode")
	await _secs(3.0)
	# every tab builds
	god.open()
	_check(get_tree().paused and god.is_open(), "opens and pauses the game")
	for i in GodMode.TABS.size():
		god._show_tab(i)
		await get_tree().process_frame
		_check(god._list.get_child_count() > 2, "%s tab has rows (%d)" % [GodMode.TABS[i], god._list.get_child_count()])
	god.close()
	_check(not get_tree().paused, "closes and unpauses")
	# invincible
	Game.cheats["invincible"] = true
	p.take_damage(500.0)
	_check(p.health == 100.0 and p.state != Player.State.DEAD, "invincible: 500 damage does nothing (health %.0f)" % p.health)
	Game.cheats["invincible"] = false
	# infinite ammo
	p.weapon.give("pistol", 60)
	p.weapon.select("pistol")
	await _secs(0.5)
	var before: int = p.weapon.in_mag
	Game.cheats["infinite_ammo"] = true
	p.weapon._fire()
	_check(p.weapon.in_mag == before, "infinite ammo: firing keeps the magazine (%d -> %d)" % [before, p.weapon.in_mag])
	Game.cheats["infinite_ammo"] = false
	p.weapon._fire()
	_check(p.weapon.in_mag == before - 1, "without it a shot uses a round")
	# never wanted / set wanted
	Game.cheats["never_wanted"] = true
	world.wanted._raise(3, p.global_position)
	_check(world.wanted.stars == 0, "never wanted: a crime raises nothing")
	god._set_wanted(3)
	_check(world.wanted.stars == 3 and not Game.cheat("never_wanted"), "wanted level set to 3 (%d)" % world.wanted.stars)
	god._set_wanted(0)
	_check(world.wanted.stars == 0, "wanted level cleared")
	# weapons, money
	var cash := Game.money
	god._give_weapons()
	_check(p.weapon.owned.size() == WeaponDefs.ORDER.size(), "all weapons given (%d)" % p.weapon.owned.size())
	Game.money += 10000
	_check(Game.money == cash + 10000, "money added")
	# spawning
	var n0 := GodMode.spawned.size()
	god._vehicle_i = Vehicle.SPECS.keys().find("sedan")
	god._spawn_vehicle(false)
	god._person_i = 0
	god._spawn_person()
	god._object_i = 0
	god._spawn_object()
	await _secs(2.0)
	_check(GodMode.spawned.size() == n0 + 3, "spawned a car, a person and an object")
	var car := GodMode.spawned[n0] as Vehicle
	_check(car and car.global_position.distance_to(p.global_position) < 10.0 and car.global_position.y > p.global_position.y - 1.5,
		"the car stands in front of the player (%s)" % (car.global_position if car else Vector3.ZERO))
	# spawn and drive, then indestructible
	god._spawn_vehicle(true)
	await _secs(1.0)
	_check(p.vehicle != null and p.state == Player.State.DRIVING, "spawn and drive puts the player at the wheel")
	if p.vehicle:
		Game.cheats["car_god"] = true
		var hp: float = p.vehicle.damage.health
		p.vehicle.damage.hit(Vector3.ZERO, Vector3(0, 0, 1), 30.0)
		_check(p.vehicle.damage.health == hp, "indestructible vehicle: a 30 m/s crash does no damage")
		Game.cheats["car_god"] = false
	# teleport in a vehicle
	god._teleport(Vector2(-280.0, -760.0))
	var t := 0.0
	while t < 30.0 and not world.city.is_settled():
		await _secs(0.25)
		t += 0.25
	await _secs(3.0)
	var vp := p.vehicle.global_position if p.vehicle else p.global_position
	_check(Vector2(vp.x, vp.z).distance_to(Vector2(-280, -760)) < 6.0 and absf(vp.y - world.data.height_at(vp.x, vp.z)) < 2.5,
		"teleported with the car to Las Lomas, on the ground (%s, ground %.1f)" % [vp, world.data.height_at(vp.x, vp.z)])
	# respawn on foot there; tidy up
	god._respawn("here")
	await _secs(2.0)
	_check(p.vehicle == null and p.state == Player.State.ON_FOOT, "respawn here: on foot")
	god.open()
	god._show_tab(1)
	var rm: Button = null
	for row in god._list.get_children():
		for c in row.get_children():
			if c is Button and (c as Button).text == "REMOVE":
				rm = c
	rm.pressed.emit()
	god.close()
	await _secs(0.5)
	_check(GodMode.spawned.filter(func(s): return is_instance_valid(s) and not s.is_queued_for_deletion()).is_empty(), "remove clears everything spawned")
	# time and weather
	world.time_of_day = 23.0
	world._update_sun()
	await _secs(0.5)
	_check(world.night > 0.5, "night at 23:00 (%.2f)" % world.night)
	world.weather.set_weather(Weather.Kind.RAIN, true)
	_check(world.weather.rain > 0.3, "rain set")
	print("GOD MODE CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
