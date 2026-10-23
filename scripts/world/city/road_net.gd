class_name RoadNet
extends RefCounted
## Junction layout for the baked road graph: how far each road is trimmed back at its nodes, the asphalt
## polygon of every junction, sidewalk corner pieces between neighbouring roads, and shared cross-sections
## where a road simply continues (so consecutive pieces meet without gaps). Read-only after build().

const SIDEWALK := 4.0
const CURB_H := 0.15

var data: WorldData
var ends := {}        # node -> Array of end dicts (sorted counter-clockwise by angle)
var trim := {}        # Vector2i(road, end) -> asphalt trim (m)
var side_trim := {}   # Vector2i(road, end) -> sidewalk trim (m)
var section := {}     # Vector2i(road, end) -> Vector2 cross-section direction (shared at continuations)
var is_junction := {} # node -> bool
var length := []      # road -> polyline length


func build(d: WorldData) -> void:
	data = d
	for r in d.roads.size():
		var rd: Dictionary = d.roads[r]
		var pts: Array = rd.pts
		length.append(_poly_len(pts))
		for e in 2:
			var node := int(rd.a if e == 0 else rd.b)
			var dir := _end_dir(pts, e)
			if not ends.has(node):
				ends[node] = []
			ends[node].append({"road": r, "end": e, "dir": dir, "w": float(rd.w), "walk": bool(rd.walk), "kind": rd.kind,
				"ang": atan2(dir.y, dir.x)})
	for node: int in ends:
		var list: Array = ends[node]
		list.sort_custom(func(a, b): return a.ang < b.ang)
		var deg := list.size()
		if deg == 1:
			var e: Dictionary = list[0]
			_set_end(e, 0.0, 0.0, Vector2(-e.dir.y, e.dir.x))
			is_junction[node] = false
		elif deg == 2 and (list[0].dir as Vector2).dot(list[1].dir) < -0.9 and absf(list[0].w - list[1].w) < 0.5:
			# straight continuation: both ends share one cross-section line through the node
			var r0 := Vector2(-list[0].dir.y, list[0].dir.x)
			var r1 := Vector2(-list[1].dir.y, list[1].dir.x)
			var s := (r0 - r1).normalized()
			_set_end(list[0], 0.0, 0.0, s)
			_set_end(list[1], 0.0, 0.0, -s)
			is_junction[node] = false
		else:
			is_junction[node] = true
			for i in deg:
				var e: Dictionary = list[i]
				var t := 0.0
				for j in deg:
					if j == i:
						continue
					var o: Dictionary = list[j]
					var sn := absf((e.dir as Vector2).cross(o.dir))
					t = maxf(t, (o.w * 0.5) / maxf(sn, 0.45))
				t = minf(t + 0.2, length[e.road] * 0.45)
				_set_end(e, t, minf(t + SIDEWALK, length[e.road] * 0.48), Vector2(-e.dir.y, e.dir.x))


func _set_end(e: Dictionary, t: float, ts: float, s: Vector2) -> void:
	var k := Vector2i(e.road, e.end)
	trim[k] = t
	side_trim[k] = ts
	section[k] = s


static func _poly_len(pts: Array) -> float:
	var L := 0.0
	for i in pts.size() - 1:
		L += Vector2(pts[i][0], pts[i][2]).distance_to(Vector2(pts[i + 1][0], pts[i + 1][2]))
	return L


## Unit direction (x, z) leaving the node at end e, measured a few metres in for stability.
static func _end_dir(pts: Array, e: int) -> Vector2:
	var p0 := Vector2(pts[0][0], pts[0][2]) if e == 0 else Vector2(pts[-1][0], pts[-1][2])
	var idx := range(1, pts.size()) if e == 0 else range(pts.size() - 2, -1, -1)
	for i in idx:
		var q := Vector2(pts[i][0], pts[i][2])
		if q.distance_to(p0) > 4.0 or i == idx[-1]:
			return (q - p0).normalized()
	return Vector2.RIGHT


func node_pos(node: int) -> Vector3:
	var n: Array = data.nodes[node]
	return Vector3(n[0], n[2], n[1])


## Height of a road at distance s along its polyline.
func road_height_at(r: int, s: float) -> float:
	var pts: Array = data.roads[r].pts
	var acc := 0.0
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][2])
		var b := Vector2(pts[i + 1][0], pts[i + 1][2])
		var L := a.distance_to(b)
		if acc + L >= s or i == pts.size() - 2:
			var t := clampf((s - acc) / maxf(L, 0.001), 0.0, 1.0)
			return lerpf(pts[i][1], pts[i + 1][1], t)
		acc += L
	return pts[-1][1]


## Point at distance t from the node along road end e (follows the polyline).
func along_from_node(e: Dictionary, t: float) -> Vector3:
	var r: int = e.road
	var s: float = t if e.end == 0 else length[r] - t
	var pts: Array = data.roads[r].pts
	var acc := 0.0
	for i in pts.size() - 1:
		var a := Vector3(pts[i][0], pts[i][1], pts[i][2])
		var b := Vector3(pts[i + 1][0], pts[i + 1][1], pts[i + 1][2])
		var L := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		if acc + L >= s or i == pts.size() - 2:
			return a.lerp(b, clampf((s - acc) / maxf(L, 0.001), 0.0, 1.0))
		acc += L
	var p: Array = pts[-1]
	return Vector3(p[0], p[1], p[2])
