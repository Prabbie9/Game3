extends Node
## Foot/hand IK review shot: characters on a 20° slope, straddling a 15 cm curb and a 30 cm step,
## and one aiming the pistol (left-hand support grip). args: OUT.png
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var a: Array = get_meta("args")
	get_tree().root.size = Vector2i(1280, 720)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7); e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.55, 0.55, 0.58)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX; env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 60, 0); sun.shadow_enabled = true; add_child(sun)
	var sb := StaticBody3D.new(); add_child(sb)
	_box(sb, Vector3(0, -0.5, 0), Vector3(30, 1, 30), Basis.IDENTITY, Color(0.4, 0.4, 0.42))
	_box(sb, Vector3(-2.0, 0.0, 0), Vector3(3, 1.2, 3), Basis(Vector3(0, 0, 1), deg_to_rad(20)), Color(0.55, 0.5, 0.45))  # slope
	_box(sb, Vector3(1.3, 0.075, 0), Vector3(1.0, 0.15, 3), Basis.IDENTITY, Color(0.6, 0.6, 0.6))  # curb
	_box(sb, Vector3(3.6, 0.15, 0), Vector3(1.0, 0.3, 3), Basis.IDENTITY, Color(0.6, 0.6, 0.6))  # step
	var spots := [Vector3(-2.2, 0.0, 0.0), Vector3(0.8, 0.0, 0.0), Vector3(3.1, 0.0, 0.0), Vector3(6.2, 0.0, 0.0)]
	var yaws := [PI, PI, PI, PI * 0.6]
	var visuals := []
	for i in spots.size():
		var body := Node3D.new(); add_child(body)
		var sp: Vector3 = spots[i]
		# root at the lowest ground under the character (like a capsule resting on the lower surface)
		var q := PhysicsRayQueryParameters3D.create(sp + Vector3(0, 3, 0), sp + Vector3(0, -3, 0))
		await get_tree().physics_frame
		var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
		# capsule rests on the lower surface under the body centre
		body.global_position = Vector3(sp.x, 0.0 if i in [1, 2] else (hit.position.y - 0.12 if hit and i == 0 else 0.0), sp.z)
		body.rotation.y = yaws[i]
		var v := HumanoidVisual.new(); body.add_child(v)
		visuals.append(v)
		FootIK.install(v.skeleton, body)
		if i == 3:
			var att := BoneAttachment3D.new(); att.bone_name = "RightHand"; v.skeleton.add_child(att)
			var gun: Node3D = WeaponModel.build("pistol")[0]; att.add_child(gun); gun.transform = WeaponMounts.PISTOL_GRIP
			var sup := Marker3D.new(); gun.add_child(sup); sup.transform = WeaponMounts.PISTOL_SUPPORT
			var ik := v.install_hand_ik(sup); ik.influence = 1.0
			v.set_aim(Vector2.ZERO, 1.0)
	for i in 40: await get_tree().process_frame
	var cam := Camera3D.new(); add_child(cam); cam.fov = 40
	cam.look_at_from_position(Vector3(2.0, 1.0, 7.5), Vector3(2.0, 0.55, 0)); cam.make_current()
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(a[0])
	# numeric check: lowest toe/heel height above the ground under each foot
	for v in visuals:
		var s := ""
		for f in ["LeftFoot", "RightFoot"]:
			var p: Vector3 = v.bone_global(f).origin
			var q2 := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.5, 0), p + Vector3(0, -1, 0))
			var h := get_viewport().get_world_3d().direct_space_state.intersect_ray(q2)
			s += "%s ankle %.3f above ground  " % [f, p.y - h.position.y if h else -1.0]
		print(s)
	get_tree().quit()


func _box(sb: StaticBody3D, pos: Vector3, size: Vector3, b: Basis, col: Color) -> void:
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = size; cs.shape = bs
	cs.transform = Transform3D(b, pos); sb.add_child(cs)
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
	var m := StandardMaterial3D.new(); m.albedo_color = col; mi.material_override = m
	mi.transform = Transform3D(b, pos); add_child(mi)
