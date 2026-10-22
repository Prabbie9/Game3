extends Node
## Player abilities check (headless): crouch, vault, climb, cover, punch, fall->ragdoll->get up, swim, turn.
## godot --headless --path . res://tests/runner.tscn -- res://tests/abilities_check.gd [SHOT_DIR]
## With SHOT_DIR (needs a renderer, e.g. xvfb-run) it also saves a side-view picture of each pose.

var fails := 0
var p: Player
var shot_dir := ""
var _shot_cam: Camera3D


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s  %-28s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	_run.call_deferred()


## Side-view picture of the player (camera to the player's right, 3.2 m away).
func _shot(name: String, side := 1.0, dist := 3.2) -> void:
	if shot_dir == "":
		return
	var c := p.global_position + Vector3(0, 0.9, 0)
	var right := p.global_basis.x * side
	_shot_cam.look_at_from_position(c + right * dist + Vector3(0, 0.4, 0) + p.global_basis.z * 0.6, c)
	_shot_cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shot_dir, name])
	p.cam.camera.make_current()


func _shot_from(name: String, eye: Vector3) -> void:
	if shot_dir == "":
		return
	_shot_cam.look_at_from_position(eye, p.global_position + Vector3(0, 0.9, 0))
	_shot_cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shot_dir, name])
	p.cam.camera.make_current()


func _box(root: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.45, 0.47) if size.y < 1.5 or size.x > 50 else Color(0.62, 0.55, 0.48)
	mi.material_override = m
	sb.add_child(mi)
	sb.position = pos
	root.add_child(sb)
	return sb


func _place(pos: Vector3, yaw := 0.0) -> void:
	p.ragdoll.stop()
	p.collision_layer = 2
	p.collision_mask = Player.MASK_ON_FOOT
	p.state = Player.State.ON_FOOT
	p.global_position = pos
	p.rotation = Vector3(0, yaw, 0)
	p.cam.yaw = yaw
	p.velocity = Vector3.ZERO
	p.visual.jump_to("ground")
	await _phys(20)


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await _phys(frames)
	Input.action_release(action)


func _tap(action: String) -> void:
	Input.action_press(action)
	await _phys(2)
	Input.action_release(action)
	await _phys(1)


## Runs at an obstacle (centre at z = obstacle_z, depth `depth`, top at `height`) and jumps: checks the expected
## clip starts, a planted hand touches the top, and where the player ends up.
func _traverse(label: String, from: Vector3, height: float, clip: String, obstacle_z: float, depth: float) -> void:
	await _place(from)
	Input.action_press("move_forward")
	await _phys(8)
	await _tap("jump")
	var started := String(p._act)
	# sample the hands on every physics step (awaiting frames can skip steps when rendering is slow)
	var best := [9.0]
	var sampler := func() -> void:
		for h in ["LeftHand", "RightHand"]:
			var hp: Vector3 = p.visual.bone_global(h).origin
			if absf(hp.z - obstacle_z) < depth * 0.5 + 0.08:
				best[0] = minf(best[0], absf(hp.y - height))
	get_tree().physics_frame.connect(sampler)
	var shot_done := false
	for i in 60 * 4:
		await get_tree().physics_frame
		if p.state != Player.State.ACTION:
			break
		if not shot_done and best[0] < 0.12:
			shot_done = true
			await _shot(clip + "_plant", -1.0)
	get_tree().physics_frame.disconnect(sampler)
	Input.action_release("move_forward")
	await _phys(30)
	var on_top := absf(p.global_position.y - height) < 0.1 and p.global_position.z < obstacle_z + depth * 0.5 - 0.1
	var over := p.global_position.z < obstacle_z - depth * 0.5 - 0.3 and absf(p.global_position.y) < 0.1
	var ok: bool = started == clip and float(best[0]) < 0.12 and p.state == Player.State.ON_FOOT and p.is_on_floor()
	ok = ok and (on_top if clip.contains("hang") or clip == "climb" else over)
	_check(label, ok, "clip %s, hand-to-top %.2f m, end (z %.2f y %.2f)" % [started, best[0], p.global_position.z, p.global_position.y])


