extends CanvasLayer
## Pause menu (Milestone 1 version: resume / graphics preset / quit to menu / quit).

var _root: Control
var _preset_btn: Button


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
	_root.visible = false
	_update_label()


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
	if event.is_action_pressed("pause"):
		if _root.visible:
			resume()
		else:
			_root.visible = true
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_root.get_child(1).get_child(2).grab_focus()
		get_viewport().set_input_as_handled()


func resume() -> void:
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
