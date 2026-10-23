class_name CityCell
extends RefCounted
## Builds one 256 m city cell from the baked world on a worker thread: merged mesh arrays per material key,
## collision boxes, prop instances (by catalog name) for MultiMesh instancing, street-light positions and water
## volumes. Nothing here touches the scene tree or the rendering/physics servers.

const SIZE := 256.0
const CURB_H := 0.15
const SIDEWALK := 4.0
const WALLS := ["white_stucco", "brick_wall_09", "plastered_wall_02", "concrete_tile_facade"]
const TINTS := [Color(0.98, 0.9, 0.78), Color(0.95, 0.9, 0.86), Color(0.86, 0.92, 0.95), Color(1, 1, 1), Color(1.0, 0.86, 0.74),
	Color(0.86, 0.93, 0.9), Color(0.92, 0.85, 0.82)]
const HOUSE_TINTS := [Color(0.97, 0.94, 0.86), Color(0.98, 0.86, 0.74), Color(0.84, 0.9, 0.94), Color(0.88, 0.92, 0.84),
	Color(0.99, 0.97, 0.95), Color(0.95, 0.82, 0.78)]
const CONTAINER_TINTS := [Color(0.62, 0.16, 0.12), Color(0.16, 0.3, 0.55), Color(0.2, 0.42, 0.28), Color(0.8, 0.45, 0.12),
	Color(0.55, 0.55, 0.55), Color(0.85, 0.82, 0.78), Color(0.35, 0.18, 0.4)]
const URBAN := ["street", "avenue", "drive", "residential"]

var key: Vector2i
var data: WorldData
var net: RoadNet
var b := MeshBatch.new()
var far := MeshBatch.new()  # cheap stand-in shown when the cell isn't loaded in detail (one material)
var boxes: Array = []    # [Transform3D, Vector3 size]
var props := {}          # catalog name -> Array[Transform3D]
var lights: Array = []   # Vector3 bulb positions
var waters: Array = []   # [Vector3 centre, Vector3 size]
var occluders: Array = [] # [Vector3 centre, Vector3 size] (buildings: occlusion culling)
var meshes := {}
var far_meshes := {}
var rng := RandomNumberGenerator.new()


func _init(k: Vector2i, d: WorldData, n: RoadNet) -> void:
	key = k
	data = d
	net = n
	rng.seed = hash(k) + 1977


func build(road_ids: Array, node_ids: Array, lot_ids: Array) -> void:
	for r: int in road_ids:
		_road(r)
	for n: int in node_ids:
		_junction(n)
	for i: int in lot_ids:
		_lot(data.lots[i])
	_nature()
	meshes = b.commit()
	far_meshes = far.commit()


# ------------------------------------------------------------------------------------------------ helpers

func _plain() -> void:
	b.uv2 = Vector2.ZERO
	b.color = Color.WHITE
	b.custom0 = Color(0, 0, 0, 0)
	b.custom1 = Color(0, 0, 0, 0)


func _col(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	boxes.append([Transform3D(basis, center), size])


func _prop(name: String, pos: Vector3, yaw: float, scale := 1.0) -> void:
	_prop_xf(name, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos))


const VEGETATION := ["palm_crown", "palm_trunk", "date_palm", "jacaranda", "oak", "boulder"]


func _prop_xf(name: String, xf: Transform3D) -> void:
	# vegetation is grouped per 64 m so each group gets its own LOD (a whole cell would pick the nearest tree's)
	if name in VEGETATION and not name.contains("@"):
		name += "@%d,%d" % [floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK)]
	if not props.has(name):
		props[name] = []
	props[name].append(xf)


static func _right(f: Vector2) -> Vector2:
	return Vector2(-f.y, f.x)


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Basis whose X runs along (dx, dz) (for boxes laid along a segment).
static func _along(d: Vector2) -> Basis:
	var x := Vector3(d.x, 0, d.y).normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))


func _ground_y(x: float, z: float) -> float:
	return data.height_at(x, z)


# ------------------------------------------------------------------------------------------------ roads

## Points along road r between distances s0 and s1: [pos Vector3, right Vector2 (scaled for mitres), s].
func _samples(r: int, s0: float, s1: float) -> Array:
	var pts: Array = data.roads[r].pts
	var L: float = net.length[r]
	var ps := []
	var acc := 0.0
	for i in pts.size():
		if i > 0:
			acc += Vector2(pts[i][0], pts[i][2]).distance_to(Vector2(pts[i - 1][0], pts[i - 1][2]))
		ps.append([Vector3(pts[i][0], pts[i][1], pts[i][2]), acc])
	var rights := []
	for i in ps.size():
		var prev: Vector3 = ps[maxi(i - 1, 0)][0]
		var next: Vector3 = ps[mini(i + 1, ps.size() - 1)][0]
		var f := Vector2(next.x - prev.x, next.z - prev.z).normalized()
		rights.append(_right(f))
	var out := []
	var _push := func(pos: Vector3, rt: Vector2, s: float) -> void:
		out.append([pos, rt, s])
	# start
	var start_r := _end_right(r, 0) if s0 < 0.01 else _interp_right(ps, rights, s0)
	_push.call(_interp_pos(ps, s0), start_r, s0)
	for i in ps.size():
		var s: float = ps[i][1]
		if s > s0 + 0.05 and s < s1 - 0.05:
			_push.call(ps[i][0], rights[i], s)
	var end_r := _end_right(r, 1) if s1 > L - 0.01 else _interp_right(ps, rights, s1)
	_push.call(_interp_pos(ps, s1), end_r, s1)
	return out


func _end_right(r: int, e: int) -> Vector2:
	var s: Vector2 = net.section[Vector2i(r, e)]
	var rt := s if e == 0 else -s
	# mitre: keep the road width constant across a slanted shared section
	var pts: Array = data.roads[r].pts
	var i0 := 0 if e == 0 else pts.size() - 1
	var i1 := 1 if e == 0 else pts.size() - 2
	var f := Vector2(pts[i1][0] - pts[i0][0], pts[i1][2] - pts[i0][2]).normalized() * (1.0 if e == 0 else -1.0)
	var k := rt.dot(_right(f))
	return rt / maxf(k, 0.5)


static func _interp_pos(ps: Array, s: float) -> Vector3:
	for i in ps.size() - 1:
		if s <= ps[i + 1][1] or i == ps.size() - 2:
			var t := clampf((s - ps[i][1]) / maxf(ps[i + 1][1] - ps[i][1], 0.001), 0.0, 1.0)
			return (ps[i][0] as Vector3).lerp(ps[i + 1][0], t)
	return ps[-1][0]


static func _interp_right(ps: Array, rights: Array, s: float) -> Vector2:
	for i in ps.size() - 1:
		if s <= ps[i + 1][1] or i == ps.size() - 2:
			var a: Vector3 = ps[i][0]
			var c: Vector3 = ps[i + 1][0]
			return _right(Vector2(c.x - a.x, c.z - a.z).normalized())
	return rights[-1]


