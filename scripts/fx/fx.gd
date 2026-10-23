class_name FX
extends RefCounted
## Pooled combat effects: bullet-hole decals, impact particles per surface, tracers, muzzle flash mesh.
## All pools live under one holder node so nothing is instantiated per shot once warmed up.

enum Surface { CONCRETE, METAL, FLESH, GLASS, WOOD, DIRT }

const MAX_DECALS := 64
const MAX_EMITTERS := 12
const MAX_TRACERS := 8

static var _holder: Node3D
static var _decals: Array[Decal] = []
static var _decal_i := 0
static var _emitters := {}
static var _emitter_i := {}
static var _tracers: Array[MeshInstance3D] = []
static var _tracer_i := 0
static var _hole_tex: Texture2D
static var _spark_mat: StandardMaterial3D
static var _dust_mat: StandardMaterial3D
static var _blood_tex: Texture2D


static func release() -> void:
	_holder = null
	_decals.clear()
	_emitters.clear()
	_tracers.clear()
	_hole_tex = null
	_spark_mat = null
	_dust_mat = null
	_blood_tex = null


static func surface_of(col: Object) -> int:
	if col == null:
		return Surface.CONCRETE
	if col is Node and (col as Node).has_meta("surface"):
		return (col as Node).get_meta("surface")
	if col is VehicleBody3D:
		return Surface.METAL
	if col is CharacterBody3D:
		return Surface.FLESH
	return Surface.CONCRETE


static func _ensure(scene: Node) -> void:
	if _holder and is_instance_valid(_holder) and _holder.is_inside_tree():
		return
	_holder = Node3D.new()
	_holder.name = "FXPool"
	scene.add_child(_holder)
	_decals.clear()
	_emitters.clear()
	_tracers.clear()
	if _hole_tex == null:
		_hole_tex = _make_hole_texture()
	for i in MAX_DECALS:
		var d := Decal.new()
		d.size = Vector3(0.12, 0.12, 0.12)
		d.texture_albedo = _hole_tex
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.cull_mask = 1
		d.visible = false
		d.distance_fade_enabled = true
		d.distance_fade_begin = 40.0
		d.distance_fade_length = 10.0
		_holder.add_child(d)
		_decals.append(d)
	for s in [Surface.CONCRETE, Surface.METAL, Surface.FLESH]:
		var arr: Array[GPUParticles3D] = []
		for i in MAX_EMITTERS:
			var e := _make_emitter(s)
			_holder.add_child(e)
			arr.append(e)
		_emitters[s] = arr
		_emitter_i[s] = 0
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.85, 0.55, 0.55)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for i in MAX_TRACERS:
		var t := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.006
		cm.height = 1.0
		cm.radial_segments = 4
		cm.rings = 1
		t.mesh = cm
		t.material_override = tm
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		_holder.add_child(t)
		_tracers.append(t)


static func impact(scene: Node, pos: Vector3, normal: Vector3, surface: int) -> void:
	_ensure(scene)
	if surface != Surface.FLESH:
		var d := _decals[_decal_i]
		_decal_i = (_decal_i + 1) % MAX_DECALS
		d.visible = true
		# Decal projects along its local -Y: align +Y with the surface normal
		d.global_basis = _basis_y(normal).rotated(normal, randf() * TAU)
		d.global_position = pos
	var kind := surface if _emitters.has(surface) else Surface.CONCRETE
	var arr: Array = _emitters[kind]
	var e: GPUParticles3D = arr[_emitter_i[kind]]
	_emitter_i[kind] = (_emitter_i[kind] + 1) % MAX_EMITTERS
	e.global_position = pos + normal * 0.02
	e.global_basis = _basis_y(normal)
	e.restart()
	e.emitting = true


