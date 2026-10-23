class_name CarLibrary
extends RefCounted
## Splits the "Generic passenger car pack" (Sketchfab, CC-BY) into individual cars at runtime.
## Each model is returned in a normalized car frame: origin on the ground between the axles, forward = -Z.
## Mesh resources are shared between all instances of a model (cheap to spawn many).

const PACK := "res://assets/models/sketchfab/generic_cars/scene.gltf"

## body node name in the pack -> settings. flip: rotate 180° if the wheel-derived axis points backwards.
const MODELS := {
	"compact": {"node": "Compact Body", "flip": false},
	"coupe": {"node": "Coupe Body", "flip": true},
	"hatchback": {"node": "Hatchback Body", "flip": false},
	"minivan": {"node": "minivan body", "flip": true},
	"offroad": {"node": "Offroad Body", "flip": true},
	"pickup": {"node": "Pickup Body", "flip": true},
	"sedan": {"node": "Sedan Body", "flip": true},
	"sport": {"node": "Sport body", "flip": false},
	"suv": {"node": "SUV Body", "flip": true},
	"wagon": {"node": "Wagon Body", "flip": true},
}

## Authored paint colour of each body texture (sRGB, measured from the textures; see car_paint.gdshader).
## Body_7 is a black car whose paint can't be told from its black trim, so it keeps its texture.
const PAINT_REF := {
	"Body_baseColor": Color8(0, 234, 254), "Body_0_baseColor": Color8(0, 70, 231), "Body_1_baseColor": Color8(255, 255, 0),
	"Body_2_baseColor": Color8(94, 0, 0), "Body_3_baseColor": Color8(31, 47, 0), "Body_4_baseColor": Color8(0, 102, 45),
	"Body_5_baseColor": Color8(159, 140, 43), "Body_6_baseColor": Color8(246, 0, 0), "Body_8_baseColor": Color8(92, 149, 159),
}
## Common real-world car colours, weighted roughly by how often they're seen on the road.
const PAINTS := [
	[Color(0.86, 0.86, 0.84), 22], [Color(0.03, 0.03, 0.035), 17], [Color(0.32, 0.33, 0.35), 15], [Color(0.62, 0.63, 0.65), 13],
	[Color(0.06, 0.13, 0.32), 9], [Color(0.55, 0.05, 0.04), 8], [Color(0.3, 0.03, 0.05), 4], [Color(0.62, 0.56, 0.44), 4],
	[Color(0.08, 0.2, 0.12), 3], [Color(0.32, 0.5, 0.66), 3], [Color(0.85, 0.55, 0.1), 1], [Color(0.9, 0.78, 0.15), 1],
]

static var _cache := {}


static func random_paint(rng: RandomNumberGenerator) -> Color:
	var total := 0
	for p in PAINTS:
		total += p[1]
	var pick := rng.randi() % total
	for p in PAINTS:
		pick -= p[1]
		if pick < 0:
			return p[0]
	return PAINTS[0][0]


static func paint_ref(tex: Texture2D) -> Color:
	if tex == null:
		return Color(0, 0, 0, 0)
	return PAINT_REF.get(tex.resource_path.get_file().get_basename(), Color(0, 0, 0, 0))


static func get_model(model: String) -> Dictionary:
	if _cache.is_empty():
		# Extract every model in one pass and free the pack right away: keeping an out-of-tree node
		# tree in a static var outlives the RenderingServer and crashes the game on exit.
		var pack: Node3D = (load(PACK) as PackedScene).instantiate()
		for m in MODELS:
			_cache[m] = _extract(pack, m)
		pack.free()
		_optics_img = null
	return _cache[model]