func _road(r: int) -> void:
	var rd: Dictionary = data.roads[r]
	var w: float = rd.w
	var L: float = net.length[r]
	var ta: float = net.trim[Vector2i(r, 0)]
	var tb: float = net.trim[Vector2i(r, 1)]
	var s0 := ta
	var s1 := L - tb
	if s1 - s0 < 0.3:
		return
	var kind: String = rd.kind
	var walk: bool = rd.walk
	var ja: bool = net.is_junction[int(rd.a)]
	var jb: bool = net.is_junction[int(rd.b)]
	var flags := 0
	if kind != "freeway":
		flags |= 1
	if int(rd.lanes) >= 2:
		flags |= 2
	if kind in ["freeway", "drive", "hill", "avenue"]:
		flags |= 4
	if walk and kind in URBAN:
		if ja:
			flags |= 8 | 32
		if jb:
			flags |= 16 | 64
	var sm := _samples(r, s0, s1)
	_plain()
	b.uv2 = Vector2(w, s1 - s0)
	b.custom0 = Color(float(rd.lanes), float(flags), 0, 0)
	for i in sm.size() - 1:
		var p: Vector3 = sm[i][0]
		var q: Vector3 = sm[i + 1][0]
		var rp: Vector2 = sm[i][1]
		var rq: Vector2 = sm[i + 1][1]
		var up: float = sm[i][2] - s0
		var uq: float = sm[i + 1][2] - s0
		var Lp := p - _v3(rp, 0) * w * 0.5
		var Rp := p + _v3(rp, 0) * w * 0.5
		var Lq := q - _v3(rq, 0) * w * 0.5
		var Rq := q + _v3(rq, 0) * w * 0.5
		b.quad("road", Lp, Rp, Rq, Lq, Vector2(0, up), Vector2(w, up), Vector2(w, uq), Vector2(0, uq))
	_plain()
	far.color = Color(0.2, 0.2, 0.21)
	far.custom0 = Color(0, 0, 0, 0)
	for i in sm.size() - 1:
		var p: Vector3 = sm[i][0] + Vector3(0, 0.02, 0)
		var q: Vector3 = sm[i + 1][0] + Vector3(0, 0.02, 0)
		var hw := w * 0.5 + (SIDEWALK if walk else 0.0)
		var rp := _v3(sm[i][1], 0) * hw
		var rq := _v3(sm[i + 1][1], 0) * hw
		far.quad("far", p - rp, p + rp, q + rq, q - rq, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	if kind == "freeway":
		_median(sm)
	if walk:
		var tsa: float = net.side_trim[Vector2i(r, 0)]
		var tsb: float = net.side_trim[Vector2i(r, 1)]
		if L - tsb - tsa > 0.5:
			var ss := _samples(r, tsa, L - tsb)
			for side: float in [-1.0, 1.0]:
				_sidewalk(ss, w, side, kind)
	elif kind == "hill":
		_guardrail_posts(sm, w)


func _median(sm: Array) -> void:
	var hw := 0.3
	var h := 0.85
	for i in sm.size() - 1:
		var p: Vector3 = sm[i][0]
		var q: Vector3 = sm[i + 1][0]
		var f := Vector2(q.x - p.x, q.z - p.z)
		var len := f.length()
		if len < 0.05:
			continue
		var rt := _right(f / len)
		var o := _v3(rt, 0) * hw
		var top := Vector3(0, h, 0)
		b.quad("barrier", p - o + top, p + o + top, q + o + top, q - o + top, Vector2(0, 0), Vector2(0.6, 0), Vector2(0.6, len), Vector2(0, len))
		b.wall("barrier", q + o, p + o, h)
		b.wall("barrier", p - o, q - o, h)
		_col((p + q) * 0.5 + Vector3(0, h * 0.5, 0), Vector3(len, h, hw * 2.0), _along(f))


func _guardrail_posts(sm: Array, w: float) -> void:
	# reflector posts along mountain roads every ~25 m on the downhill side
	var acc := 0.0
	for i in sm.size() - 1:
		var p: Vector3 = sm[i][0]
		var q: Vector3 = sm[i + 1][0]
		acc += p.distance_to(q)
		if acc < 25.0:
			continue
		acc = 0.0
		var rt: Vector2 = sm[i][1]
		for side: float in [-1.0, 1.0]:
			var at := p + _v3(rt, 0) * side * (w * 0.5 + 0.8)
			at.y = _ground_y(at.x, at.z)
			b.box("barrier", at + Vector3(0, 0.5, 0), Vector3(0.12, 1.0, 0.12))


func _sidewalk(ss: Array, w: float, side: float, kind: String) -> void:
	var inner := w * 0.5
	var outer := w * 0.5 + SIDEWALK
	var acc_lamp := 9.0
	var acc_tree := 4.0
	var acc_prop := 6.0
	for i in ss.size() - 1:
		var p: Vector3 = ss[i][0]
		var q: Vector3 = ss[i + 1][0]
		var rp: Vector2 = ss[i][1] * side
		var rq: Vector2 = ss[i + 1][1] * side
		var y := Vector3(0, CURB_H, 0)
		var Ip := p + _v3(rp, 0) * inner + y
		var Op := p + _v3(rp, 0) * outer + y
		var Iq := q + _v3(rq, 0) * inner + y
		var Oq := q + _v3(rq, 0) * outer + y
		if side > 0:
			b.quad("sidewalk", Ip, Op, Oq, Iq, Vector2(Ip.x, Ip.z), Vector2(Op.x, Op.z), Vector2(Oq.x, Oq.z), Vector2(Iq.x, Iq.z))
			b.wall("curb", Iq - y, Ip - y, CURB_H)
			b.wall("curb", Op - Vector3(0, 0.5, 0), Oq - Vector3(0, 0.5, 0), 0.5)
		else:
			b.quad("sidewalk", Op, Ip, Iq, Oq, Vector2(Op.x, Op.z), Vector2(Ip.x, Ip.z), Vector2(Iq.x, Iq.z), Vector2(Oq.x, Oq.z))
			b.wall("curb", Ip - y, Iq - y, CURB_H)
			b.wall("curb", Oq - Vector3(0, 0.5, 0), Op - Vector3(0, 0.5, 0), 0.5)
		var f := Vector2(q.x - p.x, q.z - p.z)
		var len := f.length()
		if len < 0.05:
			continue
		var basis := _along(f)
		var mid := (p + q) * 0.5
		var rm := _v3(((rp + rq) * 0.5).normalized(), 0)
		_col(mid + rm * (inner + SIDEWALK * 0.5) + Vector3(0, CURB_H * 0.5, 0), Vector3(len, CURB_H, SIDEWALK), basis)
		# invisible ramp at the kerb so wheels and feet mount it smoothly
		var ramp := 0.5
		var ang := atan2(CURB_H, ramp)
		_col(mid + rm * (inner - ramp * 0.5) + Vector3(0, CURB_H * 0.5 - 0.025, 0), Vector3(len, 0.05, ramp / cos(ang)),
			basis * Basis(Vector3.RIGHT, -ang * side))
		# street furniture along this stretch
		var dir := f / len
		var to_road := -_v3(rp, 0)
		var face := atan2(to_road.x, to_road.z)
		var t := 0.0
		while t < len:
			var step := minf(len - t, 1.0)
			t += step
			acc_lamp += step
			acc_tree += step
			acc_prop += step
			var at := p.lerp(q, t / len)
			var rr := _v3(rp.lerp(rq, t / len), 0)
			if acc_lamp > 27.0:
				acc_lamp = 0.0
				var lp := at + rr * (inner + 0.45) + y
				_prop("street_lamp_01", lp, face)
				lights.append(lp + Vector3(0, 3.55, 0))
			elif acc_tree > (16.0 if kind in ["avenue", "drive"] else 13.0):
				acc_tree = 0.0
				if rng.randf() < 0.8:
					var tp := at + rr * (inner + 1.0) + y
					if kind in ["avenue", "drive"]:
						_palm(tp)
					else:
						_prop("jacaranda", tp, rng.randf() * TAU, rng.randf_range(2.6, 3.4))
			elif acc_prop > 9.0:
				acc_prop = rng.randf_range(-3.0, 0.0)
				var roll := rng.randf()
				if roll < 0.2:
					_prop("fire_hydrant" if rng.randf() < 0.5 else "fire_hydrant_aged", at + rr * (inner + 0.5) + y, face + rng.randf_range(-0.3, 0.3))
				elif roll < 0.42:
					_prop("metal_trash_can" if rng.randf() < 0.6 else "metal_trash_can_rust", at + rr * (outer - 0.6) + y, rng.randf() * TAU)
				elif roll < 0.52 and kind != "residential":
					_prop("utility_box_01" if rng.randf() < 0.5 else "utility_box_02", at + rr * (outer - 0.5) + y, face + PI)
				elif roll < 0.62 and kind != "residential":
					_prop("bench", at + rr * (outer - 0.8) + y, atan2(dir.x, dir.y) + PI * 0.5)


func _palm(pos: Vector3) -> void:
	if rng.randf() < 0.3:
		_prop("date_palm", pos, rng.randf() * TAU, rng.randf_range(0.95, 1.2))
		return
	var h := rng.randf_range(11.0, 16.0)
	var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.04, 0.04), rng.randf() * TAU, rng.randf_range(-0.04, 0.04)))
	_prop_xf("palm_trunk", Transform3D(tilt * Basis.from_scale(Vector3(1, h, 1)), pos))
	var cs := rng.randf_range(1.15, 1.4)
	_prop_xf("palm_crown", Transform3D(tilt * Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * cs), pos + tilt * Vector3(0, h - 1.6 * cs, 0)))


