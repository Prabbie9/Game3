class_name HydrantJet
extends Node3D
## A burst hydrant: a column of water for half a minute, with its roar; cars caught in it get lifted (the
## classic). Made by PropWorld when a hydrant is knocked off.

const LIFE := 32.0
var _t := 0.0
var _jet: GPUParticles3D
var _splash: GPUParticles3D
var _snd: AudioStreamPlayer3D
static var _mat: StandardMaterial3D


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_texture = Vehicle._soft_dot()
		_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.55)
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_mat.vertex_color_use_as_albedo = true
	_jet = _emitter(260, 1.5, Vector3.UP, 4.0, 10.0, 12.5, Vector2(0.35, 0.35))
	_jet.position.y = 0.6
	_splash = _emitter(120, 0.9, Vector3.UP, 70.0, 2.0, 4.0, Vector2(0.5, 0.5))
	_splash.position.y = 0.2
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = Audio.stream("world/water_jet.ogg", true)
	_snd.bus = &"Ambience"
	_snd.unit_size = 8.0
	_snd.max_distance = 70.0
	add_child(_snd)
	_snd.play()
	Audio.play_at(Audio.stream("player/splash.ogg"), global_position + Vector3(0, 1, 0), 0.0, 0.8)


func _emitter(amount: int, life: float, dir: Vector3, spread: float, vmin: float, vmax: float, size: Vector2) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.amount = amount
	e.lifetime = life
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	e.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	q.material = _mat
	e.draw_pass_1 = q
	e.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 16, 8))
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(e)
	return e


func _physics_process(delta: float) -> void:
	_t += delta
	var k := clampf((LIFE - _t) / 4.0, 0.0, 1.0)   # fades out over the last seconds
	if k <= 0.0:
		queue_free()
		return
	_jet.amount_ratio = k
	_splash.amount_ratio = k
	_snd.volume_db = linear_to_db(maxf(k, 0.01))
	# lift whatever vehicle sits in the column
	for n: Node in get_tree().get_nodes_in_group("vehicles"):
		var v := n as RigidBody3D
		if v == null or v.freeze:
			continue
		var rel := v.global_position - global_position
		if Vector2(rel.x, rel.z).length() < 1.6 and rel.y < 9.0 and rel.y > -1.0:
			v.sleeping = false
			v.apply_central_force(Vector3.UP * v.mass * 16.0 * k * clampf(1.0 - rel.y / 9.0, 0.2, 1.0))
