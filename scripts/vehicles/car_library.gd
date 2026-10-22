class_name CarLibrary
extends RefCounted
## Splits the "Generic passenger car pack" (Sketchfab, CC-BY) into individual cars at runtime.
## Each model is returned in a normalized car frame: origin on the ground between the axles, forward = -Z.
## Mesh resources are shared between all instances of a model (cheap to spawn many).

const PACK := "res://assets/models/sketchfab/generic_cars/scene.gltf"

## body node name in the pack -> settings. flip: rotate 180° if the wheel-derived axis points backwards.
const MODELS := {
	"compact": {"node": "Compact Body", "flip": false},
	"coupe": {"node": "Coupe Body", "flip": false},
	"hatchback": {"node": "Hatchback Body", "flip": false},
	"minivan": {"node": "minivan body", "flip": false},
	"offroad": {"node": "Offroad Body", "flip": false},
	"pickup": {"node": "Pickup Body", "flip": false},
	"sedan": {"node": "Sedan Body", "flip": false},
	"sport": {"node": "Sport body", "flip": false},
	"suv": {"node": "SUV Body", "flip": false},
	"wagon": {"node": "Wagon Body", "flip": false},
}

static var _cache := {}
static var _pack: Node3D


static func get_model(model: String) -> Dictionary:
	if _cache.has(model):
		return _cache[model]
	if _pack == null:
		_pack = (load(PACK) as PackedScene).instantiate()
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
	var wheels := groups.slice(0, 4)

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
	for mi in body_meshes:
		parts.append([mi.mesh, inv * _gxf(mi)])
	var wheel_data := []
	for w in wheels:
		var wc := Transform3D(frame.basis, w.center)
		var winv := wc.affine_inverse()
		var wparts := []
		for mi in w.meshes:
			wparts.append([mi.mesh, winv * _gxf(mi)])
		var local_center: Vector3 = inv * (w.center as Vector3)
		wheel_data.append({"pos": local_center, "radius": (w.aabb as AABB).size.y * 0.5, "parts": wparts})
	var local_aabb := inv * body_aabb
	var data := {"parts": parts, "wheels": wheel_data, "aabb": local_aabb}
	_cache[model] = data
	return data


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
