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
		var sens := Game.mouse_sensitivity * (0.6 if mode == Mode.AIM else 1.0)
		yaw -= event.relative.x * sens
		pitch -= event.relative.y * sens * (-1.0 if Game.invert_y else 1.0)
		_idle_look = 0.0
	elif event.is_action_pressed("shoulder_swap"):
		shoulder = -shoulder


func add_recoil(amount: float) -> void:
	_recoil += amount


func _process(delta: float) -> void:
	if not target:
		return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.05:
		var gs := Game.gamepad_sensitivity * (0.55 if mode == Mode.AIM else 1.0)
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
		p = {"dist": vehicle_distance, "height": vehicle_height, "side": 0.0, "fov": 72.0}
		var v := Vector3.ZERO
		if target is RigidBody3D:
			v = (target as RigidBody3D).linear_velocity
		var spd := Vector2(v.x, v.z).length()
		# swing back behind the car when driving and the player isn't steering the camera
		if _idle_look > 1.2 and spd > 3.0:
			var fwd := -tgt_xf.basis.z
			var want := atan2(-fwd.x, -fwd.z)
			yaw = lerp_angle(yaw, want, 1.0 - exp(-delta * 2.5))
		p.fov = 72.0 + clampf(spd - 15.0, 0.0, 25.0) * 0.35
	pitch = clampf(pitch, deg_to_rad(-70), deg_to_rad(55) if mode != Mode.VEHICLE else deg_to_rad(30))

	var k := 1.0 - exp(-delta * 10.0)
	_dist = lerpf(_dist, p.dist, k)
	_height = lerpf(_height, p.height - (0.45 if crouch and mode != Mode.VEHICLE else 0.0), k)
	_side = lerpf(_side, p.side * shoulder, k)
	camera.fov = lerpf(camera.fov, p.fov, k)

	var focus := tgt_xf.origin + Vector3(0, _height, 0)
	_focus = focus if _focus == Vector3.ZERO else _focus.lerp(focus, 1.0 - exp(-delta * (25.0 if mode != Mode.VEHICLE else 12.0)))
	global_position = _focus
	rotation = Vector3(pitch, yaw, 0)
	spring.spring_length = _dist
	spring.position = Vector3(_side, 0, 0)
	if shake > 0.0:
		camera.h_offset = randf_range(-1, 1) * shake * 0.05
		camera.v_offset = randf_range(-1, 1) * shake * 0.05
		shake = move_toward(shake, 0.0, delta * 3.0)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## Horizontal camera basis (yaw only) for camera-relative movement.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func aim_ray(length := 400.0) -> Array:
	var from := camera.global_position
	var to := from - camera.global_basis.z * length
	return [from, to]
