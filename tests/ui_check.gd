extends Node
## Menus and persistence: rebinding (and reset), prompts following the binding, audio volume, a save / load round
## trip (position, money, weapons, ammo, stats, time, weather), the GPS route to a waypoint, every settings tab
## building its rows, the pause menu's stats and save slots.
## godot --headless --path . res://tests/runner.tscn -- res://tests/ui_check.gd

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
	Game.controls_enabled = true
	var p: Player = world.player
	await _secs(2.0)
	# --- rebinding
	var saved_bindings := Settings.bindings.duplicate(true)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	Settings.rebind("jump", k)
	_check(Settings.binding_name("jump", false) == "K", "jump rebound to K (%s)" % Settings.binding_name("jump", false))
	Game.using_gamepad = false
	_check(InputPrompts.prompt("jump") == "[K]", "prompts follow the binding (%s)" % InputPrompts.prompt("jump"))
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	Settings.rebind("jump", pad)
	_check(Settings.binding_name("jump", true) == "B" and Settings.binding_name("jump", false) == "K", "gamepad rebinding keeps the keyboard key")
	Settings.reset_bindings()
	_check(Settings.binding_name("jump", false) == "Space" and Settings.binding_name("jump", true) == "X", "reset to defaults (%s / %s)" % [Settings.binding_name("jump", false), Settings.binding_name("jump", true)])
	# --- audio
	var before: float = Settings.audio.SFX
	Settings.audio.SFX = 0.5
	Settings.apply()
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	_check(absf(db - linear_to_db(0.5)) < 0.1, "effects volume 50%% -> %.1f dB" % db)
	Settings.audio.SFX = before
	Settings.bindings = saved_bindings
	Settings.apply()
	# --- save / load
	p.global_position = Vector3(40.0, 0.2, 9.0)
	Game.money = 1234
	p.weapon.give("rifle", 75)
	p.weapon.select("rifle")
	Game.stats["kills"] = 7.0
	world.time_of_day = 21.5
	await _secs(0.5)
	var slot := SaveGame.SLOTS
	var existing := FileAccess.get_file_as_string(SaveGame.path(slot)) if FileAccess.file_exists(SaveGame.path(slot)) else ""
	_check(SaveGame.blocked_reason() == "", "saving allowed on foot, not wanted (%s)" % SaveGame.blocked_reason())
	_check(SaveGame.save(slot), "saved to slot %d" % slot)
	_check(SaveGame.describe(slot).contains("$1234"), "slot description: %s" % SaveGame.describe(slot))
	var rifle_ammo: Array = (p.weapon.ammo["rifle"] as Array).duplicate()
	# change everything, then load
	p.global_position = Vector3(-60.0, 0.2, 40.0)
	Game.money = 5
	p.weapon.confiscate()
	Game.stats["kills"] = 0.0
	world.time_of_day = 9.0
	SaveGame.apply(SaveGame.load_data(slot))
	await _secs(0.5)
	_check(p.global_position.distance_to(Vector3(40.0, 0.2, 9.0)) < 1.0, "position restored (%s)" % p.global_position.snapped(Vector3.ONE * 0.1))
	_check(Game.money == 1234, "money restored ($%d)" % Game.money)
	_check(p.weapon.has("rifle") and p.weapon.current == "rifle" and p.weapon.ammo["rifle"] == rifle_ammo, "weapons and ammo restored (%s)" % [p.weapon.ammo.get("rifle")])
	_check(int(Game.stats.get("kills", 0)) == 7, "stats restored")
	_check(absf(world.time_of_day - 21.5) < 0.01, "time of day restored")
	if existing != "":
		var f := FileAccess.open(SaveGame.path(slot), FileAccess.WRITE)
		f.store_string(existing)
	else:
		DirAccess.remove_absolute(SaveGame.path(slot))
	# saving is refused while wanted
	Game.crime("kill_police", p.global_position)
	_check(SaveGame.blocked_reason() != "", "no saving while wanted (%s)" % SaveGame.blocked_reason())
	world.wanted.clear()
	# --- GPS
	world.full_map.waypoint = Vector2(200.0, -150.0)
	world.full_map.update_route()
	var r: PackedVector3Array = world.full_map.route
	_check(r.size() >= 3 and Vector2(r[-1].x, r[-1].z).distance_to(Vector2(200.0, -150.0)) < 25.0, "GPS route to the waypoint (%d points, ends %.0f m away)" % [r.size(), Vector2(r[-1].x, r[-1].z).distance_to(Vector2(200.0, -150.0)) if r.size() > 0 else -1.0])
	var length := 0.0
	for i in range(1, r.size()):
		length += r[i - 1].distance_to(r[i])
	_check(length > 250.0 and length < 1200.0, "a sensible road route (%.0f m for %.0f m as the crow flies)" % [length, Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(200.0, -150.0))])
	p.global_position = Vector3(195.0, 0.2, -150.0)
	world.full_map.update_route()
	_check(world.full_map.waypoint == null, "arriving clears the waypoint")
	# --- settings menu tabs
	var sm := SettingsMenu.new()
	sm.world = world
	world.add_child(sm)
	await get_tree().process_frame
	for i in SettingsMenu.TABS.size():
		sm._show_tab(i)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(sm._list.get_child_count() >= 4, "settings tab %s has %d rows" % [SettingsMenu.TABS[i], sm._list.get_child_count()])
	sm.close()
	# --- pause menu panels
	var pm: CanvasLayer = load("res://scripts/ui/pause_menu.gd").new()
	world.add_child(pm)
	await get_tree().process_frame
	pm.open()
	pm._show_stats()
	await get_tree().process_frame
	_check(pm._controls.get_child_count() == Game.STAT_LABELS.size() * 2, "stats panel lists %d stats" % (pm._controls.get_child_count() / 2))
	pm._show_slots(true)
	await get_tree().process_frame
	_check(pm._panel.get_child_count() >= 3, "save slots listed")
	pm.resume()
	print("UI CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
