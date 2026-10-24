class_name Wanted
extends Node
## The wanted level and the police response. Crimes the police see (or that a witness phones in) raise the
## stars; each star brings more: officers on foot, patrol cars, roadblocks, a SWAT van, the helicopter. Officers
## report sightings; out of everyone's sight for long enough and outside the search area (the circle on the
## minimap round the last sighting) the stars go. Arrests end in BUSTED, deaths in WASTED (GameOver screen).

signal stars_changed(stars: int)

const SEE_RANGE := 60.0
## stars -> [officers on foot, patrol cars, SWAT vans, helicopter]
const RESPONSE := {1: [2, 1, 0, 0], 2: [3, 2, 0, 0], 3: [4, 3, 0, 0], 4: [4, 3, 1, 0], 5: [5, 4, 2, 1]}

var stars := 0
var heat := 0.0                  # fractional stars (crimes while wanted push it up)
var last_seen := Vector3.ZERO
var unseen := 0.0                # seconds since an officer last saw the player
var traffic: TrafficManager
var cops: Array = []             # Cop on foot
var units: Array = []            # {car: TrafficCar, kind, crew: bool}
var roadblocks: Array = []       # [Vehicle...] parked across a road
var heli: Helicopter
var _spawn_t := 0.0
var _roadblock_t := 0.0
var _rng := RandomNumberGenerator.new()
var _seen_frame := 0
var _radio_t := 3.0


func _ready() -> void:
	_rng.randomize()
	Game.crime_committed.connect(_on_crime)
	Game.police_call.connect(_on_call)


# --- crimes -------------------------------------------------------------------

const CRIME_STARS := {"shooting": 1, "assault": 1, "murder": 2, "carjack": 1, "hit_pedestrian": 1, "theft": 1,
	"explosion": 1, "attack_police": 1, "kill_police": 2, "steal_police": 1}
## Crimes against the police count whether or not an officer sees them.
const ALWAYS := ["kill_police", "attack_police", "steal_police"]


func _on_crime(kind: String, pos: Vector3) -> void:
	if not (kind in ALWAYS) and not _police_sees(pos):
		return
	_raise(CRIME_STARS.get(kind, 1), pos)


## A witness phoned it in: at least one star, the search starts where it happened.
func _on_call(_from: Vector3, where: Vector3) -> void:
	if stars == 0:
		_raise(1, where)
	else:
		heat += 0.25


func crime_against_police(killed: bool) -> void:
	_on_crime("kill_police" if killed else "attack_police", Game.player.global_position)


func _raise(to: int, pos: Vector3) -> void:
	if stars > 0:
		heat += 0.5 * float(to)    # more crimes while wanted: climb a star every two or so
	else:
		heat = float(to)
	heat = minf(heat, 5.99)
	var s := maxi(stars, int(heat))
	last_seen = pos
	unseen = 0.0
	if s != stars:
		stars = clampi(s, 0, 5)
		heat = maxf(heat, float(stars))
		stars_changed.emit(stars)
		Audio.play_at(Audio.stream("vehicles/siren_loop.ogg"), Game.player.global_position + Vector3(30, 5, 0), -18.0, 1.0, &"SFX", 400.0)


## Any officer (on foot or in a car) or the helicopter close enough to see this spot.
func _police_sees(pos: Vector3) -> bool:
	var space := (Game.world as Node3D).get_world_3d().direct_space_state if Game.world else null
	if space == null:
		return false
	var eyes := []
	for c: Cop in cops:
		if is_instance_valid(c) and c.is_alive():
			eyes.append([c.global_position + Vector3(0, 1.6, 0), c.get_rid()])
	for u: Dictionary in units:
		var tc: TrafficManager.TrafficCar = u.car
		if is_instance_valid(tc.v):
			eyes.append([tc.v.global_position + Vector3(0, 1.4, 0), tc.v.get_rid()])
	for n: Node in get_tree().get_nodes_in_group("vehicles"):
		var v := n as Vehicle
		# a parked or passing police car counts too (someone's watching)
		if v and v.model == "police" and v.driver != null and v.driver != Game.player:
			eyes.append([v.global_position + Vector3(0, 1.4, 0), v.get_rid()])
	if is_instance_valid(heli):
		eyes.append([heli.global_position, heli.get_rid()])
	for e: Array in eyes:
		var from: Vector3 = e[0]
		if from.distance_to(pos) > SEE_RANGE * (2.0 if is_instance_valid(heli) and from == heli.global_position else 1.0):
			continue
		var q := PhysicsRayQueryParameters3D.create(from, pos + Vector3(0, 1.2, 0), 1)
		q.exclude = [e[1]]
		if space.intersect_ray(q).is_empty():
			return true
	return false


