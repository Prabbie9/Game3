class_name Player
extends CharacterBody3D
## Third-person player: on-foot locomotion, aiming/shooting and vehicle enter/exit.

signal health_changed(health: float, armor: float)
signal vehicle_changed(vehicle: Node)

enum State { ON_FOOT, ENTERING, DRIVING, EXITING, DEAD }

const GRAVITY := 18.0
const JUMP_VELOCITY := 5.2
const TURN_RATE := 11.0
const SPRINT_BOOST := 1.18  # sprint faster than the clip's native speed; playback speeds up to match

@export var character_file := "ch08_nonpbr"

var state := State.ON_FOOT
var health := 100.0
var armor := 0.0
var vehicle: Vehicle
var aiming := false
var aim_weight := 0.0

var _air_time := 0.0
var _jump_timer := -1.0
var _fall_speed := 0.0
var _seq_time := 0.0
var _seq_from := Transform3D()
var _seq_to := Transform3D()
var _seat_local := Transform3D()

@onready var visual: HumanoidVisual = $Visual
@onready var cam: CameraRig = $CameraRig
@onready var weapon: Weapon = $Weapon


func _ready() -> void:
	Game.player = self
	visual.character_file = character_file
	cam.target = self
	cam.yaw = rotation.y
	visual.action_finished.connect(_on_action_finished)
	weapon.setup(self, visual, cam)


func _physics_process(delta: float) -> void:
	match state:
		State.ON_FOOT:
			_on_foot(delta)
		State.ENTERING, State.EXITING:
			_sequence(delta)
		State.DRIVING:
			_driving()


func _on_foot(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if Game.controls_enabled else Vector2.ZERO
	var move_dir := cam.flat_basis() * Vector3(input.x, 0, input.y)
	aiming = Game.controls_enabled and Input.is_action_pressed("aim") and weapon.has_weapon()
	aim_weight = move_toward(aim_weight, 1.0 if aiming else 0.0, delta * 6.0)

	var target_speed := 0.0
	if input.length() > 0.1:
		var mag := clampf(input.length(), 0.0, 1.0)
		if aiming:
			target_speed = visual.aim_run_speed if Input.is_action_pressed("sprint") else visual.aim_walk_speed
		elif Input.is_action_pressed("sprint"):
			target_speed = visual.sprint_speed * SPRINT_BOOST
		elif Input.is_action_pressed("walk_toggle") or mag < 0.5:
			target_speed = visual.walk_speed
		else:
			target_speed = visual.run_speed
		if Game.using_gamepad and not aiming:
			target_speed = lerpf(visual.walk_speed, target_speed, clampf((mag - 0.5) * 2.0, 0.0, 1.0)) if mag >= 0.5 else visual.walk_speed

	var on_floor := is_on_floor()
	var hvel := Vector3(velocity.x, 0, velocity.z)
	var want := move_dir.normalized() * target_speed
	var accel := (14.0 if target_speed > hvel.length() else 10.0) if on_floor else 2.5
	hvel = hvel.move_toward(want, accel * delta * maxf(target_speed, 3.0))

	# facing
	if aiming:
		rotation.y = lerp_angle(rotation.y, cam.yaw, 1.0 - exp(-delta * 20.0))
	elif move_dir.length() > 0.1 and on_floor:
		var yaw := atan2(-move_dir.x, -move_dir.z)
		var rate := TURN_RATE * (0.6 if hvel.length() > visual.run_speed * 1.2 else 1.0)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * rate))
		# turning sharply: don't keep full momentum sideways (prevents ice-skating arcs)
		var fwd := -global_basis.z
		var align := clampf(fwd.dot(hvel.normalized()), 0.0, 1.0) if hvel.length() > 0.1 else 1.0
		hvel = hvel.lerp(fwd * hvel.length(), (1.0 - align) * minf(1.0, delta * 8.0))

	velocity.x = hvel.x
	velocity.z = hvel.z
	if on_floor:
		if _air_time > 0.25:
			visual.travel("land" if _fall_speed > 4.0 else "ground")
		_air_time = 0.0
		_fall_speed = 0.0
		if _jump_timer >= 0.0:
			# short wind-up so the take-off frame of the clip lines up with leaving the ground
			_jump_timer -= delta
			velocity.y = -0.5
			if _jump_timer < 0.0:
				velocity.y = JUMP_VELOCITY
		elif Game.controls_enabled and Input.is_action_just_pressed("jump") and not aiming:
			var running := hvel.length() > visual.run_speed * 0.8
			_jump_timer = 0.08 if running else 0.16
			visual.travel("jump_run" if running else "jump")
			velocity.y = -0.5
		else:
			velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
		_air_time += delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
		if _air_time > 0.35 and visual.current_state() == &"ground":
			visual.travel("fall")
	move_and_slide()

	var speed := Vector2(velocity.x, velocity.z).length()
	visual.set_locomotion(speed if on_floor else 0.0)
	var local := global_basis.inverse() * velocity
	visual.set_aim(Vector2(local.x, -local.z), aim_weight)
	cam.mode = CameraRig.Mode.AIM if aiming else CameraRig.Mode.ON_FOOT

	if Game.controls_enabled and Input.is_action_just_pressed("interact"):
		var v := _nearest_vehicle()
		if v:
			enter_vehicle(v)


