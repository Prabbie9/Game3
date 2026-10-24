class_name Interior
extends Node3D
## A walk-in single-storey building, built in its own frame (place the node at the middle of the front wall's
## footing and turn it to face the street; the front wall is at local z = 0, the room goes back to z = -depth):
## floor, walls (outside / inside materials), ceiling with light panels and lamps, roof, shop windows and an
## entrance with a hinged Door. Subclasses furnish it with Poly Haven models (furnish()) and add what can be
## used inside.

@export var width := 18.0
@export var depth := 13.0
@export var height := 3.8
@export var door_x := 0.0
@export var windows: Array = []          # [[x0, x1], ...] along the front wall (local x)
@export var ext := "brick_wall_09"
@export var ext_tint := Color(0.85, 0.72, 0.62)
@export var int_wall := "plastered_wall_02"
@export var int_tint := Color(0.92, 0.9, 0.84)
@export var floor_tex := "wood_floor_deck"
@export var floor_tint := Color(0.62, 0.5, 0.4)
@export var floor_tile := 1.6
@export var sign_text := ""
@export var sign_color := Color(1.0, 0.75, 0.35)
@export var light_color := Color(1.0, 0.92, 0.8)

const T := 0.3
const DOOR_W := 1.3
const DOOR_H := 2.4
const WIN_Y := [0.9, 2.6]
const MODEL := "res://assets/models/polyhaven/%s/%s_1k.gltf"

var door: Door
var _body: StaticBody3D
var _base := CityCell.CURB_H
var _lamps: Array[OmniLight3D] = []


func _ready() -> void:
	add_to_group("interiors")
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	add_child(_body)
	_build_shell()
	_build()


## True when `pos` (a world point) is in the room (ambience: muffled street, room reverb).
func inside(pos: Vector3) -> bool:
	var l := to_local(pos)
	return absf(l.x) < width * 0.5 and l.z < 0.0 and l.z > -depth and l.y < height + 0.5


## Furniture and things to use (subclasses).
func _build() -> void:
	pass


func _city() -> City:
	return Game.world.city if Game.world else null


func _build_shell() -> void:
	var x0 := -width * 0.5
	var x1 := width * 0.5
	var z0 := -depth
	var z1 := 0.0
	var y0 := _base
	var y1 := _base + height
	var b := MeshBatch.new()
	b.flat("floor", x0 + T * 0.5, z0 + T * 0.5, x1 - T * 0.5, z1 - T * 0.5, y0 + 0.02)
	b.quad("ceiling", Vector3(x0, y1 - 0.3, z0), Vector3(x1, y1 - 0.3, z0), Vector3(x1, y1 - 0.3, z1), Vector3(x0, y1 - 0.3, z1),
		Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1))
	b.box("roof", Vector3(0, y1 - 0.12, z0 * 0.5), Vector3(width + 0.4, 0.24, depth + 0.4))
	b.box("trim", Vector3(0, y1 + 0.25, z1 + 0.05), Vector3(width + 0.5, 0.5, T + 0.2))
	_shape(Vector3(0, y1 - 0.12, z0 * 0.5), Vector3(width, 0.24, depth))
	_shape(Vector3(0, y0 - 0.05, z0 * 0.5), Vector3(width, 0.1, depth))   # floor (the lot under it is open ground)
	_add_batch(b)
	_solid_wall(Vector3(x1, y0, z0), Vector3(x0, y0, z0))
	_solid_wall(Vector3(x0, y0, z0), Vector3(x0, y0, z1))
	_solid_wall(Vector3(x1, y0, z1), Vector3(x1, y0, z0))
	# front wall: pieces between the windows and the door
	var cuts := []   # [x0, x1, kind]
	for w: Array in windows:
		cuts.append([float(w[0]), float(w[1]), "win"])
	cuts.append([door_x - DOOR_W * 0.5, door_x + DOOR_W * 0.5, "door"])
	cuts.sort_custom(func(a, c): return a[0] < c[0])
	var x := x0
	for c: Array in cuts:
		if c[0] > x + 0.01:
			_front_piece(x, c[0], 0.0, height)
		if c[2] == "win":
			_front_piece(c[0], c[1], 0.0, WIN_Y[0])
			_front_piece(c[0], c[1], WIN_Y[1], height)
			_glass(Vector3((c[0] + c[1]) * 0.5, y0 + (WIN_Y[0] + WIN_Y[1]) * 0.5, z1), Vector3(c[1] - c[0], WIN_Y[1] - WIN_Y[0], 0.04))
		else:
			_front_piece(c[0], c[1], DOOR_H, height)
		x = c[1]
	if x < x1 - 0.01:
		_front_piece(x, x1, 0.0, height)
	door = Door.new()
	door.width = DOOR_W
	door.height = DOOR_H
	add_child(door)
	door.position = Vector3(door_x - DOOR_W * 0.5, y0, z1)
	# ceiling light panels and a few real lights
	var b2 := MeshBatch.new()
	for lx: float in [x0 * 0.5, x1 * 0.5]:
		for lz: float in [z0 * 0.3, z0 * 0.72]:
			b2.box("light_panel", Vector3(lx, y1 - 0.32, lz), Vector3(1.2, 0.04, 0.3))
			var l := OmniLight3D.new()
			l.light_color = light_color
			l.light_energy = 1.1
			l.omni_range = maxf(width, depth) * 0.55
			l.shadow_enabled = false
			l.position = Vector3(lx, y1 - 0.6, lz)
			add_child(l)
			_lamps.append(l)
	_add_batch(b2)
	if sign_text != "":
		_sign()


