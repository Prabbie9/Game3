class_name World
extends Node3D
## Root of the playable world: environment/sky/sun, city, player, vehicles, HUD.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@export var time_of_day := 16.9  # hours
@export var time_scale := 1.0 / 120.0  # game hours per real second: a full day takes 48 minutes

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var weather: Weather
var street_lights: LightPool
var full_map: FullMap
var night := 0.0  # 0 day .. 1 night (from the sun)
var data: WorldData
var terrain: Terrain
var ocean: Ocean
var city: City
var player: Player
var parked: ParkedCars
var traffic: TrafficManager
var population: Population
var game_over: GameOver
var wanted: Wanted
var hospital: Storefront
var police_station: Storefront
var safehouse: Safehouse
var collectibles: Collectibles
var birds: Birds
var aircraft: Aircraft
var ambience: Ambience
var radio: Radio
var diner: Diner


func _ready() -> void:
	Game.world = self
	_build_environment()
	data = WorldData.get_data()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	ocean = Ocean.new()
	ocean.name = "Ocean"
	add_child(ocean)
	ocean.setup(data.sea, data.half)
	city = City.new()
	city.name = "City"
	add_child(city)
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	street_lights = LightPool.new()
	street_lights.name = "StreetLights"
	add_child(street_lights)
	street_lights.setup(city, 32)
	var marks := SkidMarks.new()
	marks.name = "SkidMarks"
	add_child(marks)
	if Game.benchmark_mode:
		time_scale = 0.0
		weather.auto_change = false
	var spawn := Vector3(26.0, CityCell.CURB_H + 0.05, 9.0)
	parked = ParkedCars.new()
	parked.name = "ParkedCars"
	add_child(parked)
	parked.setup(data, city.net)
	parked.warm_models()
	parked.max_active = GraphicsSettings.parked_cars()
	warm_up(spawn)
	_spawn_vehicles()
	_spawn_places()
	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	add_child(traffic)
	population = Population.new()
	population.name = "Population"
	add_child(population)
	population.traffic = traffic
	var props := PropWorld.new()
	props.name = "Props"
	add_child(props)
	wanted = Wanted.new()
	wanted.name = "Wanted"
	wanted.traffic = traffic
	add_child(wanted)
	player = PLAYER_SCENE.instantiate()
	player.position = spawn
	player.rotation.y = deg_to_rad(90)
	add_child(player)
	radio = Radio.new()
	radio.name = "Radio"
	add_child(radio)
	var hud: CanvasLayer = preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
	var wheel := WeaponWheel.new()
	wheel.name = "WeaponWheel"
	add_child(wheel)
	full_map = FullMap.new()
	full_map.name = "FullMap"
	add_child(full_map)
	var perf: CanvasLayer = preload("res://scripts/ui/perf_overlay.gd").new()
	perf.name = "PerfOverlay"
	add_child(perf)
	if Game.benchmark_mode:
		add_child(preload("res://scripts/core/benchmark.gd").new())
	GraphicsSettings.apply_to(self)
	_update_sun()
	if not Game.pending_load.is_empty():
		# a save being loaded: after the first frame, when the player and streaming are up
		var d: Dictionary = Game.pending_load
		Game.pending_load = {}
		(func(): SaveGame.apply(d)).call_deferred()


