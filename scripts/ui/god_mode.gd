class_name GodMode
extends CanvasLayer
## God Mode: the debug and cheat menu (F1, or GOD MODE in the pause menu). PLAYER cheats and refills, SPAWN
## vehicles / people / objects in front of the player, WORLD time and weather, TELEPORT round the map, DEBUG
## overlays, game speed and city life. The game pauses while it is open; every change applies at once.
## Cheats live in Game.cheats (not saved with the game).

const TABS := ["PLAYER", "SPAWN", "WORLD", "TELEPORT", "DEBUG"]
const ON_OFF := ["Off", "On"]
const SPEEDS := [1.0, 0.5, 0.25, 2.0]
const PEOPLE := ["Pedestrian", "Police officer"]
const OBJECTS := ["crate", "drum", "box", "plastic_crate", "cone", "ball"]
## Teleport spots: [name, world x/z]. Height comes from the ground once it has streamed in.
const SPOTS := [
	["Downtown (start)", Vector2(26.0, 9.0)], ["Playa Solano pier", Vector2(-756.0, 4.0)],
	["Playa Solano beach", Vector2(-830.0, -120.0)], ["Port of Solano", Vector2(500.0, 610.0)],
	["Eastside", Vector2(840.0, 60.0)], ["Las Lomas", Vector2(-280.0, -760.0)],
	["Mirador lookout", Vector2(840.0, -850.0)], ["Solano Fwy (north)", Vector2(0.0, -500.0)],
	["Stunt ramps: quay gap jump", Vector2(225.0, 834.0)], ["Stunt ramp: beach", Vector2(-815.0, -360.0)],
]
const DAY_RATE := 1.0 / 120.0   # World.time_scale: game hours per real second

const PAD_HOLD := 0.7   # seconds of VIEW held to open God Mode on a gamepad (a shorter tap is the camera view)

static var spawned: Array = []

var _root: Control
var _tab := 0
var _tab_buttons: Array[Button] = []
var _list: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _where: Label
var _hint: Label
var _pad_hold := 0.0
var _pad_done := false
var _vehicle_i := 0
var _person_i := 0
var _object_i := 0
var _speed_i := 0
var _settle: Node3D        # a teleported vehicle held still until the ground under it has streamed in
var _settle_t := 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("god_mode")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.visible = false
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(UITheme.INK, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var col := VBoxContainer.new()
	col.position = Vector2(110, 80)
	col.size = Vector2(1180, 920)
	col.add_theme_constant_override("separation", 10)
	_root.add_child(col)
	col.add_child(UITheme.label("GOD MODE", 64, UITheme.heading, UITheme.SAND))
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
	_scroll.custom_minimum_size = Vector2(1180, 640)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(1160, 0)
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)
	_status = UITheme.label("", 20, UITheme.body_bold, UITheme.TEAL)
	col.add_child(_status)
	_where = UITheme.label("", 16, UITheme.body, UITheme.MUTED)
	col.add_child(_where)
	_hint = UITheme.label("", 16, UITheme.body, UITheme.MUTED)
	col.add_child(_hint)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if Game.world == null or Game.player == null:
		return
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_ui("open")
	_status.text = ""
	_hint.text = "[D-PAD] choose and change   [A] do it   [LB / RB] tabs   [B] close" if Game.using_gamepad \
		else "[↑ ↓] choose   [← →] change   [ENTER] do it   [TAB] next tab   [F1 / ESC] close"
	_show_tab(_tab)


func close() -> void:
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play_ui("back")


func _toggle_open() -> void:
	var pm := get_tree().get_first_node_in_group("pause_menu")
	if is_open():
		close()
	elif not get_tree().paused and not (pm and pm.get("_root") and pm._root.visible):
		open()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("god_mode"):
		_toggle_open()
		get_viewport().set_input_as_handled()
		return
	if not is_open():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		_show_tab(posmod(_tab + (-1 if event.shift_pressed else 1), TABS.size()))
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_show_tab(posmod(_tab + (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1), TABS.size()))
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# gamepad: hold VIEW to open (or close) God Mode
	if Input.is_action_pressed("god_mode_pad"):
		_pad_hold += delta
		if _pad_hold >= PAD_HOLD and not _pad_done:
			_pad_done = true
			_toggle_open()
	else:
		_pad_hold = 0.0
		_pad_done = false
	if is_open() and Game.player:
		var p: Vector3 = Game.player.global_position
		_where.text = "Position  %.1f, %.1f, %.1f   ·   %s   ·   %s" % [p.x, p.y, p.z, _world().place_name(p), _clock(_world().time_of_day)]