## An officer can see the player this frame.
func report_sighting(pos: Vector3) -> void:
	last_seen = pos
	unseen = 0.0
	_seen_frame = Engine.get_physics_frames()


## An officer has the player: BUSTED.
func bust(_by: Node) -> void:
	var w := Game.world as World
	var p := Game.player as Player
	if w == null or p == null or w.game_over.running:
		return
	p.arrested(w)
	clear()


## The player is pointing a gun at the police (makes even one-star officers open fire).
func player_threatening() -> bool:
	var p := Game.player as Player
	return p != null and p.aiming and p.weapon.has_weapon() and not p.weapon.is_melee()


func search_radius() -> float:
	return 45.0 + 25.0 * stars


func evade_time() -> float:
	return 8.0 + 4.0 * stars


func clear() -> void:
	if stars == 0:
		return
	stars = 0
	heat = 0.0
	stars_changed.emit(0)
	for u: Dictionary in units:
		var tc: TrafficManager.TrafficCar = u.car
		if is_instance_valid(tc.v):
			traffic.stand_down(tc)
	units.clear()
	for c: Cop in cops:
		if is_instance_valid(c) and c.is_alive():
			c.queue_free_when_unseen()
	cops.clear()
	for v: Vehicle in roadblocks:
		if is_instance_valid(v):
			v.set_meta("abandoned", true)
	roadblocks.clear()
	if is_instance_valid(heli):
		heli.set_meta("leave", true)


# --- per frame ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var p := Game.player as Player
	if p == null:
		return
	cops = cops.filter(func(c): return is_instance_valid(c))
	units = units.filter(func(u): return is_instance_valid((u.car as TrafficManager.TrafficCar).v))
	if is_instance_valid(heli):
		_fly_heli(delta)
	if stars == 0:
		return
	var at := p.vehicle.global_position if p.vehicle else p.global_position
	# the helicopter keeps eyes on the player
	if is_instance_valid(heli) and heli.global_position.distance_to(at) < 120.0 and _police_sees(at):
		report_sighting(at)
	unseen += delta
	if unseen > evade_time() and at.distance_to(last_seen) > search_radius():
		clear()
		Game.message("You lost the police.")
		return
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 1.5
		_top_up(p, at)
	_chase_units(p, at)
	_radio(delta, p, at)
	_roadblock_t -= delta
	if stars >= 3 and p.vehicle and p.vehicle.linear_velocity.length() > 12.0 and _roadblock_t <= 0.0:
		_roadblock_t = 25.0
		_place_roadblock(p)


func _top_up(p: Player, at: Vector3) -> void:
	var want: Array = RESPONSE[stars]
	if p.vehicle == null and cops.filter(func(c): return c.is_alive()).size() < int(want[0]):
		_spawn_foot_cop(at, "pistol" if stars < 3 else "smg")
	var cars := units.filter(func(u): return u.kind == "police").size()
	if cars < int(want[1]):
		_dispatch("police", at)
	var vans := units.filter(func(u): return u.kind == "swat").size()
	if vans < int(want[2]):
		_dispatch("swat", at)
	if int(want[3]) > 0 and not is_instance_valid(heli):
		_spawn_heli(at)


