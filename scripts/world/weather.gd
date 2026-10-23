class_name Weather
extends Node3D
## Weather states that drift into each other: cloud cover, overcast dimming, fog, rain (particles that stop on
## roofs via a heightfield collider following the camera), wet streets that dry slowly, lightning in storms.

enum Kind { CLEAR, CLOUDY, OVERCAST, RAIN, STORM, FOG }
const NAMES := ["Clear", "Cloudy", "Overcast", "Rain", "Storm", "Fog"]
## kind -> [cloud coverage, cloud darkness, rain, fog, sun dimming]
const PRESETS := {
	Kind.CLEAR: [0.18, 0.0, 0.0, 0.0, 0.0],
	Kind.CLOUDY: [0.5, 0.15, 0.0, 0.05, 0.15],
	Kind.OVERCAST: [0.85, 0.55, 0.0, 0.15, 0.55],
	Kind.RAIN: [0.92, 0.7, 0.7, 0.3, 0.7],
	Kind.STORM: [0.98, 0.85, 1.0, 0.4, 0.8],
	Kind.FOG: [0.6, 0.3, 0.0, 1.0, 0.45],
}
## Which weather tends to follow which (weights).
const NEXT := {
	Kind.CLEAR: {Kind.CLEAR: 3, Kind.CLOUDY: 3, Kind.FOG: 1},
	Kind.CLOUDY: {Kind.CLEAR: 3, Kind.CLOUDY: 1, Kind.OVERCAST: 2},
	Kind.OVERCAST: {Kind.CLOUDY: 2, Kind.RAIN: 3, Kind.OVERCAST: 1},
	Kind.RAIN: {Kind.OVERCAST: 2, Kind.STORM: 1, Kind.CLOUDY: 2},
	Kind.STORM: {Kind.RAIN: 2, Kind.OVERCAST: 1},
	Kind.FOG: {Kind.CLEAR: 2, Kind.CLOUDY: 2},
}

var kind := Kind.CLEAR
var coverage := 0.18
var cloud_dark := 0.0
var rain := 0.0
var fog := 0.0
var dim := 0.0
var wetness := 0.0
var flash := 0.0
var auto_change := true
var _target: Array = PRESETS[Kind.CLEAR]
var _timer := 300.0
var _flash_timer := 8.0
var _rain: GPUParticles3D
var _rain_sound: AudioStreamPlayer
var _collider: GPUParticlesCollisionHeightField3D


func _ready() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 9000
	_rain.lifetime = 1.6
	_rain.visibility_aabb = AABB(Vector3(-30, -40, -30), Vector3(60, 60, 60))
	_rain.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 1, 28)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 2.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.88, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	_rain.draw_pass_1 = q
	add_child(_rain)
	_collider = GPUParticlesCollisionHeightField3D.new()
	_collider.size = Vector3(64, 80, 64)
	_collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_collider.follow_camera_enabled = true
	add_child(_collider)


## Change weather; instant skips the transition (menus, tests, the owner's debug key).
func set_weather(k: int, instant := false) -> void:
	kind = k
	_target = PRESETS[k]
	_timer = randf_range(240.0, 600.0)
	if instant:
		coverage = _target[0]
		cloud_dark = _target[1]
		rain = _target[2]
		fog = _target[3]
		dim = _target[4]
		wetness = 1.0 if rain > 0.3 else 0.0


func _process(delta: float) -> void:
	if auto_change:
		_timer -= delta
		if _timer <= 0.0:
			set_weather(_pick(NEXT[kind]))
	var k := 1.0 - exp(-delta / 25.0)  # ~25 s transitions
	coverage = lerpf(coverage, _target[0], k)
	cloud_dark = lerpf(cloud_dark, _target[1], k)
	rain = move_toward(rain, _target[2], delta / 20.0)
	fog = lerpf(fog, _target[3], k)
	dim = lerpf(dim, _target[4], k)
	# streets wet quickly in rain, dry over a couple of minutes
	wetness = move_toward(wetness, 1.0 if rain > 0.15 else 0.0, delta / (12.0 if rain > 0.15 else 150.0))
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	var cam := get_viewport().get_camera_3d()
	if cam:
		_rain.global_position = cam.global_position + Vector3(0, 16, 0)
	_rain.emitting = rain > 0.03
	_rain.amount_ratio = clampf(rain, 0.0, 1.0)
	# rain ambience: fades in with the shower
	if rain > 0.02:
		if _rain_sound == null:
			_rain_sound = AudioStreamPlayer.new()
			_rain_sound.stream = Audio.stream("world/rain_loop.ogg", true)
			_rain_sound.bus = &"Ambience"
			add_child(_rain_sound)
		if not _rain_sound.playing:
			_rain_sound.play(randf() * 30.0)
		_rain_sound.volume_db = linear_to_db(clampf(rain, 0.0, 1.0)) - 2.0
	elif _rain_sound and _rain_sound.playing:
		_rain_sound.stop()
	# lightning
	flash = move_toward(flash, 0.0, delta * 6.0)
	if kind == Kind.STORM and rain > 0.6:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = randf_range(6.0, 20.0)
			flash = 1.0


static func _pick(weights: Dictionary) -> int:
	var total := 0
	for w: int in weights.values():
		total += w
	var r := randi() % total
	for k: int in weights:
		r -= weights[k]
		if r < 0:
			return k
	return Kind.CLEAR
