extends CanvasLayer
## Pause menu: resume / graphics preset / quit to menu / quit, plus the controls for the current device.

const CONTROLS := [
	["ON FOOT", ""],
	["Move / sprint", "move_forward|sprint"], ["Jump, vault, climb", "jump"], ["Crouch", "crouch"], ["Take cover", "cover"],
	["Aim / shoot", "aim|fire"], ["Reload", "reload"], ["Weapon wheel (hold)", "weapon_wheel"], ["Next / previous weapon", "weapon_next|weapon_prev"],
	["Swap shoulder", "shoulder_swap"], ["Enter vehicle / use", "interact"],
	["VEHICLE", ""],
	["Accelerate / brake", "accelerate|brake"], ["Handbrake", "handbrake"], ["Horn", "horn"], ["Headlights", "headlights"],
	["Indicators / hazards", "indicator_left|indicator_right|hazards"], ["Camera view", "camera_mode"], ["Look behind", "look_behind"],
	["Shoot from the window", "aim|fire"], ["Exit vehicle", "interact"],
]

var _root: Control
var _preset_btn: Button
var _controls: GridContainer


func _ready() -> void:
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
	var col := VBoxContainer.new()
	col.position = Vector2(110, 180)
	_root.add_child(col)
	col.add_child(UITheme.label("PAUSED", 72, UITheme.heading))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	col.add_child(sp)
	_btn(col, "RESUME", resume)
	_preset_btn = _btn(col, "", _cycle_preset)
	_btn(col, "QUIT TO MENU", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	_btn(col, "QUIT GAME", func(): get_tree().quit())
	_controls = GridContainer.new()
	_controls.columns = 2
	_controls.add_theme_constant_override("h_separation", 28)
	_controls.add_theme_constant_override("v_separation", 6)
	_controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_controls.position = Vector2(-560, 200)
	_root.add_child(_controls)
	_root.visible = false
	_update_label()


func _fill_controls() -> void:
	for c in _controls.get_children():
		c.queue_free()
	for row: Array in CONTROLS:
		if row[1] == "":
			_controls.add_child(UITheme.label(row[0], 22, UITheme.heading))
			_controls.add_child(Control.new())
			continue
		var keys := []
		for a: String in String(row[1]).split("|"):
			keys.append(InputPrompts.prompt(a) if a != "move_forward" else ("[L-STICK]" if Game.using_gamepad else "[WASD]"))
		_controls.add_child(UITheme.label(row[0], 17, UITheme.body))
		_controls.add_child(UITheme.label(" ".join(keys), 17, UITheme.body_bold))


func _btn(parent: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 54)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _update_label() -> void:
	_preset_btn.text = "GRAPHICS: %s" % GraphicsSettings.PRESET_NAMES[GraphicsSettings.preset].to_upper()


func _cycle_preset() -> void:
	GraphicsSettings.set_preset((GraphicsSettings.preset + 1) % 4)
	GraphicsSettings.apply_to(Game.world)
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if Game.world and Game.world.full_map and Game.world.full_map.is_open():
		return
	if event.is_action_pressed("pause"):
		if _root.visible:
			resume()
		else:
			_root.visible = true
			_fill_controls()
			_set_hud(false)
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_root.get_child(1).get_child(2).grab_focus()
		get_viewport().set_input_as_handled()


func _set_hud(on: bool) -> void:
	var hud := Game.world.get_node_or_null("HUD") as CanvasLayer if Game.world else null
	if hud:
		hud.visible = on


func resume() -> void:
	_root.visible = false
	_set_hud(true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