func _nearest_vehicle() -> Vehicle:
	var best: Vehicle = null
	var best_d := 4.5
	for v: Vehicle in get_tree().get_nodes_in_group("vehicles"):
		var d := global_position.distance_to(v.driver_door_position())
		if d < best_d and v.driver == null:
			best = v
			best_d = d
	return best


# --- vehicle entry / exit -------------------------------------------------

func enter_vehicle(v: Vehicle) -> void:
	vehicle = v
	state = State.ENTERING
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	aim_weight = 0.0
	visual.set_aim(Vector2.ZERO, 0.0)
	weapon.holster(true)
	v.reserve(self)
	# Place the character so the root-motion clip ends with the hips at the seat.
	var seat := _seat_root(v)
	var turn := visual.clip_yaw("car_enter")
	var start_basis := seat.basis * Basis(Vector3.UP, -turn)
	var d := visual.clip_displacement("car_enter")
	var start := Transform3D(start_basis, seat.origin - start_basis * Vector3(d.x, 0, d.z))
	start.origin.y = v.ground_height_at(start.origin)
	_seq_from = global_transform
	_seq_to = start
	_seq_time = 0.0
	_seat_local = v.global_transform.affine_inverse() * seat
	visual.travel("car_enter")
	cam.mode = CameraRig.Mode.VEHICLE
	cam.target = v
	cam.vehicle_distance = v.camera_distance
	cam.vehicle_height = v.camera_height


func exit_vehicle() -> void:
	if not vehicle:
		return
	state = State.EXITING
	vehicle.set_driver_input_enabled(false)
	var seat := _seat_root(vehicle)
	global_transform = seat
	var turn := visual.clip_yaw("car_exit")
	var d := visual.clip_displacement("car_exit")
	var end_basis := seat.basis * Basis(Vector3.UP, turn)
	var end := Transform3D(end_basis, seat.origin + seat.basis * Vector3(d.x, 0, d.z))
	end.origin.y = vehicle.ground_height_at(end.origin)
	_seq_from = seat
	_seq_to = end
	_seq_time = 0.0
	visual.travel("car_exit")


## Player root transform that puts the drive pose's hips on the vehicle seat.
func _seat_root(v: Vehicle) -> Transform3D:
	var s := v.seat_transform()
	s.origin -= s.basis.y * visual.clip_hip_height("drive")
	return s


func _sequence(delta: float) -> void:
	_seq_time += delta
	if state == State.ENTERING:
		# quick blend to the door start pose, then the clip carries the body into the seat
		var k := clampf(_seq_time / 0.25, 0.0, 1.0)
		global_transform = _seq_from.interpolate_with(_seq_to, k * k * (3.0 - 2.0 * k))
	else:
		# the exit clip carries the body out of the seat; the root stays at the seat until it ends
		global_transform = vehicle.global_transform * _seat_local


func _on_action_finished(anim: StringName) -> void:
	if anim == &"car_enter" and state == State.ENTERING:
		state = State.DRIVING
		vehicle.set_driver(self)
		vehicle_changed.emit(vehicle)
	elif anim == &"car_exit" and state == State.EXITING:
		global_transform = _seq_to
		var v := vehicle
		vehicle = null
		v.set_driver(null)
		state = State.ON_FOOT
		collision_layer = 2
		collision_mask = 1 | 4 | 8 | 16
		cam.mode = CameraRig.Mode.ON_FOOT
		cam.target = self
		visual.jump_to("ground")
		vehicle_changed.emit(null)


func _driving() -> void:
	global_transform = vehicle.global_transform * _seat_local
	if Input.is_action_just_pressed("interact") and vehicle.linear_velocity.length() < 2.5:
		exit_vehicle()


func _process(_delta: float) -> void:
	if state == State.DRIVING or state == State.EXITING:
		# follow the car with the interpolated transform so the driver never jitters
		global_transform = vehicle.get_global_transform_interpolated() * _seat_local


func take_damage(amount: float, _from: Node = null) -> void:
	if state == State.DEAD:
		return
	var absorbed := minf(armor, amount * 0.7)
	armor -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	health_changed.emit(health, armor)


## Test/screenshot helper: put the player straight into the driver's seat (no entry animation).
func debug_seat_in(v: Vehicle) -> void:
	vehicle = v
	state = State.DRIVING
	collision_layer = 0
	collision_mask = 0
	v.reserve(self)
	_seat_local = v.global_transform.affine_inverse() * _seat_root(v)
	global_transform = _seat_root(v)
	visual.jump_to("drive")
	v.set_driver(self)
	cam.mode = CameraRig.Mode.VEHICLE
	cam.target = v
	cam.vehicle_distance = v.camera_distance
	cam.vehicle_height = v.camera_height
	vehicle_changed.emit(v)
