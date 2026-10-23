class_name Pedestrian
extends CharacterBody3D
## A person in the street. Milestone 5 gives them a body that reacts to violence: bullets are resolved
## against the skeleton (head, torso, limbs) rather than the capsule, so a shot past the shoulder misses and
## a head shot does triple damage; they flinch with a hit reaction, run from danger, and die as a ragdoll
## pushed by the killing shot, leaving a blood pool. With a Population they wander the pavements (WalkGraph),
## wait at crossings, stop for a phone call or a cigarette, and react to trouble: cower when it is close, run,
## spread the panic to people around them, call the police, and some men fight back when hit.

signal died(ped: Pedestrian)

enum State { IDLE, WALK, HIT, FLEE, DEAD, DOWN, GETUP, WAIT, ACT, COWER, CALL, FIGHT }

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
## Built on first use (a knock-down or death): idle physical bones on every passer-by cost physics time.
var ragdoll: Ragdoll:
	get:
		if _ragdoll == null and visual and visual.skeleton:
			_ragdoll = Ragdoll.new(visual.skeleton, 4, 1 | 8 | 16)
		return _ragdoll
var _ragdoll: Ragdoll
## Where they are heading (WALK) or running from (FLEE).
var goal := Vector3.ZERO
var _t := 0.0
var _flee_from := Vector3.ZERO
var _dead_t := 0.0
var _bones := {}
var _killer: Node
var _getup_len := 2.0
## pavement walking
var pop: Population
var female := false
var edge := -1
var from_node := -1
var s := 0.0
var lateral := 0.0          # metres off the pavement centre line (keeps people from walking in single file)
var activity := ""          # looping clip for ACT (and the idle clip people stand around with)
var act_time := 0.0
var _panic_t := 0.0
var _fight_target: Node3D
var _punch_cd := 0.0
var _called := false
## Sitting on a bench: no gravity/collision push while seated (the capsule would rest on the seat).
var sitting := false


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
	if female:
		visual.clip_swap = {"walk": "f_walk", "idle": "f_idle", "run": "f_run"}
	add_child(visual)
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
	_fight_target = from as Node3D if zone == "body" and from is Node3D and push.length() < 6.0 else null
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


## Paramedics brought them round: back on their feet, shaken, and off they go.
func revive() -> void:
	if state != State.DEAD:
		return
	health = 60.0
	add_to_group("aim_targets")
	state = State.DOWN
	_get_up()
	_flee_from = global_position - global_basis.z
	if pop and not pop.people.has(self):
		pop.people.append(self)


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
	if state in [State.DEAD, State.HIT, State.DOWN, State.GETUP, State.COWER] or source == self:
		return
	var d := pos.distance_to(global_position)
	if d > radius:
		return
	_flee_from = pos
	if stay_put:
		if state != State.COWER:
			state = State.COWER
			_t = 0.0
			visual.play_loop("cower")
		return
	if state == State.FIGHT:
		return
	# right next to the shooting: duck and cover first, then run
	if d < 9.0 and randf() < 0.4:
		state = State.COWER
		_t = 0.0
		visual.play_loop("cower")
		return
	_start_flee()


func _start_flee() -> void:
	if state != State.FLEE:
		state = State.FLEE
		_t = 0.0
		if visual.current_state() == &"act":
			visual.travel("ground")


## Fleeing people set off those around them.
func _spread_panic() -> void:
	for n: Node in get_tree().get_nodes_in_group("pedestrians"):
		var o := n as Pedestrian
		if o == self or o.state in [State.FLEE, State.DEAD, State.DOWN, State.COWER, State.FIGHT, State.CALL]:
			continue
		if o.global_position.distance_to(global_position) < 9.0 and randf() < 0.6:
			o._flee_from = _flee_from
			o._start_flee()


var _anim_acc := 0.0
var _far := false
var _vanish := false


## Leave the scene: removed the next time nobody is looking.
func queue_free_when_unseen() -> void:
	_vanish = true


