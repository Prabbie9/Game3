class_name CityBuilder
extends Node3D
## Builds the Milestone-1 city slice procedurally (deterministic): a 3x3 road grid with intersections,
## curbed sidewalks, four city blocks of facade-shaded buildings, rooftop clutter and street props.

const TEX := "res://assets/textures/polyhaven/%s/%s.jpg"
const ROAD_LINES := [-80.0, 0.0, 80.0]
const ROAD_W := {0.0: 14.0, -80.0: 12.0, 80.0: 12.0}
const EXTENT := 110.0
const SIDEWALK := 4.0
const CURB_H := 0.15

var rng := RandomNumberGenerator.new()
var _mat_cache := {}
var _static: StaticBody3D
var props_root: Node3D
## 2D map data (x/z metres) for the minimap and full map.
var map_roads := []      # [Vector2 a, Vector2 b, float width]
var map_buildings := []  # Rect2
var map_parks := []      # Rect2


func _ready() -> void:
	build()


func build() -> void:
	rng.seed = 1977
	_static = StaticBody3D.new()
	_static.name = "Collision"
	_static.collision_layer = 1
	add_child(_static)
	props_root = Node3D.new()
	props_root.name = "Props"
	add_child(props_root)
	_build_ground()
	_build_roads()
	_build_blocks()
	_build_outer_ring()


# ---------------------------------------------------------------- materials

func _tex(name: String, map: String) -> Texture2D:
	return load(TEX % [name, map])


func _pbr(name: String, tile: float, tint := Color.WHITE) -> ShaderMaterial:
	var key := "pbr_%s_%s_%s" % [name, tile, tint]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/world_pbr.gdshader")
	m.set_shader_parameter("albedo_tex", _tex(name, "albedo"))
	m.set_shader_parameter("normal_tex", _tex(name, "normal"))
	m.set_shader_parameter("arm_tex", _tex(name, "arm"))
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_mat_cache[key] = m
	return m


