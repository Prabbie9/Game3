class_name Uniform
extends RefCounted
## Police / SWAT kit fitted to any Mixamo character (the library has no uniformed characters): a duty vest
## shrink-wrapped round the character's own torso and skinned with the weights of the nearest body vertices, so
## it bends and ragdolls with the body; a peaked cap (police) or a helmet (SWAT) on the head; POLICE / SWAT
## lettering on the back and a badge on the chest. The fitted meshes are built once per character and shared.

const RINGS := 10
const SEGS := 32
const INFLATE := 0.016

static var _cache := {}   # character -> {vest: ArrayMesh, skin: Skin, back: Transform3D, chest: Transform3D, head: Dictionary}
static var _mats := {}
static var _lock := Mutex.new()
static var _pending := {}   # character -> WorkerThreadPool task id


static func dress(v: HumanoidVisual, kind: String) -> void:
	if v == null or v.skeleton == null or v.skeleton.has_node("UniformVest"):
		return
	var fit: Dictionary = _fit(v)
	if fit.is_empty():
		return
	var sk := v.skeleton
	var swat := kind == "swat"
	var vest := MeshInstance3D.new()
	vest.name = "UniformVest"
	vest.mesh = fit.vest
	vest.skin = fit.skin
	vest.material_override = _mat("swat_vest" if swat else "police_vest")
	sk.add_child(vest)
	vest.skeleton = NodePath("..")
	# lettering on the back and a badge / name on the chest, riding on the upper chest
	var chest := BoneAttachment3D.new()
	chest.bone_name = "UpperChest"
	sk.add_child(chest)
	var rest_inv := sk.get_bone_global_rest(sk.find_bone("UpperChest")).affine_inverse()
	var back := Label3D.new()
	back.text = "SWAT" if swat else "POLICE"
	back.font_size = 72
	back.outline_size = 0
	back.pixel_size = 0.00085
	back.shaded = true
	back.double_sided = false
	back.modulate = Color(0.92, 0.9, 0.8) if swat else Color(0.95, 0.85, 0.35)
	back.transform = rest_inv * (fit.back as Transform3D)
	chest.add_child(back)
	var front := Label3D.new()
	front.text = back.text
	front.font_size = 72
	front.outline_size = 0
	front.pixel_size = 0.00034
	front.shaded = true
	front.double_sided = false
	front.modulate = back.modulate
	front.transform = rest_inv * (fit.chest_r as Transform3D)
	chest.add_child(front)
	if not swat:
		var badge := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.022
		cyl.bottom_radius = 0.022
		cyl.height = 0.005
		cyl.radial_segments = 6
		cyl.rings = 1
		badge.mesh = cyl
		badge.material_override = _mat("gold")
		badge.transform = rest_inv * (fit.chest_l as Transform3D) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		chest.add_child(badge)
	# headwear
	var head := BoneAttachment3D.new()
	head.bone_name = "Head"
	sk.add_child(head)
	var hat := MeshInstance3D.new()
	hat.name = "UniformHat"
	hat.mesh = _helmet(fit.head) if swat else _cap(fit.head)
	hat.transform = sk.get_bone_global_rest(sk.find_bone("Head")).affine_inverse()
	head.add_child(hat)
	for n: Node in [vest, hat]:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _mat(id: String) -> Material:
	if _mats.has(id):
		return _mats[id]
	var m := StandardMaterial3D.new()
	match id:
		"police_vest":
			m.albedo_color = Color(0.05, 0.065, 0.11)
			m.roughness = 0.85
		"swat_vest":
			m.albedo_color = Color(0.035, 0.035, 0.04)
			m.roughness = 0.9
		"cap":
			m.albedo_color = Color(0.04, 0.05, 0.09)
			m.roughness = 0.8
		"visor":
			m.albedo_color = Color(0.015, 0.015, 0.02)
			m.roughness = 0.25
		"helmet":
			m.albedo_color = Color(0.03, 0.03, 0.035)
			m.roughness = 0.55
		"gold":
			m.albedo_color = Color(0.85, 0.68, 0.3)
			m.metallic = 1.0
			m.roughness = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = id == "cap" or id == "helmet"
	if m.vertex_color_use_as_albedo:
		m.albedo_color = Color.WHITE
	_mats[id] = m
	return m


