extends Node
## Milestone 5 combat in the real world: every weapon fires/swings and hurts a pedestrian, head shots
## multiply, a shot past the shoulder misses, reloads refill, rockets and grenades explode, drive-by works,
## pickups give weapons and the gun shop sells.
## godot --headless --path . res://tests/runner.tscn -- res://tests/weapons_check.gd

var fails := 0
var world: World
var p: Player


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame


func _ped(at: Vector3, yaw := 0.0) -> Pedestrian:
	var ped := Pedestrian.new()
	ped.character_file = "ch02_nonpbr"
	ped.position = at
	ped.rotation.y = yaw
	world.add_child(ped)
	await _secs(0.4)
	return ped


## Point the camera so its centre ray passes through `target`.
func _aim_at(target: Vector3) -> void:
	for i in 12:
		await get_tree().process_frame
		var from := p.cam.camera.global_position
		var to := target - from
		p.cam.yaw = atan2(-to.x, -to.z)
		p.cam.pitch = atan2(to.y, Vector2(to.x, to.z).length())


func _shoot(n := 1) -> void:
	for i in n:
		Input.action_press("fire")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release("fire")
		await _secs(maxf(float(p.weapon.data.get("interval", 0.2)) + 0.05, 0.1))


func _run() -> void:
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
	Game.controls_enabled = true
	Game.aim_assist = false
	p = world.player
	await _secs(1.0)
	var t := 0.0
	while not NPCDriver.is_ready("ch02_nonpbr") and t < 30.0:
		await _secs(0.25)
		t += 0.25
	_check(NPCDriver.is_ready("ch02_nonpbr"), "pedestrian character loaded")
	for id: String in WeaponDefs.ORDER:
		p.weapon.give(id)
	_check(p.weapon.owned_list().size() == WeaponDefs.ORDER.size(), "all %d weapons carried" % WeaponDefs.ORDER.size())

	# an open stretch of the wide avenue south of the start
	var base := Vector3(40.0, 0.1, -2.0)
	p.global_position = base
	p.rotation.y = 0.0
	p.cam.yaw = 0.0
	await _secs(0.5)

	# --- every gun hurts a pedestrian 9 m ahead
	for id: String in ["pistol", "smg", "shotgun", "rifle", "sniper"]:
		p.weapon.select(id)
		var ped := await _ped(base + Vector3(0, 0, -9.0), 0.0)
		Input.action_press("aim")
		await _secs(0.5)
		await _aim_at(ped.aim_point() + Vector3(0, -0.1, 0))
		var mag0 := p.weapon.in_mag
		await _shoot(1)
		_check(ped.health < 100.0, "%s hits (health %.0f, mag %d -> %d)" % [id, ped.health, mag0, p.weapon.in_mag])
		_check(p.weapon.in_mag == mag0 - 1, "%s uses a round" % id)
		Input.action_release("aim")
		ped.queue_free()
		await _secs(0.3)

	# --- head shot with the pistol kills outright; a shot past the shoulder misses
	p.weapon.select("pistol")
	var ped2 := await _ped(base + Vector3(0, 0, -7.0), 0.0)
	Input.action_press("aim")
	await _secs(0.5)
	var sh := ped2._bone_pos("LeftShoulder")
	await _aim_at(sh + Vector3(-0.45, 0.0, 0))
	await _shoot(1)
	_check(ped2.health == 100.0, "shot 0.45 m past the shoulder misses (health %.0f)" % ped2.health)
	await _aim_at(ped2._bone_pos("Head") + Vector3(0, 0.03, 0))
	await _shoot(1)
	_check(not ped2.is_alive(), "head shot kills (health %.0f)" % ped2.health)
	await _secs(1.5)
	_check(ped2.ragdoll.active, "dies as a ragdoll")
	Input.action_release("aim")

	# --- reload
	var a: Array = p.weapon.ammo["pistol"]
	var before := int(a[0])
	Input.action_press("aim")
	await _secs(0.4)
	Input.action_press("reload")
	await get_tree().process_frame
	Input.action_release("reload")
	_check(p.weapon.reloading(), "reload starts (mag %d)" % before)
	await _secs(1.8)
	_check(p.weapon.in_mag == 12, "reload fills the magazine (%d)" % p.weapon.in_mag)
	Input.action_release("aim")

	# --- knife
	p.weapon.select("knife")
	var ped3 := await _ped(base + Vector3(0, 0, -1.0), PI)
	p.cam.yaw = 0.0
	await _shoot(1)
	await _secs(1.0)
	_check(ped3.health < 100.0, "knife stab hurts (health %.0f)" % ped3.health)
	ped3.queue_free()

	# --- rocket into a car down the street
	var car := Vehicle.new()
	car.model = "sedan"
	car.position = base + Vector3(0, 0.6, -24.0)
	world.add_child(car)
	await _secs(1.5)
	p.weapon.select("launcher")
	Input.action_press("aim")
	await _secs(0.6)
	await _aim_at(car.global_position + Vector3(0, 0.3, 0))
	var h0: float = car.damage.health
	await _shoot(1)
	await _secs(1.2)
	_check(car.damage.health < h0 - 100.0 or car.damage.wrecked, "rocket damages the car (%.0f -> %.0f)" % [h0, car.damage.health])
	Input.action_release("aim")

	# --- grenade
	p.weapon.select("grenade")
	var n0 := p.weapon.in_mag
	var ped4 := await _ped(base + Vector3(0, 0, -8.0), 0.0)
	p.cam.yaw = 0.0
	p.cam.pitch = -0.2
	await _shoot(1)
	await _secs(1.0)
	_check(p.weapon.in_mag == n0 - 1, "grenade thrown (%d left)" % p.weapon.in_mag)
	var g := world.find_children("*", "Grenade", true, false)
	_check(g.size() == 1, "grenade in the world")
	if g.size() == 1:
		print("      grenade at %s" % (g[0] as Node3D).global_position)
	await _secs(3.0)
	_check(world.find_children("*", "Grenade", true, false).is_empty(), "grenade went off")
	_check(not ped4.is_alive() or ped4.health < 100.0, "the blast hurts the pedestrian (health %.0f)" % ped4.health)

	# --- drive-by from a car
	p.weapon.select("pistol")
	var dc := Vehicle.new()
	dc.model = "hatchback"
	dc.position = base + Vector3(6.0, 0.6, 10.0)
	world.add_child(dc)
	await _secs(1.5)
	p.debug_seat_in(dc)
	await _secs(0.5)
	p.weapon.select("smg")
	var smg0 := p.weapon.in_mag
	Input.action_press("aim")
	await _secs(0.5)
	_check(p.weapon.drive_by, "aiming from the seat")
	p.cam.yaw = dc.rotation.y + PI * 0.5
	await _shoot(3)
	_check(p.weapon.in_mag < smg0, "drive-by fires (%d -> %d)" % [smg0, p.weapon.in_mag])
	Input.action_release("aim")
	await _secs(0.3)
	_check(not p.weapon.drive_by, "stops aiming")
	p.exit_vehicle()
	await _secs(4.0)

	# --- pickups and the shop
	var pk := Pickup.make(Pickup.Kind.ARMOR)
	world.add_child(pk)
	pk.global_position = p.global_position + Vector3(0, 0.6, 0)
	p.armor = 0.0
	await _secs(0.5)
	_check(p.armor >= 99.0, "armour pickup (%.0f)" % p.armor)
	var shop: GunShop = world.get_node("GunShop")
	t = 0.0
	while not shop.is_open() and t < 20.0:
		await _secs(0.25)
		t += 0.25
	_check(shop.is_open(), "the gun shop has a clerk")
	p.global_position = shop.interact_point() + Vector3(0, 0.05, 0)
	await _secs(0.3)
	_check(p.nearest_interactable() == shop, "counter is in reach")
	Input.action_press("interact")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("interact")
	await get_tree().process_frame
	var menus := world.find_children("*", "ShopMenu", true, false)
	_check(menus.size() == 1, "shop menu opens")
	if menus.size() == 1:
		var m: ShopMenu = menus[0]
		Game.money = 1000
		p.armor = 0.0
		m._buy("armor")
		_check(Game.money == 1000 - ShopMenu.ARMOR_PRICE and p.armor >= 99.0, "buys armour ($%d left)" % Game.money)
		m.close()
	print("WEAPONS CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
