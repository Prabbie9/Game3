class_name Explosion
extends RefCounted
## One explosion: fireball and flash, sound, a scorch mark, a shock wave that damages, ragdolls and shoves
## whatever is in range, and camera shake by distance. Used by wrecked vehicles, rockets and grenades.

static var _fire_mat: StandardMaterial3D
static var _scorch_tex: Texture2D


static func release() -> void:
	_fire_mat = null
	_scorch_tex = null


## radius in metres; damage at the centre (falls off linearly). `exclude` is spared from the shock wave.
static func blast(scene: Node, at: Vector3, radius := 9.0, damage := 150.0, source: Node = null, exclude: Object = null) -> void:
	if source != null and source == Game.player:
		Game.crime("explosion", at)
	if Game.player:
		var near := 1.0 - clampf(Game.player.global_position.distance_to(at) / (radius * 6.0), 0.0, 1.0)
		if near > 0.0:
			Game.rumble(near, near, 0.25 + near * 0.35)
	if PropWorld.get_props():
		PropWorld.get_props().blast(at, radius)
	Audio.play_at(Audio.pick("weapons/explosion_%d.ogg", 2), at, 6.0, randf_range(0.92, 1.05), &"SFX", 450.0)
	Audio.play_at(Audio.stream("vehicles/explosion_1.ogg"), at, 1.0, 0.8, &"SFX", 200.0)
	var boom := _make_fireball()
	scene.add_child(boom)
	boom.global_position = at
	var space := (scene as Node3D).get_world_3d().direct_space_state if scene is Node3D else boom.get_world_3d().direct_space_state
	# scorch mark on the ground below
	var down := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at + Vector3(0, -2.5, 0), 1)
	var g := space.intersect_ray(down)
	if g:
		var d := Decal.new()
		if _scorch_tex == null:
			_scorch_tex = _make_scorch()
		d.texture_albedo = _scorch_tex
		d.size = Vector3(radius * 0.55, 1.2, radius * 0.55)
		d.modulate = Color(1, 1, 1, 0.9)
		d.cull_mask = 1
		scene.add_child(d)
		d.global_position = g.position
		d.rotation.y = randf() * TAU
		var tw := d.create_tween()
		tw.tween_interval(40.0)
		tw.tween_property(d, "modulate:a", 0.0, 5.0)
		tw.tween_callback(d.queue_free)
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = 2 | 4 | 8 | 16 | 32
	var seen := {}
	for r: Dictionary in space.intersect_shape(q, 48):
		var body: Object = r.collider
		if body == exclude or body == null or seen.has(body):
			continue
		# hit boxes forward to their owner; one hit per owner
		var target: Object = body.get_meta("owner") if body is Node and (body as Node).has_meta("owner") else body
		if seen.has(target):
			continue
		seen[body] = true
		seen[target] = true
		var bp: Vector3 = (body as Node3D).global_position
		var k := clampf(1.0 - bp.distance_to(at) / radius, 0.0, 1.0)
		if k <= 0.0:
			continue
		var away := (bp - at).normalized()
		if target is RigidBody3D:
			var rb := target as RigidBody3D
			rb.sleeping = false
			rb.apply_impulse((away + Vector3.UP * 0.6) * rb.mass * 7.0 * k, Vector3(randf() - 0.5, 0.3, randf() - 0.5))
		if target.has_method("blast_hit"):
			target.blast_hit(at, damage * k, source)
		elif target.has_method("take_damage"):
			target.take_damage(damage * k, source)
			if target.has_method("go_ragdoll") and k > 0.15:
				target.go_ragdoll((away + Vector3.UP) * 8.0 * k)
	var cam := boom.get_viewport().get_camera_3d()
	if cam and cam.get_parent() and cam.get_parent().get_parent() is CameraRig:
		var rig := cam.get_parent().get_parent() as CameraRig
		rig.shake = maxf(rig.shake, clampf(2.5 - cam.global_position.distance_to(at) / 20.0, 0.0, 2.5))


static func _make_fireball() -> Node3D:
	var root := Node3D.new()
	var p := GPUParticles3D.new()
	p.amount = 64
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, 3.0, 0)
	pm.damping_min = 6.0
	pm.damping_max = 9.0
	pm.scale_min = 1.6
	pm.scale_max = 3.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.3))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	g.add_point(0.25, Color(1.0, 0.5, 0.1, 0.95))
	g.add_point(0.6, Color(0.25, 0.1, 0.05, 0.6))
	g.set_color(g.get_point_count() - 1, Color(0.05, 0.05, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	if _fire_mat == null:
		_fire_mat = VehicleDamage._billboard(true)
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 1.6)
	qm.material = _fire_mat
	p.draw_pass_1 = qm
	p.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 24, 24))
	p.emitting = true
	root.add_child(p)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.35)
	flash.omni_range = 26.0
	flash.light_energy = 14.0
	flash.position = Vector3(0, 1.5, 0)
	root.add_child(flash)
	var tw := root.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.0)
	tw.tween_callback(root.queue_free)
	return root


static func _make_scorch() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d + noise.get_noise_2d(x, y) * 0.45, 0.0, 1.0)
			a = smoothstep(0.0, 0.6, a)
			img.set_pixel(x, y, Color(0.03, 0.025, 0.02, a * 0.92))
	return ImageTexture.create_from_image(img)
