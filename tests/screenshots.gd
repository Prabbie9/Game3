extends Node
## Renders the fixed review shots to PNG (software Vulkan is fine; keep the list short).
## xvfb-run -a godot --path . res://tests/runner.tscn -- res://tests/screenshots.gd OUT_DIR [shot,shot,...]

var out := "tests/output"
var only := []
var world: World


func _ready() -> void:
	var a: Array = get_meta("args", [])
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		only = a[1].split(",")
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().root.size = Vector2i(1280, 720)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	var vp := get_viewport().get_viewport_rid()
	print("shot %s  draws %d (+%d shadow)  prims %.2fM  objects %d" % [name,
		RenderingServer.viewport_get_render_info(vp, 0, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, 1, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, 0, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1e6,
		RenderingServer.viewport_get_render_info(vp, 0, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)])


func _want(n: String) -> bool:
	return only.is_empty() or n in only


func _run() -> void:
	if _want("menu"):
		var menu: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		get_tree().root.add_child(menu)
		await _frames(40)
		await _snap("menu")
		menu.queue_free()
		await _frames(2)
	var ws: PackedScene = load("res://scenes/world/world.tscn")
	world = ws.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	Game.controls_enabled = false
	world.time_scale = 0.0
	world.weather.auto_change = false
	world.weather.set_weather(Weather.Kind.CLEAR, true)
	await _frames(30)
	var p: Player = world.player
	p.cam.camera.make_current()
	if _want("day"):
		world.time_of_day = 16.9
		world._update_sun()
		p.cam.yaw = deg_to_rad(120)
		p.cam.pitch = -0.1
		await _frames(25)
		await _snap("day_street")
	if _want("aim"):
		p.cam.yaw = deg_to_rad(75)
		p.cam.pitch = -0.02
		Input.action_press("aim")
		await _frames(25)
		await _snap("on_foot_aim")
		Input.action_release("aim")
	if _want("wide"):
		var c := Camera3D.new()
		world.add_child(c)
		c.global_position = Vector3(-30, 28, 45)
		c.look_at(Vector3(20, 6, -10))
		c.make_current()
		await _frames(20)
		await _snap("aerial")
		c.queue_free()
		p.cam.camera.make_current()
	if _want("tour") or only.any(func(n): return String(n).begins_with("tour_")):
		# district overview shots from fixed cameras (streaming follows the active camera)
		var shots := [
			["tour_beach", Vector3(-700, 14, 60), Vector3(-860, 0, -40)],
			["tour_docks", Vector3(420, 30, 540), Vector3(560, 4, 800)],
			["tour_hills", Vector3(420, 40, -420), Vector3(800, 90, -850)],
			["tour_suburbs", Vector3(-300, 16, -600), Vector3(-200, 2, -760)],
			["tour_freeway", Vector3(-520, 9, 300), Vector3(-560, 0, 120)],
			["tour_downtown", Vector3(150, 60, 220), Vector3(0, 20, 0)],
			["tour_yard", Vector3(470, 14, 690), Vector3(520, 2, 760)],
			["tour_oaks", Vector3(560, 0, -620), Vector3(700, 0, -760)],
		]
		for sh: Array in shots:
			if not (_want("tour") or _want(sh[0])):
				continue
			if sh[0] == "tour_oaks":
				sh[1].y = world.data.height_at(sh[1].x, sh[1].z) + 12.0
				sh[2].y = world.data.height_at(sh[2].x, sh[2].z)
			var c := Camera3D.new()
			world.add_child(c)
			c.look_at_from_position(sh[1], sh[2])
			c.far = 4000.0
			c.make_current()
			world.warm_up(sh[1])
			await _frames(20)
			await _snap(sh[0])
			c.queue_free()
		p.cam.camera.make_current()
		world.warm_up(p.global_position)
	if _want("parked"):
		# behind a parked car on a kerbside street near the spawn, then over a car park
		var slots: Array = world.parked._slots
		var picks := {"parked_street": [Vector3(60, 0, 40), false], "parked_lot": [Vector3(0, 0, 0), true]}
		for name: String in picks:
			var best := -1
			var bd := INF
			for i in slots.size():
				var sp: Vector3 = slots[i][0]
				var in_lot := absf(sp.y - CityCell.CURB_H) < 0.001
				if in_lot != picks[name][1]:
					continue
				var d := sp.distance_to(picks[name][0])
				if d < bd:
					bd = d
					best = i
			var s: Array = slots[best]
			var fwd := Vector3(-sin(s[1]), 0, -cos(s[1]))
			var rgt := Vector3(-fwd.z, 0, fwd.x)
			var c := Camera3D.new()
			world.add_child(c)
			var at: Vector3 = s[0]
			if picks[name][1]:
				c.look_at_from_position(at + Vector3(-14, 9, 22), at + Vector3(0, 0, 6))
			else:
				c.look_at_from_position(at - fwd * 9.0 - rgt * 2.2 + Vector3(0, 1.7, 0), at + fwd * 25.0 + Vector3(0, 0.6, 0))
			c.make_current()
			world.warm_up(at)
			await _frames(30)
			await _snap(name)
			c.queue_free()
		p.cam.camera.make_current()
		world.warm_up(p.global_position)
	if _want("signals"):
		# hazards + tail lights at dusk, from behind and from the front
		world.time_of_day = 19.4
		world._update_sun()
		var cars: Array = world.get_tree().get_nodes_in_group("vehicles").slice(0, 2)
		for v: Vehicle in cars:
			v.set_headlights(true)
			v.set_indicator(Vehicle.Blinker.HAZARD)
		var v0: Vehicle = cars[0]
		for view: Array in [["signals_rear", Vector3(-2.5, 1.4, 7.0)], ["signals_front", Vector3(2.5, 1.3, -7.0)]]:
			var c := Camera3D.new()
			world.add_child(c)
			c.look_at_from_position(v0.global_transform * view[1], v0.global_position + Vector3(0, 0.7, 0))
			c.make_current()
			await _frames(10)
			for v: Vehicle in cars:
				v._blink = 0.1
				v._update_lights()
			await _frames(2)
			await _snap(view[0])
			c.queue_free()
		for v: Vehicle in cars:
			v.set_indicator(Vehicle.Blinker.OFF)
			v.set_headlights(false)
		world.time_of_day = 16.9
		world._update_sun()
		p.cam.camera.make_current()
	if _want("bike"):
		# riding: dirt bike from the side, then pedalling the bicycle
		for model: String in ["dirtbike", "bicycle"]:
			var bike: Bike = null
			for v in world.get_tree().get_nodes_in_group("vehicles"):
				if v is Bike and v.model == model:
					bike = v
			p.global_position = bike.global_transform * Vector3(-1.2, 0, 0.3)
			p.enter_vehicle(bike)
			await _frames(40)
			if model == "bicycle":
				bike.crank = 1.1
			var c := Camera3D.new()
			world.add_child(c)
			c.look_at_from_position(bike.global_transform * Vector3(-3.4, 1.3, -0.6), bike.global_position + Vector3(0, 0.9, 0))
			c.make_current()
			await _frames(6)
			await _snap("ride_" + model)
			c.queue_free()
			p.cam.camera.make_current()
			p.exit_vehicle()
			await _frames(10)
	if _want("weapons") or only.any(func(n): return String(n).begins_with("wpn_")):
		# each weapon in the hands: relaxed and aimed, from the right side and from behind the shoulder
		for id: String in WeaponDefs.ORDER:
			if not (_want("weapons") or _want("wpn_" + id)):
				continue
			p.weapon.give(id)
			p.weapon.select(id)
			# on the pavement by the start, the road in front
			p.global_position = Vector3(30.0, 0.2, 8.6)
			p.rotation.y = PI * 0.5
			p.cam.yaw = PI * 0.5
			p.cam.pitch = -0.05
			for aim in [false, true]:
				if aim:
					Game.controls_enabled = true
					Input.action_press("aim")
				await _frames(14)
				var c := Camera3D.new()
				world.add_child(c)
				c.fov = 40
				c.look_at_from_position(p.global_transform * Vector3(2.3, 1.45, -0.9), p.global_transform * Vector3(0, 1.25, -0.25))
				c.make_current()
				await _frames(3)
				await _snap("wpn_%s_%s" % [id, "aim" if aim else "idle"])
				c.queue_free()
				p.cam.camera.make_current()
				Input.action_release("aim")
				Game.controls_enabled = false
			await _frames(6)
	if _want("street"):
		# street life: a junction near the start with traffic, signals and people (let things populate first)
		for i in 900:
			await get_tree().physics_frame
		for view: Array in [["street_junction", Vector3(10.5, 1.8, 9.5), Vector3(-6.0, 0.6, -6.0)], ["street_pavement", Vector3(60.0, 1.7, 10.5), Vector3(85.0, 1.0, 8.0)]]:
			var c := Camera3D.new()
			world.add_child(c)
			c.look_at_from_position(view[1], view[2])
			c.fov = 60
			c.make_current()
			await _frames(12)
			await _snap(view[0])
			c.queue_free()
		p.cam.camera.make_current()
	if _want("police"):
		# two stars at the start: officers on foot and patrol cars close in (the player can't die for the shot)
		Game.crime("kill_police", p.global_position)
		for i in 900:
			p.health = 100.0
			world.wanted.report_sighting(p.global_position)
			await get_tree().physics_frame
		await _snap("police_hud")
		var cops: Array = get_tree().get_nodes_in_group("police")
		var c := Camera3D.new()
		world.add_child(c)
		# side view of the player and the nearest officer
		var near: Node3D = null
		for cp: Node3D in cops:
			if near == null or cp.global_position.distance_to(p.global_position) < near.global_position.distance_to(p.global_position):
				near = cp
		# over the nearest officer's shoulder, towards the player
		var look := p.global_position + Vector3(0, 1.0, 0)
		var from := look + Vector3(6.0, 2.0, 6.0)
		if near:
			var d := p.global_position - near.global_position
			d.y = 0.0
			var side := Vector3(-d.z, 0, d.x).normalized()
			from = near.global_position - d.normalized() * 3.0 + side * 1.2 + Vector3(0, 1.9, 0)
			look = (near.global_position + p.global_position) * 0.5 + Vector3(0, 1.0, 0)
		c.look_at_from_position(from, look)
		c.fov = 60
		c.make_current()
		await _frames(12)
		await _snap("police_scene")
		c.queue_free()
		p.cam.camera.make_current()
	if _want("interiors"):
		# the safehouse across the avenue and the diner behind the start, from the street and inside
		for view: Array in [["safehouse_front", Vector3(-24.0, 1.7, 1.5), Vector3(-25.5, 2.6, 13.0)],
				["safehouse_inside", Vector3(-27.75, 1.65, 13.6), Vector3(-22.75, 0.8, 21.6)],
				["safehouse_lounge", Vector3(-23.75, 1.65, 16.6), Vector3(-31.75, 0.8, 21.6)],
				["safehouse_bedroom", Vector3(-22.25, 1.6, 21.6), Vector3(-17.75, 0.6, 24.1)],
				["diner_front", Vector3(25.0, 1.7, 1.5), Vector3(24.5, 2.6, 13.0)],
				["diner_inside", Vector3(32.5, 1.65, 13.6), Vector3(20.0, 1.0, 21.0)]]:
			var c := Camera3D.new()
			world.add_child(c)
			c.look_at_from_position(view[1], view[2])
			c.fov = 64
			c.make_current()
			await _frames(16)
			await _snap(view[0])
			c.queue_free()
		p.cam.camera.make_current()
	if _want("life"):
		# a lucky coin in the park, pigeons on the plaza (pecking, then scattering), an airliner overhead
		var col := world.collectibles
		var c0: Node3D = col._coins[0]
		var keep := p.global_transform
		p.global_position = col.spots[0] + Vector3(8.0, 1.0, 0)
		for i in 240:
			await _frames(1)
			if c0.get_meta("settled"):
				break
		var c := Camera3D.new()
		world.add_child(c)
		c.look_at_from_position(c0.global_position + Vector3(2.2, 0.6, 1.2), c0.global_position)
		c.fov = 50
		c.make_current()
		await _frames(20)
		await _snap("life_coin")
		var flock: Dictionary = {}
		for f: Dictionary in world.birds.flocks:
			if f.kind == "pigeon" and Vector2(f.anchor.x, f.anchor.z).length() < 120.0:
				flock = f
				break
		if not flock.is_empty():
			var a: Vector3 = flock.anchor
			p.global_position = a + Vector3(30.0, 1.0, 0)
			c.look_at_from_position(a + Vector3(4.5, 1.2, 3.0), a + Vector3(0, 0.1, 0))
			for i in 120:
				await _frames(1)
				if flock.ground > -INF:
					break
			c.look_at_from_position(a + Vector3(3.0, flock.ground + 0.9, 2.2), a + Vector3(0, flock.ground + 0.1, 0))
			await _frames(30)
			await _snap("life_pigeons")
			Game.noise(a, 30.0, p)
			# frames take seconds here: step the flock by hand, a third of a second after take-off
			world.birds.set_process(false)
			for i in 20:
				world.birds._update(1.0 / 60.0)
			c.look_at_from_position(a + Vector3(5.0, flock.ground + 1.0, 4.0), a + Vector3(0, flock.ground + 1.2, 0))
			await _frames(2)
			await _snap("life_pigeons_fly")
		var ac := world.aircraft
		ac.launch()
		await _frames(2)
		var eye := c.global_position
		ac._plane.global_position = eye - ac._dir * 120.0 + Vector3(0, 700.0, 0)
		ac._plane.look_at(ac._plane.global_position + ac._dir, Vector3.UP)
		ac.set_process(false)   # (frames take seconds here: it would fly out of the shot)
		c.fov = 22
		c.look_at_from_position(eye, ac._plane.global_position)
		await _frames(3)
		await _snap("life_plane")
		c.queue_free()
		world.birds.set_process(true)
		ac.set_process(true)
		p.global_transform = keep
		p.cam.camera.make_current()
	if _want("shop"):
		# the gun shop from the street, then inside at the counter
		for view: Array in [["shop_front", Vector3(30.0, 1.7, -2.0), Vector3(23.0, 2.2, -12.0)], ["shop_inside", Vector3(25.5, 1.65, -13.2), Vector3(22.0, 1.3, -21.0)]]:
			var c := Camera3D.new()
			world.add_child(c)
			c.look_at_from_position(view[1], view[2])
			c.fov = 62
			c.make_current()
			await _frames(16)
			await _snap(view[0])
			c.queue_free()
		p.cam.camera.make_current()
	if _want("pool"):
		var pl: Array = world.data.pool
		var pr := Rect2(pl[0], pl[1], pl[2] - pl[0], pl[3] - pl[1])
		var pc := Vector3(pr.get_center().x, 0.0, pr.get_center().y)
		var c := Camera3D.new()
		world.add_child(c)
		c.look_at_from_position(pc + Vector3(-9.0, 4.0, 8.0), pc + Vector3(0, -0.5, 0))
		c.make_current()
		await _frames(20)
		await _snap("pool")
		c.queue_free()
		p.cam.camera.make_current()
		var keep := p.global_transform
		p.global_position = pc + Vector3(1.0, -1.2, 0.5)
		p.cam.yaw = deg_to_rad(200)
		p.cam.pitch = -0.25
		await _frames(40)
		await _snap("swim")
		p.state = Player.State.ON_FOOT
		p.collision_layer = 2
		p.collision_mask = Player.MASK_ON_FOOT
		p.velocity = Vector3.ZERO
		p.global_transform = keep
		p.visual.jump_to("ground")
		await _frames(10)
	if _want("enter"):
		var v: Vehicle = world.get_tree().get_nodes_in_group("vehicles")[0]
		p.global_position = v.driver_door_position() + v.global_basis.x * -0.8
		await _frames(5)
		p.visual.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		p.enter_vehicle(v)
		await _frames(12)
		var c := Camera3D.new()
		world.add_child(c)
		var door := v.driver_door_position()
		c.look_at_from_position(door - v.global_basis.x * 5.5 + v.global_basis.z * 0.6 + Vector3(0, 1.5, 0), door + Vector3(0, 0.9, 0) + v.global_basis.x * 0.8)
		c.fov = 55
		c.make_current()
		var prev := 0.0
		for t in [0.6, 2.0, 3.4, 5.6]:
			p.visual.tree.advance(t - prev)
			prev = t
			await _frames(3)
			await _snap("enter_%02d" % int(t * 10))
		p.visual.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		await _frames(10)
		c.queue_free()
		p.cam.camera.make_current()
	if _want("car"):
		var v: Vehicle = world.get_tree().get_nodes_in_group("vehicles")[0]
		if p.state != Player.State.DRIVING:
			p.debug_seat_in(v)
		p.cam.yaw = v.rotation.y + deg_to_rad(150)
		p.cam.pitch = -0.12
		await _frames(30)
		await _snap("in_car")
	if _want("night"):
		world.time_of_day = 22.0
		world._update_sun()
		await _frames(30)
		await _snap("night")
	if _want("rain"):
		world.time_of_day = 15.0
		world._update_sun()
		world.weather.set_weather(Weather.Kind.RAIN, true)
		await _frames(40)
		await _snap("wet")
		world.weather.set_weather(Weather.Kind.CLEAR, true)
	if _want("map"):
		world.full_map._toggle()
		await _frames(6)
		await _snap("map")
		world.full_map._toggle()
		await _frames(2)
	if _want("pause"):
		var pm: CanvasLayer = load("res://scripts/ui/pause_menu.gd").new()
		world.add_child(pm)
		await _frames(2)
		pm.open()
		await _frames(5)
		await _snap("pause")
		pm._show_stats()
		await _frames(4)
		await _snap("pause_stats")
		pm._open_settings()
		await _frames(4)
		await _snap("settings_graphics")
		pm._settings._show_tab(4)
		await _frames(4)
		await _snap("settings_controls")
		pm.resume()
	get_tree().quit()
