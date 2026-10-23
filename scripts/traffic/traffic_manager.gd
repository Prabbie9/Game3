class_name TrafficManager
extends Node3D
## Moving traffic around the player: cars with NPC drivers following the LaneGraph. They keep to their lane
## (pure pursuit on a look-ahead point), hold the lane's speed and slow for turns, stop at red/amber signals
## and give way at unsignalled junctions, keep their distance to whatever is ahead (other cars, the player,
## pedestrians), honk when held up, and speed off when there is gunfire nearby. Cars appear out of sight
## 70–160 m away and are recycled beyond 172 m (vehicles past the streamed collision
## are frozen by the World). A carjacked car simply leaves the system.

const SPAWN_MIN := 70.0
const SPAWN_MAX := 160.0
const DESPAWN := 172.0
const IN_VIEW_MIN := 120.0
const ACCEL := 3.2       # comfortable deceleration used for stopping distances (m/s^2)
const MODELS := ["sedan", "sedan", "hatchback", "hatchback", "compact", "compact", "wagon", "suv", "suv", "coupe",
	"minivan", "pickup", "sport", "van", "boxtruck", "offroad", "muscle"]

var graph: LaneGraph
var budget := 12
var cars: Array = []           # TrafficCar
var clock := 0.0               # signal clock (s)
var _spawn_t := 0.0
var _rng := RandomNumberGenerator.new()
var _junction_busy := {}       # node -> [[car, incoming road, distance to the stop line (0 = inside)], ...]


class TrafficCar:
	var v: Vehicle
	var lane := -1
	var s := 0.0
	var next := -1
	var stuck := 0.0
	var reverse_t := 0.0
	var panic := 0.0
	var honk_t := 0.0
	var blocked_t := 0.0
	var wait_node := -1
	var prev := -1      # the road lane we came from (while on a connector)
	var block: Object   # what _gap_ahead found in the way (null = other traffic or nothing)
	var change_t := 0.0
	var reason := ""    # why it is going slower than the limit (debugging / tests)


func _ready() -> void:
	_rng.randomize()
	graph = LaneGraph.new()
	var w := get_parent() as World
	graph.build(w.data, w.city.net)
	budget = GraphicsSettings.traffic_cars()
	Game.noise_made.connect(_on_noise)


func _physics_process(delta: float) -> void:
	clock += delta
	var focus := _focus()
	# who is in or about to enter each junction (cars on a connector, or near the stop line heading into one)
	_junction_busy.clear()
	for c: TrafficCar in cars:
		if not is_instance_valid(c.v):
			continue
		var ln: Dictionary = graph.lanes[c.lane]
		if ln.node >= 0:
			_occupy(int(ln.node), c, int(graph.lanes[_from_lane(c)].road) if c.prev >= 0 else -1, 0.0)
		elif c.next >= 0:
			var rem := float(ln.len) - c.s
			if rem < 22.0:
				_occupy(int(graph.lanes[c.next].node), c, int(ln.road), rem)
	for i in range(cars.size() - 1, -1, -1):
		var c: TrafficCar = cars[i]
		if not _alive(c):
			_release(c)
			cars.remove_at(i)
			continue
		if c.v.global_position.distance_to(focus) > DESPAWN and not _seen(c.v.global_position):
			c.v.queue_free()
			cars.remove_at(i)
			continue
		_drive(c, delta)
	_spawn_t -= delta
	if _spawn_t <= 0.0 and cars.size() < budget:
		_spawn_t = 0.35
		_try_spawn(focus)


func _focus() -> Vector3:
	var p := Game.player as Node3D
	return p.global_position if p else Vector3.ZERO


## Still a working traffic car: the AI driver is at the wheel and the car isn't wrecked.
func _alive(c: TrafficCar) -> bool:
	if not is_instance_valid(c.v) or c.v.damage.wrecked:
		return false
	var d := c.v.driver as NPCDriver
	return d != null and d.state == NPCDriver.State.SEATED


func _release(c: TrafficCar) -> void:
	if is_instance_valid(c.v):
		c.v.ai_drive = false
		c.v.horn_on = false


