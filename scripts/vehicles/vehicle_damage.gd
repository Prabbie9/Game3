class_name VehicleDamage
extends Node3D
## Crash damage for a Vehicle: engine health, body dents (shader-driven, see car_dents.gdshaderinc), cracked
## glass, smashed lamps, engine smoke that thickens as health drops, fire, and finally an explosion that leaves a
## burnt-out wreck. Everything here is created lazily: an undamaged car carries only this empty node.

signal destroyed

const MAX_HEALTH := 1000.0
const SMOKE_AT := 450.0
const BLACK_AT := 200.0
const BURN_TIME := 7.0         # seconds on fire before it blows
const MAX_PUSH := 0.45         # deepest dent (m)

var vehicle: Vehicle
var health := MAX_HEALTH
var on_fire := false
var wrecked := false
var lamps_broken := {"front": Vector2.ZERO, "rear": Vector2.ZERO}
var materials: Array[ShaderMaterial] = []   # every material that bends with the dents
var glass: Array[ShaderMaterial] = []
var _dents: Array = []        # [Vector3 centre, float radius, Vector3 push]
var _glass_hits: Array = []
var _burn := 0.0
var _upside := 0.0
var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _fire_light: OmniLight3D
var _fire_sound: AudioStreamPlayer3D
var _engine_pos := Vector3.ZERO
var _cool := 0.0


func setup(v: Vehicle, aabb: AABB) -> void:
	vehicle = v
	_engine_pos = Vector3(0, aabb.position.y + aabb.size.y * 0.55, aabb.position.z + aabb.size.z * 0.18)


func health_fraction() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)


## A collision: `point` and `push` (inward displacement direction × strength) in the car frame, `strength` in m/s
## of velocity change.
func hit(point: Vector3, push: Vector3, strength: float) -> void:
	if strength < 3.0:
		return
	var dmg := pow(strength - 3.0, 1.5) * 9.0
	_damage(dmg)
	var size := vehicle._size
	var depth := clampf((strength - 3.0) * 0.026, 0.0, MAX_PUSH)
	var radius := clampf(0.5 + strength * 0.05, 0.6, 1.4)
	_add_dent(point, push.normalized() * depth, radius)
	# lamps at that corner
	var front := point.z < -size.z * 0.3
	var rear := point.z > size.z * 0.3
	if strength > 7.0 and (front or rear):
		var k := "front" if front else "rear"
		var b: Vector2 = lamps_broken[k]
		if point.x < size.x * 0.2:
			b.x = 1.0
		if point.x > -size.x * 0.2:
			b.y = 1.0
		if b != lamps_broken[k]:
			lamps_broken[k] = b
			vehicle._on_lamps_broken()
	# glass near the hit cracks
	if strength > 9.0:
		_crack(point, clampf(0.5 + strength * 0.06, 0.6, 1.6))
		if randf() < 0.5:
			Audio.play_at(Audio.pick("vehicles/glass_%d.ogg", 2), vehicle.global_transform * point, -4.0, randf_range(0.9, 1.1))


## Bullet: small engine damage, cracks the glass it hits, breaks a lamp it hits.
func bullet(point: Vector3, damage: float) -> void:
	_damage(damage * 1.6)
	var size := vehicle._size
	_crack(point, 0.35)
	if absf(point.z) > size.z * 0.42 and point.y < size.y * 0.6:
		var k := "front" if point.z < 0.0 else "rear"
		var b: Vector2 = lamps_broken[k]
		if point.x < 0.0:
			b.x = 1.0
		else:
			b.y = 1.0
		lamps_broken[k] = b
		vehicle._on_lamps_broken()


func _damage(amount: float) -> void:
	if wrecked:
		return
	health = maxf(health - amount, 0.0)
	_update_smoke()
	if health <= 0.0 and not on_fire:
		_ignite()


func _add_dent(c: Vector3, push: Vector3, r: float) -> void:
	# deepen a nearby dent rather than stacking a new one on top
	for d: Array in _dents:
		if (d[0] as Vector3).distance_to(c) < r * 0.6:
			var p: Vector3 = d[2] + push * 0.7
			if p.length() > MAX_PUSH:
				p = p.normalized() * MAX_PUSH
			d[2] = p
			d[1] = maxf(d[1], r)
			_upload_dents()
			return
	if _dents.size() >= 8:
		# replace the shallowest
		var low := 0
		for i in _dents.size():
			if (_dents[i][2] as Vector3).length() < (_dents[low][2] as Vector3).length():
				low = i
		_dents.remove_at(low)
	_dents.append([c, r, push])
	_upload_dents()


func _upload_dents() -> void:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	a.resize(8)
	b.resize(8)
	for i in _dents.size():
		var c: Vector3 = _dents[i][0]
		var p: Vector3 = _dents[i][2]
		a[i] = Vector4(c.x, c.y, c.z, _dents[i][1])
		b[i] = Vector4(p.x, p.y, p.z, 0.0)
	for m in materials:
		m.set_shader_parameter("dents", a)
		m.set_shader_parameter("dent_push", b)


func _crack(point: Vector3, r: float) -> void:
	if glass.is_empty():
		return
	if _glass_hits.size() >= 4:
		_glass_hits.pop_front()
	_glass_hits.append(Vector4(point.x, point.y, point.z, r))
	var arr := PackedVector4Array()
	arr.resize(4)
	for i in _glass_hits.size():
		arr[i] = _glass_hits[i]
	for m in glass:
		m.set_shader_parameter("glass_hits", arr)


