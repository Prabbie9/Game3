class_name TrafficManager
extends Node3D
## Moving traffic around the player: cars with NPC drivers following the LaneGraph. They keep to their lane
## (pure pursuit on a look-ahead point), hold the lane's speed and slow for turns, stop at red/amber signals
## and give way at unsignalled junctions, keep their distance to whatever is ahead (other cars, the player,
## pedestrians), honk when held up, and speed off when there is gunfire nearby. Cars appear out of sight
## 40–130 m away and are recycled beyond 150 m (vehicles past the streamed collision
## are frozen by the World). A carjacked car simply leaves the system.

const SPAWN_MIN := 40.0
const SPAWN_MAX := 130.0
const DESPAWN := 150.0
const IN_VIEW_MIN := 110.0
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
	var idle_t := 0.0    # stopped with no reason to be (wedged against something)
	var pass_t := 0.0    # overtaking a stopped obstacle on a one-lane road
	var yield_t := 0.0   # making way for a siren behind
	var reason := ""    # why it is going slower than the limit (debugging / tests)
	# emergency call-outs: follow a planned route to a target point, lights and siren on
	var route: Array = []
	var target_lane := -1
	var target_s := 0.0
	var target_pos := Vector3.INF
	var emergency := false
	var arrived := false
	var chase: Node3D       # police: drive at this (the player) instead of to a fixed point
	var parked := false     # stopped for good (crew out, roadblock)
	var _replan := 0.0
	var change_side := 0    # -1 left / 1 right: the lane change just made (indicator)
	var pass_obj: Node3D    # what it is overtaking
	var search_pos := Vector3.INF   # police that lost sight of the player: where to look instead
	var want := 0.0                 # target speed this frame (debugging / tests)
	var reverses := 0               # back-offs from about the same spot (wedged)
	var reverse_at := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	graph = LaneGraph.new()
	var w := get_parent() as World
	graph.build(w.data, w.city.net)
	budget = GraphicsSettings.traffic_cars()
	var lights := TrafficLights.new()
	lights.name = "Lights"
	add_child(lights)
	lights.setup(self)
	var ems := EmergencyServices.new()
	ems.name = "Emergency"
	add_child(ems)
	ems.traffic = self
	Game.noise_made.connect(_on_noise)


## Main-thread cost of the last update (ms), for the perf overlay and tests.
var cost_ms := 0.0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_update(delta)
	cost_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _update(delta: float) -> void:
	clock += delta
	var focus := _focus()
	# who is in or about to enter each junction (cars on a connector, or near the stop line heading into one)
	_junction_busy.clear()
	for c: TrafficCar in cars:
		if not is_instance_valid(c.v):
			continue
		var ln: Dictionary = graph.lanes[c.lane]
		if ln.node >= 0:
			_occupy(int(ln.node), c, int(graph.lanes[_from_lane(c)].road) if c.prev >= 0 else -1, 0.0, int(ln.turn))
		elif c.next >= 0:
			var rem := float(ln.len) - c.s
			if rem < 40.0:
				_occupy(int(graph.lanes[c.next].node), c, int(ln.road), rem, int(graph.lanes[c.next].turn))
	for i in range(cars.size() - 1, -1, -1):
		var c: TrafficCar = cars[i]
		if not _alive(c):
			if c.emergency:
				print_verbose("traffic: unit %s lost (wrecked %s driver %s)" % [c.v.model if is_instance_valid(c.v) else "?", c.v.damage.wrecked if is_instance_valid(c.v) else false, c.v.driver if is_instance_valid(c.v) else null])
			_release(c)
			cars.remove_at(i)
			continue
		c.idle_t = c.idle_t + delta if c.v.linear_velocity.length() < 0.5 and c.reason == "" and not c.arrived else 0.0
		# far away, or wedged somewhere for a long time where nobody is looking: recycle it
		var limit := DESPAWN if not (c.emergency or is_instance_valid(c.chase)) else 320.0
		if (c.v.global_position.distance_to(focus) > limit or (c.idle_t > 25.0 and not c.emergency)) and not _seen(c.v.global_position):
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
		c.v.set_indicator(Vehicle.Blinker.OFF)


