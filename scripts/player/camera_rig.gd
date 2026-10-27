class_name CameraRig
extends Node3D
## Third-person camera: orbit with collision (SpringArm3D), separate on-foot / aim / vehicle framing,
## aim zoom and shoulder swap. Runs in _process on the target's interpolated transform for smoothness.

enum Mode { ON_FOOT, AIM, VEHICLE }

const PRESETS := {
	Mode.ON_FOOT: {"dist": 3.4, "height": 1.55, "side": 0.42, "fov": 68.0},
	Mode.AIM: {"dist": 1.45, "height": 1.58, "side": 0.62, "fov": 50.0},
	Mode.VEHICLE: {"dist": 6.5, "height": 1.7, "side": 0.0, "fov": 72.0},
}

var target: Node3D
var mode := Mode.ON_FOOT
var yaw := 0.0
var pitch := -0.15
var shoulder := 1.0
var vehicle_distance := 6.5
var vehicle_height := 1.7
var shake := 0.0
var crouch := false
## Extra framing from the player's state: widen the view when sprinting, pull back while ragdolled.
var sprinting := false
var ragdolled := false
## Scoped weapons: field of view while aiming (0 = the normal aim view).
var zoom_fov := 0.0
## Field of view setting (Settings → Display), relative to the 70° default; scopes are not scaled.
static var fov_scale := 1.0
## Hidden when the camera is squeezed against the character (back to a wall, tight corners).
var hide_when_close: Node3D
## Vehicle views cycled with camera_mode: 0 chase, 1 far chase, 2 hood, 3 cinematic.
var vehicle_view := 0
const VEHICLE_VIEWS := 4
var _looking_back := false
var _cine_kind := -1          # cinematic shot: 0 roadside (fixed in the world), 1 low side tracking, 2 high chase
var _cine_t := 0.0
var _cine_pos := Vector3.ZERO

var _dist := 3.4
var _height := 1.55
var _side := 0.42
var _idle_look := 0.0
var _focus := Vector3.ZERO
var _recoil := 0.0

@onready var spring: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	spring.collision_mask = 1  # world geometry only
	spring.margin = 0.15
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	spring.shape = sphere


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Game.mouse_sensitivity * (0.6 if mode == Mode.AIM else 1.0) * (zoom_fov / 50.0 if zoom_fov > 0.0 and mode == Mode.AIM else 1.0)
		yaw -= event.relative.x * sens
		pitch -= event.relative.y * sens * (-1.0 if Game.invert_y else 1.0)
		_idle_look = 0.0
	elif event.is_action_pressed("shoulder_swap"):
		shoulder = -shoulder
	elif event.is_action_pressed("camera_mode") and mode == Mode.VEHICLE:
		if event is InputEventJoypadButton:
			_view_down_at = Time.get_ticks_msec()   # on a pad VIEW also opens God Mode when held: act on a tap's release
		else:
			_next_view()
	elif event.is_action_released("camera_mode") and event is InputEventJoypadButton and mode == Mode.VEHICLE \
			and Time.get_ticks_msec() - _view_down_at < int(GodMode.PAD_HOLD * 1000.0 * 0.6):
		_next_view()


var _view_down_at := 0


func _next_view() -> void:
	vehicle_view = (vehicle_view + 1) % VEHICLE_VIEWS
	_cine_kind = -1


func add_recoil(amount: float) -> void:
	_recoil += amount