func _physics_process(delta: float) -> void:
	_cool -= delta
	if on_fire and not wrecked:
		_burn += delta
		if _fire_light:
			_fire_light.light_energy = 2.2 + sin(_burn * 23.0) * 0.5 + sin(_burn * 37.0) * 0.4
		# hurt whoever stands in the flames
		if Game.player and int(_burn * 4.0) != int((_burn - delta) * 4.0):
			var pl: Node3D = Game.player
			if pl.get("vehicle") != vehicle and pl.global_position.distance_to(vehicle.global_transform * _engine_pos) < 2.2:
				pl.take_damage(4.0, vehicle)
		if _burn > BURN_TIME:
			explode()
	elif not wrecked:
		# lying on its roof: the engine catches fire after a few seconds
		if vehicle.global_basis.y.y < -0.3 and vehicle.linear_velocity.length() < 1.0:
			_upside += delta
			if _upside > 3.0:
				_damage(health + 1.0)
		else:
			_upside = 0.0


func _update_smoke() -> void:
	if health >= SMOKE_AT:
		return
	if _smoke == null:
		_smoke = _make_smoke()
		_smoke.position = _engine_pos + Vector3(0, 0.1, 0)
		add_child(_smoke)
	var k := 1.0 - health / SMOKE_AT
	var pm := _smoke.process_material as ParticleProcessMaterial
	_smoke.amount_ratio = clampf(0.35 + k * 0.65, 0.0, 1.0)
	var dark := smoothstep(SMOKE_AT, BLACK_AT * 0.5, health)
	pm.color = Color(0.75, 0.75, 0.75, 0.32).lerp(Color(0.07, 0.07, 0.07, 0.7), dark)
	_smoke.emitting = true


func _ignite() -> void:
	on_fire = true
	_burn = 0.0
	_fire = _make_fire()
	_fire.position = _engine_pos
	add_child(_fire)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.55, 0.2)
	_fire_light.omni_range = 9.0
	_fire_light.light_energy = 2.2
	_fire_light.shadow_enabled = false
	_fire_light.position = _engine_pos + Vector3(0, 0.6, 0)
	add_child(_fire_light)
	_fire_sound = AudioStreamPlayer3D.new()
	_fire_sound.stream = Audio.stream("vehicles/fire_loop.ogg", true)
	_fire_sound.bus = &"SFX"
	_fire_sound.unit_size = 4.0
	_fire_sound.max_distance = 60.0
	_fire_sound.position = _engine_pos
	add_child(_fire_sound)
	_fire_sound.play()
	vehicle._on_engine_dead()


## Blow up: fireball, shock wave (pushes bodies, hurts people), the car hops and is left a charred wreck.
func explode() -> void:
	if wrecked:
		return
	wrecked = true
	on_fire = false
	health = 0.0
	var at := vehicle.global_transform * _engine_pos
	var scene := get_tree().current_scene if get_tree().current_scene else get_parent()
	Explosion.blast(scene, at, 9.0, 150.0, vehicle, vehicle)
	vehicle.sleeping = false
	vehicle.apply_impulse(Vector3.UP * vehicle.mass * 5.0, Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.6, 0.6)))
	# charred wreck, still smouldering
	for m in materials:
		m.set_shader_parameter("burnt", 1.0)
	for m in glass:
		m.set_shader_parameter("shatter", 1.0)
	if _fire:
		_fire.amount_ratio = 0.35
	if _fire_light:
		_fire_light.light_energy = 0.8
	if _fire_sound:
		_fire_sound.volume_db = -8.0
	health = 0.0
	if _smoke == null:
		_smoke = _make_smoke()
		_smoke.position = _engine_pos + Vector3(0, 0.1, 0)
		add_child(_smoke)
	(_smoke.process_material as ParticleProcessMaterial).color = Color(0.05, 0.05, 0.05, 0.75)
	_smoke.amount_ratio = 1.0
	_smoke.emitting = true
	destroyed.emit()
	vehicle._on_wrecked()
	# the flames die down after a while
	get_tree().create_timer(25.0).timeout.connect(func():
		if is_instance_valid(_fire):
			_fire.emitting = false
		if is_instance_valid(_fire_light):
			_fire_light.queue_free()
		if is_instance_valid(_fire_sound):
			_fire_sound.queue_free())


# ------------------------------------------------------------------------------------------------ effects

static var _smoke_mat: StandardMaterial3D
static var _fire_mat: StandardMaterial3D


static func release() -> void:
	_smoke_mat = null
	_fire_mat = null


static func _billboard(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if additive else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Vehicle._soft_dot()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 3.2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0.25, 0.9, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.45, 0.05, 0.35)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 3.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.15, Color(1, 1, 1, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	pm.color = Color(0.75, 0.75, 0.75, 0.32)
	p.process_material = pm
	if _smoke_mat == null:
		_smoke_mat = _billboard(false)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _smoke_mat
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
	return p


func _make_fire() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.8
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0, 2.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.55, 0.1, 0.5)
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, 0.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	g.add_point(0.35, Color(1.0, 0.42, 0.08, 0.8))
	g.set_color(g.get_point_count() - 1, Color(0.3, 0.05, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	if _fire_mat == null:
		_fire_mat = _billboard(true)
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.4)
	q.material = _fire_mat
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	return p


## Fireball + flash: a one-shot burst that frees itself.
