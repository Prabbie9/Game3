class_name Safehouse
extends Interior
## The player's place across the avenue from the start: a lounge with a sofa and TV, a kitchenette, a day bed to
## sleep on. Sleeping passes the night (or 6 hours), patches the player up and opens the save slots.

const BED := Vector3(-7.35, 0, -10.6)


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
	var ceil := height - 0.3
	# lounge on the right: TV on a long cabinet against the wall, sofa and armchair round a coffee table, a fan
	furnish("modern_wooden_cabinet", Vector3(7.55, 0, -7.5), -90.0)
	furnish("Television_01", Vector3(7.5, 0.68, -7.6), -90.0, false)
	furnish("gaming_console", Vector3(7.55, 0.68, -6.75), -90.0, false)
	furnish("book_encyclopedia_set_01", Vector3(7.6, 0.68, -8.7), -90.0, false)
	furnish("sofa_02", Vector3(3.6, 0, -7.5), 90.0)
	furnish("throw_pillows_01", Vector3(3.55, 0.45, -7.5), 90.0, false)
	furnish("modern_coffee_table_01", Vector3(5.55, 0, -7.5), 0.0)
	furnish("ArmChair_01", Vector3(5.5, 0, -10.1), 0.0)
	furnish("side_table_01", Vector3(3.6, 0, -5.9), 0.0)
	furnish("standing_picture_frame_01", Vector3(3.6, 0.55, -5.9), 30.0, false)
	furnish("ceiling_fan", Vector3(5.2, ceil, -7.5), 0.0, false)
	furnish("hanging_picture_frame_02", Vector3(7.83, 1.95, -7.5), -90.0, false)
	furnish("wooden_bookshelf_worn", Vector3(2.4, 0, -12.55), 0.0)
	furnish("wall_clock", Vector3(5.5, 2.45, -12.82), 0.0, false)
	furnish("potted_plant_02", Vector3(7.3, 0, -12.3), 0.0)
	furnish("planter_box_01", Vector3(6.0, 0, -0.45), 0.0)
	# kitchen along the left wall, dining table in front of it
	furnish("electric_stove", Vector3(-7.45, 0, -1.9), 90.0)
	furnish("painted_wooden_cabinet", Vector3(-7.5, 0, -3.25), 90.0)
	furnish("vintage_microwave", Vector3(-7.5, 1.18, -3.25), 90.0, false, 0.5)
	furnish("modern_wooden_cabinet", Vector3(-7.55, 0, -5.3), 90.0)
	furnish("vintage_electric_kettle", Vector3(-7.55, 0.68, -4.6), 120.0, false)
	furnish("dining_table", Vector3(-3.9, 0, -4.2), 0.0)
	furnish("dining_chair_02", Vector3(-4.5, 0, -3.2), 180.0)
	furnish("dining_chair_02", Vector3(-3.3, 0, -3.2), 180.0)
	furnish("dining_chair_02", Vector3(-3.9, 0, -5.2), 0.0)
	# bedroom at the back left, behind a partition with an opening
	partition(Vector3(-8.0, 0, -8.0), Vector3(-3.6, 0, -8.0))
	partition(Vector3(-1.4, 0, -8.0), Vector3(-1.4, 0, -13.0))
	furnish("vintage_day_bed", BED, 90.0)
	furnish("throw_pillows_01", BED + Vector3(0.1, 0.45, -0.6), 90.0, false)
	furnish("ClassicNightstand_01", Vector3(-7.55, 0, -12.45), 90.0)
	furnish("alarm_clock_01", Vector3(-7.55, 0.7, -12.4), 70.0, false)
	furnish("drawer_cabinet", Vector3(-4.2, 0, -12.7), 0.0)
	furnish("vintage_suitcase", Vector3(-2.4, 0, -12.75), 0.0, true, 0.45)
	furnish("hanging_picture_frame_01", Vector3(-7.83, 1.85, -10.6), 90.0, false)
	furnish("ornate_mirror_01", Vector3(-5.6, 1.55, -8.07), 180.0, false)


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