func _seen(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	return cam.is_position_in_frustum(pos + Vector3(0, 1, 0)) and cam.global_position.distance_to(pos) < 400.0


# --- spawning ------------------------------------------------------------------

func _try_spawn(focus: Vector3) -> void:
	var who: String = NPCDriver.CHARACTERS[_rng.randi() % NPCDriver.CHARACTERS.size()]
	if not NPCDriver.is_ready(who):
		return
	var cands := graph.lanes_near(focus, SPAWN_MAX)
	if cands.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	for attempt in 6:
		var id: int = cands[_rng.randi() % cands.size()]
		var ln: Dictionary = graph.lanes[id]
		if ln.node >= 0 or float(ln.len) < 20.0 or ln.kind == "hill":
			continue
		var s := _rng.randf_range(6.0, float(ln.len) - 12.0)
		var at: Array = graph.sample(id, s)
		var pos: Vector3 = at[0]
		var d := pos.distance_to(focus)
		if d < SPAWN_MIN or d > SPAWN_MAX:
			continue
		if d < IN_VIEW_MIN and cam and cam.is_position_in_frustum(pos + Vector3(0, 1, 0)):
			continue
		if not _clear(pos, 14.0):
			continue
		# the road's collision must be loaded here
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 3, 0), pos + Vector3(0, -3, 0), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var dir: Vector3 = at[1]
		var v := Vehicle.new()
		v.model = MODELS[_rng.randi() % MODELS.size()] if ln.kind != "freeway" else ["sedan", "suv", "sport", "boxtruck", "coupe", "wagon"][_rng.randi() % 6]
		v.paint = CarLibrary.random_paint(_rng)
		v.position = (hit.position as Vector3) + Vector3(0, 0.05, 0)
		v.rotation.y = atan2(-dir.x, -dir.z)
		v.add_to_group("traffic")
		get_parent().add_child(v)
		NPCDriver.seat_in(v, who)
		v.set_driver_input_enabled(false)
		v.ai_drive = true
		var c := TrafficCar.new()
		c.v = v
		c.lane = id
		c.s = s
		var start_v := minf(float(ln.speed), 12.0) * 0.8
		v.linear_velocity = dir * start_v
		v._prev_vel = v.linear_velocity  # not a crash
		cars.append(c)
		return


func _clear(pos: Vector3, r: float) -> bool:
	for n: Node in get_tree().get_nodes_in_group("vehicles"):
		if (n as Node3D).global_position.distance_to(pos) < r:
			return false
	var p := Game.player as Node3D
	return p == null or p.global_position.distance_to(pos) > r


# --- driving -------------------------------------------------------------------

