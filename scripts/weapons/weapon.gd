class_name Weapon
extends Node3D
## The player's arsenal: owned weapons and ammo, the held weapon's model in the right hand (AimPose places it
## and the left-hand support target every frame), firing (hit-scan bullets and pellets, rockets, thrown
## grenades), reloads, recoil and spread bloom, sniper zoom, gamepad aim assist and drive-by shooting.
## Melee swings are root-motion actions run by the Player; this only says which weapon is out.

signal ammo_changed(in_mag: int, reserve: int)
signal fired
signal weapon_changed(name: String)
signal inventory_changed

const SHOT_MASK := 1 | 4 | 8 | 16 | 32
const BLOOM_RECOVER := 1.5

## Currently selected weapon id (see WeaponDefs.ORDER).
var current := "fists"
## id -> true for every weapon carried.
var owned := {"fists": true}
## id -> [in magazine, reserve]
var ammo := {}
var data: Dictionary = WeaponDefs.DEFS.fists
var in_mag: int:
	get:
		return int(ammo.get(current, [0, 0])[0])
var reserve: int:
	get:
		return int(ammo.get(current, [0, 0])[1])
## True while shooting from a vehicle seat.
var drive_by := false
## Right-hand target while shooting from a bike (the Player's handlebar IK reads it).
var drive_by_hand := Transform3D()

var _cooldown := 0.0
var _reloading := 0.0
var _bloom := 0.0
var _pump := 0.0
var _player: Player
var _visual: HumanoidVisual
var _cam: CameraRig
var _models := {}
var _model: Node3D
var _muzzle: Node3D
var _flash: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_time := 0.0
var _support: Marker3D
var _hand_ik: TwoBoneIK3D
var _pose: AimPose
var _arm_ik: TwoBoneIK3D
var _arm_target: Marker3D
var _arm_pole: Marker3D
var _support_w := 0.0
var _throw_t := -1.0
var _drive_by_w := 0.0
var _assist_target: Node3D


func setup(player: Player, visual: HumanoidVisual, cam: CameraRig) -> void:
	_player = player
	_visual = visual
	_cam = cam
	_pose = AimPose.new()
	_pose.name = "AimPose"
	visual.skeleton.add_child(_pose)
	_support = Marker3D.new()
	_support.name = "SupportGrip"
	_support.top_level = true
	add_child(_support)
	_pose.support_target = _support
	_hand_ik = visual.install_hand_ik(_support)
	var pole := _support.get_node("ElbowPole") as Node3D
	pole.top_level = true
	_pose.support_pole = pole
	_muzzle = Node3D.new()
	add_child(_muzzle)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.4)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	_flash_mesh = FX.make_muzzle_flash()
	give("pistol", 72)
	select("pistol")


# --- inventory ---------------------------------------------------------------

## Add a weapon (or just ammo if already carried). Returns true if anything was added.
func give(id: String, rounds := -1) -> bool:
	var d := WeaponDefs.def_of(id)
	var new := not owned.has(id)
	owned[id] = true
	if d.kind == "melee":
		inventory_changed.emit()
		return new
	if rounds < 0:
		rounds = int(d.get("ammo_pack", d.get("mag", 1)))
	var a: Array = ammo.get(id, [0, 0])
	var before: int = a[0] + a[1]
	if d.kind == "throw":
		a[0] = mini(int(a[0]) + rounds, int(d.max))
	else:
		if new:
			var fill := mini(rounds, int(d.mag))
			a[0] = fill
			rounds -= fill
		a[1] = mini(int(a[1]) + rounds, int(d.max))
	ammo[id] = a
	if id == current:
		ammo_changed.emit(a[0], a[1])
	inventory_changed.emit()
	return new or int(a[0]) + int(a[1]) > before


## Arrested: everything but the fists is kept by the police.
func confiscate() -> void:
	owned = {"fists": true}
	ammo.clear()
	select("fists")
	inventory_changed.emit()


func has(id: String) -> bool:
	return owned.has(id)


## Ammo is full for this weapon (shops and pickups stop offering more).
func ammo_full(id: String) -> bool:
	var d := WeaponDefs.def_of(id)
	if d.kind == "melee" or not ammo.has(id):
		return d.kind == "melee" and owned.has(id)
	var a: Array = ammo[id]
	return (int(a[0]) >= int(d.max)) if d.kind == "throw" else (int(a[1]) >= int(d.max))


func owned_list() -> Array:
	return WeaponDefs.ORDER.filter(func(id): return owned.has(id))