# --- fitting --------------------------------------------------------------------

## What the fitting needs from a character, copied on the main thread (bone rests, skinned mesh arrays).
static func _snapshot(sk: Skeleton3D) -> Dictionary:
	var rests := {}
	for i in sk.get_bone_count():
		rests[sk.get_bone_name(i)] = sk.get_bone_global_rest(i)
	var meshes := []
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", false, false):
		if mi.mesh == null or mi.skin == null or mi.name.begins_with("Uniform"):
			continue
		var skin := mi.skin
		var names := PackedStringArray()
		var poses := []
		for b in skin.get_bind_count():
			var nm := skin.get_bind_name(b)
			if nm == "":
				nm = sk.get_bone_name(skin.get_bind_bone(b))
			names.append(nm)
			poses.append(skin.get_bind_pose(b))
		var surfs := []
		for si in mi.mesh.get_surface_count():
			surfs.append(mi.mesh.surface_get_arrays(si))
		meshes.append({"xf": mi.transform, "names": names, "poses": poses, "surfs": surfs})
	return {"rests": rests, "meshes": meshes}


## Collect the character's skinned vertices (skeleton space) with their bone influences by name.
static func _gather(snap: Dictionary) -> Dictionary:
	var pos := PackedVector3Array()
	var infl: Array = []      # per vertex: [[bone name, weight]...]
	var dom := PackedStringArray()
	var binds := {}           # bone name -> bind pose
	for m: Dictionary in snap.meshes:
		var names: PackedStringArray = m.names
		for b in names.size():
			if not binds.has(names[b]):
				binds[names[b]] = m.poses[b]
		var xf: Transform3D = m.xf
		for arr: Array in m.surfs:
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones == null or weights == null or (bones as PackedInt32Array).is_empty():
				continue
			var per := (bones as PackedInt32Array).size() / verts.size()
			for i in verts.size():
				pos.append(xf * verts[i])
				var inf := []
				var best := -1.0
				var bn := ""
				for k in per:
					var w: float = weights[i * per + k]
					if w <= 0.001:
						continue
					var nm: String = names[bones[i * per + k]]
					inf.append([nm, w])
					if w > best:
						best = w
						bn = nm
				infl.append(inf)
				dom.append(bn)
	return {"pos": pos, "infl": infl, "dom": dom, "binds": binds}


static func _fit(v: HumanoidVisual) -> Dictionary:
	var key := v.character_file
	_lock.lock()
	var have: bool = _cache.has(key)
	var fit: Dictionary = _cache.get(key, {})
	_lock.unlock()
	if have:
		if fit.has("arrays"):
			fit = _finalize(fit)
			_store(key, fit)
		return fit
	if _pending.has(key):
		WorkerThreadPool.wait_for_task_completion(_pending[key])
		_pending.erase(key)
		return _fit(v)
	fit = _fit_snapshot(_snapshot(v.skeleton))
	if fit.has("arrays"):
		fit = _finalize(fit)
	_store(key, fit)
	return fit


## Build the vest mesh and its skin from the fitted arrays (main thread).
static func _finalize(raw: Dictionary) -> Dictionary:
	var fit := raw.duplicate()
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, raw.arrays)
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.generate_normals()
	var mesh := st.commit()
	var skin := Skin.new()
	for b: Array in raw.binds:
		skin.add_named_bind(b[0], b[1])
	fit.erase("arrays")
	fit.erase("binds")
	fit.vest = mesh
	fit.skin = skin
	return fit