func _physics_process(delta: float) -> void:
	if _settle == null or get_tree().paused:
		return
	_settle_t -= delta
	if not is_instance_valid(_settle):
		_settle = null
		return
	var at := _settle.global_position
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 3.0, 0), at + Vector3(0, -6.0, 0), 1)
	q.exclude = [(_settle as CollisionObject3D).get_rid()]
	if _settle_t <= 0.0 or not _settle.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		(_settle as RigidBody3D).freeze = false
		_settle = null


func _world() -> World:
	return Game.world as World


func _player() -> Player:
	return Game.player as Player


func _say(text: String) -> void:
	_status.text = text
	Audio.play_ui("select")


static func _clock(h: float) -> String:
	return "%02d:%02d" % [int(h) % 24, int(fposmod(h, 1.0) * 60.0)]


# --- layout ---------------------------------------------------------------------------

func _show_tab(i: int) -> void:
	_tab = i
	for k in _tab_buttons.size():
		_tab_buttons[k].add_theme_color_override("font_color", UITheme.CORAL if k == i else UITheme.PAPER)
	for c in _list.get_children():
		c.queue_free()
	match TABS[i]:
		"PLAYER":
			_player_tab()
		"SPAWN":
			_spawn_tab()
		"WORLD":
			_world_tab()
		"TELEPORT":
			_teleport_tab()
		"DEBUG":
			_debug_tab()
	_scroll.scroll_vertical = 0
	_focus_first.call_deferred()


func _focus_first() -> void:
	for row in _list.get_children():
		for c in row.get_children():
			if c is Button or c is HSlider:
				(c as Control).grab_focus()
				return


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


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 42)
	b.add_theme_font_size_override("font_size", 22)
	b.focus_entered.connect(func(): Audio.play_ui("click"))
	return b


## A value that steps through options: click / A / Enter / → for the next, ← for the previous.
func _cycle(label: String, options: Array, current: int, on_change: Callable) -> HBoxContainer:
	var h := _row(label)
	var b := _button("")
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
	return h


func _toggle(label: String, id: String, also := Callable()) -> void:
	_cycle(label, ON_OFF, 1 if Game.cheat(id) else 0, func(i: int):
		Game.cheats[id] = i == 1
		if also.is_valid():
			also.call(i == 1))


## A row with one or more action buttons: [[text, callable], ...].
func _actions(label: String, buttons: Array) -> void:
	var h := _row(label)
	for e: Array in buttons:
		var b := _button(e[0])
		if buttons.size() > 1:
			b.custom_minimum_size.x = 340.0 / buttons.size() * 1.6
		b.pressed.connect(e[1])
		h.add_child(b)


# --- PLAYER ---------------------------------------------------------------------------

func _player_tab() -> void:
	_heading("CHEATS")
	_toggle("Invincible", "invincible", func(on: bool):
		if on:
			_player().heal(100.0))
	_toggle("Infinite ammo", "infinite_ammo")
	_toggle("Never wanted", "never_wanted", func(on: bool):
		if on and _world().wanted:
			_world().wanted.clear())
	_toggle("Indestructible vehicle", "car_god")
	_heading("NOW")
	var w := _world().wanted
	_cycle("Wanted level", ["None", "★", "★★", "★★★", "★★★★", "★★★★★"], w.stars if w else 0, _set_wanted)
	_actions("Health and armour", [["FILL UP", _fill_up]])
	_actions("Weapons", [["ALL WEAPONS, FULL AMMO", _give_weapons]])
	_actions("Money", [["+ $10,000", _add_money]])
	_actions("Vehicle", [["REPAIR", _repair]])
	_heading("RESPAWN")
	_actions("Respawn", [["HERE", _respawn.bind("here")], ["START", _respawn.bind("start")], ["HOSPITAL", _respawn.bind("hospital")]])


func _fill_up() -> void:
	_player().heal(100.0)
	_player().add_armor(100.0)
	_say("Health and armour full.")


func _add_money() -> void:
	Game.money += 10000
	_say("+ $10,000")


func _repair() -> void:
	var v := _player().vehicle
	if v == null:
		_say("Not in a vehicle.")
	elif v.damage.wrecked:
		_say("That one is a wreck: spawn another.")
	else:
		v.damage.repair()
		_say("Vehicle repaired.")


func _set_wanted(i: int) -> void:
	var w := _world().wanted
	if w == null:
		return
	w.clear()
	if i > 0:
		Game.cheats["never_wanted"] = false
		w._raise(i, _player().global_position)
	_say("Wanted level %d." % i)


func _give_weapons() -> void:
	var wpn := _player().weapon
	for id: String in WeaponDefs.ORDER:
		var d := WeaponDefs.def_of(id)
		wpn.give(id, int(d.get("max", 1)) + int(d.get("mag", 0)))
	_say("Every weapon, full ammo.")


