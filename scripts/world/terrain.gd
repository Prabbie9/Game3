class_name Terrain
extends Node3D
## Heightmap terrain from WorldData: one coarse mesh for the whole map (16 m spacing) plus streamed detail
## chunks around the focus (128 m; 2 m spacing next to it, 4 m further out) and heightmap collision.
## Chunk meshes are built on worker threads (pure arrays); the main thread only creates the resources.
## The coarse mesh discards the square the detail chunks cover, so the two never overlap.

const CHUNK := 128.0
const DETAIL_R := 3     # 7x7 detail chunks
const FINE_R := 1       # inner 3x3 at full resolution
const COL_R := 2        # 5x5 collision chunks
const FAR_STRIDE := 8   # samples (16 m)

var data: WorldData
var _mat_far: ShaderMaterial
var _mat_near: ShaderMaterial
var _far: MeshInstance3D
var _body: StaticBody3D
var _chunks := {}       # Vector2i -> {"node": MeshInstance3D, "stride": int}
var _cols := {}         # Vector2i -> CollisionShape3D
var _want := {}         # Vector2i -> stride
var _center := Vector2i(1 << 20, 1 << 20)
var _jobs := {}         # Vector2i -> task id
var _done: Array = []
var _mutex := Mutex.new()
var _hole_center := Vector2i(1 << 20, 1 << 20)
var _col_jobs := {}
var _col_done: Array = []
var _col_keep := {}


func _ready() -> void:
	data = WorldData.get_data()
	_mat_near = _make_material()
	_mat_far = _mat_near.duplicate()
	_body = StaticBody3D.new()
	_body.name = "TerrainCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var per := int(data.n - 1)
	var arr := _build_arrays(data, 0, 0, per, per, FAR_STRIDE, 0.6)
	_far = MeshInstance3D.new()
	_far.name = "TerrainFar"
	_far.mesh = _to_mesh(arr)
	_far.material_override = _mat_far
	add_child(_far)


func _exit_tree() -> void:
	for id in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(id)
	for id in _col_jobs.values():
		WorkerThreadPool.wait_for_task_completion(id)


static func _tex(name: String, map: String) -> Texture2D:
	return load("res://assets/textures/polyhaven/%s/%s.jpg" % [name, map])


func _make_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/terrain.gdshader")
	m.set_shader_parameter("splat", load("res://assets/world/splat.png"))
	for layer: Array in [["sand", "coast_sand_01"], ["dry", "aerial_grass_rock"], ["rock", "rock_face"], ["lush", "rocky_terrain_02"]]:
		m.set_shader_parameter(layer[0] + "_alb", _tex(layer[1], "albedo"))
		m.set_shader_parameter(layer[0] + "_nrm", _tex(layer[1], "normal"))
	m.set_shader_parameter("world_half", data.half)
	m.set_shader_parameter("sea_level", data.sea)
	return m


## Keep detail and collision around a world position (call every frame; cheap when nothing changes).
func update(pos: Vector3) -> void:
	var c := Vector2i(floori((pos.x + data.half) / CHUNK), floori((pos.z + data.half) / CHUNK))
	if c != _center:
		_center = c
		_want.clear()
		for dz in range(-DETAIL_R, DETAIL_R + 1):
			for dx in range(-DETAIL_R, DETAIL_R + 1):
				var k := c + Vector2i(dx, dz)
				if _valid(k):
					_want[k] = 1 if maxi(absi(dx), absi(dz)) <= FINE_R else 2
		for k: Vector2i in _want:
			_request(k, _want[k])
		_update_collision(c)
	_collect()
	_collect_collision()
	# swap the coarse mesh's hole once every wanted chunk is shown at its resolution
	if _hole_center != _center and _all_ready():
		_hole_center = _center
		for k: Vector2i in _chunks.keys():
			if not _want.has(k):
				(_chunks[k].node as Node).queue_free()
				_chunks.erase(k)
		var x0 := -data.half + (_center.x - DETAIL_R) * CHUNK
		var z0 := -data.half + (_center.y - DETAIL_R) * CHUNK
		var size := (DETAIL_R * 2 + 1) * CHUNK
		_mat_far.set_shader_parameter("hole", Vector4(x0, z0, x0 + size, z0 + size))


func is_settled() -> bool:
	return _hole_center == _center and _col_jobs.is_empty() and _col_done.is_empty()


func _valid(k: Vector2i) -> bool:
	var cnt := int((data.n - 1) * data.step / CHUNK)
	return k.x >= 0 and k.y >= 0 and k.x < cnt and k.y < cnt


func _all_ready() -> bool:
	for k: Vector2i in _want:
		if not _chunks.has(k) or _chunks[k].stride != _want[k]:
			return false
	return true


func _request(k: Vector2i, stride: int) -> void:
	if (_chunks.has(k) and _chunks[k].stride == stride) or _jobs.has(k):
		return
	var per := int(CHUNK / data.step)
	var d := data
	_jobs[k] = WorkerThreadPool.add_task(func() -> void:
		var arr := Terrain._build_arrays(d, k.x * per, k.y * per, per, per, stride, 3.0)
		_mutex.lock()
		_done.append([k, stride, arr])
		_mutex.unlock())


