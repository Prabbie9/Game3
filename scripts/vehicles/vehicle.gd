class_name Vehicle
extends VehicleBody3D
## Drivable car built from CarLibrary meshes. Arcade-but-weighty handling: speed-sensitive steering,
## handbrake drifts, downforce, low centre of mass. Every vehicle is enterable.

signal driver_changed(driver: Node)

## Handling per body type: mass (kg), engine force (N at the wheels in 1st), top speed (m/s), steering lock,
## tyre grip, suspension stiffness / travel, drive (rwd/fwd/awd), and the name shown on entry.
const SPECS := {
	"compact": {"mass": 1080, "force": 4700, "top": 44.0, "steer": 0.62, "grip": 2.6, "stiff": 40.0, "travel": 0.2, "drive": "fwd", "name": "Minnow"},
	"hatchback": {"mass": 1180, "force": 5100, "top": 47.0, "steer": 0.6, "grip": 2.65, "stiff": 42.0, "travel": 0.2, "drive": "fwd", "name": "Solano Hatch"},
	"sedan": {"mass": 1450, "force": 6300, "top": 52.0, "steer": 0.55, "grip": 2.6, "stiff": 42.0, "travel": 0.22, "drive": "rwd", "name": "Calder Sedan"},
	"wagon": {"mass": 1560, "force": 6100, "top": 49.0, "steer": 0.54, "grip": 2.55, "stiff": 40.0, "travel": 0.22, "drive": "rwd", "name": "Calder Estate"},
	"coupe": {"mass": 1340, "force": 7300, "top": 58.0, "steer": 0.56, "grip": 2.8, "stiff": 48.0, "travel": 0.18, "drive": "rwd", "name": "Vela Coupé"},
	"sport": {"mass": 1290, "force": 9200, "top": 69.0, "steer": 0.52, "grip": 3.05, "stiff": 58.0, "travel": 0.15, "drive": "rwd", "name": "Kestrel GT"},
	"suv": {"mass": 1980, "force": 7900, "top": 50.0, "steer": 0.52, "grip": 2.5, "stiff": 38.0, "travel": 0.28, "drive": "awd", "name": "Vireo Ranger"},
	"minivan": {"mass": 1860, "force": 6600, "top": 46.0, "steer": 0.52, "grip": 2.45, "stiff": 36.0, "travel": 0.24, "drive": "fwd", "name": "Ferro Family"},
	"pickup": {"mass": 1920, "force": 7800, "top": 50.0, "steer": 0.5, "grip": 2.5, "stiff": 40.0, "travel": 0.26, "drive": "rwd", "name": "Hauler 1500"},
	"offroad": {"mass": 1820, "force": 7600, "top": 48.0, "steer": 0.54, "grip": 2.7, "stiff": 32.0, "travel": 0.34, "drive": "awd", "name": "Mesa Trailhound"},
}
const GEARS := [0.2, 0.36, 0.53, 0.7, 0.86, 1.0]   # top speed fraction reached at the redline in each gear
const GEAR_PULL := [1.55, 1.25, 1.05, 0.9, 0.78, 0.68]
const IDLE_RPM := 850.0
const RED_RPM := 6800.0

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
var rpm := IDLE_RPM
var gear := 1             # 1..6, -1 reverse
var braking_now := false
var reversing := false
var skidding := 0.0       # 0..1, how hard the tyres are sliding (audio/smoke)
var _front_light: ShaderMaterial
var _rear_light: ShaderMaterial
var _smoke: Array[GPUParticles3D] = []
var _last_mark := {}      # wheel -> last skid point
var _driven := 2.0


func _ready() -> void:
	add_to_group("vehicles")
	var spec: Dictionary = SPECS.get(model, SPECS.sedan)
	vehicle_mass = spec.mass
	max_engine_force = spec.force
	top_speed = spec.top
	max_steer = spec.steer
	if display_name == "" or display_name == "Calder Sedan":
		display_name = spec.name
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
		var spec: Dictionary = SPECS.get(model, SPECS.sedan)
		wheel.wheel_rest_length = 0.16 + (float(spec.travel) - 0.22) * 0.5
		wheel.suspension_travel = spec.travel
		wheel.suspension_stiffness = spec.stiff
		wheel.suspension_max_force = vehicle_mass * 12.0
		wheel.damping_compression = 1.9
		wheel.damping_relaxation = 2.4
		wheel.wheel_friction_slip = float(spec.grip) + (0.1 if front else 0.0)
		wheel.wheel_roll_influence = 0.04
		wheel.use_as_steering = front
		wheel.use_as_traction = front if spec.drive == "fwd" else (true if spec.drive == "awd" else not front)
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
	_build_optics(data)
	_driven = 0.0
	for w in _wheels:
		if w.use_as_traction:
			_driven += 1.0
	set_meta("hood_cam", Vector3(0, aabb.position.y + _size.y * 0.78, aabb.position.z + _size.z * 0.36))
	for w in _wheels:
		if not w.use_as_steering:
			var sm := _smoke_emitter()
			sm.position = w.position + Vector3(0, -w.wheel_radius * 0.8, 0.2)
			add_child(sm)
			_smoke.append(sm)


