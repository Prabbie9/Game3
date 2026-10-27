class_name City
extends Node3D
## The streamed city: cells of CityCell geometry around the focus (built on worker threads, instantiated on
## the main thread a little per frame) and a cheap merged stand-in for every other cell.

const LOAD_R := 380.0     # cells whose rect is within this distance of the focus are shown in detail
const UNLOAD_R := 520.0
const BUDGET_MS := 3.0    # main-thread time per frame for creating cell nodes
const LEAD_S := 2.5       # moving fast, the cells nearest where the focus will be this many seconds on come first
const PROP_RANGE := {"fire_hydrant": 140.0, "fire_hydrant_aged": 140.0, "metal_trash_can": 140.0, "metal_trash_can_rust": 140.0,
	"utility_box_01": 160.0, "utility_box_02": 160.0, "bench": 160.0, "exterior_aircon_unit": 180.0,
	"picket_fence": 150.0, "chainlink_fence": 170.0,
	"palm_crown": 700.0, "palm_trunk": 700.0, "date_palm": 600.0, "jacaranda": 450.0, "oak": 900.0, "boulder": 500.0}
const IMPOSTOR_AT := 130.0  # trees switch to picture cards beyond this distance
const MESH_FLAGS := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)

var data: WorldData
var net: RoadNet
var lights: Array = []          # bulb positions of all loaded cells (for the street-light pool)
var _lights_dirty := false
var _trash: Array[Node] = []     # unloaded cells, freed a few nodes per frame
var _cell_roads := {}           # Vector2i -> Array[int]
var _cell_nodes := {}
var _cell_lots := {}
var _cells := {}                # Vector2i -> Node3D (detail)
var _far := {}                  # Vector2i -> MeshInstance3D
var _jobs := {}                 # Vector2i -> task id
var _done: Array = []
var _queue: Array = []          # built CityCells waiting to be instantiated
var _steps: Array[Callable] = []  # pending node-creation steps (spread over frames)
var _stepping := Vector2i(1 << 20, 1 << 20)
var _mutex := Mutex.new()
var _mats := {}
var _far_mat: ShaderMaterial
var _focus := Vector3.ZERO
var _cell_set := {}
var ready_cells := 0


func _ready() -> void:
	data = WorldData.get_data()
	net = RoadNet.new()
	net.build(data)
	PropCatalog.prepare()
	PropCatalog.bake_impostors(self)
	_index()
	_far_mat = ShaderMaterial.new()
	_far_mat.shader = preload("res://assets/shaders/far_city.gdshader")
	_build_far()


func _exit_tree() -> void:
	for id in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(id)
	for n in _trash:
		if is_instance_valid(n) and not n.is_inside_tree():
			n.free()
	_trash.clear()


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CityCell.SIZE), floori(z / CityCell.SIZE))


func _index() -> void:
	for r in data.roads.size():
		var pts: Array = data.roads[r].pts
		var m: Array = pts[pts.size() / 2]
		_add(_cell_roads, cell_of(m[0], m[2]), r)
	for n: int in net.ends:
		var p: Array = data.nodes[n]
		_add(_cell_nodes, cell_of(p[0], p[1]), n)
	for i in data.lots.size():
		var l: Dictionary = data.lots[i]
		_add(_cell_lots, cell_of((l.x0 + l.x1) * 0.5, (l.z0 + l.z1) * 0.5), i)


static func _add(d: Dictionary, k: Vector2i, v: int) -> void:
	if not d.has(k):
		d[k] = []
	d[k].append(v)


func _all_cells() -> Array:
	var keys := {}
	# every cell over land (wild vegetation grows outside the road/lot cells too)
	var c0 := cell_of(-1100.0, -1420.0)
	var c1 := cell_of(1300.0, 1100.0)
	for z in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			keys[Vector2i(x, z)] = true
	for d: Dictionary in [_cell_roads, _cell_nodes, _cell_lots]:
		for k: Vector2i in d:
			keys[k] = true
	return keys.keys()


