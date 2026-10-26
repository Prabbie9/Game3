class_name Storefront
extends Node3D
## A one-storey building on a reserved lot (WorldData.RESERVED) with a lit sign over the entrance: the hospital,
## the police station and the respray garage. The front faces the street on the lot's +Z (front = 1) or -Z
## (front = -1) side. Doors are glazed but closed; a garage front leaves a drive-in opening with an interior.

@export var rect := Rect2(0, 0, 20, 12)     # x/z footprint
@export var front := 1
@export var sign_text := "SIGN"
@export var sign_color := Color(1, 1, 1)
@export var wall := "plastered_wall_02"
@export var wall_tint := Color(1, 1, 1)
@export var garage := false                  # drive-in opening in the middle of the front
@export var height := 4.6

const T := 0.3
var _body: StaticBody3D
var _base := CityCell.CURB_H


func _ready() -> void:
	var city: City = Game.world.city if Game.world else null
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	add_child(_body)
	var x0 := rect.position.x
	var x1 := rect.end.x
	var z0 := rect.position.y
	var z1 := rect.end.y
	var y0 := _base
	var H := height
	var b := MeshBatch.new()
	# roof slab, parapet trim on the front
	b.box("roof", Vector3((x0 + x1) * 0.5, y0 + H - 0.12, (z0 + z1) * 0.5), Vector3(x1 - x0 + 0.4, 0.24, z1 - z0 + 0.4))
	_shape(Vector3((x0 + x1) * 0.5, y0 + H - 0.12, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.24, z1 - z0))
	var fz := z1 if front > 0 else z0
	b.box("trim", Vector3((x0 + x1) * 0.5, y0 + H + 0.3, fz + front * 0.05), Vector3(x1 - x0 + 0.5, 0.6, T + 0.2))
	# three plain walls (seen from outside, a -> c runs left to right)
	var corners := [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)]
	for i in 4:
		var a: Vector3 = corners[(i + 1) % 4]
		var c: Vector3 = corners[i]
		var is_front := (front > 0 and i == 2) or (front < 0 and i == 0)
		if is_front:
			continue
		_wall(b, a, c, 0.0, H)
	# the front: two shop windows either side of a central entrance (doors or the garage opening)
	var mid := (x0 + x1) * 0.5
	var door_w := 4.6 if garage else 2.4
	var door_h := 3.6 if garage else 2.6
	var pieces := [[x0, x0 + 1.0, 0.0, H], [x0 + 1.0, mid - door_w * 0.5 - 1.0, -1.0, H],
		[mid - door_w * 0.5 - 1.0, mid - door_w * 0.5, 0.0, H], [mid - door_w * 0.5, mid + door_w * 0.5, -2.0, H],
		[mid + door_w * 0.5, mid + door_w * 0.5 + 1.0, 0.0, H], [mid + door_w * 0.5 + 1.0, x1 - 1.0, -1.0, H], [x1 - 1.0, x1, 0.0, H]]
	for pc: Array in pieces:
		var a := Vector3(pc[0] if front > 0 else pc[1], y0, fz)
		var c := Vector3(pc[1] if front > 0 else pc[0], y0, fz)
		var w := absf(float(pc[1]) - float(pc[0]))
		if w < 0.05:
			continue
		match int(pc[2]):
			0:
				_wall(b, a, c, 0.0, H)
			-1:  # window
				_wall(b, a, c, 0.0, 0.9)
				_wall(b, a, c, 2.9, H)
				_glass(Vector3((a.x + c.x) * 0.5, y0 + 1.9, fz), Vector3(w, 2.0, 0.05), false, true)
			-2:  # entrance
				_wall(b, a, c, door_h, H)
				if not garage:
					_glass(Vector3((a.x + c.x) * 0.5, y0 + door_h * 0.5, fz), Vector3(w, door_h, 0.06), true)
	# behind the windows: a lit interior so they don't look like holes
	b.flat("floor", x0 + T, z0 + T, x1 - T, z1 - T, y0 + 0.02)
	b.quad("ceiling", Vector3(x0, y0 + H - 0.3, z0), Vector3(x1, y0 + H - 0.3, z0), Vector3(x1, y0 + H - 0.3, z1), Vector3(x0, y0 + H - 0.3, z1),
		Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1))
	for lx in range(int(x0) + 3, int(x1) - 1, 5):
		b.box("light_panel", Vector3(lx, y0 + H - 0.32, (z0 + z1) * 0.5), Vector3(1.2, 0.04, 0.3))
	# sign board
	b.box("sign", Vector3(mid, y0 + H - 0.65, fz + front * 0.22), Vector3(minf(9.0, x1 - x0 - 2.0), 0.9, 0.12))
	_commit(b, city)
	_sign(Vector3(mid, y0 + H - 0.65, fz + front * 0.29))
	if garage:
		var o := OmniLight3D.new()
		o.light_energy = 1.4
		o.omni_range = 9.0
		o.position = Vector3(mid, y0 + H - 0.8, (z0 + z1) * 0.5)
		add_child(o)


