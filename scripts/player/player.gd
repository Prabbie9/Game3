class_name Player
extends CharacterBody3D
## Third-person player: on-foot locomotion, crouch, vault/climb, cover, melee, swimming, ragdoll falls,
## aiming/shooting and vehicle enter/exit.

signal health_changed(health: float, armor: float)
signal vehicle_changed(vehicle: Node)

enum State { ON_FOOT, ENTERING, DRIVING, EXITING, DEAD, ACTION, COVER, SWIM, RAGDOLL }

const GRAVITY := 18.0
const JUMP_VELOCITY := 5.2
const TURN_RATE := 11.0
const SPRINT_BOOST := 1.18  # sprint faster than the clip's native speed; playback speeds up to match
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const SWIM_DEPTH := 1.25    # water deeper than this (at the feet) means swimming
const SWIM_BOOST := 2.6     # surface swim is faster than the slow underwater clip; playback scales with it
const HARD_LANDING := 9.0   # fall speeds (m/s) for a hard landing / ragdoll
const RAGDOLL_FALL := 15.0
const MASK_ON_FOOT := 1 | 4 | 8 | 16

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
var foot_ik: FootIK
var ragdoll: Ragdoll
var crouched := false
var spawn_point := Transform3D()

# action (root-motion) state
var _act := ""
var _act_t := 0.0
var _act_len := 0.0
var _act_start := Transform3D()
var _act_from := Transform3D()
var _act_height := -1.0  # obstacle/ledge height for traversal clips (-1 = none)
var _act_blend := 0.18
var _act_next := ""  # chained action (jump to hang -> climb)
var _act_hit_done := false
# cover
var _cover_normal := Vector3.ZERO
var _cover_low := false
# melee
var _combo := 0
var _combo_window := 0.0
# ragdoll
var _rag_time := 0.0
var _respawn_timer := -1.0
var _capsule: CapsuleShape3D
@onready var _col: CollisionShape3D = $Collision

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
	foot_ik = FootIK.install(visual.skeleton, self)
	ragdoll = Ragdoll.new(visual.skeleton)
	_capsule = _col.shape
	spawn_point = global_transform


func _physics_process(delta: float) -> void:
	_combo_window -= delta
	match state:
		State.ON_FOOT:
			_on_foot(delta)
		State.ENTERING, State.EXITING:
			_sequence(delta)
		State.DRIVING:
			_driving()
		State.ACTION:
			_action(delta)
		State.COVER:
			_cover(delta)
		State.SWIM:
			_swim(delta)
		State.RAGDOLL, State.DEAD:
			_ragdolled(delta)


func _on_foot(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if Game.controls_enabled else Vector2.ZERO
	var move_dir := cam.flat_basis() * Vector3(input.x, 0, input.y)
	aiming = Game.controls_enabled and Input.is_action_pressed("aim") and weapon.has_weapon()
	aim_weight = move_toward(aim_weight, 1.0 if aiming else 0.0, delta * 6.0)
	if aiming and crouched:
		_set_crouch(false)
	if Game.controls_enabled and Input.is_action_just_pressed("crouch") and is_on_floor():
		_set_crouch(not crouched)
	if _water_depth() > SWIM_DEPTH:
		_enter_swim()
		return
	if Game.controls_enabled and weapon.is_fists() and Input.is_action_just_pressed("fire") and is_on_floor():
		_punch()
		return
	if Game.controls_enabled and Input.is_action_just_pressed("cover") and is_on_floor() and _try_cover():
		return
	# turn in place: a sharp change of direction from standing still pivots with a turn clip
	if Game.controls_enabled and input.length() > 0.5 and not aiming and not crouched and is_on_floor() \
			and Vector2(velocity.x, velocity.z).length() < 0.3:
		var want_yaw := atan2(-move_dir.x, -move_dir.z)
		var diff := wrapf(want_yaw - rotation.y, -PI, PI)
		if absf(diff) > deg_to_rad(135):
			_start_action("turn_180", true)
			return

	var target_speed := 0.0
	if input.length() > 0.1:
		var mag := clampf(input.length(), 0.0, 1.0)
		if aiming:
			target_speed = visual.aim_run_speed if Input.is_action_pressed("sprint") else visual.aim_walk_speed
		elif crouched:
			target_speed = visual.crouch_speed * clampf(mag, 0.6, 1.0)
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
			if _fall_speed > RAGDOLL_FALL:
				take_damage((_fall_speed - RAGDOLL_FALL) * 6.0 + 25.0)
				go_ragdoll(velocity)
				return
			elif _fall_speed > HARD_LANDING:
				take_damage((_fall_speed - HARD_LANDING) * 3.0)
				_start_action("hard_land", false)
				return
			visual.travel("land" if _fall_speed > 4.0 else ("crouch" if crouched else "ground"))
		_air_time = 0.0
		_fall_speed = 0.0
		if _jump_timer >= 0.0:
			# short wind-up so the take-off frame of the clip lines up with leaving the ground
			_jump_timer -= delta
			velocity.y = -0.5
			if _jump_timer < 0.0:
				velocity.y = JUMP_VELOCITY
		elif Game.controls_enabled and Input.is_action_just_pressed("jump") and not aiming and _try_traverse():
			return
		elif Game.controls_enabled and Input.is_action_just_pressed("jump") and not aiming:
			if crouched:
				_set_crouch(false)
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
	if crouched:
		visual.set_state_blend("crouch", speed, visual.crouch_speed)
	# feet adapt to the ground when grounded; lighter while sprinting so strides stay natural
	foot_ik.weight = clampf(1.0 - (speed - visual.run_speed) / 3.0, 0.4, 1.0) if on_floor and _jump_timer < 0.0 else 0.0
	var local := global_basis.inverse() * velocity
	visual.set_aim(Vector2(local.x, -local.z), aim_weight)
	cam.mode = CameraRig.Mode.AIM if aiming else CameraRig.Mode.ON_FOOT
	cam.crouch = crouched

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
	foot_ik.weight = 0.0
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


# --- crouch ----------------------------------------------------------------

func _set_crouch(on: bool) -> void:
	if not on and crouched and _blocked_above(STAND_HEIGHT):
		return
	crouched = on
	_capsule.height = CROUCH_HEIGHT if on else STAND_HEIGHT
	_col.position.y = _capsule.height * 0.5
	visual.travel("crouch" if on else "ground")


func _blocked_above(h: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, h + 0.05, 0), 1 | 16)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- root-motion actions (vault, climb, turns, punches, landings, get-ups) ------------