## Builds every cell once on worker threads to collect the far stand-ins (blocks until done; part of loading).
func _build_far() -> void:
	var cells := _all_cells()
	var results := []
	results.resize(cells.size())
	var d := data
	var n := net
	var group := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var k: Vector2i = cells[i]
		var c := CityCell.new(k, d, n)
		c.build(_cell_roads.get(k, []), _cell_nodes.get(k, []), _cell_lots.get(k, []))
		results[i] = c.far_meshes, cells.size())
	WorkerThreadPool.wait_for_group_task_completion(group)
	for i in cells.size():
		var fm: Dictionary = results[i]
		if not fm.has("far"):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_from({"far": fm.far}, {"far": _far_mat})
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Far_%d_%d" % [cells[i].x, cells[i].y]
		add_child(mi)
		_far[cells[i]] = mi


## Keep detail cells around a world position; call every frame.
var anchor := Vector3.INF  # cells near this point stay loaded too (the player when the camera is elsewhere)


var cost_ms := 0.0             # main-thread time spent creating cell nodes last frame (benchmark)
var _lead := Vector3.ZERO      # where the focus will be in a couple of seconds (moving fast: build ahead first)
var _vel := Vector3.ZERO
var _last_t := 0


func update(focus: Vector3) -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_t) / 1e6 if _last_t > 0 else 0.0
	_last_t = now
	if dt > 0.0 and dt < 0.5:
		var v := (focus - _focus) / dt
		_vel = _vel.lerp(v if v.length() < 120.0 else _vel, minf(1.0, dt * 4.0))   # (teleports don't count)
	_focus = focus
	var ahead := _vel * LEAD_S
	ahead.y = 0.0
	_lead = focus + ahead.limit_length(LOAD_R * 0.6)
	var want := _all_cells_near(focus, LOAD_R)
	if anchor != Vector3.INF:
		want.append_array(_all_cells_near(anchor, 150.0))
	var missing := want.filter(func(k: Vector2i): return not _cells.has(k) and not _jobs.has(k) and not _queued(k))
	# nearest the point ahead first: the cells the car is about to reach are built and shown before those behind
	missing.sort_custom(func(a: Vector2i, b: Vector2i): return _rect_dist(a, _lead) < _rect_dist(b, _lead))
	for k: Vector2i in missing:
		_request(k)
	for k: Vector2i in _cells.keys():
		if _rect_dist(k, focus) > UNLOAD_R and (anchor == Vector3.INF or _rect_dist(k, anchor) > 260.0):
			_unload(k)
	_collect()
	_free_some(40)
	if _lights_dirty:
		_lights_dirty = false
		lights = []
		for k: Vector2i in _cells:
			if is_instance_valid(_cells[k]):
				lights.append_array(_cells[k].get_meta("lights", []))
	var t0 := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - t0) < BUDGET_MS * 1000.0:
		if _steps.is_empty():
			if _queue.is_empty():
				break
			_steps = _steps_for(_pop_nearest())
		_steps.pop_front().call()
	cost_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Frees up to n nodes of unloaded cells (freeing a whole cell at once costs tens of milliseconds).
func _free_some(n: int) -> void:
	while n > 0 and not _trash.is_empty():
		var node: Node = _trash[-1]
		if node.get_child_count() == 0:
			_trash.pop_back()
			node.free()
			n -= 1
			continue
		var child := node.get_child(node.get_child_count() - 1)
		if child.get_child_count() > 0:
			_trash.append(child)
			continue
		child.free()
		n -= 1


## The built cell nearest the point ahead (instantiated next).
func _pop_nearest() -> CityCell:
	var best := 0
	for i in range(1, _queue.size()):
		if _rect_dist((_queue[i] as CityCell).key, _lead) < _rect_dist((_queue[best] as CityCell).key, _lead):
			best = i
	var c: CityCell = _queue[best]
	_queue.remove_at(best)
	return c


func _queued(k: Vector2i) -> bool:
	for c: CityCell in _queue:
		if c.key == k:
			return true
	return false


func _all_cells_near(p: Vector3, r: float) -> Array:
	var out := []
	var c0 := cell_of(p.x - r, p.z - r)
	var c1 := cell_of(p.x + r, p.z + r)
	for z in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var k := Vector2i(x, z)
			if _rect_dist(k, p) <= r and _known(k):
				out.append(k)
	return out


func _known(k: Vector2i) -> bool:
	if _cell_set.is_empty():
		for c: Vector2i in _all_cells():
			_cell_set[c] = true
	return _cell_set.has(k)


