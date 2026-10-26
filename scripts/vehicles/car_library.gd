class_name CarLibrary
extends RefCounted
## Vehicle meshes in a normalized car frame: origin on the ground between the axles, forward = -Z, metres.
## The "Generic passenger car pack" (Sketchfab, CC-BY) is split into individual cars; other vehicles come one per
## glTF (SINGLE). Each surface is tagged with a kind (paint / body / cutout / glass / beacon) so Vehicle can give
## it a dentable shader, and light meshes are merged into front/rear "optics" with a role per vertex.
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

const DIR := "res://assets/models/sketchfab/"
## One glTF per vehicle. scale: to metres. forward: the nose direction in the file (or taken from the FL/FR wheel
## node names). Wheels by node-name substring, by mesh name (+ axle hubs that spin with them), or cut out of a
## merged mesh: [length, height, radius, inner |x|] cylinders in the mesh's own coordinates, one per axle.
## paint: material-name substring of the paintable body ("" = livery, keep it). beacons: node-name substring of
## an emergency light bar; beacon_boxes: light bar boxes to add (car frame) when the model has none.
const SINGLE := {
	"muscle": {"file": DIR + "muscle_phoenix/scene.gltf", "wheel_nodes": "WheelStock", "paint": "Bodymat"},
	"police": {"file": DIR + "police_cruiser/scene.gltf", "wheel_nodes": "WheelStamp", "paint": "", "beacons": "Lightbar"},
	"van": {"file": DIR + "van_shvan/scene.gltf", "wheel_nodes": "WheelStock", "paint": "bodymat"},
	"ambulance": {"file": DIR + "ambulance_shvan/scene.gltf", "wheel_nodes": "WheelStock", "paint": "", "beacons": "Lightbar"},
	"boxtruck": {"file": DIR + "truck_lct/scene.gltf", "wheel_nodes": "WheelStock", "paint": "Bodymat"},
	"bus": {"file": DIR + "town_bus/scene.gltf", "scale": 0.092, "forward": Vector3(1, 0, 0),
		"wheel_meshes": ["Object_10", "Object_11", "Object_12", "Object_14"], "hub_meshes": ["Object_13", "Object_15"], "paint": ""},
	"firetruck": {"file": DIR + "fire_truck/scene.gltf", "scale": 4.4, "forward": Vector3(0, 0, 1),
		"cut_wheels": [[-0.472, -0.272, 0.124, 0.12, 1.06], [0.415, -0.278, 0.124, 0.035]], "paint": "",
		"beacon_boxes": [[Vector3(-0.85, 3.02, -3.05), Vector3(0.5, 0.16, 0.22)], [Vector3(0.85, 3.02, -3.05), Vector3(0.5, 0.16, 0.22)]]},
	# no wheels: framed on the bounding box (origin under its centre). spin: parts that rotate (axis in car frame)
	"heli": {"file": DIR + "police_heli/scene.gltf", "scale": 4.5, "forward": Vector3(0, 0, 1), "paint": "",
		"spin": {"rotor": Vector3.UP, "tail": Vector3.RIGHT}},
	"speedboat": {"file": DIR + "speedboat/scene.gltf", "forward": Vector3(0, 0, 1), "paint": ""},
	# two-wheelers. root_node: use only that subtree (the dirt bike file holds seven bikes). wheel_groups: node names
	# (dots become underscores in Godot) whose meshes spin as one wheel, the first group is the front wheel.
	"dirtbike": {"file": DIR + "dirt_bikes/scene.gltf", "root_node": "dirt_bike red", "paint": "",
		"wheel_groups": [["front_003"], ["rear_003"]]},  # the importer turns "*_wheel" nodes into VehicleWheel3Ds named front_003 etc.
	"bicycle": {"file": DIR + "bicycle_yellow/scene.gltf", "scale": 0.0036, "paint": "",
		"wheel_groups": [["Cylinder_018", "Circle_015", "Cylinder_038", "Cylinder_039", "Cylinder_040", "Cylinder_041", "Cylinder_042",
			"Cylinder_043", "Cylinder_044", "Cylinder_045", "Cylinder_046", "Cylinder_047", "Cylinder_048", "Cylinder_049", "Cylinder_050"],
			["Cylinder_017", "Circle_002", "Cylinder_021", "Cylinder_024", "Cylinder_027", "Cylinder_028", "Cylinder_029", "Cylinder_030",
			"Cylinder_031", "Cylinder_032", "Cylinder_033", "Cylinder_034", "Cylinder_035", "Cylinder_036", "Cylinder_037"]]},
}
## light mesh roles by node name (checked in order), stored in the optics' vertex alpha for car_lights.gdshader
const ROLES := [["Blinker", 0.5], ["Reverse", 0.7], ["Brakelight", 0.3], ["Taillight", 0.3], ["Headlight", 0.1]]

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
	if SINGLE.has(model):
		if not _cache.has(model):
			_cache[model] = _extract_single(model)
			_cut_doors(_cache[model], model)
		return _cache[model]
	if not _cache.has("sedan"):
		# Extract every model in one pass and free the pack right away: keeping an out-of-tree node
		# tree in a static var outlives the RenderingServer and crashes the game on exit.
		var pack: Node3D = (load(PACK) as PackedScene).instantiate()
		for m in MODELS:
			_cache[m] = _extract(pack, m)
			_cut_doors(_cache[m], m)
		pack.free()
		_optics_img = null
	return _cache[model]


