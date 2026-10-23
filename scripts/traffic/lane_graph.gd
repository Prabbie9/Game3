class_name LaneGraph
extends RefCounted
## Driving lanes from the baked road graph, for traffic. Every road gets its lanes in both directions (right-hand
## traffic), offset from the centre line by lane index; at nodes, connector lanes (curves) join each lane that
## arrives to the lanes leaving on other roads: straight on to the same lane, left turns from the inner lane,
## right turns from the outer one. Junctions of three or more town roads get traffic signals with two phases
## (one per crossing axis). Pure data: built once on any thread, read by TrafficManager.

## lane speed limits by road kind (m/s)
const SPEED := {"freeway": 26.0, "drive": 17.0, "avenue": 15.0, "street": 12.5, "residential": 10.0, "hill": 11.0}
const CONNECTOR_SPEED := 6.5
## signal cycle (s): green, amber, all-red per phase
const GREEN := 18.0
const AMBER := 3.0
const ALL_RED := 1.0

## Lane: {pts: PackedVector3Array, cum: PackedFloat32Array, len, road, dir (+1 a->b / -1), index, lanes,
##        from, to (nodes), next: [lane ids], speed, node (-1, or the junction a connector crosses),
##        group (signal phase that lets a connector go, -1 none), turn (-1 left, 0 straight, 1 right)}
var lanes: Array = []
## node -> {group per incoming road end: Vector2i(road, end) -> 0/1, offset: phase offset (s)}
var signals := {}
var _by_road := {}      # Vector2i(road, dir) -> [lane ids, inner first]
var _grid := {}         # Vector2i cell (64 m) -> [lane ids] (road lanes only, for spawning near a point)


func build(data: WorldData, net: RoadNet) -> void:
	for r in data.roads.size():
		var rd: Dictionary = data.roads[r]
		var n := maxi(int(rd.lanes), 1)
		for dir: int in [1, -1]:
			var ids := []
			for i in n:
				ids.append(_road_lane(data, net, r, dir, i, n))
			_by_road[Vector2i(r, dir)] = ids
	# junction signals
	for node: int in net.ends:
		var list: Array = net.ends[node]
		if list.size() < 3:
			continue
		var town := 0
		for e: Dictionary in list:
			if e.kind in ["street", "avenue", "drive"]:
				town += 1
		if town < 3:
			continue
		var d0: Vector2 = list[0].dir
		var groups := {}
		for e: Dictionary in list:
			groups[Vector2i(e.road, e.end)] = 0 if absf((e.dir as Vector2).dot(d0)) > 0.7 else 1
		signals[node] = {"groups": groups, "offset": fposmod(float(node) * 7.3, cycle())}
	# connectors
	for node: int in net.ends:
		var list: Array = net.ends[node]
		var arriving := []   # lanes ending at this node
		var leaving := []
		for e: Dictionary in list:
			var r: int = e.road
			# a lane arrives at node if it runs towards this end
			arriving.append([e, _by_road[Vector2i(r, 1 if e.end == 1 else -1)]])
			leaving.append([e, _by_road[Vector2i(r, 1 if e.end == 0 else -1)]])
		for arr: Array in arriving:
			var ein: Dictionary = arr[0]
			var in_dir := -(ein.dir as Vector2)   # direction of travel arriving
			for lv: Array in leaving:
				var eout: Dictionary = lv[0]
				if eout.road == ein.road and eout.end == ein.end and list.size() > 1:
					continue  # no U-turns except at dead ends
				var out_dir: Vector2 = eout.dir
				var cross := in_dir.cross(out_dir)
				var dot := in_dir.dot(out_dir)
				var turn := 0 if dot > 0.7 else (-1 if cross < 0.0 else 1)
				if list.size() <= 2:
					turn = 0
				var ins: Array = arr[1]
				var outs: Array = lv[1]
				for k in ins.size():
					var li: int = ins[k]
					var lo := -1
					match turn:
						0:
							lo = outs[mini(k, outs.size() - 1)]
						-1:
							if k == 0:
								lo = outs[0]
						1:
							if k == ins.size() - 1:
								lo = outs[outs.size() - 1]
					if lo < 0:
						continue
					var grp := -1
					if signals.has(node):
						grp = int(signals[node].groups[Vector2i(ein.road, ein.end)])
					var c := _connector(li, lo, node, grp, turn)
					(lanes[li].next as Array).append(c)
	# dead lanes (no way on) loop nowhere: traffic despawns there; fine on map edges