func _rect_dist(k: Vector2i, p: Vector3) -> float:
	var s := CityCell.SIZE
	var dx := maxf(maxf(k.x * s - p.x, p.x - (k.x + 1) * s), 0.0)
	var dz := maxf(maxf(k.y * s - p.z, p.z - (k.y + 1) * s), 0.0)
	return Vector2(dx, dz).length()


func _request(k: Vector2i) -> void:
	var d := data
	var n := net
	var roads: Array = _cell_roads.get(k, [])
	var nodes: Array = _cell_nodes.get(k, [])
	var lots: Array = _cell_lots.get(k, [])
	_jobs[k] = WorkerThreadPool.add_task(func() -> void:
		var c := CityCell.new(k, d, n)
		c.build(roads, nodes, lots)
		_mutex.lock()
		_done.append(c)
		_mutex.unlock())


func _collect() -> void:
	_mutex.lock()
	var ready := _done
	_done = []
	_mutex.unlock()
	for c: CityCell in ready:
		WorkerThreadPool.wait_for_task_completion(_jobs[c.key])
		_jobs.erase(c.key)
		if _rect_dist(c.key, _focus) <= UNLOAD_R or (anchor != Vector3.INF and _rect_dist(c.key, anchor) <= 260.0):
			_queue.append(c)


func _unload(k: Vector2i) -> void:
	if k == _stepping and not _steps.is_empty():
		_steps.clear()
	var node: Node3D = _cells[k]
	node.visible = false
	_trash.append(node)
	_lights_dirty = true
	_cells.erase(k)
	if _far.has(k):
		_far[k].visible = true


## Turns a built cell into nodes as a list of small steps, so update() can spread the work over frames.
func _steps_for(c: CityCell) -> Array[Callable]:
	var steps: Array[Callable] = []
	var root := Node3D.new()
	root.name = "Cell_%d_%d" % [c.key.x, c.key.y]
	root.visible = false
	steps.append(func() -> void: add_child(root))
	for key: String in c.meshes:
		steps.append(func() -> void:
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh_from({key: c.meshes[key]}, {key: _mat(key)})
			mi.name = key.replace(":", "_")
			if key in ["road", "sidewalk", "ground", "grass", "path", "coping", "curb", "pool_tiles", "deck"]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi))
	# collision in small bodies built off-tree (adding shapes to a live body rebuilds its compound each time)
	for i0 in range(0, c.boxes.size(), 32):
		steps.append(func() -> void:
			var sb := StaticBody3D.new()
			sb.collision_layer = 1
			sb.collision_mask = 0
			for bx: Array in c.boxes.slice(i0, i0 + 32):
				var cs := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = bx[1]
				cs.shape = shape
				cs.transform = bx[0]
				sb.add_child(cs)
			root.add_child(sb))
	for pname: String in c.props:
		var xfs: Array = c.props[pname]
		for i0 in range(0, xfs.size(), 40):
			steps.append(func() -> void: _add_props(root, pname, xfs.slice(i0, i0 + 40)))
	steps.append(func() -> void:
		for o: Array in c.occluders:
			var oi := OccluderInstance3D.new()
			var bo := BoxOccluder3D.new()
			bo.size = o[1]
			oi.occluder = bo
			oi.position = o[0]
			root.add_child(oi)
		for w: Array in c.waters:
			var vol := WaterVolume.new()
			vol.size = w[1]
			vol.position = w[0]
			root.add_child(vol)
		root.set_meta("lights", c.lights)
		root.set_meta("benches", c.props.get("bench", []))
		_lights_dirty = true
		root.visible = true
		if _far.has(c.key):
			_far[c.key].visible = false
		ready_cells += 1)
	_cells[c.key] = root
	_stepping = c.key
	return steps


