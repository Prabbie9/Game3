class_name WeaponWheel
extends CanvasLayer
## Hold the wheel button (Tab / LB) on foot: time slows, a ring of the carried weapons opens and the mouse or
## right stick points at one; releasing selects it. Each slot shows the weapon's name and ammo.

static var open := false

const RADIUS := 210.0
const INNER := 90.0
const SLOW := 0.25

var _root: Control
var _ring: Control
var _label: Label
var _ammo: Label
var _items: Array = []
var _pick := -1
var _cursor := Vector2.ZERO
var _player: Player


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_ring = Control.new()
	_ring.set_anchors_preset(Control.PRESET_CENTER)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	_root.add_child(_ring)
	_label = UITheme.label("", 30, UITheme.heading, UITheme.PAPER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.size = Vector2(240, 40)
	_label.position = Vector2(-120, -30)
	_ring.add_child(_label)
	_ammo = UITheme.label("", 20, UITheme.body_bold, UITheme.MUTED)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ammo.size = Vector2(240, 30)
	_ammo.position = Vector2(-120, 8)
	_ring.add_child(_ammo)


func _process(_delta: float) -> void:
	_player = Game.player as Player
	if not _player:
		return
	var can := Game.controls_enabled and _player.state == Player.State.ON_FOOT and not get_tree().paused
	if not open and can and Input.is_action_just_pressed("weapon_wheel"):
		_open()
	elif open and (not Input.is_action_pressed("weapon_wheel") or not can):
		_close(can)
	if open:
		var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if stick.length() > 0.5:
			_cursor = stick.normalized() * RADIUS
		if _cursor.length() > INNER * 0.6:
			var a := fposmod(atan2(_cursor.x, -_cursor.y), TAU)
			var n := _items.size()
			_pick = int(round(a / (TAU / n))) % n
		_update_labels()
		_ring.queue_redraw()


func _input(event: InputEvent) -> void:
	if open and event is InputEventMouseMotion:
		_cursor += (event as InputEventMouseMotion).relative
		if _cursor.length() > RADIUS:
			_cursor = _cursor.normalized() * RADIUS
		get_viewport().set_input_as_handled()


func _open() -> void:
	open = true
	_items = _player.weapon.owned_list()
	_pick = _items.find(_player.weapon.current)
	_cursor = Vector2.ZERO
	_root.visible = true
	Engine.time_scale = SLOW
	_update_labels()


func _close(apply: bool) -> void:
	open = false
	_root.visible = false
	Engine.time_scale = 1.0
	if apply and _pick >= 0 and _pick < _items.size() and _items[_pick] != _player.weapon.current:
		_player.weapon.select(_items[_pick])
		Audio.play_at(Audio.stream("weapons/reload_pistol.ogg"), _player.global_position + Vector3(0, 1.2, 0), -14.0, 1.4)


func _update_labels() -> void:
	if _pick < 0 or _pick >= _items.size():
		_label.text = ""
		_ammo.text = ""
		return
	var id: String = _items[_pick]
	var d := WeaponDefs.def_of(id)
	_label.text = String(d.name).to_upper()
	var a: Array = _player.weapon.ammo.get(id, [0, 0])
	match String(d.kind):
		"melee":
			_ammo.text = ""
		"throw":
			_ammo.text = "x %d" % int(a[0])
		_:
			_ammo.text = "%d  /  %d" % [int(a[0]), int(a[1])]


func _draw_ring() -> void:
	var n := _items.size()
	if n == 0:
		return
	var seg := TAU / n
	for i in n:
		var a0 := i * seg - seg * 0.5 - PI * 0.5
		var sel := i == _pick
		var col := Color(0.93, 0.62, 0.2, 0.85) if sel else Color(0.08, 0.1, 0.13, 0.78)
		var pts := PackedVector2Array()
		var steps := 12
		for k in steps + 1:
			var a := a0 + seg * (0.04 + 0.92 * k / steps)
			pts.append(Vector2(cos(a), sin(a)) * RADIUS)
		for k in range(steps, -1, -1):
			var a := a0 + seg * (0.04 + 0.92 * k / steps)
			pts.append(Vector2(cos(a), sin(a)) * INNER)
		_ring.draw_colored_polygon(pts, col)
		var mid := a0 + seg * 0.5
		var c := Vector2(cos(mid), sin(mid)) * (INNER + RADIUS) * 0.5
		var id: String = _items[i]
		var font := UITheme.heading
		var txt := _short(id)
		var fs := 22
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_ring.draw_string(font, c + Vector2(-w * 0.5, 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.06, 0.06, 0.08) if sel else UITheme.PAPER)
	_ring.draw_arc(Vector2.ZERO, INNER - 4, 0, TAU, 48, Color(1, 1, 1, 0.15), 2.0)


static func _short(id: String) -> String:
	return {"fists": "FISTS", "knife": "KNIFE", "bat": "BAT", "pistol": "PISTOL", "smg": "SMG", "shotgun": "SHOTGUN",
		"rifle": "RIFLE", "sniper": "SNIPER", "launcher": "RPG", "grenade": "GRENADE"}.get(id, id.to_upper())