func _drive(c: TrafficCar, delta: float) -> void:
	var v := c.v
	var pos := v.global_position
	var fwd := -v.global_basis.z
	var speed := fwd.dot(v.linear_velocity)
	# where are we along the lane? (moves forward only; spills into the next lane at the end)
	c.s = graph.project(c.lane, pos)
	var ln: Dictionary = graph.lanes[c.lane]
	if c.next < 0:
		c.next = _pick_next(c.lane)
	if c.s >= float(ln.len) - 0.6:
		if c.next < 0:
			c.v.queue_free()  # end of the road network: gone
			return
		c.prev = c.lane if graph.lanes[c.next].node >= 0 else -1
		c.lane = c.next
		c.s = graph.project(c.lane, pos)
		c.next = _pick_next(c.lane)
		ln = graph.lanes[c.lane]
	var remaining := float(ln.len) - c.s
	# steering: pure pursuit on a point ahead
	var look := clampf(absf(speed) * 0.75, 5.0, 15.0)
	var target := _point_ahead(c, look)
	var local := v.global_transform.affine_inverse() * target
	var alpha := atan2(-local.x, -local.z)
	var steer_limit := v.max_steer / (1.0 + absf(speed) / 5.5)
	var wheel := atan(2.0 * 2.7 * sin(alpha) / maxf(look, 1.0))
	var steer := clampf(wheel / maxf(steer_limit, 0.05), -1.0, 1.0)
	# speed: the lane's limit, slower into turns, stop for signals / give way, keep distance
	var want := float(ln.speed) * (1.3 if c.panic > 0.0 else 1.0)
	c.reason = ""
	var nl: Dictionary = graph.lanes[c.next] if c.next >= 0 else {}
	if not nl.is_empty():
		want = minf(want, sqrt(float(nl.speed) * float(nl.speed) + 2.0 * ACCEL * remaining))
		if ln.node < 0 and nl.node >= 0 and c.panic <= 0.0:
			var stop := false
			if int(nl.group) >= 0:
				var st := graph.signal_state(int(nl.node), int(nl.group), clock)
				var stopping := speed * speed / (2.0 * ACCEL * 1.6)
				stop = st == 2 or (st == 1 and remaining > stopping + 2.0)
			if stop:
				c.reason = "signal"
			if not stop and not _may_enter(c, int(nl.node), int(ln.road), int(nl.turn), int(nl.group) >= 0, remaining):
				stop = true
				c.reason = "give way"
			if stop:
				want = minf(want, sqrt(2.0 * ACCEL * maxf(remaining - 2.0, 0.0)))
	var gap := _gap_ahead(c, pos, fwd, speed)
	if gap < INF and (gap - 3.0) * 0.9 < want:
		c.reason = "behind %s" % (c.block.name if c.block else "traffic")
	if gap < INF:
		want = minf(want, maxf(0.0, (gap - 3.0) * 0.9))
		c.blocked_t = c.blocked_t + delta if speed < 1.0 else 0.0
	else:
		c.blocked_t = 0.0
	# something that isn't moving (a parked or abandoned car, a crash) sits in our lane: change lanes
	c.change_t -= delta
	if c.blocked_t > 1.5 and c.change_t <= 0.0 and ln.node < 0 and c.block != null and not _is_traffic(c.block):
		var other := graph.adjacent_lane(c.lane)
		if other >= 0 and _lane_clear(other, c.s, pos):
			c.lane = other
			c.s = graph.project(other, pos)
			c.next = _pick_next(other)
			c.change_t = 4.0
			c.blocked_t = 0.0
	# controls
	var err := want - speed
	var throttle := 0.0
	var brake := 0.0
	if err > 0.3:
		throttle = clampf(err * 0.35 + 0.2, 0.0, 1.0)
	elif err < -0.6:
		brake = clampf(-err * 0.3, 0.0, 1.0)
	if want < 0.3 and speed < 1.5:
		brake = 1.0
		throttle = 0.0
	# stuck against something for a while: back up a little, then try again
	if want > 3.0 and absf(speed) < 0.4 and gap == INF:
		c.stuck += delta
	else:
		c.stuck = maxf(0.0, c.stuck - delta)
	if c.stuck > 4.0:
		c.reverse_t = 1.6
		c.stuck = 0.0
	if c.reverse_t > 0.0:
		c.reverse_t -= delta
		throttle = -0.6
		brake = 0.0
		steer = -steer
	v.ai_throttle = throttle
	v.ai_brake = brake
	v.ai_steer = steer
	v.ai_handbrake = false
	# horn: held up by the player, or panicking
	c.panic = maxf(0.0, c.panic - delta)
	c.honk_t -= delta
	if (c.blocked_t > 2.5 or (c.panic > 0.0 and randf() < delta * 0.4)) and c.honk_t <= 0.0:
		c.honk_t = 4.0 + randf() * 3.0
		v.horn_on = true
		get_tree().create_timer(0.5 + randf() * 0.5).timeout.connect(func():
			if is_instance_valid(v):
				v.horn_on = false)
	# headlights after dark
	var w := get_parent() as World
	if w and v.headlights_on != (w.night > 0.5):
		v.set_headlights(w.night > 0.5)


func _is_traffic(o: Object) -> bool:
	return o is Node and (o as Node).is_in_group("traffic") and (o as Vehicle).ai_drive


