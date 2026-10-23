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

static var _cache := {}


static func get_model(model: String) -> Dictionary:
	if _cache.is_empty():
		# Extract every model in one pass and free the pack right away: keeping an out-of-tree node
		# tree in a static var outlives the RenderingServer and crashes the game on exit.
		var pack: Node3D = (load(PACK) as PackedScene).instantiate()
		for m in MODELS:
			_cache[m] = _extract(pack, m)
		pack.free()
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
				_split_optics(mesh.surface_get_arrays(s), xf, optics)
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
	return {"parts": parts, "wheels": wheel_data, "aabb": local_aabb, "optics": optic_meshes, "optics_mat": optics_mat}


## Triangles of a light surface into the front/rear SurfaceTools (car frame: forward = -Z).
static func _split_optics(arr: Array, xf: Transform3D, out: Dictionary) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] else PackedInt32Array(range(v.size()))
	for t in range(0, idx.size(), 3):
		var a := xf * v[idx[t]]
		var b := xf * v[idx[t + 1]]
		var c := xf * v[idx[t + 2]]
		var st: SurfaceTool = out["front" if (a.z + b.z + c.z) < 0.0 else "rear"]
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