func _spawn_foot_cop(at: Vector3, gun: String) -> void:
	var pop: Population = (Game.world as World).population
	var cands := pop.walk.edges_near(at, 70.0)
	var cam := get_viewport().get_camera_3d()
	for attempt in 8:
		if cands.is_empty():
			return
		var id: int = cands[_rng.randi() % cands.size()]
		var e: Dictionary = pop.walk.edges[id]
		var pos := pop.walk.point(id, _rng.randf() * float(e.len), int(e.a))
		var d := pos.distance_to(at)
		if d < 30.0 or d > 70.0 or (cam and cam.is_position_in_frustum(pos + Vector3(0, 1, 0)) and d < 55.0):
			continue
		var c := _make_cop(gun)
		Game.world.add_child(c)
		c.global_position = pos + Vector3(0, 0.05, 0)
		return


func _make_cop(gun: String, swat := false) -> Cop:
	var c := Cop.new()
	var chars: Array = SWAT_CHARACTERS if swat else POLICE_CHARACTERS
	c.kit = "swat" if swat else "police"
	c.character_file = chars[_rng.randi() % chars.size()]
	c.female = Population.CHARACTERS.get(c.character_file, false)
	c.gun = gun
	c.wanted = self
	c.accuracy = 0.45 + 0.08 * stars
	cops.append(c)
	return c


## Who wears the uniform (see docs/DECISIONS.md: no police characters in the library; dark-clothed ones are used).
const POLICE_CHARACTERS := ["ch31_nonpbr", "ch33_nonpbr", "ch07_nonpbr", "ch23_nonpbr"]
const SWAT_CHARACTERS := ["ch28_nonpbr", "ch31_nonpbr", "ch12_nonpbr"]


func _dispatch(kind: String, at: Vector3) -> void:
	var model := "police" if kind == "police" else "van"
	var crew: Array = SWAT_CHARACTERS if kind == "swat" else POLICE_CHARACTERS
	var tc := traffic.dispatch(model, at, crew[_rng.randi() % crew.size()],
		Color(0.06, 0.07, 0.09) if kind == "swat" else Color(0, 0, 0, 0))
	if tc == null:
		return
	tc.chase = Game.player
	if kind == "swat" and tc.v.driver is NPCDriver:
		Uniform.dress((tc.v.driver as NPCDriver).visual, "swat")
	units.append({"car": tc, "kind": kind, "crew": false})


## Police cars close in on the player; once near and the player is on foot (or stopped), the crew gets out.
func _chase_units(p: Player, at: Vector3) -> void:
	for u: Dictionary in units:
		var tc: TrafficManager.TrafficCar = u.car
		if u.crew:
			continue
		# out of sight: patrol the search area round the last sighting instead of homing in on the player
		if unseen > 2.0:
			var sp: Vector3 = u.get("search", Vector3.INF)
			u.search_t = float(u.get("search_t", 0.0)) - get_physics_process_delta_time()
			if sp == Vector3.INF or float(u.search_t) <= 0.0 or tc.v.global_position.distance_to(sp) < 15.0:
				var a := _rng.randf() * TAU
				sp = last_seen + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.2, 0.75) * search_radius()
				u.search = sp
				u.search_t = 14.0
			tc.search_pos = sp
			u.stall = 0.0
			continue
		tc.search_pos = Vector3.INF
		u.erase("search")
		var d := tc.v.global_position.distance_to(at)
		var player_slow := p.vehicle == null or p.vehicle.linear_velocity.length() < 3.0
		# close by and stopped, or stuck behind something not far off: out of the car and on foot
		var slow := tc.v.linear_velocity.length() < 1.0
		u.stall = float(u.get("stall", 0.0)) + get_physics_process_delta_time() if slow and d < 55.0 else 0.0
		if player_slow and ((d < 22.0 and tc.v.linear_velocity.length() < 4.0) or float(u.stall) > 3.0):
			u.crew = true
			traffic.park(tc)
			var n := 2 if u.kind == "police" else 4
			for i in n:
				var c := _make_cop("pistol" if u.kind == "police" and stars < 3 else ("smg" if u.kind == "police" else "rifle"), u.kind == "swat")
				Game.world.add_child(c)
				var side := tc.v.global_basis.x * (1.5 + tc.v._bounds.size.x * 0.5) * (-1.0 if i % 2 == 0 else 1.0)
				c.global_position = tc.v.global_position + side + tc.v.global_basis.z * (i / 2) * 1.2 + Vector3(0, 0.2, 0)