func _seen(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	return cam.is_position_in_frustum(pos + Vector3(0, 1, 0)) and cam.global_position.distance_to(pos) < 400.0


# --- spawning ------------------------------------------------------------------

func _try_spawn(focus: Vector3) -> void:
	var chars: Array = Population.CHARACTERS.keys()
	var who: String = chars[_rng.randi() % chars.size()]
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
	if c.parked:
		v.ai_throttle = 0.0
		v.ai_brake = 1.0
		if v.indicator != Vehicle.Blinker.HAZARD:
			v.set_indicator(Vehicle.Blinker.HAZARD)
		return
	if is_instance_valid(c.chase):
		if _pursue(c, delta):
			return
	var pos := v.global_position
	var fwd := -v.global_basis.z
	var speed := fwd.dot(v.linear_velocity)
	# where are we along the lane? (moves forward only; spills into the next lane at the end)
	c.s = graph.project(c.lane, pos)
	var ln: Dictionary = graph.lanes[c.lane]
	if c.next < 0:
		c.next = _pick_next(c.lane, c)
	if c.s >= float(ln.len) - 0.6:
		if c.next < 0:
			c.v.queue_free()  # end of the road network: gone
			return
		c.prev = c.lane if graph.lanes[c.next].node >= 0 else -1
		c.lane = c.next
		c.s = graph.project(c.lane, pos)
		c.next = _pick_next(c.lane, c)
		ln = graph.lanes[c.lane]
	var remaining := float(ln.len) - c.s
	# steering: pure pursuit on a point ahead
	var look := clampf(absf(speed) * 0.75, 5.0, 15.0)
	var target := _point_ahead(c, look)
	# siren behind: slow down and keep to the right to let it through
	if not c.emergency and _siren_behind(c, pos):
		if ln.node < 0:
			var d2 := (target - pos)
			d2.y = 0.0
			target += Vector3(-d2.z, 0, d2.x).normalized() * 1.3
		c.yield_t = 1.0
	if c.pass_t > 0.0 and _oncoming_clear(c, pos):
		# overtaking a stopped car: aim a lane's width to the left
		var dir := (target - pos)
		dir.y = 0.0
		target += Vector3(dir.z, 0, -dir.x).normalized() * 3.4
	var local := v.global_transform.affine_inverse() * target
	var alpha := atan2(-local.x, -local.z)
	var steer_limit := v.max_steer / (1.0 + absf(speed) / 5.5)
	var wheel := atan(2.0 * v.wheelbase * sin(alpha) / maxf(look, 1.0))
	var steer := clampf(wheel / maxf(steer_limit, 0.05), -1.0, 1.0)
	# speed: the lane's limit, slower into turns, stop for signals / give way, keep distance
	if c.emergency:
		c.panic = maxf(c.panic, 1.0)  # lights and siren: through red lights, no waiting to turn
	var want := _lane_speed(c, ln) * (1.3 if c.panic > 0.0 else 1.0)
	c.reason = ""
	c.yield_t -= delta
	if c.yield_t > 0.0:
		want = minf(want, 3.0)
		c.reason = "yield"
	if c.emergency and c.target_pos != Vector3.INF:
		# pull up beside the scene, whichever side of the road it is on
		var dist := Vector2(pos.x - c.target_pos.x, pos.z - c.target_pos.z).length()
		var at_spot := c.lane == c.target_lane and c.s >= c.target_s - 3.0
		if dist < 16.0 or at_spot:
			want = minf(want, maxf(0.0, (dist - 8.0) * 0.8))
			if at_spot or dist < 10.0:
				want = 0.0   # stop here, don't roll on past
			if absf(speed) < 0.6:
				c.arrived = true
		elif c.route.is_empty() and c.lane != c.target_lane and c.target_lane >= 0 and not is_instance_valid(c.chase):
			# ran out of route (overshot, or turned off it round an obstacle): plan again from here
			c._replan -= delta
			if c._replan <= 0.0:
				c._replan = 3.0
				var path := route(c.next if c.next >= 0 else c.lane, c.target_lane)
				if not path.is_empty():
					c.route = path
					if c.next < 0:
						c.next = c.route.pop_front()
	var nl: Dictionary = graph.lanes[c.next] if c.next >= 0 else {}
	if not nl.is_empty():
		var nls := _lane_speed(c, nl)
		want = minf(want, sqrt(nls * nls + 2.0 * ACCEL * remaining))
		if ln.node < 0 and nl.node >= 0 and c.panic <= 0.0:
			var stop := false
			if int(nl.group) >= 0:
				var st := graph.signal_state(int(nl.node), int(nl.group), clock)
				var stopping := speed * speed / (2.0 * ACCEL * 1.6)
				stop = st == 2 or (st == 1 and remaining > stopping + 2.0)
			if stop:
				c.reason = "signal"
				# a siren right behind: creep through the red to clear the way (if the junction is clear)
				if c.yield_t > 0.0 and remaining < 8.0 and _cross_clear(c, int(nl.node), int(ln.road)):
					stop = false
					want = minf(want, 4.0)
					c.reason = "clearing"
			if not stop and not _may_enter(c, int(nl.node), int(ln.road), int(nl.turn), int(nl.group) >= 0, remaining):
				stop = true
				c.reason = "give way"
			if stop:
				want = minf(want, sqrt(2.0 * ACCEL * maxf(remaining - 2.0, 0.0)))
	var gap := _gap_ahead(c, pos, fwd, speed)
	if gap < INF and (gap - 3.0) * 0.9 < want:
		c.reason = "behind %s" % (c.block.name if c.block else "traffic")
	if gap < INF:
		# just pulled out round a stopped obstacle: creep past it instead of stopping behind it again
		var margin := 1.0 if (c.change_t > 0.0 or c.pass_t > 0.0) and not _is_traffic(c.block) else 3.0
		want = minf(want, maxf(0.0, (gap - margin) * 0.9))
		if margin < 3.0:
			want = minf(maxf(want, 2.5), 3.0)
		c.blocked_t = c.blocked_t + delta if speed < 1.0 else 0.0
	else:
		c.blocked_t = 0.0
	# something that isn't moving (a parked or abandoned car, a crash) sits in our lane: change lanes
	c.change_t -= delta
	# a slow car in front of an emergency vehicle also gets overtaken
	var slow_block := c.emergency and gap < 25.0 and c.block is RigidBody3D and (c.block as RigidBody3D).linear_velocity.length() < float(ln.speed) * 0.7
	if slow_block:
		# a car waiting at a light ahead clears the way through the red for the siren: wait for it rather than
		# swerving into a turn lane and taking a long way round
		var bc := _car_of(c.block)
		if bc and (bc.reason == "signal" or bc.reason == "clearing" or bc.reason.begins_with("give")):
			slow_block = false
	if slow_block:
		c.blocked_t += delta
	if c.blocked_t > 1.5 and c.change_t <= 0.0 and c.block != null and (not _is_traffic(c.block) or slow_block):
		var other := graph.adjacent_lane(c.lane) if ln.node < 0 else _adjacent_connector(c)
		if other >= 0 and _lane_clear(other, c.s, pos):
			var to_lane := v.global_transform.affine_inverse() * (graph.sample(other, graph.project(other, pos))[0] as Vector3)
			c.change_side = -1 if to_lane.x < 0.0 else 1
			c.lane = other
			c.s = graph.project(other, pos)
			c.next = _pick_next(other, c) if ln.node < 0 else int(graph.lanes[other].next[0])
			if not c.route.is_empty() and ln.node >= 0:
				c.route.clear()   # re-planned below if it's on a call
				c._replan = 0.0
			c.change_t = 4.0
			c.blocked_t = 0.0
			if c.target_lane >= 0 and (c.emergency or is_instance_valid(c.chase)):
				c.route = route(c.lane, c.target_lane)
				c.next = c.route.pop_front() if not c.route.is_empty() else _pick_next(c.lane)
		elif int(graph.lanes[c.lane].lanes) == 1 and ln.node < 0 and remaining > 25.0:
			# one lane each way: pull out round it when nothing is coming (not just before a junction, where
			# the car would end up waiting at the lights on the wrong side)
			c.pass_t = 5.0
			c.pass_obj = c.block as Node3D
		elif c.emergency and c.blocked_t > 4.0:
			c.pass_t = 4.0   # lights and siren: go round it on the other side
			c.pass_obj = c.block as Node3D
	# last resort for a unit on a call: a stalled car that has blocked it for long, out of sight, is towed away
	if c.emergency and c.blocked_t > 15.0 and c.block is Vehicle and _is_traffic(c.block) and not _seen((c.block as Vehicle).global_position):
		(c.block as Vehicle).queue_free()
		c.blocked_t = 0.0
	c.pass_t -= delta
	# don't pull back in while still alongside what it is overtaking
	if c.pass_t > -0.5 and c.pass_t < 0.3 and is_instance_valid(c.pass_obj):
		var rel := v.global_transform.affine_inverse() * c.pass_obj.global_position
		if rel.z < 3.0 and rel.length() < 12.0:   # forward is -Z: not yet behind us
			c.pass_t = 0.3
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
	if want > 1.5 and absf(speed) < 0.4 and gap == INF:
		c.stuck += delta
	else:
		c.stuck = maxf(0.0, c.stuck - delta)
	if c.stuck > 4.0:
		c.reverse_t = 1.6
		c.stuck = 0.0
		# backing off again and again from the same spot: wedged (a kerb corner, a wall). Out of sight, set it
		# back on its lane (a unit on a call) or take it away (ordinary traffic).
		if c.reverses == 0 or pos.distance_to(c.reverse_at) > 15.0:
			c.reverses = 0
			c.reverse_at = pos
		c.reverses += 1
		if c.reverses >= 3 and not _seen(pos):
			c.reverses = 0
			if c.emergency or is_instance_valid(c.chase):
				var smp: Array = graph.sample(c.lane, minf(c.s + 4.0, float(ln.len)))
				var d3: Vector3 = smp[1]
				v.global_transform = Transform3D(Basis(Vector3.UP, atan2(-d3.x, -d3.z)), (smp[0] as Vector3) + Vector3(0, 0.6, 0))
				v.linear_velocity = Vector3.ZERO
				v.angular_velocity = Vector3.ZERO
				v._prev_vel = Vector3.ZERO
				c.reverse_t = 0.0
			else:
				v.queue_free()
				return
	if c.reverse_t > 0.0:
		c.reverse_t -= delta
		throttle = -0.6
		brake = 0.0
		steer = -steer
	v.ai_throttle = throttle
	v.ai_brake = brake
	v.ai_steer = steer
	v.ai_handbrake = false
	c.want = want
	# horn: held up by the player, or panicking
	c.panic = maxf(0.0, c.panic - delta)
	c.honk_t -= delta
	if (c.blocked_t > 2.5 or (c.panic > 0.0 and randf() < delta * 0.4)) and c.honk_t <= 0.0:
		c.honk_t = 4.0 + randf() * 3.0
		v.horn_on = true
		# bound to the car (not a lambda capturing it), so a car freed meanwhile just drops the call
		get_tree().create_timer(0.5 + randf() * 0.5).timeout.connect(v.set.bind("horn_on", false))
	_indicate(c, ln, nl, remaining)
	# headlights after dark
	var w := get_parent() as World
	if w and v.headlights_on != (w.night > 0.5):
		v.set_headlights(w.night > 0.5)


## Indicators: before and through a turn at a junction, for a lane change or an overtake, right when pulling over
## for a siren; hazards when parked on a call or a roadblock.
func _indicate(c: TrafficCar, ln: Dictionary, nl: Dictionary, remaining: float) -> void:
	var want := 0   # -1 left, 1 right
	if int(ln.node) >= 0 and int(ln.turn) != 0:
		want = int(ln.turn)
	elif not nl.is_empty() and int(nl.node) >= 0 and int(nl.turn) != 0 and remaining < 35.0:
		want = int(nl.turn)
	elif c.change_t > 2.0 and c.change_side != 0:
		want = c.change_side
	elif c.pass_t > 3.5:
		want = -1
	elif c.yield_t > 0.0:
		want = 1
	var sig := Vehicle.Blinker.OFF
	if c.parked:
		sig = Vehicle.Blinker.HAZARD
	elif want < 0:
		sig = Vehicle.Blinker.LEFT
	elif want > 0:
		sig = Vehicle.Blinker.RIGHT
	if c.v.indicator != sig:
		c.v.set_indicator(sig)


func _car_of(o: Object) -> TrafficCar:
	for o2: TrafficCar in cars:
		if o2.v == o:
			return o2
	return null


## Speed for a lane: long vehicles (trucks, buses) take turns slowly so they don't swing into the other lane.
func _lane_speed(c: TrafficCar, ln: Dictionary) -> float:
	var sp := float(ln.speed)
	if int(ln.node) >= 0 and int(ln.turn) != 0 and c.v.wheelbase > 3.4:
		sp = minf(sp, 5.0)
	return sp


## On a junction connector blocked beyond it: the connector from the same approach into the neighbouring lane.
func _adjacent_connector(c: TrafficCar) -> int:
	if c.prev < 0:
		return -1
	var out: int = graph.lanes[c.lane].next[0]
	var alt := graph.adjacent_lane(out)
	if alt < 0:
		return -1
	for id: int in graph.lanes[c.prev].next:
		if int(graph.lanes[id].next[0]) == alt:
			return id
	return -1


## Nothing coming the other way within ~40 m (for overtaking on a one-lane road).
func _oncoming_clear(c: TrafficCar, pos: Vector3) -> bool:
	var fwd := -c.v.global_basis.z
	for n: Node in get_tree().get_nodes_in_group("vehicles"):
		var o := n as RigidBody3D
		if o == null or o == c.v:
			continue
		var rel := o.global_position - pos
		if rel.length() < 45.0 and rel.dot(fwd) > 0.0 and o.linear_velocity.dot(fwd) < -1.0:
			return false
	return true


func _siren_behind(c: TrafficCar, pos: Vector3) -> bool:
	var fwd := -c.v.global_basis.z
	for o: TrafficCar in cars:
		if o == c or not o.emergency or not is_instance_valid(o.v):
			continue
		var rel := o.v.global_position - pos
		if rel.length() < 30.0 and rel.dot(fwd) < -3.0 and absf(rel.dot(c.v.global_basis.x)) < 4.0:
			return true
	return false


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


func _occupy(node: int, c: TrafficCar, road: int, dist: float, turn: int) -> void:
	if not _junction_busy.has(node):
		_junction_busy[node] = []
	(_junction_busy[node] as Array).append([c, road, dist, turn])


## Nobody from another approach is in the junction or coming up to it (going through a red for a siren).
func _cross_clear(c: TrafficCar, node: int, road: int) -> bool:
	for e: Array in _junction_busy.get(node, []):
		var o: TrafficCar = e[0]
		if o == c or int(e[1]) == road:
			continue
		if float(e[2]) == 0.0 or (float(e[2]) < 35.0 and o.v.linear_velocity.length() > 1.0):
			return false
	return true


## Junction etiquette. Signalled: the phase already decided who goes; turning left also waits for oncoming
## cars in (or about to enter) the junction. Unsignalled: wait while anyone from another road is crossing,
## and give way to whoever is closer to their stop line.
func _may_enter(c: TrafficCar, node: int, road: int, turn: int, signalled: bool, rem: float) -> bool:
	for e: Array in _junction_busy.get(node, []):
		var o: TrafficCar = e[0]
		if o == c or int(e[1]) == road:
			continue
		var d: float = e[2]
		if d > 22.0:
			continue   # far off (only the siren rule looks that far)
		var oturn: int = e[3]
		# someone from another approach is already in the junction on a path that may cross ours
		if d == 0.0 and not ((turn == 0 and oturn == 0) or (turn == 1 and oturn == 1)):
			return false
		if signalled:
			if turn == -1 and d < 18.0 and o.v.linear_velocity.length() > 2.0:
				return false
		else:
			if d == 0.0 or (d < rem - 1.0 and o.v.linear_velocity.length() > 0.5):
				return false
	return true


func _pick_next(lane: int, c: TrafficCar = null) -> int:
	if c and not c.route.is_empty():
		return c.route.pop_front()
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
			# the rays run straight ahead while the lane may curve: something standing beside the lane (a car
			# at the kerb, someone on the pavement as we turn) isn't in the way
			if not _is_traffic(hit.collider) and _off_path(c, hit.position) > c.v._bounds.size.x * 0.5 + 0.25:
				continue
			var d := (from.distance_to(hit.position)) + half
			if d < best:
				best = d
				c.block = hit.collider
	return best - half if best < INF else INF


## How far a point lies to the side of the path the car is following (its lane, then the next one).
func _off_path(c: TrafficCar, p: Vector3) -> float:
	var best := INF
	for id: int in [c.lane, c.next]:
		if id < 0:
			continue
		var s := graph.project(id, p)
		var q: Vector3 = graph.sample(id, s)[0]
		best = minf(best, Vector2(q.x - p.x, q.z - p.z).length())
	return best


## Police pursuit: far off, keep re-planning a lane route to the target; close (or once the route runs out)
## drive straight at it, faster than traffic, ramming if need be. Returns true when it handled the controls.
func _pursue(c: TrafficCar, delta: float) -> bool:
	var v := c.v
	var tgt := c.chase.global_position
	var p := c.chase as Player
	if p and p.vehicle:
		tgt = p.vehicle.global_position
	if c.search_pos != Vector3.INF:
		tgt = c.search_pos
		p = null   # cruising the search area: no ramming, pull up at the spot
	var d := v.global_position.distance_to(tgt)
	c._replan -= delta
	if d > 45.0:
		if c._replan <= 0.0:
			c._replan = 3.0
			var tl := nearest_lane(tgt)
			if tl[0] >= 0:
				var path := route(c.lane, int(tl[0]))
				if not path.is_empty():
					c.route = path
					c.next = c.route.pop_front()
					c.target_lane = tl[0]
					c.target_s = tl[1]
		c.emergency = true
		return false  # lane driving towards it
	var speed := -v.global_basis.z.dot(v.linear_velocity)
	var local := v.global_transform.affine_inverse() * tgt
	var alpha := atan2(-local.x, -local.z)
	var steer_limit := v.max_steer / (1.0 + absf(speed) / 5.5)
	var steer := clampf(alpha / maxf(steer_limit, 0.05), -1.0, 1.0)
	var target_v := 22.0
	var player_slow := p == null or p.vehicle == null or p.vehicle.linear_velocity.length() < 3.0
	if player_slow:
		target_v = clampf((d - 8.0) * 0.8, 0.0, 14.0)   # pull up near them
	if absf(alpha) > 2.2 and speed < 6.0:
		# target behind: reverse-turn
		v.ai_throttle = -0.8
		v.ai_brake = 0.0
		v.ai_steer = -steer
		return true
	v.ai_throttle = clampf((target_v - speed) * 0.3 + 0.2, 0.0, 1.0) if target_v > speed else 0.0
	v.ai_brake = clampf((speed - target_v) * 0.25, 0.0, 1.0) if speed > target_v + 1.0 else (1.0 if target_v < 0.5 else 0.0)
	v.ai_steer = steer
	v.ai_handbrake = absf(alpha) > 1.2 and speed > 10.0
	return true


## Shortest lane route (lane ids after `from`) to `to`; empty if unreachable. A* over the lane graph with a
## binary heap (straight-line distance to the target lane as the heuristic).
func route(from: int, to: int) -> Array:
	if from == to:
		return []
	var goal: Vector3 = (graph.lanes[to].pts as PackedVector3Array)[0]
	var g := {from: 0.0}
	var prev := {}
	var heap: Array = []   # [f, lane]
	_push(heap, [0.0, from])
	var closed := {}
	while not heap.is_empty():
		var cur: Array = _pop(heap)
		var id: int = cur[1]
		if closed.has(id):
			continue
		closed[id] = true
		if id == to:
			break
		if closed.size() > 5000:
			return []
		var base: float = g[id] + float(graph.lanes[id].len)
		for n: int in graph.lanes[id].next:
			if base < float(g.get(n, INF)):
				g[n] = base
				prev[n] = id
				var h := (graph.lanes[n].pts as PackedVector3Array)[0].distance_to(goal)
				_push(heap, [base + h, n])
	if not prev.has(to):
		return []
	var path := []
	var k := to
	while k != from:
		path.push_front(k)
		k = prev[k]
	return path


## GPS: the road route from `from` to `to` as a polyline (empty if there is none). With a heading (driving) the
## route starts on the lane going that way; on foot it takes whichever direction gives the shorter route.
func gps_path(from: Vector3, heading: Vector3, to: Vector3) -> PackedVector3Array:
	var goal := nearest_lane(to)
	if int(goal[0]) < 0:
		return PackedVector3Array()
	var starts := []
	if heading.length() > 0.1:
		var la := lane_ahead(from, heading.normalized(), 0.0)
		if int(la[0]) >= 0:
			starts.append(la)
	if starts.is_empty():
		for dir: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			var la2 := lane_ahead(from, dir, 0.0)
			if int(la2[0]) >= 0 and not starts.any(func(x): return int(x[0]) == int(la2[0])):
				starts.append(la2)
			if starts.size() >= 2:
				break
	var best := PackedVector3Array()
	var best_len := INF
	for st: Array in starts:
		var lanes := [int(st[0])] + route(int(st[0]), int(goal[0]))
		if lanes.size() == 1 and int(st[0]) != int(goal[0]):
			continue
		var pts := PackedVector3Array()
		var length := 0.0
		for i in lanes.size():
			var ln: Dictionary = graph.lanes[lanes[i]]
			var lp: PackedVector3Array = ln.pts
			var cum: PackedFloat32Array = ln.cum
			var s0 := float(st[1]) if i == 0 else 0.0
			var s1 := float(goal[1]) if i == lanes.size() - 1 else float(ln.len)
			if i == 0:
				pts.append(graph.sample(lanes[i], s0)[0])
			for k in lp.size():
				if cum[k] > s0 and cum[k] < s1:
					pts.append(lp[k])
			pts.append(graph.sample(lanes[i], s1)[0])
			length += maxf(s1 - s0, 0.0)
		if length < best_len:
			best_len = length
			best = pts
	return best


static func _push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p][0] <= h[i][0]:
			break
		var t: Array = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


