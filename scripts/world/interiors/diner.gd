class_name Diner
extends Interior
## Solano Diner, behind the start: a counter with stools and a till, tables by the windows, a waitress. A meal at
## the counter ($12) puts the player back to full health.

const MEAL := 12
const COUNTER_Z := -8.5

var waitress: Pedestrian


func _init() -> void:
	width = 20.0
	depth = 12.0
	door_x = 0.0
	windows = [[-9.0, -1.6], [1.6, 9.0]]
	ext = "brick_wall_09"
	ext_tint = Color(0.75, 0.5, 0.45)
	int_tint = Color(0.95, 0.9, 0.78)
	floor_tex = "checkered_pavement_tiles"
	floor_tint = Color(0.95, 0.95, 0.95)
	floor_tile = 1.2
	sign_text = "SOLANO DINER"
	sign_color = Color(1.0, 0.35, 0.3)
	light_color = Color(1.0, 0.95, 0.85)


func _build() -> void:
	add_to_group("interactables")
	# counter along the back with a dark top, the till on it, stools in front
	var b := MeshBatch.new()
	b.color = Color(0.62, 0.18, 0.16)
	b.box("wood", Vector3(0, _base + 0.5, COUNTER_Z), Vector3(12.0, 1.0, 0.7))
	b.color = Color(0.85, 0.85, 0.82)
	b.box("metal", Vector3(0, _base + 1.03, COUNTER_Z), Vector3(12.3, 0.06, 0.85))
	# back shelves with glasses
	b.color = Color(0.35, 0.25, 0.18)
	b.box("wood", Vector3(0, _base + 1.6, -depth + 0.45), Vector3(10.0, 0.06, 0.4))
	b.box("wood", Vector3(0, _base + 2.1, -depth + 0.45), Vector3(10.0, 0.06, 0.4))
	_add_batch(b)
	_shape(Vector3(0, _base + 0.5, COUNTER_Z), Vector3(12.0, 1.0, 0.7))
	furnish("CashRegister_01", Vector3(4.5, 1.06, COUNTER_Z), 180.0, false)
	for i in 6:
		furnish("bar_chair_round_01", Vector3(-4.5 + i * 1.6, 0, COUNTER_Z + 1.0), 0.0, false)
	# tables by the windows
	for x: float in [-7.0, -3.6, 3.6, 7.0]:
		furnish("round_wooden_table_01", Vector3(x, 0, -2.0), 0.0)
		furnish("dining_chair_02", Vector3(x - 0.75, 0, -2.0), 90.0)
		furnish("dining_chair_02", Vector3(x + 0.75, 0, -2.0), -90.0)
	furnish("potted_plant_02", Vector3(-9.2, 0, -11.2), 0.0)
	furnish("potted_plant_02", Vector3(9.2, 0, -6.4), 0.0)
	# the back shelves: jugs, vases, bowls and goblets
	var items := ["jug_01", "ceramic_vase_01", "wooden_bowl_01", "metal_jug", "brass_goblets"]
	for row in 2:
		for i in 9:
			var item: String = items[(i + row * 2) % items.size()]
			if row == 1 and item == "ceramic_vase_01":
				item = "wooden_bowl_01"   # (too tall for the top shelf)
			furnish(item, Vector3(-4.0 + i + row * 0.5 - (0.5 if row == 1 and i == 8 else 0.0), 1.63 + row * 0.5, -depth + 0.45), randf_range(-30.0, 30.0), false)
	furnish("CoffeeCart_01", Vector3(7.6, 0, -11.2), 0.0)
	furnish("standing_chalkboard_01", Vector3(-9.0, 0, -6.0), 90.0)
	var ceil := height - 0.3
	furnish("ceiling_fan", Vector3(-5.0, ceil, -4.5), 0.0, false)
	furnish("ceiling_fan", Vector3(5.0, ceil, -4.5), 0.0, false)
	furnish("hanging_picture_frame_02", Vector3(-9.83, 2.0, -9.0), 90.0, false)
	furnish("hanging_picture_frame_03", Vector3(9.83, 2.0, -9.5), -90.0, false)
	_spawn_waitress.call_deferred()


func _spawn_waitress() -> void:
	if not NPCDriver.is_ready("ch21_nonpbr"):
		get_tree().create_timer(1.0).timeout.connect(_spawn_waitress)
		return
	waitress = Pedestrian.new()
	waitress.character_file = "ch21_nonpbr"
	waitress.female = true
	waitress.stay_put = true
	Game.world.add_child(waitress)
	waitress.global_position = world(Vector3(-1.0, 0.02, COUNTER_Z - 1.0))
	waitress.global_rotation.y = global_rotation.y
	waitress.remove_from_group("pedestrians")


func is_open() -> bool:
	return is_instance_valid(waitress) and waitress.is_alive()


func interact_point() -> Vector3:
	return world(Vector3(-1.0, 0, COUNTER_Z + 1.3))


func interact_range() -> float:
	return 2.4


func interact_prompt(_p: Node) -> String:
	return "Order a meal ($%d)" % MEAL if is_open() else ""


func interact(p: Node) -> void:
	var pl := p as Player
	if Game.money < MEAL:
		Game.say("Waitress", "Sorry hon, cash only, and you're a little short.")
		return
	Game.money -= MEAL
	pl.health = 100.0
	pl.health_changed.emit(pl.health, pl.armor)
	Audio.play_at(Audio.stream("world/coins.ogg"), world(Vector3(4.5, 1.1, COUNTER_Z)), -6.0)
	Game.say("Waitress", ["Burger and fries, coming right up.", "Here you go. Enjoy!", "Coffee's on the house, sweetie."][randi() % 3])
	Game.message("Full health.")
