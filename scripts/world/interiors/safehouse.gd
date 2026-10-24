class_name Safehouse
extends Interior
## The player's place across the avenue from the start: a lounge with a sofa and TV, a kitchenette, a day bed to
## sleep on. Sleeping passes the night (or 6 hours), patches the player up and opens the save slots.

const BED := Vector3(-6.2, 0, -10.0)


func _init() -> void:
	width = 16.0
	depth = 13.0
	door_x = 3.0
	windows = [[-6.5, -1.5], [5.0, 7.0]]
	ext = "white_stucco"
	ext_tint = Color(0.95, 0.9, 0.8)
	int_tint = Color(0.86, 0.88, 0.84)
	floor_tex = "laminate_floor_02"
	floor_tint = Color(0.8, 0.72, 0.62)
	floor_tile = 2.0
	light_color = Color(1.0, 0.88, 0.72)


func _build() -> void:
	add_to_group("interactables")
	# lounge: sofa facing the TV, coffee table, plant, clock on the wall
	furnish("sofa_02", Vector3(2.0, 0, -8.6), 0.0)
	furnish("modern_coffee_table_01", Vector3(2.0, 0, -6.6), 0.0)
	furnish("side_table_01", Vector3(2.0, 0, -3.9), 180.0)
	furnish("Television_01", Vector3(2.0, 0.55, -3.9), 180.0, false)
	furnish("potted_plant_02", Vector3(6.9, 0, -12.0), 0.0)
	furnish("wall_clock", Vector3(2.0, 2.3, -12.82), 0.0, false)
	furnish("steel_frame_shelves_01", Vector3(7.3, 0, -8.5), -90.0)
	# kitchenette on the left
	furnish("electric_stove", Vector3(-7.4, 0, -4.2), 90.0)
	furnish("vintage_microwave", Vector3(-7.45, 0.92, -6.0), 90.0, false)
	furnish("dining_table", Vector3(-4.6, 0, -5.4), 0.0)
	furnish("dining_chair_02", Vector3(-4.6, 0, -4.4), 180.0)
	furnish("dining_chair_02", Vector3(-4.6, 0, -6.4), 0.0)
	# bed in the back corner
	furnish("vintage_day_bed", BED, 90.0)
	furnish("throw_pillows_01", BED + Vector3(-0.5, 0.45, 0), 90.0, false)


func interact_point() -> Vector3:
	return world(BED + Vector3(1.4, 0, 0))


func interact_range() -> float:
	return 1.8


func interact_prompt(_p: Node) -> String:
	var w := Game.world as World
	if w and w.wanted and w.wanted.stars > 0:
		return ""
	return "Sleep and save"


func interact(p: Node) -> void:
	var w := Game.world as World
	var pl := p as Player
	# sleep through to the morning (or six hours), wake up patched up
	var h := fposmod(w.time_of_day, 24.0)
	w.time_of_day = 8.0 if (h > 18.0 or h < 6.0) else fposmod(h + 6.0, 24.0)
	pl.health = 100.0
	pl.health_changed.emit(pl.health, pl.armor)
	Game.message("You slept well.")
	var pm := get_tree().get_first_node_in_group("pause_menu")
	if pm:
		pm.open()
		pm._show_slots(true)
