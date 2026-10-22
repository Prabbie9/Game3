class_name Vehicle
extends VehicleBody3D
## Drivable car built from CarLibrary meshes. Arcade-but-weighty handling: speed-sensitive steering,
## handbrake drifts, downforce, low centre of mass. Every vehicle is enterable.

signal driver_changed(driver: Node)

@export var model := "sedan"
@export var display_name := "Calder Sedan"
@export var paint := Color(0.55, 0.08, 0.06)
@export var max_engine_force := 5200.0
@export var max_brake := 90.0
@export var top_speed := 52.0  # m/s (~187 km/h)
@export var max_steer := 0.55
@export var vehicle_mass := 1450.0

var driver: Node = null
var camera_distance := 6.5
var camera_height := 1.7
var input_enabled := false
var headlights_on := false

var _throttle := 0.0
var _steer := 0.0
var _size := Vector3(1.9, 1.5, 4.5)
var _seat := Transform3D()
var _door := Vector3()
var _wheels: Array[VehicleWheel3D] = []
var _lights: Array[Light3D] = []
var _brake_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("vehicles")
	mass = vehicle_mass
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8 | 16
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	continuous_cd = true
	_build()


func _build() -> void:
	var data := CarLibrary.get_model(model)
	var aabb: AABB = data.aabb
	_size = aabb.size
	var body_mat := _paint_material()
	for p in data.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.transform = p[1]
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m and String(m.resource_name).begins_with("Body"):
				var bm: StandardMaterial3D = body_mat.duplicate()
				bm.albedo_texture = (m as BaseMaterial3D).albedo_texture
				mi.set_surface_override_material(s, bm)
		add_child(mi)
	# collision: convex hull of the body (one per mesh part is overkill; use the main body part)
	var hull := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x * 0.96, aabb.size.y * 0.55, aabb.size.z * 0.97)
	hull.shape = box
	hull.position = aabb.get_center() + Vector3(0, -aabb.size.y * 0.12, 0)
	add_child(hull)
	var cabin := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(aabb.size.x * 0.8, aabb.size.y * 0.42, aabb.size.z * 0.5)
	cabin.shape = cbox
	cabin.position = aabb.get_center() + Vector3(0, aabb.size.y * 0.25, -aabb.size.z * 0.03)
	add_child(cabin)
	center_of_mass = Vector3(0, aabb.position.y + 0.08, 0)

	for w in data.wheels:
		var wheel := VehicleWheel3D.new()
		var front: bool = w.pos.z < 0.0
		wheel.position = w.pos + Vector3(0, 0.12, 0)
		wheel.wheel_radius = w.radius
		wheel.wheel_rest_length = 0.16
		wheel.suspension_travel = 0.22
		wheel.suspension_stiffness = 42.0
		wheel.suspension_max_force = vehicle_mass * 12.0
		wheel.damping_compression = 1.9
		wheel.damping_relaxation = 2.4
		wheel.wheel_friction_slip = 2.7 if front else 2.5
		wheel.wheel_roll_influence = 0.04
		wheel.use_as_steering = front
		wheel.use_as_traction = not front
		for part in w.parts:
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = part[1]
			wheel.add_child(mi)
		add_child(wheel)
		_wheels.append(wheel)

	camera_distance = clampf(_size.z * 1.35, 5.0, 11.0)
	camera_height = clampf(_size.y * 1.05, 1.5, 3.0)
	# driver sits left of centre (US layout), a bit behind the front axle
	var wheelbase_front := 0.0
	for w in data.wheels:
		wheelbase_front = minf(wheelbase_front, w.pos.z)
	# seat = where the driver's hips sit (Player offsets its root by the drive clip's hip height)
	_seat = Transform3D(Basis.IDENTITY, Vector3(-_size.x * 0.21, aabb.position.y + _size.y * 0.3, wheelbase_front * 0.18))
	_door = Vector3(-_size.x * 0.5 - 0.55, 0.0, wheelbase_front * 0.2)
	_build_lights(aabb)


