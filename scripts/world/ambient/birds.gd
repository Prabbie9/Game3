class_name Birds
extends Node3D
## Birds: gulls wheeling over the beaches, the pier and the port (gliding, now and then a few wing beats), and
## pigeons pecking about on the plaza, in the parks and on downtown pavements, which burst up and away when the
## player comes close or a gun goes off, circle for a while and settle again. Each flock is one MultiMesh of a
## small procedural bird whose wings beat in the vertex shader (phase, rate, amplitude and folding per bird in
## the instance custom data); only flocks near the camera are simulated.

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 body_color : source_color;
uniform vec3 wing_color : source_color;
uniform vec3 tip_color : source_color;
uniform vec3 head_color : source_color;
uniform vec3 beak_color : source_color;
varying vec3 col;
void vertex() {
	// COLOR.r: 0 on the body .. 1 at the wing tip; g: dark tip feathers; b: head / beak; a: flat part
	float w = COLOR.r;
	float flap = sin(TIME * INSTANCE_CUSTOM.y * 30.0 + INSTANCE_CUSTOM.x * 6.2832) * INSTANCE_CUSTOM.z;
	float ax = abs(VERTEX.x);
	if (w > 0.0) {
		float r = (ax - 0.03) * mix(1.0, 0.18, INSTANCE_CUSTOM.w);   // folded: tucked along the body
		float ang = flap * (0.4 + 0.6 * w) + 0.12 * (1.0 - INSTANCE_CUSTOM.w);
		VERTEX.x = sign(VERTEX.x) * (0.03 + r * cos(ang));
		VERTEX.y += r * sin(ang);
		VERTEX.z += INSTANCE_CUSTOM.w * w * 0.12;
	}
	col = w > 0.0 ? mix(wing_color, tip_color, COLOR.g) : (COLOR.b > 0.75 ? beak_color : (COLOR.b > 0.25 ? head_color : body_color));
}
void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.85;
	if (!FRONT_FACING && COLOR.a > 0.5) {   // flat parts (wings, tail) are lit on both sides
		NORMAL = -NORMAL;
	}
}
"""

## kind -> [body length, span, body colour, wing colour, tip colour, visible range, head colour, beak colour]
const KINDS := {
	"gull": [0.5, 1.25, Color(0.93, 0.93, 0.92), Color(0.72, 0.74, 0.77), Color(0.12, 0.12, 0.13), 600.0,
		Color(0.96, 0.96, 0.95), Color(0.95, 0.75, 0.2)],
	"pigeon": [0.34, 0.64, Color(0.52, 0.54, 0.6), Color(0.62, 0.64, 0.7), Color(0.22, 0.23, 0.27), 220.0,
		Color(0.33, 0.36, 0.42), Color(0.25, 0.22, 0.2)],
}
const SIM_RANGE := {"gull": 450.0, "pigeon": 160.0}
const SCARE := 6.5

var cost_ms := 0.0      # main-thread time of the last frame (perf overlay / stream_check)
var flocks: Array = []   # {kind, mmi, anchor, birds: [{pos, vel, yaw, state, t, home, ...}], active, grounded}
var _rng := RandomNumberGenerator.new()
var _scared: Array = []  # noise positions this frame
static var _meshes := {}
static var _shader: Shader


func _ready() -> void:
	_rng.seed = 4242
	var data := WorldData.get_data()
	# gulls over the water's edge: lifeguard towers, the pier, the boardwalk, the port
	var spots: Array[Vector3] = []
	for l: Dictionary in data.lots:
		if l.kind in ["lifeguard", "pier", "container_yard", "boardwalk"]:
			spots.append(Vector3((float(l.x0) + float(l.x1)) * 0.5, 0, (float(l.z0) + float(l.z1)) * 0.5))
	var used: Array[Vector3] = []
	for s in spots:
		if used.any(func(u): return u.distance_to(s) < 120.0):
			continue
		used.append(s)
		_add_flock("gull", s, _rng.randi_range(4, 7))
	# pigeons: the plaza, the parks, and pavements along downtown avenues
	for l: Dictionary in data.lots:
		if l.kind == "plaza":
			_add_flock("pigeon", Vector3(lerpf(l.x0, l.x1, 0.3), 0, lerpf(l.z0, l.z1, 0.75)), 9)
			_add_flock("pigeon", Vector3(lerpf(l.x0, l.x1, 0.2), 0, lerpf(l.z0, l.z1, 0.3)), 7)
		elif l.kind == "park":
			_add_flock("pigeon", Vector3(lerpf(l.x0, l.x1, 0.4), 0, lerpf(l.z0, l.z1, 0.6)), 8)
	var n := 0
	for r: Dictionary in data.roads:
		if n >= 8 or not r.walk or r.kind != "avenue":
			continue
		var pts: Array = r.pts
		var k := pts.size() / 2
		var a := Vector3(pts[k][0], 0, pts[k][2])
		var b := Vector3(pts[k + 1][0], 0, pts[k + 1][2]) if k + 1 < pts.size() else a + Vector3(1, 0, 0)
		if a.length() > 420.0 or a.distance_to(b) < 0.5:
			continue
		var side := (b - a).normalized().cross(Vector3.UP) * (1.0 if n % 2 == 0 else -1.0)
		_add_flock("pigeon", a + side * (float(r.w) * 0.5 + 2.3), 6)
		n += 1
	Game.noise_made.connect(func(pos: Vector3, radius: float, _src: Node): _scared.append([pos, radius]))


func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var k: Array = KINDS[kind]
	var L: float = k[0]
	var S: float = k[1] * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# COLOR: r = wing weight (0 body .. 1 tip), g = dark tip feathers, b = 0.5 head / 1 beak
	var vert := func(v: Vector3, n: Vector3, c: Color) -> void:
		st.set_color(c)
		st.set_normal(n)
		st.add_vertex(v)
	# rounded parts (body, head): ellipsoids with analytic normals
	var ellipsoid := func(c: Vector3, r: Vector3, col: Color, rings: int, segs: int) -> void:
		var pt := func(i: int, j: int) -> Array:
			var th := PI * float(i) / rings
			var ph := TAU * float(j) / segs
			var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			return [c + u * r, (u / r).normalized()]
		for i in rings:
			for j in segs:
				var a: Array = pt.call(i, j)
				var b: Array = pt.call(i + 1, j)
				var d: Array = pt.call(i + 1, j + 1)
				var e: Array = pt.call(i, j + 1)
				for q: Array in [a, d, b, a, e, d]:
					vert.call(q[0], q[1], col)
	var body := Color(0, 0, 0, 0)
	ellipsoid.call(Vector3(0, 0, L * 0.02), Vector3(L * 0.17, L * 0.17, L * 0.4), body, 6, 8)
	ellipsoid.call(Vector3(0, L * 0.15, -L * 0.4), Vector3(L * 0.11, L * 0.11, L * 0.12), Color(0, 0, 0.5, 0), 5, 8)
	# beak: a little pyramid off the front of the head
	var bt := Vector3(0, L * 0.13, -L * 0.62)
	var bb := [Vector3(-L * 0.03, L * 0.15, -L * 0.5), Vector3(L * 0.03, L * 0.15, -L * 0.5), Vector3(0, L * 0.11, -L * 0.5)]
	for i in 3:
		var a: Vector3 = bb[i]
		var b: Vector3 = bb[(i + 1) % 3]
		vert.call(bt, Vector3(0, 0, -1), Color(0, 0, 1, 0))
		vert.call(a, (a - Vector3(0, L * 0.14, -L * 0.5)).normalized(), Color(0, 0, 1, 0))
		vert.call(b, (b - Vector3(0, L * 0.14, -L * 0.5)).normalized(), Color(0, 0, 1, 0))
	# tail fan (flat; the shader lights both sides)
	var t0 := Vector3(0, L * 0.02, L * 0.3)
	for q: Array in [[t0, Vector3(-L * 0.13, 0, L * 0.68), Vector3(L * 0.13, 0, L * 0.68)]]:
		for v: Vector3 in q:
			vert.call(v, Vector3.UP, Color(0, 0, 0, 1))
	# wings: inner panel and swept tip panel each side
	for sx in [-1.0, 1.0]:
		var r0 := Vector3(sx * 0.03, L * 0.06, -L * 0.18)
		var r1 := Vector3(sx * 0.03, L * 0.06, L * 0.14)
		var m0 := Vector3(sx * S * 0.55, L * 0.05, -L * 0.14)
		var m1 := Vector3(sx * S * 0.55, L * 0.05, L * 0.18)
		var tp := Vector3(sx * S, L * 0.05, L * 0.24)
		for tri: Array in [[[r0, 0.01, 0.0], [m0, 0.55, 0.0], [m1, 0.55, 0.0]], [[r0, 0.01, 0.0], [m1, 0.55, 0.0], [r1, 0.01, 0.0]],
				[[m0, 0.55, 0.6], [tp, 1.0, 1.0], [m1, 0.75, 0.7]]]:
			for v: Array in tri:
				vert.call(v[0], Vector3.UP, Color(v[1], v[2], 0, 1))
	var m := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("body_color", k[2])
	mat.set_shader_parameter("wing_color", k[3])
	mat.set_shader_parameter("tip_color", k[4])
	mat.set_shader_parameter("head_color", k[6])
	mat.set_shader_parameter("beak_color", k[7])
	m.surface_set_material(0, mat)
	_meshes[kind] = m
	return m


func _add_flock(kind: String, anchor: Vector3, count: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh(kind)
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = float(KINDS[kind][5])
	mmi.visible = false
	add_child(mmi)
	var f := {"kind": kind, "mmi": mmi, "anchor": anchor, "birds": [], "active": false, "ground": -INF, "calm": 0.0}
	for i in count:
		var b := {"pos": anchor, "vel": Vector3.ZERO, "yaw": _rng.randf() * TAU, "state": "glide" if kind == "gull" else "ground",
			"t": _rng.randf() * 3.0, "phase": _rng.randf(), "ang": _rng.randf() * TAU, "rad": _rng.randf_range(10.0, 26.0),
			"alt": _rng.randf_range(12.0, 26.0), "dir": 1.0 if _rng.randf() < 0.75 else -1.0, "flap": 0.0, "fold": 0.0,
			"home": anchor + Vector3(_rng.randf_range(-3.0, 3.0), 0, _rng.randf_range(-3.0, 3.0)), "peck": 0.0}
		f.birds.append(b)
	flocks.append(f)


## The nearest gull flock's centre (for their cries), or Vector3.INF.
func nearest_gulls(pos: Vector3, within: float) -> Vector3:
	var best := Vector3.INF
	var bd := within
	for f: Dictionary in flocks:
		if f.kind == "gull" and f.active:
			var c: Vector3 = (f.birds[0] as Dictionary).pos
			var d := c.distance_to(pos)
			if d < bd:
				bd = d
				best = c
	return best


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_update(delta)
	cost_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _update(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var p := Game.player as Node3D
	var threat := p.global_position if p else Vector3.INF
	var city := (Game.world as World).city if Game.world else null
	for f: Dictionary in flocks:
		var a: Vector3 = f.anchor
		var near := Vector2(a.x - eye.x, a.z - eye.z).length() < float(SIM_RANGE[f.kind])
		if near != f.active:
			f.active = near
			(f.mmi as Node3D).visible = near
		if not near:
			continue
		if f.ground == -INF:
			var gy := city.ground_y(a.x, a.z) if city else NAN
			if is_nan(gy):
				continue
			f.ground = gy
			for b: Dictionary in f.birds:
				b.home.y = f.ground
				b.pos = b.home if f.kind == "pigeon" else a + Vector3(0, f.ground + b.alt, 0)
		if f.kind == "gull":
			_gulls(f, delta)
		else:
			_pigeons(f, delta, threat)
		var mm: MultiMesh = (f.mmi as MultiMeshInstance3D).multimesh
		for i in f.birds.size():
			var b: Dictionary = f.birds[i]
			var v: Vector3 = b.vel
			var bank: float = b.get("bank", 0.0)
			var pitch: float = clampf(-v.y * 0.08, -0.6, 0.6) if b.state != "ground" else -float(b.peck) * 0.7
			var basis := Basis.from_euler(Vector3(pitch, b.yaw, bank), EULER_ORDER_YXZ)
			mm.set_instance_transform(i, Transform3D(basis, b.pos))
			mm.set_instance_custom_data(i, Color(b.phase, b.rate if b.has("rate") else 0.4, b.flap, b.fold))
	_scared.clear()


func _gulls(f: Dictionary, delta: float) -> void:
	var a: Vector3 = f.anchor
	f.calm += delta
	# the circling centre drifts slowly around the anchor
	var c := a + Vector3(sin(f.calm * 0.03) * 25.0, f.ground, cos(f.calm * 0.021) * 25.0)
	for b: Dictionary in f.birds:
		var speed := 7.5
		b.ang = fmod(b.ang + b.dir * speed / b.rad * delta, TAU)
		var target := c + Vector3(cos(b.ang) * b.rad, b.alt + sin(f.calm * 0.4 + b.phase * 6.0) * 2.0, sin(b.ang) * b.rad)
		var v: Vector3 = (target - b.pos) / maxf(delta, 0.001)
		v = v.limit_length(12.0)
		b.vel = (b.vel as Vector3).lerp(v, minf(1.0, delta * 2.0))
		b.pos += b.vel * delta
		var hv := Vector2(b.vel.x, b.vel.z)
		if hv.length() > 0.5:
			b.yaw = lerp_angle(b.yaw, atan2(-hv.x, -hv.y), minf(1.0, delta * 4.0))
		b.bank = -b.dir * 0.35
		# mostly gliding; now and then a few slow wing beats
		b.t -= delta
		if b.t <= 0.0:
			b.flapping = not b.get("flapping", false)
			b.t = _rng.randf_range(1.0, 2.5) if b.flapping else _rng.randf_range(3.0, 9.0)
		b.flap = lerpf(b.flap, 0.75 if b.get("flapping", false) else 0.06, minf(1.0, delta * 3.0))
		b.rate = 0.3
		b.fold = 0.0


func _pigeons(f: Dictionary, delta: float, threat: Vector3) -> void:
	var a: Vector3 = f.anchor
	var scare := false
	if threat != Vector3.INF:
		for b: Dictionary in f.birds:
			if b.state == "ground" and (b.pos as Vector3).distance_to(threat) < SCARE:
				scare = true
				break
	for s: Array in _scared:
		if (s[0] as Vector3).distance_to(a) < maxf(float(s[1]), 25.0):
			scare = true
	var player_near := threat != Vector3.INF and Vector2(threat.x - a.x, threat.z - a.z).length() < 12.0
	if scare:
		f.calm = _rng.randf_range(15.0, 25.0)
		var flew := false
		for b: Dictionary in f.birds:
			if b.state == "ground" or b.state == "land":
				var away: Vector3 = (b.pos - threat) if threat != Vector3.INF else Vector3(_rng.randf() - 0.5, 0, _rng.randf() - 0.5)
				away.y = 0.0
				away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
				b.vel = away * _rng.randf_range(4.0, 7.0) + Vector3(0, _rng.randf_range(4.5, 6.5), 0)
				b.state = "flee"
				b.t = _rng.randf_range(1.5, 2.5)
				flew = true
		if flew:
			Audio.play_at(Audio.stream("ambience/flutter.ogg"), a + Vector3(0, f.ground + 0.5, 0), -4.0, _rng.randf_range(0.9, 1.1), &"Ambience", 60.0)
	else:
		f.calm -= delta
	var lift := a + Vector3(0, f.ground, 0)
	for b: Dictionary in f.birds:
		match b.state:
			"ground":
				b.flap = 0.0
				b.fold = 1.0
				b.vel = Vector3.ZERO
				b.bank = 0.0
				b.t -= delta
				b.peck = maxf(0.0, b.peck - delta * 4.0)
				if b.t <= 0.0:
					b.t = _rng.randf_range(0.4, 2.0)
					if _rng.randf() < 0.5:
						b.peck = 1.0
					else:   # a little hop
						var step := Vector3(_rng.randf_range(-0.35, 0.35), 0, _rng.randf_range(-0.35, 0.35))
						var np: Vector3 = b.pos + step
						if Vector2(np.x - b.home.x, np.z - b.home.z).length() < 2.5:
							b.pos = np
							b.yaw = atan2(-step.x, -step.z)
			"flee":
				b.flap = 0.9
				b.fold = 0.0
				b.rate = 0.6
				b.vel = (b.vel as Vector3).lerp(Vector3(b.vel.x, 3.0, b.vel.z), delta)
				b.pos += b.vel * delta
				b.yaw = atan2(-b.vel.x, -b.vel.z)
				b.t -= delta
				if b.t <= 0.0:
					b.state = "circle"
					b.ang = atan2(b.pos.z - a.z, b.pos.x - a.x)
					b.rad = _rng.randf_range(8.0, 16.0)
					b.alt = _rng.randf_range(9.0, 15.0)
			"circle":
				b.ang = fmod(b.ang + 9.0 / b.rad * delta, TAU)
				var target := lift + Vector3(cos(b.ang) * b.rad, b.alt, sin(b.ang) * b.rad)
				b.vel = (b.vel as Vector3).lerp(((target - b.pos) * 2.0).limit_length(10.0), minf(1.0, delta * 2.0))
				b.pos += b.vel * delta
				b.yaw = lerp_angle(b.yaw, atan2(-b.vel.x, -b.vel.z), minf(1.0, delta * 5.0))
				b.bank = -0.4
				b.flap = 0.55
				b.rate = 0.5
				if f.calm <= 0.0 and not player_near:
					b.state = "land"
			"land":
				var to: Vector3 = b.home - b.pos
				b.vel = (b.vel as Vector3).lerp(to.limit_length(5.0), minf(1.0, delta * 2.0))
				b.pos += b.vel * delta
				if Vector2(b.vel.x, b.vel.z).length() > 0.3:
					b.yaw = lerp_angle(b.yaw, atan2(-b.vel.x, -b.vel.z), minf(1.0, delta * 5.0))
				b.bank = 0.0
				b.flap = 0.7 if to.length() > 1.0 else 0.9
				b.rate = 0.6
				if to.length() < 0.15:
					b.pos = b.home
					b.state = "ground"
					b.t = _rng.randf_range(0.5, 2.0)
				elif player_near:
					b.state = "circle"