## No traffic within a car length behind to a few lengths ahead of s on that lane.
func _lane_clear(lane: int, s: float, _pos: Vector3) -> bool:
	for o: TrafficCar in cars:
		if o.lane == lane and o.s > s - 10.0 and o.s < s + 14.0:
			return false
	return true


func _from_lane(c: TrafficCar) -> int:
	return c.prev if c.prev >= 0 else c.lane


func _occupy(node: int, c: TrafficCar, road: int, dist: float) -> void:
	if not _junction_busy.has(node):
		_junction_busy[node] = []
	(_junction_busy[node] as Array).append([c, road, dist])


## Junction etiquette. Signalled: the phase already decided who goes; turning left also waits for oncoming
## cars in (or about to enter) the junction. Unsignalled: wait while anyone from another road is crossing,
## and give way to whoever is closer to their stop line.
func _may_enter(c: TrafficCar, node: int, road: int, turn: int, signalled: bool, rem: float) -> bool:
	for e: Array in _junction_busy.get(node, []):
		var o: TrafficCar = e[0]
		if o == c or int(e[1]) == road:
			continue
		var d: float = e[2]
		if signalled:
			if turn == -1 and (d == 0.0 or (d < 18.0 and o.v.linear_velocity.length() > 2.0)):
				return false
		else:
			if d == 0.0 or (d < rem - 1.0 and o.v.linear_velocity.length() > 0.5):
				return false
	return true


func _pick_next(lane: int) -> int:
	var opts: Array = graph.lanes[lane].next
	if opts.is_empty():
		return -1
	if opts.size() == 1:
		return opts[0]
	# mostly straight on
	var straight := opts.filter(func(id): return int(graph.lanes[id].turn) == 0)
	if not straight.is_empty() and _rng.randf() < 0.55:
		return straight[_rng.randi() % straight.size()]
	return opts[_rng.randi() % opts.size()]


func _point_ahead(c: TrafficCar, dist: float) -> Vector3:
	var ln: Dictionary = graph.lanes[c.lane]
	var s := c.s + dist
	if s <= float(ln.len) or c.next < 0:
		return graph.sample(c.lane, s)[0]
	var rest := s - float(ln.len)
	var nl: Dictionary = graph.lanes[c.next]
	if rest <= float(nl.len) or (nl.next as Array).is_empty():
		return graph.sample(c.next, rest)[0]
	return graph.sample(int((nl.next as Array)[0]), rest - float(nl.len))[0]


## Distance to the nearest thing in the way: other traffic in our lane or the next one, and anything a
## box cast ahead finds (the player, parked or crashed cars, people). INF when the way is clear.
func _gap_ahead(c: TrafficCar, pos: Vector3, fwd: Vector3, speed: float) -> float:
	var best := INF
	c.block = null
	var nxt_len := float(graph.lanes[c.lane].len) - c.s
	for o: TrafficCar in cars:
		if o == c or not is_instance_valid(o.v):
			continue
		var d := INF
		if o.lane == c.lane and o.s > c.s:
			d = o.s - c.s
		elif o.lane == c.next:
			d = nxt_len + o.s
		if d < best:
			best = d
	var reach := clampf(speed * 1.6 + 8.0, 8.0, 40.0)
	var space := get_world_3d().direct_space_state
	var half := c.v._bounds.size.z * 0.5
	var from := pos + Vector3(0, 0.8, 0) + fwd * (half + 0.3)
	var right := c.v.global_basis.x
	for side: float in [-0.7, 0.0, 0.7]:
		var q := PhysicsRayQueryParameters3D.create(from + right * side, from + right * side + fwd * reach, 2 | 4 | 8)
		q.exclude = [c.v.get_rid()]
		var hit := space.intersect_ray(q)
		if hit:
			var d := (from.distance_to(hit.position)) + half
			if d < best:
				best = d
				c.block = hit.collider
	return best - half if best < INF else INF


func _on_noise(pos: Vector3, radius: float, _source: Node) -> void:
	for c: TrafficCar in cars:
		if is_instance_valid(c.v) and c.v.global_position.distance_to(pos) < maxf(radius, 50.0):
			c.panic = 12.0
