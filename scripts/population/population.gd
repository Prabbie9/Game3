class_name Population
extends Node3D
## People on the streets around the player. How many depends on the graphics preset, the district (busy
## downtown, quiet hills) and the time of day (fewer at night). Most walk the pavements; some stand about on the
## phone, smoking or chatting in pairs. They appear out of sight 22–85 m away and are recycled beyond 100 m.
## Crossings: people wait while the road's traffic has green (signalled junctions) or a car is coming.

const SPAWN_MIN := 22.0
const SPAWN_MAX := 85.0
const DESPAWN := 100.0
const IN_VIEW_MIN := 60.0

## character file -> female (clip set). Every NPC character that ships.
const CHARACTERS := {
	"ch02_nonpbr": true, "ch21_nonpbr": true, "ch07_nonpbr": true, "ch13_nonpbr": true, "ch22_nonpbr": true,
	"ch26_nonpbr": true, "ch41_nonpbr": true,
	"ch33_nonpbr": false, "ch01_nonpbr": false, "ch06_nonpbr": false, "ch12_nonpbr": false, "ch23_nonpbr": false,
	"ch28_nonpbr": false, "ch31_nonpbr": false,
}
## district name -> crowd density 0..1
const DENSITY := {"Downtown": 1.0, "Playa Solano": 0.75, "Port of Solano": 0.35, "Eastside": 0.5, "Las Lomas": 0.45,
	"Mirador Hills": 0.2}

## Where someone sits on a bench, relative to the bench prop (tuned with the "street" screenshots).
const BENCH_SEAT := Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 0.32))

var walk: WalkGraph
var traffic: TrafficManager
var enabled := true   # false: no new people (tests that measure other systems)
var people: Array = []
var _spawn_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var w := get_parent() as World
	walk = WalkGraph.new()
	walk.build(w.data, w.city.net)
	NPCDriver.preload_characters()
	_prewarm_uniforms()


func _exit_tree() -> void:
	Uniform.finish()


## Fit the police / SWAT kits in the background as their characters finish loading.
func _prewarm_uniforms() -> void:
	var todo: Array = Wanted.POLICE_CHARACTERS + Wanted.SWAT_CHARACTERS
	while not todo.is_empty() and is_inside_tree():
		for c: String in todo.duplicate():
			if NPCDriver.is_ready(c):
				Uniform.prewarm(c)
				todo.erase(c)
				break
		await get_tree().create_timer(0.2).timeout


## People wanted around `pos` right now.
func target_count(pos: Vector3) -> int:
	var w := get_parent() as World
	var base := GraphicsSettings.pedestrians()
	var dens := 0.6
	if w:
		var best := INF
		for d: Dictionary in w.data.districts:
			var dd := Vector2(pos.x - float(d.x), pos.z - float(d.z)).length()
			if dd < best:
				best = dd
				dens = DENSITY.get(String(d.name), 0.6)
		var hour := fposmod(w.time_of_day, 24.0)
		if hour < 6.0 or hour > 22.5:
			dens *= 0.3
		elif hour > 19.5:
			dens *= 0.65
		if w.weather and w.weather.rain > 0.5:
			dens *= 0.6
	return int(round(base * dens))


## Main-thread cost of the last update (ms), for the perf overlay and tests.
var cost_ms := 0.0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_update(delta)
	cost_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _update(delta: float) -> void:
	var focus := _focus()
	for i in range(people.size() - 1, -1, -1):
		var p: Pedestrian = people[i]
		if not is_instance_valid(p):
			people.remove_at(i)
			continue
		if p.state == Pedestrian.State.DEAD:
			people.remove_at(i)  # the body stays (it cleans itself up)
			continue
		if p.global_position.distance_to(focus) > DESPAWN and not _seen(p.global_position):
			p.queue_free()
			people.remove_at(i)
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 0.25
		if enabled and people.size() < target_count(focus):
			_try_spawn(focus)


func _focus() -> Vector3:
	var p := Game.player as Node3D
	return p.global_position if p else Vector3.ZERO


