class_name Minimap
extends Control
## GTA-style rotating minimap drawn from CityBuilder map data: roads, buildings, parks, blips.

var range_m := 140.0  # metres from centre to edge
var follow_camera := true

const BG := Color(0.12, 0.14, 0.15, 0.92)
const BUILDING := Color(0.27, 0.29, 0.3)
const PARK := Color(0.22, 0.34, 0.24)
const WATER := Color(0.16, 0.36, 0.48)
const ROAD := Color(0.62, 0.64, 0.66)
const ROAD_EDGE := Color(0.08, 0.09, 0.1)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var size_px := size
	var c := size_px * 0.5
	draw_rect(Rect2(Vector2.ZERO, size_px), BG)
	var p: Player = Game.player as Player
	var city: CityBuilder = Game.world.city if Game.world else null
	if not p or not city:
		return
	var focus := p.global_position
	if p.vehicle:
		focus = p.vehicle.global_position
	var yaw := p.cam.yaw if follow_camera else 0.0
	var scale_f := size_px.y * 0.5 / range_m
	var xf := Transform2D(yaw, Vector2.ZERO).scaled(Vector2(scale_f, scale_f))
	var to_px := func(v: Vector2) -> Vector2:
		var d := v - Vector2(focus.x, focus.z)
		return c + Transform2D(yaw, Vector2.ZERO) * d * scale_f
	draw_set_transform(Vector2.ZERO)
	for r in city.map_parks:
		_draw_rect_rot(r, to_px, PARK)
	for r in city.map_water:
		_draw_rect_rot(r, to_px, WATER)
	for r in city.map_buildings:
		_draw_rect_rot(r, to_px, BUILDING)
	for road in city.map_roads:
		draw_line(to_px.call(road[0]), to_px.call(road[1]), ROAD_EDGE, road[2] * scale_f + 2.0)
	for road in city.map_roads:
		draw_line(to_px.call(road[0]), to_px.call(road[1]), ROAD, road[2] * scale_f * 0.8)
	# vehicle blips
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v == p.vehicle:
			continue
		var vp: Vector2 = to_px.call(Vector2(v.global_position.x, v.global_position.z))
		if Rect2(Vector2.ZERO, size_px).has_point(vp):
			draw_circle(vp, 3.0, Color(0.55, 0.75, 0.95, 0.9))
	# player arrow (north-up rotates with camera)
	var fwd := -p.global_basis.z if not p.vehicle else -p.vehicle.global_basis.z
	var ang := atan2(fwd.x, -fwd.z) + yaw
	var pts := PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(0, 3), Vector2(-6, 7)])
	var rot := Transform2D(ang, c)
	draw_colored_polygon(rot * pts, UITheme.PAPER)
	draw_polyline(rot * (pts + PackedVector2Array([pts[0]])), Color(0, 0, 0, 0.6), 1.5)
	# north marker
	var n_dir := Transform2D(yaw, Vector2.ZERO) * Vector2(0, -1)
	var n_pos := c + n_dir * (size_px.y * 0.5 - 12.0)
	draw_circle(n_pos, 9.0, Color(UITheme.INK, 0.9))
	draw_string(UITheme.body_bold, n_pos + Vector2(-4.5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.PAPER)


func _draw_rect_rot(r: Rect2, to_px: Callable, col: Color) -> void:
	var pts := PackedVector2Array([to_px.call(r.position), to_px.call(Vector2(r.end.x, r.position.y)), to_px.call(r.end), to_px.call(Vector2(r.position.x, r.end.y))])
	draw_colored_polygon(pts, col)
