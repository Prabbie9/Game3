class_name GraphicsSettings
extends RefCounted
## Graphics presets (Low/Medium/High/Ultra) + individual toggles, persisted to user://settings.cfg.

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }
const PRESET_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]
const PATH := "user://settings.cfg"

const PRESETS := {
	Preset.LOW: {"ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "volumetric_fog": false, "glow": true,
		"shadow_size": 2048, "shadow_filter": 1, "shadow_distance": 140.0, "render_scale": 0.77, "upscaler": "fsr1",
		"taa": false, "fxaa": true, "lod_threshold": 4.0, "foliage_density": 0.5},
	Preset.MEDIUM: {"ssao": true, "ssil": false, "ssr": false, "sdfgi": false, "volumetric_fog": true, "glow": true,
		"shadow_size": 2048, "shadow_filter": 2, "shadow_distance": 200.0, "render_scale": 1.0, "upscaler": "none",
		"taa": true, "fxaa": false, "lod_threshold": 2.0, "foliage_density": 0.75},
	Preset.HIGH: {"ssao": true, "ssil": true, "ssr": true, "sdfgi": true, "volumetric_fog": true, "glow": true,
		"shadow_size": 4096, "shadow_filter": 3, "shadow_distance": 260.0, "render_scale": 1.0, "upscaler": "none",
		"taa": true, "fxaa": false, "lod_threshold": 1.0, "foliage_density": 1.0},
	Preset.ULTRA: {"ssao": true, "ssil": true, "ssr": true, "sdfgi": true, "volumetric_fog": true, "glow": true,
		"shadow_size": 8192, "shadow_filter": 4, "shadow_distance": 380.0, "render_scale": 1.0, "upscaler": "none",
		"taa": true, "fxaa": false, "lod_threshold": 0.6, "foliage_density": 1.25},
}

static var preset := Preset.HIGH
static var values: Dictionary = PRESETS[Preset.HIGH].duplicate()
static var display := {"fov": 70.0, "vsync": false, "max_fps": 0, "window_mode": "fullscreen"}
static var _loaded := false


## How many parked cars are kept around the player.
static func parked_cars() -> int:
	return [16, 22, 30, 38][mini(preset, 3)] if preset != Preset.CUSTOM else 30


## How many moving traffic cars are kept around the player.
static func traffic_cars() -> int:
	return [8, 12, 16, 22][mini(preset, 3)] if preset != Preset.CUSTOM else 16


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		preset = cf.get_value("graphics", "preset", Preset.HIGH)
		values = PRESETS.get(preset, PRESETS[Preset.HIGH]).duplicate()
		for k in values:
			values[k] = cf.get_value("graphics", k, values[k])
		for k in display:
			display[k] = cf.get_value("display", k, display[k])


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "preset", preset)
	for k in values:
		cf.set_value("graphics", k, values[k])
	for k in display:
		cf.set_value("display", k, display[k])
	cf.save(PATH)


static func set_preset(p: int) -> void:
	preset = p
	if PRESETS.has(p):
		values = PRESETS[p].duplicate()
	save()


static func apply_to(world: Node) -> void:
	ensure_loaded()
	var vp := world.get_viewport()
	vp.scaling_3d_scale = values.render_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if values.upscaler == "fsr1" else Viewport.SCALING_3D_MODE_BILINEAR
	vp.use_taa = values.taa
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if values.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = values.lod_threshold
	RenderingServer.directional_shadow_atlas_set_size(values.shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(values.shadow_filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(values.shadow_filter)
	if world is World:
		var env: Environment = world.env
		env.ssao_enabled = values.ssao
		env.ssil_enabled = values.ssil
		env.ssr_enabled = values.ssr
		env.sdfgi_enabled = values.sdfgi
		env.sdfgi_cascades = 6 if preset == Preset.ULTRA else 4
		env.volumetric_fog_enabled = values.volumetric_fog
		env.glow_enabled = values.glow
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if preset >= Preset.ULTRA else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50, 300)
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, preset < Preset.ULTRA, 0.5, 4, 50, 300)
		RenderingServer.environment_set_volumetric_fog_volume_size(96 if preset >= Preset.ULTRA else 64, 64 if preset >= Preset.ULTRA else 48)
		world.sun.directional_shadow_max_distance = values.shadow_distance
		# street lights that cast real light scale with the preset
		if world.street_lights:
			world.street_lights.set_count([12, 20, 32, 48][mini(preset, 3)])
		if world.get("parked"):
			world.parked.max_active = parked_cars()
	var cam := vp.get_camera_3d()
	if cam:
		cam.fov = display.fov
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if display.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(display.max_fps)
