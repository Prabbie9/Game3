class_name UITheme
extends RefCounted
## Port Solano UI look: off-white on deep ink, coral highlight, teal secondary; Oswald + Inter.

const INK := Color("14161A")
const INK_2 := Color("1E2228")
const PAPER := Color("F4EFE6")
const CORAL := Color("E76F51")
const TEAL := Color("2A9D8F")
const SAND := Color("E9C46A")
const MUTED := Color(0.96, 0.94, 0.9, 0.55)

static var _theme: Theme
static var heading: Font
static var body: Font
static var body_bold: Font


static func get_theme() -> Theme:
	if _theme:
		return _theme
	heading = load("res://assets/fonts/Oswald-SemiBold.ttf")
	body = load("res://assets/fonts/Inter-Regular.ttf")
	body_bold = load("res://assets/fonts/Inter-SemiBold.ttf")
	var t := Theme.new()
	t.default_font = body
	t.default_font_size = 18
	for type in ["Label", "Button", "CheckBox", "OptionButton"]:
		t.set_color("font_color", type, PAPER)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", CORAL)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_font("font", "Button", heading)
	t.set_font_size("font_size", "Button", 30)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover := normal.duplicate()
	hover.bg_color = Color(CORAL, 0.92)
	hover.skew = Vector2(-0.18, 0)
	var focus := hover.duplicate()
	focus.bg_color = Color(CORAL, 0.75)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", hover)
	t.set_stylebox("focus", "Button", focus)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(INK, 0.86)
	panel.corner_radius_top_left = 4
	panel.corner_radius_top_right = 4
	panel.corner_radius_bottom_left = 4
	panel.corner_radius_bottom_right = 4
	panel.content_margin_left = 16
	panel.content_margin_right = 16
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12
	t.set_stylebox("panel", "PanelContainer", panel)
	_theme = t
	return t


## A big menu entry (main / pause menu) with the menu sounds.
static func menu_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 54)
	b.focus_entered.connect(func(): Audio.play_ui("click"))
	b.mouse_entered.connect(func():
		if not b.has_focus():
			b.grab_focus())
	b.pressed.connect(func():
		Audio.play_ui("select")
		cb.call())
	parent.add_child(b)
	return b


static func label(text: String, size := 18, font: Font = null, color := PAPER) -> Label:
	get_theme()
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else body)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 3)
	return l