## Hand-placed places and things: the gun shop, weapon/health/armour/cash pickups around the map, and a
## few people hanging around the plaza.
func _spawn_places() -> void:
	var shop := GunShop.new()
	shop.name = "GunShop"
	add_child(shop)
	police_station = Storefront.new()
	police_station.name = "PoliceStation"
	police_station.rect = Rect2(-66.0, -26.0, 20.0, 14.0)
	police_station.front = 1
	police_station.sign_text = "POLICE"
	police_station.sign_color = Color(0.5, 0.7, 1.0)
	police_station.wall = "concrete_tile_facade"
	add_child(police_station)
	hospital = Storefront.new()
	hospital.name = "Hospital"
	hospital.rect = Rect2(92.0, 12.0, 24.0, 14.0)
	hospital.front = -1
	hospital.sign_text = "SOLANO GENERAL  +"
	hospital.sign_color = Color(1.0, 0.35, 0.35)
	hospital.wall = "white_stucco"
	add_child(hospital)
	# the player's safehouse across the avenue and the diner behind the start, both facing 6th Ave
	safehouse = Safehouse.new()
	safehouse.name = "Safehouse"
	safehouse.position = Vector3(-24.75, 0, 12.6)
	safehouse.rotation.y = PI
	add_child(safehouse)
	diner = Diner.new()
	diner.name = "Diner"
	diner.position = Vector3(24.75, 0, 12.6)
	diner.rotation.y = PI
	add_child(diner)
	if Game.pending_load.is_empty():
		Game.new_career()
	collectibles = Collectibles.new()
	collectibles.name = "Collectibles"
	add_child(collectibles)
	birds = Birds.new()
	birds.name = "Birds"
	add_child(birds)
	aircraft = Aircraft.new()
	aircraft.name = "Aircraft"
	add_child(aircraft)
	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	var respray := Respray.new()
	respray.name = "Respray"
	respray.rect = Rect2(95.0, -28.0, 14.0, 16.0)
	respray.front = 1
	add_child(respray)
	game_over = GameOver.new()
	game_over.name = "GameOver"
	add_child(game_over)
	var W := Pickup.Kind.WEAPON
	var spots := [
		[W, "smg", Vector3(40.5, 0, 57.0)], [W, "bat", Vector3(128.0, 0, -112.0)], [W, "knife", Vector3(-850.0, 0, -706.0)],
		[W, "shotgun", Vector3(-265.0, 0, -447.0)], [W, "rifle", Vector3(175.0, 0, 735.0)], [W, "sniper", Vector3(846.0, 0, -846.0)],
		[W, "launcher", Vector3(-1045.0, 0, 2.0)], [W, "grenade", Vector3(-120.0, 0, 524.0)],
		[Pickup.Kind.HEALTH, "", Vector3(-189.0, 0, 209.0)], [Pickup.Kind.HEALTH, "", Vector3(-15.0, 0, 15.0)],
		[Pickup.Kind.HEALTH, "", Vector3(600.0, 0, 700.0)], [Pickup.Kind.ARMOR, "", Vector3(40.5, 0, -57.0)],
		[Pickup.Kind.ARMOR, "", Vector3(150.0, 0, -420.0)], [Pickup.Kind.CASH, "", Vector3(-40.5, 0, -57.0)],
		[Pickup.Kind.CASH, "", Vector3(-120.5, 0, 57.0)], [Pickup.Kind.CASH, "", Vector3(120.5, 0, 120.0)],
		[Pickup.Kind.CASH, "", Vector3(-760.0, 0, -620.0)], [Pickup.Kind.CASH, "", Vector3(520.0, 0, -690.0)],
	]
	for sp: Array in spots:
		var pk := Pickup.make(sp[0], sp[1], 250 if sp[0] == Pickup.Kind.CASH else 0)
		var at: Vector3 = sp[2]
		at.y = data.height_at(at.x, at.z) + CityCell.CURB_H + 0.6
		pk.position = at
		add_child(pk)
	_plaza_people = [[Vector3(-30.0, 0, 9.0), PI * 0.5, "ch02_nonpbr"], [Vector3(-31.2, 0, 8.6), -PI * 0.5, "ch33_nonpbr"],
		[Vector3(-52.0, 0, 9.2), 0.3, "ch21_nonpbr"]]


var _plaza_people := []


## Where the player comes round: "hospital" (wasted) or "police" (busted).
## "6th Ave" (the street at pos) or the district name, for radio chatter and saves.
func place_name(pos: Vector3) -> String:
	if traffic:
		var nl := traffic.nearest_lane(pos)
		if int(nl[0]) >= 0 and float(nl[2]) < 18.0:
			var rd: Dictionary = data.roads[int(traffic.graph.lanes[int(nl[0])].road)]
			if String(rd.get("name", "")) != "":
				return String(rd.name)
	return SaveGame.district_at(pos)


## Places shown on the minimap and the map: [world x/z, letter, colour, name].
func places() -> Array:
	var out := [[Vector2(-24.75, 19.0), "S", UITheme.SAND, "Safehouse"], [Vector2(23.0, -18.0), "G", UITheme.CORAL, "Gun shop"],
		[Vector2(24.75, 18.5), "D", Color(1.0, 0.45, 0.4), "Diner"], [Vector2(102.0, -20.0), "R", UITheme.TEAL, "Respray"]]
	if hospital:
		out.append([hospital.rect.get_center(), "H", Color(0.9, 0.3, 0.32), "Hospital"])
	if police_station:
		out.append([police_station.rect.get_center(), "P", Color(0.35, 0.55, 0.95), "Police"])
	return out


func respawn_point(kind: String) -> Transform3D:
	var b := hospital if kind == "hospital" else police_station
	return b.entrance() if b else player.spawn_point


