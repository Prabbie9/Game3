extends Node
## Renders street props in a row seen from +Z (their front), for checking scale and facing.
## xvfb-run -a godot --path . res://tests/runner.tscn -- res://tests/prop_shot.gd OUT.png [names,...]

func _ready() -> void:
	get_tree().root.size = Vector2i(1600, 700)
	_run.call_deferred()


func _run() -> void:
	var a: Array = get_meta("args", ["tests/output/props.png"])
	var names: Array = ["vending_machine", "atm", "payphone", "fire_hydrant", "metal_trash_can", "street_lamp_01"]
	if a.size() > 1:
		names = String(a[1]).split(",")
	PropCatalog.prepare()
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0)
	root.add_child(sun)
	for i in names.size():
		var mi := MeshInstance3D.new()
		mi.mesh = PropCatalog.mesh(names[i])
		mi.position = Vector3((i - names.size() * 0.5 + 0.5) * 1.6, 0, 0)
		root.add_child(mi)
		var l := Label3D.new()
		l.text = names[i]
		l.font_size = 28
		l.position = mi.position + Vector3(0, -0.25, 0.6)
		root.add_child(l)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.6, 7.5), Vector3(0, 1.0, 0))
	cam.fov = 50
	cam.make_current()
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(a[0])
	get_tree().quit()