func _respawn(where: String) -> void:
	var p := _player()
	var w := _world()
	var at := Transform3D()
	match where:
		"here":
			var o := p.vehicle.global_position + p.vehicle.global_basis.x * -3.0 if p.vehicle else p.global_position
			at = Transform3D(Basis(Vector3.UP, p.cam.yaw), Vector3(o.x, w.data.height_at(o.x, o.z) + 1.0, o.z))
		"start":
			at = p.spawn_point
		"hospital":
			at = w.respawn_point("hospital")
	p._respawn(at, "")
	close()


# --- SPAWN ----------------------------------------------------------------------------

func _vehicle_models() -> Array:
	return Vehicle.SPECS.keys()


func _spawn_tab() -> void:
	var models := _vehicle_models()
	var names := models.map(func(m): return "%s  (%s)" % [String(Vehicle.SPECS[m].get("name", m)), m])
	_heading("VEHICLES")
	_cycle("Vehicle", names, _vehicle_i, func(i: int): _vehicle_i = i)
	_actions("", [["SPAWN", _spawn_vehicle.bind(false)], ["SPAWN AND DRIVE", _spawn_vehicle.bind(true)]])
	_heading("PEOPLE")
	_cycle("Person", PEOPLE, _person_i, func(i: int): _person_i = i)
	_actions("", [["SPAWN", _spawn_person]])
	_heading("OBJECTS")
	_cycle("Object", OBJECTS.map(func(o): return String(o).replace("_", " ").capitalize()), _object_i, func(i: int): _object_i = i)
	_actions("", [["SPAWN", _spawn_object]])
	_heading("TIDY UP")
	_actions("Everything spawned here", [["REMOVE", _remove_spawned]])


func _remove_spawned() -> void:
	var n := 0
	var keep := []
	for s in spawned:
		if not is_instance_valid(s):
			continue
		if s == _player().vehicle:
			keep.append(s)
		else:
			s.queue_free()
			n += 1
	spawned = keep
	_say("Removed %d." % n)


## A point `ahead` metres in front of the player (or their vehicle), on the ground.
func _ahead(ahead: float) -> Transform3D:
	var p := _player()
	var base: Node3D = p.vehicle if p.vehicle else p
	var fwd := -base.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var at := base.global_position + fwd * ahead
	at.y = _ground(at)
	return Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), at)


func _ground(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 6.0, 0), at + Vector3(0, -30.0, 0), 1)
	var hit := _player().get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if hit else maxf(_world().data.height_at(at.x, at.z), _world().data.sea)


func _spawn_vehicle(drive: bool) -> void:
	var p := _player()
	var model: String = _vehicle_models()[_vehicle_i]
	if drive and p.vehicle:
		_say("Get out of this one first.")
		return
	if drive and p.state != Player.State.ON_FOOT:
		_say("Not right now.")
		return
	var big := model in ["bus", "firetruck", "boxtruck", "heli", "speedboat"]
	var xf := _ahead(11.0 if big else 6.5)
	var v: Vehicle
	match model:
		"heli":
			v = Helicopter.new()
		"speedboat":
			var d := _world().data
			if d.height_at(xf.origin.x, xf.origin.z) > d.sea - 1.2:
				_say("A boat needs open water: face the sea.")
				return
			v = Boat.new()
			xf.origin.y = d.sea - 0.5
		"dirtbike", "bicycle":
			v = Bike.new()
		_:
			v = Vehicle.new()
	v.model = model
	_world().add_child(v)
	xf.origin.y += 0.0 if model == "speedboat" else (0.05 if model == "heli" else 0.6)
	v.global_transform = xf
	spawned.append(v)
	if drive:
		close()
		if v is Bike:
			p.global_position = v.global_position + v.global_basis.x * -1.0
			p.enter_vehicle(v)
		else:
			p.debug_seat_in(v)
	else:
		_say("Spawned a %s." % String(Vehicle.SPECS[model].get("name", model)))


func _spawn_person() -> void:
	var xf := _ahead(3.5)
	xf.basis = xf.basis.rotated(Vector3.UP, PI)   # facing the player
	var ped: Pedestrian
	if PEOPLE[_person_i] == "Police officer":
		ped = _world().wanted._make_cop("pistol")
	else:
		var ready := Population.CHARACTERS.keys().filter(func(c): return NPCDriver.is_ready(c))
		if ready.is_empty():
			_say("People are still loading.")
			return
		ped = Pedestrian.new()
		ped.character_file = ready[randi() % ready.size()]
		ped.female = Population.CHARACTERS[ped.character_file]
	_world().add_child(ped)
	ped.global_transform = Transform3D(xf.basis, xf.origin + Vector3(0, 0.05, 0))
	spawned.append(ped)
	_say("Spawned a %s." % PEOPLE[_person_i].to_lower())


