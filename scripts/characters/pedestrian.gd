class_name Pedestrian
extends CharacterBody3D
## A person in the street. Milestone 5 gives them a body that reacts to violence: bullets are resolved
## against the skeleton (head, torso, limbs) rather than the capsule, so a shot past the shoulder misses and
## a head shot does triple damage; they flinch with a hit reaction, run from danger, and die as a ragdoll
## pushed by the killing shot, leaving a blood pool. Wandering the pavements comes with the population (M6).

signal died(ped: Pedestrian)

enum State { IDLE, WALK, HIT, FLEE, DEAD, DOWN, GETUP }

const GRAVITY := 18.0
const RUN := 4.6
const HEAD_MULT := 3.0
const LIMB_MULT := 0.6

## bone chain segments for hit tests: [from bone, to bone, radius, zone]
const SEGMENTS := [
	["Hips", "Spine", 0.17, "body"], ["Spine", "Chest", 0.17, "body"], ["Chest", "Neck", 0.17, "body"],
	["Neck", "Head", 0.07, "body"], ["Head", "", 0.115, "head"],
	["LeftUpperArm", "LeftLowerArm", 0.06, "limb"], ["LeftLowerArm", "LeftHand", 0.05, "limb"],
	["RightUpperArm", "RightLowerArm", 0.06, "limb"], ["RightLowerArm", "RightHand", 0.05, "limb"],
	["LeftUpperLeg", "LeftLowerLeg", 0.09, "limb"], ["LeftLowerLeg", "LeftFoot", 0.065, "limb"],
	["RightUpperLeg", "RightLowerLeg", 0.09, "limb"], ["RightLowerLeg", "RightFoot", 0.065, "limb"],
]

@export var character_file := "ch02_nonpbr"
var health := 100.0
## Stays where placed (a shop clerk): ducks at gunfire instead of running off.
var stay_put := false
var state := State.IDLE
var visual: HumanoidVisual
var ragdoll: Ragdoll
## Where they are heading (WALK) or running from (FLEE).
var goal := Vector3.ZERO
var _t := 0.0
var _flee_from := Vector3.ZERO
var _dead_t := 0.0
var _bones := {}
var _killer: Node
var _getup_len := 2.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 8 | 16
	add_to_group("pedestrians")
	add_to_group("aim_targets")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	set_meta("surface", FX.Surface.FLESH)
	visual = HumanoidVisual.new()
	visual.character_file = character_file
	add_child(visual)
	ragdoll = Ragdoll.new(visual.skeleton, 4, 1 | 8 | 16)
	for seg: Array in SEGMENTS:
		for b in [seg[0], seg[1]]:
			if b != "" and not _bones.has(b):
				_bones[b] = visual.skeleton.find_bone(b)
	Game.noise_made.connect(_on_noise)


func is_alive() -> bool:
	return state != State.DEAD


## Where aim assist locks on (upper chest).
func aim_point() -> Vector3:
	return _bone_pos("Chest") if state != State.DEAD else global_position


func _bone_pos(b: String) -> Vector3:
	var i: int = _bones.get(b, -1)
	if i < 0:
		return global_position + Vector3(0, 1.2, 0)
	return visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(i).origin


## Precise ray test against the body (called by weapons once the ray touches the capsule).
## Returns {} for a miss (the bullet carries on), else {pos, zone}.
func ray_test(from: Vector3, dir: Vector3) -> Dictionary:
	var best_t := INF
	var best := {}
	for seg: Array in SEGMENTS:
		var a := _bone_pos(seg[0])
		var b := a + (a - _bone_pos("Neck")).normalized() * 0.12 if seg[1] == "" else _bone_pos(seg[1])
		var r: float = seg[2]
		var hit := _ray_capsule(from, dir, a, b, r)
		if hit < 0.0:
			continue
		# the torso capsules round off above the shoulders; a ray through the skull counts as the head
		if seg[3] == "head" and hit < best_t + 0.3:
			return {"pos": from + dir * hit, "zone": "head"}
		if hit < best_t:
			best_t = hit
			best = {"pos": from + dir * hit, "zone": seg[3]}
	return best