func select(id: String) -> void:
	if not owned.has(id):
		return
	current = id
	data = WeaponDefs.def_of(id)
	_reloading = 0.0
	_bloom = 0.0
	_throw_t = -1.0
	_show_model(String(data.get("model", "")))
	weapon_changed.emit(weapon_name())
	var a: Array = ammo.get(id, [0, 0])
	ammo_changed.emit(int(a[0]), int(a[1]) if data.kind != "throw" else -1)


func cycle(step: int) -> void:
	var list := owned_list()
	var i := list.find(current)
	select(list[(i + step + list.size()) % list.size()])


func has_weapon() -> bool:
	return data.kind != "melee"


func is_fists() -> bool:
	return current == "fists"


func is_melee() -> bool:
	return data.kind == "melee"


func is_long_gun() -> bool:
	return int(data.get("stance", 0)) == 1


func weapon_name() -> String:
	return String(data.name).to_upper()


func holster(on: bool) -> void:
	if _model:
		_model.visible = not on


func reloading() -> bool:
	return _reloading > 0.0


## Camera field of view while aiming (0 = the normal aim view).
func zoom_fov() -> float:
	return float(data.get("zoom", 0.0))


func scoped() -> bool:
	return zoom_fov() > 0.0 and _player.aiming and _player.aim_weight > 0.9 and _player.state == Player.State.ON_FOOT


## Current spread cone (radians) for the crosshair.
func spread() -> float:
	var moving := Vector2(_player.velocity.x, _player.velocity.z).length() > 0.5
	return float(data.get("spread", 0.0)) + (float(data.get("spread_move", 0.0)) if moving else 0.0) + _bloom


# --- models ------------------------------------------------------------------

func _show_model(model_id: String) -> void:
	if _model:
		_model.visible = false
	_model = null
	_pose.model = null
	if model_id == "":
		return
	if not _models.has(model_id):
		var root: Node3D
		var muzzle := Vector3.ZERO
		var support := Transform3D()
		if model_id == "pistol":
			var built := WeaponModel.build("pistol")
			root = built[0]
			muzzle = built[1]
			support = WeaponMounts.PISTOL_SUPPORT
		else:
			root = (load("res://assets/models/weapons/%s.scn" % model_id) as PackedScene).instantiate()
			var m := root.get_node_or_null("Muzzle") as Node3D
			muzzle = m.position if m else Vector3.ZERO
			var s := root.get_node_or_null("Support") as Node3D
			support = Transform3D(WeaponMounts.LONG_SUPPORT_BASIS, s.position if s else Vector3.ZERO)
		root.top_level = true
		add_child(root)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.set_meta("muzzle", muzzle)
		root.set_meta("support", support)
		_models[model_id] = root
	_model = _models[model_id]
	_model.visible = true
	_pose.model = _model
	_pose.mount = WeaponMounts.grip(model_id)
	_pose.support_local = _model.get_meta("support")
	var sl: Transform3D = _pose.support_local
	# elbow: pistol (two-hand grip) as tuned with M2; long guns under and outside the fore-end
	_pose.pole_local = sl * Vector3(-0.35, -0.45, 0.25) if model_id == "pistol" else sl.origin + Vector3(-0.32, -0.5, 0.18)
	_muzzle.reparent(_model, false)
	_muzzle.position = _model.get_meta("muzzle")
	if _flash.get_parent():
		_flash.reparent(_muzzle, false)
		_flash_mesh.reparent(_muzzle, false)
	else:
		_muzzle.add_child(_flash)
		_muzzle.add_child(_flash_mesh)
	_flash.position = Vector3.ZERO
	_flash_mesh.position = Vector3.ZERO
	_flash_mesh.scale = Vector3.ONE * (1.4 if is_long_gun() else 1.0)


