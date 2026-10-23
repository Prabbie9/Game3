extends Node
func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_run.call_deferred()
func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
	Game.controls_enabled = false
	world.player.global_position = Vector3(-140, 0.2, 8)
	for i in 60 * 40:
		await get_tree().physics_frame
	for c in world.traffic.cars:
		if is_instance_valid(c.v) and c.v.global_position.distance_to(Vector3(-160, 0, 0)) < 30:
			print("car %s at %s lane %s s %.1f speed %.1f stuck %.1f reason '%s' block %s" % [c.v.model, c.v.global_position.snapped(Vector3.ONE * 0.1), world.traffic.graph.lanes[c.lane].kind, c.s, c.v.linear_velocity.length(), c.stuck, c.reason, c.block])
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(-145, 26, 14), Vector3(-160, 0, 0))
	cam.make_current()
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(get_meta("args")[0])
	get_tree().quit()
