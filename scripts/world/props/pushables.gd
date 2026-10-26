class_name Pushables
extends Node3D
## Loose things lying about that you can push, kick, shoot and drive through: wooden crates, oil drums and
## cardboard boxes in the industrial yards and the port, traffic cones at the quay cranes and in car parks,
## footballs in the parks, on the beach and in front yards. Each is a real physics body, made when the player comes
## within SPAWN_R of it and put away beyond DESPAWN_R; where it was left is remembered (a crate shoved across the
## yard is still there when you come back).

const SPAWN_R := 90.0
const DESPAWN_R := 130.0
const GRID := 64.0
const LAYER := 32            # debris: people walk through-and-shove them, cars hit them
const PER_TICK := 10

## kind -> model (Poly Haven, assets/models/polyhaven), mesh part filter, scale, mass, collision, sound
const KINDS := {
	"crate": {"model": "wooden_crate_02", "mass": 22.0, "shape": "box", "sound": "world/crate_%d.ogg"},
	"plastic_crate": {"model": "plastic_crate_01", "scale": 1.3, "mass": 1.5, "shape": "box", "sound": "world/cone_%d.ogg", "tris": 1500},
	"box": {"model": "cardboard_box_01", "mass": 2.5, "shape": "box", "sound": "world/cone_%d.ogg", "tris": 1200},
	"drum": {"model": "barrel_03", "mass": 28.0, "shape": "cyl", "sound": "world/drum_%d.ogg"},
	"ball": {"model": "football", "part": "football_inflated", "mass": 0.43, "shape": "sphere", "bounce": 0.65, "sound": "world/cone_%d.ogg"},
	"cone": {"mass": 3.0, "shape": "cone", "sound": "world/cone_%d.ogg"},
}
## cluster -> members [kind, offset (bottom centre, cluster space), yaw]
const CLUSTERS := {
	"drums": [["drum", Vector3(0, 0, 0), 0.0], ["drum", Vector3(0.68, 0, 0.12), 1.0], ["drum", Vector3(0.3, 0, 0.66), 2.0]],
	"crates": [["crate", Vector3(0, 0, 0), 0.0], ["crate", Vector3(0.62, 0, 0.04), 0.05], ["crate", Vector3(0.3, 0.46, 0.0), -0.08]],
	"boxes": [["box", Vector3(0, 0, 0), 0.1], ["box", Vector3(0.5, 0, 0.1), -0.2], ["box", Vector3(0.2, 0.35, 0.05), 0.4],
		["plastic_crate", Vector3(-0.7, 0, 0.3), 0.0], ["plastic_crate", Vector3(-0.7, 0.35, 0.3), 0.1]],
	"cones": [["cone", Vector3(0, 0, 0), 0.0], ["cone", Vector3(1.4, 0, 0), 0.0], ["cone", Vector3(2.8, 0, 0), 0.0], ["cone", Vector3(4.2, 0, 0), 0.0]],
	"ball": [["ball", Vector3.ZERO, 0.0]],
}

var spots: Array = []      # [{pos, yaw, cluster, bodies: Array, saved: Array (transforms or empty), retry: float}]
var cost_ms := 0.0
var _grid := {}            # Vector2i -> PackedInt32Array of spot ids
var _live := {}            # spot id -> true
var _t := 0.0
var _clock := 0.0
var _push_q: PhysicsShapeQueryParameters3D
static var _defs := {}     # kind -> {mesh, size, shape: Shape3D, com}


func _ready() -> void:
	_plan()


static func release() -> void:
	_defs.clear()


# --- where things lie -----------------------------------------------------------------------------------