## Vehicles whose front doors are cut out of the body to swing open (none of the files has separate doors).
const NO_DOORS := ["heli", "speedboat", "dirtbike", "bicycle"]


## Cuts the front doors out of the body: the outer shell's triangles (skin, window, mirror) between the front
## wheel arch and just behind the seat, on each side, become a separate mesh hinged at the door's front edge
## (data.doors: [{side (-1 driver / 1 passenger), mesh, kinds, hinge}] in the car frame). Closed, the car looks
## exactly as before. Done once per model while loading.
static func _cut_doors(data: Dictionary, model: String) -> void:
	data["doors"] = []
	if model in NO_DOORS or (data.wheels as Array).size() < 4:
		return
	var aabb: AABB = data.aabb
	var front_z := INF
	var front_r := 0.3
	for w: Dictionary in data.wheels:
		if (w.pos as Vector3).z < front_z:
			front_z = (w.pos as Vector3).z
			front_r = float(w.radius)
	var spec: Dictionary = Vehicle.SPECS.get(model, Vehicle.SPECS.sedan)
	var seat_z: float = aabb.position.z + float(spec.seat_z) if spec.has("seat_z") else front_z * 0.18
	var seat_y: float = aabb.position.y + aabb.size.y * float(spec.get("seat_y", 0.3))
	var long_door: bool = model in ["coupe", "sport", "muscle"]
	var z0 := maxf(seat_z - (0.95 if long_door else 0.85), front_z + front_r + 0.06)
	var z1 := seat_z + (0.45 if long_door else 0.3)
	var y0 := maxf(aabb.position.y + front_r * 0.55, seat_y - 0.5)
	var y1 := seat_y + 0.95
	if seat_z < front_z + front_r + 0.3:
		# cab over the front axle (trucks): the door is above the wheel arch, beside the seat
		z0 = seat_z - 0.55
		z1 = seat_z + 0.5
		y0 = maxf(y0, aabb.position.y + front_r * 2.0 + 0.08)
	var only_side := 0
	if model == "bus":
		# the bus's door is ahead of the front wheel on the kerb side
		z0 = aabb.position.z + 0.25
		z1 = front_z - front_r - 0.08
		y0 = aabb.position.y + 0.3
		y1 = aabb.position.y + 2.7
		only_side = 1
	if OS.has_environment("DOOR_DEBUG"):
		print("DOORS %s z %.2f..%.2f y %.2f..%.2f seat %.2f/%.2f front %.2f r %.2f aabb %s" % [model, z0, z1, y0, y1, seat_z, seat_y, front_z, front_r, aabb])
	# the body's sides from the wheel track (a model's bounds can carry stray geometry)
	var cx := 0.0
	for w: Dictionary in data.wheels:
		cx += (w.pos as Vector3).x / 4.0
	var half := 0.0
	for w: Dictionary in data.wheels:
		half = maxf(half, absf((w.pos as Vector3).x - cx) + 0.14)
	var inner := half * 0.6
	# per side: material -> [SurfaceTool, kind]
	var door_st := {-1: {}, 1: {}}
	var bounds := {-1: [INF, -INF], 1: [INF, -INF]}   # outer x extent of each door
	var new_parts := []
	for p: Array in data.parts:
		var mesh: ArrayMesh = p[0]
		var xf: Transform3D = p[1]
		var kinds: Array = p[2]
		var part_box := xf * mesh.get_aabb()
		if part_box.end.z < z0 or part_box.position.z > z1 or part_box.end.y < y0 or part_box.position.y > y1 \
				or (part_box.position.x > cx - inner and part_box.end.x < cx + inner):
			new_parts.append(p)
			continue
		var keep := ArrayMesh.new()
		var keep_kinds: Array[String] = []
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			var kept := PackedInt32Array()
			var mat := mesh.surface_get_material(si)
			var kind: String = kinds[si] if si < kinds.size() else "body"
			for t in range(0, idx.size() - 2, 3):
				var a := idx[t]
				var b := idx[t + 1]
				var c := idx[t + 2]
				# a triangle is door only if all its corners are in the door's box (big panels stay on the body)
				var pa := xf * verts[a]
				var pb := xf * verts[b]
				var pc := xf * verts[c]
				var side := 0
				if minf(pa.z, minf(pb.z, pc.z)) > z0 - 0.04 and maxf(pa.z, maxf(pb.z, pc.z)) < z1 + 0.04 \
						and minf(pa.y, minf(pb.y, pc.y)) > y0 - 0.04 and maxf(pa.y, maxf(pb.y, pc.y)) < y1 + 0.04:
					var mx := maxf(pa.x, maxf(pb.x, pc.x))
					var nx := minf(pa.x, minf(pb.x, pc.x))
					if mx < cx - inner and only_side != 1:
						side = -1
					elif nx > cx + inner and only_side != -1:
						side = 1
				if side == 0:
					kept.append(a)
					kept.append(b)
					kept.append(c)
					continue
				var sides: Dictionary = door_st[side]
				if not sides.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					sides[mat] = [st, kind, not uvs.is_empty()]
				var st2: SurfaceTool = sides[mat][0]
				for vi in [a, b, c]:
					if not normals.is_empty():
						st2.set_normal((xf.basis * normals[vi]).normalized())
					if not uvs.is_empty():
						st2.set_uv(uvs[vi])
					var wv := xf * verts[vi]
					st2.add_vertex(wv)
					bounds[side][0] = minf(bounds[side][0], wv.x)
					bounds[side][1] = maxf(bounds[side][1], wv.x)
			if kept.is_empty():
				continue
			arr[Mesh.ARRAY_INDEX] = kept
			keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			keep.surface_set_material(keep.get_surface_count() - 1, mat)
			keep_kinds.append(kind)
		if keep.get_surface_count() > 0:
			new_parts.append([keep, xf, keep_kinds])
	data.parts = new_parts
	for side: int in [-1, 1]:
		var sides: Dictionary = door_st[side]
		if sides.is_empty():
			continue
		var dm := ArrayMesh.new()
		var dkinds: Array[String] = []
		for mat: Variant in sides:
			var st: SurfaceTool = sides[mat][0]
			if sides[mat][2]:
				st.generate_tangents()
			st.commit(dm)
			dm.surface_set_material(dm.get_surface_count() - 1, mat)
			dkinds.append(sides[mat][1])
		var outer_x: float = bounds[side][0] if side < 0 else bounds[side][1]
		(data.doors as Array).append({"side": side, "mesh": dm, "kinds": dkinds,
			"hinge": Vector3(outer_x - side * 0.04, (y0 + y1) * 0.5, z0)})


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
		var kinds: Array[String] = []
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat and String(mat.resource_name).begins_with("Optics"):
				# lights: split into front (headlights) and rear (tail/brake/reverse) in the car frame
				optics_mat = mat
				_split_optics(mesh.surface_get_arrays(s), xf, optics, amber, _optics_image(mat))
				continue
			keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
			keep.surface_set_material(keep.get_surface_count() - 1, mat)
			var mname := String(mat.resource_name) if mat else ""
			kinds.append("paint" if mname.begins_with("Body") else ("glass" if mname.begins_with("Glass") else "body"))
		parts.append([keep, xf, kinds])
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


