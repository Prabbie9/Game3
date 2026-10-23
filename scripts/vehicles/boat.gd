class_name Boat
extends Vehicle
## Speedboat: floats on the same Gerstner swell the ocean draws (Ocean.wave_height), driven by a propeller at the
## stern and a rudder that only bites with way on. Low drag along the hull, high drag sideways, so it carves and
## the bow lifts under power.

const THRUST := 19000.0       # N at full throttle
const RUDDER := 1.15          # yaw rate (rad/s) at speed
const BUOYANCY := 2.6         # x weight when a float is a full FLOAT_DEPTH under
const FLOAT_DEPTH := 0.45

var _floats: Array[Vector3] = []   # hull points in the car frame
var in_water := false
var _wake: GPUParticles3D
var _stern := Vector3.ZERO


func _ready() -> void:
	model = "speedboat"
	super._ready()
	angular_damp = 0.8
	linear_damp = 0.05
	var a: AABB = CarLibrary.get_model(model).aabb
	var y := a.position.y + 0.35
	for fz: float in [-0.38, -0.1, 0.18, 0.4]:
		for fx: float in [-0.32, 0.32]:
			_floats.append(Vector3(a.get_center().x + a.size.x * fx, y, a.get_center().z + a.size.z * fz))
	_stern = Vector3(a.get_center().x, a.position.y + 0.3, a.end.z - 0.3)
	center_of_mass = Vector3(0, a.position.y + a.size.y * 0.22, a.get_center().z + 0.3)
	_wake = _make_wake()
	_wake.position = _stern + Vector3(0, 0.15, 0.4)
	add_child(_wake)


func _physics_process(delta: float) -> void:
	var ocean: Ocean = Game.world.ocean if Game.world else null
	var submerged := 0
	var n := float(_floats.size())
	for lp in _floats:
		var p := global_transform * lp
		var h := ocean.wave_height(p.x, p.z) if ocean else -2.0
		var depth := h - p.y
		if depth <= 0.0:
			continue
		submerged += 1
		var v := linear_velocity + angular_velocity.cross(p - global_position)
		var f := clampf(depth / FLOAT_DEPTH, 0.0, 1.0) * mass * 9.8 * BUOYANCY / n - v.y * mass * 1.6 / n
		apply_force(Vector3.UP * maxf(f, 0.0), p - global_position)
	in_water = submerged > 0
	if not in_water:
		# beached or flying off a wave: an ordinary body
		_detect_impact(delta)
		return
	sleeping = false
	_prev_vel = linear_velocity  # waves rock the hull: no crash damage from swell
	var fwd := -global_basis.z
	var vf := linear_velocity.dot(fwd)
	var vs := linear_velocity.dot(global_basis.x)
	# hull drag: low lengthways, high sideways
	apply_central_force((-fwd * vf * 0.11 - global_basis.x * vs * 2.2) * mass * (float(submerged) / n))
	var throttle := 0.0
	var steer_in := 0.0
	if input_enabled and not engine_dead:
		throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake") * 0.45
		steer_in = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		horn_on = Input.is_action_pressed("horn")
		if Input.is_action_just_pressed("headlights"):
			set_headlights(not headlights_on)
	_throttle = move_toward(_throttle, throttle, delta * 1.5)
	var stern_p := global_transform * _stern
	var stern_wet := ocean == null or ocean.wave_height(stern_p.x, stern_p.z) > stern_p.y - 0.2
	if stern_wet:
		var push := THRUST * _throttle * (1.0 - pow(clampf(vf / top_speed, 0.0, 1.0), 2.0) * 0.9)
		apply_force(fwd * push, stern_p - global_position)
		# rudder: turn rate grows with speed; reversing steers the other way
		var bite := clampf(absf(vf) / 7.0, 0.15, 1.0) * signf(vf if absf(vf) > 0.5 else 1.0)
		var want_yaw := steer_in * RUDDER * bite
		angular_velocity.y = lerpf(angular_velocity.y, want_yaw, 1.0 - exp(-delta * 2.0))
		# bank into the turn a little
		apply_torque(fwd * -steer_in * bite * mass * 2.0)
	rpm = lerpf(rpm, IDLE_RPM + (RED_RPM - IDLE_RPM) * clampf(absf(_throttle) * 0.8 + absf(vf) / top_speed * 0.3, 0.0, 1.0), 1.0 - exp(-delta * 4.0))
	braking_now = false
	reversing = _throttle < -0.05
	_wake.emitting = absf(vf) > 2.0
	_wake.amount_ratio = clampf(absf(vf) / top_speed, 0.2, 1.0)
	_update_lights()


func _make_wake() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 1.6
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 1)
	pm.spread = 30.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, -6, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.05, 0.2)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.75))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Vehicle._soft_dot()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	return p


## No wheels: the hull itself rests on the ground / sits in the water.
func _make_collision(aabb: AABB) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size * Vector3(0.92, 0.9, 0.94)
	cs.shape = box
	cs.position = aabb.get_center() - Vector3(0, aabb.size.y * 0.05, 0)
	add_child(cs)