func _run() -> void:
	var args: Array = get_meta("args") if has_meta("args") else []
	if args.size() > 0:
		shot_dir = String(args[0])
		DirAccess.make_dir_recursive_absolute(shot_dir)
		get_tree().root.size = Vector2i(960, 720)
		# software rendering is slow: one physics step per rendered frame keeps animation and physics in lockstep
		Engine.max_physics_steps_per_frame = 1
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.58)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	_shot_cam = Camera3D.new()
	_shot_cam.fov = 50
	root.add_child(_shot_cam)
	# ground with a 20x20 m, 3 m deep pool cut out at (-40, -15)
	_box(root, Vector3(35, -0.5, 0), Vector3(130, 1, 200))       # x -30..100
	_box(root, Vector3(-75, -0.5, 0), Vector3(50, 1, 200))       # x -100..-50
	_box(root, Vector3(-40, -0.5, 42.5), Vector3(20, 1, 115))    # in front of the pool (z -5..100)
	_box(root, Vector3(-40, -0.5, -62.5), Vector3(20, 1, 75))    # behind the pool (z -100..-25)
	_box(root, Vector3(-40, -3.5, -15), Vector3(20, 1, 20))      # pool floor at y -3
	_box(root, Vector3(0, 0.4, -10), Vector3(4, 0.8, 0.3))      # barrier to vault (0.8 m)
	_box(root, Vector3(8, 0.625, -10), Vector3(4, 1.25, 0.3))   # wall to vault (1.25 m)
	_box(root, Vector3(20, 0.9, -11.5), Vector3(6, 1.8, 3))     # platform to climb (1.8 m)
	_box(root, Vector3(28, 0.6, -11.5), Vector3(6, 1.2, 3))     # platform to climb (1.2 m)
	_box(root, Vector3(-20, 1.2, -6), Vector3(8, 2.4, 0.5))     # wall for cover
	var crate := RigidBody3D.new()
	crate.collision_layer = 16
	var ccs := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(0.6, 0.6, 0.6)  # knee-high: punches must still connect
	ccs.shape = cb
	crate.add_child(ccs)
	crate.mass = 15.0
	crate.position = Vector3(40, 1.1, -0.9)
	root.add_child(crate)
	var water := WaterVolume.new()
	water.size = Vector3(20, 3, 20)
	water.position = Vector3(-40, -1.6, -15)  # surface at y = -0.1, floor at -3
	root.add_child(water)
	p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(p)
	Game.controls_enabled = true
	await _phys(30)

	# crouch
	await _place(Vector3(0, 0.1, 0))
	await _tap("crouch")
	await _phys(10)
	_check("crouch toggles", p.crouched and is_equal_approx(p._capsule.height, Player.CROUCH_HEIGHT))
	await _phys(30)
	await _shot("crouch_idle")
	Input.action_press("move_forward")
	await _phys(60)
	await _shot("crouch_walk")
	var cs := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_release("move_forward")
	_check("crouch walk speed", absf(cs - p.visual.crouch_speed) < 0.3, "%.2f m/s (clip %.2f)" % [cs, p.visual.crouch_speed])
	await _tap("crouch")
	await _phys(10)
	_check("stand up", not p.crouched)

	# vaults (low: one hand, high: two hands) and climbs (chest height: from the wall, high: jump to a hang first)
	await _traverse("vault 0.8 m barrier", Vector3(0, 0.1, -8.6), 0.8, "vault", -10.0, 0.3)
	await _traverse("vault 1.25 m wall", Vector3(8, 0.1, -8.6), 1.25, "vault_high", -10.0, 0.3)
	await _traverse("climb 1.2 m ledge", Vector3(28, 0.1, -9.4), 1.2, "climb", -11.5, 3.0)
	await _traverse("climb 1.8 m ledge", Vector3(20, 0.1, -9.4), 1.8, "jump_hang", -11.5, 3.0)

	# cover against the wall, slide along it, leave
	await _place(Vector3(-20, 0.1, -4.6), 0.0)
	await _tap("cover")
	var in_cover := p.state == Player.State.COVER
	var x0 := p.global_position.x
	await _phys(30)
	await _shot("cover_idle", 1.0, 3.6)
	await _shot_from("cover_front", p.global_position + Vector3(1.2, 1.6, 3.2))
	await _shot_from("cover_top", p.global_position + Vector3(2.5, 3.5, 0.6))
	Input.action_press("move_right")
	await _phys(40)
	await _shot("cover_move", 1.0, 3.6)
	Input.action_release("move_right")
	var moved := absf(p.global_position.x - x0)
	_check("take cover", in_cover, "dist to wall %.2f" % absf(p.global_position.z + 5.75))
	_check("move along cover", moved > 0.3, "moved %.2f m" % moved)
	await _tap("cover")
	_check("leave cover", p.state == Player.State.ON_FOOT)

	# punch a crate with fists
	await _place(Vector3(40, 0.1, 0.0), 0.0)
	p.weapon.select(0)
	p.cam.yaw = 0.0
	var c0 := crate.global_position
	await _tap("fire")
	await _phys(14)
	await _shot("punch")
	await _phys(36)
	_check("punch moves crate", crate.global_position.distance_to(c0) > 0.05 or crate.linear_velocity.length() > 0.1, "moved %.2f" % crate.global_position.distance_to(c0))
	p.weapon.select(1)

	# fall from 12 m -> ragdoll -> get up
	await _place(Vector3(60, 12.0, 0))
	var h0 := p.health
	var ragdolled := false
	for i in 60 * 6:
		await get_tree().physics_frame
		if p.state == Player.State.RAGDOLL and not ragdolled:
			ragdolled = true
			await _phys(70)
			await _shot("ragdoll", 1.0, 4.0)
		if ragdolled and p.state == Player.State.ON_FOOT:
			break
	_check("long fall ragdolls", ragdolled, "health %.0f -> %.0f" % [h0, p.health])
	await _phys(int(60 * 4))
	await _shot("got_up")
	_check("gets back up", p.state == Player.State.ON_FOOT and p.is_on_floor(), "state %s" % Player.State.keys()[p.state])

	# swim: put the player into the water volume (deep)
	p.health = 100.0
	await _place(Vector3(-40, -2.4, -15))
	await _phys(10)
	_check("swims in deep water", p.state == Player.State.SWIM, "state %s, y %.2f" % [Player.State.keys()[p.state], p.global_position.y])
	var sx := p.global_position
	await _shot("swim_idle")
	Input.action_press("move_left")
	await _phys(60)
	await _shot("swim_move")
	Input.action_release("move_left")
	_check("swims forward", p.global_position.distance_to(sx) > 0.8, "moved %.2f m" % p.global_position.distance_to(sx))

	# turn in place
	await _place(Vector3(80, 0.1, 0), 0.0)
	await _hold("move_back", 6)
	var turning := p.state == Player.State.ACTION and p._act == "turn_180"
	await _phys(int(60 * 0.4))
	await _shot("turn_mid")
	await _phys(int(60 * 1.1))
	_check("turn in place 180", turning and absf(wrapf(p.rotation.y - PI, -PI, PI)) < 0.6, "started %s, yaw %.0f°" % [turning, rad_to_deg(p.rotation.y)])

	print("ABILITIES CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)
