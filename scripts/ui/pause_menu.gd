extends CanvasLayer
## Pause menu: resume / map / settings / stats / save / load / quit. The panel on the right shows the controls
## for the current device, or the stats, or the save slots.

const CONTROLS := [
	["ON FOOT", ""],
	["Move / sprint", "move_forward|sprint"], ["Jump, vault, climb", "jump"], ["Crouch", "crouch"], ["Take cover", "cover"],
	["Aim / shoot", "aim|fire"], ["Reload", "reload"], ["Weapon wheel (hold)", "weapon_wheel"], ["Next / previous weapon", "weapon_next|weapon_prev"],
	["Swap shoulder", "shoulder_swap"], ["Enter vehicle / use", "interact"], ["Map", "map"], ["God Mode (debug menu)", "god_mode"],
	["VEHICLE", ""],
	["Accelerate / brake", "accelerate|brake"], ["Handbrake", "handbrake"], ["Horn", "horn"], ["Headlights", "headlights"],
	["Indicators (pad: A, the way you steer) / hazards", "indicator_left|indicator_right|indicator_pad|hazards"], ["Camera view", "camera_mode"], ["Look behind", "look_behind"],
	["Shoot from the window", "vehicle_aim|vehicle_fire"], ["Radio station", "radio_next|radio_prev"], ["Exit vehicle", "interact"],
]

var _root: Control
var _col: VBoxContainer
var _panel: VBoxContainer
var _panel_title: Label
var _controls: GridContainer
var _settings: SettingsMenu
var _first: Button


func _ready() -> void:
	add_to_group("pause_menu")
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(UITheme.INK, 0.72)
	_root.add_child(shade)
	_col = VBoxContainer.new()
	_col.position = Vector2(110, 150)
	_root.add_child(_col)
	_col.add_child(UITheme.label("PAUSED", 72, UITheme.heading))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 24)
	_col.add_child(sp)
	_first = UITheme.menu_button(_col, "RESUME", resume)
	UITheme.menu_button(_col, "MAP", _open_map)
	UITheme.menu_button(_col, "SETTINGS", _open_settings)
	UITheme.menu_button(_col, "STATS", _show_stats)
	UITheme.menu_button(_col, "GOD MODE", _open_god_mode)
	UITheme.menu_button(_col, "SAVE GAME", _show_slots.bind(true))
	UITheme.menu_button(_col, "LOAD GAME", _show_slots.bind(false))
	UITheme.menu_button(_col, "QUIT TO MENU", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	UITheme.menu_button(_col, "QUIT GAME", func(): get_tree().quit())
	# right-hand panel
	_panel = VBoxContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-760, 170)
	_panel.custom_minimum_size = Vector2(660, 0)
	_panel.add_theme_constant_override("separation", 8)
	_root.add_child(_panel)
	_panel_title = UITheme.label("", 30, UITheme.heading, UITheme.SAND)
	_panel.add_child(_panel_title)
	_controls = GridContainer.new()
	_controls.columns = 2
	_controls.add_theme_constant_override("h_separation", 28)
	_controls.add_theme_constant_override("v_separation", 6)
	_panel.add_child(_controls)
	_root.visible = false


func _clear_panel() -> void:
	for c in _controls.get_children():
		c.queue_free()
	for c in _panel.get_children():
		if c != _panel_title and c != _controls:
			c.queue_free()