## Animation level of detail: people far from the camera animate at 10 Hz.
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or visual == null or visual.tree == null:
		return
	if _vanish and not (cam.is_position_in_frustum(global_position + Vector3(0, 1, 0)) and cam.global_position.distance_to(global_position) < 120.0):
		queue_free()
		return
	var far := cam.global_position.distance_to(global_position) > 45.0 and state != State.DOWN
	if far != _far:
		_far = far
		visual.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if far else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		_anim_acc = 0.0
	if _far:
		_anim_acc += delta
		if _anim_acc >= 0.1:
			visual.tree.advance(_anim_acc)
			_anim_acc = 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	_punch_cd -= delta
	match state:
		State.DEAD:
			_dead_t += delta
			# bodies are cleared away once nobody is looking (or after a long while)
			if _dead_t > (25.0 if not has_meta("attended") else 150.0):
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
				_t = 0.0
				visual.travel("ground")
				if stay_put:
					state = State.IDLE
				elif not female and _fight_target and randf() < 0.3 and not _armed(_fight_target):
					state = State.FIGHT
				else:
					state = State.FLEE
			_move(Vector3.ZERO, delta)
		State.COWER:
			_move(Vector3.ZERO, delta)
			if _t > randf_range(3.5, 6.0):
				visual.travel("ground")
				state = State.IDLE if stay_put else State.FLEE
				_t = 0.0
		State.FLEE:
			_flee(delta)
		State.CALL:
			_move(Vector3.ZERO, delta)
			if _t > 7.0:
				visual.travel("ground")
				state = State.FLEE
				_t = 0.0
		State.FIGHT:
			_fight(delta)
		State.WAIT:
			_move(Vector3.ZERO, delta)
			if _may_cross():
				state = State.WALK
		State.ACT:
			_move(Vector3.ZERO, delta)
			act_time -= delta
			if act_time <= 0.0 and edge >= 0:
				visual.travel("ground")
				state = State.WALK
		State.WALK:
			if edge >= 0 and pop:
				_walk(delta)
			else:
				var to := goal - global_position
				to.y = 0.0
				if to.length() < 0.6:
					state = State.IDLE
					_move(Vector3.ZERO, delta)
				else:
					_move(to.normalized() * visual.walk_speed, delta)
		_:
			_move(Vector3.ZERO, delta)


func _armed(n: Node3D) -> bool:
	return n is Player and (n as Player).weapon.has_weapon() and not (n as Player).weapon.is_melee()


## Along the pavement graph: follow the edge with a little sideways offset, choose a new edge at each end,
## wait at crossings, now and then stop for a call or a cigarette.
func _walk(delta: float) -> void:
	var g := pop.walk
	var e: Dictionary = g.edges[edge]
	s += visual.walk_speed * delta
	if s >= float(e.len):
		var at := g.other_end(edge, from_node)
		var opts: Array = (g.links[at] as Array).filter(func(id): return id != edge)
		if opts.is_empty():
			opts = [edge]
		# mostly carry on along the pavement; crossings now and then
		var pick: int = opts[randi() % opts.size()]
		for k in 2:
			if g.edges[pick].cross and randf() < 0.5:
				pick = opts[randi() % opts.size()]
		edge = pick
		from_node = at
		s = 0.0
		e = g.edges[edge]
		if e.cross:
			state = State.WAIT
			return
		if randf() < 0.06 and not pop.busy_spot(global_position):
			_start_activity(["phone_f" if female else "phone_m", "texting", "smoke", "nervous"][randi() % 4], randf_range(8.0, 20.0))
			return
	var target := g.point(edge, s + 1.2, from_node)
	var ahead := g.point(edge, s + 0.2, from_node)
	var dir := target - ahead
	dir.y = 0.0
	var side := Vector3(-dir.z, 0, dir.x).normalized() * (lateral if not e.cross else lateral * 0.3)
	if _far:
		# far from the camera: follow the pavement directly, no collision work
		global_position = ahead + side
		if dir.length() > 0.01:
			rotation.y = atan2(-dir.x, -dir.z)
		velocity = dir.normalized() * visual.walk_speed
		visual.set_locomotion(visual.walk_speed)
		return
	var to := (target + side) - global_position
	to.y = 0.0
	# pushed off the pavement (a crowd, a car, a wall corner): head straight back to it, or reappear on it
	var off := Vector2(ahead.x - global_position.x, ahead.z - global_position.z).length()
	if off > 2.6:
		var cam := get_viewport().get_camera_3d()
		if off > 4.0 and not (cam and cam.is_position_in_frustum(global_position + Vector3(0, 1, 0))):
			global_position = ahead + Vector3(0, 0.1, 0)
			velocity = Vector3.ZERO
			return
		to = ahead - global_position
		to.y = 0.0
	var want := to.normalized() * visual.walk_speed
	if off <= 2.6:
		want = _avoid(want)
	_move(want, delta)


## Slow down / step aside for someone just in front; turn back at an obstacle.
var _avoid_t := 0
var _avoid_push := Vector3.ZERO