func _start_action(act: String, keep_collision: bool, start := Transform3D(), height := -1.0, blend := 0.18) -> void:
	state = State.ACTION
	_act = act
	_act_t = 0.0
	_act_len = visual.action_duration(act)
	_act_start = start if start != Transform3D() else global_transform
	_act_from = global_transform
	_act_height = height
	_act_blend = blend
	_act_hit_done = false
	_air_time = 0.0
	_fall_speed = 0.0
	_jump_timer = -1.0
	velocity = Vector3.ZERO
	if not keep_collision:
		collision_layer = 0
		collision_mask = 0
	foot_ik.weight = 0.0 if not keep_collision else foot_ik.weight
	visual.set_aim(Vector2.ZERO, 0.0)
	aim_weight = 0.0
	visual.travel(act)


## True while an action needs both hands (traversal, getting up): the pistol is tucked away.
func hands_busy() -> bool:
	return state == State.ACTION and (_act.begins_with("vault") or _act in ["climb", "jump_hang"] or _act.begins_with("get_up"))


## Vertical shift that fits a traversal clip to the real obstacle height at action time t.
func _traverse_offset(act: String, t: float, height: float) -> float:
	if height < 0.0 or not AnimLib.TRAVERSE.has(act):
		return 0.0
	var spec: Array = AnimLib.TRAVERSE[act]
	var off: float = height - (float(spec[0]) if float(spec[0]) > 0.0 else visual.path_ledge(act))
	match String(spec[1]):
		"ramp":
			return off * smoothstep(float(spec[2]), float(spec[3]), t)
		"bump":
			if t < float(spec[3]):
				return off * smoothstep(float(spec[2]), float(spec[3]), t)
			return off * (1.0 - smoothstep(float(spec[3]), float(spec[4]), t))
	return off


func _action(delta: float) -> void:
	_act_t += delta
	var k := minf(_act_t, _act_len)
	if AnimLib.paths.has(_act):
		var target := _act_start * visual.path_transform(_act, k)
		target.origin.y += _traverse_offset(_act, k, _act_height)
		# ease from where we were into the action's start pose over the first frames (no visible snap)
		var b := clampf(_act_t / _act_blend, 0.0, 1.0) if _act_blend > 0.0 else 1.0
		global_transform = _act_from.interpolate_with(target, b * b * (3.0 - 2.0 * b)) if b < 1.0 else target
	if _act.begins_with("punch") and not _act_hit_done and _act_t > _act_len * 0.38:
		_act_hit_done = true
		_melee_hit()
	foot_ik.weight = 1.0 if _act.begins_with("turn") or _act.begins_with("punch") or _act.begins_with("hit") else 0.0
	if _act_t >= _act_len:
		if _act_next != "":
			# continue straight into the chained clip from the same pose: back to the un-shifted frame, no blend
			var next := _act_next
			_act_next = ""
			var base := global_transform
			base.origin.y -= _traverse_offset(_act, _act_len, _act_height)
			_start_action(next, false, base, _act_height, 0.0)
			return
		_end_action()


