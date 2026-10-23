extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var world: Node = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	print("LOAD %d ms cells %d" % [Time.get_ticks_msec() - t0, world.city._cells.size()])
	world.warm_up(Vector3(800, 80, -800))
	print("LOAD hills cells %d" % world.city._cells.size())
	for i in 30: await get_tree().process_frame
	get_tree().quit()