func _avoid(want: Vector3) -> Vector3:
	if want.length() < 0.1:
		return want
	# the neighbour scan runs every fourth frame; the push in between is reused
	_avoid_t = (_avoid_t + 1) % 4
	if _avoid_t != 0:
		return (want + _avoid_push) * (0.6 if _avoid_push.length() > 0.05 else 1.0)
	var base := want
	var fwd := want.normalized()
	var others: Array = pop.people if pop else get_tree().get_nodes_in_group("pedestrians")
	for n in others:
		var o := n as Node3D
		if o == self or not is_instance_valid(o):
			continue
		var rel := o.global_position - global_position
		rel.y = 0.0
		var d := rel.length()
		if d < 1.2 and d > 0.01 and rel.dot(fwd) > 0.3 * d:
			# step to the right of them
			want += Vector3(-fwd.z, 0, fwd.x) * 0.8 * (1.2 - d)
			want *= clampf(d / 1.2, 0.3, 1.0)
	var p := Game.player as Node3D
	if p:
		var rel := p.global_position - global_position
		rel.y = 0.0
		if rel.length() < 1.3 and rel.dot(fwd) > 0.0:
			want += Vector3(-fwd.z, 0, fwd.x) * 1.0
	_avoid_push = want - base
	return want


func _may_cross() -> bool:
	if pop == null or edge < 0:
		return true
	return pop.may_cross(pop.walk.edges[edge])


func _start_activity(clip: String, secs: float) -> void:
	state = State.ACT
	activity = clip
	act_time = secs
	visual.play_loop(clip)


## Run from danger: along the pavements away from it when on the graph, else straight away; spread the panic,
## and some people stop at a safe distance to call the police.
func _flee(delta: float) -> void:
	_panic_t -= delta
	if _panic_t <= 0.0:
		_panic_t = 1.0
		_spread_panic()
	var away := global_position - _flee_from
	away.y = 0.0
	var dir := away.normalized() if away.length() > 0.1 else -global_basis.z
	if pop and edge >= 0:
		# choose the direction along the current edge that leads away
		var g := pop.walk
		var e: Dictionary = g.edges[edge]
		var p_fwd := g.point(edge, s + 2.0, from_node)
		var p_back := g.point(edge, s - 2.0, from_node)
		if p_back.distance_to(_flee_from) > p_fwd.distance_to(_flee_from) + 0.5:
			from_node = g.other_end(edge, from_node)
			s = float(e.len) - s
		s += RUN * delta
		if s >= float(e.len):
			var at := g.other_end(edge, from_node)
			var best := edge
			var bd := -INF
			for id: int in g.links[at]:
				var far := g.node_pos(g.other_end(id, at)).distance_to(_flee_from)
				if id != edge and far > bd:
					bd = far
					best = id
			edge = best
			from_node = at
			s = 0.0
		var target := g.point(edge, s + 2.0, from_node)
		var to := target - global_position
		to.y = 0.0
		if to.length() > 0.2:
			dir = to.normalized()
	_move(_avoid(dir * RUN), delta)
	if not _called and _t > 6.0 and away.length() > 25.0 and randf() < delta * 0.25:
		_called = true
		state = State.CALL
		_t = 0.0
		visual.play_loop("call_police")
		Game.police_called(global_position, _flee_from)
		return
	if _t > 14.0 and away.length() > 45.0:
		state = State.WALK if edge >= 0 else State.IDLE
		_t = 0.0


## Squaring up to whoever hit them: close in and throw punches until they win, lose or a gun comes out.
func _fight(delta: float) -> void:
	if not is_instance_valid(_fight_target) or _t > 15.0 or _armed(_fight_target):
		state = State.FLEE
		_t = 0.0
		return
	var to := _fight_target.global_position - global_position
	to.y = 0.0
	if to.length() > 1.1:
		_move(to.normalized() * RUN * 0.8, delta)
		return
	_move(Vector3.ZERO, delta)
	rotation.y = atan2(-to.x, -to.z)
	if _punch_cd <= 0.0:
		_punch_cd = 1.1
		visual.travel(["punch_jab", "punch_cross", "punch_hook"][randi() % 3])
		get_tree().create_timer(0.35).timeout.connect(func():
			if state == State.FIGHT and is_instance_valid(_fight_target) and _fight_target.global_position.distance_to(global_position) < 1.5:
				if _fight_target.has_method("take_damage"):
					_fight_target.take_damage(7.0, self)
				Audio.play_at(Audio.pick("player/punch_%d.ogg", 3), global_position + Vector3(0, 1.3, 0), -6.0, randf_range(0.9, 1.1)))


func _move(want: Vector3, delta: float) -> void:
	if sitting:
		if want.length() < 0.1 and state in [State.ACT, State.IDLE, State.COWER]:
			return
		sitting = false  # getting up to run
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(want, delta * 10.0)
	velocity.x = h.x
	velocity.z = h.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if h.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-h.x, -h.z), 1.0 - exp(-delta * 8.0))
	visual.set_locomotion(Vector2(velocity.x, velocity.z).length())