static func tracer(scene: Node, from: Vector3, to: Vector3) -> void:
	_ensure(scene)
	var t := _tracers[_tracer_i]
	_tracer_i = (_tracer_i + 1) % MAX_TRACERS
	var len := from.distance_to(to)
	if len < 1.0:
		return
	t.visible = true
	t.global_transform = Transform3D(_basis_y((to - from) / len).scaled(Vector3(1, len, 1)), (from + to) * 0.5)
	var tw := t.create_tween()
	tw.tween_interval(0.04)
	tw.tween_callback(func(): t.visible = false)


static func _basis_y(y: Vector3) -> Basis:
	y = y.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func make_muzzle_flash() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _make_flash_texture()
	m.albedo_color = Color(1.0, 0.8, 0.45)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


static func _make_emitter(surface: int) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.one_shot = true
	e.emitting = false
	e.explosiveness = 0.95
	e.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	match surface:
		Surface.METAL:
			e.amount = 14
			e.lifetime = 0.35
			pm.spread = 55.0
			pm.initial_velocity_min = 3.0
			pm.initial_velocity_max = 7.0
			pm.gravity = Vector3(0, -12, 0)
			pm.color = Color(1.0, 0.7, 0.3)
			q.size = Vector2(0.02, 0.02)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		Surface.FLESH:
			e.amount = 18
			e.lifetime = 0.55
			pm.spread = 40.0
			pm.initial_velocity_min = 1.2
			pm.initial_velocity_max = 3.6
			pm.gravity = Vector3(0, -9, 0)
			pm.damping_min = 1.0
			pm.damping_max = 2.0
			pm.color = Color(0.45, 0.02, 0.02, 0.95)
			pm.scale_min = 0.5
			pm.scale_max = 1.6
			q.size = Vector2(0.07, 0.07)
			m.albedo_texture = _make_soft_texture()
		_:
			e.amount = 10
			e.lifetime = 0.7
			pm.spread = 30.0
			pm.initial_velocity_min = 0.5
			pm.initial_velocity_max = 1.6
			pm.gravity = Vector3(0, -1.5, 0)
			pm.damping_min = 1.5
			pm.damping_max = 3.0
			pm.scale_min = 0.6
			pm.scale_max = 1.8
			var grad := Gradient.new()
			grad.set_color(0, Color(0.62, 0.6, 0.56, 0.7))
			grad.set_color(1, Color(0.62, 0.6, 0.56, 0.0))
			var gt := GradientTexture1D.new()
			gt.gradient = grad
			pm.color_ramp = gt
			q.size = Vector2(0.12, 0.12)
			m.albedo_texture = _make_soft_texture()
	q.material = m
	e.process_material = pm
	e.draw_pass_1 = q
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	return e


## A dark red pool with a ragged edge (decal under a body).
static func blood_texture() -> Texture2D:
	if _blood_tex:
		return _blood_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.045
	noise.seed = 7
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
			var a := clampf((1.0 - d) * 2.2 + noise.get_noise_2d(x, y) * 1.4 - 0.25, 0.0, 1.0)
			a = smoothstep(0.15, 0.45, a)
			img.set_pixel(x, y, Color(0.22, 0.01, 0.01, a * 0.95))
	_blood_tex = ImageTexture.create_from_image(img)
	return _blood_tex


static func _make_hole_texture() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			var a := 0.0
			var c := 0.06
			if d < 0.22:
				a = 1.0
			elif d < 0.55:
				a = clampf(1.0 - (d - 0.22) / 0.33, 0.0, 1.0) * (0.55 + rng.randf() * 0.45)
				c = 0.12 + rng.randf() * 0.1
			img.set_pixel(x, y, Color(c, c * 0.95, c * 0.9, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _make_soft_texture() -> Texture2D:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
	return ImageTexture.create_from_image(img)


static func _make_flash_texture() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var v := Vector2(x - s / 2.0, y - s / 2.0) / (s / 2.0)
			var ang := atan2(v.y, v.x)
			var star := 0.35 + 0.65 * absf(cos(ang * 3.0)) ** 6
			var a := clampf(1.0 - v.length() / star, 0.0, 1.0) ** 1.5
			img.set_pixel(x, y, Color(1, 0.9, 0.7, a))
	return ImageTexture.create_from_image(img)