func _build_optics(data: Dictionary) -> void:
	var tex: Texture2D = (data.optics_mat as BaseMaterial3D).albedo_texture if data.get("optics_mat") is BaseMaterial3D else null
	for k: String in data.get("optics", {}):
		var m := ShaderMaterial.new()
		m.shader = preload("res://assets/shaders/car_lights.gdshader")
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("rear", k == "rear")
		var mi := MeshInstance3D.new()
		mi.mesh = data.optics[k]
		mi.material_override = m
		add_child(mi)
		if k == "rear":
			_rear_light = m
		else:
			_front_light = m


func _smoke_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.6
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.85, 0.85, 0.35))
	grad.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	q.material = m
	p.draw_pass_1 = q
	return p


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
	_dot = ImageTexture.create_from_image(img)
	return _dot


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
	# automatic gearbox: pick the gear for this speed, engine pull falls off with gear and near the redline
	var v := absf(fwd_speed)
	if _throttle < -0.01:
		gear = -1
	elif gear < 1:
		gear = 1
	if gear >= 1:
		var top_g: float = top_speed * GEARS[gear - 1]
		var r := v / top_g
		if r > 0.92 and gear < GEARS.size():
			gear += 1
		elif gear > 1 and v < top_speed * GEARS[gear - 2] * 0.62:
			gear -= 1
		top_g = top_speed * GEARS[gear - 1]
		var target_rpm := IDLE_RPM + (RED_RPM - IDLE_RPM) * clampf(v / top_g, 0.0, 1.0)
		if v < 2.0:
			target_rpm = lerpf(IDLE_RPM + 2200.0 * absf(_throttle), target_rpm, v / 2.0)
		rpm = lerpf(rpm, target_rpm, 1.0 - exp(-delta * 10.0))
	else:
		rpm = lerpf(rpm, IDLE_RPM + 3000.0 * clampf(v / 7.0, 0.0, 1.0) + 800.0 * absf(_throttle), 1.0 - exp(-delta * 8.0))
	var speed_factor := clampf(1.0 - v / top_speed, 0.0, 1.0)
	var pull: float = GEAR_PULL[gear - 1] if gear >= 1 else 1.2
	if _throttle < 0.0:
		speed_factor = clampf(1.0 - v / 7.0, 0.0, 1.0)  # reverse tops out ~25 km/h
	var torque := clampf(0.55 + 0.6 * sin(clampf(rpm / RED_RPM, 0.0, 1.0) * PI * 0.9), 0.4, 1.15)
	# VehicleBody3D drives along +Z; our cars face -Z, so forward thrust is a negative engine force
	# engine_force is applied at every driven wheel: normalise so AWD isn't twice as strong as RWD
	engine_force = -_throttle * max_engine_force * pull * torque * (0.5 + 0.5 * speed_factor) / GEAR_PULL[2] * 2.0 / maxf(_driven, 1.0)
	braking_now = braking > 0.05 or (handbrake and v > 1.0)
	reversing = _throttle < -0.05
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
	_update_tyres(v, handbrake)
	_update_lights()


## Skid marks and smoke when the tyres slide (handbrake, wheelspin, hard cornering).
func _update_tyres(v: float, handbrake: bool) -> void:
	var slide := 0.0
	var marks := SkidMarks.instance
	for w in _wheels:
		var s := 0.0
		if w.is_in_contact() and v > 3.0:
			s = clampf((0.75 - w.get_skidinfo()) / 0.5, 0.0, 1.0)
			if handbrake and not w.use_as_steering:
				s = maxf(s, 0.8)
		if w.is_in_contact() and absf(engine_force) > max_engine_force * 0.8 and v < 6.0 and w.use_as_traction:
			s = maxf(s, 0.7)  # launch wheelspin
		slide = maxf(slide, s)
		if marks:
			var contact := w.get_contact_point() if w.is_in_contact() else Vector3.INF
			if s > 0.35 and contact != Vector3.INF:
				var last: Vector3 = _last_mark.get(w, Vector3.INF)
				if last != Vector3.INF and last.distance_to(contact) > 0.25:
					marks.add(last, contact, w.get_contact_normal(), s)
					_last_mark[w] = contact
				elif last == Vector3.INF:
					_last_mark[w] = contact
			else:
				_last_mark.erase(w)
	skidding = lerpf(skidding, slide, 0.2)
	for sm in _smoke:
		sm.emitting = skidding > 0.45
		sm.amount_ratio = clampf(skidding, 0.2, 1.0)


func _update_lights() -> void:
	var night: float = Game.world.night if Game.world else 0.0
	if driver != null and not headlights_on and night > 0.5:
		set_headlights(true)
	var on := 1.0 if headlights_on else 0.0
	if _front_light:
		_front_light.set_shader_parameter("head", on)
	if _rear_light:
		_rear_light.set_shader_parameter("tail", on)
		_rear_light.set_shader_parameter("brake", 1.0 if braking_now and driver != null else 0.0)
		_rear_light.set_shader_parameter("reverse", 1.0 if reversing and driver != null else 0.0)