# ------------------------------------------------------------------------------------------------ junctions

func _junction(node: int) -> void:
	if not net.is_junction.get(node, false):
		return
	var list: Array = net.ends[node]
	var c := net.node_pos(node)
	var poly := []   # Vector3 corners in increasing angle
	var info := []
	for e: Dictionary in list:
		var t: float = net.trim[Vector2i(e.road, e.end)]
		var p := net.along_from_node(e, t)
		var rt := _v3(_right(e.dir), 0)
		var hw: float = e.w * 0.5
		poly.append(p - rt * hw)
		poly.append(p + rt * hw)
		info.append({"t": t, "ts": net.side_trim[Vector2i(e.road, e.end)], "p": p, "rt": rt, "hw": hw, "e": e})
	_plain()
	b.uv2 = Vector2(100, 100)
	b.custom0 = Color(1, 128, 0, 0)
	for i in poly.size():
		var a: Vector3 = poly[i]
		var d: Vector3 = poly[(i + 1) % poly.size()]
		b.tri("road", c, d, a, Vector2(c.x, c.z), Vector2(d.x, d.z), Vector2(a.x, a.z))
	_plain()
	# sidewalk corners between neighbouring roads
	for i in info.size():
		var A: Dictionary = info[i]
		var B: Dictionary = info[(i + 1) % info.size()]
		if not (A.e.walk and B.e.walk):
			continue
		var gap := wrapf(B.e.ang - A.e.ang, 0.0, TAU)
		if info.size() > 1 and gap > deg_to_rad(200):
			continue
		var pa_s := net.along_from_node(A.e, A.ts)
		var pb_s := net.along_from_node(B.e, B.ts)
		var y := Vector3(0, CURB_H, 0)
		var pts := [
			A.p + A.rt * A.hw, pa_s + A.rt * A.hw, pa_s + A.rt * (A.hw + SIDEWALK),
			pb_s - B.rt * (B.hw + SIDEWALK), pb_s - B.rt * B.hw, B.p - B.rt * B.hw,
		]
		var cen := Vector3.ZERO
		for p: Vector3 in pts:
			cen += p
		cen /= pts.size()
		for k in pts.size():
			var a: Vector3 = pts[k] + y
			var d: Vector3 = pts[(k + 1) % pts.size()] + y
			if a.distance_to(d) < 0.01:
				continue
			# keep the fan facing up whichever way the outline runs
			if (d - cen).cross(a - cen).y > 0.0:
				b.tri("sidewalk", cen + y, d, a, Vector2(cen.x, cen.z), Vector2(d.x, d.z), Vector2(a.x, a.z))
			else:
				b.tri("sidewalk", cen + y, a, d, Vector2(cen.x, cen.z), Vector2(a.x, a.z), Vector2(d.x, d.z))
		# kerb faces where the corner meets asphalt (both sides so they're visible from anywhere)
		for seg: Array in [[pts[0], pts[1]], [pts[4], pts[5]], [pts[5], pts[0]]]:
			if (seg[0] as Vector3).distance_to(seg[1]) > 0.05:
				b.wall("curb", seg[0], seg[1], CURB_H)
				b.wall("curb", seg[1], seg[0], CURB_H)
		# collision: box over the corner in road A's frame
		var fa: Vector2 = A.e.dir
		var basis := _along(fa)
		var lo := Vector3(INF, 0, INF)
		var hi := Vector3(-INF, 0, -INF)
		var inv := basis.inverse()
		for p: Vector3 in pts:
			var l := inv * (p - cen)
			lo = Vector3(minf(lo.x, l.x), 0, minf(lo.z, l.z))
			hi = Vector3(maxf(hi.x, l.x), 0, maxf(hi.z, l.z))
		var mid := cen + basis * ((lo + hi) * 0.5)
		_col(mid + Vector3(0, CURB_H * 0.5, 0), Vector3(hi.x - lo.x, CURB_H, hi.z - lo.z), basis)


# ------------------------------------------------------------------------------------------------ nature

const CHUNK := 64.0  # trees are grouped per 64 m so each group picks its own LOD / visibility


## Wild oaks and boulders from the baked density map (hills, shores), on an 9 m jittered grid.
func _nature() -> void:
	var x0 := key.x * SIZE
	var z0 := key.y * SIZE
	var g := 7.0
	var n := int(SIZE / g)
	for j in n:
		for i in n:
			var x := x0 + (i + rng.randf()) * g
			var z := z0 + (j + rng.randf()) * g
			var dens := data.nature_at(x, z)
			if dens < 0.05 or rng.randf() > dens * 0.75:
				continue
			var y := _ground_y(x, z)
			if y < data.sea + 1.0:
				continue
			var nrm := data.normal_at(x, z)
			var pos := Vector3(x, y - 0.1, z)
			var ck := "@%d,%d" % [floori(x / CHUNK), floori(z / CHUNK)]
			if nrm.y < 0.82 or rng.randf() < 0.12:
				_prop("boulder" + ck, pos - Vector3(0, 0.3, 0), rng.randf() * TAU, rng.randf_range(0.8, 2.6))
			else:
				_prop("oak" + ck, pos, rng.randf() * TAU, rng.randf_range(0.7, 1.3))


# ------------------------------------------------------------------------------------------------ lots

func _lot(l: Dictionary) -> void:
	var r := Rect2(l.x0, l.z0, l.x1 - l.x0, l.z1 - l.z0)
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	rng.seed = int(l.get("seed", 1)) + 7
	match String(l.kind):
		"block":
			_block(r, bool(l.get("core", false)), int(l.get("ring", 3)))
		"plaza":
			_plaza_block(r)
		"park":
			_park(r)
		"beachfront":
			_beachfront(r)
		"midrise":
			_block(r, false, 3)
		"mall":
			_mall(r)
		"parking":
			_parking(r)
		"gas_station":
			_gas_station(r)
		"industrial":
			_industrial(r)
		"port_sheds":
			_sheds(r)
		"container_yard":
			_containers(r)
		"crane":
			_crane(r)
		"house":
			_house(r, float(l.get("yaw", 0.0)), false)
		"mansion":
			_house(r, float(l.get("yaw", 0.0)), true)
		"boardwalk":
			_boardwalk(r)
		"pier":
			_pier(r)
		"lifeguard":
			_lifeguard(r)
		"lookout":
			_lookout(r)


func _ground(r: Rect2, key := "ground", y := CURB_H) -> void:
	_plain()
	b.flat(key, r.position.x, r.position.y, r.end.x, r.end.y, y)
	_col(Vector3(r.get_center().x, y * 0.5, r.get_center().y), Vector3(r.size.x, y, r.size.y))


## Four lots in a block with 5 m alleys.
static func _quarters(r: Rect2) -> Array:
	var hw := r.size.x * 0.5
	var hd := r.size.y * 0.5
	return [Rect2(r.position, Vector2(hw - 2.5, hd - 2.5)), Rect2(r.position + Vector2(hw + 2.5, 0), Vector2(hw - 2.5, hd - 2.5)),
		Rect2(r.position + Vector2(0, hd + 2.5), Vector2(hw - 2.5, hd - 2.5)), Rect2(r.position + Vector2(hw + 2.5, hd + 2.5), Vector2(hw - 2.5, hd - 2.5))]