func _fill_controls() -> void:
	_clear_panel()
	_panel_title.text = "CONTROLS (%s)" % ("GAMEPAD" if Game.using_gamepad else "KEYBOARD / MOUSE")
	_controls.columns = 2
	for row: Array in CONTROLS:
		if row[1] == "":
			_controls.add_child(UITheme.label(row[0], 22, UITheme.heading))
			_controls.add_child(Control.new())
			continue
		var keys := []
		for a: String in String(row[1]).split("|"):
			# actions that only exist on the other device (pad indicator, God Mode's F1) are left out
			if a != "move_forward" and Settings.binding_name(a, Game.using_gamepad) == "—" and not (Game.using_gamepad and InputPrompts.PAD.has(a)):
				continue
			keys.append(InputPrompts.prompt(a) if a != "move_forward" else ("[L-STICK]" if Game.using_gamepad else "[%s%s%s%s]" % [Settings.binding_name("move_forward", false), Settings.binding_name("move_left", false), Settings.binding_name("move_back", false), Settings.binding_name("move_right", false)]))
		_controls.add_child(UITheme.label(row[0], 17, UITheme.body))
		_controls.add_child(UITheme.label(" ".join(keys) if not keys.is_empty() else "PAUSE MENU", 17, UITheme.body_bold))


func _show_stats() -> void:
	_clear_panel()
	_panel_title.text = "STATS"
	_controls.columns = 2
	for row: Array in Game.STAT_LABELS:
		_controls.add_child(UITheme.label(row[1], 19, UITheme.body))
		_controls.add_child(UITheme.label(Game.stat_text(row[0]), 19, UITheme.body_bold))


func _show_slots(saving: bool) -> void:
	_clear_panel()
	_panel_title.text = "SAVE GAME" if saving else "LOAD GAME"
	var reason := SaveGame.blocked_reason() if saving else ""
	if reason != "":
		_panel.add_child(UITheme.label(reason, 20, UITheme.body, UITheme.CORAL))
		return
	var first: Button = null
	for slot in range(1, SaveGame.SLOTS + 1):
		var desc := SaveGame.describe(slot)
		var b := Button.new()
		b.text = "SLOT %d   %s" % [slot, desc if desc != "" else "— empty —"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(660, 50)
		b.add_theme_font_size_override("font_size", 20)
		b.disabled = not saving and desc == ""
		b.focus_entered.connect(func(): Audio.play_ui("click"))
		b.pressed.connect(func():
			Audio.play_ui("select")
			if saving:
				if SaveGame.save(slot):
					Game.message("Saved to slot %d." % slot)
					_show_slots(true)
			else:
				_load(slot))
		_panel.add_child(b)
		if first == null and not b.disabled:
			first = b
	if first:
		first.grab_focus.call_deferred()


func _load(slot: int) -> void:
	var d := SaveGame.load_data(slot)
	if d.is_empty():
		return
	Game.pending_load = d
	Game.autoplay = true
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _open_map() -> void:
	resume()
	if Game.world and Game.world.full_map:
		Game.world.full_map._toggle()


func _open_god_mode() -> void:
	resume()
	var g := get_tree().get_first_node_in_group("god_mode") as GodMode
	if g:
		g.open()


func _open_settings() -> void:
	_col.visible = false
	_panel.visible = false
	_settings = SettingsMenu.new()
	_settings.world = Game.world
	_root.add_child(_settings)
	_settings.closed.connect(func():
		_col.visible = true
		_panel.visible = true
		_fill_controls()
		_first.grab_focus.call_deferred())


func _unhandled_input(event: InputEvent) -> void:
	if Game.world and Game.world.full_map and Game.world.full_map.is_open():
		return
	if is_instance_valid(_settings):
		return
	if event.is_action_pressed("pause") or (_root.visible and event.is_action_pressed("ui_cancel")):
		if _root.visible:
			Audio.play_ui("back")
			resume()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_root.visible = true
	_col.visible = true
	_panel.visible = true
	_fill_controls()
	_set_hud(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_ui("open")
	_first.grab_focus()


func _set_hud(on: bool) -> void:
	var hud := Game.world.get_node_or_null("HUD") as CanvasLayer if Game.world else null
	if hud:
		hud.visible = on and bool(Settings.gameplay.hud)


func resume() -> void:
	if is_instance_valid(_settings):
		_settings.close()
	_root.visible = false
	_set_hud(true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