static func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and h[l][0] < h[m][0]:
			m = l
		if r < n and h[r][0] < h[m][0]:
			m = r
		if m == i:
			break
		var t: Array = h[m]
		h[m] = h[i]
		h[i] = t
		i = m
	return top


## Nearest road lane point to `pos`: [lane, s, distance].
func nearest_lane(pos: Vector3) -> Array:
	var best := [-1, 0.0, INF]
	for id: int in graph.lanes_near(pos, 64.0):
		var ln: Dictionary = graph.lanes[id]
		if ln.node >= 0 or ln.kind == "freeway":
			continue
		var s := graph.project(id, pos)
		var d := (graph.sample(id, s)[0] as Vector3).distance_to(pos)
		if d < best[2]:
			best = [id, s, d]
	return best


## The point `dist` metres ahead along the road the car at pos is driving (straight on at junctions), on a road
## lane (not inside a junction): [lane, s], or [-1, 0] if it isn't on a road going that way.
func lane_ahead(pos: Vector3, dir: Vector3, dist: float) -> Array:
	var lane := -1
	var s := 0.0
	var bd := 6.0
	for id: int in graph.lanes_near(pos, 20.0):
		var ln: Dictionary = graph.lanes[id]
		if ln.node >= 0:
			continue
		var ps := graph.project(id, pos)
		var smp: Array = graph.sample(id, ps)
		var d := (smp[0] as Vector3).distance_to(pos)
		if d < bd and (smp[1] as Vector3).dot(dir) > 0.6:
			bd = d
			lane = id
			s = ps
	if lane < 0:
		return [-1, 0.0]
	var left := dist
	for guard in 40:
		var ln: Dictionary = graph.lanes[lane]
		var rest := float(ln.len) - s
		if left <= rest and ln.node < 0:
			return [lane, s + left]
		left = maxf(left - rest, 0.0)
		var opts: Array = ln.next
		if opts.is_empty():
			return [-1, 0.0]
		var pick: int = opts[0]
		for o: int in opts:
			if int(graph.lanes[o].turn) == 0:
				pick = o
		lane = pick
		s = 0.0
	return [-1, 0.0]