# --- per frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not _player:
		return
	_cooldown -= delta
	_bloom = move_toward(_bloom, 0.0, delta * BLOOM_RECOVER * maxf(0.02, float(data.get("bloom", 0.0))) * 8.0)
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash.light_energy = maxf(0.0, _flash_time / 0.05) * 3.0
		_flash_mesh.visible = _flash_time > 0.02
	var st := _player.state
	var on_foot := st == Player.State.ON_FOOT
	if Game.controls_enabled and on_foot and not WeaponWheel.open:
		if Input.is_action_just_pressed("weapon_next"):
			cycle(1)
		elif Input.is_action_just_pressed("weapon_prev"):
			cycle(-1)
	_update_drive_by(delta)
	_update_arc()
	var shown := (st in [Player.State.ON_FOOT, Player.State.COVER] or (st == Player.State.ACTION and not _player.hands_busy())) \
			or drive_by
	if _model:
		_model.visible = shown and not (current == "grenade" and in_mag <= 0)
	# stance, spine pitch and the support hand
	_visual.set_stance(1.0 if is_long_gun() and on_foot else 0.0)
	var aim_w := _player.aim_weight if on_foot else 0.0
	_pose.weight = aim_w
	_pose.pitch = _cam.pitch
	_pose.axis = _player.global_basis.x
	var want_support := 0.0
	if _model and _model.visible and _reloading <= 0.0 and not _visual.upper_active() and on_foot:
		if is_long_gun():
			want_support = 1.0
		elif current == "pistol":
			want_support = clampf((aim_w - 0.3) / 0.7, 0.0, 1.0)
	if st == Player.State.ACTION and _player.current_action().begins_with("bat"):
		want_support = 1.0
	_support_w = move_toward(_support_w, want_support, delta * 6.0)
	_hand_ik.influence = _support_w
	if _reloading > 0.0:
		_reloading -= delta
		if _reloading <= 0.0:
			var a: Array = ammo[current]
			var n := mini(int(data.mag) - int(a[0]), int(a[1]))
			a[0] = int(a[0]) + n
			a[1] = int(a[1]) - n
			ammo_changed.emit(a[0], a[1])
		return
	if _pump > 0.0:
		_pump -= delta
		if _pump <= 0.0 and _model:
			Audio.play_at(Audio.stream("weapons/pump.ogg"), _model.global_position, -6.0, randf_range(0.95, 1.05))
	if _throw_t >= 0.0:
		_throw_t += delta
		if _throw_t >= 0.62:
			_throw_t = -1.0
			_release_grenade()
		return
	if not Game.controls_enabled or WeaponWheel.open:
		return
	if drive_by:
		_trigger(true)
		return
	if not on_foot:
		return
	if data.kind == "throw":
		if Input.is_action_just_pressed("fire") and _cooldown <= 0.0 and in_mag > 0:
			_throw()
		return
	if not has_weapon() or not _player.aiming:
		return
	_aim_assist(delta)
	if Input.is_action_just_pressed("reload") and in_mag < int(data.mag) and reserve > 0:
		_start_reload()
		return
	_trigger(false)


func _trigger(from_vehicle: bool) -> void:
	var act := "vehicle_fire" if from_vehicle else "fire"
	var held := Input.is_action_pressed(act) if data.get("auto", false) else Input.is_action_just_pressed(act)
	if not held or _cooldown > 0.0:
		return
	if not from_vehicle and _player.aim_weight < 0.8:
		return
	if in_mag <= 0:
		if reserve > 0:
			_start_reload()
		elif Input.is_action_just_pressed(act):
			Audio.play_at(Audio.stream("weapons/dry_fire.ogg"), _muzzle.global_position, -8.0)
			_cooldown = 0.25
		return
	_fire()


func _start_reload() -> void:
	_reloading = float(data.reload)
	if drive_by:
		_reloading *= 1.2
	else:
		var clip := String(data.get("reload_clip", ""))
		if clip != "" and AnimLib.get_library().has_animation(clip):
			_visual.play_upper(clip, _visual.clip_length(clip) / maxf(_reloading, 0.1))
	if data.has("reload_sound"):
		var snd := Audio.stream("weapons/%s.ogg" % data.reload_sound)
		var at := _player.global_position + Vector3(0, 1.2, 0)
		get_tree().create_timer(_reloading * 0.35).timeout.connect(func():
			Audio.play_at(snd, at, -6.0, randf_range(0.95, 1.05)))


# --- firing ------------------------------------------------------------------

