class_name SettingsMenu
extends Control
## Settings screen, opened from the main menu and the pause menu: GRAPHICS / DISPLAY / AUDIO / GAMEPLAY /
## CONTROLS. Works with mouse, keyboard and gamepad: up/down moves between rows, left/right changes a value,
## LB/RB (or the tab buttons) switch tabs, A / Enter on a binding waits for the new key or button, B / Esc goes
## back. Every change applies at once and is saved.

signal closed

const TABS := ["GRAPHICS", "DISPLAY", "AUDIO", "GAMEPLAY", "CONTROLS"]
const ON_OFF := ["Off", "On"]
const LEVELS := ["Low", "Medium", "High", "Ultra"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]
const FPS_CAPS := [30, 60, 90, 120, 144, 165, 240, 0]
## Rebindable actions: [label, action, gamepad rebindable]
const BINDABLE := [
	["ON FOOT", "", false],
	["Move forward", "move_forward", false], ["Move back", "move_back", false], ["Move left", "move_left", false],
	["Move right", "move_right", false], ["Sprint", "sprint", true], ["Jump / vault / climb", "jump", true],
	["Crouch", "crouch", true], ["Take cover", "cover", true], ["Aim", "aim", true], ["Shoot", "fire", true],
	["Reload", "reload", true], ["Weapon wheel", "weapon_wheel", true], ["Next weapon", "weapon_next", true],
	["Previous weapon", "weapon_prev", true], ["Enter vehicle / use", "interact", true],
	["Swap shoulder", "shoulder_swap", true], ["Map", "map", true], ["God Mode (debug menu)", "god_mode", false],
	["VEHICLE", "", false],
	["Accelerate", "accelerate", true], ["Brake / reverse", "brake", true], ["Steer left", "steer_left", false],
	["Steer right", "steer_right", false], ["Handbrake", "handbrake", true], ["Horn / siren", "horn", true],
	["Headlights", "headlights", true], ["Camera view", "camera_mode", true], ["Look behind", "look_behind", true],
	["Indicator left", "indicator_left", true], ["Indicator right", "indicator_right", true],
	["Hazard lights", "hazards", true], ["Aim from the window", "vehicle_aim", true],
	["Shoot from the window", "vehicle_fire", true], ["Helicopter up", "ascend", true],
	["Helicopter down", "descend", true], ["Next radio station", "radio_next", true],
	["Previous radio station", "radio_prev", true],
]

var world: Node
var _tab := 0
var _tab_buttons: Array[Button] = []
var _list: VBoxContainer
var _scroll: ScrollContainer
var _hint: Label
var _listen: Dictionary = {}   # {action, pad, button} while waiting for a new binding
var _back: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	GraphicsSettings.ensure_loaded()
	Settings.ensure_loaded()
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(UITheme.INK, 0.8)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var col := VBoxContainer.new()
	col.position = Vector2(110, 90)
	col.size = Vector2(1180, 900)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	col.add_child(UITheme.label("SETTINGS", 64, UITheme.heading))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	col.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(_show_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(1180, 700)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(1160, 0)
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 30)
	col.add_child(foot)
	_back = Button.new()
	_back.text = "BACK"
	_back.pressed.connect(close)
	foot.add_child(_back)
	_hint = UITheme.label("", 16, UITheme.body, UITheme.MUTED)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_hint)
	_show_tab(0)


func close() -> void:
	_listen = {}
	closed.emit()
	queue_free()


func _show_tab(i: int) -> void:
	_tab = i
	_listen = {}
	for k in _tab_buttons.size():
		_tab_buttons[k].add_theme_color_override("font_color", UITheme.CORAL if k == i else UITheme.PAPER)
	for c in _list.get_children():
		c.queue_free()
	match TABS[i]:
		"GRAPHICS":
			_graphics()
		"DISPLAY":
			_display()
		"AUDIO":
			_audio()
		"GAMEPLAY":
			_gameplay()
		"CONTROLS":
			_controls()
	_hint.text = _hint_text()
	_scroll.scroll_vertical = 0
	_focus_first.call_deferred()


func _hint_text() -> String:
	if Game.using_gamepad:
		return "[D-PAD] choose and change     [LB / RB] tabs     [A] rebind     [B] back"
	return "[↑ ↓] choose   [← →] change   [TAB] next tab   [ENTER] rebind   [ESC] back"