func _process(_delta: float) -> void:
	# interior lamps only matter close to the camera
	var cam := get_viewport().get_camera_3d()
	var on := cam != null and cam.global_position.distance_to(global_position) < 45.0
	for l in _lamps:
		l.visible = on


func _material(key: String) -> Material:
	var city := _city()
	match key:
		"floor":
			return city._pbr(floor_tex, floor_tile, floor_tint) if city else StandardMaterial3D.new()
		"ext":
			return city._pbr(ext, 2.2, ext_tint) if city else StandardMaterial3D.new()
		"int":
			return city._pbr(int_wall, 2.5, int_tint) if city else StandardMaterial3D.new()
		"roof":
			return city._pbr("concrete_pavement", 2.0, Color(0.6, 0.6, 0.6)) if city else StandardMaterial3D.new()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	match key:
		"ceiling":
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.86, 0.86, 0.84)
		"trim":
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.12, 0.13, 0.14)
			m.roughness = 0.5
		"light_panel":
			m.vertex_color_use_as_albedo = false
			m.emission_enabled = true
			m.emission = light_color
			m.emission_energy_multiplier = 3.0
		"wood":
			m.roughness = 0.55
		"metal":
			m.metallic = 0.7
			m.roughness = 0.35
	return m


## A full-height wall from a to c (seen from outside, left to right): outside and inside faces, collision.
func _solid_wall(a: Vector3, c: Vector3) -> void:
	var b := MeshBatch.new()
	var d := (c - a).normalized()
	var n := Vector3(-d.z, 0, d.x)
	b.wall("ext", a + n * T * 0.5, c + n * T * 0.5, height)
	b.wall("int", c - n * T * 0.5, a - n * T * 0.5, height - 0.3)
	_add_batch(b)
	var mid := (a + c) * 0.5
	_shape(mid + Vector3(0, height * 0.5, 0), Vector3(absf(c.x - a.x) + (T if absf(d.z) > 0.5 else 0.0), height, absf(c.z - a.z) + (T if absf(d.x) > 0.5 else 0.0)))


## An inside partition wall from a to c (local, floor level): plastered both sides, with end caps, solid.
func partition(a: Vector3, c: Vector3, thick := 0.12) -> void:
	var b := MeshBatch.new()
	var d := (c - a).normalized()
	var n := Vector3(-d.z, 0, d.x) * thick * 0.5
	var y := Vector3(0, _base, 0)
	var h := height - 0.3
	b.wall("int", a + y + n, c + y + n, h)
	b.wall("int", c + y - n, a + y - n, h)
	for e: Vector3 in [a, c]:   # caps (one of each pair faces out, the other is culled)
		b.wall("int", e + y - n, e + y + n, h)
		b.wall("int", e + y + n, e + y - n, h)
	_add_batch(b)
	_shape((a + c) * 0.5 + y + Vector3(0, h * 0.5, 0), Vector3(absf(c.x - a.x) + (thick if absf(d.z) > 0.5 else 0.0), h, absf(c.z - a.z) + (thick if absf(d.x) > 0.5 else 0.0)))