func _block(r: Rect2, core: bool, ring: int) -> void:
	_ground(r)
	var q := _quarters(r)
	var wall: String = WALLS[rng.randi() % WALLS.size()]
	if core:
		var tall := rng.randi_range(14, 32)
		_building(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5 - 2.5)), CURB_H, tall, "concrete_tile_facade" if rng.randf() < 0.6 else "plastered_wall_02",
			Color(0.95, 0.95, 0.97), true, 1)
		_building(q[2], CURB_H, rng.randi_range(8, 16), WALLS[rng.randi() % 4], TINTS[rng.randi() % TINTS.size()], true, 0)
		_building(q[3], CURB_H, rng.randi_range(9, 20), WALLS[rng.randi() % 4], TINTS[rng.randi() % TINTS.size()], true, 2)
		return
	var lo := 5 if ring <= 2 else 2
	var hi := 12 if ring <= 2 else 7
	if rng.randf() < 0.3:
		# one wide building along one side, two smaller behind
		_building(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5 - 2.5)), CURB_H, rng.randi_range(lo, hi), wall, TINTS[rng.randi() % TINTS.size()], true, 0)
		_building(q[2], CURB_H, rng.randi_range(lo, hi), WALLS[rng.randi() % 4], TINTS[rng.randi() % TINTS.size()], true, 0)
		_building(q[3], CURB_H, rng.randi_range(lo, hi), WALLS[rng.randi() % 4], TINTS[rng.randi() % TINTS.size()], true, 0)
	else:
		for lot: Rect2 in q:
			_building(lot, CURB_H, rng.randi_range(lo, hi), WALLS[rng.randi() % 4], TINTS[rng.randi() % TINTS.size()], true, rng.randi() % 3)


## Facade-shaded box building with cornice roof, rooftop units and collision. Towers on big lots get a podium
## and a set-back shaft, and sometimes rooftop water tanks or a mast.
func _building(lot: Rect2, base_y: float, floors: int, wall: String, tint: Color, storefront: bool, glass: int) -> void:
	if floors >= 14 and lot.size.x > 24.0 and lot.size.y > 20.0 and rng.randf() < 0.7:
		var podium := rng.randi_range(3, 5)
		_box_building(lot, base_y, podium, wall, tint, storefront, glass)
		var inset := rng.randf_range(3.0, minf(lot.size.x, lot.size.y) * 0.22)
		var top_y := base_y + 4.2 + float(podium - 1) * 3.3 + 1.2
		var shaft := lot.grow(-inset)
		var tw: String = "concrete_tile_facade" if rng.randf() < 0.5 else wall
		_box_building(shaft, top_y, floors - podium, tw, tint, false, glass)
		_rooftop(shaft, top_y + float(floors - podium - 1) * 3.3 + 5.4)
		return
	_box_building(lot, base_y, floors, wall, tint, storefront, glass)
	if floors >= 8:
		_rooftop(lot, base_y + 4.2 + float(floors - 1) * 3.3 + 1.2)


func _rooftop(lot: Rect2, top: float) -> void:
	var roll := rng.randf()
	var c := lot.get_center()
	if roll < 0.35:
		# timber water tank on legs
		var p := Vector3(c.x + rng.randf_range(-lot.size.x, lot.size.x) * 0.25, top, c.y + rng.randf_range(-lot.size.y, lot.size.y) * 0.25)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.box("metal", p + Vector3(sx * 1.3, 1.0, sz * 1.3), Vector3(0.18, 2.0, 0.18))
		b.box("piles", p + Vector3(0, 3.4, 0), Vector3(3.2, 2.8, 3.2))
		b.box("roof", p + Vector3(0, 5.0, 0), Vector3(3.4, 0.4, 3.4))
	elif roll < 0.55:
		# antenna mast with a red beacon
		var p := Vector3(c.x, top, c.y)
		b.box("metal", p + Vector3(0, 6.0, 0), Vector3(0.4, 12.0, 0.4))
		b.box("metal", p + Vector3(0, 0.6, 0), Vector3(2.0, 1.2, 2.0))
	elif roll < 0.75:
		# lift / plant room
		b.box("roof", Vector3(c.x, top + 1.8, c.y), Vector3(minf(lot.size.x * 0.4, 10.0), 3.6, minf(lot.size.y * 0.35, 8.0)))


func _box_building(lot: Rect2, base_y: float, floors: int, wall: String, tint: Color, storefront: bool, glass: int) -> void:
	var height := 4.2 + float(floors - 1) * 3.3 + 1.2
	var tall := floors >= 10
	var frame: Color = [Color(0.92, 0.91, 0.88), Color(0.25, 0.25, 0.26), Color(0.55, 0.38, 0.28)][rng.randi() % 3]
	b.uv2 = Vector2(0, height)
	b.custom0 = Color(2.6 if tall else rng.randf_range(2.9, 3.6), 2.1 if tall else rng.randf_range(1.1, 1.6),
		2.3 if tall else rng.randf_range(1.5, 1.9), 0.6 if tall else 0.95)
	b.custom1 = Color(frame.r, frame.g, frame.b, (1.0 if storefront else 0.0) + 2.0 * glass)
	var x0 := lot.position.x
	var x1 := lot.end.x
	var z0 := lot.position.y
	var z1 := lot.end.y
	for f: Array in [[Vector3(x0, base_y, z1), Vector3(x1, base_y, z1)], [Vector3(x1, base_y, z1), Vector3(x1, base_y, z0)],
			[Vector3(x1, base_y, z0), Vector3(x0, base_y, z0)], [Vector3(x0, base_y, z0), Vector3(x0, base_y, z1)]]:
		b.uv2.x = (f[0] as Vector3).distance_to(f[1])
		b.color = Color(tint.r, tint.g, tint.b, rng.randf())
		b.wall("facade:" + wall, f[0], f[1], height)
	_plain()
	_roof(lot, base_y + height)
	_col(Vector3(lot.get_center().x, base_y + height * 0.5, lot.get_center().y), Vector3(lot.size.x, height, lot.size.y))
	_far_box(lot, base_y, height, tint, 1.0)
	if height > 8.0:
		occluders.append([Vector3(lot.get_center().x, base_y + height * 0.5, lot.get_center().y), Vector3(lot.size.x - 0.6, height - 1.0, lot.size.y - 0.6)])


## Stand-in box for the far version: walls with a coarse window pattern (CUSTOM0.x = 1), plain roof.
func _far_box(lot: Rect2, base_y: float, height: float, tint: Color, windows: float) -> void:
	far.color = tint * 0.9
	far.custom0 = Color(windows, 0, 0, 0)
	var x0 := lot.position.x
	var x1 := lot.end.x
	var z0 := lot.position.y
	var z1 := lot.end.y
	for f: Array in [[Vector3(x0, base_y, z1), Vector3(x1, base_y, z1)], [Vector3(x1, base_y, z1), Vector3(x1, base_y, z0)],
			[Vector3(x1, base_y, z0), Vector3(x0, base_y, z0)], [Vector3(x0, base_y, z0), Vector3(x0, base_y, z1)]]:
		far.wall("far", f[0], f[1], height)
	far.color = Color(0.55, 0.55, 0.53)
	far.custom0 = Color(0, 0, 0, 0)
	far.flat("far", x0, z0, x1, z1, base_y + height)


func _roof(lot: Rect2, top: float) -> void:
	var r := lot.grow(0.35)
	var t := 0.45
	b.flat("roof", r.position.x, r.position.y, r.end.x, r.end.y, top)
	for f: Array in [[Vector3(r.position.x, top - t, r.end.y), Vector3(r.end.x, top - t, r.end.y)], [Vector3(r.end.x, top - t, r.end.y), Vector3(r.end.x, top - t, r.position.y)],
			[Vector3(r.end.x, top - t, r.position.y), Vector3(r.position.x, top - t, r.position.y)], [Vector3(r.position.x, top - t, r.position.y), Vector3(r.position.x, top - t, r.end.y)]]:
		b.wall("roof", f[0], f[1], t, top - t)
	var n := 1 + rng.randi() % 3
	for i in n:
		if lot.size.x > 6 and lot.size.y > 6:
			_prop("exterior_aircon_unit", Vector3(rng.randf_range(lot.position.x + 2, lot.end.x - 2), top, rng.randf_range(lot.position.y + 2, lot.end.y - 2)), rng.randf() * TAU, 1.6)