## The plaza regulars appear once their characters have finished loading in the background.
func _place_people() -> void:
	for i in range(_plaza_people.size() - 1, -1, -1):
		var e: Array = _plaza_people[i]
		if not NPCDriver.is_ready(e[2]):
			continue
		var ped := Pedestrian.new()
		ped.character_file = e[2]
		ped.position = Vector3(e[0].x, CityCell.CURB_H + 0.02, e[0].z)
		ped.rotation.y = e[1]
		add_child(ped)
		_plaza_people.remove_at(i)


func _spawn_vehicles() -> void:
	# parked at the kerb of the streets round the start (not in the avenue's lanes, where traffic would have
	# to go round them): Grand St to the east, 7th St to the north, 5th St to the south
	var spots := [
		["sedan", Vector3(75.2, 0.6, 36.0), PI], ["sport", Vector3(75.2, 0.6, 46.0), PI],
		["muscle", Vector3(75.2, 0.6, -34.0), PI], ["pickup", Vector3(84.8, 0.6, 30.0), 0.0],
		["police", Vector3(-30.0, 0.6, 75.2), PI * 0.5], ["ambulance", Vector3(-48.0, 0.6, 75.2), PI * 0.5],
		["firetruck", Vector3(-30.0, 0.6, 84.8), -PI * 0.5], ["bus", Vector3(30.0, 0.6, 74.7), PI * 0.5],
		["hatchback", Vector3(30.0, 0.6, -75.2), -PI * 0.5], ["compact", Vector3(44.0, 0.6, -75.2), -PI * 0.5],
		["suv", Vector3(-30.0, 0.6, -75.2), -PI * 0.5],
	]
	for s in spots:
		parked.reserve_area(s[1], 7.0 if s[0] != "bus" else 9.0)
		var v := Vehicle.new()
		v.model = s[0]
		v.position = s[1]
		v.rotation.y = s[2]
		add_child(v)
	# a dirt bike and a bicycle on the pavement by the start
	for b: Array in [["dirtbike", Vector3(30.0, CityCell.CURB_H + 0.05, 9.4), PI * 0.5], ["bicycle", Vector3(19.0, CityCell.CURB_H + 0.05, 9.4), PI * 0.5]]:
		var bike := Bike.new()
		bike.model = b[0]
		bike.position = b[1]
		bike.rotation.y = b[2]
		add_child(bike)
	# a police helicopter at the end of the south car park, a speedboat moored beside the pier
	var pad := Vector3(215.0, 0.0, -447.0)
	pad.y = data.height_at(pad.x, pad.z) + CityCell.CURB_H + 0.05
	parked.reserve_area(pad, 9.0)
	var heli := Helicopter.new()
	heli.position = pad
	heli.rotation.y = PI * 0.5
	add_child(heli)
	var boat := Boat.new()
	boat.position = Vector3(-1020.0, data.sea - 0.5, 15.0)
	boat.rotation.y = PI * 0.5
	add_child(boat)


func _build_environment() -> void:
	env = Environment.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://assets/shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.8
	env.ssil_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_energy = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.72, 0.76, 0.84)
	env.fog_density = 0.6
	env.fog_depth_begin = 120.0
	env.fog_depth_end = 1400.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.6
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.002
	env.volumetric_fog_albedo = Color(0.92, 0.9, 0.86)
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	var attrs := CameraAttributesPractical.new()
	attrs.auto_exposure_enabled = true
	attrs.auto_exposure_scale = 0.35
	attrs.auto_exposure_min_sensitivity = 60.0
	attrs.auto_exposure_max_sensitivity = 800.0
	attrs.auto_exposure_speed = 0.8
	we.camera_attributes = attrs
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)


## Streams terrain and city detail around `focus` and blocks until it's all in place (loading, teleports).
func warm_up(focus: Vector3) -> void:
	terrain.update(focus)
	for i in 600:
		city.update(focus)
		terrain.update(focus)
		if city.is_settled() and terrain.is_settled():
			break
		OS.delay_msec(10)
	city.flush()
	if parked:
		parked.request_fill()


var _freeze_timer := 0.0


## Vehicles beyond the streamed collision would fall through the world: park them (frozen) until we come back.
func _freeze_far_vehicles(f: Vector3) -> void:
	for v: Node in get_tree().get_nodes_in_group("vehicles"):
		var rb := v as RigidBody3D
		# (an AI helicopter needs no ground under it)
		if rb == null or (player and player.vehicle == rb) or (rb is Helicopter and (rb as Helicopter).ai_drive):
			if rb:
				rb.freeze = false
			continue
		var far := rb.global_position.distance_to(f) > 180.0
		if far != rb.freeze:
			if far:
				rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rb.freeze = far