## Two police cars parked across the road ahead of the player, officers behind them.
func _place_roadblock(p: Player) -> void:
	var v := p.vehicle
	var vel := v.linear_velocity
	vel.y = 0.0
	var la := traffic.lane_ahead(v.global_position, vel.normalized(), 120.0)
	if int(la[0]) < 0:
		_roadblock_t = 3.0   # not on a road right now: try again shortly
		return
	var ln: Dictionary = traffic.graph.lanes[int(la[0])]
	var at: Array = traffic.graph.sample(int(la[0]), float(la[1]))
	var pos: Vector3 = at[0]
	var dir: Vector3 = at[1]
	var cam := get_viewport().get_camera_3d()
	if cam and cam.is_position_in_frustum(pos) and cam.global_position.distance_to(pos) < 90.0:
		_roadblock_t = 3.0
		return
	var right := Vector3(-dir.z, 0, dir.x)
	# across the whole road: from the lane back to the centre line, then car after car kerb to kerb
	var rd: Dictionary = (Game.world as World).data.roads[int(ln.road)]
	var width := float(rd.w)
	var n := maxi(int(ln.lanes), 1)
	var lw := width / (2.0 * n)
	var off := lw * (int(ln.index) + 0.5) if n >= 2 else lw * 0.42
	var centre := pos - right * off
	var count := maxi(2, int(ceil((width - 1.0) / 4.4)))
	for k in count:
		var x := lerpf(-width * 0.5 + 2.2, width * 0.5 - 2.2, float(k) / maxf(count - 1, 1))
		var car := Vehicle.new()
		car.model = "police"
		car.position = centre + right * x + Vector3(0, 0.6, 0)
		car.rotation.y = atan2(-right.x, -right.z) + (0.25 if k % 2 == 0 else -0.25)
		Game.world.add_child(car)
		car.set_siren(true)
		roadblocks.append(car)
	for i in 2:
		var c := _make_cop("smg" if stars >= 4 else "pistol")
		Game.world.add_child(c)
		c.global_position = centre - dir * 3.5 + right * (i * 2.0 - 1.0) * 2.0 + Vector3(0, 0.2, 0)


## Radio chatter from the nearest police car or officer (or the stolen police car the player is driving).
func _radio(delta: float, p: Player, at: Vector3) -> void:
	_radio_t -= delta
	if _radio_t > 0.0:
		return
	_radio_t = _rng.randf_range(6.0, 14.0)
	var src := Vector3.INF
	var best := 45.0
	if p.vehicle and p.vehicle.model == "police":
		src = p.vehicle.global_position
	else:
		var from: Array = []
		for u: Dictionary in units:
			from.append((u.car as TrafficManager.TrafficCar).v)
		from.append_array(cops)
		for n: Node3D in from:
			if is_instance_valid(n) and n.global_position.distance_to(at) < best:
				best = n.global_position.distance_to(at)
				src = n.global_position
	if src != Vector3.INF:
		Audio.play_at(Audio.pick("police/radio_%d.ogg", 6), src + Vector3(0, 1.2, 0), -6.0, _rng.randf_range(0.95, 1.05), &"SFX", 40.0)


# --- helicopter -----------------------------------------------------------------

func _spawn_heli(at: Vector3) -> void:
	var h := Helicopter.new()
	h.model = "heli"
	var dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	h.position = at + dir * 160.0 + Vector3(0, 90.0, 0)
	Game.world.add_child(h)
	h.freeze = false
	var pilot := NPCDriver.seat_in(h, POLICE_CHARACTERS[0])
	pilot.visible = true
	h.set_driver_input_enabled(false)
	h.ai_drive = true
	h.rotor = 1.0
	heli = h


