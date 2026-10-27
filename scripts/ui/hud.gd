extends CanvasLayer
## In-game HUD: minimap with health/armor, money, weapon & ammo, crosshair, speedometer,
## vehicle name toast and notifications. Built in code with the Port Solano theme.

var _money: Label
var _ammo: Label
var _weapon: Label
var _crosshair: Control
var _stars: Control
var _scope: Control
var _hit_marker := 0.0
var _speed: Label
var _speed_unit: Label
var _toast: Label
var _radio: VBoxContainer
var _radio_tween: Tween
var _notify: Label
var _subtitle: RichTextLabel
var _sub_tween: Tween
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
	# wanted stars (only while wanted)
	_stars = Control.new()
	_stars.custom_minimum_size = Vector2(380, 34)
	_stars.draw.connect(_draw_stars)
	tr.add_child(_stars)
	_weapon = UITheme.label("PISTOL", 22, UITheme.heading, UITheme.PAPER)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_weapon)
	_ammo = UITheme.label("12  /  72", 22, UITheme.body_bold, UITheme.MUTED)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_ammo)

	# crosshair
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.draw.connect(_draw_crosshair)
	_crosshair.visible = false
	root.add_child(_crosshair)
	# sniper scope: black surround with a thin reticle
	_scope = Control.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.draw.connect(_draw_scope)
	_scope.visible = false
	root.add_child(_scope)
	root.move_child(_scope, 0)

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

	# radio station (top centre)
	_radio = VBoxContainer.new()
	_radio.anchor_left = 0.5
	_radio.anchor_right = 0.5
	_radio.offset_left = -500
	_radio.offset_right = 500
	_radio.offset_top = 40
	_radio.modulate.a = 0.0
	_radio.add_theme_constant_override("separation", 0)
	root.add_child(_radio)
	var rn := UITheme.label("", 34, UITheme.heading, UITheme.SAND)
	rn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio.add_child(rn)
	var rt := UITheme.label("", 18, UITheme.body_bold, UITheme.PAPER)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio.add_child(rt)

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

	# subtitles (bottom centre)
	_subtitle = RichTextLabel.new()
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.offset_top = -200
	_subtitle.offset_bottom = -140
	_subtitle.offset_left = -520
	_subtitle.offset_right = 520
	_subtitle.add_theme_font_override("normal_font", UITheme.body)
	_subtitle.add_theme_font_override("bold_font", UITheme.body_bold)
	_subtitle.add_theme_font_size_override("normal_font_size", 22)
	_subtitle.add_theme_font_size_override("bold_font_size", 22)
	_subtitle.add_theme_constant_override("outline_size", 6)
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.modulate.a = 0.0
	root.add_child(_subtitle)
	Game.subtitle.connect(show_subtitle)

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
		_player.weapon.ammo_changed.connect(func(a, r): _ammo.text = ("x %d" % a) if r < 0 else "%d  /  %d" % [a, r])
		_player.weapon.weapon_changed.connect(func(n):
			_weapon.text = n
			_ammo.visible = not _player.weapon.is_melee())
		_weapon.text = _player.weapon.weapon_name()
		_player.health_changed.connect(_on_health)
		_player.vehicle_changed.connect(_on_vehicle)
		_ammo.text = "%d  /  %d" % [_player.weapon.in_mag, _player.weapon.reserve]
	if not _player:
		return
	_stars.queue_redraw()
	var scoped := _player.weapon.scoped()
	_scope.visible = scoped
	_crosshair.visible = _player.aiming and _player.aim_weight > 0.5 and not scoped
	_crosshair.queue_redraw()
	if scoped:
		_scope.queue_redraw()
	_hit_marker = maxf(0.0, _hit_marker - _delta)
	var box: Control = _speed.get_meta("box")
	box.visible = _player.vehicle != null and _player.state == Player.State.DRIVING
	if box.visible:
		_speed.text = str(int(round(_player.vehicle.speed_kmh())))
	var hint := ""
	var it: Node = _player.interact_target() if _player.state == Player.State.ON_FOOT else null
	if it is Vehicle:
		hint = "%s  Enter vehicle" % InputPrompts.prompt("interact")
	elif it:
		hint = "%s  %s" % [InputPrompts.prompt("interact"), it.interact_prompt(_player)]
	elif _player.state == Player.State.DRIVING and _player.vehicle is Helicopter:
		# flying: the controls stay on screen (climb / descend aren't the driving keys)
		hint = "%s Climb   %s Descend   %s Nose down / up   %s Turn" % [InputPrompts.prompt("ascend"), InputPrompts.prompt("descend"),
			_pair("accelerate", "brake"), _pair("steer_left", "steer_right")]
		if _player.vehicle.linear_velocity.length() < 2.5:
			hint += "   %s Exit" % InputPrompts.prompt("interact")
	elif _player.state == Player.State.DRIVING and _player.vehicle.linear_velocity.length() < 2.5:
		hint = "%s  Exit vehicle" % InputPrompts.prompt("interact")
	_hint.text = hint


## Two prompts as one ("[W/S]", "[RT/LT]"), or the stick on a pad for steering.
func _pair(a: String, b: String) -> String:
	if Game.using_gamepad and a == "steer_left":
		return "[L-STICK]"
	return "[%s/%s]" % [InputPrompts.prompt(a).trim_prefix("[").trim_suffix("]"), InputPrompts.prompt(b).trim_prefix("[").trim_suffix("]")]