func _seen(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.is_position_in_frustum(pos + Vector3(0, 1, 0)) and cam.global_position.distance_to(pos) < 300.0


func _try_spawn(focus: Vector3) -> void:
	var ready := CHARACTERS.keys().filter(func(c): return NPCDriver.is_ready(c))
	if ready.is_empty():
		return
	if _rng.randf() < 0.15 and _try_bench(focus, ready):
		return
	var cands := walk.edges_near(focus, SPAWN_MAX)
	if cands.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	for attempt in 6:
		var id: int = cands[_rng.randi() % cands.size()]
		var e: Dictionary = walk.edges[id]
		if float(e.len) < 3.0:
			continue
		var s := _rng.randf_range(0.5, float(e.len) - 0.5)
		var from: int = e.a if _rng.randf() < 0.5 else e.b
		var pos := walk.point(id, s, from)
		var d := pos.distance_to(focus)
		if d < SPAWN_MIN or d > SPAWN_MAX:
			continue
		if d < IN_VIEW_MIN and cam and cam.is_position_in_frustum(pos + Vector3(0, 1, 0)):
			continue
		# the pavement must be loaded (collision) and not inside something
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 2.0, 0), pos + Vector3(0, -2.0, 0), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or absf((hit.position as Vector3).y - pos.y) > 0.6:
			continue
		var roll := _rng.randf()
		var group := 1
		if roll < 0.12:
			group = 2
		for k in group:
			var c: String = _pick_character(ready)
			var ped := Pedestrian.new()
			ped.character_file = c
			ped.female = CHARACTERS[c]
			ped.pop = self
			ped.edge = id
			ped.from_node = from
			ped.s = s + k * 0.9
			ped.lateral = _rng.randf_range(-0.9, 0.9)
			add_child(ped)
			var at := walk.point(id, ped.s, from)
			var dir := walk.point(id, ped.s + 1.0, from) - at
			ped.global_position = Vector3(at.x, (hit.position as Vector3).y + 0.02, at.z) + Vector3(-dir.z, 0, dir.x).normalized() * ped.lateral
			ped.rotation.y = atan2(-dir.x, -dir.z)
			if group == 2:
				# a pair chatting, facing each other
				ped.rotation.y += PI * 0.5 if k == 0 else -PI * 0.5
				ped._start_activity("talk" if k == 0 else "argue" if _rng.randf() < 0.3 else "talk", _rng.randf_range(20.0, 50.0))
			elif roll < 0.22:
				ped._start_activity(["phone_f" if ped.female else "phone_m", "texting", "smoke"][_rng.randi() % 3], _rng.randf_range(10.0, 40.0))
			else:
				ped.state = Pedestrian.State.WALK
			people.append(ped)
		return


var _bench_taken := {}   # bench origin (snapped) -> Pedestrian


## Someone sitting on a free bench out of sight.
func _try_bench(focus: Vector3, ready: Array) -> bool:
	var w := get_parent() as World
	var benches: Array = w.city.benches_near(focus, SPAWN_MAX)
	if benches.is_empty():
		return false
	var cam := get_viewport().get_camera_3d()
	for attempt in 4:
		var xf: Transform3D = benches[_rng.randi() % benches.size()]
		var key := xf.origin.snapped(Vector3.ONE * 0.5)
		var who = _bench_taken.get(key)
		if who != null and is_instance_valid(who):
			continue
		var d := xf.origin.distance_to(focus)
		if d < SPAWN_MIN or (d < IN_VIEW_MIN and cam and cam.is_position_in_frustum(xf.origin + Vector3(0, 1, 0))):
			continue
		var c: String = _pick_character(ready)
		var ped := Pedestrian.new()
		ped.character_file = c
		ped.female = CHARACTERS[c]
		ped.pop = self
		add_child(ped)
		var seat := Transform3D(xf.basis.orthonormalized(), xf.origin) * BENCH_SEAT
		ped.global_transform = seat
		ped.sitting = true
		ped._start_activity("sit_talk" if _rng.randf() < 0.2 else "sit", 9999.0)
		_bench_taken[key] = ped
		people.append(ped)
		return true
	return false


func _pick_character(ready: Array) -> String:
	# the least used character among a few random picks, so a street never fills with clones
	var counts := {}
	for p: Pedestrian in people:
		if is_instance_valid(p):
			counts[p.character_file] = int(counts.get(p.character_file, 0)) + 1
	var best: String = ready[_rng.randi() % ready.size()]
	for i in 3:
		var c: String = ready[_rng.randi() % ready.size()]
		if int(counts.get(c, 0)) < int(counts.get(best, 0)):
			best = c
	return best


## Someone already standing about here (so people don't pile up for phone calls in one spot).
func busy_spot(pos: Vector3) -> bool:
	for p: Pedestrian in people:
		if is_instance_valid(p) and p.state == Pedestrian.State.ACT and p.global_position.distance_to(pos) < 4.0:
			return true
	return false


## May someone step onto this crossing now? At signalled junctions only while the cars on that road have red;
## elsewhere when no car is coming within a safe distance.
func may_cross(e: Dictionary) -> bool:
	var node: int = e.node
	var road: int = e.road
	if traffic and traffic.graph.signals.has(node) and road >= 0:
		var g: int = int(traffic.graph.signals[node].groups.get(Vector2i(road, int(e.end)), -1))
		if g >= 0:
			return traffic.graph.signal_state(node, g, traffic.clock) == 2
	var mid: Vector3 = ((e.pts as PackedVector3Array)[0] + (e.pts as PackedVector3Array)[-1]) * 0.5
	for n: Node in get_tree().get_nodes_in_group("vehicles"):
		var v := n as RigidBody3D
		if v == null:
			continue
		var rel := mid - v.global_position
		var sp := v.linear_velocity.length()
		if rel.length() < 6.0 or (sp > 2.0 and rel.length() < 30.0 and rel.normalized().dot(v.linear_velocity / sp) > 0.6):
			return false
	return true
