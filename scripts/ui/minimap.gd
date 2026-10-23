class_name Minimap
extends Control
## GTA-style rotating minimap: the baked world map (assets/world/map.png) under the player, vehicle blips.

var range_m := 140.0  # metres from centre to edge
var follow_camera := true

const BG := Color(0.12, 0.14, 0.15, 0.92)


var _map: Texture2D
var _half := 2048.0


func _ready() -> void:
	clip_contents = true


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var size_px := size
	var c := size_px * 0.5
	draw_rect(Rect2(Vector2.ZERO, size_px), BG)
	var p: Player = Game.player as Player
	if not Game.world:
		return
	var focus := p.global_position
	if p.vehicle:
		focus = p.vehicle.global_position
	var yaw := p.cam.yaw if follow_camera else 0.0
	var scale_f := size_px.y * 0.5 / range_m
	var to_px := func(v: Vector2) -> Vector2:
		var d := v - Vector2(focus.x, focus.z)
		return c + Transform2D(yaw, Vector2.ZERO) * d * scale_f
	if _map == null:
		_map = load("res://assets/world/map.png")
		_half = WorldData.get_data().half
	draw_set_transform_matrix(Transform2D(yaw, c) * Transform2D(0.0, Vector2(scale_f, scale_f), 0.0, Vector2.ZERO) * Transform2D(0.0, Vector2(-focus.x, -focus.z)))
	draw_texture_rect(_map, Rect2(-_half, -_half, _half * 2.0, _half * 2.0), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# waypoint (clamped to the edge when off the map)
	var fm: FullMap = Game.world.full_map
	if fm and fm.waypoint != null:
		var wp: Vector2 = to_px.call(fm.waypoint)
		var r := Rect2(Vector2(8, 8), size_px - Vector2(16, 16))
		wp = Vector2(clampf(wp.x, r.position.x, r.end.x), clampf(wp.y, r.position.y, r.end.y))
		draw_circle(wp, 6.0, Color(0.1, 0.1, 0.1, 0.8))
		draw_circle(wp, 4.0, UITheme.SAND)
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