func _fire() -> void:
	_cooldown = float(data.interval)
	var a: Array = ammo[current]
	a[0] = int(a[0]) - 1
	ammo_changed.emit(a[0], a[1])
	fired.emit()
	_flash_time = 0.06
	_flash_mesh.rotation.z = randf() * TAU
	var vol := float(data.get("volume", 0.0))
	var snd := Audio.pick("weapons/%s.ogg" % String(data.sound), int(data.get("sounds", 1)))
	Audio.play_at(snd, _muzzle.global_position, vol, randf_range(0.94, 1.06), &"SFX", 260.0)
	var ray := _cam.aim_ray(float(data.range))
	var from: Vector3 = ray[0]
	var aim_dir: Vector3 = (ray[1] - from).normalized()
	# start the trace at the player's depth along the view so nothing between camera and player is hit
	from += aim_dir * maxf(0.0, (_muzzle.global_position - from).dot(aim_dir) - 0.3)
	Game.stat_add("shots")
	if data.kind == "launcher":
		_launch_rocket(from, aim_dir)
	else:
		var sp := spread()
		var hit_someone := false
		for i in int(data.get("pellets", 1)):
			var dir := (aim_dir + _cone(sp)).normalized()
			if _bullet(from, dir, float(data.damage), i == 0 or i % 3 == 0):
				hit_someone = true
		if hit_someone:
			Game.stat_add("hits")
		_bloom = minf(_bloom + float(data.get("bloom", 0.0)), float(data.get("max_bloom", 0.03)))
	_cam.add_recoil(float(data.recoil) * (0.6 if _player.crouched else 1.0))
	_cam.shake = maxf(_cam.shake, 0.15 + float(data.recoil) * 2.0)
	if data.get("pump", false):
		_pump = 0.35
	if int(a[0]) <= 0 and int(a[1]) > 0 and data.kind == "launcher":
		_start_reload()
	Game.noise(_player.global_position, 60.0 if data.kind != "launcher" else 120.0, _player)
	Game.crime("shooting", _player.global_position)


func _cone(radius: float) -> Vector3:
	if radius <= 0.0:
		return Vector3.ZERO
	var r := radius * sqrt(randf())
	var t := randf() * TAU
	var b := _cam.camera.global_basis
	return b.x * cos(t) * r + b.y * sin(t) * r


## Returns true when it hit a person.
func _bullet(from: Vector3, dir: Vector3, damage: float, tracer: bool) -> bool:
	var range: float = data.range
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = [_player.get_rid()]
	if drive_by and _player.vehicle:
		excl.append(_player.vehicle.get_rid())
	var end: Vector3 = from + dir * range
	# the muzzle itself must see the aim point (no shooting through a wall you stand next to)
	var q0 := PhysicsRayQueryParameters3D.create(from, end, SHOT_MASK)
	q0.exclude = excl
	var first := space.intersect_ray(q0)
	var aim_end: Vector3 = first.position if first else end
	var start := _muzzle.global_position
	var dir2 := (aim_end + dir * 0.05 - start).normalized()
	var hit := Weapon.trace(space, start, dir2, start.distance_to(aim_end) + (range if not first else 0.1), excl)
	var person := false
	if hit:
		end = hit.position
		person = hit.has("zone")
		if hit.get("zone", "") == "head":
			Game.stat_add("headshots")
		Weapon.apply_hit(get_tree().current_scene, hit, dir2, damage, _player)
	elif first:
		end = aim_end
	if tracer:
		FX.tracer(get_tree().current_scene, start, end)
	return person


## A bullet's path: the first thing it really hits. Characters are tested against their limbs (ray_test),
## so a shot through the gap under an arm carries on. Returns the ray hit (plus "zone" for characters) or {}.
static func trace(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float, exclude: Array[RID], mask := SHOT_MASK) -> Dictionary:
	var excl := exclude.duplicate()
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * length, mask)
		q.exclude = excl
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var col: Object = hit.collider
		if col and col.has_method("ray_test"):
			var r: Dictionary = col.ray_test(from, dir)
			if r.is_empty():
				excl.append(hit.rid)
				continue
			hit.position = r.pos
			hit.zone = r.zone
			hit.normal = -dir
		return hit
	return {}


## Deliver a bullet to whatever a ray hit: characters (hit zones), vehicles, props; effects and sound by surface.
static func apply_hit(scene: Node, hit: Dictionary, dir: Vector3, damage: float, source: Node) -> void:
	var col: Object = hit.collider
	var pos: Vector3 = hit.position
	var surface := FX.surface_of(col)
	if col and col.has_method("bullet_hit"):
		if hit.has("zone"):
			col.bullet_hit(pos, dir, damage, source, hit.zone)
		else:
			col.bullet_hit(pos, dir, damage, source)
	elif col and col.has_method("take_damage"):
		col.take_damage(damage, source)
	elif col is RigidBody3D:
		(col as RigidBody3D).apply_impulse(dir * 6.0, pos - (col as RigidBody3D).global_position)
	FX.impact(scene, pos, hit.normal, surface)
	var kind := "flesh" if surface == FX.Surface.FLESH else ("metal" if surface == FX.Surface.METAL else "hard")
	if randf() < 0.7 or kind == "flesh":
		Audio.play_at(Audio.pick("weapons/bullet_%s_%%d.ogg" % kind, 2), pos, -8.0 if kind != "flesh" else -4.0, randf_range(0.9, 1.1), &"SFX", 40.0)


