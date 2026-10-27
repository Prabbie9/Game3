class_name StuntRamp
extends StaticBody3D
## A stunt ramp: a steel wedge rising along -Z (drive at it from +Z), yellow and black chevrons on the slope.
## Solid for cars, bikes and people alike.

@export var length := 9.0
@export var width := 5.0
@export var height := 2.2

static var _mat_top: StandardMaterial3D
static var _mat_side: StandardMaterial3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("stunt_ramps")
	var hw := width * 0.5
	var l := length * 0.5
	# the wedge: low edge at +Z on the ground, high edge at -Z
	var lo_l := Vector3(-hw, 0, l)
	var lo_r := Vector3(hw, 0, l)
	var hi_l := Vector3(-hw, height, -l)
	var hi_r := Vector3(hw, height, -l)
	var bk_l := Vector3(-hw, 0, -l)
	var bk_r := Vector3(hw, 0, -l)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([lo_l, lo_r, hi_l, hi_r, bk_l, bk_r])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_materials()
	var slope := Vector3(0, height, -length).length()
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	# (clockwise seen from the front: Godot's front faces)
	for v: Array in [[lo_l, Vector2(0, 0)], [hi_l, Vector2(0, slope)], [hi_r, Vector2(width, slope)],
			[lo_l, Vector2(0, 0)], [hi_r, Vector2(width, slope)], [lo_r, Vector2(width, 0)]]:
		top.set_uv(v[1] / 2.5)
		top.add_vertex(v[0])
	top.generate_normals()
	top.generate_tangents()
	var mesh := top.commit()
	var side := SurfaceTool.new()
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in [lo_l, bk_l, hi_l,   lo_r, hi_r, bk_r,   bk_l, bk_r, hi_r,   bk_l, hi_r, hi_l]:
		side.set_uv(Vector2(v.z, v.y))
		side.add_vertex(v)
	side.generate_normals()
	side.commit(mesh)
	mesh.surface_set_material(0, _mat_top)
	mesh.surface_set_material(1, _mat_side)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


static func _materials() -> void:
	if _mat_top:
		return
	# yellow and black chevrons, pointing up the slope
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var k := posmod(y + absi(x - 32), 32) < 16
			img.set_pixel(x, y, Color(0.95, 0.75, 0.1) if k else Color(0.08, 0.08, 0.08))
	img.generate_mipmaps()
	_mat_top = StandardMaterial3D.new()
	_mat_top.albedo_texture = ImageTexture.create_from_image(img)
	_mat_top.roughness = 0.6
	_mat_top.metallic = 0.3
	_mat_side = StandardMaterial3D.new()
	_mat_side.albedo_color = Color(0.32, 0.33, 0.35)
	_mat_side.roughness = 0.5
	_mat_side.metallic = 0.6


static func release() -> void:
	_mat_top = null
	_mat_side = null