## Fit a character's kit on a worker thread (once the character has loaded), so dressing it later is instant.
static func prewarm(character: String) -> void:
	_lock.lock()
	var have: bool = _cache.has(character)
	_lock.unlock()
	if have or _pending.has(character):
		return
	var model: Node3D = load(HumanoidVisual.CHAR_PATH % character).instantiate()
	var snap := _snapshot(model.get_node("GeneralSkeleton"))
	model.free()
	_pending[character] = WorkerThreadPool.add_task(func(): _store(character, _fit_snapshot(snap)), false, "uniform fit")


## Wait for any background fits (before the world goes away or the game quits).
static func finish() -> void:
	for k: String in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[k])
	_pending.clear()


static func _store(key: String, fit: Dictionary) -> void:
	_lock.lock()
	_cache[key] = fit
	_lock.unlock()


static func _fit_snapshot(snap: Dictionary) -> Dictionary:
	var rests: Dictionary = snap.rests
	var g := _gather(snap)
	if (g.pos as PackedVector3Array).is_empty():
		return {}
	var bone_y := func(n: String) -> Vector3: return (rests[n] as Transform3D).origin
	var hips: Vector3 = bone_y.call("Hips")
	var neck: Vector3 = bone_y.call("Neck")
	var arm_x := absf((bone_y.call("LeftUpperArm") as Vector3).x - (bone_y.call("RightUpperArm") as Vector3).x) * 0.5
	var y_lo := hips.y + 0.03
	var y_hi := neck.y - 0.045
	var torso_bones := ["Hips", "Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder"]
	# torso vertices (clothes and body), arms and head excluded
	var tp := PackedVector3Array()
	var ti := PackedInt32Array()
	var P: PackedVector3Array = g.pos
	for i in P.size():
		var p := P[i]
		if p.y < y_lo - 0.06 or p.y > y_hi + 0.03 or absf(p.x - hips.x) > arm_x * 0.92:
			continue
		if not (g.dom[i] in torso_bones):
			continue
		tp.append(p)
		ti.append(i)
	if tp.size() < 50:
		return {}
	# rings of radii round the torso, pushed outwards (no hollows between the shoulder blades / under the bust)
	var rings: Array = []
	var centres: Array = []
	for r in RINGS:
		var y := lerpf(y_lo, y_hi, float(r) / (RINGS - 1))
		var band := (y_hi - y_lo) / (RINGS - 1) * 0.75
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in tp:
			if absf(p.y - y) < band:
				mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.z))
				mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.z))
		var c := (mn + mx) * 0.5 if mn.x < INF else Vector2(hips.x, hips.z)
		var rad := PackedFloat32Array()
		rad.resize(SEGS)
		rad.fill(0.0)
		for p in tp:
			if absf(p.y - y) < band:
				var d := Vector2(p.x, p.z) - c
				var a := int(floor(fposmod(atan2(d.y, d.x), TAU) / TAU * SEGS)) % SEGS
				rad[a] = maxf(rad[a], d.length())
		# fill empty sectors, then smooth outwards
		for pass_i in 3:
			for a in SEGS:
				if rad[a] <= 0.0:
					rad[a] = maxf(rad[(a + SEGS - 1) % SEGS], rad[(a + 1) % SEGS])
		for pass_i in 3:
			var nr := rad.duplicate()
			for a in SEGS:
				nr[a] = maxf(rad[a], (rad[(a + SEGS - 1) % SEGS] + rad[(a + 1) % SEGS]) * 0.5)
			rad = nr
		rings.append(rad)
		centres.append(c)
	for pass_i in 2:
		for r in range(1, RINGS - 1):
			var rr: PackedFloat32Array = rings[r]
			for a in SEGS:
				rr[a] = maxf(rr[a], ((rings[r - 1] as PackedFloat32Array)[a] + (rings[r + 1] as PackedFloat32Array)[a]) * 0.5)
			rings[r] = rr
	# vest surface: the rings, a lip at the hem, and a shoulder yoke closing in towards the neck
	var verts := PackedVector3Array()
	var ring_of := []   # ring y and scale per row
	for r in RINGS:
		ring_of.append([lerpf(y_lo, y_hi, float(r) / (RINGS - 1)), 1.0, r])
	ring_of.append([y_hi + 0.022, 0.8, RINGS - 1])
	ring_of.append([neck.y - 0.005, 0.5, RINGS - 1])
	var rows := ring_of.size()
	for row: Array in ring_of:
		var rr: PackedFloat32Array = rings[row[2]]
		var c: Vector2 = centres[row[2]]
		for a in SEGS:
			var ang := (a + 0.5) / SEGS * TAU
			var rad: float = (rr[a] + INFLATE) * float(row[1])
			verts.append(Vector3(c.x + cos(ang) * rad, row[0], c.y + sin(ang) * rad))
	var idx := PackedInt32Array()
	for r in rows - 1:
		for a in SEGS:
			var a2 := (a + 1) % SEGS
			var i0 := r * SEGS + a
			var i1 := r * SEGS + a2
			var i2 := (r + 1) * SEGS + a
			var i3 := (r + 1) * SEGS + a2
			idx.append_array([i0, i2, i1, i1, i2, i3])
	# armholes: drop the shoulder-yoke quads at the sides so the arms come out through openings
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 6):
		var r := (t / 6) / SEGS
		var a := (t / 6) % SEGS
		var ang := (a + 0.5) / SEGS * TAU
		var side := absf(cos(ang)) > 0.82
		if r >= RINGS - 1 and side:
			continue
		for k in 6:
			keep.append(idx[t + k])
	idx = keep
	# skin weights from the nearest torso vertex
	var grid := {}
	for k in tp.size():
		var cell := Vector3i((tp[k] / 0.05).floor())
		if not grid.has(cell):
			grid[cell] = PackedInt32Array()
		(grid[cell] as PackedInt32Array).append(k)
	var bind_names: Array = []
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for vp in verts:
		var cell := Vector3i((vp / 0.05).floor())
		var best := -1
		var bd := INF
		for rad in [1, 2, 3]:
			for dx in range(-rad, rad + 1):
				for dy in range(-rad, rad + 1):
					for dz in range(-rad, rad + 1):
						var lst = grid.get(cell + Vector3i(dx, dy, dz))
						if lst == null:
							continue
						for k: int in lst:
							var d := tp[k].distance_squared_to(vp)
							if d < bd:
								bd = d
								best = k
			if best >= 0:
				break
		var inf: Array = (g.infl as Array)[ti[best]] if best >= 0 else [["Chest", 1.0]]
		inf = inf.duplicate()
		inf.sort_custom(func(x, y): return x[1] > y[1])
		var tot := 0.0
		for k in 4:
			if k < inf.size():
				tot += float(inf[k][1])
		for k in 4:
			if k < inf.size():
				var nm: String = inf[k][0]
				var bi := bind_names.find(nm)
				if bi < 0:
					bind_names.append(nm)
					bi = bind_names.size() - 1
				bones.append(bi)
				weights.append(float(inf[k][1]) / tot)
			else:
				bones.append(0)
				weights.append(0.0)
	var binds := []
	for nm: String in bind_names:
		binds.append([nm, g.binds.get(nm, (rests[nm] as Transform3D).affine_inverse())])
	# (no mesh / RenderingServer calls here: this can run on a worker thread; _finalize builds the mesh)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	# lettering spots (skeleton space): back between the shoulder blades, chest left (badge) and right (name)
	var rb := int(RINGS * 0.68)
	var cb: Vector2 = centres[rb]
	var yb := lerpf(y_lo, y_hi, float(rb) / (RINGS - 1))
	var r_at := func(ring: int, ang: float) -> float:
		var a := int(floor(fposmod(ang, TAU) / TAU * SEGS)) % SEGS
		return (rings[ring] as PackedFloat32Array)[a] + INFLATE + 0.006
	var back := Transform3D(Basis(Vector3.UP, PI), Vector3(cb.x, yb, cb.y - r_at.call(rb, -PI * 0.5)))
	var rc := int(RINGS * 0.78)
	var cc: Vector2 = centres[rc]
	var yc := lerpf(y_lo, y_hi, float(rc) / (RINGS - 1))
	var la := PI * 0.5 - 0.55   # towards +X (the character's left), front is +Z
	var ra := PI * 0.5 + 0.55
	var chest_l := Transform3D(Basis(Vector3.UP, la - PI * 0.5).rotated(Vector3.UP, 0.0), Vector3(cc.x + cos(la) * r_at.call(rc, la), yc, cc.y + sin(la) * r_at.call(rc, la)))
	var chest_r := Transform3D(Basis(Vector3.UP, ra - PI * 0.5), Vector3(cc.x + cos(ra) * r_at.call(rc, ra), yc, cc.y + sin(ra) * r_at.call(rc, ra)))
	# face the labels outwards: Label3D reads from +Z
	chest_l.basis = Basis(Vector3.UP, -(la - PI * 0.5))
	chest_r.basis = Basis(Vector3.UP, -(ra - PI * 0.5))
	return {"arrays": arrays, "binds": binds, "back": back, "chest_l": chest_l, "chest_r": chest_r, "head": _head(g, rests)}