func _launch_rocket(from: Vector3, dir: Vector3) -> void:
	var target := from + dir * float(data.range)
	var q := PhysicsRayQueryParameters3D.create(from, target, SHOT_MASK)
	q.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		target = hit.position
	var start := _muzzle.global_position
	var r := Rocket.new()
	r.source = _player
	r.damage = float(data.damage)
	get_tree().current_scene.add_child(r)
	r.launch(start, (target - start).normalized())


func _throw() -> void:
	_cooldown = float(data.interval)
	_throw_t = 0.0
	_visual.play_upper("throw", 1.35)
	_player.face_camera()


func _throw_start() -> Vector3:
	return _player.global_position + Vector3(0, 1.7, 0) + _player.global_basis.x * 0.25


## Lob: forward along the view, pitched up a little more than the camera.
func _throw_velocity() -> Vector3:
	var aim := -_cam.camera.global_basis.z
	var flat := Vector3(aim.x, 0, aim.z).normalized()
	var a := clampf(_cam.pitch + 0.35, -0.6, 1.2)
	return (flat * cos(a) + Vector3.UP * sin(a)).normalized() * 15.0 + _player.velocity * 0.5


var _arc: MultiMeshInstance3D


## While aiming a grenade: dots along the predicted flight, ending where it first lands.
func _update_arc() -> void:
	var show := current == "grenade" and in_mag > 0 and _player.aiming and _player.state == Player.State.ON_FOOT and _throw_t < 0.0
	if not show:
		if _arc:
			_arc.visible = false
		return
	if _arc == null:
		_arc = MultiMeshInstance3D.new()
		_arc.top_level = true
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		sm.radial_segments = 6
		sm.rings = 3
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.85, 0.5)
		sm.material = m
		mm.mesh = sm
		mm.instance_count = 40
		_arc.multimesh = mm
		_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_arc)
	_arc.visible = true
	_arc.global_transform = Transform3D.IDENTITY
	var mm := _arc.multimesh
	var p := _throw_start()
	var v := _throw_velocity()
	var space := get_world_3d().direct_space_state
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var n := 0
	var landed := false
	for i in 80:
		var nxt := p + v * 0.03
		v.y -= g * 0.03
		var q := PhysicsRayQueryParameters3D.create(p, nxt, 1 | 8 | 16)
		var hit := space.intersect_ray(q)
		if hit:
			nxt = hit.position
			landed = true
		if i % 2 == 0 or landed:
			if n < mm.instance_count:
				var sc := 2.2 if landed else 1.0
				mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), nxt))
				n += 1
		p = nxt
		if landed:
			break
	mm.visible_instance_count = n


func _release_grenade() -> void:
	var a: Array = ammo[current]
	if int(a[0]) <= 0:
		return
	a[0] = int(a[0]) - 1
	ammo_changed.emit(a[0], -1)
	var g := Grenade.new()
	g.source = _player
	g.damage = float(data.damage)
	get_tree().current_scene.add_child(g)
	var start := _throw_start()
	g.global_position = start
	g.linear_velocity = _throw_velocity()
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-4, 4), randf_range(-8, 8))
	g.add_collision_exception_with(_player)
	Audio.play_at(Audio.pick("weapons/swing_%d.ogg", 3), start, -10.0, 1.2)
	if int(a[0]) <= 0:
		_model.visible = false


# --- aim assist ----------------------------------------------------------------

