class_name ShopMenu
extends CanvasLayer
## Gun shop counter menu: every weapon with its price (or OWNED) and an ammo refill, plus body armour.
## Up/down (keys, D-pad or mouse) browses, the browsed weapon turns on the counter; accept buys, back closes.

const ARMOR_PRICE := 250

var shop: GunShop
var _player: Player
var _root: Control
var _list: VBoxContainer
var _info: Label
var _money: Label
var _rows: Array = []


func open(p: Player) -> void:
	_player = p
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(UITheme.INK, 0.55)
	shade.anchor_bottom = 1.0
	shade.offset_right = 640
	_root.add_child(shade)
	var col := VBoxContainer.new()
	col.position = Vector2(70, 60)
	col.add_theme_constant_override("separation", 2)
	_root.add_child(col)
	col.add_child(UITheme.label("GUNS & AMMO", 56, UITheme.heading))
	_money = UITheme.label("", 26, UITheme.heading, Color(0.55, 0.85, 0.55))
	col.add_child(_money)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	col.add_child(sp)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	col.add_child(_list)
	for id: String in WeaponDefs.ORDER:
		if id != "fists":
			_add_row(id)
	_add_row("armor")
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 16)
	col.add_child(sp2)
	_info = UITheme.label("", 17, UITheme.body, UITheme.MUTED)
	_info.custom_minimum_size = Vector2(500, 0)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_info)
	var hint := UITheme.label("%s Buy      %s Leave" % [InputPrompts.prompt("ui_accept"), InputPrompts.prompt("pause")], 17, UITheme.body_bold, UITheme.MUTED)
	col.add_child(hint)
	_refresh()
	(_rows[0][1] as Button).grab_focus()
	Audio.play_at(Audio.stream("weapons/reload_pistol.ogg"), p.global_position + Vector3(0, 1.2, 0), -12.0, 1.2)


func _add_row(id: String) -> void:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(520, 44)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(_buy.bind(id))
	b.focus_entered.connect(_focus.bind(id))
	b.mouse_entered.connect(func(): b.grab_focus())
	_list.add_child(b)
	_rows.append([id, b])


func _price(id: String) -> int:
	if id == "armor":
		return ARMOR_PRICE
	var w := _player.weapon
	var d := WeaponDefs.def_of(id)
	if not w.has(id):
		return int(d.get("price", 0))
	if d.kind == "melee":
		return -1
	return int(d.get("ammo_price", 0))


func _refresh() -> void:
	_money.text = "$%s" % _fmt(Game.money)
	var w := _player.weapon
	for r: Array in _rows:
		var id: String = r[0]
		var b: Button = r[1]
		var name := "BODY ARMOUR" if id == "armor" else String(WeaponDefs.def_of(id).name).to_upper()
		var price := _price(id)
		var right := ""
		if id == "armor":
			right = "FULL" if _player.armor >= 100.0 else "$%d" % price
		elif not w.has(id):
			right = "$%s" % _fmt(price)
		elif price < 0:
			right = "OWNED"
		elif w.ammo_full(id):
			right = "AMMO FULL"
		else:
			right = "AMMO +%d   $%d" % [int(WeaponDefs.def_of(id).ammo_pack), price]
		b.text = "%-18s %s" % [name, right]
		b.modulate = Color(1, 1, 1, 1.0 if price >= 0 and price <= Game.money else 0.55)


func _focus(id: String) -> void:
	if shop:
		shop.preview(id)
	var d := WeaponDefs.def_of(id)
	if id == "armor":
		_info.text = "Kevlar vest. Takes most of the damage from gunfire until it is used up."
		return
	var lines := []
	match String(d.kind):
		"melee":
			lines.append("Close quarters. %d damage a swing." % int(d.damage))
		"throw":
			lines.append("Three-second fuse. Throw with %s; hold %s to aim the throw." % [InputPrompts.prompt("fire"), InputPrompts.prompt("aim")])
		_:
			var dmg := int(d.damage) * int(d.get("pellets", 1))
			lines.append("%d damage per shot, %d-round magazine%s." % [dmg, int(d.mag), ", fully automatic" if d.get("auto", false) else ""])
			if d.get("zoom", 0.0) > 0.0:
				lines.append("Telescopic sight.")
			if d.get("drive_by", false):
				lines.append("Can be fired from a vehicle.")
	var w := _player.weapon
	if w.has(id) and d.kind != "melee":
		var a: Array = w.ammo[id]
		lines.append("Carrying %d." % (int(a[0]) + int(a[1])))
	_info.text = " ".join(lines)


func _buy(id: String) -> void:
	var price := _price(id)
	var w := _player.weapon
	if price < 0 or (id == "armor" and _player.armor >= 100.0) or (id != "armor" and w.has(id) and w.ammo_full(id)):
		_deny()
		return
	if Game.money < price:
		_deny()
		Game.message("Not enough money.")
		return
	Game.money -= price
	if id == "armor":
		_player.add_armor(100.0)
	else:
		var first := not w.has(id)
		w.give(id)
		if first:
			w.select(id)
	Audio.play_at(Audio.stream("weapons/reload_rifle.ogg"), _player.global_position + Vector3(0, 1.2, 0), -8.0, 1.1)
	_refresh()
	_focus(id)


func _deny() -> void:
	Audio.play_at(Audio.stream("weapons/dry_fire.ogg"), _player.global_position + Vector3(0, 1.2, 0), -6.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()


func _input(event: InputEvent) -> void:
	# the pause menu also listens for Esc/Start: leave the shop first
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if shop:
		shop.preview("")
	Game.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()


static func _fmt(m: int) -> String:
	var s := str(m)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
