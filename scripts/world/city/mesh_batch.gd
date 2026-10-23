class_name MeshBatch
extends RefCounted
## Collects triangles per material key on any thread (no rendering-server calls) so a whole city cell becomes a
## handful of merged meshes. Per-vertex parameters (UV2, COLOR, CUSTOM0/1) carry what used to be per-object
## shader uniforms (facade window layout, road markings), so different buildings/roads share one material.

var _st := {}  # key -> SurfaceTool
var uv2 := Vector2.ZERO
var color := Color.WHITE
var custom0 := Color(0, 0, 0, 0)
var custom1 := Color(0, 0, 0, 0)


func _tool(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
		st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
		_st[key] = st
	return _st[key]


func _v(st: SurfaceTool, p: Vector3, uv: Vector2) -> void:
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.set_color(color)
	st.set_custom(0, custom0)
	st.set_custom(1, custom1)
	st.add_vertex(p)


## Quad a-b-c-d counter-clockwise seen from its front (emitted clockwise = Godot front faces).
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var st := _tool(key)
	_v(st, a, ua); _v(st, c, uc); _v(st, b, ub)
	_v(st, a, ua); _v(st, d, ud); _v(st, c, uc)


func tri(key: String, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var st := _tool(key)
	_v(st, a, ua); _v(st, c, uc); _v(st, b, ub)


## Horizontal rectangle facing up (UV = world x/z).
func flat(key: String, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	quad(key, Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x0, y, z0),
		Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0), Vector2(x0, z0))


## Axis-aligned box (all six faces outward; UVs in metres per face).
func box(key: String, c: Vector3, s: Vector3, bottom := false) -> void:
	var x0 := c.x - s.x * 0.5
	var x1 := c.x + s.x * 0.5
	var y0 := c.y - s.y * 0.5
	var y1 := c.y + s.y * 0.5
	var z0 := c.z - s.z * 0.5
	var z1 := c.z + s.z * 0.5
	flat(key, x0, z0, x1, z1, y1)
	if bottom:
		quad(key, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1))
	wall(key, Vector3(x0, y0, z1), Vector3(x1, y0, z1), y1 - y0)
	wall(key, Vector3(x1, y0, z1), Vector3(x1, y0, z0), y1 - y0)
	wall(key, Vector3(x1, y0, z0), Vector3(x0, y0, z0), y1 - y0)
	wall(key, Vector3(x0, y0, z0), Vector3(x0, y0, z1), y1 - y0)


## Vertical wall from a to b (left to right seen from the front), height h, UV = (metres along, metres up from a.y).
func wall(key: String, a: Vector3, b: Vector3, h: float, v0 := 0.0) -> void:
	var w := a.distance_to(b)
	quad(key, a, b, b + Vector3(0, h, 0), a + Vector3(0, h, 0), Vector2(0, v0), Vector2(w, v0), Vector2(w, v0 + h), Vector2(0, v0 + h))


func is_empty() -> bool:
	return _st.is_empty()


## key -> mesh arrays (normals + tangents generated). Thread-safe (no server calls).
func commit() -> Dictionary:
	var out := {}
	for key: String in _st:
		var st: SurfaceTool = _st[key]
		st.generate_normals()
		st.generate_tangents()
		out[key] = st.commit_to_arrays()
	_st.clear()
	return out