func _spawn_object() -> void:
	var kind: String = OBJECTS[_object_i]
	var xf := _ahead(2.5)
	xf.origin.y += 0.3
	var rb := _world().pushables._make(kind, xf)
	rb.sleeping = false
	spawned.append(rb)
	_say("Spawned a %s." % kind.replace("_", " "))


# --- WORLD ----------------------------------------------------------------------------

func _world_tab() -> void:
	var w := _world()
	_heading("TIME")
	var h := _row("Time of day")
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 23.75
	s.step = 0.25
	s.value = snappedf(w.time_of_day, 0.25)
	s.custom_minimum_size = Vector2(360, 42)
	s.focus_mode = Control.FOCUS_ALL
	var v := UITheme.label(_clock(w.time_of_day), 20, UITheme.body_bold)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(x: float):
		v.text = _clock(x)
		w.time_of_day = x
		w._update_sun())
	h.add_child(s)
	h.add_child(v)
	_actions("Jump to", [["DAWN", _set_time.bind(6.0, s)], ["NOON", _set_time.bind(12.0, s)],
		["DUSK", _set_time.bind(19.5, s)], ["NIGHT", _set_time.bind(23.0, s)]])
	_cycle("Clock", ["Running", "Frozen"], 1 if w.time_scale == 0.0 else 0, func(i: int):
		w.time_scale = 0.0 if i == 1 else DAY_RATE)
	_heading("WEATHER")
	_cycle("Weather", Weather.NAMES, w.weather.kind, func(i: int):
		w.weather.set_weather(i, true)
		_say("%s." % Weather.NAMES[i]))
	_cycle("Weather changes by itself", ON_OFF, 1 if w.weather.auto_change else 0, func(i: int): w.weather.auto_change = i == 1)


func _set_time(hour: float, s: HSlider) -> void:
	s.value = hour   # value_changed sets the world clock
	_say("%s." % _clock(hour))


# --- TELEPORT -------------------------------------------------------------------------

func _teleport_tab() -> void:
	_heading("PLACES")
	for e: Array in SPOTS:
		_actions(e[0], [["GO", _teleport.bind(e[1])]])
	_actions("Hospital", [["GO", _teleport_building.bind("hospital")]])
	_actions("Police station", [["GO", _teleport_building.bind("police")]])
	_heading("MAP")
	_actions("Map waypoint", [["GO", _teleport_waypoint]])


func _teleport_building(kind: String) -> void:
	_teleport_xf(_world().respawn_point(kind))


func _teleport_waypoint() -> void:
	var wp: Variant = _world().full_map.waypoint if _world().full_map else null
	if wp == null:
		_say("No waypoint: set one on the map (M) first.")
	else:
		_teleport(wp as Vector2)


func _teleport(xz: Vector2) -> void:
	var y := maxf(_world().data.height_at(xz.x, xz.y), _world().data.sea) + 1.0
	_teleport_xf(Transform3D(Basis(Vector3.UP, _player().cam.yaw), Vector3(xz.x, y, xz.y)))


func _teleport_xf(xf: Transform3D) -> void:
	var p := _player()
	if p.vehicle:
		var v := p.vehicle
		v.linear_velocity = Vector3.ZERO
		v.angular_velocity = Vector3.ZERO
		v.global_transform = Transform3D(xf.basis, xf.origin + Vector3(0, 1.0, 0))
		v.freeze = true
		_settle = v
		_settle_t = 8.0
	else:
		p._respawn(xf, "")
	close()


# --- DEBUG ----------------------------------------------------------------------------

func _debug_tab() -> void:
	var w := _world()
	_heading("SCREEN")
	var perf := w.get_node_or_null("PerfOverlay") as CanvasLayer
	if perf:
		_cycle("Performance overlay (F3)", ON_OFF, 1 if perf.visible else 0, func(i: int): perf.visible = i == 1)
	_heading("SIMULATION")
	_cycle("Game speed", SPEEDS.map(func(x): return "%d%%" % int(x * 100.0)), _speed_i, func(i: int):
		_speed_i = i
		Engine.time_scale = SPEEDS[i])
	_cycle("Traffic", ON_OFF, 1 if w.traffic.budget > 0 else 0, func(i: int):
		w.traffic.budget = GraphicsSettings.traffic_cars() if i == 1 else 0)
	_cycle("Pedestrians", ON_OFF, 1 if w.population.enabled else 0, func(i: int): w.population.enabled = i == 1)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
