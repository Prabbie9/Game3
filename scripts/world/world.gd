class_name World
extends Node3D
## Root of the playable world: environment/sky/sun, city, player, vehicles, HUD.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@export var time_of_day := 16.9  # hours
@export var time_scale := 0.0     # game hours per real second (M3: day/night cycle)

var env: Environment
var sun: DirectionalLight3D
var sky_mat: PhysicalSkyMaterial
var city: CityBuilder
var player: Player


func _ready() -> void:
	Game.world = self
	_build_environment()
	city = CityBuilder.new()
	city.name = "City"
	add_child(city)
	_spawn_vehicles()
	player = PLAYER_SCENE.instantiate()
	player.position = Vector3(26.0, CityBuilder.CURB_H + 0.05, 9.0)
	player.rotation.y = deg_to_rad(90)
	add_child(player)
	var hud: CanvasLayer = preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
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
	sky_mat = PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.2
	sky_mat.mie_coefficient = 0.006
	sky_mat.mie_eccentricity = 0.82
	sky_mat.turbidity = 9.0
	sky_mat.sun_disk_scale = 1.4
	sky_mat.ground_color = Color(0.35, 0.32, 0.3)
	sky_mat.energy_multiplier = 1.0
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
	env.volumetric_fog_density = 0.0035
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


func _process(delta: float) -> void:
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
	sky_mat.energy_multiplier = lerpf(0.05, 1.0, day)
	env.ambient_light_energy = lerpf(0.35, 1.0, day)
	env.volumetric_fog_albedo = Color(0.92, 0.9, 0.86).lerp(Color(1.0, 0.82, 0.64), low * 0.6)
	env.fog_light_color = Color(0.7, 0.76, 0.86).lerp(Color(0.95, 0.78, 0.62), low * 0.5).lerp(Color(0.04, 0.05, 0.09), night)
