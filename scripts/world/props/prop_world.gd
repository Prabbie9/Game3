class_name PropWorld
extends Node3D
## Street furniture comes alive around the player. The city draws props as MultiMesh instances with merged static
## collision (City._add_props tags every collision shape with its prop and instance); here single instances are
## broken out into physics debris when a vehicle drives into them, a bullet or a blast hits them, or the player
## kicks them: lamp posts topple (their light goes out), bins tumble, hydrants burst into a water jet, a smashed
## ATM spills cash. Vending machines, ATMs, payphones and benches near the player get a "use" proxy
## (PropUse). A broken prop comes back when its city cell is rebuilt.

## name -> mass (kg), vehicle speed (m/s) that breaks it, sound, extra behaviour
const BREAKABLE := {
	"street_lamp_01": {"mass": 90.0, "speed": 6.0, "sound": "world/metal_fall_%d.ogg", "n": 2, "lamp": true},
	"fire_hydrant": {"mass": 40.0, "speed": 4.0, "sound": "world/metal_hit_%d.ogg", "n": 2, "hydrant": true},
	"fire_hydrant_aged": {"mass": 40.0, "speed": 4.0, "sound": "world/metal_hit_%d.ogg", "n": 2, "hydrant": true},
	"metal_trash_can": {"mass": 12.0, "speed": 1.0, "sound": "world/bin_%d.ogg", "n": 3, "bullets": true},
	"metal_trash_can_rust": {"mass": 12.0, "speed": 1.0, "sound": "world/bin_%d.ogg", "n": 3, "bullets": true},
	"vending_machine": {"mass": 260.0, "speed": 9.0, "sound": "world/metal_hit_%d.ogg", "n": 2},
	"payphone": {"mass": 70.0, "speed": 6.0, "sound": "world/metal_hit_%d.ogg", "n": 2},
	"atm": {"mass": 300.0, "speed": 11.0, "sound": "world/metal_hit_%d.ogg", "n": 2, "atm": true},
	"utility_box_01": {"mass": 120.0, "speed": 10.0, "sound": "world/metal_hit_%d.ogg", "n": 2},
	"utility_box_02": {"mass": 120.0, "speed": 10.0, "sound": "world/metal_hit_%d.ogg", "n": 2},
}
const USABLE := ["vending_machine", "atm", "payphone", "bench"]
const MAX_DEBRIS := 40
const DEBRIS_LAYER := 32

var _debris: Array[RigidBody3D] = []
var _uses := {}          # "mmi id:instance" -> PropUse
var _scan_t := 0.0
var _atm_hits := {}      # "mmi id:instance" -> bullet hits taken
var _last_pv := Vector2.ZERO


func _ready() -> void:
	Game.set_meta("props", self)


func _exit_tree() -> void:
	if Game.get_meta("props", null) == self:
		Game.remove_meta("props")


static func get_props() -> PropWorld:
	return Game.get_meta("props", null) as PropWorld


func _physics_process(delta: float) -> void:
	var p := Game.player as Player
	if p == null:
		return
	var focus := p.vehicle.global_position if p.vehicle else p.global_position
	_vehicle_hits(focus, delta)
	_player_kicks(p)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.4
		_update_uses(focus)
		_tidy_debris(focus)


# --- breaking ---------------------------------------------------------------------

## The prop behind a collision shape hit (a city prop body and shape index): [name, mmi, instance, CollisionShape3D].
func _prop_at(body: Object, shape: int) -> Array:
	var sb := body as StaticBody3D
	if sb == null or not sb.has_meta("prop"):
		return []
	var owner_id := sb.shape_find_owner(shape)
	if owner_id < 0:
		return []
	var cs := sb.shape_owner_get_owner(owner_id) as CollisionShape3D
	if cs == null or not cs.has_meta("inst") or cs.disabled:
		return []
	return [String(sb.get_meta("prop")), sb.get_meta("mmi"), int(cs.get_meta("inst")), cs]