var _made_this_frame := 0


func _collect() -> void:
	_made_this_frame = 0
	_mutex.lock()
	var ready := _done
	_done = []
	_mutex.unlock()
	for r: Array in ready:
		if _made_this_frame >= 2:
			_mutex.lock()
			_done.append(r)
			_mutex.unlock()
			continue
		_made_this_frame += 1
		var k: Vector2i = r[0]
		WorkerThreadPool.wait_for_task_completion(_jobs[k])
		_jobs.erase(k)
		if not _want.has(k):
			continue
		if _want[k] != r[1]:
			_request(k, _want[k])
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _to_mesh(r[2])
		mi.material_override = _mat_near
		add_child(mi)
		if _chunks.has(k):
			(_chunks[k].node as Node).queue_free()
		_chunks[k] = {"node": mi, "stride": r[1]}


func _update_collision(c: Vector2i) -> void:
	var keep := {}
	for dz in range(-COL_R, COL_R + 1):
		for dx in range(-COL_R, COL_R + 1):
			var k := c + Vector2i(dx, dz)
			if not _valid(k):
				continue
			keep[k] = true
			if _cols.has(k) or _col_jobs.has(k):
				continue
			var d := data
			var per := int(CHUNK / data.step)
			_col_jobs[k] = WorkerThreadPool.add_task(func() -> void:
				var f := PackedFloat32Array()
				f.resize((per + 1) * (per + 1))
				for j in per + 1:
					for i in per + 1:
						f[j * (per + 1) + i] = d.sample(k.x * per + i, k.y * per + j)
				_mutex.lock()
				_col_done.append([k, f])
				_mutex.unlock())
	for k: Vector2i in _cols.keys():
		if not keep.has(k):
			(_cols[k] as Node).queue_free()
			_cols.erase(k)
	_col_keep = keep


## One finished collision chunk per frame (each is a single cheap shape).
func _collect_collision() -> void:
	_mutex.lock()
	var item: Array = _col_done.pop_front() if not _col_done.is_empty() else []
	_mutex.unlock()
	if item.is_empty():
		return
	var k: Vector2i = item[0]
	WorkerThreadPool.wait_for_task_completion(_col_jobs[k])
	_col_jobs.erase(k)
	if not _col_keep.has(k) or _cols.has(k):
		return
	var per := int(CHUNK / data.step)
	var hm := HeightMapShape3D.new()
	hm.map_width = per + 1
	hm.map_depth = per + 1
	hm.map_data = item[1]
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(data.step, 1.0, data.step)
	cs.position = Vector3(-data.half + (k.x + 0.5) * CHUNK, 0.0, -data.half + (k.y + 0.5) * CHUNK)
	_body.add_child(cs)
	_cols[k] = cs


## Vertex/normal/tangent/index arrays for the sample rectangle [i0, i0 + w] x [j0, j0 + h] every `stride`
## samples, with a skirt `skirt` metres deep around the border (hides cracks between resolutions).
static func _build_arrays(d: WorldData, i0: int, j0: int, w: int, h: int, stride: int, skirt: float) -> Array:
	var cx := w / stride + 1
	var cz := h / stride + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var idx := PackedInt32Array()
	verts.resize(cx * cz)
	normals.resize(cx * cz)
	tangents.resize(cx * cz * 4)
	var e := float(stride) * d.step
	for b in cz:
		for a in cx:
			var i := i0 + a * stride
			var j := j0 + b * stride
			var k := b * cx + a
			verts[k] = Vector3(-d.half + i * d.step, d.sample(i, j), -d.half + j * d.step)
			var n := Vector3(d.sample(i - stride, j) - d.sample(i + stride, j), 2.0 * e, d.sample(i, j - stride) - d.sample(i, j + stride)).normalized()
			normals[k] = n
			var t := (Vector3.RIGHT - n * n.x).normalized()
			tangents[k * 4] = t.x
			tangents[k * 4 + 1] = t.y
			tangents[k * 4 + 2] = t.z
			tangents[k * 4 + 3] = -1.0
	for b in cz - 1:
		for a in cx - 1:
			var v00 := b * cx + a
			idx.append_array([v00, v00 + 1, v00 + cx, v00 + 1, v00 + cx + 1, v00 + cx])
	if skirt > 0.0:
		var ring := PackedInt32Array()
		for a in cx:
			ring.append(a)
		for b in range(1, cz):
			ring.append(b * cx + cx - 1)
		for a in range(cx - 2, -1, -1):
			ring.append((cz - 1) * cx + a)
		for b in range(cz - 2, 0, -1):
			ring.append(b * cx)
		var base := verts.size()
		for r in ring:
			verts.append(verts[r] - Vector3(0, skirt, 0))
			normals.append(normals[r])
			tangents.append_array([tangents[r * 4], tangents[r * 4 + 1], tangents[r * 4 + 2], -1.0])
		for q in ring.size():
			var a0 := ring[q]
			var a1 := ring[(q + 1) % ring.size()]
			var b0 := base + q
			var b1 := base + (q + 1) % ring.size()
			idx.append_array([a0, a1, b0, a1, b1, b0, a0, b0, a1, a1, b0, b1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TANGENT] = tangents
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


static func _to_mesh(arr: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