func cycle() -> float:
	return 2.0 * (GREEN + AMBER + ALL_RED)


## Signal state for phase group g at a node, time t: 0 green, 1 amber, 2 red.
func signal_state(node: int, g: int, t: float) -> int:
	if g < 0 or not signals.has(node):
		return 0
	var c := fposmod(t + float(signals[node].offset), cycle())
	var half := GREEN + AMBER + ALL_RED
	var local := c - (0.0 if g == 0 else half)
	if local < 0.0 or local >= half:
		return 2
	if local < GREEN:
		return 0
	if local < GREEN + AMBER:
		return 1
	return 2


func _road_lane(data: WorldData, net: RoadNet, r: int, dir: int, i: int, n: int) -> int:
	var rd: Dictionary = data.roads[r]
	var w: float = rd.w
	var lw := w / (2.0 * n)
	var off := lw * (i + 0.5) if n >= 2 else lw * 0.42
	if rd.kind == "freeway":
		off += 0.6  # median barrier
	var L: float = net.length[r]
	var s0: float = net.trim[Vector2i(r, 0)]
	var s1: float = L - net.trim[Vector2i(r, 1)]
	var raw := _polyline(rd.pts, s0, s1)
	var pts := PackedVector3Array()
	var m := raw.size()
	for j in m:
		var k := j if dir == 1 else m - 1 - j
		var p: Vector3 = raw[k]
		var a: Vector3 = raw[maxi(k - 1, 0)]
		var b: Vector3 = raw[mini(k + 1, m - 1)]
		var f := Vector2(b.x - a.x, b.z - a.z).normalized() * float(dir)
		var right := Vector2(-f.y, f.x)
		pts.append(p + Vector3(right.x, 0, right.y) * off)
	var lane := _make(pts)
	lane.road = r
	lane.dir = dir
	lane.index = i
	lane.lanes = n
	lane.from = int(rd.a if dir == 1 else rd.b)
	lane.to = int(rd.b if dir == 1 else rd.a)
	lane.speed = SPEED.get(rd.kind, 12.0)
	lane.kind = rd.kind
	var id := lanes.size()
	lanes.append(lane)
	for j in range(0, pts.size()):
		var cell := Vector2i(floori(pts[j].x / 64.0), floori(pts[j].z / 64.0))
		if not _grid.has(cell):
			_grid[cell] = []
		if not (_grid[cell] as Array).has(id):
			(_grid[cell] as Array).append(id)
	return id


func _connector(from_lane: int, to_lane: int, node: int, group: int, turn: int) -> int:
	var a: Dictionary = lanes[from_lane]
	var b: Dictionary = lanes[to_lane]
	var p0: Vector3 = (a.pts as PackedVector3Array)[-1]
	var p3: Vector3 = (b.pts as PackedVector3Array)[0]
	var ap: PackedVector3Array = a.pts
	var bp: PackedVector3Array = b.pts
	var d0 := (p0 - ap[maxi(ap.size() - 2, 0)]).normalized()
	var d1 := (bp[mini(1, bp.size() - 1)] - p3).normalized()
	var k := p0.distance_to(p3) * 0.42
	var p1 := p0 + d0 * k
	var p2 := p3 - d1 * k
	var pts := PackedVector3Array()
	var steps := 8 if turn != 0 else 3
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	var c := _make(pts)
	c.road = -1
	c.from = node
	c.to = node
	c.node = node
	c.group = group
	c.turn = turn
	c.speed = CONNECTOR_SPEED if turn != 0 else minf(float(a.speed), float(b.speed))
	c.next = [to_lane]
	c.kind = "junction"
	var id := lanes.size()
	lanes.append(c)
	return id


