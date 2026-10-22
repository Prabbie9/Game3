extends CanvasLayer
## In-game HUD: minimap with health/armor, money, weapon & ammo, crosshair, speedometer,
## vehicle name toast and notifications. Built in code with the Port Solano theme.

var _money: Label
var _ammo: Label
var _weapon: Label
var _crosshair: Control
var _speed: Label
var _speed_unit: Label
var _toast: Label
var _notify: Label
var _health_bar: ColorRect
var _armor_bar: ColorRect
var _minimap: Minimap
var _hint: Label
var _player: Player


func _ready() -> void:
	layer = 10
	Game.hud = self
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	# minimap (bottom-left) with health/armor strip underneath
	var mm_frame := Control.new()
	mm_frame.position = Vector2(36, 0)
	mm_frame.size = Vector2(300, 196)
	mm_frame.anchor_top = 1.0
	mm_frame.anchor_bottom = 1.0
	mm_frame.offset_top = -244
	mm_frame.offset_bottom = -48
	mm_frame.clip_contents = true
	root.add_child(mm_frame)
	_minimap = Minimap.new()
	_minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	mm_frame.add_child(_minimap)
	var bars := Control.new()
	bars.anchor_top = 1.0
	bars.anchor_bottom = 1.0
	bars.offset_top = -44
	bars.offset_bottom = -34
	bars.offset_left = 36
	bars.offset_right = 336
	root.add_child(bars)
	var hb_bg := ColorRect.new()
	hb_bg.color = Color(0.1, 0.2, 0.14, 0.85)
	hb_bg.position = Vector2(0, 0)
	hb_bg.size = Vector2(148, 9)
	bars.add_child(hb_bg)
	_health_bar = ColorRect.new()
	_health_bar.color = Color(0.36, 0.72, 0.42)
	_health_bar.size = Vector2(148, 9)
	bars.add_child(_health_bar)
	var ab_bg := ColorRect.new()
	ab_bg.color = Color(0.1, 0.16, 0.24, 0.85)
	ab_bg.position = Vector2(152, 0)
	ab_bg.size = Vector2(148, 9)
	bars.add_child(ab_bg)
	_armor_bar = ColorRect.new()
	_armor_bar.color = Color(0.36, 0.6, 0.9)
	_armor_bar.position = Vector2(152, 0)
	_armor_bar.size = Vector2(0, 9)
	bars.add_child(_armor_bar)

	# top-right: money, weapon, ammo
	var tr := VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -420
	tr.offset_right = -40
	tr.offset_top = 32
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(tr)
	_money = UITheme.label("$500", 40, UITheme.heading, Color(0.55, 0.85, 0.55))
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_money)
	_weapon = UITheme.label("PISTOL", 22, UITheme.heading, UITheme.PAPER)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_weapon)
	_ammo = UITheme.label("12  /  72", 22, UITheme.body_bold, UITheme.MUTED)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_ammo)

	# crosshair
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.draw.connect(func():
		_crosshair.draw_circle(Vector2.ZERO, 3.2, Color(0, 0, 0, 0.5))
		_crosshair.draw_circle(Vector2.ZERO, 2.0, Color(1, 1, 1, 0.95)))
	_crosshair.visible = false
	root.add_child(_crosshair)

	# speedometer (bottom-right)
	var sp := VBoxContainer.new()
	sp.anchor_left = 1.0
	sp.anchor_right = 1.0
	sp.anchor_top = 1.0
	sp.anchor_bottom = 1.0
	sp.offset_left = -260
	sp.offset_right = -48
	sp.offset_top = -150
	sp.offset_bottom = -40
	root.add_child(sp)
	_speed = UITheme.label("0", 64, UITheme.heading)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sp.add_child(_speed)
	_speed_unit = UITheme.label("KM/H", 16, UITheme.body_bold, UITheme.MUTED)
	_speed_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sp.add_child(_speed_unit)
	sp.visible = false
	_speed.set_meta("box", sp)

	# vehicle name toast (bottom-right, above speedo)
	_toast = UITheme.label("", 34, UITheme.heading, UITheme.PAPER)
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = -600
	_toast.offset_right = -48
	_toast.offset_top = -210
	_toast.offset_bottom = -160
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	# notifications (top-left)
	var np := PanelContainer.new()
	np.position = Vector2(36, 32)
	np.custom_minimum_size = Vector2(360, 0)
	np.modulate.a = 0.0
	root.add_child(np)
	_notify = UITheme.label("", 18)
	_notify.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notify.custom_minimum_size = Vector2(340, 0)
	np.add_child(_notify)
	_notify.set_meta("panel", np)

	# context hint (enter vehicle etc.)
	_hint = UITheme.label("", 18, UITheme.body_bold)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -120
	_hint.offset_bottom = -90
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hint)

	Game.money_changed.connect(func(m): _money.text = "$%s" % _fmt_money(m))
	Game.notify.connect(show_notification)
	_money.text = "$%s" % _fmt_money(Game.money)


func _fmt_money(m: int) -> String:
	var s := str(m)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _process(_delta: float) -> void:
	if not _player and Game.player:
		_player = Game.player as Player
		_player.weapon.ammo_changed.connect(func(a, r): _ammo.text = "%d  /  %d" % [a, r])
		_player.weapon.weapon_changed.connect(func(n):
			_weapon.text = n
			_ammo.visible = n != "FISTS")
		_player.health_changed.connect(_on_health)
		_player.vehicle_changed.connect(_on_vehicle)
		_ammo.text = "%d  /  %d" % [_player.weapon.in_mag, _player.weapon.reserve]
	if not _player:
		return
	_crosshair.visible = _player.aiming and _player.aim_weight > 0.5
	_crosshair.queue_redraw()
	var box: Control = _speed.get_meta("box")
	box.visible = _player.vehicle != null and _player.state == Player.State.DRIVING
	if box.visible:
		_speed.text = str(int(round(_player.vehicle.speed_kmh())))
	var hint := ""
	if _player.state == Player.State.ON_FOOT and _player._nearest_vehicle():
		hint = "%s  Enter vehicle" % InputPrompts.prompt("interact")
	elif _player.state == Player.State.DRIVING and _player.vehicle.linear_velocity.length() < 2.5:
		hint = "%s  Exit vehicle" % InputPrompts.prompt("interact")
	_hint.text = hint


func _on_health(h: float, a: float) -> void:
	_health_bar.size.x = 148.0 * h / 100.0
	_armor_bar.size.x = 148.0 * a / 100.0


func _on_vehicle(v: Node) -> void:
	if v:
		_toast.text = (v as Vehicle).display_name.to_upper()
		var tw := create_tween()
		tw.tween_property(_toast, "modulate:a", 1.0, 0.25)
		tw.tween_interval(2.2)
		tw.tween_property(_toast, "modulate:a", 0.0, 0.6)


func show_notification(text: String) -> void:
	_notify.text = text
	var panel: Control = _notify.get_meta("panel")
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	tw.tween_interval(4.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
