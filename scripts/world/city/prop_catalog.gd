class_name PropCatalog
extends RefCounted
## Street furniture and plants as single meshes (one surface per material) for MultiMesh instancing, plus the
## collision each needs. Kits that stack a clean and a weathered variant are split into two entries.
## Load on the main thread (PropCatalog.prepare()) before city cells are built on worker threads.

const PH := "res://assets/models/polyhaven/%s/%s_1k.gltf"
## name -> [scene path, node filter ("" all, "clean", "aged"), collision ["cyl", r, h] / ["box"] (mesh bounds) / []]
const SOURCES := {
	"street_lamp_01": ["ph", "", ["cyl", 0.1, 3.8]],
	"fire_hydrant": ["ph", "clean", ["cyl", 0.14, 0.8]],
	"fire_hydrant_aged": ["ph:fire_hydrant", "aged", ["cyl", 0.14, 0.8]],
	"metal_trash_can": ["ph", "clean", ["cyl", 0.29, 0.95]],
	"metal_trash_can_rust": ["ph:metal_trash_can", "aged", ["cyl", 0.29, 0.95]],
	"utility_box_01": ["ph", "", ["box"]],
	"utility_box_02": ["ph", "", ["box"]],
	"concrete_road_barrier": ["ph", "", ["box"]],
	"exterior_aircon_unit": ["ph", "", []],
	"palm_crown": ["res://assets/models/sketchfab/fan_palm/scene.gltf", "", []],
	"date_palm": ["res://assets/models/sketchfab/date_palm/scene.gltf", "", ["cyl", 0.35, 4.0]],
	"jacaranda": ["res://assets/models/sketchfab/jacaranda/scene.gltf", "", ["cyl", 0.07, 1.2]],
	"oak": ["res://assets/models/sketchfab/oak/scene.gltf", "", ["cyl", 0.3, 3.0]],
	"boulder": ["ph:boulder_01", "", ["box"]],
}

static var _entries := {}  # name -> {"mesh": Mesh, "aabb": AABB, "col": Array}


static func prepare() -> void:
	if not _entries.is_empty():
		return
	for name: String in SOURCES:
		_entries[name] = _extract(name)
	_entries["bench"] = _bench()
	_entries["palm_trunk"] = _palm_trunk()


static func release() -> void:
	_entries.clear()


static func entry(name: String) -> Dictionary:
	return _entries.get(name, {})


static func mesh(name: String) -> Mesh:
	return _entries[name].mesh


static func aabb(name: String) -> AABB:
	return _entries[name].aabb


## Collision for an instance: [] (none) or [Shape3D, local offset].
static func collision(name: String, scale := 1.0) -> Array:
	var c: Array = _entries[name].col
	if c.is_empty():
		return []
	if c[0] == "cyl":
		var cyl := CylinderShape3D.new()
		cyl.radius = c[1] * scale
		cyl.height = c[2] * scale
		return [cyl, Vector3(0, c[2] * scale * 0.5, 0)]
	var b: AABB = _entries[name].aabb
	var box := BoxShape3D.new()
	box.size = b.size * scale
	return [box, b.get_center() * scale]


static func _extract(name: String) -> Dictionary:
	var src: Array = SOURCES[name]
	var path: String = src[0]
	if path == "ph":
		path = PH % [name, name]
	elif path.begins_with("ph:"):
		path = PH % [path.substr(3), path.substr(3)]
	var root: Node = (load(path) as PackedScene).instantiate()
	var by_mat := {}  # Material -> SurfaceTool
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var lname := String(mi.name).to_lower()
		var weathered := lname.contains("aged") or lname.contains("rust")
		if (src[1] == "clean" and weathered) or (src[1] == "aged" and not weathered):
			continue
		var xf := _xf_to_root(mi, root)
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
			(by_mat[mat] as SurfaceTool).append_from(mi.mesh, s, xf)
		var b: AABB = xf * mi.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	root.free()
	var am := ArrayMesh.new()
	for mat: Material in by_mat:
		var st: SurfaceTool = by_mat[mat]
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	if name in LOD_NAMES:
		am = _with_lods(am)
	return {"mesh": am, "aabb": aabb, "col": src[2]}


## Vegetation is instanced by the hundred: give it automatic LODs (the merge above drops the imported ones).
const LOD_NAMES := ["palm_crown", "date_palm", "jacaranda", "oak", "boulder"]


static func _with_lods(am: ArrayMesh) -> ArrayMesh:
	var im := ImporterMesh.new()
	for s in am.get_surface_count():
		var src := am.surface_get_arrays(s)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
			arr[a] = src[a]
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, am.surface_get_material(s))
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


static func _xf_to_root(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Backless slatted bench from the modular street-seating kit (the kit ships every piece at the origin).
static func _bench() -> Dictionary:
	var kit: Node = (load(PH % ["modular_street_seating", "modular_street_seating"]) as PackedScene).instantiate()
	var parts := {}
	for c in kit.get_children():
		if c is MeshInstance3D:
			parts[String(c.name)] = c
	var by_mat := {}
	for p: Array in [["seat_bench", Transform3D(Basis.IDENTITY, Vector3(0, 0.475, 0))],
			["legs_single", Transform3D(Basis.IDENTITY, Vector3(-0.84, 0, 0))],
			["legs_single", Transform3D(Basis(Vector3.UP, PI), Vector3(0.84, 0, 0))]]:
		var mi: MeshInstance3D = parts[p[0]]
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
			(by_mat[mat] as SurfaceTool).append_from(mi.mesh, s, p[1])
	kit.free()
	var am := ArrayMesh.new()
	for mat: Material in by_mat:
		(by_mat[mat] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	return {"mesh": am, "aabb": AABB(Vector3(-0.92, 0, -0.3), Vector3(1.84, 0.475, 0.6)), "col": ["box"]}


## Unit-height palm trunk (pivot at the base) textured with the fan palm's bark; scale Y per tree.
static func _palm_trunk() -> Dictionary:
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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(cm, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	var am := st.commit()
	am.surface_set_material(0, m)
	return {"mesh": am, "aabb": AABB(Vector3(-0.26, 0, -0.26), Vector3(0.52, 1, 0.52)), "col": ["cyl", 0.25, 4.0]}