func _make(pts: PackedVector3Array) -> Dictionary:
	var cum := PackedFloat32Array()
	var acc := 0.0
	cum.append(0.0)
	for i in range(1, pts.size()):
		acc += pts[i].distance_to(pts[i - 1])
		cum.append(acc)
	return {"pts": pts, "cum": cum, "len": acc, "road": -1, "dir": 1, "index": 0, "lanes": 1, "from": -1, "to": -1,
		"next": [], "speed": 12.0, "node": -1, "group": -1, "turn": 0, "kind": ""}


## Points along a road polyline between distances s0 and s1 (x, y, z; y = road height).
static func _polyline(pts: Array, s0: float, s1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var acc := 0.0
	var prev := Vector3(pts[0][0], pts[0][1], pts[0][2])
	var started := false
	for i in range(1, pts.size()):
		var cur := Vector3(pts[i][0], pts[i][1], pts[i][2])
		var L := Vector2(prev.x, prev.z).distance_to(Vector2(cur.x, cur.z))
		if not started and acc + L >= s0:
			out.append(prev.lerp(cur, clampf((s0 - acc) / maxf(L, 0.001), 0.0, 1.0)))
			started = true
		if started:
			if acc + L >= s1:
				out.append(prev.lerp(cur, clampf((s1 - acc) / maxf(L, 0.001), 0.0, 1.0)))
				break
			# subdivide long straight pieces so curves offset smoothly and lookups stay cheap
			var segs := maxi(1, int(L / 12.0))
			for k in range(1, segs + 1):
				var q := prev.lerp(cur, float(k) / segs)
				if Vector2(q.x, q.z).distance_to(Vector2(out[-1].x, out[-1].z)) > 0.5:
					out.append(q)
		acc += L
		prev = cur
	if out.size() < 2:
		out = PackedVector3Array([Vector3(pts[0][0], pts[0][1], pts[0][2]), Vector3(pts[-1][0], pts[-1][1], pts[-1][2])])
	return out


## The neighbouring lane in the same direction (inner if there is one, else outer), -1 on one-lane roads.
func adjacent_lane(id: int) -> int:
	var ln: Dictionary = lanes[id]
	if ln.node >= 0 or int(ln.lanes) < 2:
		return -1
	var ids: Array = _by_road[Vector2i(int(ln.road), int(ln.dir))]
	var i: int = ln.index
	return ids[i - 1] if i > 0 else ids[i + 1]


## Position and travel direction at distance s along lane id.
func sample(id: int, s: float) -> Array:
	var ln: Dictionary = lanes[id]
	var pts: PackedVector3Array = ln.pts
	var cum: PackedFloat32Array = ln.cum
	s = clampf(s, 0.0, float(ln.len))
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(cum[hi] - cum[lo], 0.0001)
	var t := (s - cum[lo]) / seg
	return [pts[lo].lerp(pts[hi], t), (pts[hi] - pts[lo]).normalized()]


## Road lanes with a point within the 64 m grid cells around pos.
func lanes_near(pos: Vector3, radius: float) -> Array:
	var out := {}
	var r := ceili(radius / 64.0)
	var c := Vector2i(floori(pos.x / 64.0), floori(pos.z / 64.0))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for id in _grid.get(c + Vector2i(dx, dz), []):
				out[id] = true
	return out.keys()


## Closest distance along a lane to a world point (coarse: per point).
func project(id: int, pos: Vector3) -> float:
	var ln: Dictionary = lanes[id]
	var pts: PackedVector3Array = ln.pts
	var cum: PackedFloat32Array = ln.cum
	var best := 0.0
	var bd := INF
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := (a + ab * t).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = cum[i] + (cum[i + 1] - cum[i]) * t
	return best
