class_name Bike
extends Vehicle
## Motorbike or bicycle. Two VehicleWheel3Ds carry it; a lean controller keeps it up: it leans into turns in
## proportion to steering and speed, stands upright at a stop with a rider (feet down), rests on its side stand
## when parked, and gives up once it has crashed or fallen too far, so it falls over like a real bike.

const LEAN_MAX := 0.6          # rad at full lock and speed
const STAND_LEAN := 0.2        # parked on the side stand (leans left)
const FALL_AT := 1.0           # rad: past this it's down

var pedal := false             # bicycle: rider-powered, no engine
var down := false              # lying on its side after a crash
var crank := 0.0               # pedal angle (rider IK)
var _down_t := 0.0


func _ready() -> void:
	super._ready()
	pedal = model == "bicycle"
	for w in _wheels:
		w.wheel_roll_influence = 0.0
	angular_damp = 0.4
	center_of_mass = Vector3(0, _size.y * 0.32, 0)
	# narrow tyres: a thin hull so it can lie on its side
	set_meta("hood_cam", Vector3(0, _size.y * 1.05, -0.2))


func _make_collision(aabb: AABB) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x * 0.5, aabb.size.y * 0.45, aabb.size.z * 0.82)
	cs.shape = box
	cs.position = aabb.get_center() + Vector3(0, aabb.size.y * 0.12, 0)
	add_child(cs)


func _stabilize(delta: float, grounded: int, fwd_speed: float) -> void:
	var roll := asin(clampf(global_basis.x.y, -1.0, 1.0))
	if down:
		_down_t += delta
		# righted by hand (it's light) when a rider gets on, after it has settled
		if driver != null and _down_t > 1.0 and linear_velocity.length() < 1.0:
			down = false
			global_rotation = Vector3(0, global_rotation.y, 0)
			global_position += Vector3(0, 0.3, 0)
		return
	if absf(roll) > FALL_AT or (grounded == 0 and absf(roll) > 0.7):
		down = true
		_down_t = 0.0
		return
	var spd := absf(fwd_speed)
	var want := 0.0
	if driver == null and spd < 1.0:
		want = STAND_LEAN
	elif spd > 0.5:
		var steer_k := _steer / maxf(max_steer, 0.01)
		want = clampf(steer_k * LEAN_MAX * clampf(spd / 9.0, 0.0, 1.0) * clampf(spd / 4.0, 0.3, 1.0), -LEAN_MAX, LEAN_MAX)
	# roll rate toward the target (rotation about +Z raises the right side, i.e. leans left)
	var roll_rate := angular_velocity.dot(global_basis.z)
	var want_rate := (want - roll) * 6.0
	angular_velocity += global_basis.z * (want_rate - roll_rate) * (1.0 - exp(-delta * 12.0))
	if grounded >= 1:
		# light pitch hold (no wheelies or stoppies from the arcade model)
		var pitch := asin(clampf(-global_basis.z.y, -1.0, 1.0))
		var pitch_rate := angular_velocity.dot(global_basis.x)
		angular_velocity += global_basis.x * (-pitch * 3.0 - pitch_rate) * (1.0 - exp(-delta * 4.0)) * 0.5
	if pedal:
		crank = fmod(crank + fwd_speed / 0.34 * 0.36 * delta, TAU)  # crank turns ~0.36x the wheel (gearing)


## Thrown off in a crash: the bike falls, the rider goes flying.
func _detect_impact(delta: float) -> void:
	var before := _jolt_ticks
	super._detect_impact(delta)
	if before > 0 and _jolt_ticks == 0 and _last_strength > 6.0 and driver and driver.has_method("thrown_off"):
		down = true
		_down_t = 0.0
		driver.thrown_off(self, linear_velocity + _last_jolt * -0.3)