## Gamepad aim assist (Game.aim_assist): slows the view and pulls gently onto the nearest target in a narrow
## cone; snaps onto it when the aim button is first pressed.
func _aim_assist(delta: float) -> void:
	if not Game.aim_assist or not Game.using_gamepad:
		_assist_target = null
		return
	var just := Input.is_action_just_pressed("aim") or (_assist_target == null and _player.aim_weight < 0.9)
	var cam_xf := _cam.camera.global_transform
	var fwd := -cam_xf.basis.z
	var best: Node3D = null
	var best_a := deg_to_rad(9.0 if just else 5.0)
	for t: Node in get_tree().get_nodes_in_group("aim_targets"):
		var n := t as Node3D
		if not n.has_method("aim_point") or (n.has_method("is_alive") and not n.is_alive()):
			continue
		var p: Vector3 = n.aim_point()
		var to := p - cam_xf.origin
		if to.length() > float(data.range) or to.length() < 1.0:
			continue
		var ang := fwd.angle_to(to.normalized())
		if ang < best_a:
			var q := PhysicsRayQueryParameters3D.create(cam_xf.origin, p, 1 | 8)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				best = n
				best_a = ang
	_assist_target = best
	if best:
		var to: Vector3 = best.aim_point() - cam_xf.origin
		var want_yaw := atan2(-to.x, -to.z)
		var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
		var k := 1.0 - exp(-delta * (14.0 if just else 3.0))
		_cam.yaw = lerp_angle(_cam.yaw, want_yaw, k)
		_cam.pitch = lerpf(_cam.pitch, want_pitch, k)


# --- drive-by ----------------------------------------------------------------

## Best weapon to shoot from a seat: the held one if it can, else the strongest one-handed gun carried.
func _drive_by_weapon() -> String:
	if data.get("drive_by", false) and in_mag + reserve > 0:
		return current
	for id in ["smg", "pistol"]:
		if owned.has(id) and int(ammo[id][0]) + int(ammo[id][1]) > 0:
			return id
	return ""


func _update_drive_by(delta: float) -> void:
	var seated := _player.state == Player.State.DRIVING and _player.vehicle and not (_player.vehicle is Helicopter)
	var want := seated and Game.controls_enabled and Input.is_action_pressed("vehicle_aim") and not WeaponWheel.open
	if want and not drive_by:
		var id := _drive_by_weapon()
		if id == "":
			want = false
		elif id != current:
			select(id)
	if want != drive_by:
		drive_by = want
		_player.set_drive_by(want)
		var sk0 := _visual.skeleton
		if want:
			# solve order: the arm reaches first, then AimPose turns the hand onto the gun and places it
			if _player.vehicle is Bike:
				sk0.move_child(_pose, -1)
			else:
				if _arm_ik == null:
					_install_arm_ik()
				sk0.move_child(_arm_ik, 0)
				sk0.move_child(_pose, 1)
		else:
			sk0.move_child(_pose, 0)
			if _arm_ik:
				_arm_ik.influence = 0.0
	_drive_by_w = move_toward(_drive_by_w, 1.0 if drive_by else 0.0, delta * 5.0)
	_pose.drive_w = _drive_by_w
	if not drive_by:
		return
	# the gun out at arm's length along the aim, the right hand on its grip
	var sk := _visual.skeleton
	var sh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightShoulder"))
	var ray := _cam.aim_ray(60.0)
	var aim: Vector3 = ((ray[1] as Vector3) - sh.origin).normalized()
	var car := _player.vehicle.global_basis
	# no aiming back through your own head and torso: keep the arm on the near side when looking left/back
	var gun_pos := sh.origin + aim * 0.48 + car.y * -0.06
	var gun := Transform3D(Basis.looking_at(aim, car.y), gun_pos)
	var hand := gun * _pose.mount.affine_inverse()
	if _player.vehicle is Bike:
		drive_by_hand = hand
	else:
		if _arm_ik == null:
			_install_arm_ik()
		_arm_target.global_transform = hand
		_arm_pole.global_position = sh.origin + car.y * -0.5 + car.x * 0.3 - aim * 0.2
		_arm_ik.influence = _drive_by_w
	_pose.drive_xf = sk.global_transform.affine_inverse() * gun


func _install_arm_ik() -> void:
	_arm_ik = TwoBoneIK3D.new()
	_arm_ik.name = "DriveByIK"
	_visual.skeleton.add_child(_arm_ik)
	_arm_ik.setting_count = 1
	_arm_target = Marker3D.new()
	_arm_target.top_level = true
	_arm_ik.add_child(_arm_target)
	_arm_pole = Marker3D.new()
	_arm_pole.top_level = true
	_arm_ik.add_child(_arm_pole)
	_arm_ik.set_root_bone_name(0, "RightUpperArm")
	_arm_ik.set_middle_bone_name(0, "RightLowerArm")
	_arm_ik.set_end_bone_name(0, "RightHand")
	_arm_ik.set_target_node(0, _arm_ik.get_path_to(_arm_target))
	_arm_ik.set_pole_node(0, _arm_ik.get_path_to(_arm_pole))
	_arm_ik.influence = 0.0