func _plaza_block(r: Rect2) -> void:
	var pr := Rect2(data.pool[0], data.pool[1], data.pool[2] - data.pool[0], data.pool[3] - data.pool[1]) if data.pool.size() == 4 else Rect2()
	if pr.size != Vector2.ZERO:
		# ground around the pool's coping only (the basin sits below it)
		for q: Rect2 in _around(r, pr.grow(0.45)):
			_plain()
			b.flat("ground", q.position.x, q.position.y, q.end.x, q.end.y, CURB_H)
		for q: Rect2 in _around(r, pr):
			_col(Vector3(q.get_center().x, CURB_H * 0.5, q.get_center().y), Vector3(q.size.x, CURB_H, q.size.y))
	else:
		_ground(r)
	var q := _quarters(r)
	_building(q[0], CURB_H, 6, "white_stucco", Color(0.98, 0.9, 0.78), true, 0)
	_building(q[1], CURB_H, 4, "brick_wall_09", Color(1, 1, 1), true, 0)
	_building(q[2], CURB_H, 7, "plastered_wall_02", Color(1.0, 0.86, 0.74), true, 0)
	var lot: Rect2 = q[3]
	var c := lot.get_center()
	if pr.size != Vector2.ZERO:
		_pool(pr, 2.0)
		for sx: float in [-3.5, 3.5]:
			for sz: float in [-1.0, 1.0]:
				_prop("bench", Vector3(c.x + sx, CURB_H, c.y + sz * (pr.size.y * 0.5 + 2.2)), 0.0)
	for i in 4:
		var a := TAU * i / 4.0
		var lp := Vector3(c.x + cos(a) * 11.0, CURB_H, c.y + sin(a) * 11.0)
		_prop("street_lamp_01", lp, -a)
		lights.append(lp + Vector3(0, 3.55, 0))
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		_palm(Vector3(c.x + cos(a) * 15.5, CURB_H, c.y + sin(a) * 15.5))


## Sunken basin with stone coping flush with the ground at CURB_H; water surface at y = 0.
func _pool(p: Rect2, depth: float) -> void:
	var floor_y := -depth
	var coping := p.grow(0.45)
	_plain()
	# the lot ground was laid over the pool too: punch nothing (the coping/water sit on top) — the ground quad
	# is replaced by the coping band below and the basin, so cover the hole with those only
	for q: Rect2 in _around(coping, p):
		b.flat("coping", q.position.x, q.position.y, q.end.x, q.end.y, CURB_H + 0.006)
	_basin(p, -0.12, CURB_H + 0.006, "coping")
	b.flat("pool_tiles", p.position.x, p.position.y, p.end.x, p.end.y, floor_y)
	_basin(p, floor_y, -0.12, "pool_tiles")
	_col(Vector3(p.get_center().x, floor_y - 0.25, p.get_center().y), Vector3(p.size.x + 1.0, 0.5, p.size.y + 1.0))
	var wy := floor_y * 0.5
	_col(Vector3(p.position.x - 0.25, wy, p.get_center().y), Vector3(0.5, -floor_y, p.size.y + 1.0))
	_col(Vector3(p.end.x + 0.25, wy, p.get_center().y), Vector3(0.5, -floor_y, p.size.y + 1.0))
	_col(Vector3(p.get_center().x, wy, p.position.y - 0.25), Vector3(p.size.x, -floor_y, 0.5))
	_col(Vector3(p.get_center().x, wy, p.end.y + 0.25), Vector3(p.size.x, -floor_y, 0.5))
	waters.append([Vector3(p.get_center().x, -depth * 0.5, p.get_center().y), Vector3(p.size.x, depth, p.size.y)])


static func _around(r: Rect2, hole: Rect2) -> Array:
	return [Rect2(r.position.x, r.position.y, r.size.x, hole.position.y - r.position.y),
		Rect2(r.position.x, hole.end.y, r.size.x, r.end.y - hole.end.y),
		Rect2(r.position.x, hole.position.y, hole.position.x - r.position.x, hole.size.y),
		Rect2(hole.end.x, hole.position.y, r.end.x - hole.end.x, hole.size.y)]


func _basin(p: Rect2, y0: float, y1: float, key: String) -> void:
	var x0 := p.position.x
	var x1 := p.end.x
	var z0 := p.position.y
	var z1 := p.end.y
	var h := y1 - y0
	b.wall(key, Vector3(x0, y0, z0), Vector3(x1, y0, z0), h, y0)
	b.wall(key, Vector3(x1, y0, z1), Vector3(x0, y0, z1), h, y0)
	b.wall(key, Vector3(x0, y0, z1), Vector3(x0, y0, z0), h, y0)
	b.wall(key, Vector3(x1, y0, z0), Vector3(x1, y0, z1), h, y0)


func _park(r: Rect2) -> void:
	_plain()
	_col(Vector3(r.get_center().x, CURB_H * 0.5, r.get_center().y), Vector3(r.size.x, CURB_H, r.size.y))
	b.flat("grass", r.position.x, r.position.y, r.end.x, r.end.y, CURB_H)
	var c := r.get_center()
	# cross paths
	b.flat("path", c.x - 1.6, r.position.y, c.x + 1.6, r.end.y, CURB_H + 0.012)
	b.flat("path", r.position.x, c.y - 1.6, r.end.x, c.y + 1.6, CURB_H + 0.012)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		_prop("bench", Vector3(c.x + cos(a) * 5.5, CURB_H, c.y + sin(a) * 5.5), -a + PI * 0.5)
	for i in 4:
		var p := Vector3(c.x + (8.0 if i % 2 == 0 else -8.0), CURB_H, c.y + (8.0 if i < 2 else -8.0))
		_prop("street_lamp_01", p, 0.0)
		lights.append(p + Vector3(0, 3.55, 0))
	var n := int(r.size.x * r.size.y / 140.0)
	for i in n:
		var p := Vector3(rng.randf_range(r.position.x + 2, r.end.x - 2), CURB_H, rng.randf_range(r.position.y + 2, r.end.y - 2))
		if absf(p.x - c.x) < 3.0 or absf(p.z - c.y) < 3.0:
			continue
		if rng.randf() < 0.5:
			_prop("oak", p, rng.randf() * TAU, rng.randf_range(0.8, 1.15))
		else:
			_prop("jacaranda", p, rng.randf() * TAU, rng.randf_range(2.6, 3.6))


func _beachfront(r: Rect2) -> void:
	_ground(r)
	var x := r.position.x
	# hotels facing the ocean (west), low-rise shops behind
	var hotel_w := minf(r.size.x * 0.55, 60.0)
	var z := r.position.y
	while z < r.end.y - 12.0:
		var d := minf(rng.randf_range(22.0, 34.0), r.end.y - z)
		_building(Rect2(x, z, hotel_w, d - 4.0), CURB_H, rng.randi_range(5, 14), "white_stucco" if rng.randf() < 0.6 else "plastered_wall_02",
			HOUSE_TINTS[rng.randi() % HOUSE_TINTS.size()], true, 2)
		z += d
	var z2 := r.position.y
	while z2 < r.end.y - 10.0:
		var d2 := minf(rng.randf_range(16.0, 26.0), r.end.y - z2)
		_building(Rect2(x + hotel_w + 5.0, z2, r.size.x - hotel_w - 5.0, d2 - 3.0), CURB_H, rng.randi_range(1, 3), WALLS[rng.randi() % 3],
			TINTS[rng.randi() % TINTS.size()], true, 0)
		z2 += d2
	for i in int(r.size.y / 14.0):
		_palm(Vector3(r.position.x + 1.5, CURB_H, r.position.y + 7.0 + i * 14.0))


func _mall(r: Rect2) -> void:
	_parking(r)
	var inner := r.grow(-14.0)
	if inner.size.x > 10 and inner.size.y > 10:
		_building(inner, CURB_H, rng.randi_range(2, 3), "concrete_tile_facade", Color(0.96, 0.95, 0.92), true, 0)


func _parking(r: Rect2) -> void:
	_plain()
	_col(Vector3(r.get_center().x, CURB_H * 0.5, r.get_center().y), Vector3(r.size.x, CURB_H, r.size.y))
	b.uv2 = Vector2(r.size.x, r.size.y)
	b.custom0 = Color(1, 128 | 256, 0, 0)
	b.quad("road", Vector3(r.position.x, CURB_H, r.end.y), Vector3(r.end.x, CURB_H, r.end.y), Vector3(r.end.x, CURB_H, r.position.y), Vector3(r.position.x, CURB_H, r.position.y),
		Vector2(0, r.size.y), Vector2(r.size.x, r.size.y), Vector2(r.size.x, 0), Vector2(0, 0))
	_plain()
	var nl := int(r.size.x / 30.0)
	for i in nl:
		var p := Vector3(r.position.x + (i + 0.5) * r.size.x / nl, CURB_H, r.get_center().y)
		_prop("street_lamp_01", p, 0.0)
		lights.append(p + Vector3(0, 3.55, 0))