func _wall(b: MeshBatch, a: Vector3, c: Vector3, h0: float, h1: float) -> void:
	var d := (c - a).normalized()
	var n := Vector3(-d.z, 0, d.x)
	var y := Vector3(0, h0, 0)
	b.wall("ext", a + n * T * 0.5 + y, c + n * T * 0.5 + y, h1 - h0, h0)
	b.wall("int", c - n * T * 0.5 + y, a - n * T * 0.5 + y, minf(h1, height - 0.3) - h0, h0)
	if h0 > 0.0:
		b.quad("ext", a + n * T * 0.5 + y, c + n * T * 0.5 + y, c - n * T * 0.5 + y, a - n * T * 0.5 + y, Vector2(0, 0), Vector2(1, 0), Vector2(1, T), Vector2(0, T))
	var mid := (a + c) * 0.5
	_shape(Vector3(mid.x, a.y + (h0 + h1) * 0.5, mid.z), Vector3(absf(c.x - a.x) + (T if absf(d.z) > 0.5 else 0.0), h1 - h0, absf(c.z - a.z) + (T if absf(d.x) > 0.5 else 0.0)))


func _commit(b: MeshBatch, city: City) -> void:
	var arrays := b.commit()
	var am := ArrayMesh.new()
	for key: String in arrays:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays[key], [], {}, City.MESH_FLAGS)
		am.surface_set_material(am.get_surface_count() - 1, _material(city, key))
	var mi := MeshInstance3D.new()
	mi.mesh = am
	add_child(mi)


func _material(city: City, key: String) -> Material:
	if city:
		match key:
			"ext":
				return city._pbr(wall, 2.5, wall_tint)
			"int":
				return city._pbr("plastered_wall_02", 2.5, Color(0.92, 0.92, 0.9))
			"floor":
				return city._pbr("concrete_pavement", 2.0, Color(0.7, 0.7, 0.72))
			"roof":
				return city._pbr("concrete_pavement", 2.0, Color(0.6, 0.6, 0.6))
	var m := StandardMaterial3D.new()
	match key:
		"ceiling":
			m.albedo_color = Color(0.86, 0.86, 0.84)
		"trim", "sign":
			m.albedo_color = Color(0.1, 0.11, 0.12)
			m.roughness = 0.45
		"light_panel":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.97, 0.92)
			m.emission_energy_multiplier = 3.0
	return m


func _shape(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	cs.position = c
	_body.add_child(cs)


func _glass(c: Vector3, s: Vector3, solid: bool, breakable := false) -> void:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.68, 0.74, 0.35 if not solid else 0.55)
	m.roughness = 0.05
	m.metallic = 0.5
	if breakable:
		GlassPane.make(self, c, s, m)
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = c
	add_child(mi)
	if solid:
		_shape(c, s)


func _sign(at: Vector3) -> void:
	var l := Label3D.new()
	l.text = sign_text
	l.font = UITheme.heading
	l.font_size = 150
	l.pixel_size = 0.004
	l.modulate = sign_color
	l.shaded = false
	l.position = at
	if front < 0:
		l.rotation.y = PI
	add_child(l)
	var glow := OmniLight3D.new()
	glow.light_color = sign_color
	glow.light_energy = 0.7
	glow.omni_range = 4.5
	glow.position = at + Vector3(0, -0.3, front * 0.8)
	add_child(glow)


## Where people come out (respawns): on the pavement in front of the entrance.
func entrance() -> Transform3D:
	var mid := rect.get_center().x
	var fz := (rect.end.y if front > 0 else rect.position.y) + front * 1.8
	return Transform3D(Basis(Vector3.UP, PI if front > 0 else 0.0), Vector3(mid, _base + 0.05, fz))