## Swap the instance for a physics body pushed by `impulse` at `at`. Returns the body (or null).
func break_prop(body: Object, shape: int, impulse: Vector3, at: Vector3) -> RigidBody3D:
	var pr := _prop_at(body, shape)
	if pr.is_empty() or not BREAKABLE.has(pr[0]):
		return null
	var name: String = pr[0]
	var mmi := pr[1] as MultiMeshInstance3D
	var inst: int = pr[2]
	var cs: CollisionShape3D = pr[3]
	if not is_instance_valid(mmi):
		return null
	var lxf: Transform3D = (mmi.get_meta("xfs") as Array)[inst]
	var xf := mmi.global_transform * lxf
	mmi.multimesh.set_instance_transform(inst, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), lxf.origin))
	var broken: Dictionary = mmi.get_meta("broken", {})
	broken[inst] = true
	mmi.set_meta("broken", broken)
	cs.set_deferred("disabled", true)
	var def: Dictionary = BREAKABLE[name]
	var rb := RigidBody3D.new()
	rb.collision_layer = DEBRIS_LAYER
	rb.collision_mask = 1 | 2 | 4 | 8 | 16 | DEBRIS_LAYER
	rb.mass = float(def.mass)
	rb.set_meta("surface", FX.Surface.METAL)
	var mi := MeshInstance3D.new()
	mi.mesh = PropCatalog.mesh(name)
	mi.scale = xf.basis.get_scale()
	rb.add_child(mi)
	var col := PropCatalog.collision(name, xf.basis.get_scale().x)
	if not col.is_empty():
		var c2 := CollisionShape3D.new()
		c2.shape = col[0]
		c2.position = col[1]
		rb.add_child(c2)
		rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		rb.center_of_mass = col[1] * (0.6 if def.get("lamp", false) else 1.0)
	add_child(rb)
	rb.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3(0, 0.02, 0))
	rb.apply_impulse(impulse, at - rb.global_position)
	_debris.append(rb)
	Audio.play_at(Audio.pick(String(def.sound), int(def.n)), at, -2.0, randf_range(0.9, 1.1))
	if def.get("lamp", false):
		_lamp_out(mmi, xf.origin)
	if def.get("hydrant", false):
		var jet := HydrantJet.new()
		add_child(jet)
		jet.global_position = xf.origin
	if def.get("atm", false):
		_spill_cash(xf.origin + xf.basis.z.normalized() * 0.8)
	return rb


func _lamp_out(mmi: Node, base: Vector3) -> void:
	var cell := mmi.get_parent()
	if cell == null or not cell.has_meta("lights"):
		return
	var lights: Array = cell.get_meta("lights")
	for i in lights.size():
		var lp: Vector3 = lights[i]
		if Vector2(lp.x - base.x, lp.z - base.z).length() < 0.8:
			lights.remove_at(i)
			break
	cell.set_meta("lights", lights)
	var w := Game.world as World
	if w and w.city:
		w.city._lights_dirty = true


func _spill_cash(at: Vector3) -> void:
	for i in randi_range(2, 4):
		var c := Pickup.make(Pickup.Kind.CASH, "", randi_range(40, 120))
		get_parent().add_child(c)
		c.global_position = at + Vector3(randf_range(-0.9, 0.9), 0.6, randf_range(-0.9, 0.9))
	Game.crime("theft", at)
	Game.noise(at, 25.0, Game.player)