func _plan() -> void:
	var data := WorldData.get_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for l: Dictionary in data.lots:
		var r := Rect2(float(l.x0), float(l.z0), float(l.x1) - float(l.x0), float(l.z1) - float(l.z0))
		match String(l.kind):
			"industrial":
				for k in 2:
					_add(Vector3(rng.randf_range(r.position.x + 3.0, r.end.x - 4.0), 0, r.end.y - rng.randf_range(3.0, 9.0)),
						rng.randf() * TAU, ["drums", "crates", "boxes"][rng.randi() % 3])
			"port_sheds", "container_yard":
				for k in 3:
					var z := r.end.y - 3.0 if rng.randf() < 0.5 else r.position.y + 3.0
					_add(Vector3(rng.randf_range(r.position.x + 4.0, r.end.x - 4.0), 0, z), rng.randf() * TAU, ["drums", "crates"][rng.randi() % 2])
			"crane":
				var c := r.get_center()
				_add(Vector3(c.x - 2.1, 0, c.y - 4.0), 0.0, "cones")
			"parking":
				if rng.randf() < 0.4:
					_add(Vector3(rng.randf_range(r.position.x + 4.0, r.end.x - 8.0), 0, r.position.y + 8.0), 0.0, "cones")
			"park", "plaza":
				_add(Vector3(lerpf(r.position.x, r.end.x, rng.randf_range(0.3, 0.7)), 0, lerpf(r.position.y, r.end.y, rng.randf_range(0.3, 0.7))), 0.0, "ball")
			"lifeguard":
				_add(Vector3(r.get_center().x + 4.0, 0, r.get_center().y + rng.randf_range(-3.0, 3.0)), 0.0, "ball")
			"house":
				if rng.randf() < 0.25:
					var b := Basis(Vector3.UP, float(l.get("yaw", 0.0)))
					var c := r.get_center()
					_add(Vector3(c.x, 0, c.y) + b * Vector3(rng.randf_range(-6.0, 6.0), 0, -6.2), 0.0, "ball")


func _add(pos: Vector3, yaw: float, cluster: String) -> void:
	var id := spots.size()
	spots.append({"pos": pos, "yaw": yaw, "cluster": cluster, "bodies": [], "saved": [], "retry": 0.0})
	var k := Vector2i(floori(pos.x / GRID), floori(pos.z / GRID))
	if not _grid.has(k):
		_grid[k] = PackedInt32Array()
	_grid[k].append(id)


