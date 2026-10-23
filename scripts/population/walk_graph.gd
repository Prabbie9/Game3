class_name WalkGraph
extends RefCounted
## Where people walk: the pavements along every road that has them, joined round the junction corners, plus
## zebra crossings across each road end at town junctions (and across dead ends). Built from the road graph at
## load; pedestrians wander it edge by edge.

const URBAN := ["street", "avenue", "drive", "residential"]

## Edge: {pts: PackedVector3Array, cum, len, a, b (graph nodes), cross: bool, node (junction, crossings),
##        road, end (crossing: which road end it spans)}
var edges: Array = []
## graph node -> [edge ids]
var links := {}
var _pos := []            # graph node -> Vector3
var _grid := {}           # Vector2i (64 m) -> [edge ids] (pavement edges only)


func build(data: WorldData, net: RoadNet) -> void:
	var end_pts := {}     # Vector3i(road, end, side) -> graph node at that pavement end
	for r in data.roads.size():
		var rd: Dictionary = data.roads[r]
		if not bool(rd.walk):
			continue
		var w: float = rd.w
		var off := w * 0.5 + RoadNet.SIDEWALK * 0.5
		var L: float = net.length[r]
		var s0: float = net.side_trim[Vector2i(r, 0)]
		var s1: float = L - net.side_trim[Vector2i(r, 1)]
		if s1 - s0 < 2.0:
			continue
		var raw := LaneGraph._polyline(rd.pts, s0, s1)
		for side: int in [-1, 1]:
			var pts := PackedVector3Array()
			var m := raw.size()
			for j in m:
				var p: Vector3 = raw[j]
				var a: Vector3 = raw[maxi(j - 1, 0)]
				var b: Vector3 = raw[mini(j + 1, m - 1)]
				var f := Vector2(b.x - a.x, b.z - a.z).normalized()
				var right := Vector2(-f.y, f.x) * float(side)
				pts.append(Vector3(p.x + right.x * off, p.y + CityCell.CURB_H, p.z + right.y * off))
			var na := _node(pts[0])
			var nb := _node(pts[-1])
			end_pts[Vector3i(r, 0, side)] = na
			end_pts[Vector3i(r, 1, side)] = nb
			_edge(pts, na, nb, false, -1, r, -1)
	# junction corners and crossings
	for node: int in net.ends:
		var list: Array = (net.ends[node] as Array).filter(func(e): return end_pts.has(Vector3i(e.road, e.end, 1)))
		var deg := list.size()
		if deg == 0:
			continue
		if deg == 1:
			# dead end: cross over the end of the road
			var e: Dictionary = list[0]
			_join(end_pts[Vector3i(e.road, e.end, -1)], end_pts[Vector3i(e.road, e.end, 1)], true, node, e.road, e.end)
			continue
		if deg == 2 and (list[0].dir as Vector2).dot(list[1].dir) < -0.8:
			# the pavements simply continue: nearest ends pair up
			var e0: Dictionary = list[0]
			var e1: Dictionary = list[1]
			for s: int in [-1, 1]:
				var a: int = end_pts[Vector3i(e0.road, e0.end, s)]
				var b1: int = end_pts[Vector3i(e1.road, e1.end, 1)]
				var b2: int = end_pts[Vector3i(e1.road, e1.end, -1)]
				_join(a, b1 if (_pos[a] as Vector3).distance_to(_pos[b1]) < (_pos[a] as Vector3).distance_to(_pos[b2]) else b2, false, node, -1, -1)
			continue
		for i in deg:
			var ei: Dictionary = list[i]
			var ej: Dictionary = list[(i + 1) % deg]
			var a := _facing(end_pts, ei, ej)
			var b := _facing(end_pts, ej, ei)
			if a >= 0 and b >= 0:
				_join(a, b, false, node, -1, -1)
		# crossings over each town road at this junction
		if deg >= 3:
			for e: Dictionary in list:
				if e.kind in URBAN:
					_join(end_pts[Vector3i(e.road, e.end, -1)], end_pts[Vector3i(e.road, e.end, 1)], true, node, e.road, e.end)


## The pavement end of road end `e` on the corner it shares with neighbouring end `o`.
func _facing(end_pts: Dictionary, e: Dictionary, o: Dictionary) -> int:
	var best := -1
	var bd := INF
	for s: int in [-1, 1]:
		var n: int = end_pts[Vector3i(e.road, e.end, s)]
		var other_n: int = end_pts[Vector3i(o.road, o.end, -1)]
		var other_m: int = end_pts[Vector3i(o.road, o.end, 1)]
		var d := minf((_pos[n] as Vector3).distance_to(_pos[other_n]), (_pos[n] as Vector3).distance_to(_pos[other_m]))
		if d < bd:
			bd = d
			best = n
	return best


func _node(p: Vector3) -> int:
	_pos.append(p)
	links[_pos.size() - 1] = []
	return _pos.size() - 1


func _join(a: int, b: int, crossing: bool, node: int, road: int, end: int) -> void:
	var pa: Vector3 = _pos[a]
	var pb: Vector3 = _pos[b]
	if pa.distance_to(pb) < 0.05:
		return
	var pts := PackedVector3Array([pa, pb])
	if crossing:
		# a crossing steps down off the kerb onto the road and back up
		var dir := (pb - pa)
		pts = PackedVector3Array([pa, pa + dir * 0.18 - Vector3(0, CityCell.CURB_H, 0), pa + dir * 0.82 - Vector3(0, CityCell.CURB_H, 0), pb])
	_edge(pts, a, b, crossing, node, road, end)


func _edge(pts: PackedVector3Array, a: int, b: int, crossing: bool, node: int, road: int, end: int) -> void:
	var cum := PackedFloat32Array([0.0])
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += pts[i].distance_to(pts[i - 1])
		cum.append(acc)
	var id := edges.size()
	edges.append({"pts": pts, "cum": cum, "len": acc, "a": a, "b": b, "cross": crossing, "node": node, "road": road, "end": end})
	(links[a] as Array).append(id)
	(links[b] as Array).append(id)
	if not crossing:
		for p in pts:
			var c := Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
			if not _grid.has(c):
				_grid[c] = []
			if not (_grid[c] as Array).has(id):
				(_grid[c] as Array).append(id)


func node_pos(n: int) -> Vector3:
	return _pos[n]


## Point at distance s along edge id, walking from its end `from` (a or b).
func point(id: int, s: float, from: int) -> Vector3:
	var e: Dictionary = edges[id]
	var L: float = e.len
	var t := s if from == int(e.a) else L - s
	t = clampf(t, 0.0, L)
	var pts: PackedVector3Array = e.pts
	var cum: PackedFloat32Array = e.cum
	for i in range(1, pts.size()):
		if cum[i] >= t:
			var seg := maxf(cum[i] - cum[i - 1], 0.0001)
			return pts[i - 1].lerp(pts[i], (t - cum[i - 1]) / seg)
	return pts[-1]


func other_end(id: int, n: int) -> int:
	var e: Dictionary = edges[id]
	return int(e.b) if n == int(e.a) else int(e.a)


func edges_near(pos: Vector3, radius: float) -> Array:
	var out := {}
	var r := ceili(radius / 64.0)
	var c := Vector2i(floori(pos.x / 64.0), floori(pos.z / 64.0))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for id in _grid.get(c + Vector2i(dx, dz), []):
				out[id] = true
	return out.keys()


func node_count() -> int:
	return _pos.size()