## Distance along a ray to a capsule a-b of radius r (approximate: closest approach of two lines), -1 = miss.
static func _ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var u := b - a
	var w := o - a
	var uu := u.dot(u)
	var ud := u.dot(d)
	var uw := u.dot(w)
	var dw := d.dot(w)
	var den := uu - ud * ud
	var s := 0.0
	var t := 0.0
	if den > 1e-6:
		s = clampf((uw - ud * dw) / den, 0.0, 1.0)
	t = maxf(0.0, (a + u * s - o).dot(d))
	var p := o + d * t
	var q := a + u * clampf((p - a).dot(u) / maxf(uu, 1e-6), 0.0, 1.0)
	var dist := p.distance_to(q)
	if dist > r:
		return -1.0
	return maxf(0.0, t - sqrt(r * r - dist * dist))


# --- damage ------------------------------------------------------------------

func bullet_hit(pos: Vector3, dir: Vector3, amount: float, from: Node = null, zone := "body") -> void:
	var mult := HEAD_MULT if zone == "head" else (LIMB_MULT if zone == "limb" else 1.0)
	_hurt(amount * mult, from, dir * clampf(amount * 0.12, 2.0, 14.0), pos, zone)


func melee_hit(amount: float, from: Node, dir: Vector3) -> void:
	_hurt(amount, from, dir * 4.0 + Vector3.UP, _bone_pos("Chest"), "body")


func blast_hit(at: Vector3, amount: float, from: Node) -> void:
	var away := (global_position - at).normalized()
	_hurt(amount, from, (away + Vector3.UP * 0.8) * clampf(amount * 0.08, 4.0, 14.0), global_position + Vector3(0, 1, 0), "blast")


func take_damage(amount: float, from: Node = null) -> void:
	_hurt(amount, from, Vector3.ZERO, global_position + Vector3(0, 1, 0), "body")


## Knocked over (a car hit, an explosion) without necessarily dying.
func go_ragdoll(vel: Vector3, _impulse := Vector3.ZERO) -> void:
	if state == State.DEAD or state == State.DOWN:
		return
	_knock_down(vel)


## Hit by a vehicle: damage from the closing speed, thrown along with the bonnet.
func struck_by_vehicle(v: Vehicle, vel: Vector3) -> void:
	if state == State.DEAD or state == State.DOWN:
		return
	var closing := (vel - velocity).length()
	if closing < 3.0:
		return
	var who: Node = v.driver if v.driver else v
	_hurt((closing - 2.5) * 7.0, who, vel * 1.1 + Vector3.UP * (2.0 + closing * 0.15), global_position + Vector3(0, 0.9, 0), "blast")
	Audio.play_at(Audio.pick("vehicles/bump_%d.ogg", 3), global_position + Vector3(0, 0.8, 0), clampf(-8.0 + closing, -8.0, 4.0), randf_range(0.8, 1.0))
	if who == Game.player:
		Game.crime("hit_pedestrian", global_position)


func _knock_down(push: Vector3) -> void:
	state = State.DOWN
	_t = 0.0
	collision_layer = 0
	collision_mask = 0
	ragdoll.start(velocity + push * 0.5, Vector3.ZERO)
	if push.length() > 0.1:
		ragdoll.push("Chest", push * 4.0)
	Audio.play_at(Audio.stream("player/body_fall.ogg"), global_position + Vector3(0, 0.5, 0), -8.0, randf_range(0.9, 1.1))


func _get_up() -> void:
	var down := ragdoll.face_down()
	var hx := ragdoll.hips_transform()
	ragdoll.stop()
	var fwd := hx.basis.y
	fwd.y = 0.0
	var at := hx.origin
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at + Vector3(0, -2.0, 0), 1 | 8 | 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	global_position = hit.position if hit else Vector3(at.x, at.y - 0.2, at.z)
	if fwd.length() > 0.1:
		rotation.y = atan2(fwd.x, fwd.z) + (0.0 if down else PI)
	collision_layer = 4
	collision_mask = 1 | 8 | 16
	velocity = Vector3.ZERO
	var clip := "get_up_front" if down else "get_up_back"
	visual.jump_to(clip)
	state = State.GETUP
	_t = 0.0
	_getup_len = visual.action_duration(clip)