func _process(delta: float) -> void:
	if not target:
		return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.05:
		var gs := Game.gamepad_sensitivity * (0.55 if mode == Mode.AIM else 1.0) * (zoom_fov / 50.0 if zoom_fov > 0.0 and mode == Mode.AIM else 1.0)
		yaw -= look.x * gs * delta
		pitch -= look.y * gs * 0.7 * delta * (-1.0 if Game.invert_y else 1.0)
		_idle_look = 0.0
	_idle_look += delta
	# recoil kicks the view up and recovers
	pitch += _recoil * delta * 10.0
	_recoil = move_toward(_recoil, 0.0, delta * 3.0)

	var p: Dictionary = PRESETS[mode]
	var tgt_xf := target.get_global_transform_interpolated()
	if mode == Mode.VEHICLE:
		var far := 1.45 if vehicle_view == 1 else 1.0
		p = {"dist": vehicle_distance * far, "height": vehicle_height * (1.2 if vehicle_view == 1 else 1.0), "side": 0.0, "fov": 72.0}
		var v := Vector3.ZERO
		if target is RigidBody3D:
			v = (target as RigidBody3D).linear_velocity
		var spd := Vector2(v.x, v.z).length()
		# swing back behind the car when driving and the player isn't steering the camera
		var fwd := -tgt_xf.basis.z
		var want := atan2(-fwd.x, -fwd.z)
		var back := Input.is_action_pressed("look_behind")
		if back:
			yaw = want + PI
			_focus = Vector3.ZERO
		elif _looking_back:
			yaw = want
			_focus = Vector3.ZERO
		_looking_back = back
		if not back and _idle_look > 1.2 and spd > 3.0:
			yaw = lerp_angle(yaw, want, 1.0 - exp(-delta * 2.5))
		p.fov = 72.0 + clampf(spd - 15.0, 0.0, 25.0) * 0.35
	pitch = clampf(pitch, deg_to_rad(-70), deg_to_rad(55) if mode != Mode.VEHICLE else deg_to_rad(30))

	if mode == Mode.AIM and zoom_fov > 0.0:
		p = p.duplicate()
		p.fov = zoom_fov
	if mode == Mode.ON_FOOT:
		p = p.duplicate()
		if sprinting:
			p.fov += 6.0
			p.dist += 0.35
		if ragdolled:
			p.dist += 1.0
			p.height -= 0.6
	var k := 1.0 - exp(-delta * 10.0)
	_dist = lerpf(_dist, p.dist, k)
	_height = lerpf(_height, p.height - (0.45 if crouch and mode != Mode.VEHICLE else 0.0), k)
	_side = lerpf(_side, p.side * shoulder, k)
	camera.fov = lerpf(camera.fov, p.fov * (fov_scale if zoom_fov <= 0.0 or mode != Mode.AIM else 1.0), k if zoom_fov <= 0.0 else 1.0 - exp(-delta * 18.0))

	# characters can supply a smoother anchor than their root (the pelvis during vaults, climbs, ragdoll)
	var anchor := tgt_xf.origin
	if mode != Mode.VEHICLE and target.has_method("camera_anchor"):
		anchor = target.camera_anchor(tgt_xf.origin)
	var focus := anchor + Vector3(0, _height, 0)
	_focus = focus if _focus == Vector3.ZERO else _focus.lerp(focus, 1.0 - exp(-delta * (25.0 if mode != Mode.VEHICLE else 12.0)))
	global_position = _focus
	rotation = Vector3(pitch, yaw, 0)
	spring.spring_length = _dist
	spring.position = Vector3(_side, 0, 0)
	if mode == Mode.VEHICLE and vehicle_view == 2 and target:
		# hood view: fixed to the car just above the windscreen base, free look with the stick/mouse
		var vt := target.get_global_transform_interpolated()
		var hood: Vector3 = target.get_meta("hood_cam", Vector3(0, 1.3, -0.6))
		var car_yaw := atan2(vt.basis.z.x, vt.basis.z.z)
		var free := Basis(Vector3.UP, PI if _looking_back else (wrapf(yaw - car_yaw, -PI, PI) if _idle_look < 1.5 else 0.0))
		global_transform = Transform3D(vt.basis * free * Basis(Vector3.RIGHT, clampf(pitch, -0.4, 0.3)), vt * hood)
		spring.spring_length = 0.0
		spring.position = Vector3.ZERO
		camera.fov = lerpf(camera.fov, p.fov * fov_scale, k)
	if mode == Mode.VEHICLE and vehicle_view == 3 and target:
		_cinematic(delta)
	if hide_when_close:
		# also hidden through a scope: the zoomed shoulder view would otherwise fill one side with the player's own body
		var scoped := mode == Mode.AIM and zoom_fov > 0.0 and camera.fov < zoom_fov + 10.0
		hide_when_close.visible = (mode == Mode.VEHICLE and vehicle_view != 2) or (mode != Mode.VEHICLE and spring.get_hit_length() > 0.55 and not scoped)
	if shake > 0.0:
		camera.h_offset = randf_range(-1, 1) * shake * 0.05
		camera.v_offset = randf_range(-1, 1) * shake * 0.05
		shake = move_toward(shake, 0.0, delta * 3.0)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## Cinematic vehicle view: cuts between a fixed roadside camera the car drives past, a low tracking shot
## beside the wheels and a high chase. Cuts when a shot has run its course or loses sight of the car.
func _cinematic(delta: float) -> void:
	var vt := target.get_global_transform_interpolated()
	var vel := (target as RigidBody3D).linear_velocity if target is RigidBody3D else Vector3.ZERO
	var car := vt.origin + Vector3(0, 0.9, 0)
	_cine_t += delta
	var space := get_world_3d().direct_space_state
	var cut := _cine_kind < 0 or _cine_t > (7.0 if _cine_kind == 0 else 5.0)
	if _cine_kind == 0 and _cine_pos.distance_to(car) > 45.0 and _cine_t > 1.0:
		cut = true
	if not cut and _cine_t > 0.5:
		var q := PhysicsRayQueryParameters3D.create(camera.global_position, car, 1)
		if not space.intersect_ray(q).is_empty():
			cut = true
	if cut:
		_cine_kind = (_cine_kind + 1 + randi() % 2) % 3
		_cine_t = 0.0
		if _cine_kind == 0:
			# ahead of the car, off to one side, at about head height
			var ahead := vel * 2.2 if vel.length() > 4.0 else -vt.basis.z * 12.0
			var side := vt.basis.x * (6.0 if randf() < 0.5 else -6.0)
			_cine_pos = car + ahead + side + Vector3(0, 0.4, 0)
			var down := PhysicsRayQueryParameters3D.create(_cine_pos + Vector3(0, 10, 0), _cine_pos + Vector3(0, -20, 0), 1)
			var hit := space.intersect_ray(down)
			if hit:
				_cine_pos.y = maxf(_cine_pos.y, hit.position.y + 1.3)
	var pos := _cine_pos
	match _cine_kind:
		1:
			pos = vt * Vector3(2.6, 0.45, -1.2)
		2:
			pos = vt.origin + vt.basis.z * 12.0 + Vector3(0, 7.5, 0)
	global_transform = Transform3D(Basis.IDENTITY, pos)
	spring.spring_length = 0.0
	spring.position = Vector3.ZERO
	if pos.distance_to(car) > 0.5:
		look_at(car + (-vt.basis.z * 2.0 if _cine_kind == 1 else Vector3.ZERO), Vector3.UP)
	camera.fov = lerpf(camera.fov, 50.0 if _cine_kind == 0 else 62.0, 1.0 - exp(-delta * 6.0))


## Horizontal camera basis (yaw only) for camera-relative movement.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func aim_ray(length := 400.0) -> Array:
	var from := camera.global_position
	var to := from - camera.global_basis.z * length
	return [from, to]