func _add_props(root: Node3D, pname: String, xfs: Array) -> void:
	var name := pname.get_slice("@", 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = PropCatalog.mesh(name)
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = pname.replace(",", "_").replace("@", "_")
	mmi.multimesh = mm
	# instance transforms kept on the CPU side (PropWorld reads them; the renderer's copy isn't readable everywhere)
	mmi.set_meta("prop", name)
	mmi.set_meta("xfs", xfs)
	mmi.visibility_range_end = PROP_RANGE.get(name, 450.0)
	mmi.visibility_range_end_margin = 20.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mmi)
	var imp := PropCatalog.impostor(name)
	if imp:
		# full trees up close, picture cards beyond (with a cross-fade between the two)
		mmi.visibility_range_end = IMPOSTOR_AT
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.mesh = imp
		mm2.instance_count = xfs.size()
		for i in xfs.size():
			mm2.set_instance_transform(i, Transform3D(Basis.from_scale((xfs[i] as Transform3D).basis.get_scale()), (xfs[i] as Transform3D).origin))
		var far := MultiMeshInstance3D.new()
		far.multimesh = mm2
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.visibility_range_begin = IMPOSTOR_AT - 10.0
		far.visibility_range_begin_margin = 20.0
		far.visibility_range_end = PROP_RANGE.get(name, 450.0) * 1.6
		far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(far)
	var psb := StaticBody3D.new()
	psb.collision_layer = 16
	psb.collision_mask = 0
	# PropWorld breaks single instances: which prop / MultiMesh / instance each shape stands for
	psb.set_meta("prop", name)
	psb.set_meta("mmi", mmi)
	if PropWorld.BREAKABLE.has(name) and PropWorld.BREAKABLE[name].has("surface"):
		psb.set_meta("surface", PropWorld.BREAKABLE[name].surface)
	for i in xfs.size():
		var xf: Transform3D = xfs[i]
		var col := PropCatalog.collision(name, xf.basis.get_scale().x)
		if col.is_empty():
			continue
		var cs := CollisionShape3D.new()
		cs.shape = col[0]
		var q := xf.basis.get_rotation_quaternion()
		cs.transform = Transform3D(Basis(q), xf.origin + q * col[1])
		cs.set_meta("inst", i)
		psb.add_child(cs)
	if psb.get_child_count() > 0:
		root.add_child(psb)
	else:
		psb.free()


func _mesh_from(arrays: Dictionary, mats: Dictionary) -> ArrayMesh:
	var am := ArrayMesh.new()
	for key: String in arrays:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays[key], [], {}, MESH_FLAGS)
		am.surface_set_material(am.get_surface_count() - 1, mats[key])
	return am


## Bench transforms (seat origin, facing -Z of the prop... see Population.BENCH_SEAT) in loaded cells near pos.
func benches_near(pos: Vector3, radius: float) -> Array:
	var out := []
	for k: Vector2i in _cells:
		var n = _cells[k]
		if not is_instance_valid(n) or not (n as Node3D).visible:
			continue
		for xf: Transform3D in (n as Node).get_meta("benches", []):
			if xf.origin.distance_to(pos) < radius:
				out.append(xf)
	return out


## Walkable ground height at x/z (a street, pavement, park, deck or pier, not a roof, canopy or tower top): a
## ray down from just above the terrain (or the sea) once the detailed cell there and its collision are in.
## NAN while that cell is still streaming in.
func ground_y(x: float, z: float) -> float:
	var k := cell_of(x, z)
	if _known(k) and not (_cells.has(k) and (_cells[k] as Node3D).visible):
		return NAN
	var top := maxf(data.height_at(x, z), 0.0) + 3.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, top - 80.0, z), 1 | 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if hit else data.height_at(x, z)


## True once every cell around the focus is shown in detail (used while loading).
func is_settled() -> bool:
	return _jobs.is_empty() and _queue.is_empty() and _steps.is_empty()


## Instantiate everything already built, ignoring the per-frame budget (loading screens).
func flush() -> void:
	_collect()
	while not _steps.is_empty() or not _queue.is_empty():
		if _steps.is_empty():
			_steps = _steps_for(_queue.pop_front())
		_steps.pop_front().call()


# ------------------------------------------------------------------------------------------------ materials

static func _tex(name: String, map: String) -> Texture2D:
	return load("res://assets/textures/polyhaven/%s/%s.jpg" % [name, map])