# ------------------------------------------------------------------------------------------------ single models

static func _extract_single(model: String) -> Dictionary:
	var cfg: Dictionary = SINGLE[model]
	var root: Node3D = (load(cfg.file) as PackedScene).instantiate()
	var sc: float = cfg.get("scale", 1.0)
	var all: Array[MeshInstance3D] = []
	var sub: Node = root.find_child(cfg.root_node, true, false) if cfg.has("root_node") else root
	for mi in sub.find_children("*", "MeshInstance3D", true, false):
		all.append(mi)
	var used := {}
	var groups := []          # {parts: [[mesh, pack xf]], center, aabb, name}
	var replaced := {}        # MeshInstance3D -> ArrayMesh left after cutting the wheels out
	if cfg.has("wheel_nodes"):
		for n in root.find_children("*" + String(cfg.wheel_nodes) + "*", "Node3D", true, false):
			if n is MeshInstance3D:
				continue
			var ms: Array[MeshInstance3D] = []
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				ms.append(mi)
				used[mi] = true
			if ms.is_empty():
				continue
			var a := _global_aabb(ms)
			groups.append({"parts": ms.map(func(m): return [m.mesh, _gxf(m)]), "center": a.get_center(), "aabb": a, "name": String(n.name)})
	elif cfg.has("wheel_groups"):
		var gi := 0
		for names: Array in cfg.wheel_groups:
			var ms: Array[MeshInstance3D] = []
			for mi in all:
				var n: Node = mi
				while n and n != root:
					if String(n.name) in names:
						ms.append(mi)
						used[mi] = true
						break
					n = n.get_parent()
			if not ms.is_empty():
				var a := _global_aabb(ms)
				groups.append({"parts": ms.map(func(m): return [m.mesh, _gxf(m)]), "center": a.get_center(), "aabb": a,
					"name": "_F" if gi == 0 else "_R"})
			gi += 1
	elif cfg.has("wheel_meshes"):
		for nm: String in cfg.wheel_meshes:
			var mi: MeshInstance3D = root.find_child(nm, true, false)
			used[mi] = true
			var a := _gxf(mi) * mi.get_aabb()
			groups.append({"parts": [[mi.mesh, _gxf(mi)]], "center": a.get_center(), "aabb": a, "name": nm})
	elif cfg.has("cut_wheels"):
		var mi: MeshInstance3D = all[0]
		var cut := _cut_wheels(mi, cfg.cut_wheels)
		replaced[mi] = cut[0]
		for g: Dictionary in cut[1]:
			groups.append(g)
	# nose direction and the axles
	var fwd: Vector3 = cfg.get("forward", Vector3.ZERO)
	if fwd == Vector3.ZERO:
		var fm := Vector3.ZERO
		var rm := Vector3.ZERO
		var nf := 0
		for g: Dictionary in groups:
			if g.name.contains("_F"):
				fm += g.center
				nf += 1
			else:
				rm += g.center
		fwd = fm / maxf(nf, 1) - rm / maxf(groups.size() - nf, 1)
	fwd.y = 0
	fwd = fwd.normalized()
	if groups.is_empty():
		# no wheels (aircraft, boats): frame on the overall bounds
		var bb := _global_aabb(all)
		groups.append({"parts": [], "center": bb.get_center() - Vector3(0, bb.size.y * 0.5, 0), "aabb": AABB(bb.position, Vector3(0, 0, 0)), "name": "_none"})
	var along := groups.map(func(g): return (g.center as Vector3).dot(fwd))
	var lo: float = along.min()
	var hi: float = along.max()
	var mid := Vector3.ZERO
	var ground_y := INF
	for g: Dictionary in groups:
		mid += g.center
		ground_y = minf(ground_y, (g.aabb as AABB).position.y)
	mid /= groups.size()
	# origin halfway between the front and rear axles (not the wheel centroid: buses have more wheels behind)
	mid += fwd * ((lo + hi) * 0.5 - mid.dot(fwd))
	var z := -fwd
	var x := Vector3.UP.cross(z).normalized()
	var frame := Transform3D(Basis(x, Vector3.UP, z), Vector3(mid.x, ground_y, mid.z))
	var car := Transform3D(Basis.from_scale(Vector3.ONE * sc), Vector3.ZERO) * frame.affine_inverse()
	# hubs ride with the nearest wheel
	for nm: String in cfg.get("hub_meshes", []):
		var mi: MeshInstance3D = root.find_child(nm, true, false)
		used[mi] = true
		var c := (_gxf(mi) * mi.get_aabb()).get_center()
		var best: Dictionary = groups[0]
		for g: Dictionary in groups:
			if absf((g.center - c).dot(fwd)) < absf((best.center - c).dot(fwd)):
				best = g
		best.parts.append([mi.mesh, _gxf(mi)])

	var parts := []
	var optics := {"front": SurfaceTool.new(), "rear": SurfaceTool.new()}
	var optics_mat: Material = null
	for st: SurfaceTool in optics.values():
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spinners := []
	var spin: Dictionary = cfg.get("spin", {})
	var paint_key: String = cfg.get("paint", "")
	var beacon_key: String = cfg.get("beacons", "")
	var body_aabb := AABB()
	var first := true
	for mi in all:
		if used.has(mi):
			continue
		var xf := car * _gxf(mi)
		var mesh: Mesh = replaced.get(mi, mi.mesh)
		var path := _path_name(mi)
		var spin_axis := Vector3.ZERO
		for key: String in spin:
			if path.contains(key):
				spin_axis = spin[key]
		if spin_axis != Vector3.ZERO:
			var c := (xf * mi.get_aabb()).get_center()
			spinners.append({"mesh": mi.mesh, "xf": Transform3D(Basis.IDENTITY, -c) * xf, "pivot": c, "axis": spin_axis,
				"radius": (xf * mi.get_aabb()).size.x * 0.5})
			continue
		var role := -1.0
		# the mesh instance itself is named after its material ("..._Lights_and_Glass_0"): judge by its parents
		if not _path_name(mi.get_parent()).to_lower().contains("glass"):
			for r: Array in ROLES:
				if path.contains(r[0]):
					role = r[1]
					break
		var keep := ArrayMesh.new()
		var kinds: Array[String] = []
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si)
			var arr := _clean(mesh.surface_get_arrays(si))
			if role >= 0.0:
				optics_mat = mat
				_add_role_tris(arr, xf, optics, role)
				continue
			var mname := String(mat.resource_name).to_lower() if mat else ""
			var kind := "body"
			if beacon_key != "" and path.contains(beacon_key):
				kind = "beacon"
			elif mname.contains("glass") or mname.contains("transperent") or mname.contains("transparent"):
				kind = "glass"
			elif paint_key != "" and mname.contains(paint_key.to_lower()):
				kind = "paint"
			elif mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				kind = "cutout"
			keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			keep.surface_set_material(keep.get_surface_count() - 1, mat)
			kinds.append(kind)
		if keep.get_surface_count() > 0:
			parts.append([keep, xf, kinds])
			var a := xf * keep.get_aabb()
			body_aabb = a if first else body_aabb.merge(a)
			first = false
	var optic_meshes := {}
	for k: String in optics:
		var st: SurfaceTool = optics[k]
		st.generate_normals()
		var m := st.commit()
		if m.get_surface_count() > 0:
			optic_meshes[k] = m
	var wheel_data := []
	for g: Dictionary in groups:
		if g.name == "_none":
			continue
		var c := car * (g.center as Vector3)
		var wparts := []
		for pp: Array in g.parts:
			wparts.append([pp[0], Transform3D(Basis.IDENTITY, -c) * car * (pp[1] as Transform3D)])
		wheel_data.append({"pos": c, "radius": (g.aabb as AABB).size.y * 0.5 * sc, "parts": wparts})
	root.free()
	return {"parts": parts, "wheels": wheel_data, "aabb": body_aabb, "optics": optic_meshes, "optics_mat": optics_mat,
		"amber": {"front": true, "rear": true}, "roles": true, "beacon_boxes": cfg.get("beacon_boxes", []), "spinners": spinners}


