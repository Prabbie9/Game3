class_name ParkedCars
extends Node3D
## Parked cars along kerbs and in car parks. Slots come from the baked road graph and lots (deterministic, so the
## same street always has the same cars); Vehicles are created for the nearest occupied slots around the focus and
## freed again when far. A car someone has driven or pushed away from its slot is left alone (it becomes an
## ordinary world vehicle) until it is far from the player.

const SPAWN_R := 115.0
const DESPAWN_R := 150.0
const LOOSE_R := 320.0         # moved cars are freed beyond this
const IN_VIEW_MIN := 95.0      # don't pop cars in closer than this while the camera looks at the slot
const GRID := 64.0
const MAX_OCCUPIED := 3        # cars waiting with a driver inside, at most this many around
const OCCUPIED_PCT := 6
const KERB_GAP := 6.6          # kerbside slot pitch (m)
const KERB_ODDS := {"street": 0.42, "residential": 0.3}
const LOT_ODDS := {"parking": 0.55, "mall": 0.5, "gas_station": 0.25, "industrial": 0.35, "port_sheds": 0.3, "container_yard": 0.15}
const URBAN_MODELS := ["sedan", "sedan", "hatchback", "hatchback", "compact", "compact", "wagon", "suv", "coupe", "minivan", "pickup", "sport",
	"muscle", "van", "sedan", "hatchback"]
## kerbside only (too wide for a painted bay)
const KERB_EXTRA := ["boxtruck", "van"]
const SUBURB_MODELS := ["suv", "suv", "minivan", "minivan", "wagon", "sedan", "hatchback", "pickup", "offroad", "compact"]
const WORK_MODELS := ["pickup", "pickup", "pickup", "offroad", "suv", "sedan", "wagon", "minivan", "van", "van"]

var max_active := 30
var _slots: Array = []         # [Vector3 pos (road surface), float yaw, String model, Color paint]
var _grid := {}                # Vector2i -> PackedInt32Array of slot ids
var _active := {}              # slot id -> Vehicle sitting in it
var _taken := {}               # slot id -> Vehicle that was moved off it (slot stays empty)
var _want: Array = []          # slot ids that should have a car, nearest first
var _scan := 0.0
var _reserved: Array = []     # [Vector3, radius]: kept clear (helipad, boat ramp)
var _fill_in := -1             # frames until a full fill (new collision needs a physics step to be queryable)


## Extract every model the slots use now (during loading) rather than on first sight (~0.1 s each).
func warm_models() -> void:
	var seen := {}
	for sl: Array in _slots:
		if not seen.has(sl[2]):
			seen[sl[2]] = true
			CarLibrary.get_model(sl[2])
	NPCDriver.preload_characters()


func setup(data: WorldData, net: RoadNet) -> void:
	for r in data.roads.size():
		var rd: Dictionary = data.roads[r]
		if not KERB_ODDS.has(rd.kind) or not rd.walk:
			continue
		_kerb_slots(r, rd, net)
	for l: Dictionary in data.lots:
		if LOT_ODDS.has(l.kind):
			_lot_slots(l)


func _kerb_slots(r: int, rd: Dictionary, net: RoadNet) -> void:
	var pts: Array = rd.pts
	var L: float = net.length[r]
	var s0: float = net.trim[Vector2i(r, 0)] + (8.0 if net.is_junction[int(rd.a)] else 1.0)
	var s1: float = L - net.trim[Vector2i(r, 1)] - (8.0 if net.is_junction[int(rd.b)] else 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(r, 77))
	var off: float = float(rd.w) * 0.5 - 1.2
	var models: Array = SUBURB_MODELS if rd.kind == "residential" else URBAN_MODELS
	var odds: float = KERB_ODDS[rd.kind]
	var s := s0 + KERB_GAP * 0.5
	while s < s1 - KERB_GAP * 0.5:
		for side: float in [-1.0, 1.0]:
			if rng.randf() > odds:
				continue
			var at := _along(pts, s + rng.randf_range(-0.6, 0.6))
			var p: Vector3 = at[0]
			var f: Vector2 = at[1]
			var rt := Vector2(-f.y, f.x) * side
			var m: String = models[rng.randi() % models.size()] if rng.randf() > 0.07 else KERB_EXTRA[rng.randi() % KERB_EXTRA.size()]
			# vans and trucks sit tight against the kerb so they don't stick out into the traffic lane
			var pos := p + Vector3(rt.x, 0, rt.y) * (off + (0.45 if m in KERB_EXTRA else 0.0))
			# cars face the direction of travel of their side of the road (forward is -Z)
			var dir := f * side
			_add_slot(pos, atan2(-dir.x, -dir.y) + rng.randf_range(-0.03, 0.03), m, CarLibrary.random_paint(rng))
		s += KERB_GAP


