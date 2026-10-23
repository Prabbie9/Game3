extends Node
## Every car class on a flat test pad: 0-100 km/h time, speed after 8 s, a handbrake turn stays upright and
## leaves skid marks. godot --headless --path . res://tests/runner.tscn -- res://tests/vehicle_classes_check.gd

var fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2000, 2, 2000)
	cs.shape = b
	sb.add_child(cs)
	sb.position.y = -1.0
	root.add_child(sb)
	var marks := SkidMarks.new()
	root.add_child(marks)
	print("CLASS        0-100 km/h   v(12 s)  gear  upright  marks")
	for model: String in Vehicle.SPECS:
		if int(Vehicle.SPECS[model].force) == 0 or Vehicle.SPECS[model].has("rider"):
			continue  # aircraft, boats and bikes have their own checks
		var v := Vehicle.new()
		v.model = model
		v.position = Vector3(0, 0.8, 0)
		root.add_child(v)
		for i in 30:
			await get_tree().physics_frame
		v.set_driver(self)
		Input.action_press("accelerate")
		var t100 := -1.0
		var t := 0.0
		while t < 12.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if t100 < 0.0 and v.speed_kmh() >= 100.0:
				t100 = t
		var v8 := v.speed_kmh()
		var g := v.gear
		# handbrake turn at speed
		var m0 := marks._next
		Input.action_press("steer_left")
		Input.action_press("handbrake")
		for i in 90:
			await get_tree().physics_frame
		Input.action_release("handbrake")
		Input.action_release("steer_left")
		Input.action_release("accelerate")
		for i in 120:
			await get_tree().physics_frame
		var up := v.global_basis.y.dot(Vector3.UP)
		var made := posmod(marks._next - m0, SkidMarks.MAX)
		var heavy: bool = Vehicle.SPECS[model].get("sound", "") == "heavy"
		var quick_enough := (t100 > 0.0 and t100 < 12.0) if not heavy else v8 > 55.0  # buses and trucks are slow off the line
		var ok := quick_enough and up > 0.8 and made > 5
		if not ok:
			fails += 1
		print("%-10s   %6s s   %5.0f    %d    %.2f   %4d  %s" % [model, ("%.1f" % t100) if t100 > 0 else "  -", v8, g, up, made, "" if ok else "FAIL"])
		v.queue_free()
		await get_tree().physics_frame
	print("VEHICLE CLASSES CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)