## Vehicles plough through props: look a little ahead of each moving vehicle near the player.
func _vehicle_hits(focus: Vector3, delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for n: Node in get_tree().get_nodes_in_group("vehicles"):
		var v := n as Vehicle
		if v == null or v.freeze or v is Bike:
			continue
		var vel := v.linear_velocity
		var speed := vel.length()
		if speed < 1.0 or v.global_position.distance_to(focus) > 140.0:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = v._bounds.size * Vector3(1.02, 0.9, 1.02)
		q.shape = box
		q.transform = Transform3D(v.global_basis, v.global_transform * v._bounds.get_center() + vel * delta * 2.0)
		q.collision_mask = 16
		for r: Dictionary in space.intersect_shape(q, 6):
			var pr := _prop_at(r.collider, int(r.shape))
			if pr.is_empty() or not BREAKABLE.has(pr[0]):
				continue
			var def: Dictionary = BREAKABLE[pr[0]]
			if speed < float(def.speed):
				continue
			var m := float(def.mass)
			var rb := break_prop(r.collider, int(r.shape), vel * m * 0.9 + Vector3(0, m * 2.0, 0), (pr[3] as CollisionShape3D).global_position + Vector3(0, 0.6, 0))
			if rb:
				# the car loses a little speed (more for heavy things)
				v.linear_velocity = vel * clampf(1.0 - m / (v.mass * 2.5), 0.6, 0.98)


## On foot, walking or running into a bin knocks it over.
func _player_kicks(p: Player) -> void:
	# the velocity from before this frame's collision (running into something stops the body dead)
	var hv := _last_pv
	_last_pv = Vector2(p.velocity.x, p.velocity.z)
	if p.vehicle or p.state != Player.State.ON_FOOT:
		return
	if hv.length() < 1.2:
		return
	for i in p.get_slide_collision_count():
		var c := p.get_slide_collision(i)
		var pr := _prop_at(c.get_collider(), c.get_collider_shape_index())
		if pr.is_empty() or not BREAKABLE.has(pr[0]) or float(BREAKABLE[pr[0]].mass) > 20.0:
			continue
		var push := Vector3(hv.x, 1.5, hv.y) * 6.0
		break_prop(c.get_collider(), c.get_collider_shape_index(), push, c.get_position())
		return
	# shove debris bins along
	for i in p.get_slide_collision_count():
		var rb := p.get_slide_collision(i).get_collider() as RigidBody3D
		if rb and rb.get_collision_layer_value(6) and rb.mass < 30.0:
			rb.apply_central_impulse(Vector3(hv.x, 0.6, hv.y) * 3.0)


## A bullet (or a punch) hit a city prop: bins and hydrants break, ATMs give way after a few rounds.
func on_hit(hit: Dictionary, dir: Vector3, damage: float) -> void:
	var pr := _prop_at(hit.get("collider"), int(hit.get("shape", -1)))
	if pr.is_empty() or not BREAKABLE.has(pr[0]):
		var rb := hit.get("collider") as RigidBody3D
		if rb and rb.get_collision_layer_value(6):
			rb.apply_impulse(dir * damage * 0.25, hit.position - rb.global_position)
		return
	var def: Dictionary = BREAKABLE[pr[0]]
	var key := "%d:%d" % [(pr[1] as Object).get_instance_id(), pr[2]]
	if def.get("bullets", false) or def.get("hydrant", false):
		break_prop(hit.collider, int(hit.shape), dir * damage * 0.4 + Vector3.UP * 4.0, hit.position)
	elif def.get("atm", false):
		_atm_hits[key] = int(_atm_hits.get(key, 0)) + 1
		if int(_atm_hits[key]) >= 5:
			break_prop(hit.collider, int(hit.shape), dir * 200.0, hit.position)


## A blast throws everything breakable within the radius.
func blast(at: Vector3, radius: float) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	q.shape = sph
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 16
	for r: Dictionary in space.intersect_shape(q, 24):
		var pr := _prop_at(r.collider, int(r.shape))
		if pr.is_empty() or not BREAKABLE.has(pr[0]):
			continue
		var cpos := (pr[3] as CollisionShape3D).global_position
		var away := (cpos - at)
		var k := clampf(1.0 - away.length() / radius, 0.2, 1.0)
		var m := float(BREAKABLE[pr[0]].mass)
		break_prop(r.collider, int(r.shape), (away.normalized() + Vector3.UP * 0.8).normalized() * m * 14.0 * k, cpos)
	for rb: RigidBody3D in _debris:
		if is_instance_valid(rb) and rb.global_position.distance_to(at) < radius:
			var away := rb.global_position - at
			rb.apply_central_impulse((away.normalized() + Vector3.UP * 0.8).normalized() * rb.mass * 12.0 * clampf(1.0 - away.length() / radius, 0.2, 1.0))


func _tidy_debris(focus: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	for i in range(_debris.size() - 1, -1, -1):
		var rb := _debris[i]
		if not is_instance_valid(rb):
			_debris.remove_at(i)
			continue
		var far := rb.global_position.distance_to(focus) > 120.0 and not (cam and cam.is_position_in_frustum(rb.global_position))
		if far or rb.global_position.y < -50.0 or (_debris.size() > MAX_DEBRIS and i == 0):
			rb.queue_free()
			_debris.remove_at(i)


# --- using things -------------------------------------------------------------------

## Proxies for the usable props within 18 m of the player (made and freed as they come and go).
func _update_uses(focus: Vector3) -> void:
	var w := Game.world as World
	if w == null or w.city == null:
		return
	var seen := {}
	var ck := Vector2i(floori(focus.x / CityCell.SIZE), floori(focus.z / CityCell.SIZE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell = w.city._cells.get(ck + Vector2i(dx, dz))
			if cell == null or not is_instance_valid(cell) or not (cell as Node3D).visible:
				continue
			for mmi in (cell as Node).get_children():
				if not (mmi is MultiMeshInstance3D):
					continue
				var name := String(mmi.get_meta("prop", ""))
				if not (name in USABLE):
					continue
				var xfs: Array = mmi.get_meta("xfs", [])
				var broken: Dictionary = mmi.get_meta("broken", {})
				for i in xfs.size():
					if broken.has(i):
						continue
					var xf := (mmi as Node3D).global_transform * (xfs[i] as Transform3D)
					if xf.origin.distance_to(focus) > 18.0:
						continue
					var key := "%d:%d" % [mmi.get_instance_id(), i]
					seen[key] = true
					if not _uses.has(key):
						var u := PropUse.new()
						u.kind = name
						u.prop_xf = xf
						u.mmi = mmi
						u.inst = i
						add_child(u)
						_uses[key] = u
	for key: String in _uses.keys():
		if not seen.has(key) or not is_instance_valid(_uses[key]):
			if is_instance_valid(_uses[key]):
				_uses[key].queue_free()
			_uses.erase(key)
