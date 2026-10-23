extends Node
## Vehicle damage + audio: a car driven into a wall dents at the front, breaks its headlights, loses engine health
## and smokes; engine sound layers run while driving; a destroyed engine burns and explodes into a wreck that
## shoves nearby cars. With a SHOT_DIR (under xvfb-run) it also saves pictures of the crashed car and the wreck.
## godot --headless --path . res://tests/runner.tscn -- res://tests/damage_check.gd [SHOT_DIR]

var fails := 0
var shots := ""


func _ready() -> void:
	var a: Array = get_meta("args", [])
	if a.size() > 0:
		shots = a[0]
		DirAccess.make_dir_recursive_absolute(shots)
		get_tree().root.size = Vector2i(1280, 720)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _snap(name: String, cam: Camera3D, from: Vector3, at: Vector3) -> void:
	if shots == "":
		return
	cam.look_at_from_position(from, at)
	await _frames(6)
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(shots.path_join(name + ".png"))


func _run() -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := _box(root, Vector3(0, -1, 0), Vector3(400, 2, 400), Color(0.35, 0.35, 0.36))
	ground.name = "Ground"
	_box(root, Vector3(0, 1.5, -60), Vector3(14, 3, 1), Color(0.6, 0.58, 0.55))  # the wall
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var marks := SkidMarks.new()
	root.add_child(marks)

	var v := Vehicle.new()
	v.model = "sedan"
	v.paint = Color(0.12, 0.25, 0.55)
	v.position = Vector3(0, 0.4, 0)
	root.add_child(v)
	await _frames(40)
	v.set_driver(self)
	_check(v.audio != null and v.audio.running, "engine started on entry")
	var layers_heard := 0
	await _frames(70)
	for p in v.audio._layers:
		if p.playing:
			layers_heard |= 1 << v.audio._layers.find(p)
	Input.action_press("accelerate")
	var hit_speed := 0.0
	for i in 360:
		await get_tree().physics_frame
		for p in v.audio._layers:
			if p.playing:
				layers_heard |= 1 << v.audio._layers.find(p)
		if v.global_position.z > -55.0:
			hit_speed = v.speed_kmh()
		if v.global_position.z < -50.0 and v.speed_kmh() < 5.0:
			break
	Input.action_release("accelerate")
	print("  hit the wall at %.0f km/h" % hit_speed)
	_check(layers_heard == 7, "engine layers crossfade with rpm (mask %d)" % layers_heard)
	await _frames(60)
	var dmg := v.damage
	_check(dmg.health < VehicleDamage.MAX_HEALTH * 0.8, "engine damaged (%.0f / %.0f)" % [dmg.health, VehicleDamage.MAX_HEALTH])
	_check(dmg._dents.size() > 0, "body dented (%d dents)" % dmg._dents.size())
	var front_dent := false
	for d: Array in dmg._dents:
		if (d[0] as Vector3).z < -v._size.z * 0.3:
			front_dent = true
	_check(front_dent, "dent is at the front")
	_check(dmg.lamps_broken.front != Vector2.ZERO, "headlights smashed %s" % dmg.lamps_broken.front)
	if dmg.health < VehicleDamage.SMOKE_AT:
		_check(dmg._smoke != null and dmg._smoke.emitting, "engine smokes")
	await _snap("crash_front", cam, v.global_transform * Vector3(4.2, 1.5, -1.0), v.global_transform * Vector3(0, 0.6, -1.6))

	# wreck it: a second car parked beside gets shoved by the blast
	var other := Vehicle.new()
	other.model = "hatchback"
	other.position = v.global_position + v.global_basis.x * 4.5
	root.add_child(other)
	await _frames(40)
	var other_p := other.global_position
	v.set_driver(null)
	v.take_damage(5000.0)
	_check(dmg.on_fire, "destroyed engine catches fire")
	await _frames(60)
	await _snap("car_fire", cam, v.global_transform * Vector3(4.5, 2.0, 5.5), v.global_position + Vector3(0, 0.8, 0))
	await _frames(int(VehicleDamage.BURN_TIME * 60.0))
	_check(dmg.wrecked, "explodes after burning")
	_check(v.engine_dead, "wreck can't be driven")
	await _frames(90)
	_check(other.global_position.distance_to(other_p) > 0.3, "blast shoves the car beside (%.2f m)" % other.global_position.distance_to(other_p))
	_check(other.damage.health < VehicleDamage.MAX_HEALTH, "blast damages the car beside")
	await _snap("car_wreck", cam, v.global_transform * Vector3(4.0, 2.2, 5.0), v.global_position + Vector3(0, 0.6, 0))
	print("DAMAGE CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)


func _box(parent: Node, pos: Vector3, size: Vector3, col: Color) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	bm.material = m
	mi.mesh = bm
	sb.add_child(mi)
	sb.position = pos
	parent.add_child(sb)
	return sb