# --- streaming ------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_shove()
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var t0 := Time.get_ticks_usec()
	_update()
	cost_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Walking into something moves it along at your pace (the player's capsule passes through the debris layer, so
## contact is found here and the thing is given the walker's speed along the line between them).
func _shove() -> void:
	var p := Game.player as Player
	if p == null or p.vehicle != null or _live.is_empty():
		return
	var hv := Vector3(p.velocity.x, 0, p.velocity.z)
	if hv.length() < 0.4:
		return
	if _push_q == null:
		_push_q = PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.45
		cap.height = 1.7
		_push_q.shape = cap
		_push_q.collision_mask = LAYER
	_push_q.transform = Transform3D(Basis(), p.global_position + Vector3(0, 0.85, 0) + hv.normalized() * 0.1)
	for r: Dictionary in get_world_3d().direct_space_state.intersect_shape(_push_q, 6):
		var rb := r.collider as Pushable
		if rb == null:
			continue
		var n := rb.global_position - p.global_position
		n.y = 0.0
		if n.length() < 0.01:
			continue
		n = n.normalized()
		var along := hv.dot(n)
		if along < 0.2:
			continue
		# a ball is dribbled ahead; boxes and drums are pushed at walking pace
		var want := along * (1.35 if rb.kind == "ball" else 1.0)
		var dv := want - rb.linear_velocity.dot(n)
		if dv > 0.0:
			rb.sleeping = false
			rb.apply_impulse(n * dv * rb.mass, Vector3(0, 0.1, 0))


func _focus() -> Vector3:
	var p := Game.player as Player
	if p == null:
		return Vector3.INF
	return p.vehicle.global_position if p.vehicle and is_instance_valid(p.vehicle) else p.global_position


func _update() -> void:
	var w := Game.world as World
	var focus := _focus()
	if w == null or w.city == null or focus == Vector3.INF:
		return
	# put away what is far behind
	for id: int in _live.keys():
		var s: Dictionary = spots[id]
		var home: Vector3 = s.pos
		if Vector2(home.x - focus.x, home.z - focus.z).length() > DESPAWN_R:
			_put_away(id)
	# bring out what is near
	var made := 0
	var ck := Vector2i(floori(focus.x / GRID), floori(focus.z / GRID))
	var reach := ceili(SPAWN_R / GRID)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var ids: PackedInt32Array = _grid.get(ck + Vector2i(dx, dz), PackedInt32Array())
			for id in ids:
				if made >= PER_TICK:
					return
				if _live.has(id):
					continue
				var s: Dictionary = spots[id]
				var home: Vector3 = s.pos
				if Vector2(home.x - focus.x, home.z - focus.z).length() > SPAWN_R or _clock < float(s.retry):
					continue
				if _bring_out(id, w.city):
					made += 1


## Makes a spot's bodies: where they were left, or the cluster set out on open ground near its spot.
func _bring_out(id: int, city: City) -> bool:
	var s: Dictionary = spots[id]
	var members: Array = CLUSTERS[s.cluster]
	var xfs: Array = s.saved
	if xfs.is_empty():
		xfs = _set_out(s, members, city)
		if xfs.is_empty():
			return false
	var bodies := []
	for i in members.size():
		bodies.append(_make(String(members[i][0]), xfs[i]))
	s.bodies = bodies
	_live[id] = true
	return true


## Transforms for a cluster at its spot, moved round the spot until nothing (walls, cars, props) is in the way.
## Empty when the ground isn't loaded yet or there is no room (tried again later).
func _set_out(s: Dictionary, members: Array, city: City) -> Array:
	var space := get_world_3d().direct_space_state
	var data := WorldData.get_data()
	var basis := Basis(Vector3.UP, float(s.yaw))
	var home: Vector3 = s.pos
	for r: float in [0.0, 1.5, 3.0, 4.5]:
		for k in (1 if r == 0.0 else 8):
			var base := home + Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * r
			var gy := city.ground_y(base.x, base.z)
			if is_nan(gy):
				s.retry = _clock + 1.0
				return []
			if gy < data.sea + 0.15:
				continue
			var xfs := []
			var clear := true
			for m: Array in members:
				var def := _def(String(m[0]))
				var off: Vector3 = basis * (m[1] as Vector3)
				var at := Vector3(base.x + off.x, 0, base.z + off.z)
				var y := (city.ground_y(at.x, at.z) if off.y == 0.0 else gy) + off.y + (def.size as Vector3).y * 0.5 + 0.01
				if is_nan(y):
					s.retry = _clock + 1.0
					return []
				var xf := Transform3D(basis * Basis(Vector3.UP, float(m[2])), Vector3(at.x, y, at.z))
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = def.shape
				q.transform = xf * Transform3D(Basis(), def.shape_at)
				q.collision_mask = 1 | 8 | 16 | LAYER
				q.margin = -0.02
				if not space.intersect_shape(q, 1).is_empty():
					clear = false
					break
				xfs.append(xf)
			if clear:
				return xfs
	s.retry = _clock + 6.0
	return []


func _put_away(id: int) -> void:
	var s: Dictionary = spots[id]
	var saved := []
	var moved := false
	var members: Array = CLUSTERS[s.cluster]
	for i in (s.bodies as Array).size():
		var rb: RigidBody3D = s.bodies[i]
		if not is_instance_valid(rb):
			saved = []
			moved = false
			break
		saved.append(rb.global_transform)
		if not rb.has_meta("home") or (rb.get_meta("home") as Transform3D).origin.distance_to(rb.global_position) > 0.3:
			moved = true
		rb.queue_free()
	# lost in the sea or under the map: back where it belongs next time
	var data := WorldData.get_data()
	for xf: Transform3D in saved:
		if xf.origin.y < data.sea - 0.5 or xf.origin.y < -20.0:
			moved = false
			break
	s.saved = saved if moved and saved.size() == members.size() else []
	s.bodies = []
	_live.erase(id)


# --- the things themselves ------------------------------------------------------------------------------

func _make(kind: String, xf: Transform3D) -> RigidBody3D:
	var def := _def(kind)
	var spec: Dictionary = KINDS[kind]
	var rb := Pushable.new()
	rb.kind = kind
	rb.sound = String(spec.sound)
	rb.collision_layer = LAYER
	rb.collision_mask = 1 | 2 | 4 | 8 | 16 | LAYER
	rb.mass = float(spec.mass)
	rb.set_meta("surface", FX.Surface.WOOD if kind in ["crate", "box"] else (FX.Surface.METAL if kind == "drum" else FX.Surface.CONCRETE))
	var pm := PhysicsMaterial.new()
	pm.friction = 0.55
	pm.bounce = float(spec.get("bounce", 0.05))
	rb.physics_material_override = pm
	if spec.has("bounce"):
		rb.angular_damp = 0.6
		rb.linear_damp = 0.15
	var mi := MeshInstance3D.new()
	mi.mesh = def.mesh
	mi.visibility_range_end = 110.0
	if kind in ["ball", "cone", "plastic_crate"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = def.shape
	cs.position = def.shape_at
	rb.add_child(cs)
	if def.has("base"):
		var cb := CollisionShape3D.new()
		cb.shape = def.base
		cb.position = def.base_at
		rb.add_child(cb)
	if def.has("com"):
		rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		rb.center_of_mass = def.com
	add_child(rb)
	rb.global_transform = xf
	rb.set_meta("home", xf)
	rb.sleeping = true
	return rb


## Mesh (centred on its bounds) and collision for a kind, built once.
static func _def(kind: String) -> Dictionary:
	if _defs.has(kind):
		return _defs[kind]
	var spec: Dictionary = KINDS[kind]
	var d := {}
	if kind == "cone":
		d = _cone()
	else:
		var name: String = spec.model
		var root: Node = (load(PropCatalog.PH % [name, name]) as PackedScene).instantiate()
		var by_mat := {}
		var aabb := AABB()
		var first := true
		var parts := []
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if spec.has("part") and String(mi.name) != String(spec.part):
				continue
			var xf := PropCatalog._xf_to_root(mi, root)
			parts.append([mi, xf])
			var b: AABB = xf * mi.mesh.get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
		var k := float(spec.get("scale", 1.0))
		var norm := Transform3D(Basis.from_scale(Vector3.ONE * k), -aabb.get_center() * k)
		for part: Array in parts:
			var mi: MeshInstance3D = part[0]
			for si in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(si)
				if not by_mat.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					by_mat[mat] = st
				(by_mat[mat] as SurfaceTool).append_from(mi.mesh, si, norm * (part[1] as Transform3D))
		root.free()
		var am := ArrayMesh.new()
		for mat: Material in by_mat:
			(by_mat[mat] as SurfaceTool).commit(am)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		if spec.has("tris"):
			am = PropCatalog._reduced(am, int(spec.tris))
		var size := aabb.size * k
		d = {"mesh": am, "size": size, "shape_at": Vector3.ZERO}
		match String(spec.shape):
			"box":
				var bs := BoxShape3D.new()
				bs.size = size
				d.shape = bs
			"cyl":
				var cy := CylinderShape3D.new()
				cy.radius = maxf(size.x, size.z) * 0.5
				cy.height = size.y
				d.shape = cy
			"sphere":
				var sp := SphereShape3D.new()
				sp.radius = maxf(size.x, maxf(size.y, size.z)) * 0.5
				d.shape = sp
	_defs[kind] = d
	return d


## A traffic cone: orange body with a white reflective band on a black square base (centred on its bounds,
## weighted low so it rocks back up unless knocked flat).
static func _cone() -> Dictionary:
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(1.0, 0.36, 0.06)
	orange.roughness = 0.55
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)
	white.roughness = 0.3
	white.metallic = 0.2
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.06, 0.06, 0.06)
	black.roughness = 0.8
	var h := 0.66
	var base_h := 0.035
	var y0 := -(h + base_h) * 0.5   # bottom
	var body := CylinderMesh.new()
	body.top_radius = 0.025
	body.bottom_radius = 0.15
	body.height = h - 0.02
	body.radial_segments = 16
	body.rings = 1
	var band := CylinderMesh.new()
	band.top_radius = 0.025 + (0.15 - 0.025) * 0.38 + 0.004
	band.bottom_radius = 0.025 + (0.15 - 0.025) * 0.58 + 0.004
	band.height = 0.13
	band.radial_segments = 16
	band.rings = 1
	band.cap_top = false
	band.cap_bottom = false
	var base := BoxMesh.new()
	base.size = Vector3(0.36, base_h, 0.36)
	var am := ArrayMesh.new()
	for part: Array in [[body, orange, Vector3(0, y0 + base_h + (h - 0.02) * 0.5, 0)],
			[band, white, Vector3(0, y0 + base_h + (h - 0.02) * 0.52, 0)],
			[base, black, Vector3(0, y0 + base_h * 0.5, 0)]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(part[0], 0, Transform3D(Basis(), part[2]))
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, part[1])
	var cy := CylinderShape3D.new()
	cy.radius = 0.1
	cy.height = h - 0.04
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.36, base_h, 0.36)
	return {"mesh": am, "size": Vector3(0.36, h + base_h, 0.36), "shape": cy, "shape_at": Vector3(0, y0 + base_h + (h - 0.04) * 0.5, 0),
		"base": bs, "base_at": Vector3(0, y0 + base_h * 0.5, 0), "com": Vector3(0, y0 + 0.12, 0)}
