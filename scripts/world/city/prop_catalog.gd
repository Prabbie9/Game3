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
	# [source, variant, collision, real height in m (scaled to it, centred, standing on y = 0), yaw (degrees) that
	# turns its front to +Z]
	"vending_machine": ["res://assets/models/sketchfab/vending_machine/scene.gltf", "", ["box"], 1.83, 180.0],
	"atm": ["res://assets/models/sketchfab/atm/scene.gltf", "", ["box"], 1.62, -90.0],
	"payphone": ["res://assets/models/sketchfab/payphone/scene.gltf", "", ["box"], 2.2, 0.0],
}

static var _entries := {}  # name -> {"mesh": Mesh, "aabb": AABB, "col": Array}


static func prepare() -> void:
	if not _entries.is_empty():
		return
	for name: String in SOURCES:
		_entries[name] = _extract(name)
	_entries["bench"] = _bench()
	_entries["palm_trunk"] = _palm_trunk()
	_entries["picket_fence"] = _picket_fence()
	_entries["chainlink_fence"] = _chainlink_fence()


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
	var parts := []   # [MeshInstance3D, xf]
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var lname := String(mi.name).to_lower()
		var weathered := lname.contains("aged") or lname.contains("rust")
		if (src[1] == "clean" and weathered) or (src[1] == "aged" and not weathered):
			continue
		var xf := _xf_to_root(mi, root)
		parts.append([mi, xf])
		var b: AABB = xf * mi.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	# a real height given: scale to it, centre on x/z, stand on y = 0
	var norm := Transform3D()
	if src.size() > 3 and aabb.size.y > 0.0:
		var k := float(src[3]) / aabb.size.y
		var c := aabb.get_center()
		norm = Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3(-c.x * k, -aabb.position.y * k, -c.z * k))
		if src.size() > 4:
			norm = Transform3D(Basis(Vector3.UP, deg_to_rad(float(src[4]))), Vector3.ZERO) * norm
		aabb = norm * aabb
	for part: Array in parts:
		var mi: MeshInstance3D = part[0]
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
			(by_mat[mat] as SurfaceTool).append_from(mi.mesh, s, norm * (part[1] as Transform3D))
	root.free()
	var am := ArrayMesh.new()
	for mat: Material in by_mat:
		var st: SurfaceTool = by_mat[mat]
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	am = _with_lods(am) if name in VEGETATION else _reduced(am, BUDGET.get(name, 2000))
	return {"mesh": am, "aabb": aabb, "col": src[2]}


## Vegetation keeps automatic LODs (grouped per 64 m, impostors far away). Street furniture is grouped per cell, so a
## LOD would be picked for the nearest instance only: bake a reduced mesh instead (triangle budget per prop).
const VEGETATION := ["palm_crown", "date_palm", "jacaranda", "oak", "boulder"]
const BUDGET := {"street_lamp_01": 3500, "fire_hydrant": 1600, "fire_hydrant_aged": 1600, "metal_trash_can": 1400,
	"metal_trash_can_rust": 1400, "utility_box_01": 600, "utility_box_02": 600, "concrete_road_barrier": 500,
	"exterior_aircon_unit": 1200, "bench": 2000}


