extends Node
## Renders every NPC character standing in a row (front view), for picking/classifying characters.
## xvfb-run -a godot --path . res://tests/runner.tscn -- res://tests/lineup.gd OUT.png

func _ready() -> void:
	get_tree().root.size = Vector2i(1800, 700)
	_run.call_deferred()


func _run() -> void:
	var out: String = (get_meta("args", ["tests/output/lineup.png"]) as Array)[0]
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.4, 0)
	root.add_child(sun)
	var chars: Array = Population.CHARACTERS.keys()
	var a: Array = get_meta("args", [])
	if a.size() > 1:
		var b := int(a[1])
		chars = chars.slice(b * 8, b * 8 + 8)
	var t := 0
	NPCDriver.preload_characters()
	while chars.any(func(c): return not NPCDriver.is_ready(c)) and t < 2400:
		await get_tree().process_frame
		t += 1
	for i in chars.size():
		var v := HumanoidVisual.new()
		v.character_file = chars[i]
		root.add_child(v)
		v.position = Vector3((i - chars.size() * 0.5) * 0.9, 0, 0)
		v.rotation.y = PI
		var l := Label3D.new()
		l.text = String(chars[i]).substr(2, 2)
		l.font_size = 48
		l.position = v.position + Vector3(0, 2.0, 0)
		root.add_child(l)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.0, 5.2), Vector3(0, 0.95, 0))
	cam.fov = 50
	cam.make_current()
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(out)
	get_tree().quit()