## A piece of the front wall from x a to x c, between heights h0..h1 above the floor.
func _front_piece(a: float, c: float, h0: float, h1: float) -> void:
	var b := MeshBatch.new()
	var y := _base + h0
	var w := c - a
	b.wall("ext", Vector3(a, y, T * 0.5), Vector3(c, y, T * 0.5), h1 - h0, h0)
	b.wall("int", Vector3(c, y, -T * 0.5), Vector3(a, y, -T * 0.5), minf(h1, height - 0.3) - h0, h0)
	if h0 > 0.0:
		b.quad("ext", Vector3(a, y, T * 0.5), Vector3(c, y, T * 0.5), Vector3(c, y, -T * 0.5), Vector3(a, y, -T * 0.5),
			Vector2(0, 0), Vector2(w, 0), Vector2(w, T), Vector2(0, T))
	if h1 < height:
		var yt := _base + h1
		b.quad("ext", Vector3(a, yt, -T * 0.5), Vector3(c, yt, -T * 0.5), Vector3(c, yt, T * 0.5), Vector3(a, yt, T * 0.5),
			Vector2(0, 0), Vector2(w, 0), Vector2(w, T), Vector2(0, T))
	# the sides of the opening (door / window reveals)
	_add_batch(b)
	_shape(Vector3((a + c) * 0.5, _base + (h0 + h1) * 0.5, 0), Vector3(w, h1 - h0, T))


func _add_batch(b: MeshBatch) -> void:
	var arrays := b.commit()
	var am := ArrayMesh.new()
	for key: String in arrays:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays[key], [], {}, City.MESH_FLAGS)
		am.surface_set_material(am.get_surface_count() - 1, _material(key))
	var mi := MeshInstance3D.new()
	mi.mesh = am
	add_child(mi)


func _shape(c: Vector3, s: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	cs.transform = Transform3D(basis, c)
	_body.add_child(cs)


static var _glass_mat: StandardMaterial3D


func _glass(c: Vector3, s: Vector3) -> void:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.albedo_color = Color(0.7, 0.82, 0.86, 0.18)
		_glass_mat.roughness = 0.05
		_glass_mat.metallic = 0.4
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = _glass_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = c
	add_child(mi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.set_meta("surface", FX.Surface.GLASS)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	sb.add_child(cs)
	sb.position = c
	add_child(sb)


func _sign() -> void:
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(minf(width * 0.45, 0.5 + sign_text.length() * 0.62), 0.8, 0.12)
	board.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.08)
	board.material_override = m
	board.position = Vector3(door_x, _base + DOOR_H + 0.75, 0.25)
	add_child(board)
	var l := Label3D.new()
	l.text = sign_text
	l.font = UITheme.get_theme().get_font("font", "Button")
	l.font_size = 96
	l.pixel_size = 0.005
	l.modulate = sign_color
	l.outline_size = 0
	l.position = board.position + Vector3(0, 0, 0.07)
	l.shaded = false
	add_child(l)
	var glow := OmniLight3D.new()
	glow.light_color = sign_color
	glow.light_energy = 0.8
	glow.omni_range = 4.0
	glow.position = board.position + Vector3(0, 0, 0.8)
	add_child(glow)


## Place a Poly Haven model (local position, yaw in degrees), optionally with a box collider round it.
func furnish(model: String, pos: Vector3, yaw := 0.0, collide := true, scale_k := 1.0) -> Node3D:
	var path := MODEL % [model, model]
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.position = pos + Vector3(0, _base, 0)
	n.rotation.y = deg_to_rad(yaw)
	n.scale = Vector3.ONE * scale_k
	add_child(n)
	if collide:
		var aabb := AABB()
		var first := true
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			var xf := _rel(mi, n)
			var bb := xf * mi.mesh.get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
		if not first:
			var c := n.transform * aabb.get_center()
			_shape(c, aabb.size * scale_k * 0.95, n.transform.basis.orthonormalized())
	return n


func _rel(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D()
	var n: Node = node
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## A world point from a local one (for interact points).
func world(p: Vector3) -> Vector3:
	return global_transform * (p + Vector3(0, _base, 0))
