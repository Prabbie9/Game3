class_name Weapon
extends Node3D
## The player's equipped firearm (Milestone 1: pistol). Hit-scan from the crosshair, muzzle flash,
## recoil, reload, per-surface impact effects via the FX helper.

signal ammo_changed(in_mag: int, reserve: int)
signal fired
signal weapon_changed(name: String)

## Equipped slot: 0 = fists, 1 = pistol (the weapon wheel in Milestone 5 extends this).
var slot := 1

const PISTOL := {
	"name": "Pistol", "damage": 34.0, "interval": 0.22, "mag": 12, "reload": 1.4,
	"spread": 0.006, "spread_move": 0.02, "recoil": 0.035, "range": 120.0,
}

var data := PISTOL
var in_mag := 12
var reserve := 72
var _cooldown := 0.0
var _reloading := 0.0
var _player: Player
var _visual: HumanoidVisual
var _cam: CameraRig
var _model: Node3D
var _attach: BoneAttachment3D
var _muzzle: Node3D
var _flash: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_time := 0.0
var _support: Marker3D
var _hand_ik: TwoBoneIK3D


func setup(player: Player, visual: HumanoidVisual, cam: CameraRig) -> void:
	_player = player
	_visual = visual
	_cam = cam
	_attach = BoneAttachment3D.new()
	_attach.bone_name = "RightHand"
	visual.skeleton.add_child(_attach)
	var built := WeaponModel.build("pistol")
	_model = built[0]
	_attach.add_child(_model)
	_model.transform = WeaponMounts.PISTOL_GRIP
	_muzzle = Node3D.new()
	_model.add_child(_muzzle)
	_muzzle.position = built[1]
	_support = Marker3D.new()
	_support.name = "SupportGrip"
	_model.add_child(_support)
	_support.transform = WeaponMounts.PISTOL_SUPPORT
	_hand_ik = visual.install_hand_ik(_support)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.4)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	_muzzle.add_child(_flash)
	_flash_mesh = FX.make_muzzle_flash()
	_muzzle.add_child(_flash_mesh)
	ammo_changed.emit(in_mag, reserve)


func has_weapon() -> bool:
	return _model != null and slot == 1


func is_fists() -> bool:
	return slot == 0


func weapon_name() -> String:
	return "FISTS" if slot == 0 else String(data.name).to_upper()


func select(new_slot: int) -> void:
	slot = clampi(new_slot, 0, 1)
	weapon_changed.emit(weapon_name())


func holster(on: bool) -> void:
	if _model:
		_model.visible = not on


func _process(delta: float) -> void:
	if not _player:
		return
	_cooldown -= delta
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash.light_energy = maxf(0.0, _flash_time / 0.05) * 3.0
		_flash_mesh.visible = _flash_time > 0.02
	if Game.controls_enabled and _player.state == Player.State.ON_FOOT:
		if Input.is_action_just_pressed("weapon_next") or Input.is_action_just_pressed("weapon_prev"):
			select(1 - slot)
	if _model:
		_model.visible = slot == 1 and (_player.state in [Player.State.ON_FOOT, Player.State.COVER] \
				or (_player.state == Player.State.ACTION and not _player.hands_busy()))
	if _hand_ik:
		_hand_ik.influence = clampf((_player.aim_weight - 0.3) / 0.7, 0.0, 1.0) if _model.visible and _reloading <= 0.0 else 0.0
	if _reloading > 0.0:
		_reloading -= delta
		if _reloading <= 0.0:
			var n := mini(data.mag - in_mag, reserve)
			in_mag += n
			reserve -= n
			ammo_changed.emit(in_mag, reserve)
		return
	if _player.state != Player.State.ON_FOOT or not _player.aiming:
		return
	if Input.is_action_just_pressed("reload") and in_mag < data.mag and reserve > 0:
		_reloading = data.reload
		return
	if Input.is_action_just_pressed("fire") and _cooldown <= 0.0 and _player.aim_weight > 0.8:
		if in_mag <= 0:
			if reserve > 0:
				_reloading = data.reload
			return
		_fire()


func _fire() -> void:
	_cooldown = data.interval
	in_mag -= 1
	ammo_changed.emit(in_mag, reserve)
	fired.emit()
	_flash_time = 0.06
	_flash_mesh.rotation.z = randf() * TAU
	var ray := _cam.aim_ray(data.range)
	var from: Vector3 = ray[0]
	var dir: Vector3 = (ray[1] - from).normalized()
	var moving := Vector2(_player.velocity.x, _player.velocity.z).length() > 0.5
	var spread: float = data.spread + (data.spread_move if moving else 0.0)
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * data.range, 1 | 4 | 8 | 16 | 32)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	var end: Vector3 = from + dir * data.range
	if hit:
		end = hit.position
		# make sure the muzzle itself can see the target point (no shooting through walls next to you)
		var q2 := PhysicsRayQueryParameters3D.create(_muzzle.global_position, end + dir * 0.05, 1 | 4 | 8 | 16 | 32)
		q2.exclude = [_player.get_rid()]
		var hit2 := space.intersect_ray(q2)
		if hit2:
			hit = hit2
			end = hit2.position
		var col: Object = hit.collider
		if col and col.has_method("bullet_hit"):
			col.bullet_hit(end, dir, data.damage, _player)
		elif col and col.has_method("take_damage"):
			col.take_damage(data.damage, _player)
		elif col is RigidBody3D:
			(col as RigidBody3D).apply_impulse(dir * 6.0, end - (col as RigidBody3D).global_position)
		FX.impact(get_tree().current_scene, end, hit.normal, FX.surface_of(col))
	FX.tracer(get_tree().current_scene, _muzzle.global_position, end)
	_cam.add_recoil(data.recoil)
	_cam.shake = maxf(_cam.shake, 0.15)