## What the streaming follows: the active camera (works for gameplay, menu orbit and the benchmark flight).
func focus_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if player and (not cam or cam == player.cam.camera):
		return player.vehicle.global_position if player.vehicle else player.global_position
	return cam.global_position if cam else Vector3.ZERO


func _process(delta: float) -> void:
	if not _plaza_people.is_empty():
		_place_people()
	var f := focus_point()
	# whatever the camera does, the ground under the player stays solid
	var a := player.global_position if player else Vector3.INF
	terrain.anchor = a
	city.anchor = a
	terrain.update(f)
	city.update(f)
	var cam := get_viewport().get_camera_3d()
	ocean.follow(cam.global_position if cam else f)
	_freeze_timer -= delta
	if _freeze_timer <= 0.0:
		_freeze_timer = 0.5
		_freeze_far_vehicles(f)
	if time_scale > 0.0:
		time_of_day = fmod(time_of_day + delta * time_scale, 24.0)
	_update_sun()


## Sun path for a sunny coastal latitude; warm low sun at the ends of the day, moonlight at night.
func _update_sun() -> void:
	var ang := (time_of_day - 6.0) / 24.0 * TAU  # 0 = sunrise, PI/2 = noon, PI = sunset
	var elevation := sin(ang) * deg_to_rad(70.0)
	var azimuth := lerpf(deg_to_rad(-100.0), deg_to_rad(100.0), clampf(ang / PI, 0.0, 1.0))
	var day := smoothstep(deg_to_rad(-6.0), deg_to_rad(4.0), elevation)
	var low := 1.0 - clampf(elevation / deg_to_rad(25.0), 0.0, 1.0)
	if elevation > deg_to_rad(-1.5):
		sun.rotation = Vector3(-maxf(elevation, deg_to_rad(1.5)), azimuth + PI, 0)
		sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.7, 0.45), low * 0.8)
		sun.light_energy = lerpf(0.4, 1.6, smoothstep(0.0, deg_to_rad(20.0), elevation))
		sun.shadow_enabled = true
	else:
		# moonlight: cool, dim
		sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0)
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = 0.1
	night = 1.0 - day
	RenderingServer.global_shader_parameter_set("night", night)
	var w := weather
	var dim := w.dim if w else 0.0
	var fogw := w.fog if w else 0.0
	var flash := w.flash if w else 0.0
	sun.light_energy *= 1.0 - dim * 0.7
	sun.shadow_opacity = 1.0 - dim * 0.6
	# sky colours: day blue -> warm low sun -> night, greyed by cloud
	var zen := Color(0.2, 0.4, 0.76).lerp(Color(0.24, 0.3, 0.52), low * 0.7).lerp(Color(0.012, 0.018, 0.04), night)
	var hor := Color(0.66, 0.77, 0.9).lerp(Color(0.98, 0.62, 0.38), low * 0.85).lerp(Color(0.045, 0.055, 0.09), night)
	var grey := Color(0.56, 0.59, 0.63) * lerpf(1.0, 0.08, night)
	zen = zen.lerp(grey * 0.9, dim)
	hor = hor.lerp(grey, dim)
	sky_mat.set_shader_parameter("zenith", zen)
	sky_mat.set_shader_parameter("horizon", hor)
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("coverage", w.coverage if w else 0.2)
	sky_mat.set_shader_parameter("cloud_dark", w.cloud_dark if w else 0.0)
	sky_mat.set_shader_parameter("exposure", lerpf(1.7, 0.4, night) * (1.0 - dim * 0.35) + flash * 3.0)
	env.ambient_light_energy = lerpf(0.35, 1.0, day) * (1.0 - dim * 0.25) + flash * 2.0
	env.volumetric_fog_albedo = Color(0.92, 0.9, 0.86).lerp(Color(1.0, 0.82, 0.64), low * 0.6)
	env.volumetric_fog_density = 0.002 + fogw * 0.02 + (w.rain if w else 0.0) * 0.006
	env.fog_density = 0.6 + fogw * 2.5
	env.fog_depth_end = lerpf(1400.0, 380.0, fogw)
	env.fog_light_color = Color(0.7, 0.76, 0.86).lerp(Color(0.95, 0.78, 0.62), low * 0.5).lerp(grey, dim).lerp(Color(0.04, 0.05, 0.09), night)
	if street_lights:
		street_lights.night = maxf(night, clampf((dim - 0.6) * 1.5, 0.0, 0.5))
