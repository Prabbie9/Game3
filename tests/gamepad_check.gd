extends Node
## Xbox controller: every action you need on foot and at the wheel has a pad binding, no button does two things in
## the same place, and the pad-only indicator button signals the way the stick is pushed.
## godot --headless --path . res://tests/runner.tscn -- res://tests/gamepad_check.gd

## What is read on foot / at the wheel (an action only ever acts where it applies, so the two sets may share).
const ON_FOOT := ["move_forward", "move_back", "move_left", "move_right", "look_left", "look_right", "look_up",
	"look_down", "sprint", "jump", "crouch", "interact", "reload", "cover", "aim", "fire", "weapon_wheel",
	"weapon_next", "weapon_prev", "shoulder_swap", "map", "pause"]
const DRIVING := ["accelerate", "brake", "steer_left", "steer_right", "look_left", "look_right", "look_up",
	"look_down", "handbrake", "horn", "headlights", "indicator_pad", "hazards", "camera_mode", "look_behind",
	"vehicle_aim", "vehicle_fire", "radio_next", "radio_prev", "interact", "map", "pause"]

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	_run.call_deferred()


func _pad_events(action: String) -> Array:
	return InputMap.action_get_events(action).filter(func(e): return Settings.is_pad(e))


func _key(e: InputEvent) -> String:
	if e is InputEventJoypadButton:
		return "b%d" % (e as InputEventJoypadButton).button_index
	var m := e as InputEventJoypadMotion
	return "a%d%s" % [m.axis, "+" if m.axis_value > 0.0 else "-"]


func _context(name: String, actions: Array) -> void:
	var used := {}
	var missing := []
	for a: String in actions:
		var evs := _pad_events(a)
		if evs.is_empty():
			missing.append(a)
		for e in evs:
			var k := _key(e)
			used[k] = used.get(k, []) + [a]
	var clashes := []
	for k in used:
		if used[k].size() > 1:
			clashes.append("%s: %s" % [Settings.event_name(_pad_events(used[k][0]).filter(func(e): return _key(e) == k)[0]), ", ".join(used[k])])
	_check(missing.is_empty(), "%s: every action is on the pad%s" % [name, "" if missing.is_empty() else " (missing %s)" % ", ".join(missing)])
	_check(clashes.is_empty(), "%s: no button does two things%s" % [name, "" if clashes.is_empty() else " (%s)" % "; ".join(clashes)])


func _press_a(down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_A
	e.pressed = down
	Input.parse_input_event(e)


## Press a pad button, hold it `secs` (real frames, so it works while the game is paused), release.
func _button(b: JoyButton, secs: float) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	var t := 0.0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
	var r := InputEventJoypadButton.new()
	r.button_index = b
	r.pressed = false
	Input.parse_input_event(r)
	for i in 3:
		await get_tree().process_frame


func _stick_x(v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_X
	e.axis_value = v
	Input.parse_input_event(e)


func _run() -> void:
	InputSetup.apply_defaults()
	_context("on foot", ON_FOOT)
	_context("at the wheel", DRIVING)
	_check(Settings.event_name(_pad_events("pause")[0]) == "MENU" and Settings.event_name(_pad_events("crouch")[0]) == "LS",
		"buttons carry their Xbox names (pause %s, crouch %s)" % [Settings.event_name(_pad_events("pause")[0]), Settings.event_name(_pad_events("crouch")[0])])
	# in a car: A with the stick left / right / centred
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	world.traffic.budget = 0
	Game.controls_enabled = true
	for i in 60:
		await get_tree().physics_frame
	var car := Vehicle.new()
	car.model = "sedan"
	car.position = Vector3(60.0, 0.6, -5.2)
	world.add_child(car)
	for i in 30:
		await get_tree().physics_frame
	world.player.debug_seat_in(car)
	for i in 10:
		await get_tree().physics_frame
	var want := [[-1.0, Vehicle.Blinker.LEFT, "left"], [1.0, Vehicle.Blinker.RIGHT, "right"], [0.0, Vehicle.Blinker.OFF, "off (stick centred)"]]
	for w: Array in want:
		_stick_x(w[0])
		await get_tree().physics_frame
		_press_a(true)
		for i in 3:
			await get_tree().physics_frame
		_press_a(false)
		await get_tree().physics_frame
		_check(car.indicator == w[1], "A with the stick %s: indicator %s" % ["left" if w[0] < 0 else ("right" if w[0] > 0 else "centred"), w[2]])
	_stick_x(0.0)
	# VIEW: a tap at the wheel changes the camera; held, it opens God Mode (and doesn't change the camera)
	var cam := world.player.cam
	var god: GodMode = world.get_node("GodMode")
	var view0 := cam.vehicle_view
	await _button(JOY_BUTTON_BACK, 0.15)
	_check(cam.vehicle_view != view0 and not god.is_open(), "a tap of VIEW changes the camera view (%d -> %d)" % [view0, cam.vehicle_view])
	var view1 := cam.vehicle_view
	await _button(JOY_BUTTON_BACK, 1.0)
	_check(god.is_open() and cam.vehicle_view == view1, "holding VIEW opens God Mode, camera unchanged")
	await _button(JOY_BUTTON_B, 0.1)
	_check(not god.is_open() and not get_tree().paused, "B closes it again")
	# the pause menu: MENU opens it, B backs out
	var pm := get_tree().get_first_node_in_group("pause_menu")
	if pm == null:   # (it belongs to the main scene; this test loads the world on its own)
		pm = preload("res://scripts/ui/pause_menu.gd").new()
		get_tree().root.add_child(pm)
		await get_tree().process_frame
	await _button(JOY_BUTTON_START, 0.1)
	_check(pm._root.visible and get_tree().paused, "MENU opens the pause menu")
	await _button(JOY_BUTTON_B, 0.1)
	_check(not pm._root.visible and not get_tree().paused, "B closes the pause menu")
	# helicopter: LB descends, RB climbs
	var heli := Helicopter.new()
	world.add_child(heli)
	heli.global_position = Vector3(0.0, 40.0, 0.0)   # over an avenue junction (open sky)
	world.player.debug_seat_in(heli)
	heli.rotor = 1.0   # already spun up: it hovers where it is
	for i in 120:
		await get_tree().physics_frame
	var y0 := heli.global_position.y
	await _button(JOY_BUTTON_LEFT_SHOULDER, 2.5)
	var y1 := heli.global_position.y
	_check(y1 < y0 - 6.0, "LB brings the helicopter down (%.1f m -> %.1f m)" % [y0, y1])
	for i in 90:   # (let go: it steadies into a hover)
		await get_tree().physics_frame
	var y2 := heli.global_position.y
	await _button(JOY_BUTTON_RIGHT_SHOULDER, 3.0)
	_check(heli.global_position.y > y2 + 6.0, "RB takes it up again (%.1f m -> %.1f m)" % [y2, heli.global_position.y])
	print("GAMEPAD CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
