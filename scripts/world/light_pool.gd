class_name LightPool
extends Node3D
## Street lights at night: a fixed pool of OmniLights given to the lamps nearest the camera (the city has
## thousands of lamps; only the closest few cast real light, the rest glow through their bulbs). A light stays
## on its lamp until it has faded out, lights fade in and out instead of popping, and a lamp that is lit keeps
## its light until it falls well behind the cut-off, so driving fast down a street doesn't make them flicker.

const REFRESH := 0.1
const FADE := 0.4        # seconds for a light to come up or go out
const REACH := 150.0     # lamps further than this from the camera only glow
const KEEP := 1.25       # a lit lamp keeps its light while nearer than this x the cut-off distance

var city: City
var count := 28
var night := 0.0
var _lights: Array[OmniLight3D] = []
var _level := PackedFloat32Array()   # 0..1 per light (fade)
var _want := PackedByteArray()       # 1: fading in / on, 0: fading out / off
var _lamp: Array = []                # lamp position per light (null: free)
var _slot := {}                      # lamp position -> light index
var _timer := 0.0
var _bulb_mats: Array[StandardMaterial3D] = []


func setup(c: City, n: int) -> void:
	city = c
	count = n
	for i in 48:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.omni_range = 22.0
		l.omni_attenuation = 1.1
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.light_specular = 0.6
		l.distance_fade_enabled = true
		l.distance_fade_begin = REACH - 50.0
		l.distance_fade_length = 40.0
		l.visible = false
		add_child(l)
		_lights.append(l)
	_level.resize(_lights.size())
	_want.resize(_lights.size())
	_lamp.resize(_lights.size())
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
	count = clampi(n, 0, _lights.size())
	_release_all()


func _release_all() -> void:
	for i in _lights.size():
		_lights[i].visible = false
		_level[i] = 0.0
		_want[i] = 0
		_lamp[i] = null
	_slot.clear()


func _process(delta: float) -> void:
	for sm in _bulb_mats:
		sm.emission_energy_multiplier = night * 6.0
	if night < 0.05 or count == 0:
		if not _slot.is_empty():
			_release_all()
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		_assign()
	var step := delta / FADE
	for i in _lights.size():
		if _lamp[i] == null:
			continue
		_level[i] = move_toward(_level[i], float(_want[i]), step)
		var l := _lights[i]
		l.light_energy = night * 4.5 * _level[i] * _level[i] * (3.0 - 2.0 * _level[i])
		l.visible = _level[i] > 0.0
		if _level[i] <= 0.0 and _want[i] == 0:
			_slot.erase(_lamp[i])
			_lamp[i] = null


## Which lamps should be lit now: the nearest `count` (and those already lit that are not far past the cut-off);
## new ones take a free light, ones no longer wanted fade out where they are.
func _assign() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var p := cam.global_position
	var near: Array = []
	for lp: Vector3 in city.lights:
		var d := lp.distance_squared_to(p)
		if d < REACH * REACH:
			near.append([d, lp])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var cut: float = near[mini(count, near.size()) - 1][0] if not near.is_empty() else 0.0
	var keep := cut * KEEP * KEEP
	var wanted := {}
	var most := mini(_lights.size(), count + count / 2)
	for i in near.size():
		var e: Array = near[i]
		if i < count or (_slot.has(e[1]) and float(e[0]) < keep and wanted.size() < most):
			wanted[e[1]] = true
	for i in _lights.size():
		if _lamp[i] != null:
			_want[i] = 1 if wanted.has(_lamp[i]) else 0
	for lp: Vector3 in wanted:
		if _slot.has(lp):
			continue
		var free := _free_light()
		if free < 0:
			break   # every light is busy (some still fading out): the rest get one on a later pass
		_lamp[free] = lp
		_slot[lp] = free
		_want[free] = 1
		_level[free] = 0.0
		_lights[free].global_position = lp


func _free_light() -> int:
	for i in _lights.size():
		if _lamp[i] == null:
			return i
	return -1