func _end_action() -> void:
	state = State.ON_FOOT
	collision_layer = 2
	collision_mask = MASK_ON_FOOT
	# settle onto whatever is below (climbs end on a ledge, vaults on the far side)
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.6, 0), global_position + Vector3(0, -1.2, 0), 1 | 8 | 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		global_position.y = hit.position.y
	rotation = Vector3(0, rotation.y, 0)
	if _act.begins_with("punch"):
		_combo_window = 0.45
	visual.travel("crouch" if crouched else "ground")
	_act = ""


func _try_traverse() -> bool:
	var plan := Traversal.analyse(get_world_3d(), global_transform, [get_rid()])
	if plan.is_empty():
		return false
	if crouched:
		_set_crouch(false)
	if plan.type == "climb" and plan.height >= Traversal.HANG_ABOVE:
		_act_next = "climb"
		_start_action("jump_hang", false, plan.start, plan.height)
	else:
		_act_next = ""
		_start_action(String(plan.clip), false, plan.start, plan.height)
	return true


# --- melee -------------------------------------------------------------------

func _punch() -> void:
	var chain := ["punch_jab", "punch_cross", "punch_hook"]
	_combo = (_combo + 1) % 3 if _combo_window > 0.0 else 0
	# face where the camera looks so punches land on what the player is looking at
	rotation.y = cam.yaw
	_start_action(chain[_combo], true)


func _melee_hit() -> void:
	# a capsule in front of the chest, from the hips to the head, so low and high targets both connect
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 1.05, 0) - global_basis.z * 0.7)
	q.collision_mask = 4 | 8 | 16
	q.exclude = [get_rid()]
	for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c: Object = r.collider
		if c and c.has_method("take_damage"):
			c.take_damage(12.0 if _combo < 2 else 22.0, self)
		elif c is RigidBody3D:
			(c as RigidBody3D).apply_impulse(-global_basis.z * 60.0 + Vector3(0, 15, 0))
	cam.shake = maxf(cam.shake, 0.25)


# --- cover -------------------------------------------------------------------

func _try_cover() -> bool:
	var spot := CoverSpot.find(get_world_3d(), global_position, -cam.flat_basis().z, [get_rid()])
	if spot.is_empty():
		return false
	if crouched:
		_set_crouch(false)
	state = State.COVER
	_cover_normal = spot.normal
	_cover_low = spot.low
	velocity = Vector3.ZERO
	global_position = spot.point
	rotation.y = atan2(-_cover_normal.x, -_cover_normal.z) + CoverSpot.FACING
	visual.travel("cover_low" if _cover_low else "cover")
	return true


func _cover(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if Game.controls_enabled else Vector2.ZERO
	var leave := Game.controls_enabled and (Input.is_action_just_pressed("cover") or Input.is_action_just_pressed("jump") or Input.is_action_pressed("aim"))
	# move along the wall with camera-relative left/right
	var tangent := Vector3.UP.cross(_cover_normal).normalized()  # wall-right as seen facing the wall
	var cam_right := cam.flat_basis().x
	var side := input.x * signf(cam_right.dot(tangent)) if absf(cam_right.dot(tangent)) > 0.2 else -input.y * signf(-cam.flat_basis().z.dot(tangent))
	var away := -cam.flat_basis().z.dot(_cover_normal) * -input.y + cam_right.dot(_cover_normal) * input.x
	if away > 0.85:
		leave = true
	var spd := side * visual.cover_speed
	var next := global_position + tangent * spd * delta
	var spot := CoverSpot.probe(get_world_3d(), next, _cover_normal, [get_rid()])
	if spot.is_empty():
		spd = 0.0  # end of the wall: stop at the edge
	else:
		_cover_normal = spot.normal
		global_position = Vector3(spot.point.x, global_position.y, spot.point.z)
		_cover_low = spot.low
	rotation.y = lerp_angle(rotation.y, atan2(-_cover_normal.x, -_cover_normal.z) + CoverSpot.FACING, 1.0 - exp(-delta * 10.0))
	var lateral := spd * CoverSpot.SIDE_SIGN
	var st := "cover_low" if _cover_low else "cover"
	if visual.current_state() != StringName(st):
		visual.travel(st)
	visual.set_state_blend(st, lateral, visual.cover_speed)
	foot_ik.weight = 1.0
	if leave:
		state = State.ON_FOOT
		visual.travel("ground")


# --- swimming ----------------------------------------------------------------

## Depth of water above the feet (0 if not in water).
func _water_depth() -> float:
	for w in get_tree().get_nodes_in_group("water"):
		var d: float = w.depth_at(global_position)
		if d > 0.0:
			return d
	return 0.0


func _surface_y() -> float:
	for w in get_tree().get_nodes_in_group("water"):
		if w.depth_at(global_position) > 0.0:
			return w.surface_y()
	return global_position.y


func _enter_swim() -> void:
	state = State.SWIM
	if crouched:
		_set_crouch(false)
	foot_ik.weight = 0.0
	visual.travel("swim")
	cam.mode = CameraRig.Mode.ON_FOOT


func _swim(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if Game.controls_enabled else Vector2.ZERO
	var move_dir := cam.flat_basis() * Vector3(input.x, 0, input.y)
	var target := visual.swim_speed * SWIM_BOOST * (1.4 if Input.is_action_pressed("sprint") else 1.0)
	var want := move_dir.normalized() * target * clampf(input.length(), 0.0, 1.0)
	var hvel := Vector3(velocity.x, 0, velocity.z).move_toward(want, delta * 3.0)
	if move_dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-move_dir.x, -move_dir.z), 1.0 - exp(-delta * 4.0))
	# float with the hips just under the surface; gentle bob
	var want_y := _surface_y() - visual.clip_hip_height("swim") - 0.05 + sin(Time.get_ticks_msec() * 0.002) * 0.04
	velocity = Vector3(hvel.x, (want_y - global_position.y) * 4.0, hvel.z)
	move_and_slide()
	visual.set_state_blend("swim", hvel.length() / SWIM_BOOST, visual.swim_speed)
	# climb out where it gets shallow
	if _water_depth() < SWIM_DEPTH - 0.25:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), global_position + Vector3(0, -0.6, 0), 1 | 16)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			global_position.y = hit.position.y
			state = State.ON_FOOT
			visual.travel("ground")