## Crosshair: a dot, plus four ticks that open with the current spread (guns) and a hit marker.
func _draw_crosshair() -> void:
	_crosshair.draw_circle(Vector2.ZERO, 3.2, Color(0, 0, 0, 0.5))
	_crosshair.draw_circle(Vector2.ZERO, 2.0, Color(1, 1, 1, 0.95))
	if not _player:
		return
	var w := _player.weapon
	if w.data.kind == "gun" or w.data.kind == "launcher":
		var cam := get_viewport().get_camera_3d()
		var px := 6.0
		if cam:
			px += tan(w.spread()) / tan(deg_to_rad(cam.fov * 0.5)) * get_viewport().get_visible_rect().size.y * 0.5
		px = clampf(px, 6.0, 80.0)
		for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_crosshair.draw_line(d * px, d * (px + 7.0), Color(0, 0, 0, 0.5), 3.5)
			_crosshair.draw_line(d * px, d * (px + 7.0), Color(1, 1, 1, 0.9), 1.6)
	if _hit_marker > 0.0:
		var a := clampf(_hit_marker / 0.25, 0.0, 1.0)
		var c := Color(1.0, 0.35, 0.3, a) if _hit_kill else Color(1, 1, 1, a)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_crosshair.draw_line(d.normalized() * 9.0, d.normalized() * 17.0, c, 2.2)


var _hit_kill := false


## A shot connected with a character (from NPCs): flashes the hit marker, red on a kill.
func hit_marker(kill: bool) -> void:
	_hit_marker = 0.25
	_hit_kill = kill


func _draw_stars() -> void:
	var w = Game.world.get("wanted") if Game.world else null
	if w == null or int(w.stars) == 0:
		return
	var n: int = w.stars
	# out of sight: the stars blink while the police search
	var searching: bool = w.unseen > 1.5
	var on := not searching or int(Time.get_ticks_msec() / 300) % 2 == 0
	for i in 5:
		var c := Vector2(_stars.size.x - 18.0 - (4 - i) * 34.0, 17.0)
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0
			var r := 14.0 if k % 2 == 0 else 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		if i < n and on:
			_stars.draw_colored_polygon(pts, Color(0.98, 0.86, 0.3))
		pts.append(pts[0])
		_stars.draw_polyline(pts, Color(0, 0, 0, 0.7) if i < n else Color(1, 1, 1, 0.25), 2.0, true)


func _draw_scope() -> void:
	var sz := _scope.size
	var c := sz * 0.5
	var r := minf(sz.x, sz.y) * 0.46
	var black := Color(0, 0, 0, 1)
	# surround: four rects plus a ring of thick arcs to round the opening
	_scope.draw_rect(Rect2(0, 0, c.x - r, sz.y), black)
	_scope.draw_rect(Rect2(c.x + r, 0, sz.x - c.x - r, sz.y), black)
	_scope.draw_rect(Rect2(c.x - r, 0, r * 2, c.y - r), black)
	_scope.draw_rect(Rect2(c.x - r, c.y + r, r * 2, sz.y - c.y - r), black)
	var thick := r * 0.45
	_scope.draw_arc(c, r + thick * 0.5, 0, TAU, 96, black, thick, true)
	_scope.draw_arc(c, r, 0, TAU, 96, Color(0.05, 0.05, 0.05, 0.9), 3.0, true)
	var lc := Color(0.02, 0.02, 0.02, 0.9)
	_scope.draw_line(Vector2(c.x - r, c.y), Vector2(c.x - 12, c.y), lc, 2.0)
	_scope.draw_line(Vector2(c.x + 12, c.y), Vector2(c.x + r, c.y), lc, 2.0)
	_scope.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y - 12), lc, 2.0)
	_scope.draw_line(Vector2(c.x, c.y + 12), Vector2(c.x, c.y + r), lc, 2.0)
	for i in range(1, 5):
		var y := c.y + i * r * 0.12
		_scope.draw_line(Vector2(c.x - 8 + i, y), Vector2(c.x + 8 - i, y), lc, 1.5)
	_scope.draw_circle(c, 1.6, Color(0.85, 0.1, 0.1))


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


## Radio station toast: the station (or RADIO OFF) and the song.
func show_radio(station: String, song: String) -> void:
	(_radio.get_child(0) as Label).text = station
	(_radio.get_child(1) as Label).text = song
	if _radio_tween:
		_radio_tween.kill()
	_radio_tween = create_tween()
	_radio_tween.tween_property(_radio, "modulate:a", 1.0, 0.15)
	_radio_tween.tween_interval(3.5)
	_radio_tween.tween_property(_radio, "modulate:a", 0.0, 0.6)


func show_subtitle(speaker: String, text: String) -> void:
	_subtitle.text = "[center][b][color=#%s]%s:[/color][/b] %s[/center]" % [UITheme.SAND.to_html(false), speaker.to_upper(), text]
	if _sub_tween:
		_sub_tween.kill()
	_sub_tween = create_tween()
	_subtitle.modulate.a = 1.0
	_sub_tween.tween_interval(2.5 + text.length() * 0.04)
	_sub_tween.tween_property(_subtitle, "modulate:a", 0.0, 0.4)


func show_notification(text: String) -> void:
	_notify.text = text
	var panel: Control = _notify.get_meta("panel")
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	tw.tween_interval(4.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
