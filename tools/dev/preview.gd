extends Node
# Renders an asset (or scene) to PNG for visual review.
# xvfb-run -a godot --path . res://tests/runner.tscn -- res://tools/dev/preview.gd res://asset out.png [cam_dist] [yaw] [pitch] [w] [h]
func _ready():
	var a: Array = get_meta("args")
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(200, 200)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.35, 0.35, 0.36); fm.roughness = 0.9
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)
	var inst: Node3D = load(a[0]).instantiate()
	root.add_child(inst)
	var aabb := _aabb(inst, Transform3D.IDENTITY)
	print("AABB: ", aabb, " size: ", aabb.size)
	var dist := float(a[2]) if a.size() > 2 else aabb.size.length() * 1.1
	var yaw := deg_to_rad(float(a[3]) if a.size() > 3 else 35.0)
	var pitch := deg_to_rad(float(a[4]) if a.size() > 4 else 20.0)
	var cam := Camera3D.new()
	root.add_child(cam)
	var c := aabb.get_center()
	cam.look_at_from_position(c + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist, c)
	cam.fov = 50
	var w := int(a[5]) if a.size() > 5 else 960
	var h := int(a[6]) if a.size() > 6 else 540
	get_tree().root.size = Vector2i(w, h)
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(a[1])
	get_tree().quit()

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t: Transform3D = xf * ((n as Node3D).transform if n is Node3D else Transform3D.IDENTITY)
	if n is VisualInstance3D:
		out = t * (n as VisualInstance3D).get_aabb(); first = false
	for ch in n.get_children():
		var b := _aabb(ch, t)
		if b.size != Vector3.ZERO:
			out = b if first else out.merge(b); first = false
	return out
