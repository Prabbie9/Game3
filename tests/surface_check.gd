extends Node
## Getting about over the city's surfaces: up the pier ramp from the boardwalk by car and on foot.
## godot --headless --path . res://tests/runner.tscn -- res://tests/surface_check.gd

var fails := 0
var world: World
var p: Player


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	_run.call_deferred()


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame


func _go(pos: Vector3, yaw: float) -> void:
	p._respawn(Transform3D(Basis(Vector3.UP, yaw), pos), "")
	p.cam.yaw = yaw
	await _secs(0.5)
	var t := 0.0
	while t < 30.0 and not world.city.is_settled():
		await _secs(0.25)
		t += 0.25
	await _secs(1.0)


func _run() -> void:
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
	world.traffic.budget = 0
	world.wanted.process_mode = Node.PROCESS_MODE_DISABLED
	Game.controls_enabled = true
	p = world.player
	await _secs(3.0)
	var pier: Dictionary = WorldData.get_data().lots.filter(func(l): return l.kind == "pier")[0]
	var land := float(pier.x1)
	var deck_x := land - 60.0
	# on foot: from the boardwalk west up the ramp onto the deck
	await _go(Vector3(land + 4.0, 0.6, 0.0), PI * 0.5)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t := 0.0
	while t < 20.0 and p.global_position.x > deck_x:
		await _secs(0.25)
		t += 0.25
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _secs(0.5)
	_check(p.global_position.x <= deck_x + 1.0 and p.global_position.y > 2.0, "walks up the ramp onto the pier deck (x %.1f, y %.2f, %.0f s)" % [p.global_position.x, p.global_position.y, t])
	# by car
	await _go(Vector3(land + 6.0, 0.6, 3.0), PI * 0.5)
	var car := Vehicle.new()
	car.model = "compact"
	world.add_child(car)
	car.global_position = Vector3(land + 6.0, 1.0, 0.0)
	car.rotation.y = PI * 0.5
	await _secs(1.0)
	p.debug_seat_in(car)
	await _secs(0.5)
	car.set_driver_input_enabled(false)
	car.ai_drive = true
	car.ai_throttle = 0.6
	t = 0.0
	while t < 20.0 and car.global_position.x > deck_x:
		await _secs(0.25)
		t += 0.25
	car.ai_throttle = 0.0
	car.ai_brake = 1.0
	await _secs(1.0)
	_check(car.global_position.x <= deck_x + 2.0 and car.global_position.y > 2.0, "drives up the ramp onto the pier deck (x %.1f, y %.2f, %.0f s)" % [car.global_position.x, car.global_position.y, t])
	print("SURFACE CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
