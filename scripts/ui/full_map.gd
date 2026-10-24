class_name FullMap
extends CanvasLayer
## Full-screen map (M / D-pad down): the baked city map with district names, the player, vehicles and a
## waypoint (click / A to set, again to clear). Pauses the game while open. Wheel / triggers zoom, drag / stick pans.

signal waypoint_changed(pos: Variant)

var waypoint: Variant = null  # Vector2 (world x/z) or null
## GPS: the road route to the waypoint (world points), drawn here and on the minimap.
var route := PackedVector3Array()
var _route_t := 0.0
var _root: Control
var _map: Texture2D
var _data: WorldData
var _zoom := 0.35        # pixels per metre
var _center := Vector2.ZERO
var _drag := false


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_data = WorldData.get_data()
	_map = load("res://assets/world/map.png")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.draw.connect(_draw_map)
	_root.gui_input.connect(_on_input)
	_root.visible = false
	add_child(_root)


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map") or (_root.visible and event.is_action_pressed("pause")):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_root.visible = not _root.visible
	get_tree().paused = _root.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _root.visible else Input.MOUSE_MODE_CAPTURED
	if _root.visible and Game.player:
		var p: Vector3 = Game.player.global_position
		_center = Vector2(p.x, p.z)
	var hud := Game.world.get_node_or_null("HUD") as CanvasLayer if Game.world else null
	if hud:
		hud.visible = not _root.visible


func _process(delta: float) -> void:
	if not _root.visible:
		return
	var pan := Input.get_vector("look_left", "look_right", "look_up", "look_down") + Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_center += pan * delta * 500.0 / maxf(_zoom, 0.05)
	var z := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	_zoom = clampf(_zoom * (1.0 + z * delta * 1.5), 0.12, 3.0)
	if Input.is_action_just_pressed("jump"):
		_set_waypoint(_center)
	_root.queue_redraw()


func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(_zoom * 1.15, 3.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(_zoom / 1.15, 0.12)
		elif e.button_index == MOUSE_BUTTON_LEFT and e.double_click:
			_set_waypoint(_to_world(e.position))
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_set_waypoint(_to_world(e.position))
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	if e is InputEventMouseMotion and _drag:
		_center -= e.relative / _zoom


func _physics_process(delta: float) -> void:
	_route_t -= delta
	if _route_t <= 0.0:
		_route_t = 1.5
		update_route()


## Recompute the GPS route from where the player is (arrived: the waypoint goes).
func update_route() -> void:
	route = PackedVector3Array()
	var p := Game.player as Player
	var w := Game.world as World
	if waypoint == null or p == null or w == null or w.traffic == null:
		return
	var at := p.vehicle.global_position if p.vehicle else p.global_position
	var wp: Vector2 = waypoint
	if Vector2(at.x, at.z).distance_to(wp) < 22.0:
		waypoint = null
		waypoint_changed.emit(null)
		Game.message("You have reached your destination.")
		Audio.play_ui("select")
		return
	var heading := Vector3.ZERO
	if p.vehicle:
		heading = -p.vehicle.global_basis.z
		heading.y = 0.0
	route = w.traffic.gps_path(at, heading, Vector3(wp.x, 0, wp.y))


func _set_waypoint(p: Vector2) -> void:
	if waypoint != null and (waypoint as Vector2).distance_to(p) < 30.0 / _zoom:
		waypoint = null
	else:
		waypoint = p
	waypoint_changed.emit(waypoint)
	update_route()


func _to_world(px: Vector2) -> Vector2:
	return _center + (px - _root.size * 0.5) / _zoom


func _to_px(w: Vector2) -> Vector2:
	return (w - _center) * _zoom + _root.size * 0.5


func _draw_map() -> void:
	var c := _root
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.13, 0.28, 0.38))
	var h := _data.half
	c.draw_texture_rect(_map, Rect2(_to_px(Vector2(-h, -h)), Vector2(h, h) * 2.0 * _zoom), false)
	for d: Dictionary in _data.districts:
		var p := _to_px(Vector2(d.x, d.z))
		var t := String(d.name).to_upper()
		var w := UITheme.heading.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		c.draw_string(UITheme.heading, p - Vector2(w * 0.5 - 1, -1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.6))
		c.draw_string(UITheme.heading, p - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UITheme.PAPER)
	for v in get_tree().get_nodes_in_group("vehicles"):
		c.draw_circle(_to_px(Vector2(v.global_position.x, v.global_position.z)), 4.0, Color(0.55, 0.75, 0.95))
	# GPS route
	if route.size() >= 2:
		var pl := PackedVector2Array()
		for q in route:
			pl.append(_to_px(Vector2(q.x, q.z)))
		c.draw_polyline(pl, Color(0.05, 0.05, 0.06, 0.8), 7.0, true)
		c.draw_polyline(pl, UITheme.SAND, 4.0, true)
	# places + a legend in the corner
	var places: Array = Game.world.places() if Game.world and Game.world.has_method("places") else []
	for pl: Array in places:
		var pp := _to_px(pl[0])
		c.draw_circle(pp, 11.0, Color(UITheme.INK, 0.9))
		var lw := UITheme.heading.get_string_size(pl[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		c.draw_string(UITheme.heading, pp + Vector2(-lw * 0.5, 7.0), pl[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, pl[2])
	var lg := Vector2(c.size.x - 200.0, 30.0)
	c.draw_rect(Rect2(lg - Vector2(14, 14), Vector2(190, 30.0 * (places.size() + 2) + 6)), Color(UITheme.INK, 0.75))
	var rows := places.duplicate()
	rows.append([null, "", UITheme.CORAL, "You"])
	rows.append([null, "", UITheme.SAND, "Waypoint"])
	for i in rows.size():
		var row: Array = rows[i]
		var at := lg + Vector2(10, 30.0 * i + 8)
		c.draw_circle(at, 10.0, Color(0.25, 0.27, 0.3) if row[0] != null else row[2])
		if row[0] != null:
			var lw2 := UITheme.heading.get_string_size(row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			c.draw_string(UITheme.heading, at + Vector2(-lw2 * 0.5, 6.0), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, row[2])
		c.draw_string(UITheme.body_bold, at + Vector2(22, 6), row[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.PAPER)
	if waypoint != null:
		var wp := _to_px(waypoint)
		c.draw_circle(wp, 9.0, Color(0.1, 0.1, 0.1, 0.8))
		c.draw_circle(wp, 6.5, UITheme.SAND)
	if Game.player:
		var p: Vector3 = Game.player.global_position
		var fwd: Vector3 = -Game.player.global_basis.z
		var pts := PackedVector2Array([Vector2(0, -11), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)])
		var xf := Transform2D(atan2(fwd.x, -fwd.z), _to_px(Vector2(p.x, p.z)))
		c.draw_colored_polygon(xf * pts, UITheme.CORAL)
	var hint := "%s / drag  move     WHEEL  zoom     RMB  set waypoint     %s  close" % ["[L-STICK]" if Game.using_gamepad else "[WASD]", InputPrompts.prompt("map")]
	c.draw_rect(Rect2(0, c.size.y - 44, c.size.x, 44), Color(UITheme.INK, 0.8))
	c.draw_string(UITheme.body_bold, Vector2(24, c.size.y - 16), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.PAPER)