func _focus_first() -> void:
	for row in _list.get_children():
		var f := _first_focusable(row)
		if f:
			f.grab_focus()
			return
	_back.grab_focus()


func _first_focusable(n: Node) -> Control:
	if n is Control and (n as Control).focus_mode == Control.FOCUS_ALL and (n as Control).visible:
		return n
	for c in n.get_children():
		var f := _first_focusable(c)
		if f:
			return f
	return null


# --- rows -------------------------------------------------------------------------

func _row(label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(1140, 46)
	h.add_theme_constant_override("separation", 16)
	var l := UITheme.label(label, 20, UITheme.body)
	l.custom_minimum_size = Vector2(430, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	_list.add_child(h)
	return h


func _heading(text: String) -> void:
	var l := UITheme.label(text, 24, UITheme.heading, UITheme.SAND)
	l.custom_minimum_size = Vector2(0, 46)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_list.add_child(l)


func _value_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 42)
	b.add_theme_font_size_override("font_size", 22)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


## A value that steps through options: click / A / Enter / → for the next, ← for the previous.
func _cycle(label: String, options: Array, current: int, on_change: Callable) -> void:
	var h := _row(label)
	var b := _value_button("")
	var state := {"i": clampi(current, 0, options.size() - 1)}
	var refresh := func(): b.text = "‹  %s  ›" % options[state.i]
	refresh.call()
	var step := func(d: int):
		state.i = posmod(state.i + d, options.size())
		refresh.call()
		Audio.play_ui("click")
		on_change.call(state.i)
	b.pressed.connect(step.bind(1))
	b.gui_input.connect(func(e: InputEvent):
		if e.is_action_pressed("ui_left"):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right"):
			step.call(1)
			b.accept_event())
	h.add_child(b)


func _toggle(label: String, on: bool, on_change: Callable) -> void:
	_cycle(label, ON_OFF, 1 if on else 0, func(i: int): on_change.call(i == 1))


func _slider(label: String, lo: float, hi: float, step: float, value: float, fmt: Callable, on_change: Callable) -> void:
	var h := _row(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(360, 42)
	s.focus_mode = Control.FOCUS_ALL
	var v := UITheme.label(fmt.call(value), 20, UITheme.body_bold)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(x: float):
		v.text = fmt.call(x)
		on_change.call(x))
	h.add_child(s)
	h.add_child(v)


# --- tabs ---------------------------------------------------------------------------

func _graphics() -> void:
	var gs := GraphicsSettings
	var names: Array = LEVELS.duplicate()
	if gs.preset == gs.Preset.CUSTOM:
		names.append("Custom")
	_cycle("Quality preset", names, gs.preset if gs.preset != gs.Preset.CUSTOM else 4, func(i: int):
		if i < 4:
			gs.set_preset(i)
			_apply_graphics()
			_show_tab.call_deferred(_tab))
	_heading("DETAIL")
	_toggle("Global illumination", gs.values.sdfgi, func(on): _set_value("sdfgi", on))
	_toggle("Ambient occlusion", gs.values.ssao, func(on): _set_value("ssao", on))
	_toggle("Indirect light bounce", gs.values.ssil, func(on): _set_value("ssil", on))
	_toggle("Screen-space reflections", gs.values.ssr, func(on): _set_value("ssr", on))
	_toggle("Volumetric fog", gs.values.volumetric_fog, func(on): _set_value("volumetric_fog", on))
	_toggle("Bloom", gs.values.glow, func(on): _set_value("glow", on))
	var shadow_sizes := [2048, 2048, 4096, 8192]
	var shadow_filters := [1, 2, 3, 3]
	# (High and Ultra share the filter and differ in shadow map size)
	var si := maxi(shadow_filters.find(int(gs.values.shadow_filter)), 0)
	for i in shadow_sizes.size():
		if shadow_filters[i] == int(gs.values.shadow_filter) and shadow_sizes[i] == int(gs.values.shadow_size):
			si = i
	_cycle("Shadow quality", LEVELS, si, func(i: int):
		gs.values.shadow_size = shadow_sizes[i]
		_set_value("shadow_filter", shadow_filters[i]))
	var dists := [140.0, 200.0, 260.0, 380.0]
	_cycle("Shadow distance", ["140 m", "200 m", "260 m", "380 m"], _nearest(dists, float(gs.values.shadow_distance)), func(i: int): _set_value("shadow_distance", dists[i]))
	var lods := [4.0, 2.0, 1.0, 0.6]
	_cycle("Model detail", LEVELS, _nearest(lods, float(gs.values.lod_threshold)), func(i: int): _set_value("lod_threshold", lods[i]))
	var aa := 0 if gs.values.taa else (1 if gs.values.fxaa else 2)
	_cycle("Anti-aliasing", ["TAA", "FXAA", "Off"], aa, func(i: int):
		gs.values.taa = i == 0
		_set_value("fxaa", i == 1))
	_slider("Render scale", 50.0, 100.0, 5.0, float(gs.values.render_scale) * 100.0, func(x): return "%d%%" % int(x), func(x: float): _set_value("render_scale", x / 100.0))
	_cycle("Upscaling", ["FSR 1.0", "Bilinear"], 0 if gs.values.upscaler == "fsr1" else 1, func(i: int): _set_value("upscaler", "fsr1" if i == 0 else "none"))
	_heading("CITY LIFE (CPU)")
	var traffic := [8, 12, 16, 22]
	_cycle("Traffic", LEVELS, _nearest(traffic, float(gs.traffic_cars())), func(i: int): _set_value("traffic", traffic[i]))
	var crowd := [12, 18, 26, 34]
	_cycle("Pedestrians", LEVELS, _nearest(crowd, float(gs.pedestrians())), func(i: int): _set_value("crowd", crowd[i]))
	var parked := [16, 22, 30, 38]
	_cycle("Parked cars", LEVELS, _nearest(parked, float(gs.parked_cars())), func(i: int): _set_value("parked", parked[i]))


func _nearest(arr: Array, v: float) -> int:
	var best := 0
	for i in arr.size():
		if absf(float(arr[i]) - v) < absf(float(arr[best]) - v):
			best = i
	return best


## One graphics value changed by hand: the preset becomes Custom.
func _set_value(key: String, v) -> void:
	GraphicsSettings.values[key] = v
	if GraphicsSettings.preset != GraphicsSettings.Preset.CUSTOM:
		GraphicsSettings.preset = GraphicsSettings.Preset.CUSTOM
		var first := _list.get_child(0)
		var b := _first_focusable(first) as Button
		if b:
			b.text = "‹  Custom  ›"
	GraphicsSettings.save()
	_apply_graphics()


func _apply_graphics() -> void:
	if world:
		GraphicsSettings.apply_to(world)
		var w := world as World
		if w:
			w.traffic.budget = GraphicsSettings.traffic_cars()


func _display() -> void:
	var d := GraphicsSettings.display
	var modes := ["fullscreen", "borderless", "windowed"]
	_cycle("Window mode", ["Fullscreen", "Borderless", "Windowed"], maxi(modes.find(String(d.window_mode)), 0), func(i: int):
		d.window_mode = modes[i]
		_apply_display())
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(3840, 2160)
	var res: Array = RESOLUTIONS.filter(func(r: Vector2i): return r.x <= screen.x and r.y <= screen.y)
	if res.is_empty():
		res = [RESOLUTIONS[0]]
	var cur: Vector2i = d.resolution
	var ri := maxi(res.find(cur), res.find(Vector2i(1920, 1080)))
	_cycle("Window size", res.map(func(r: Vector2i): return "%d × %d" % [r.x, r.y]), maxi(ri, 0), func(i: int):
		d.resolution = res[i]
		_apply_display())
	_toggle("V-sync", d.vsync, func(on):
		d.vsync = on
		_apply_display())
	_cycle("Frame rate limit", FPS_CAPS.map(func(f): return "Unlimited" if f == 0 else "%d" % f), maxi(FPS_CAPS.find(int(d.max_fps)), 0), func(i: int):
		d.max_fps = FPS_CAPS[i]
		_apply_display())
	_slider("Field of view", 55.0, 100.0, 1.0, float(d.fov), func(x): return "%d°" % int(x), func(x: float):
		d.fov = x
		GraphicsSettings.save()
		CameraRig.fov_scale = x / 70.0)


func _apply_display() -> void:
	GraphicsSettings.save()
	GraphicsSettings.apply_display()


func _audio() -> void:
	for b: String in Settings.BUS_LABELS:
		_slider(Settings.BUS_LABELS[b], 0.0, 100.0, 5.0, float(Settings.audio[b]) * 100.0, func(x): return "%d%%" % int(x), func(x: float):
			Settings.audio[b] = x / 100.0
			Settings.apply()
			Settings.save()
			if b == "SFX" or b == "Master":
				Audio.play_ui("click"))


func _gameplay() -> void:
	var g := Settings.gameplay
	var set_g := func(k: String, v):
		g[k] = v
		Settings.apply()
		Settings.save()
	_toggle("Aim assist (gamepad)", g.aim_assist, func(on): set_g.call("aim_assist", on))
	_toggle("Blood", g.blood, func(on): set_g.call("blood", on))
	_toggle("Subtitles (police radio, calls)", g.subtitles, func(on): set_g.call("subtitles", on))
	_toggle("HUD", g.hud, func(on): set_g.call("hud", on))
	_toggle("Invert look up / down", g.invert_y, func(on): set_g.call("invert_y", on))
	_slider("Mouse sensitivity", 25.0, 300.0, 5.0, float(g.mouse_sens) * 100.0, func(x): return "%d%%" % int(x), func(x: float): set_g.call("mouse_sens", x / 100.0))
	_slider("Gamepad look speed", 25.0, 300.0, 5.0, float(g.pad_sens) * 100.0, func(x): return "%d%%" % int(x), func(x: float): set_g.call("pad_sens", x / 100.0))


func _controls() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var l0 := Control.new()
	l0.custom_minimum_size = Vector2(430, 0)
	head.add_child(l0)
	for t in ["KEYBOARD / MOUSE", "GAMEPAD"]:
		var l := UITheme.label(t, 18, UITheme.body_bold, UITheme.MUTED)
		l.custom_minimum_size = Vector2(300, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(l)
	_list.add_child(head)
	for row: Array in BINDABLE:
		if row[1] == "":
			_heading(row[0])
			continue
		var h := _row(row[0])
		for pad: bool in [false, true]:
			var b := _value_button(Settings.binding_name(row[1], pad))
			b.custom_minimum_size = Vector2(300, 42)
			if pad and not row[2]:
				b.disabled = true
				b.focus_mode = Control.FOCUS_NONE
			else:
				b.pressed.connect(_start_listen.bind(row[1], pad, b))
			h.add_child(b)
	var reset := _value_button("RESET TO DEFAULTS")
	reset.pressed.connect(func():
		Settings.reset_bindings()
		_show_tab(_tab))
	var hr := _row("")
	hr.add_child(reset)


func _start_listen(action: String, pad: bool, b: Button) -> void:
	Audio.play_ui("select")
	_listen = {"action": action, "pad": pad, "button": b, "t": Time.get_ticks_msec()}
	b.text = "PRESS A BUTTON…" if pad else "PRESS A KEY…"


func _input(event: InputEvent) -> void:
	if _listen.is_empty():
		# tab switching with the shoulder buttons / Tab
		if event is InputEventJoypadButton and event.pressed:
			if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
				_show_tab(posmod(_tab - 1, TABS.size()))
				get_viewport().set_input_as_handled()
			elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				_show_tab(posmod(_tab + 1, TABS.size()))
				get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
			_show_tab(posmod(_tab + (-1 if event.shift_pressed else 1), TABS.size()))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
			Audio.play_ui("back")
			get_viewport().set_input_as_handled()
			close()
		return
	# waiting for a new binding (ignore the press that started it)
	if Time.get_ticks_msec() - int(_listen.t) < 200:
		return
	var b: Button = _listen.button
	var e: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			b.text = Settings.binding_name(_listen.action, _listen.pad)
			_listen = {}
			get_viewport().set_input_as_handled()
			return
		e = event
	elif event is InputEventMouseButton and event.pressed:
		e = event
	elif event is InputEventJoypadButton and event.pressed:
		e = event
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6 and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		var m := InputEventJoypadMotion.new()
		m.axis = event.axis
		m.axis_value = 1.0
		e = m
	if e == null or Settings.is_pad(e) != bool(_listen.pad):
		return
	Settings.rebind(_listen.action, e)
	b.text = Settings.binding_name(_listen.action, _listen.pad)
	_listen = {}
	Audio.play_ui("click")
	get_viewport().set_input_as_handled()