## Top of the head, its centre and radius at the brow (from the head and hair vertices).
static func _head(g: Dictionary, rests: Dictionary) -> Dictionary:
	var P: PackedVector3Array = g.pos
	var hb := (rests["Head"] as Transform3D).origin
	var top := -INF
	for i in P.size():
		if g.dom[i] == "Head" or String(g.dom[i]).contains("HeadTop"):
			top = maxf(top, P[i].y)
	if top == -INF:
		top = hb.y + 0.2
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in P.size():
		if P[i].y > top - 0.12 and (g.dom[i] == "Head" or String(g.dom[i]).contains("HeadTop")):
			mn = Vector2(minf(mn.x, P[i].x), minf(mn.y, P[i].z))
			mx = Vector2(maxf(mx.x, P[i].x), maxf(mx.y, P[i].z))
	var c := (mn + mx) * 0.5
	var r := maxf((mx.x - mn.x), (mx.y - mn.y)) * 0.5
	# the skull itself at the brow (narrower than the hair/ears band above)
	var smn := Vector2(INF, INF)
	var smx := Vector2(-INF, -INF)
	for i in P.size():
		if P[i].y > top - 0.08 and P[i].y < top - 0.04 and g.dom[i] == "Head":
			smn = Vector2(minf(smn.x, P[i].x), minf(smn.y, P[i].z))
			smx = Vector2(maxf(smx.x, P[i].x), maxf(smx.y, P[i].z))
	var sr := (smx.x - smn.x) * 0.5 if smn.x < INF else r
	return {"top": top, "c": c, "r": clampf(r, 0.075, 0.12), "skull": clampf(sr, 0.065, 0.1)}