func _pbr(name: String, tile: float, tint := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/world_pbr.gdshader")
	m.set_shader_parameter("albedo_tex", _tex(name, "albedo"))
	m.set_shader_parameter("normal_tex", _tex(name, "normal"))
	m.set_shader_parameter("arm_tex", _tex(name, "arm"))
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return m


func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if key.begins_with("facade"):
		var wall := key.get_slice(":", 1)
		var f := ShaderMaterial.new()
		f.shader = preload("res://assets/shaders/facade.gdshader")
		f.set_shader_parameter("wall_albedo", _tex(wall, "albedo"))
		f.set_shader_parameter("wall_normal", _tex(wall, "normal"))
		f.set_shader_parameter("wall_arm", _tex(wall, "arm"))
		f.set_shader_parameter("wall_tile", 3.5 if wall != "concrete_tile_facade" else 6.0)
		if key.begins_with("facade_res"):
			f.set_shader_parameter("ground_floor", 0.0)
			f.set_shader_parameter("floor_height", 3.0)
		m = f
	else:
		match key:
			"road":
				var r := ShaderMaterial.new()
				r.shader = preload("res://assets/shaders/road.gdshader")
				r.set_shader_parameter("albedo_tex", _tex("asphalt_02", "albedo"))
				r.set_shader_parameter("normal_tex", _tex("asphalt_02", "normal"))
				r.set_shader_parameter("arm_tex", _tex("asphalt_02", "arm"))
				m = r
			"sidewalk":
				m = _pbr("concrete_pavement", 2.5, Color(0.92, 0.9, 0.86))
			"curb":
				m = _pbr("concrete_pavement", 1.0, Color(0.8, 0.79, 0.76))
			"ground":
				m = _pbr("concrete_pavement", 3.0, Color(0.8, 0.78, 0.74))
			"roof":
				m = _pbr("concrete_pavement", 2.0, Color(0.72, 0.71, 0.69))
			"barrier", "plinth":
				m = _pbr("concrete_pavement", 1.5, Color(0.78, 0.77, 0.74))
			"coping":
				m = _pbr("concrete_pavement", 1.5, Color(0.97, 0.95, 0.9))
			"grass":
				m = _pbr("rocky_terrain_02", 5.0, Color(0.95, 1.0, 0.9))
			"path":
				m = _pbr("concrete_pavement", 1.2, Color(0.9, 0.86, 0.78))
			"pool_tiles":
				var p := ShaderMaterial.new()
				p.shader = preload("res://assets/shaders/pool_tiles.gdshader")
				m = p
			"roof_tiles":
				m = _pbr("clay_roof_tiles", 2.0)
			"roof_under", "door":
				m = _pbr("wood_floor_deck", 1.5, Color(0.55, 0.42, 0.32) if key == "door" else Color(0.9, 0.88, 0.84))
			"gable":
				m = _pbr("white_stucco", 3.5)
			"shutter":
				m = _pbr("painted_metal_shutter", 2.5, Color(0.92, 0.92, 0.9))
			"metal":
				m = _pbr("corrugated_iron_02", 3.0)
			"canopy":
				m = _pbr("concrete_pavement", 2.0, Color(0.95, 0.95, 0.95))
			"deck":
				m = _pbr("wood_floor_deck", 2.0)
			"piles":
				m = _pbr("wood_floor_deck", 1.0, Color(0.55, 0.45, 0.36))
			"rail":
				m = _pbr("wood_floor_deck", 1.0, Color(0.92, 0.9, 0.86))
			"balcony":
				m = _pbr("concrete_pavement", 1.5, Color(0.86, 0.85, 0.82))
			"balcony_rail":
				var br := StandardMaterial3D.new()
				br.albedo_color = Color(0.16, 0.17, 0.18)
				br.metallic = 0.6
				br.roughness = 0.4
				m = br
			"balcony_glass":
				var bg := StandardMaterial3D.new()
				bg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				bg.albedo_color = Color(0.36, 0.52, 0.58, 0.55)
				bg.metallic = 0.2
				bg.roughness = 0.05
				m = bg
			"container":
				m = _pbr("corrugated_iron_02", 1.2, Color(1.3, 1.3, 1.3))
			"crane":
				m = _pbr("rusty_metal_sheet", 3.0, Color(1.4, 1.4, 1.4))
			_:
				push_warning("City: no material for key %s" % key)
				m = StandardMaterial3D.new()
	_mats[key] = m
	return m