func _paint_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.metallic = 0.55
	m.roughness = 0.28
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.08
	return m


func _build_lights(aabb: AABB) -> void:
	var front_z := aabb.position.z + 0.15
	for side in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.position = Vector3(side * aabb.size.x * 0.33, aabb.position.y + aabb.size.y * 0.38, front_z)
		l.rotation_degrees = Vector3(-4, 0, 0)
		l.spot_range = 38.0
		l.spot_angle = 32.0
		l.spot_attenuation = 0.8
		l.light_energy = 6.0
		l.light_color = Color(1.0, 0.95, 0.85)
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)


func set_headlights(on: bool) -> void:
	headlights_on = on
	for l in _lights:
		l.visible = on


func driver_door_position() -> Vector3:
	return global_transform * _door


## Driver hips target (on the seat cushion), facing forward.
func seat_transform() -> Transform3D:
	return global_transform * _seat


func ground_height_at(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2, 0), p + Vector3(0, -4, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else global_position.y


func reserve(who: Node) -> void:
	driver = who
	brake = max_brake
	engine_force = 0.0


func set_driver(who: Node) -> void:
	driver = who
	input_enabled = who != null
	if who == null:
		engine_force = 0.0
		brake = max_brake * 0.3
		_throttle = 0.0
	driver_changed.emit(who)


func set_driver_input_enabled(on: bool) -> void:
	input_enabled = on
	if not on:
		engine_force = 0.0
		brake = max_brake


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func _physics_process(delta: float) -> void:
	var fwd_speed := -global_basis.z.dot(linear_velocity)
	var throttle := 0.0
	var brake_in := 0.0
	var steer_in := 0.0
	var handbrake := false
	if input_enabled:
		throttle = Input.get_action_strength("accelerate")
		brake_in = Input.get_action_strength("brake")
		steer_in = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		handbrake = Input.is_action_pressed("handbrake")
		if Input.is_action_just_pressed("headlights"):
			set_headlights(not headlights_on)

	# brake pedal reverses once (almost) stopped
	var drive := throttle
	var braking := 0.0
	if brake_in > 0.05:
		if fwd_speed > 1.0:
			braking = brake_in
		else:
			drive = -brake_in * 0.55
	if throttle > 0.05 and fwd_speed < -1.0:
		braking = throttle
		drive = 0.0
	_throttle = move_toward(_throttle, drive, delta * 3.0)
	var speed_factor := clampf(1.0 - absf(fwd_speed) / top_speed, 0.0, 1.0)
	if _throttle < 0.0:
		speed_factor = clampf(1.0 - absf(fwd_speed) / 7.0, 0.0, 1.0)  # reverse tops out ~25 km/h
	# VehicleBody3D drives along +Z; our cars face -Z, so forward thrust is a negative engine force
	engine_force = -_throttle * max_engine_force * (0.35 + 0.65 * speed_factor)
	# nobody at the controls (parked, or a driver getting in/out): hold the car firmly
	brake = braking * max_brake if input_enabled else max_brake

	var steer_limit := max_steer / (1.0 + absf(fwd_speed) / 5.5)
	var steer_rate := 2.6 if absf(steer_in) > 0.01 else 4.0
	_steer = move_toward(_steer, steer_in * steer_limit, delta * steer_rate)
	steering = _steer

	for w in _wheels:
		if not w.use_as_steering:
			w.wheel_friction_slip = 1.0 if handbrake else 2.5
			if handbrake:
				w.brake = max_brake * 0.8
	# downforce keeps it planted at speed
	apply_central_force(-global_basis.y * linear_velocity.length_squared() * 1.6)
	# arcade anti-roll: resist roll/pitch away from upright (weaker when airborne so jumps still tumble)
	var grounded := 0
	for w in _wheels:
		if w.is_in_contact():
			grounded += 1
	var tilt := global_basis.y.cross(Vector3.UP)
	var k := 16.0 if grounded >= 2 else 1.5
	apply_torque(tilt * mass * k - (angular_velocity - global_basis.y * angular_velocity.dot(global_basis.y)) * mass * 0.6)