static func _ring(st: SurfaceTool, c: Vector3, rx: float, rz: float, n: int) -> Array:
	var out := []
	for a in n:
		var ang := float(a) / n * TAU
		out.append(c + Vector3(cos(ang) * rx, 0, sin(ang) * rz))
	return out


static func _band(st: SurfaceTool, lo: Array, hi: Array, col: Color) -> void:
	st.set_color(col)
	var n := lo.size()
	for a in n:
		var b := (a + 1) % n
		st.add_vertex(lo[a]); st.add_vertex(hi[a]); st.add_vertex(lo[b])
		st.add_vertex(lo[b]); st.add_vertex(hi[a]); st.add_vertex(hi[b])


## Peaked police cap: navy crown flaring to a flat top, black band and visor, gold badge colour on the front.
static func _cap(h: Dictionary) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector2 = h.c
	var r: float = h.r + 0.012
	var top: float = h.top
	var n := 24
	var base := Vector3(c.x, top - 0.075, c.y)
	var r0 := _ring(st, base, r, r * 1.08, n)
	var r1 := _ring(st, base + Vector3(0, 0.035, 0), r * 1.0, r * 1.1, n)
	var r2 := _ring(st, base + Vector3(0, 0.085, 0.006), r * 1.18, r * 1.3, n)
	var r3 := _ring(st, base + Vector3(0, 0.1, 0.006), r * 1.1, r * 1.22, n)
	_band(st, r0, r1, Color(0.02, 0.02, 0.025))
	_band(st, r1, r2, Color(0.04, 0.05, 0.09))
	_band(st, r2, r3, Color(0.04, 0.05, 0.09))
	var ctr := base + Vector3(0, 0.104, 0.006)
	st.set_color(Color(0.04, 0.05, 0.09))
	for a in n:
		st.add_vertex(r3[a]); st.add_vertex(ctr); st.add_vertex(r3[(a + 1) % n])
	# visor: a half-moon off the front (+Z), tilted down
	st.set_color(Color(0.015, 0.015, 0.02))
	var vc := base + Vector3(0, 0.004, 0)
	for a in 12:
		var a0 := lerpf(0.15, PI - 0.15, a / 12.0)
		var a1 := lerpf(0.15, PI - 0.15, (a + 1) / 12.0)
		var in0 := vc + Vector3(cos(a0) * r, 0, sin(a0) * r * 1.08)
		var in1 := vc + Vector3(cos(a1) * r, 0, sin(a1) * r * 1.08)
		var out0 := in0 + Vector3(cos(a0) * 0.045, -0.018, sin(a0) * 0.06)
		var out1 := in1 + Vector3(cos(a1) * 0.045, -0.018, sin(a1) * 0.06)
		st.add_vertex(in0); st.add_vertex(out0); st.add_vertex(in1)
		st.add_vertex(in1); st.add_vertex(out0); st.add_vertex(out1)
	# badge on the front of the crown
	st.set_color(Color(0.85, 0.68, 0.3))
	var bf := base + Vector3(0, 0.055, r * 1.17 + 0.002)
	for a in 6:
		var a0 := float(a) / 6.0 * TAU
		var a1 := float(a + 1) / 6.0 * TAU
		st.add_vertex(bf); st.add_vertex(bf + Vector3(cos(a0), sin(a0), 0) * 0.016); st.add_vertex(bf + Vector3(cos(a1), sin(a1), 0) * 0.016)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _mat("cap"))
	return m


## SWAT helmet: a dome over the head, lower at the back, with a short brim.
static func _helmet(h: Dictionary) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector2 = h.c
	var r: float = h.skull + 0.024
	var top: float = h.top + 0.022
	var depth := 0.125    # crown to brow
	var n := 24
	var rows := []
	for k in 7:
		var phi := float(k) / 6.0 * PI * 0.5       # 0 at the rim, 90° at the crown
		var y := top - depth * (1.0 - sin(phi))
		var ring := []
		for a in n:
			var ang := float(a) / n * TAU
			# lower over the back of the head and the ears, cut higher over the brow
			var drop := (0.045 * maxf(0.0, -sin(ang)) + 0.02 * absf(cos(ang)) - 0.01 * maxf(0.0, sin(ang))) * (1.0 - float(k) / 6.0)
			ring.append(Vector3(c.x + cos(ang) * r * cos(phi), y - drop, c.y - 0.008 + sin(ang) * r * 1.12 * cos(phi)))
		rows.append(ring)
	for k in 6:
		_band(st, rows[k], rows[k + 1], Color(0.03, 0.03, 0.035))
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _mat("helmet"))
	return m