## Send an emergency vehicle (ambulance, firetruck, police) to `target`: it appears on a lane 60–140 m away
## out of sight with a route there, siren on. Returns the TrafficCar or null.
func dispatch(model: String, target: Vector3, crew: String = "", paint := Color(0, 0, 0, 0)) -> TrafficCar:
	# any lane running past the scene will do (either side of the road)
	var goals := []
	for id: int in graph.lanes_near(target, 64.0):
		var ln: Dictionary = graph.lanes[id]
		if ln.node >= 0 or ln.kind == "freeway":
			continue
		var gs := graph.project(id, target)
		if (graph.sample(id, gs)[0] as Vector3).distance_to(target) < 14.0:
			goals.append([id, gs])
	if goals.is_empty():
		var tl0 := nearest_lane(target)
		if tl0[0] < 0:
			return null
		goals.append([tl0[0], tl0[1]])
	var focus := _focus()
	var cam := get_viewport().get_camera_3d()
	var cands := graph.lanes_near(target, 130.0)
	# collect a few possible starting points and take the one with the shortest drive
	var best := []
	var best_len := INF
	var tried := 0
	for attempt in 40:
		if tried >= 6:
			break
		var id: int = cands[_rng.randi() % cands.size()]
		var ln: Dictionary = graph.lanes[id]
		if ln.node >= 0 or float(ln.len) < 20.0 or ln.kind == "freeway":
			continue
		var s := _rng.randf_range(4.0, float(ln.len) - 8.0)
		var at: Array = graph.sample(id, s)
		var pos: Vector3 = at[0]
		var d := pos.distance_to(target)
		# not too close to the scene, and well inside the streamed (unfrozen) area around the player
		if d < 50.0 or d > 120.0 or pos.distance_to(focus) < 55.0 or pos.distance_to(focus) > 140.0:
			continue
		if cam and cam.is_position_in_frustum(pos + Vector3(0, 1, 0)) and pos.distance_to(focus) < 140.0:
			continue
		if not _clear(pos, 12.0):
			continue
		tried += 1
		for g: Array in goals:
			var path := route(id, int(g[0]))
			if path.is_empty() and id != int(g[0]):
				continue
			var L := float(ln.len) - s
			for k: int in path:
				L += float(graph.lanes[k].len)
			if L < best_len:
				best_len = L
				best = [id, s, at, path, g]
	if best.is_empty() or best_len > 600.0:
		return null
	var tl: Array = [best[4][0], best[4][1]]
	for once in 1:
		var id: int = best[0]
		var s: float = best[1]
		var at: Array = best[2]
		var path: Array = best[3]
		var pos: Vector3 = at[0]
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 3, 0), pos + Vector3(0, -3, 0), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var dir: Vector3 = at[1]
		var v := Vehicle.new()
		v.model = model
		if paint.a > 0.0:
			v.paint = paint
		v.position = (hit.position as Vector3) + Vector3(0, 0.05, 0)
		v.rotation.y = atan2(-dir.x, -dir.z)
		v.add_to_group("traffic")
		get_parent().add_child(v)
		var who: String = crew if crew != "" else Population.CHARACTERS.keys()[_rng.randi() % Population.CHARACTERS.size()]
		NPCDriver.seat_in(v, who)
		v.set_driver_input_enabled(false)
		v.ai_drive = true
		v.set_siren(true)
		var c := TrafficCar.new()
		c.v = v
		c.lane = id
		c.s = s
		c.route = path
		c.target_lane = tl[0]
		c.target_s = tl[1]
		c.target_pos = target
		c.emergency = true
		v.linear_velocity = dir * 8.0
		v._prev_vel = v.linear_velocity
		cars.append(c)
		return c
	return null


## Stop where it is for good (crew got out); the car stays as a parked police car.
func park(c: TrafficCar) -> void:
	c.parked = true
	c.route.clear()
	if is_instance_valid(c.v):
		c.v.ai_throttle = 0.0
		c.v.ai_brake = 1.0
		c.v.ai_steer = 0.0


## The job is done: back to normal driving (siren off).
func stand_down(c: TrafficCar) -> void:
	c.emergency = false
	c.arrived = false
	c.route.clear()
	c.panic = 0.0
	if is_instance_valid(c.v):
		c.v.set_siren(false)


func _on_noise(pos: Vector3, radius: float, _source: Node) -> void:
	for c: TrafficCar in cars:
		if is_instance_valid(c.v) and c.v.global_position.distance_to(pos) < maxf(radius, 50.0):
			c.panic = 12.0