func _gas_station(r: Rect2) -> void:
	_parking(r)
	var c := r.get_center()
	# canopy on four pillars over the pumps
	var cw := minf(r.size.x * 0.5, 22.0)
	var cd := minf(r.size.y * 0.5, 14.0)
	b.box("canopy", Vector3(c.x, CURB_H + 5.4, c.y), Vector3(cw, 0.7, cd), true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(c.x + sx * (cw * 0.5 - 1.0), CURB_H + 2.6, c.y + sz * (cd * 0.5 - 1.0))
			b.box("canopy", p, Vector3(0.5, 5.2, 0.5))
			_col(p, Vector3(0.5, 5.2, 0.5))
	for i in 3:
		var p := Vector3(c.x - cw * 0.3 + i * cw * 0.3, CURB_H + 0.8, c.y)
		b.box("metal", p, Vector3(0.9, 1.6, 0.6))
		_col(p, Vector3(0.9, 1.6, 0.6))
		lights.append(Vector3(p.x, CURB_H + 5.0, p.z))
	var shop := Rect2(r.end.x - 18.0, r.position.y + 3.0, 15.0, 11.0)
	if shop.position.x > r.position.x:
		_building(shop, CURB_H, 1, "white_stucco", Color(0.95, 0.95, 0.93), true, 0)


func _industrial(r: Rect2) -> void:
	_parking(r)
	var x := r.position.x + 6.0
	while x < r.end.x - 20.0:
		var w := minf(rng.randf_range(36.0, 70.0), r.end.x - 6.0 - x)
		_warehouse(Rect2(x, r.position.y + 8.0, w, r.size.y - 22.0), rng.randf_range(8.0, 13.0))
		x += w + 10.0


func _sheds(r: Rect2) -> void:
	_parking(r)
	var x := r.position.x + 10.0
	while x < r.end.x - 30.0:
		var w := minf(rng.randf_range(70.0, 120.0), r.end.x - 10.0 - x)
		_warehouse(Rect2(x, r.position.y + 6.0, w, r.size.y - 12.0), rng.randf_range(10.0, 14.0))
		x += w + 18.0


## Corrugated-metal shed with roller doors on the long sides.
func _warehouse(r: Rect2, h: float) -> void:
	var y := CURB_H
	var tint: Color = [Color(0.85, 0.86, 0.88), Color(0.72, 0.78, 0.82), Color(0.9, 0.85, 0.74), Color(0.66, 0.7, 0.66)][rng.randi() % 4]
	_plain()
	b.color = tint
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	b.wall("metal", Vector3(x0, y, z1), Vector3(x1, y, z1), h)
	b.wall("metal", Vector3(x1, y, z1), Vector3(x1, y, z0), h)
	b.wall("metal", Vector3(x1, y, z0), Vector3(x0, y, z0), h)
	b.wall("metal", Vector3(x0, y, z0), Vector3(x0, y, z1), h)
	_plain()
	b.flat("roof", x0 - 0.3, z0 - 0.3, x1 + 0.3, z1 + 0.3, y + h)
	# roller doors
	var n := int(r.size.x / 14.0)
	for i in n:
		var cx := x0 + (i + 0.5) * r.size.x / n
		b.wall("shutter", Vector3(cx - 2.2, y, z1 + 0.03), Vector3(cx + 2.2, y, z1 + 0.03), 4.6)
		b.wall("shutter", Vector3(cx + 2.2, y, z0 - 0.03), Vector3(cx - 2.2, y, z0 - 0.03), 4.6)
		lights.append(Vector3(cx, y + 5.4, z1 + 0.6))
	_col(Vector3(r.get_center().x, y + h * 0.5, r.get_center().y), Vector3(r.size.x, h, r.size.y))
	_far_box(r, y, h, tint * 0.8, 0.0)
	occluders.append([Vector3(r.get_center().x, y + h * 0.5, r.get_center().y), Vector3(r.size.x - 0.6, h - 0.6, r.size.y - 0.6)])


func _containers(r: Rect2) -> void:
	_parking(r)
	var L := 12.2
	var W := 2.44
	var H := 2.6
	var x := r.position.x + 4.0
	while x < r.end.x - L:
		var z := r.position.y + 6.0
		while z < r.end.y - W * 4.0:
			# a block of rows 4 wide, stacked 1-4 high
			for row in 4:
				var stack := rng.randi_range(1, 4)
				for lvl in stack:
					_plain()
					b.color = CONTAINER_TINTS[rng.randi() % CONTAINER_TINTS.size()]
					var cpos := Vector3(x + L * 0.5, CURB_H + H * (lvl + 0.5), z + W * (row + 0.5) + row * 0.12)
					b.box("container", cpos, Vector3(L, H, W))
				_col(Vector3(x + L * 0.5, CURB_H + H * stack * 0.5, z + W * (row + 0.5) + row * 0.12), Vector3(L, H * stack, W))
			_far_box(Rect2(x, z, L, W * 4.0 + 0.36), CURB_H, H * 2.0, Color(0.5, 0.35, 0.3), 0.0)
			z += W * 4.0 + 10.0
		x += L + (2.0 if rng.randf() < 0.7 else 14.0)
	_plain()


## Ship-to-shore gantry crane: legs straddling the quay, boom out over the water.
func _crane(r: Rect2) -> void:
	var c := r.get_center()
	var y := CURB_H
	var leg_h := 32.0
	_plain()
	b.color = Color(0.75, 0.16, 0.12) if rng.randf() < 0.5 else Color(0.9, 0.9, 0.88)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(c.x + sx * 8.0, y + leg_h * 0.5, c.y + sz * 9.0)
			b.box("crane", p, Vector3(1.2, leg_h, 1.2))
			_col(p, Vector3(1.2, leg_h, 1.2))
		b.box("crane", Vector3(c.x + sx * 8.0, y + 6.0, c.y), Vector3(0.8, 0.8, 18.0))
	# portal beams and boom (out over the sea to the south)
	b.box("crane", Vector3(c.x, y + leg_h, c.y), Vector3(17.2, 2.4, 20.0), true)
	b.box("crane", Vector3(c.x, y + leg_h + 1.6, c.y + 28.0), Vector3(3.0, 1.6, 76.0), true)
	b.box("crane", Vector3(c.x, y + leg_h + 10.0, c.y - 2.0), Vector3(2.0, 18.0, 2.0))
	_plain()
	b.box("canopy", Vector3(c.x + 1.8, y + leg_h - 2.6, c.y + 14.0), Vector3(2.6, 2.4, 3.0), true)
	lights.append(Vector3(c.x, y + leg_h - 1.0, c.y + 30.0))


## Suburban house (pitched tile roof) or hillside villa (flat roof, terrace, pool). Front faces -Z before yaw.
func _house(r: Rect2, yaw: float, villa: bool) -> void:
	var c := r.get_center()
	var w := rng.randf_range(10.0, 13.0) if not villa else rng.randf_range(18.0, 24.0)
	var d := rng.randf_range(8.5, 10.5) if not villa else rng.randf_range(12.0, 15.0)
	var floors := (1 if rng.randf() < 0.6 else 2) if not villa else 2
	var wall_h := floors * 3.0 + 0.3
	var basis := Basis(Vector3.UP, yaw)
	var lc := c + Vector2(0, 1.5).rotated(-yaw) if not villa else c
	var corners: Array[Vector3] = []
	for s: Vector2 in [Vector2(-w, -d), Vector2(w, -d), Vector2(w, d), Vector2(-w, d)]:
		var p := basis * Vector3(s.x * 0.5, 0, s.y * 0.5) + Vector3(lc.x, 0, lc.y)
		corners.append(p)
	var gmin := INF
	var gmax := -INF
	for p: Vector3 in corners:
		var g := _ground_y(p.x, p.z)
		gmin = minf(gmin, g)
		gmax = maxf(gmax, g)
	var base := gmax + 0.2
	for i in 4:
		corners[i].y = base
	# plinth down to the lowest ground
	_plain()
	for i in 4:
		var a: Vector3 = corners[i]
		var e: Vector3 = corners[(i + 1) % 4]
		b.wall("plinth", e - Vector3(0, base - gmin + 0.3, 0), a - Vector3(0, base - gmin + 0.3, 0), base - gmin + 0.3)
	var tint: Color = HOUSE_TINTS[rng.randi() % HOUSE_TINTS.size()]
	b.uv2 = Vector2(0, wall_h)
	b.custom0 = Color(3.0 if not villa else 4.2, 1.3 if not villa else 3.0, 1.4 if not villa else 2.3, 0.9 if not villa else 0.35)
	b.custom1 = Color(0.95, 0.95, 0.93, 2.0 * 2.0)
	var key := "facade_res:" + ("white_stucco" if rng.randf() < 0.7 or villa else "plastered_wall_02")
	for i in 4:
		var a: Vector3 = corners[(i + 1) % 4]
		var e: Vector3 = corners[i]
		b.uv2.x = a.distance_to(e)
		b.color = Color(tint.r, tint.g, tint.b, rng.randf())
		b.wall(key, e, a, wall_h)
	var top := base + wall_h
	_plain()
	var fwd := basis * Vector3(0, 0, -1)
	var rgt := basis * Vector3(1, 0, 0)
	var front_mid := (corners[0] + corners[1]) * 0.5
	# door and garage on the front (-Z) facade
	var door_c := front_mid - rgt * (w * 0.18) + fwd * 0.03
	b.wall("door", door_c - rgt * 0.5, door_c + rgt * 0.5, 2.15)
	var gar_c := front_mid + rgt * (w * 0.25) + fwd * 0.03
	b.wall("shutter", gar_c - rgt * 1.5, gar_c + rgt * 1.5, 2.4)
	# driveway to the street
	var street := front_mid + fwd * 12.0
	var dw0 := gar_c + Vector3(0, 0, 0)
	for k in 6:
		var a := dw0.lerp(street, k / 6.0)
		var e := dw0.lerp(street, (k + 1) / 6.0)
		a.y = _ground_y(a.x, a.z) + 0.04
		e.y = _ground_y(e.x, e.z) + 0.04
		b.quad("ground", a - rgt * 1.6, a + rgt * 1.6, e + rgt * 1.6, e - rgt * 1.6,
			Vector2(a.x, a.z), Vector2(a.x, a.z) + Vector2(1, 0), Vector2(e.x, e.z), Vector2(e.x, e.z))
	if villa:
		_flat_roof(corners, top, basis)
		# pool on the terrace behind
		var back := (corners[2] + corners[3]) * 0.5 - fwd * 6.0
		var pr := Rect2(back.x - 4.0, back.z - 2.0, 8.0, 4.0)
		var gy := _ground_y(back.x, back.z)
		b.flat("coping", pr.position.x - 3.0, pr.position.y - 3.0, pr.end.x + 3.0, pr.end.y + 3.0, gy + 0.3)
		b.flat("pool_tiles", pr.position.x, pr.position.y, pr.end.x, pr.end.y, gy + 0.32)
		waters.append([Vector3(pr.get_center().x, gy + 0.25, pr.get_center().y), Vector3(pr.size.x, 0.1, pr.size.y)])
	else:
		_gable(corners, top, basis, w, d, tint)
	_col(Vector3(lc.x, (base + top) * 0.5 - (base - gmin) * 0.5, lc.y), Vector3(w, top - gmin, d), basis)
	_far_box(_rect_of(corners).grow(-0.5), base, wall_h + (0.0 if villa else 1.5), tint, 0.0)
	# a tree or two in the yard
	for k in rng.randi_range(1, 2):
		var off := basis * Vector3(rng.randf_range(-w * 0.6, w * 0.6), 0, -d * 0.5 - rng.randf_range(3.0, 6.0))
		var tp := Vector3(lc.x, 0, lc.y) + off
		if absf(off.dot(rgt) - w * 0.25) < 2.5:
			continue
		tp.y = _ground_y(tp.x, tp.z)
		if rng.randf() < 0.45:
			_prop("jacaranda", tp, rng.randf() * TAU, rng.randf_range(2.6, 3.4))
		elif rng.randf() < 0.6:
			_palm(tp)
		else:
			_prop("oak", tp, rng.randf() * TAU, rng.randf_range(0.6, 0.85))


static func _rect_of(pts: Array[Vector3]) -> Rect2:
	var r := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
	for p: Vector3 in pts:
		r = r.expand(Vector2(p.x, p.z))
	return r


## Gable roof along the house's long axis (local X) with overhangs; clay tiles, gable ends in plaster.
func _gable(corners: Array[Vector3], top: float, basis: Basis, w: float, d: float, tint: Color) -> void:
	var o := 0.45
	var rise := (d * 0.5 + o) * tan(deg_to_rad(28.0))
	var c := (corners[0] + corners[2]) * 0.5
	c.y = top
	var X := basis * Vector3(w * 0.5 + o, 0, 0)
	var Z := basis * Vector3(0, 0, d * 0.5 + o)
	var ridge := Vector3(0, rise, 0)
	var eave := Vector3(0, -o * tan(deg_to_rad(28.0)), 0)
	var slope_len := (Z + ridge).length()
	# front slope (-Z side) and back slope (+Z side)
	b.quad("roof_tiles", c - Z - X + eave, c - Z + X + eave, c + X + ridge, c - X + ridge, Vector2(0, 0), Vector2(w + 2 * o, 0), Vector2(w + 2 * o, slope_len), Vector2(0, slope_len))
	b.quad("roof_tiles", c + Z + X + eave, c + Z - X + eave, c - X + ridge, c + X + ridge, Vector2(0, 0), Vector2(w + 2 * o, 0), Vector2(w + 2 * o, slope_len), Vector2(0, slope_len))
	# undersides (visible from below the eaves)
	b.quad("roof_under", c - X + ridge, c + X + ridge, c - Z + X + eave, c - Z - X + eave, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	b.quad("roof_under", c + X + ridge, c - X + ridge, c + Z - X + eave, c + Z + X + eave, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	# gable triangles (wall plane, no overhang)
	var Xw := basis * Vector3(w * 0.5, 0, 0)
	var Zw := basis * Vector3(0, 0, d * 0.5)
	var rw := Vector3(0, (d * 0.5) * tan(deg_to_rad(28.0)), 0)
	b.color = tint
	for sx: float in [-1.0, 1.0]:
		var a := c + Xw * sx - Zw * sx
		var e := c + Xw * sx + Zw * sx
		var t := c + Xw * sx + rw
		b.tri("gable", a, e, t, Vector2(0, 0), Vector2(d, 0), Vector2(d * 0.5, rw.y))
	_plain()


## Flat roof slab with a parapet over a (possibly rotated) rectangular footprint.
func _flat_roof(corners: Array[Vector3], top: float, basis: Basis) -> void:
	var c := (corners[0] + corners[2]) * 0.5
	var g := []
	for p: Vector3 in corners:
		var q := c + (p - c) * 1.03
		q.y = top
		g.append(q)
	b.quad("roof", g[3], g[2], g[1], g[0], Vector2(g[3].x, g[3].z), Vector2(g[2].x, g[2].z), Vector2(g[1].x, g[1].z), Vector2(g[0].x, g[0].z))
	for i in 4:
		b.wall("roof", g[(i + 1) % 4] - Vector3(0, 0.45, 0), g[i] - Vector3(0, 0.45, 0), 0.9)


# ------------------------------------------------------------------------------------------------ beach & lookout

## Wooden promenade between Ocean Drive's sidewalk and the sand, with lamps and benches facing the sea.
func _boardwalk(r: Rect2) -> void:
	_plain()
	var y := CURB_H + 0.05
	b.flat("deck", r.position.x, r.position.y, r.end.x, r.end.y, y)
	b.wall("deck", Vector3(r.position.x, y - 0.6, r.end.y), Vector3(r.position.x, y - 0.6, r.position.y), 0.6)
	_col(Vector3(r.get_center().x, y * 0.5 - 0.2, r.get_center().y), Vector3(r.size.x, y + 0.4, r.size.y))
	var z := r.position.y + 10.0
	while z < r.end.y - 5.0:
		if absf(z) > 12.0:
			var lp := Vector3(r.position.x + 0.6, y, z)
			_prop("street_lamp_01", lp, 0.0)
			lights.append(lp + Vector3(0, 3.55, 0))
			_prop("bench", Vector3(r.position.x + 2.2, y, z + 6.0), PI * 0.5)
			if rng.randf() < 0.5:
				_palm(Vector3(r.end.x - 1.0, y, z + 12.0))
		z += 24.0


## Long timber pier over the sea: ramp up from the boardwalk, deck on piles, railings, lamps, kiosks at the end.
func _pier(r: Rect2) -> void:
	_plain()
	var deck_y := 2.2
	var ramp := 40.0
	var x_land := r.end.x
	var x_sea := r.position.x
	var z0 := r.position.y
	var z1 := r.end.y
	var w := z1 - z0
	# ramp (from the boardwalk up to deck height)
	var a := Vector3(x_land, CURB_H + 0.05, z0)
	var b2 := Vector3(x_land - ramp, deck_y, z0)
	b.quad("deck", Vector3(x_land, CURB_H + 0.05, z1), a, b2, Vector3(x_land - ramp, deck_y, z1),
		Vector2(x_land, z1), Vector2(x_land, z0), Vector2(x_land - ramp, z0), Vector2(x_land - ramp, z1))
	var ang := atan2(deck_y - CURB_H, ramp)
	_col(Vector3(x_land - ramp * 0.5, (deck_y + CURB_H) * 0.5 - 0.15, (z0 + z1) * 0.5), Vector3(ramp / cos(ang), 0.3, w),
		Basis(Vector3(0, 0, 1), ang))
	# deck + edge boards
	b.flat("deck", x_sea, z0, x_land - ramp, z1, deck_y)
	b.wall("deck", Vector3(x_sea, deck_y - 0.5, z1), Vector3(x_land - ramp, deck_y - 0.5, z1), 0.5)
	b.wall("deck", Vector3(x_land - ramp, deck_y - 0.5, z0), Vector3(x_sea, deck_y - 0.5, z0), 0.5)
	_col(Vector3((x_sea + x_land - ramp) * 0.5, deck_y - 0.15, (z0 + z1) * 0.5), Vector3(x_land - ramp - x_sea, 0.3, w))
	# piles down to the seabed and railings along both edges
	var x := x_sea + 2.0
	while x < x_land - 4.0:
		var top := deck_y if x < x_land - ramp else lerpf(deck_y, CURB_H, (x - (x_land - ramp)) / ramp)
		var gy := _ground_y(x, z0)
		if gy < top - 0.6:
			for zz: float in [z0 + 0.6, z1 - 0.6, (z0 + z1) * 0.5]:
				b.box("piles", Vector3(x, (gy + top - 0.5) * 0.5, zz), Vector3(0.45, top - 0.5 - gy, 0.45))
		for zz: float in [z0 + 0.15, z1 - 0.15]:
			b.box("rail", Vector3(x, top + 0.55, zz), Vector3(0.12, 1.1, 0.12))
		x += 5.0
	for zz: float in [z0 + 0.15, z1 - 0.15]:
		b.box("rail", Vector3((x_sea + x_land - ramp) * 0.5, deck_y + 1.05, zz), Vector3(x_land - ramp - x_sea, 0.08, 0.1))
		_col(Vector3((x_sea + x_land - ramp) * 0.5, deck_y + 0.55, zz), Vector3(x_land - ramp - x_sea, 1.1, 0.2))
	# lamps, benches and a couple of kiosks out at the end
	var lx := x_sea + 8.0
	while lx < x_land - ramp - 4.0:
		for zz: float in [z0 + 0.7, z1 - 0.7]:
			var lp := Vector3(lx, deck_y, zz)
			_prop("street_lamp_01", lp, 0.0)
			lights.append(lp + Vector3(0, 3.55, 0))
		_prop("bench", Vector3(lx + 10.0, deck_y, z0 + 1.6), 0.0)
		lx += 26.0
	for k in 2:
		var kx := x_sea + 14.0 + k * 16.0
		_building(Rect2(kx, (z0 + z1) * 0.5 - 2.0 + (2.5 if k == 0 else -2.5), 7.0, 3.0), deck_y, 1, "plastered_wall_02",
			HOUSE_TINTS[(k * 3) % HOUSE_TINTS.size()], true, 0)


## Lifeguard tower on stilts on the sand.
func _lifeguard(r: Rect2) -> void:
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	c.y = _ground_y(c.x, c.z)
	_plain()
	b.color = Color(0.86, 0.9, 0.95)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box("canopy", c + Vector3(sx * 1.1, 1.2, sz * 1.1), Vector3(0.2, 2.6, 0.2))
	b.box("canopy", c + Vector3(0, 2.55, 0), Vector3(3.2, 0.15, 3.2), true)
	b.color = Color(0.45, 0.68, 0.86)
	b.box("canopy", c + Vector3(0, 3.65, 0), Vector3(2.6, 2.1, 2.4), true)
	b.color = Color(0.95, 0.95, 0.95)
	b.box("canopy", c + Vector3(0, 4.85, 0), Vector3(3.0, 0.2, 2.8), true)
	# ramp down to the sand on the land side
	b.color = Color(0.86, 0.9, 0.95)
	b.quad("canopy", c + Vector3(1.6, 2.6, -0.5), c + Vector3(1.6, 2.6, 0.5), c + Vector3(5.0, 0.0, 0.5), c + Vector3(5.0, 0.0, -0.5),
		Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	_plain()
	_col(c + Vector3(0, 3.4, 0), Vector3(3.2, 2.6, 3.2))
	_far_box(Rect2(c.x - 1.3, c.z - 1.2, 2.6, 2.4), c.y + 2.6, 2.3, Color(0.45, 0.68, 0.86), 0.0)


## Hilltop lookout: paved platform with a low wall, benches, coin telescopes and lamps.
func _lookout(r: Rect2) -> void:
	var c := r.get_center()
	var y := _ground_y(c.x, c.y) + 0.12
	_plain()
	b.flat("path", r.position.x, r.position.y, r.end.x, r.end.y, y)
	_col(Vector3(c.x, y - 0.5, c.y), Vector3(r.size.x, 1.0, r.size.y))
	for f: Array in [[Vector3(r.position.x, y - 1.0, r.end.y), Vector3(r.end.x, y - 1.0, r.end.y)], [Vector3(r.end.x, y - 1.0, r.end.y), Vector3(r.end.x, y - 1.0, r.position.y)],
			[Vector3(r.end.x, y - 1.0, r.position.y), Vector3(r.position.x, y - 1.0, r.position.y)], [Vector3(r.position.x, y - 1.0, r.position.y), Vector3(r.position.x, y - 1.0, r.end.y)]]:
		b.wall("barrier", f[0], f[1], 1.9)
		var mid: Vector3 = (f[0] + f[1]) * 0.5 + Vector3(0, 1.45, 0)
		var along: Vector3 = (f[1] - f[0])
		_col(mid, Vector3(along.length(), 0.9, 0.4), _along(Vector2(along.x, along.z)))
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var p := Vector3(c.x + cos(a) * 9.0, y, c.y + sin(a) * 9.0)
		_prop("bench", p, -a + PI * 0.5)
		var lp := Vector3(c.x + cos(a + 0.5) * 15.0, y, c.y + sin(a + 0.5) * 15.0)
		_prop("street_lamp_01", lp, 0.0)
		lights.append(lp + Vector3(0, 3.55, 0))
	for k in 3:
		var tp := Vector3(c.x - 6.0 + k * 6.0, y, r.end.y - 1.2)
		b.box("metal", tp + Vector3(0, 0.55, 0), Vector3(0.12, 1.1, 0.12))
		b.box("metal", tp + Vector3(0, 1.2, 0.1), Vector3(0.22, 0.22, 0.5))