func _lot_slots(l: Dictionary) -> void:
	var r := Rect2(l.x0, l.z0, l.x1 - l.x0, l.z1 - l.z0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(l.get("seed", 1)) + 911
	var odds: float = LOT_ODDS[l.kind]
	var models: Array = WORK_MODELS if l.kind in ["industrial", "port_sheds", "container_yard"] else URBAN_MODELS
	# matches the bay markings in road.gdshader: 2.6 m bays in rows 5 m deep, 16 m row pitch
	var nx := int(r.size.x / 2.6)
	var row := 0.0
	while row < r.size.y - 4.0:
		for depth: float in [2.5, 13.5]:
			if row + depth > r.size.y - 2.4:
				continue
			for i in nx:
				if rng.randf() > odds:
					continue
				var pos := Vector3(r.position.x + 2.6 * (i + 0.5), CityCell.CURB_H, r.position.y + row + depth)
				# nose in, facing the curb row; now and then backed in
				var yaw := (0.0 if depth < 8.0 else PI) + (PI if rng.randf() < 0.25 else 0.0) + rng.randf_range(-0.05, 0.05)
				_add_slot(pos + Vector3(rng.randf_range(-0.15, 0.15), 0, 0), yaw, models[rng.randi() % models.size()], CarLibrary.random_paint(rng))
		row += 16.0


func _add_slot(pos: Vector3, yaw: float, model: String, paint: Color) -> void:
	var id := _slots.size()
	_slots.append([pos, yaw, model, paint])
	var k := Vector2i(floori(pos.x / GRID), floori(pos.z / GRID))
	if not _grid.has(k):
		_grid[k] = PackedInt32Array()
	_grid[k].append(id)


## Point and unit direction (xz) at distance s along a road polyline.
static func _along(pts: Array, s: float) -> Array:
	var acc := 0.0
	for i in pts.size() - 1:
		var a := Vector3(pts[i][0], pts[i][1], pts[i][2])
		var b := Vector3(pts[i + 1][0], pts[i + 1][1], pts[i + 1][2])
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		if s <= acc + seg or i == pts.size() - 2:
			var t := clampf((s - acc) / maxf(seg, 0.001), 0.0, 1.0)
			return [a.lerp(b, t), Vector2(b.x - a.x, b.z - a.z).normalized()]
		acc += seg
	return [Vector3(pts[0][0], pts[0][1], pts[0][2]), Vector2(0, -1)]


## Keep parked cars out of a circle (where a helicopter stands, say).
func reserve_area(pos: Vector3, radius: float) -> void:
	_reserved.append([pos, radius])


func slot_count() -> int:
	return _slots.size()


func active_count() -> int:
	return _active.size()


func _process(delta: float) -> void:
	if not Game.world:
		return
	var focus: Vector3 = Game.world.focus_point()
	if _fill_in >= 0:
		_fill_in -= 1
		if _fill_in < 0:
			fill(focus)
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.3
		_refresh(focus)
	# at most one new car per frame: building a vehicle costs a couple of milliseconds
	var cam := get_viewport().get_camera_3d()
	for id: int in _want:
		if _active.has(id) or _taken.has(id):
			continue
		var pos: Vector3 = _slots[id][0]
		if cam and pos.distance_to(focus) < IN_VIEW_MIN and cam.is_position_in_frustum(pos + Vector3(0, 0.8, 0)) \
				and cam.global_position.distance_to(pos) < IN_VIEW_MIN:
			continue
		if _spawn(id):
			break


func request_fill() -> void:
	_fill_in = 2


## Fill every wanted slot right away (loading, teleports), ignoring the in-view rule.
func fill(focus: Vector3) -> void:
	_refresh(focus)
	for id: int in _want:
		if not _active.has(id) and not _taken.has(id):
			_spawn(id)


func _refresh(focus: Vector3) -> void:
	# release cars that left their slot, and free those that are far away
	for id: int in _active.keys():
		var v: Vehicle = _active[id]
		if not is_instance_valid(v):
			_active.erase(id)
			continue
		var slot: Vector3 = _slots[id][0]
		var used: bool = v.driver != null and not v.driver is NPCDriver
		if used or Vector2(v.global_position.x - slot.x, v.global_position.z - slot.z).length() > 1.5:
			_active.erase(id)
			_taken[id] = v
		elif slot.distance_to(focus) > DESPAWN_R:
			_active.erase(id)
			v.queue_free()
	var player: Node = Game.player
	for id: int in _taken.keys():
		var v: Vehicle = _taken[id]
		var slot: Vector3 = _slots[id][0]
		if not is_instance_valid(v):
			if slot.distance_to(focus) > DESPAWN_R:
				_taken.erase(id)
			continue
		var in_use: bool = (v.driver != null and not v.driver is NPCDriver) or (player and player.get("vehicle") == v)
		if not in_use and v.global_position.distance_to(focus) > LOOSE_R:
			v.queue_free()
		elif slot.distance_to(focus) > DESPAWN_R and v.global_position.distance_to(slot) > 20.0:
			_taken.erase(id)  # it has gone elsewhere: the slot may get a new car next time we come by
	# nearest occupied slots
	var near := []
	var k0 := Vector2i(floori((focus.x - SPAWN_R) / GRID), floori((focus.z - SPAWN_R) / GRID))
	var k1 := Vector2i(floori((focus.x + SPAWN_R) / GRID), floori((focus.z + SPAWN_R) / GRID))
	for gx in range(k0.x, k1.x + 1):
		for gz in range(k0.y, k1.y + 1):
			for id: int in _grid.get(Vector2i(gx, gz), PackedInt32Array()):
				var d := (_slots[id][0] as Vector3).distance_to(focus)
				if d < SPAWN_R:
					near.append([d, id])
	near.sort_custom(func(a, b): return a[0] < b[0])
	_want.clear()
	for e in near:
		if _want.size() >= max_active:
			break
		_want.append(e[1])
	# over budget (the focus moved on): free the farthest parked cars that are no longer wanted
	if _active.size() > max_active:
		for id: int in _active.keys():
			if not id in _want:
				(_active[id] as Vehicle).queue_free()
				_active.erase(id)


func _spawn(id: int) -> bool:
	var s: Array = _slots[id]
	var pos: Vector3 = s[0]
	for r: Array in _reserved:
		if Vector2(pos.x - r[0].x, pos.z - r[0].z).length() < r[1]:
			_taken[id] = null
			return false
	var space := get_world_3d().direct_space_state
	# needs the ground's collision to be streamed in; finds the exact surface height
	var ray := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 2.5, 0), pos + Vector3(0, -3.0, 0), 1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return false
	pos.y = hit.position.y
	# keep clear of buildings, pumps, containers and other cars
	var box := BoxShape3D.new()
	var size := (CarLibrary.get_model(s[2]).aabb as AABB).size
	box.size = Vector3(size.x * 0.92, 1.1, size.z + 0.3)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis(Vector3.UP, s[1]), pos + Vector3(0, 1.0, 0))
	q.collision_mask = 1 | 2 | 8
	if not space.intersect_shape(q, 1).is_empty():
		_taken[id] = null  # blocked for good while we're around
		return false
	var v := Vehicle.new()
	v.model = s[2]
	v.paint = s[3]
	v.position = pos + Vector3(0, 0.02, 0)
	v.rotation.y = s[1]
	v.add_to_group("parked")
	add_child(v)
	_active[id] = v
	# now and then someone waits at the wheel with the engine running (carjackable)
	var who: String = NPCDriver.CHARACTERS[hash(id) % NPCDriver.CHARACTERS.size()]
	if _occupied() < MAX_OCCUPIED and hash(id * 31 + 7) % 100 < OCCUPIED_PCT and v.has_passenger_door() and NPCDriver.is_ready(who):
		NPCDriver.seat_in(v, who)
	return true


func _occupied() -> int:
	var n := 0
	for v: Vehicle in _active.values():
		if is_instance_valid(v) and v.driver is NPCDriver:
			n += 1
	return n
