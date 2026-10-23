class_name Wanted
extends Node
## The wanted level and the police response. Crimes the police see (or that a witness phones in) raise the
## stars; each star brings more: officers on foot, patrol cars, roadblocks, a SWAT van, the helicopter. Officers
## report sightings; out of everyone's sight for long enough and outside the search area (the circle on the
## minimap round the last sighting) the stars go. Arrests end in BUSTED, deaths in WASTED (GameOver screen).

signal stars_changed(stars: int)

const SEE_RANGE := 60.0
## stars -> [officers on foot, patrol cars, SWAT vans, helicopter]
const RESPONSE := {1: [2, 1, 0, 0], 2: [3, 2, 0, 0], 3: [4, 3, 0, 0], 4: [4, 3, 1, 1], 5: [5, 4, 2, 1]}

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


func _ready() -> void:
	_rng.randomize()
	Game.crime_committed.connect(_on_crime)
	Game.police_call.connect(_on_call)


# --- crimes -------------------------------------------------------------------

const CRIME_STARS := {"shooting": 1, "assault": 1, "murder": 2, "carjack": 1, "hit_pedestrian": 1, "theft": 1,
	"explosion": 1, "attack_police": 1, "kill_police": 2}


func _on_crime(kind: String, pos: Vector3) -> void:
	if not _police_sees(pos) and kind != "kill_police" and kind != "attack_police":
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


func _make_cop(gun: String) -> Cop:
	var c := Cop.new()
	var chars: Array = POLICE_CHARACTERS
	c.character_file = chars[_rng.randi() % chars.size()]
	c.female = Population.CHARACTERS.get(c.character_file, false)
	c.gun = gun
	c.wanted = self
	c.accuracy = 0.45 + 0.08 * stars
	cops.append(c)
	return c


## Who wears the uniform (see docs/DECISIONS.md: no police characters in the library; dark-clothed ones are used).
const POLICE_CHARACTERS := ["ch33_nonpbr", "ch31_nonpbr", "ch23_nonpbr", "ch07_nonpbr"]


func _dispatch(kind: String, at: Vector3) -> void:
	var model := "police" if kind == "police" else "van"
	var tc := traffic.dispatch(model, at, POLICE_CHARACTERS[_rng.randi() % POLICE_CHARACTERS.size()],
		Color(0.06, 0.07, 0.09) if kind == "swat" else Color(0, 0, 0, 0))
	if tc == null:
		return
	tc.chase = Game.player
	units.append({"car": tc, "kind": kind, "crew": false})


## Police cars close in on the player; once near and the player is on foot (or stopped), the crew gets out.
func _chase_units(p: Player, at: Vector3) -> void:
	for u: Dictionary in units:
		var tc: TrafficManager.TrafficCar = u.car
		if u.crew:
			continue
		var d := tc.v.global_position.distance_to(at)
		var player_slow := p.vehicle == null or p.vehicle.linear_velocity.length() < 3.0
		if d < 22.0 and player_slow and tc.v.linear_velocity.length() < 4.0:
			u.crew = true
			traffic.park(tc)
			var n := 2 if u.kind == "police" else 4
			for i in n:
				var c := _make_cop("pistol" if u.kind == "police" and stars < 3 else ("smg" if u.kind == "police" else "rifle"))
				Game.world.add_child(c)
				var side := tc.v.global_basis.x * (1.5 + tc.v._bounds.size.x * 0.5) * (-1.0 if i % 2 == 0 else 1.0)
				c.global_position = tc.v.global_position + side + tc.v.global_basis.z * (i / 2) * 1.2 + Vector3(0, 0.2, 0)


## Two police cars parked across the road ahead of the player, officers behind them.
func _place_roadblock(p: Player) -> void:
	var v := p.vehicle
	var ahead := v.global_position + v.linear_velocity.normalized() * 110.0
	var tl := traffic.nearest_lane(ahead)
	if tl[0] < 0 or float(tl[2]) > 12.0:
		return
	var at: Array = traffic.graph.sample(int(tl[0]), float(tl[1]))
	var pos: Vector3 = at[0]
	var dir: Vector3 = at[1]
	var cam := get_viewport().get_camera_3d()
	if cam and cam.is_position_in_frustum(pos) and cam.global_position.distance_to(pos) < 90.0:
		return
	var right := Vector3(-dir.z, 0, dir.x)
	for k: float in [-1.0, 1.0]:
		var car := Vehicle.new()
		car.model = "police"
		car.position = pos + right * k * 2.3 + Vector3(0, 0.6, 0)
		car.rotation.y = atan2(-right.x, -right.z) + (0.25 if k > 0 else -0.25)
		Game.world.add_child(car)
		car.set_siren(true)
		roadblocks.append(car)
	for i in 2:
		var c := _make_cop("smg" if stars >= 4 else "pistol")
		Game.world.add_child(c)
		c.global_position = pos - dir * 3.0 + right * (i * 2.0 - 1.0) * 2.0 + Vector3(0, 0.2, 0)


# --- helicopter -----------------------------------------------------------------

func _spawn_heli(at: Vector3) -> void:
	var h := Helicopter.new()
	h.model = "heli"
	var dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	h.position = at + dir * 160.0 + Vector3(0, 60.0, 0)
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
	if h.has_meta("leave") or stars < 4:
		want = h.global_position + (h.global_position - target).normalized() * 50.0 + Vector3(0, 20, 0)
		if h.global_position.distance_to(target) > 300.0:
			h.queue_free()
			heli = null
			return
	var to := want - h.global_position
	var flat := Vector3(to.x, 0, to.z)
	var fwd := -h.global_basis.z
	fwd.y = 0.0
	var face := (Vector3(target.x, 0, target.z) - Vector3(h.global_position.x, 0, h.global_position.z))
	var yaw_err := fwd.normalized().signed_angle_to(face.normalized() if face.length() > 1.0 else fwd.normalized(), Vector3.UP)
	h.ai_steer = clampf(yaw_err * 1.5, -1.0, 1.0)
	var along := flat.dot(fwd.normalized())
	var vel_along := h.linear_velocity.dot(fwd.normalized())
	h.ai_throttle = clampf((along - 8.0) * 0.04 - vel_along * 0.06, -1.0, 1.0)
	h.ai_lift = clampf(to.y * 0.15 - h.linear_velocity.y * 0.3, -1.0, 1.0)
