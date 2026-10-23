class_name Cop
extends Pedestrian
## A police officer (or SWAT). Hunts the wanted player: runs to where they were last seen, draws and fires
## when it has a line of sight (from two stars, or at once if the player points a gun at them), and arrests
## a player who stands close without fighting back. Shot at by the player, it fights back; killed, it raises
## the wanted level. Reports sightings to the Wanted system.

var wanted: Wanted
var gun := "pistol"
var accuracy := 0.55
var _fire_cd := 1.0
var _model: Node3D
var _muzzle := Vector3.ZERO
var _arrest_t := 0.0
var _hand := -1
var _seen_t := 0.0


func _ready() -> void:
	super._ready()
	remove_from_group("pedestrians")   # not part of the crowd's panic
	add_to_group("police")
	stay_put = false
	_model = WeaponModel.build("pistol")[0] if gun == "pistol" else (load("res://assets/models/weapons/%s.scn" % gun) as PackedScene).instantiate()
	add_child(_model)
	_model.top_level = true
	var m := _model.get_node_or_null("Muzzle") as Node3D
	_muzzle = m.position if m else Vector3(0, 0.05, -0.2)
	_hand = visual.skeleton.find_bone("RightHand")
	visual.set_stance(1.0 if gun != "pistol" else 0.0)
	state = State.WALK


func _on_noise(_pos: Vector3, _radius: float, _source: Node) -> void:
	pass  # gunfire doesn't scare the police


func _process(delta: float) -> void:
	super._process(delta)
	# the gun in the right hand (follows the animated hand; no IK for NPC officers)
	if _model and _hand >= 0 and state != State.DEAD:
		var hand := visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(_hand)
		hand.basis = hand.basis.orthonormalized()
		_model.global_transform = hand * WeaponMounts.grip("pistol" if gun == "pistol" else "rifle")
	elif _model and state == State.DEAD:
		_model.queue_free()
		_model = null


func _physics_process(delta: float) -> void:
	if state in [State.DEAD, State.DOWN, State.GETUP, State.HIT]:
		super._physics_process(delta)
		return
	_t += delta
	_fire_cd -= delta
	var p := Game.player as Player
	if p == null or wanted == null or wanted.stars == 0:
		# stand down: walk off and let the population tidy up
		_move(Vector3.ZERO, delta)
		visual.set_aim(Vector2.ZERO, 0.0)
		return
	var target := p.vehicle.global_position if p.vehicle else p.global_position
	var eye := global_position + Vector3(0, 1.6, 0)
	var aim_at := target + Vector3(0, 1.1, 0)
	var sees := _line_of_sight(eye, aim_at, p)
	if sees:
		_seen_t += delta
		wanted.report_sighting(target)
	else:
		_seen_t = 0.0
	var goal_pos := target if sees or global_position.distance_to(target) < 15.0 else wanted.last_seen
	var to := goal_pos - global_position
	to.y = 0.0
	var dist := to.length()
	var hostile := wanted.stars >= 2 or wanted.player_threatening()
	# arrest: close, unarmed or not fighting, on foot (or in a car that has stopped)
	if dist < 1.9 and wanted.stars <= 3 and not p.state in [Player.State.RAGDOLL, Player.State.DEAD]:
		var stopped := p.vehicle == null or p.vehicle.linear_velocity.length() < 1.0
		if stopped and not (p.aiming and p.weapon.has_weapon()):
			_arrest_t += delta
			visual.set_aim(Vector2.ZERO, 0.0)
			_move(Vector3.ZERO, delta)
			rotation.y = atan2(-to.x, -to.z)
			if _arrest_t > 1.4:
				wanted.bust(self)
			return
	_arrest_t = 0.0
	if sees and hostile and dist < 38.0:
		# stand and shoot (strafe a little when close)
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-delta * 10.0))
		visual.set_aim(Vector2.ZERO, 1.0)
		_move(Vector3.ZERO if dist > 6.0 else -to.normalized() * 1.2, delta)
		if _fire_cd <= 0.0 and _seen_t > 0.4:
			_shoot(aim_at, p)
		return
	visual.set_aim(Vector2.ZERO, 0.0)
	if dist > 1.5:
		_move(to.normalized() * (RUN if dist > 6.0 else visual.walk_speed), delta)
	else:
		_move(Vector3.ZERO, delta)


func _line_of_sight(from: Vector3, to: Vector3, p: Player) -> bool:
	if from.distance_to(to) > 70.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 8 | 16)
	q.exclude = [get_rid()]
	if p.vehicle:
		q.exclude.append(p.vehicle.get_rid())
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _shoot(at: Vector3, p: Player) -> void:
	var auto := gun != "pistol"
	_fire_cd = randf_range(0.12, 0.2) if auto else randf_range(0.45, 0.9)
	if auto and randf() < 0.25:
		_fire_cd = 1.2  # bursts
	var from := _model.global_transform * _muzzle if _model else global_position + Vector3(0, 1.4, 0)
	var d := from.distance_to(at)
	var moving := (p.vehicle.linear_velocity.length() if p.vehicle else p.velocity.length()) * 0.03
	var spread := (1.0 - accuracy) * 0.06 + moving + d * 0.0012
	var dir := (at - from).normalized()
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var space := get_world_3d().direct_space_state
	var hit := Weapon.trace(space, from, dir, 120.0, [get_rid()])
	var end := from + dir * 120.0
	if hit:
		end = hit.position
		var col: Object = hit.collider
		var dmg := 7.0 if gun == "pistol" else 9.0
		if col == p:
			p.take_damage(dmg, self)
		elif p.vehicle and col == p.vehicle:
			p.vehicle.bullet_hit(end, dir, dmg, self)
			# a share gets through to the driver
			if randf() < 0.25:
				p.take_damage(dmg * 0.6, self)
		else:
			Weapon.apply_hit(get_tree().current_scene, hit, dir, dmg, self)
	FX.tracer(get_tree().current_scene, from, end)
	var snd := "weapons/pistol_%d.ogg" if gun == "pistol" else ("weapons/smg_%d.ogg" if gun == "smg" else "weapons/rifle_%d.ogg")
	Audio.play_at(Audio.pick(snd, 2 if gun != "smg" else 1), from, -3.0, randf_range(0.95, 1.05), &"SFX", 240.0)


func _hurt(amount: float, from: Node, push: Vector3, at: Vector3, zone: String) -> void:
	var was_alive := state != State.DEAD
	super._hurt(amount, from, push, at, zone)
	if from == Game.player and wanted:
		wanted.crime_against_police(state == State.DEAD and was_alive)
	if state == State.FLEE:
		state = State.WALK  # officers don't run away