## Surface arrays without the custom channels and skinning some files carry (not needed, and they'd need
## matching format flags to be re-added).
static func _clean(arr: Array) -> Array:
	for i in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		arr[i] = null
	return arr


## Names of a node and its ancestors (light meshes are named on their parent nodes in these files).
static func _path_name(n: Node) -> String:
	var out := ""
	while n:
		out += String(n.name) + "/"
		n = n.get_parent()
	return out


## Light triangles into front/rear SurfaceTools with their role in the vertex alpha.
static func _add_role_tris(arr: Array, xf: Transform3D, out: Dictionary, role: float) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] else PackedInt32Array(range(v.size()))
	for t in range(0, idx.size(), 3):
		var a := xf * v[idx[t]]
		var b := xf * v[idx[t + 1]]
		var c := xf * v[idx[t + 2]]
		var st: SurfaceTool = out["front" if (a.z + b.z + c.z) < 0.0 else "rear"]
		for k in 3:
			st.set_color(Color(1, 1, 1, role))
			if uv.size() > 0:
				st.set_uv(uv[idx[t + k]])
			st.add_vertex([a, b, c][k])


## Split the wheels out of a merged mesh: triangles inside each axle's cylinder (left and right of the centre
## line, beyond the inner |x|) become a wheel. Returns [remaining body mesh, wheel groups].
static func _cut_wheels(mi: MeshInstance3D, specs: Array) -> Array:
	var gx := _gxf(mi)
	var body := ArrayMesh.new()
	var groups := []
	var mesh := mi.mesh
	for si in mesh.get_surface_count():
		var arr := _clean(mesh.surface_get_arrays(si))
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] else PackedInt32Array(range(v.size()))
		var keep := PackedInt32Array()
		var wheel_idx := []
		for i in specs.size() * 2:
			wheel_idx.append([])  # plain Arrays: packed arrays are copied on access
		for t in range(0, idx.size(), 3):
			var hit := -1
			for wi in specs.size():
				var sp: Array = specs[wi]
				var inside := 0
				var side := 0.0
				for k in 3:
					var p := v[idx[t + k]]
					# optional 5th value: how far out (x radius) to take triangles; past the tyre is the arch liner
					if Vector2(p.y - sp[0], p.z - sp[1]).length() < sp[2] * (float(sp[4]) if sp.size() > 4 else 1.14) and absf(p.x) > sp[3]:
						inside += 1
						side += p.x
				if inside == 3:
					hit = wi * 2 + (0 if side < 0.0 else 1)
					break
			if hit < 0:
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			else:
				(wheel_idx[hit] as Array).append_array([idx[t], idx[t + 1], idx[t + 2]])
		var mat := mesh.surface_get_material(si)
		var a2 := arr.duplicate()
		a2[Mesh.ARRAY_INDEX] = keep
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		body.surface_set_material(body.get_surface_count() - 1, mat)
		for wi in wheel_idx.size():
			var ids := PackedInt32Array(wheel_idx[wi])
			if ids.is_empty():
				continue
			var sp: Array = specs[wi / 2]
			var wm := ArrayMesh.new()
			var a3 := arr.duplicate()
			a3[Mesh.ARRAY_INDEX] = ids
			wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a3)
			wm.surface_set_material(0, mat)
			var sx := 0.0
			for i in ids:
				sx += v[i].x
			var local := Vector3(sx / ids.size(), sp[0], sp[1])
			var r: float = sp[2]
			var bb := AABB(gx * (local - Vector3(0.05, r, r)), Vector3.ZERO).expand(gx * (local + Vector3(0.05, r, r)))
			groups.append({"parts": [[wm, gx]], "center": gx * local, "aabb": bb, "name": "cut%d" % wi})
	return [body, groups]