## Mesh with the simplest generated LOD that still has at least `tris` triangles per surface (scaled by share).
static func _reduced(am: ArrayMesh, tris: int) -> ArrayMesh:
	var total := 0
	for s in am.get_surface_count():
		total += am.surface_get_array_index_len(s) / 3 if am.surface_get_array_index_len(s) > 0 else am.surface_get_array_len(s) / 3
	if total <= tris:
		return am
	var im := ImporterMesh.new()
	for s in am.get_surface_count():
		var src := am.surface_get_arrays(s)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
			arr[a] = src[a]
		if arr[Mesh.ARRAY_INDEX] == null:
			var idx := PackedInt32Array()
			for i in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				idx.append(i)
			arr[Mesh.ARRAY_INDEX] = idx
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, am.surface_get_material(s))
	im.generate_lods(25.0, 60.0, [])
	var out := ArrayMesh.new()
	for s in im.get_surface_count():
		var arr := im.get_surface_arrays(s)
		var share := float((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3) / maxf(total, 1)
		var want := int(tris * share)
		var best: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for l in im.get_surface_lod_count(s):
			var li := im.get_surface_lod_indices(s, l)
			if li.size() / 3 >= want and li.size() < best.size():
				best = li
		arr[Mesh.ARRAY_INDEX] = best
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, im.get_surface_material(s))
	return out


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
	am = _reduced(am, BUDGET["bench"])
	return {"mesh": am, "aabb": AABB(Vector3(-0.92, 0, -0.3), Vector3(1.84, 0.475, 0.6)), "col": ["box"]}


const PICKET_LEN := 2.0
const CHAINLINK_LEN := 1.99
static var picket_mat: StandardMaterial3D


## A 2 m run of white picket fence along X (centred, standing on y = 0): a post at each end, two rails behind,
## eleven pointed pickets in front (the front faces -Z).
static func _picket_fence() -> Dictionary:
	if picket_mat == null:
		picket_mat = StandardMaterial3D.new()
		picket_mat.albedo_color = Color(0.93, 0.92, 0.88)
		picket_mat.roughness = 0.75
		picket_mat.vertex_color_use_as_albedo = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := PICKET_LEN * 0.5
	for x: float in [-half + 0.045, half - 0.045]:
		_box_into(st, Vector3(x, 0.55, 0.02), Vector3(0.09, 1.1, 0.09), Color(0.9, 0.89, 0.85))
	for y: float in [0.28, 0.74]:
		_box_into(st, Vector3(0, y, 0.035), Vector3(PICKET_LEN - 0.18, 0.07, 0.035), Color(0.88, 0.87, 0.83))
	var n := 11
	for i in n:
		var x := -half + 0.17 + i * (PICKET_LEN - 0.34) / (n - 1)
		var tint := Color(1, 1, 1) * (0.97 + 0.03 * sin(i * 2.3))
		_picket_into(st, x, tint)
	var am := st.commit()
	am.surface_set_material(0, picket_mat)
	return {"mesh": am, "aabb": AABB(Vector3(-half, 0, -0.06), Vector3(PICKET_LEN, 1.05, 0.12)), "col": ["box"]}


## An axis-aligned box into a SurfaceTool (flat faces; normals generated after).
static func _box_into(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)]]
	st.set_color(col)
	for f: Array in faces:
		var nrm: Vector3 = f[0]
		st.set_normal(nrm)
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + nrm * h
		var du := u * h
		var dv := v * h
		var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_uv(Vector2(1.0 if k == 1 or k == 2 else 0.0, 1.0 if k >= 2 else 0.0))
			st.add_vertex(q[k])


## One picket: a slat 0.085 wide with a pointed top, 2 cm thick, in front of the rails.
static func _picket_into(st: SurfaceTool, x: float, col: Color) -> void:
	_box_into(st, Vector3(x, 0.47, 0.0), Vector3(0.085, 0.86, 0.02), col)
	var w := 0.0425
	st.set_color(col)
	for z: float in [-0.01, 0.01]:
		var a := Vector3(x - w, 0.9, z)
		var b := Vector3(x + w, 0.9, z)
		var t := Vector3(x, 0.99, z)
		st.set_normal(Vector3(0, 0, signf(z)))
		for v in ([a, b, t] if z < 0.0 else [a, t, b]):
			st.add_vertex(v)
	for side: float in [-1.0, 1.0]:
		var p0 := Vector3(x + side * w, 0.9, -0.01)
		var p1 := Vector3(x, 0.99, -0.01)
		var p2 := Vector3(x, 0.99, 0.01)
		var p3 := Vector3(x + side * w, 0.9, 0.01)
		st.set_normal(Vector3(side * 0.09, w, 0).normalized())
		var quad := [p0, p1, p2, p0, p2, p3] if side < 0.0 else [p0, p3, p2, p0, p2, p1]
		for v in quad:
			st.add_vertex(v)