func _road_mat(width: float, length: float, lanes: int, cw_start: bool, cw_end: bool, markings := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/road.gdshader")
	m.set_shader_parameter("albedo_tex", _tex("asphalt_02", "albedo"))
	m.set_shader_parameter("normal_tex", _tex("asphalt_02", "normal"))
	m.set_shader_parameter("arm_tex", _tex("asphalt_02", "arm"))
	m.set_shader_parameter("road_width", width)
	m.set_shader_parameter("road_length", length)
	m.set_shader_parameter("lanes_per_side", lanes)
	m.set_shader_parameter("center_line", markings)
	m.set_shader_parameter("lane_lines", markings and lanes > 1)
	m.set_shader_parameter("edge_lines", markings)
	if cw_start:
		m.set_shader_parameter("crosswalk_start", 0.6)
		m.set_shader_parameter("crosswalk_end", 3.8)
		m.set_shader_parameter("stop_line_at", 4.6)
	return m


# ---------------------------------------------------------------- geometry helpers

## Quad with UVs given per corner; corners counter-clockwise seen from the normal side
## (emitted clockwise, which is Godot's front-face winding).
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for v in [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]:
		st.set_uv(v[1])
		st.add_vertex(v[0])


func _mesh(st: SurfaceTool, mat: Material, name := "Mesh", shadows := true) -> MeshInstance3D:
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _box_col(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = Transform3D(basis, center)
	_static.add_child(cs)


func _road_w(line: float) -> float:
	return ROAD_W.get(line, 12.0)


# ---------------------------------------------------------------- ground & roads

func _build_ground() -> void:
	# a single slab under everything (roads sit at y = 0)
	_box_col(Vector3(0, -0.5, 0), Vector3(EXTENT * 2 + 60, 1.0, EXTENT * 2 + 60))


func _build_roads() -> void:
	var st_int := SurfaceTool.new()
	st_int.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: float in ROAD_LINES:
		for z: float in ROAD_LINES:
			var hx := _road_w(x) * 0.5
			var hz := _road_w(z) * 0.5
			quad(st_int, Vector3(x - hx, 0, z + hz), Vector3(x + hx, 0, z + hz), Vector3(x + hx, 0, z - hz), Vector3(x - hx, 0, z - hz),
				Vector2(x - hx, z + hz), Vector2(x + hx, z + hz), Vector2(x + hx, z - hz), Vector2(x - hx, z - hz))
	_mesh(st_int, _road_mat(14.0, 14.0, 2, false, false, false), "Intersections", false)

	# segments between intersections and out to the edge, along X (fixed z) and along Z (fixed x)
	var stops := [-EXTENT] + ROAD_LINES + [EXTENT]
	for line: float in ROAD_LINES:
		var w := _road_w(line)
		for i in stops.size() - 1:
			var s0: float = stops[i]
			var s1: float = stops[i + 1]
			var a0 := s0 + (_road_w(s0) * 0.5 if ROAD_LINES.has(s0) else 0.0)
			var a1 := s1 - (_road_w(s1) * 0.5 if ROAD_LINES.has(s1) else 0.0)
			for axis: int in [0, 1]:
				_road_segment(axis, line, a0, a1, w, ROAD_LINES.has(s0), ROAD_LINES.has(s1))


## axis 0: road runs along +X at z = line; axis 1: runs along +Z at x = line.
func _road_segment(axis: int, line: float, a0: float, a1: float, w: float, cw0: bool, cw1: bool) -> void:
	var length := a1 - a0
	var ext := w * 0.5
	if axis == 0:
		map_roads.append([Vector2(a0 - ext, line), Vector2(a1 + ext, line), w])
	else:
		map_roads.append([Vector2(line, a0 - ext), Vector2(line, a1 + ext), w])
	var lanes := 2 if w >= 14.0 else 1
	# build in local (along, across) and map to world; two halves so each end gets its own crosswalk
	for half: int in [0, 1]:
		var b0 := a0 + length * 0.5 * half
		var b1 := b0 + length * 0.5
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var p := func(along: float, across: float) -> Vector3:
			return Vector3(along, 0, line - w * 0.5 + across) if axis == 0 else Vector3(line + w * 0.5 - across, 0, along)
		# UV.y measured from this half's intersection end so the crosswalk lands at the junction
		var flip: bool = half == 1
		var u := func(along: float, across: float) -> Vector2:
			var a: float = (b1 - along) if flip else (along - b0)
			return Vector2(w - across if flip else across, a)
		quad(st, p.call(b0, w), p.call(b1, w), p.call(b1, 0.0), p.call(b0, 0.0),
			u.call(b0, w), u.call(b1, w), u.call(b1, 0.0), u.call(b0, 0.0))
		var cw := cw0 if half == 0 else cw1
		var mi := _mesh(st, _road_mat(w, length * 0.5, lanes, cw, false), "Road", false)
		mi.set_meta("surface", 0)
	# sidewalks + curbs on both sides
	for side: float in [-1.0, 1.0]:
		var c0 := w * 0.5
		var c1 := w * 0.5 + SIDEWALK
		_sidewalk_strip(axis, line, a0, a1, side, c0, c1)


func _sidewalk_strip(axis: int, line: float, a0: float, a1: float, side: float, c0: float, c1: float) -> void:
	# extend into the intersection corners so sidewalks wrap around
	# only the X-running strips wrap the corners (Z strips stop at the corner) to avoid overlapping quads
	var e0 := a0 - SIDEWALK if a0 > -EXTENT + 1 and axis == 0 else a0
	var e1 := a1 + SIDEWALK if a1 < EXTENT - 1 and axis == 0 else a1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var P := func(along: float, off: float, y: float) -> Vector3:
		return Vector3(along, y, line + off * side) if axis == 0 else Vector3(line + off * side, y, along)
	var top0: Vector3 = P.call(e0, c0, CURB_H)
	# top surface
	var verts := [P.call(e0, c0, CURB_H), P.call(e1, c0, CURB_H), P.call(e1, c1, CURB_H), P.call(e0, c1, CURB_H)]
	var uvs := []
	for v in verts:
		uvs.append(Vector2(v.x, v.z))
	if (side > 0) == (axis == 0):
		quad(st, verts[0], verts[3], verts[2], verts[1], uvs[0], uvs[3], uvs[2], uvs[1])
	else:
		quad(st, verts[0], verts[1], verts[2], verts[3], uvs[0], uvs[1], uvs[2], uvs[3])
	_mesh(st, _pbr("concrete_pavement", 2.5, Color(0.92, 0.9, 0.86)), "Sidewalk", false)
	# curb face
	var cs := SurfaceTool.new()
	cs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var f0: Vector3 = P.call(a0, c0, 0.0)
	var f1: Vector3 = P.call(a1, c0, 0.0)
	var g0: Vector3 = P.call(a0, c0, CURB_H)
	var g1: Vector3 = P.call(a1, c0, CURB_H)
	var len := a1 - a0
	if (side > 0) == (axis == 0):
		quad(cs, f0, g0, g1, f1, Vector2(0, 0), Vector2(0, CURB_H), Vector2(len, CURB_H), Vector2(len, 0))
	else:
		quad(cs, f0, f1, g1, g0, Vector2(0, 0), Vector2(len, 0), Vector2(len, CURB_H), Vector2(0, CURB_H))
	_mesh(cs, _pbr("concrete_pavement", 1.0, Color(0.8, 0.79, 0.76)), "Curb", false)
	# collision: slab + a gentle invisible ramp at the curb so characters and cars mount it smoothly
	var mid_off := (c0 + c1) * 0.5
	var size := Vector3(e1 - e0, CURB_H, c1 - c0) if axis == 0 else Vector3(c1 - c0, CURB_H, e1 - e0)
	_box_col(P.call((e0 + e1) * 0.5, mid_off, CURB_H * 0.5), size)
	var ramp_len := 0.5
	var ang := atan2(CURB_H, ramp_len)
	var ramp_size := Vector3(a1 - a0, 0.05, ramp_len / cos(ang)) if axis == 0 else Vector3(ramp_len / cos(ang), 0.05, a1 - a0)
	var tilt := Basis(Vector3.RIGHT, -ang * side) if axis == 0 else Basis(Vector3.FORWARD, -ang * side)
	_box_col(P.call((a0 + a1) * 0.5, c0 - ramp_len * 0.5, CURB_H * 0.5 - 0.025), ramp_size, tilt)
	_street_props(axis, line, a0, a1, side, c0, c1)


func _street_props(axis: int, line: float, a0: float, a1: float, side: float, c0: float, c1: float) -> void:
	var P := func(along: float, off: float) -> Vector3:
		return Vector3(along, CURB_H, line + off * side) if axis == 0 else Vector3(line + off * side, CURB_H, along)
	# facing the road: yaw that points the prop's -Z towards the roadway
	var face_road := (PI if side > 0 else 0.0) if axis == 0 else (PI * 0.5 if side > 0 else -PI * 0.5)
	var length := a1 - a0
	if length < 12.0:
		return
	# palms along the kerb between the lamps
	var n_palms := int(length / 16.0)
	for i in n_palms:
		var at := a0 + (i + 0.5) * length / n_palms + 4.0
		if at < a1 - 3.0 and rng.randf() < 0.75:
			_palm(P.call(at, c0 + 0.9), i)
	var n_lamps := maxi(1, int(length / 24.0))
	for i in n_lamps:
		var at := a0 + (i + 0.5) * length / n_lamps
		_prop("street_lamp_01", P.call(at, c0 + 0.45), face_road)
	var along := a0 + 6.0
	while along < a1 - 4.0:
		var roll := rng.randf()
		if roll < 0.18:
			_prop("fire_hydrant", P.call(along, c0 + 0.5), face_road + rng.randf_range(-0.3, 0.3))
		elif roll < 0.38:
			_prop("metal_trash_can", P.call(along, c1 - 0.6), rng.randf() * TAU)
		elif roll < 0.48:
			_prop("utility_box_01" if rng.randf() < 0.5 else "utility_box_02", P.call(along, c1 - 0.5), face_road + PI)
		elif roll < 0.58:
			_prop("modular_street_seating", P.call(along, c1 - 0.8), face_road + PI)
		along += rng.randf_range(7.0, 13.0)


# ---------------------------------------------------------------- blocks & buildings

func _build_blocks() -> void:
	var edges := []
	for i in ROAD_LINES.size() - 1:
		var l0: float = ROAD_LINES[i]
		var l1: float = ROAD_LINES[i + 1]
		edges.append([l0 + _road_w(l0) * 0.5 + SIDEWALK, l1 - _road_w(l1) * 0.5 - SIDEWALK])
	var kinds := [["downtown", "plaza"], ["midrise", "commercial"]]
	for bx in edges.size():
		for bz in edges.size():
			var x0: float = edges[bx][0]
			var x1: float = edges[bx][1]
			var z0: float = edges[bz][0]
			var z1: float = edges[bz][1]
			_fill_block(Rect2(x0, z0, x1 - x0, z1 - z0), kinds[bx][bz])


func _fill_block(r: Rect2, kind: String) -> void:
	# block ground (pavement between buildings / alleys)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := CURB_H
	quad(st, Vector3(r.position.x, y, r.end.y), Vector3(r.end.x, y, r.end.y), Vector3(r.end.x, y, r.position.y), Vector3(r.position.x, y, r.position.y),
		Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.position.y))
	_mesh(st, _pbr("concrete_pavement", 3.0, Color(0.8, 0.78, 0.74)), "BlockGround", false)
	_box_col(Vector3(r.get_center().x, y * 0.5, r.get_center().y), Vector3(r.size.x, y, r.size.y))

	var hw := r.size.x * 0.5
	var hd := r.size.y * 0.5
	var lots := [Rect2(r.position, Vector2(hw - 2.5, hd - 2.5)), Rect2(r.position + Vector2(hw + 2.5, 0), Vector2(hw - 2.5, hd - 2.5)),
		Rect2(r.position + Vector2(0, hd + 2.5), Vector2(hw - 2.5, hd - 2.5)), Rect2(r.position + Vector2(hw + 2.5, hd + 2.5), Vector2(hw - 2.5, hd - 2.5))]
	match kind:
		"downtown":
			_building(Rect2(r.position, Vector2(r.size.x, hd - 2.5)), 15, "concrete_tile_facade", Color(0.95, 0.95, 0.97), true, Color(0.55, 0.62, 0.68))
			_building(lots[2], 9, "brick_wall_09", Color(0.95, 0.88, 0.82), true)
			_building(lots[3], 11, "plastered_wall_02", Color(0.86, 0.9, 0.92), true)
		"plaza":
			_building(lots[0], 6, "white_stucco", Color(0.98, 0.9, 0.78), true)
			_building(lots[1], 4, "brick_wall_09", Color(1, 1, 1), true)
			_building(lots[2], 7, "plastered_wall_02", Color(1.0, 0.86, 0.74), true)
			_plaza(lots[3])
		"midrise":
			_building(lots[0], 5, "white_stucco", Color(0.86, 0.93, 0.9), true)
			_building(lots[1], 6, "brick_wall_09", Color(0.9, 0.85, 0.82), true)
			_building(lots[2], 4, "white_stucco", Color(1.0, 0.93, 0.82), true)
			_building(lots[3], 8, "plastered_wall_02", Color(0.95, 0.92, 0.86), true)
		"commercial":
			_building(Rect2(r.position, Vector2(r.size.x, hd - 2.5)), 2, "white_stucco", Color(0.96, 0.87, 0.76), true)
			_building(lots[2], 3, "brick_wall_09", Color(0.92, 0.82, 0.78), true)
			_building(lots[3], 2, "plastered_wall_02", Color(0.86, 0.92, 0.95), true)


const SIGN_COLORS := [Color(0.16, 0.45, 0.42), Color(0.7, 0.25, 0.18), Color(0.15, 0.2, 0.3), Color(0.55, 0.42, 0.2), Color(0.35, 0.18, 0.32)]


func _building(lot: Rect2, floors: int, wall: String, tint: Color, storefront: bool, glass := Color(0.55, 0.66, 0.72)) -> void:
	var base_y := CURB_H
	var height := 4.2 + float(floors - 1) * 3.3 + 1.2
	var x0 := lot.position.x
	var x1 := lot.end.x
	var z0 := lot.position.y
	var z1 := lot.end.y
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/facade.gdshader")
	mat.set_shader_parameter("wall_albedo", _tex(wall, "albedo"))
	mat.set_shader_parameter("wall_normal", _tex(wall, "normal"))
	mat.set_shader_parameter("wall_arm", _tex(wall, "arm"))
	mat.set_shader_parameter("wall_tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("wall_tile", 3.5 if wall != "concrete_tile_facade" else 6.0)
	mat.set_shader_parameter("building_height", height)
	mat.set_shader_parameter("storefront", storefront)
	mat.set_shader_parameter("seed", rng.randf() * 100.0)
	mat.set_shader_parameter("sign_color", SIGN_COLORS[rng.randi() % SIGN_COLORS.size()])
	mat.set_shader_parameter("glass_tint", Vector3(glass.r, glass.g, glass.b))
	var tall := floors >= 10
	mat.set_shader_parameter("bay_width", 2.6 if tall else rng.randf_range(2.9, 3.6))
	mat.set_shader_parameter("window_size", Vector2(2.1, 2.3) if tall else Vector2(rng.randf_range(1.1, 1.6), rng.randf_range(1.5, 1.9)))
	mat.set_shader_parameter("sill_height", 0.6 if tall else 0.95)
	var frame: Color = [Color(0.92, 0.91, 0.88), Color(0.25, 0.25, 0.26), Color(0.55, 0.38, 0.28)][rng.randi() % 3]
	mat.set_shader_parameter("frame_color", Vector3(frame.r, frame.g, frame.b))

	# four facades: each gets its own UV run (x = metres along the facade); one mesh, one material instance per face
	var faces := [
		[Vector3(x0, 0, z1), Vector3(x1, 0, z1)],  # south (+z)
		[Vector3(x1, 0, z1), Vector3(x1, 0, z0)],  # east (+x)
		[Vector3(x1, 0, z0), Vector3(x0, 0, z0)],  # north (-z)
		[Vector3(x0, 0, z0), Vector3(x0, 0, z1)],  # west (-x)
	]
	for f in faces:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var w := a.distance_to(b)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y0 := Vector3(0, base_y, 0)
		var y1 := Vector3(0, base_y + height, 0)
		quad(st, a + y0, b + y0, b + y1, a + y1, Vector2(0, 0), Vector2(w, 0), Vector2(w, height), Vector2(0, height))
		var m: ShaderMaterial = mat.duplicate()
		m.set_shader_parameter("facade_width", w)
		m.set_shader_parameter("seed", rng.randf() * 100.0)
		_mesh(st, m, "Facade")
	# cornice band + roof
	_roof(lot, base_y + height, tall)
	map_buildings.append(lot)
	_box_col(Vector3(lot.get_center().x, base_y + height * 0.5, lot.get_center().y), Vector3(lot.size.x, height, lot.size.y))


func _roof(lot: Rect2, top: float, tall: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o := 0.35  # cornice overhang
	var t := 0.45
	var r := lot.grow(o)
	var y0 := top - t
	var y1 := top
	# top
	quad(st, Vector3(r.position.x, y1, r.end.y), Vector3(r.end.x, y1, r.end.y), Vector3(r.end.x, y1, r.position.y), Vector3(r.position.x, y1, r.position.y),
		Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.position.y))
	# underside + sides of the cornice slab
	quad(st, Vector3(r.position.x, y0, r.position.y), Vector3(r.end.x, y0, r.position.y), Vector3(r.end.x, y0, r.end.y), Vector3(r.position.x, y0, r.end.y),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	var c := [Vector3(r.position.x, 0, r.end.y), Vector3(r.end.x, 0, r.end.y), Vector3(r.end.x, 0, r.position.y), Vector3(r.position.x, 0, r.position.y)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var w := a.distance_to(b)
		quad(st, a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), b + Vector3(0, y1, 0), a + Vector3(0, y1, 0), Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1))
	_mesh(st, _pbr("concrete_pavement", 2.0, Color(0.72, 0.71, 0.69)), "Roof")
	# rooftop clutter: AC units
	var n := 2 + rng.randi() % 3
	for i in n:
		var p := Vector3(rng.randf_range(lot.position.x + 2, lot.end.x - 2), top, rng.randf_range(lot.position.y + 2, lot.end.y - 2))
		_prop("exterior_aircon_unit", p, rng.randf() * TAU, 1.6)


func _plaza(lot: Rect2) -> void:
	map_parks.append(lot)
	var c := lot.get_center()
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		_prop("modular_street_seating", Vector3(c.x + cos(a) * 6.0, CURB_H, c.y + sin(a) * 6.0), -a + PI / 2.0)
	for i in 4:
		var a := TAU * i / 4.0
		_prop("street_lamp_01", Vector3(c.x + cos(a) * 11.0, CURB_H, c.y + sin(a) * 11.0), -a)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		_palm(Vector3(c.x + cos(a) * 15.5, CURB_H, c.y + sin(a) * 15.5), i)


# ---------------------------------------------------------------- props

func _prop(name: String, pos: Vector3, yaw: float, scale := 1.0) -> Node3D:
	var path := "res://assets/models/polyhaven/%s/%s_1k.gltf" % [name, name]
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	props_root.add_child(n)
	return n


var _trunk_mesh: Mesh


## Mature California fan palm: tall slender trunk (fan-palm trunk textures) crowned with the fan-palm
## model's fronds; every third tree is a date palm for variety.
func _palm(pos: Vector3, i: int) -> void:
	var date := (i + int(pos.x)) % 3 == 0
	if date:
		var d: Node3D = (load("res://assets/models/sketchfab/date_palm/scene.gltf") as PackedScene).instantiate()
		d.position = pos
		d.rotation.y = rng.randf() * TAU
		d.scale = Vector3.ONE * rng.randf_range(0.95, 1.2)
		props_root.add_child(d)
	else:
		var h := rng.randf_range(11.0, 16.0)
		var tree := Node3D.new()
		tree.position = pos
		tree.rotation = Vector3(rng.randf_range(-0.04, 0.04), rng.randf() * TAU, rng.randf_range(-0.04, 0.04))
		props_root.add_child(tree)
		var trunk := MeshInstance3D.new()
		trunk.mesh = _palm_trunk()
		trunk.scale = Vector3(1, h, 1)
		tree.add_child(trunk)
		var crown: Node3D = (load("res://assets/models/sketchfab/fan_palm/scene.gltf") as PackedScene).instantiate()
		crown.scale = Vector3.ONE * rng.randf_range(1.15, 1.4)
		crown.position = Vector3(0, h - 1.6 * crown.scale.y, 0)
		crown.rotation.y = rng.randf() * TAU
		tree.add_child(crown)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.25 if not date else 0.35
	cyl.height = 4.0
	cs.shape = cyl
	cs.position = pos + Vector3(0, 2.0, 0)
	_static.add_child(cs)


func _palm_trunk() -> Mesh:
	if _trunk_mesh:
		return _trunk_mesh
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.26
	cm.height = 1.0
	cm.radial_segments = 10
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/models/sketchfab/fan_palm/textures/Wash_trunk_baseColor.png")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/models/sketchfab/fan_palm/textures/Wash_trunk_normal.png")
	m.roughness = 0.9
	m.uv1_scale = Vector3(1.0, 6.0, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	cm.material = m
	# pivot at the base
	var st := SurfaceTool.new()
	st.create_from(cm, 0)
	var arr := st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for k in verts.size():
		verts[k].y += 0.5
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, m)
	_trunk_mesh = am
	return am


func _build_outer_ring() -> void:
	# Buildings lining the outside of the outer roads, so every street is a real street.
	var inner := 80.0 + _road_w(80.0) * 0.5 + SIDEWALK  # 90
	var outer := EXTENT + 8.0
	var walls := ["white_stucco", "brick_wall_09", "plastered_wall_02", "concrete_tile_facade"]
	var tints := [Color(0.98, 0.9, 0.78), Color(0.95, 0.9, 0.86), Color(0.86, 0.92, 0.95), Color(1, 1, 1), Color(1.0, 0.86, 0.74)]
	for side in 4:
		var x := -outer
		while x < outer - 6.0:
			var w := rng.randf_range(18.0, 30.0)
			var x1 := minf(x + w, outer)
			var lot: Rect2
			match side:
				0: lot = Rect2(x, inner, x1 - x, outer - inner)
				1: lot = Rect2(x, -outer, x1 - x, outer - inner)
				2: lot = Rect2(inner, x, outer - inner, x1 - x)
				_: lot = Rect2(-outer, x, outer - inner, x1 - x)
			# keep road mouths open: skip lots that overlap a road corridor
			var blocked := false
			for line: float in ROAD_LINES:
				var hw := _road_w(line) * 0.5 + SIDEWALK
				var a0 := lot.position.x if side < 2 else lot.position.y
				var a1 := lot.end.x if side < 2 else lot.end.y
				if a1 > line - hw and a0 < line + hw:
					blocked = true
			if not blocked:
				_building(lot.grow(-1.0), rng.randi_range(3, 12), walls[rng.randi() % walls.size()], tints[rng.randi() % tints.size()], true)
			x = x1 + 2.0
	# Road ends at the slice edge: barriers + an invisible wall
	for line: float in ROAD_LINES:
		for sgn: float in [-1.0, 1.0]:
			for axis: int in [0, 1]:
				var end := (EXTENT - 1.0) * sgn
				for k in 5:
					var off := -_road_w(line) * 0.5 + 1.2 + k * (_road_w(line) - 2.4) / 4.0
					var p := Vector3(end, 0, line + off) if axis == 0 else Vector3(line + off, 0, end)
					_prop("concrete_road_barrier", p, PI * 0.5 if axis == 0 else 0.0)
				var c := Vector3(end + sgn * 1.0, 3.0, line) if axis == 0 else Vector3(line, 3.0, end + sgn * 1.0)
				_box_col(c, Vector3(1.0, 6.0, 30.0) if axis == 0 else Vector3(30.0, 6.0, 1.0))
	# Distant skyline (no collision / no shadows) so the horizon reads as a city
	for i in 70:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(170.0, 420.0)
		var c := Vector2(cos(ang), sin(ang)) * dist
		var sz := Vector2(rng.randf_range(20, 45), rng.randf_range(20, 45))
		var floors := rng.randi_range(4, 30) if dist < 300.0 else rng.randi_range(8, 40)
		_skyline_building(Rect2(c - sz * 0.5, sz), floors, walls[rng.randi() % walls.size()], tints[rng.randi() % tints.size()])


func _skyline_building(lot: Rect2, floors: int, wall: String, tint: Color) -> void:
	var before := get_child_count()
	_building(lot, floors, wall, tint, false)
	# strip collision/shadows from the distant skyline (they never come near the player)
	for i in range(before, get_child_count()):
		var n := get_child(i)
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_buildings.pop_back()
	var col: CollisionShape3D = _static.get_child(_static.get_child_count() - 1)
	col.queue_free()