func _hurt(amount: float, from: Node, push: Vector3, at: Vector3, zone: String) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if from == Game.player:
		if Game.hud and Game.hud.has_method("hit_marker") and zone != "blast":
			Game.hud.hit_marker(health <= 0.0)
		Game.crime("murder" if health <= 0.0 else "assault", global_position)
	if health <= 0.0:
		_killer = from
		_die(push, "Head" if zone == "head" else "")
		return
	if zone == "blast":
		_flee_from = from.global_position if from is Node3D else at
		_knock_down(push)
		return
	# flinch, then run from whoever did it
	state = State.HIT
	_t = 0.0
	visual.travel("hit_head" if zone == "head" or randf() < 0.3 else "hit_body")
	_flee_from = from.global_position if from is Node3D else at
	Game.noise(global_position, 20.0, from)


func _die(push: Vector3, bone: String) -> void:
	var was_down := state == State.DOWN
	state = State.DEAD
	_dead_t = 0.0
	collision_layer = 0
	collision_mask = 0
	remove_from_group("aim_targets")
	if not was_down:
		ragdoll.start(velocity + push * 0.35, Vector3.ZERO)
	if push.length() > 0.1:
		ragdoll.push(bone if bone != "" else "Chest", push * 6.0)
	Audio.play_at(Audio.stream("player/body_fall.ogg"), global_position + Vector3(0, 0.5, 0), -6.0, randf_range(0.9, 1.1))
	died.emit(self)
	if Game.blood:
		get_tree().create_timer(1.6).timeout.connect(_blood_pool)


func _blood_pool() -> void:
	if not is_inside_tree():
		return
	var at := ragdoll.hips_transform().origin
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at + Vector3(0, -1.5, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit:
		return
	var d := Decal.new()
	d.texture_albedo = FX.blood_texture()
	d.size = Vector3(0.2, 0.6, 0.2)
	d.cull_mask = 1
	d.modulate = Color(1, 1, 1, 0.92)
	get_parent().add_child(d)
	d.global_position = hit.position
	d.rotation.y = randf() * TAU
	var tw := d.create_tween()
	tw.tween_property(d, "size", Vector3(1.5, 0.6, 1.5), 9.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(40.0)
	tw.tween_property(d, "modulate:a", 0.0, 4.0)
	tw.tween_callback(d.queue_free)


func _on_noise(pos: Vector3, radius: float, source: Node) -> void:
	if state in [State.DEAD, State.HIT] or source == self:
		return
	if pos.distance_to(global_position) > radius:
		return
	_flee_from = pos
	if stay_put:
		return
	if state != State.FLEE:
		state = State.FLEE
		_t = 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		State.DEAD:
			_dead_t += delta
			# bodies are cleared away once nobody is looking (or after a long while)
			if _dead_t > 25.0:
				var cam := get_viewport().get_camera_3d()
				var seen := cam and cam.is_position_in_frustum(global_position) and cam.global_position.distance_to(global_position) < 80.0
				if not seen or _dead_t > 90.0:
					queue_free()
			return
		State.DOWN:
			if (_t > 1.6 and ragdoll.hips_speed() < 0.4) or _t > 6.0:
				_get_up()
			return
		State.GETUP:
			if _t >= _getup_len - 0.1:
				state = State.IDLE if stay_put else State.FLEE
				_t = 0.0
				visual.travel("ground")
			return
		State.HIT:
			if _t > 0.7:
				state = State.IDLE if stay_put else State.FLEE
				_t = 0.0
				visual.travel("ground")
			_move(Vector3.ZERO, delta)
		State.FLEE:
			var away := global_position - _flee_from
			away.y = 0.0
			var dir := away.normalized() if away.length() > 0.1 else -global_basis.z
			_move(dir * RUN, delta)
			if _t > 12.0 and away.length() > 40.0:
				state = State.IDLE
		State.WALK:
			var to := goal - global_position
			to.y = 0.0
			if to.length() < 0.6:
				state = State.IDLE
				_move(Vector3.ZERO, delta)
			else:
				_move(to.normalized() * visual.walk_speed, delta)
		_:
			_move(Vector3.ZERO, delta)


func _move(want: Vector3, delta: float) -> void:
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(want, delta * 10.0)
	velocity.x = h.x
	velocity.z = h.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if h.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-h.x, -h.z), 1.0 - exp(-delta * 8.0))
	visual.set_locomotion(Vector2(velocity.x, velocity.z).length())