# --- ragdoll / death ---------------------------------------------------------

func go_ragdoll(vel: Vector3, impulse := Vector3.ZERO) -> void:
	if state == State.RAGDOLL or state == State.DEAD:
		return
	state = State.RAGDOLL if health > 0.0 else State.DEAD
	_rag_time = 0.0
	_air_time = 0.0
	_fall_speed = 0.0
	_jump_timer = -1.0
	foot_ik.weight = 0.0
	aim_weight = 0.0
	collision_layer = 0
	collision_mask = 0
	ragdoll.start(vel, impulse)


func _ragdolled(delta: float) -> void:
	_rag_time += delta
	# keep the (invisible) root under the pelvis so the camera follows the body
	var hips := ragdoll.hips_transform().origin
	var q := PhysicsRayQueryParameters3D.create(hips + Vector3(0, 0.5, 0), hips + Vector3(0, -2.0, 0), 1 | 8 | 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	global_position = Vector3(hips.x, hit.position.y if hit else hips.y - 0.15, hips.z)
	if state == State.DEAD:
		if _respawn_timer < 0.0:
			_respawn_timer = 4.0
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	if _rag_time > 1.2 and ragdoll.hips_speed() < 0.35:
		_get_up()


func _get_up() -> void:
	var down := ragdoll.face_down()
	var hx := ragdoll.hips_transform()
	# stand up facing along the body: from the back the clip turns ~75°, from the front ~180°
	var head_dir := hx.basis.y  # bone +Y runs up the spine
	head_dir.y = 0
	var yaw := atan2(-head_dir.x, -head_dir.z) if head_dir.length() > 0.1 else rotation.y
	ragdoll.stop()
	rotation = Vector3(0, yaw + (PI if not down else 0.0), 0)
	_start_action("get_up_front" if down else "get_up_back", true)
	collision_layer = 2
	collision_mask = MASK_ON_FOOT


func _respawn() -> void:
	ragdoll.stop()
	_respawn_timer = -1.0
	health = 100.0
	armor = 0.0
	health_changed.emit(health, armor)
	global_transform = spawn_point
	velocity = Vector3.ZERO
	collision_layer = 2
	collision_mask = MASK_ON_FOOT
	state = State.ON_FOOT
	visual.jump_to("ground")
	Game.message("You woke up a little bruised.")


func take_damage(amount: float, _from: Node = null) -> void:
	if state == State.DEAD:
		return
	var absorbed := minf(armor, amount * 0.7)
	armor -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	health_changed.emit(health, armor)
	if health <= 0.0:
		if state == State.RAGDOLL:
			state = State.DEAD
		else:
			go_ragdoll(velocity)


## Test/screenshot helper: put the player straight into the driver's seat (no entry animation).
func debug_seat_in(v: Vehicle) -> void:
	vehicle = v
	state = State.DRIVING
	collision_layer = 0
	collision_mask = 0
	foot_ik.weight = 0.0
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