## A 2 m bay of the chain-link fence kit: the double-width wire panel between two posts, along X and centred.
## The wire is alpha-tested (the kit ships it blended, which sorts badly against everything behind).
static func _chainlink_fence() -> Dictionary:
	var kit: Node = (load(PH % ["modular_chainlink_fence", "modular_chainlink_fence"]) as PackedScene).instantiate()
	var parts := {}
	for c in kit.find_children("*", "MeshInstance3D", true, false):
		parts[String(c.name)] = c
	var by_mat := {}
	var half := CHAINLINK_LEN * 0.5
	for p: Array in [["modular_chainlink_fence_double", Transform3D(Basis.IDENTITY, Vector3(half, 0, 0))],
			["modular_chainlink_fence_post", Transform3D(Basis.IDENTITY, Vector3(-half, 0, 0))],
			["modular_chainlink_fence_post", Transform3D(Basis.IDENTITY, Vector3(half, 0, 0))]]:
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
		var m := mat
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			# the kit's JPG colour map has lost its alpha: use the PNG (with the wire's opacity) and alpha-test it
			m = mat.duplicate()
			(m as BaseMaterial3D).albedo_texture = load("res://assets/models/polyhaven/modular_chainlink_fence/textures/modular_chainlink_fence_wire_rgba_1k.png")
			(m as BaseMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			(m as BaseMaterial3D).alpha_scissor_threshold = 0.4
			(m as BaseMaterial3D).alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			(m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		am.surface_set_material(am.get_surface_count() - 1, m)
	am = _reduced(am, 1500)
	return {"mesh": am, "aabb": AABB(Vector3(-half - 0.075, 0, -0.075), Vector3(CHAINLINK_LEN + 0.15, 2.4, 0.15)), "col": ["box"]}


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


# ------------------------------------------------------------------------------------------------ impostors

## Trees far away are drawn as camera-facing cards with a pre-rendered picture of the model (leaf cards don't
## survive mesh LOD). Baked once at load by rendering each tree into a viewport; skipped without a renderer.
const IMPOSTOR_NAMES := ["palm_crown", "date_palm", "jacaranda", "oak"]
static var _impostors := {}  # name -> QuadMesh


static func impostor(name: String) -> Mesh:
	return _impostors.get(name)


static func bake_impostors(host: Node) -> void:
	if not _impostors.is_empty() or DisplayServer.get_name() == "headless":
		return
	for name: String in IMPOSTOR_NAMES:
		var b: AABB = _entries[name].aabb
		var size := maxf(maxf(b.size.x, b.size.z), b.size.y)
		var vp := SubViewport.new()
		vp.size = Vector2i(256, 256)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		host.add_child(vp)
		var mi := MeshInstance3D.new()
		mi.mesh = _entries[name].mesh
		vp.add_child(mi)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = size * 1.02
		cam.position = Vector3(b.get_center().x, b.get_center().y, b.get_center().z + size * 2.0)
		cam.far = size * 5.0
		vp.add_child(cam)
		cam.current = true
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-35, 25, 0)
		sun.light_energy = 1.1
		vp.add_child(sun)
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.66, 0.7)
		env.ambient_light_energy = 0.9
		we.environment = env
		vp.add_child(we)
		RenderingServer.force_draw(false)
		var img := vp.get_texture().get_image()
		vp.queue_free()
		if img == null or img.is_empty():
			continue
		img.generate_mipmaps()
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		m.roughness = 0.9
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		q.center_offset = Vector3(b.get_center().x, b.get_center().y, 0)
		q.material = m
		_impostors[name] = q
