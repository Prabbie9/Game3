class_name Helicopter
extends Vehicle
## Flyable helicopter. Arcade flight that still feels like a machine with weight: the rotor spins up before it
## can lift, lift holds a hover by itself, pitching the nose (accelerate / brake) tilts the lift into forward
## speed, steering yaws and banks into the turn, ascend / descend work the collective. Without power the rotor
## winds down and the helicopter sinks (it doesn't drop like a stone).

const SPIN_UP := 4.0          # seconds to full rotor speed
const MAX_PITCH := 0.42       # rad
const MAX_BANK := 0.38
const YAW_RATE := 1.25        # rad/s
const DRAG := 0.085           # horizontal drag (1/s): top speed ~ g * tan(pitch) / drag

var rotor := 0.0              # 0..1 rotor speed
var ai_lift := 0.0            # AI collective (-1 descend .. 1 climb)
var _spin := []               # [Node3D pivot, axis, rate]
var _rotor_sound: AudioStreamPlayer3D
var _grounded := true


func _ready() -> void:
	model = "heli"
	super._ready()
	gravity_scale = 1.0
	angular_damp = 1.5
	for c in get_children():
		if c.has_meta("spin_axis"):
			_spin.append([c, c.get_meta("spin_axis"), 30.0 if (c.get_meta("spin_axis") as Vector3) == Vector3.UP else 70.0])
	_rotor_sound = AudioStreamPlayer3D.new()
	_rotor_sound.stream = Audio.stream("vehicles/heli_loop.ogg", true)
	_rotor_sound.bus = &"Vehicles"
	_rotor_sound.unit_size = 18.0
	_rotor_sound.max_distance = 450.0
	_rotor_sound.position = Vector3(0, _size.y, 0)
	add_child(_rotor_sound)


## Helicopters don't use the car engine sound or tyres.
func set_driver(who: Node) -> void:
	driver = who
	sleeping = false
	input_enabled = who != null
	horn_on = false
	driver_changed.emit(who)


func _physics_process(delta: float) -> void:
	_detect_impact(delta)
	var powered := driver != null and not engine_dead
	rotor = move_toward(rotor, 1.0 if powered else 0.0, delta / (SPIN_UP if powered else 10.0))
	# sound + spinning blades
	if rotor > 0.01:
		if not _rotor_sound.playing:
			_rotor_sound.play(randf() * 6.0)
		_rotor_sound.pitch_scale = 0.55 + 0.45 * rotor
		_rotor_sound.volume_db = linear_to_db(clampf(rotor, 0.02, 1.0))
	elif _rotor_sound.playing:
		_rotor_sound.stop()
	for sp: Array in _spin:
		(sp[0] as Node3D).rotate_object_local(sp[1], rotor * sp[2] * delta)
	if rotor < 0.02 and driver == null:
		if linear_velocity.length_squared() < 0.06 and angular_velocity.length_squared() < 0.01 and not sleeping:
			_idle_time += delta
			if _idle_time > 0.5:
				sleeping = true
		return
	_idle_time = 0.0
	sleeping = false

	var pitch_in := 0.0
	var yaw_in := 0.0
	var lift_in := 0.0
	if input_enabled:
		pitch_in = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		yaw_in = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		lift_in = Input.get_action_strength("ascend") - Input.get_action_strength("descend")
		if Input.is_action_just_pressed("headlights"):
			set_headlights(not headlights_on)
	elif ai_drive:
		pitch_in = ai_throttle - ai_brake
		yaw_in = ai_steer
		lift_in = ai_lift
	var lift_k := rotor * rotor
	var up := global_basis.y
	# ground contact: skids on something just below
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, -0.35, 0), 1 | 8 | 16)
	q.exclude = [get_rid()]
	_grounded = not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

	# collective: hover by default (cancel vertical speed), climb / sink on input
	var hover := mass * 9.8 / maxf(up.y, 0.6)
	var vy := linear_velocity.y
	var thrust := hover * (1.0 + lift_in * 0.6) - vy * mass * 1.9 * (1.0 - absf(lift_in) * 0.7)
	if _grounded and lift_in <= 0.0 and rotor < 0.95:
		thrust = minf(thrust, hover * 0.8)  # spinning up on the pad: stays down until full speed
	apply_central_force(up * maxf(thrust, 0.0) * lift_k)
	# attitude: steer toward a target pitch/bank, yaw at a rate; level out with no input
	if not _grounded or lift_k > 0.8:
		var fwd := -global_basis.z
		var pitch := asin(clampf(fwd.y, -1.0, 1.0))
		var bank := asin(clampf(global_basis.x.y, -1.0, 1.0))
		var spd := Vector2(linear_velocity.x, linear_velocity.z).length()
		var want_pitch := -pitch_in * MAX_PITCH
		var want_bank := yaw_in * MAX_BANK * clampf(spd / 12.0, 0.25, 1.0)
		var w := global_basis.x * (want_pitch - pitch) * 2.6 + global_basis.z * (want_bank - bank) * 2.6 + Vector3.UP * yaw_in * YAW_RATE
		angular_velocity = angular_velocity.lerp(w * lift_k, 1.0 - exp(-delta * 4.0))
		# air drag (horizontal) and a little sideslip damping so turns carve
		var hv := Vector3(linear_velocity.x, 0, linear_velocity.z)
		var side := global_basis.x * hv.dot(global_basis.x)
		apply_central_force((-hv * DRAG - side * 0.25) * mass)
	rpm = 2000.0 + 4000.0 * rotor
	_update_lights()


## No wheels: the hull itself rests on the ground / sits in the water.
func _make_collision(aabb: AABB) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size * Vector3(0.92, 0.9, 0.94)
	cs.shape = box
	cs.position = aabb.get_center() - Vector3(0, aabb.size.y * 0.05, 0)
	add_child(cs)
