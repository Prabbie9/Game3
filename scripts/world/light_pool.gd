class_name LightPool
extends Node3D
## Street lights at night: a fixed pool of OmniLights moved to the lamps nearest the camera (the city has
## thousands of lamps; only the closest few cast real light, the rest glow through their bulbs).

const REFRESH := 0.25

var city: City
var count := 28
var night := 0.0
var _lights: Array[OmniLight3D] = []
var _timer := 0.0
var _bulb_mats: Array[StandardMaterial3D] = []


func setup(c: City, n: int) -> void:
	city = c
	count = n
	for i in 48:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.omni_range = 16.0
		l.omni_attenuation = 1.4
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.light_specular = 0.6
		l.visible = false
		add_child(l)
		_lights.append(l)
	# the lamp model's glass/bulb surfaces glow at night
	var m: Mesh = PropCatalog.mesh("street_lamp_01")
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		if mat is StandardMaterial3D and (String(mat.resource_name).contains("bulb") or String(mat.resource_name).contains("glass")):
			var sm := mat as StandardMaterial3D
			sm.emission_enabled = true
			sm.emission = Color(1.0, 0.8, 0.55)
			_bulb_mats.append(sm)


func set_count(n: int) -> void:
	for i in _lights.size():
		_lights[i].visible = false
	count = clampi(n, 0, _lights.size())


func _process(delta: float) -> void:
	for sm in _bulb_mats:
		sm.emission_energy_multiplier = night * 6.0
	if night < 0.05 or count == 0:
		for l in _lights:
			l.visible = false
		return
	_timer -= delta
	if _timer > 0.0:
		for l in _lights:
			l.light_energy = night * 2.2
		return
	_timer = REFRESH
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var p := cam.global_position
	var best: Array = []
	for lp: Vector3 in city.lights:
		var d := lp.distance_squared_to(p)
		if d < 160.0 * 160.0:
			best.append([d, lp])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for i in _lights.size():
		var l := _lights[i]
		if i < mini(count, best.size()):
			l.global_position = best[i][1]
			l.light_energy = night * 2.2
			l.visible = true
		else:
			l.visible = false