static func _extract(_pack: Node3D, model: String) -> Dictionary:
	var cfg: Dictionary = MODELS[model]
	var body: Node3D = _pack.find_child(cfg.node, true, false)
	var body_meshes: Array[MeshInstance3D] = []
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		body_meshes.append(mi)
	var body_aabb := _global_aabb(body_meshes)
	var center := body_aabb.get_center()

	# the four wheel groups closest to this body
	var groups := []
	for wn in _pack.find_children("Wheel_*", "Node3D", true, false):
		if wn is MeshInstance3D:
			continue
		var meshes: Array[MeshInstance3D] = []
		for mi in wn.find_children("*", "MeshInstance3D", true, false):
			meshes.append(mi)
		if meshes.is_empty():
			continue
		var a := _global_aabb(meshes)
		var c := a.get_center()
		groups.append({"meshes": meshes, "center": c, "aabb": a, "d": Vector2(c.x - center.x, c.z - center.z).length()})
	groups.sort_custom(func(a, b): return a.d < b.d)
	# the pack contains duplicate wheel groups at identical positions: keep 4 distinct wheels
	var wheels := []
	for g in groups:
		var dup := false
		for w in wheels:
			if (w.center as Vector3).distance_to(g.center) < 0.3:
				dup = true
				break
		if not dup:
			wheels.append(g)
		if wheels.size() == 4:
			break

	# axles: pair each wheel with its nearest neighbour; forward = from rear axle mid to front axle mid
	var w0: Vector3 = wheels[0].center
	var nearest := 1
	for i in range(2, 4):
		if (wheels[i].center - w0).length() < (wheels[nearest].center - w0).length():
			nearest = i
	var axle_a: Vector3 = (w0 + wheels[nearest].center) * 0.5
	var others := [0, 1, 2, 3].filter(func(i): return i != 0 and i != nearest)
	var axle_b: Vector3 = (wheels[others[0]].center + wheels[others[1]].center) * 0.5
	var fwd := axle_a - axle_b
	fwd.y = 0
	fwd = fwd.normalized()
	if cfg.flip:
		fwd = -fwd
	var mid := (axle_a + axle_b) * 0.5
	var ground_y := INF
	for w in wheels:
		ground_y = minf(ground_y, (w.aabb as AABB).position.y)
	var z := -fwd
	var x := Vector3.UP.cross(z).normalized()
	var frame := Transform3D(Basis(x, Vector3.UP, z), Vector3(mid.x, ground_y, mid.z))
	var inv := frame.affine_inverse()

	var parts := []
	var optics := {"front": SurfaceTool.new(), "rear": SurfaceTool.new()}
	var amber := {"front": 0, "rear": 0}
	var optics_mat: Material = null
	for st: SurfaceTool in optics.values():
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mi in body_meshes:
		var xf := inv * _gxf(mi)
		var mesh: Mesh = mi.mesh
		var keep := ArrayMesh.new()
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat and String(mat.resource_name).begins_with("Optics"):
				# lights: split into front (headlights) and rear (tail/brake/reverse) in the car frame
				optics_mat = mat
				_split_optics(mesh.surface_get_arrays(s), xf, optics, amber, _optics_image(mat))
				continue
			keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
			keep.surface_set_material(keep.get_surface_count() - 1, mat)
		parts.append([keep, xf])
	var optic_meshes := {}
	for k: String in optics:
		var st: SurfaceTool = optics[k]
		st.generate_normals()
		var m := st.commit()
		if m.get_surface_count() > 0:
			optic_meshes[k] = m
	var wheel_data := []
	for w in wheels:
		var wc := Transform3D(frame.basis, w.center)
		var winv := wc.affine_inverse()
		var wparts := []
		for mi in w.meshes:
			wparts.append([mi.mesh, winv * _gxf(mi)])
		var local_center: Vector3 = inv * (w.center as Vector3)
		wheel_data.append({"pos": local_center, "radius": (w.aabb as AABB).size.y * 0.5, "parts": wparts})
	# tight bounds in the car frame (world-axis bounds of rotated cars are inflated)
	var local_aabb := AABB()
	var first := true
	for mi in body_meshes:
		var a := (inv * _gxf(mi)) * mi.get_aabb()
		local_aabb = a if first else local_aabb.merge(a)
		first = false
	# indicators blink on the amber lenses; a cluster without any uses its outer third instead
	var has_amber := {"front": amber.front >= 4, "rear": amber.rear >= 4}
	return {"parts": parts, "wheels": wheel_data, "aabb": local_aabb, "optics": optic_meshes, "optics_mat": optics_mat,
		"amber": has_amber}


static var _optics_img: Image


static func _optics_image(mat: Material) -> Image:
	if _optics_img == null and mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
		_optics_img = (mat as BaseMaterial3D).albedo_texture.get_image()
		if _optics_img and _optics_img.is_compressed():
			_optics_img.decompress()
	return _optics_img


## Orange indicator lens colour (sRGB); the same test runs in car_lights.gdshader.
static func is_amber(c: Color) -> bool:
	return c.r > 0.45 and c.g > 0.32 * c.r and c.g < 0.78 * c.r and c.b < 0.55 * c.g


## Triangles of a light surface into the front/rear SurfaceTools (car frame: forward = -Z); counts amber triangles.
static func _split_optics(arr: Array, xf: Transform3D, out: Dictionary, amber: Dictionary, img: Image) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] else PackedInt32Array(range(v.size()))
	for t in range(0, idx.size(), 3):
		var a := xf * v[idx[t]]
		var b := xf * v[idx[t + 1]]
		var c := xf * v[idx[t + 2]]
		var side := "front" if (a.z + b.z + c.z) < 0.0 else "rear"
		var st: SurfaceTool = out[side]
		if img and uv.size() > 0:
			var m := (uv[idx[t]] + uv[idx[t + 1]] + uv[idx[t + 2]]) / 3.0
			var px := Vector2i(clampi(int(fposmod(m.x, 1.0) * img.get_width()), 0, img.get_width() - 1),
				clampi(int(fposmod(m.y, 1.0) * img.get_height()), 0, img.get_height() - 1))
			if is_amber(img.get_pixelv(px)):
				amber[side] += 1
		for k in 3:
			if uv.size() > 0:
				st.set_uv(uv[idx[t + k]])
			st.add_vertex([a, b, c][k])


static func _global_aabb(meshes: Array[MeshInstance3D]) -> AABB:
	var out := AABB()
	var first := true
	for mi in meshes:
		var a := _gxf(mi) * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


## Global transform within the (out-of-tree) pack instance.
static func _gxf(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