## Hold station above and behind the player at about 35 m, nose towards them; leave when the job's over.
func _fly_heli(delta: float) -> void:
	var p := Game.player as Player
	var h := heli
	var target := (p.vehicle.global_position if p.vehicle else p.global_position)
	var want := target + Vector3(0, 35.0, 0)
	if h.has_meta("leave") or stars < 5:
		want = h.global_position + (h.global_position - target).normalized() * 50.0 + Vector3(0, 20, 0)
		if h.global_position.distance_to(target) > 300.0:
			h.queue_free()
			heli = null
			return
	# keep clear of the towers: cruise high until close, never lower than 22 m over whatever is below or ahead
	var hp := h.global_position
	var flat_d := Vector2(hp.x - target.x, hp.z - target.z).length()
	if flat_d > 70.0:
		want.y = maxf(want.y, target.y + 80.0)
	var space := h.get_world_3d().direct_space_state
	var fwd := -h.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var floor_y := -INF
	# what is under it and along where it is heading (look further ahead the faster it flies)
	var spd := Vector2(h.linear_velocity.x, h.linear_velocity.z).length()
	var probes: Array = [Vector3.ZERO, h.linear_velocity * 1.5]
	for k in [6.0, 12.0, 18.0, 25.0, 35.0, 45.0]:
		if k < 8.0 + spd * 2.5:
			probes.append(fwd * k)
	var side := Vector3(-fwd.z, 0, fwd.x)
	probes.append_array([side * 5.0, -side * 5.0])
	for probe: Vector3 in probes:
		var top := hp + probe
		top.y = 400.0   # from high above, so a tower taller than the helicopter is found too
		var q := PhysicsRayQueryParameters3D.create(top, hp + probe + Vector3(0, -150, 0), 1)
		q.exclude = [h.get_rid()]
		var hit := space.intersect_ray(q)
		if hit:
			floor_y = maxf(floor_y, (hit.position as Vector3).y)
	if floor_y > -INF:
		want.y = maxf(want.y, floor_y + 22.0)
	# the hover point itself must be clear: above any roof within 10 m of it
	for k in 9:
		var off := Vector3.ZERO if k == 0 else Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * 10.0
		var top2 := Vector3(target.x, 400.0, target.z) + off
		var q2 := PhysicsRayQueryParameters3D.create(top2, top2 + Vector3(0, -420.0, 0), 1)
		q2.exclude = [h.get_rid()]
		var hit2 := space.intersect_ray(q2)
		if hit2 and flat_d < 60.0:
			want.y = maxf(want.y, (hit2.position as Vector3).y + 18.0)
	var to := want - hp
	# velocity control: head for the hover point at a speed that falls off as it gets close; the nose turns
	# into the needed velocity (correcting drift), the pitch sets the speed along it. Close by, face the player.
	var flat := Vector3(to.x, 0, to.z)
	var vh := Vector3(h.linear_velocity.x, 0, h.linear_velocity.z)
	var v_des := flat.normalized() * clampf(flat.length() * 0.35, 0.0, 20.0) if flat.length() > 0.5 else Vector3.ZERO
	var face := v_des + (v_des - vh) * 0.8
	if flat.length() < 15.0 or face.length() < 1.0:
		face = Vector3(target.x - hp.x, 0, target.z - hp.z)
	var yaw_err := fwd.signed_angle_to(face.normalized() if face.length() > 0.5 else fwd, Vector3.UP)
	h.ai_steer = clampf(yaw_err * 1.5, -1.0, 1.0)
	h.ai_throttle = clampf((v_des.dot(fwd) - vh.dot(fwd)) * 0.12, -1.0, 1.0)
	# well below where it needs to be (a roof ahead): climb first, don't press on into the wall
	if to.y > 6.0:
		h.ai_throttle = minf(h.ai_throttle, clampf(1.0 - (to.y - 6.0) / 10.0, -0.3, 1.0))
	h.ai_lift = clampf(to.y * 0.15 - h.linear_velocity.y * 0.3, -1.0, 1.0)
