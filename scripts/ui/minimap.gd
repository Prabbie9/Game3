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
	# GPS route to the waypoint
	var fm: FullMap = Game.world.full_map
	if fm and fm.route.size() >= 2:
		var pl := PackedVector2Array()
		for q in fm.route:
			pl.append(to_px.call(Vector2(q.x, q.z)))
		draw_polyline(pl, Color(0.05, 0.05, 0.06, 0.7), 6.0, true)
		draw_polyline(pl, UITheme.SAND, 3.5, true)
	# waypoint (clamped to the edge when off the map)
	if fm and fm.waypoint != null:
		var wp: Vector2 = to_px.call(fm.waypoint)
		var r := Rect2(Vector2(8, 8), size_px - Vector2(16, 16))
		wp = Vector2(clampf(wp.x, r.position.x, r.end.x), clampf(wp.y, r.position.y, r.end.y))
		draw_circle(wp, 6.0, Color(0.1, 0.1, 0.1, 0.8))
		draw_circle(wp, 4.0, UITheme.SAND)
	# places: gun shop, respray, hospital, police station (kept at the edge when off the map)
	if Game.world.has_method("places"):
		var r2 := Rect2(Vector2(10, 10), size_px - Vector2(20, 20))
		for pl: Array in Game.world.places():
			var sp: Vector2 = to_px.call(pl[0])
			sp = Vector2(clampf(sp.x, r2.position.x, r2.end.x), clampf(sp.y, r2.position.y, r2.end.y))
			draw_circle(sp, 8.0, Color(UITheme.INK, 0.9))
			var lw := UITheme.heading.get_string_size(pl[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(UITheme.heading, sp + Vector2(-lw * 0.5, 5.5), pl[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, pl[2])
	# wanted: the search area round the last sighting, police blips
	var wanted = Game.world.get("wanted")
	var flash_w := int(Time.get_ticks_msec() / 250) % 2 == 0
	if wanted and int(wanted.stars) > 0:
		if wanted.unseen > 1.5:
			var zc: Vector2 = to_px.call(Vector2(wanted.last_seen.x, wanted.last_seen.z))
			var zr: float = wanted.search_radius() * scale_f
			draw_circle(zc, zr, Color(0.9, 0.2, 0.2, 0.18) if flash_w else Color(0.2, 0.35, 0.95, 0.18))
			draw_arc(zc, zr, 0, TAU, 48, Color(1, 1, 1, 0.35), 1.5)
		for cop in get_tree().get_nodes_in_group("police"):
			var cp: Vector2 = to_px.call(Vector2(cop.global_position.x, cop.global_position.z))
			if Rect2(Vector2.ZERO, size_px).has_point(cp):
				draw_circle(cp, 3.5, Color(0.95, 0.2, 0.2) if flash_w else Color(0.25, 0.45, 1.0))
	# emergency vehicles on a call: flashing red / blue
	var flash := int(Time.get_ticks_msec() / 250) % 2 == 0
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v == p.vehicle or not (v as Vehicle).siren_on:
			continue
		var vp: Vector2 = to_px.call(Vector2(v.global_position.x, v.global_position.z))
		if Rect2(Vector2.ZERO, size_px).has_point(vp):
			draw_circle(vp, 4.0, Color(0.95, 0.2, 0.2) if flash else Color(0.25, 0.45, 1.0))
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
