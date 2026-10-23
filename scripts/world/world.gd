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
var data: WorldData
var terrain: Terrain
var ocean: Ocean
var city: City
var player: Player


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
	if Game.benchmark_mode:
		time_scale = 0.0
		weather.auto_change = false
	var spawn := Vector3(26.0, CityCell.CURB_H + 0.05, 9.0)
	warm_up(spawn)
	_spawn_vehicles()
	player = PLAYER_SCENE.instantiate()
	player.position = spawn
	player.rotation.y = deg_to_rad(90)
	add_child(player)
	var hud: CanvasLayer = preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
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


func _spawn_vehicles() -> void:
	var spots := [
		["sedan", Vector3(22.0, 0.6, 5.2), -PI * 0.5],
		["sport", Vector3(34.0, 0.6, 5.2), -PI * 0.5],
		["suv", Vector3(-24.0, 0.6, -5.2), PI * 0.5],
		["hatchback", Vector3(5.2, 0.6, 30.0), PI],
		["pickup", Vector3(-5.2, 0.6, -36.0), 0.0],
		["compact", Vector3(46.0, 0.6, -5.2), PI * 0.5],
	]
	var names := {"sedan": "Calder Sedan", "sport": "Kestrel GT", "suv": "Vireo Ranger", "hatchback": "Solano Hatch",
		"pickup": "Hauler 1500", "compact": "Minnow"}
	for s in spots:
		var v := Vehicle.new()
		v.model = s[0]
		v.display_name = names[s[0]]
		v.position = s[1]
		v.rotation.y = s[2]
		add_child(v)


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


## What the streaming follows: the active camera (works for gameplay, menu orbit and the benchmark flight).
func focus_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if player and (not cam or cam == player.cam.camera):
		return player.vehicle.global_position if player.vehicle else player.global_position
	return cam.global_position if cam else Vector3.ZERO


func _process(delta: float) -> void:
	var f := focus_point()
	terrain.update(f)
	city.update(f)
	var cam := get_viewport().get_camera_3d()
	ocean.follow(cam.global_position if cam else f)
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
	var night := 1.0 - day
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
	sky_mat.set_shader_parameter("exposure", lerpf(1.0, 0.35, night) + flash * 3.0)
	env.ambient_light_energy = lerpf(0.35, 1.0, day) * (1.0 - dim * 0.25) + flash * 2.0
	env.volumetric_fog_albedo = Color(0.92, 0.9, 0.86).lerp(Color(1.0, 0.82, 0.64), low * 0.6)
	env.volumetric_fog_density = 0.002 + fogw * 0.02 + (w.rain if w else 0.0) * 0.006
	env.fog_density = 0.6 + fogw * 2.5
	env.fog_depth_end = lerpf(1400.0, 380.0, fogw)
	env.fog_light_color = Color(0.7, 0.76, 0.86).lerp(Color(0.95, 0.78, 0.62), low * 0.5).lerp(grey, dim).lerp(Color(0.04, 0.05, 0.09), night)
	if street_lights:
		street_lights.night = maxf(night, clampf((dim - 0.6) * 1.5, 0.0, 0.5))
