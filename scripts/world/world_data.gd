class_name WorldData
extends RefCounted
## The baked world layout (tools/world/gen_world.py): heightmap, road graph, lots, coastline, districts.
## Loaded once and shared; heights are uint16 samples every `step` metres over [-half, half]².

const DIR := "res://assets/world/"

static var _inst: WorldData

var half := 2048.0
var step := 2.0
var n := 2049
var sea := -2.0
var h_min := -64.0
var h_max := 192.0
var nodes: Array = []      # [x, z, y]
var roads: Array = []      # {a, b, pts: [[x, y, z]...], w, lanes, kind, walk, name}
var lots: Array = []       # {kind, x0, z0, x1, z1, ...}
var coast := PackedVector2Array()
var districts: Array = []
var lookout := Vector3.ZERO
var pool: Array = []       # plaza pool rect [x0, z0, x1, z1]
var nature: Image          # wild vegetation density, 4 m per pixel
var _h := PackedByteArray()
var _scale := 1.0


static func get_data() -> WorldData:
	if _inst == null:
		_inst = WorldData.new()
		_inst._load()
	return _inst


static func release() -> void:
	_inst = null


func _load() -> void:
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "world.json"))
	half = j.half
	step = j.step
	n = int(j.n)
	sea = j.sea
	h_min = j.h_min
	h_max = j.h_max
	nodes = j.nodes
	roads = j.roads
	lots = j.lots
	districts = j.districts
	for p: Array in j.coast:
		coast.append(Vector2(p[0], p[1]))
	var lo: Array = j.lookout
	lookout = Vector3(lo[0], lo[2], lo[1])
	pool = j.get("pool", [])
	_h = FileAccess.get_file_as_bytes(DIR + "height.bin")
	_scale = (h_max - h_min) / 65535.0
	nature = (load(DIR + "nature.png") as Texture2D).get_image()
	if nature.is_compressed():
		nature.decompress()


## Wild vegetation density 0..1 at world x/z (hills, shores; 0 in the city).
func nature_at(x: float, z: float) -> float:
	var px := clampi(int((x + half) / (step * 2.0)), 0, nature.get_width() - 1)
	var pz := clampi(int((z + half) / (step * 2.0)), 0, nature.get_height() - 1)
	return nature.get_pixel(px, pz).r


## Height of grid sample (i = column along X, j = row along Z).
func sample(i: int, j: int) -> float:
	i = clampi(i, 0, n - 1)
	j = clampi(j, 0, n - 1)
	return h_min + _h.decode_u16((j * n + i) * 2) * _scale


## Bilinear terrain height at world x/z.
func height_at(x: float, z: float) -> float:
	var fx := (x + half) / step
	var fz := (z + half) / step
	var i := floori(fx)
	var j := floori(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(sample(i, j), sample(i + 1, j), tx)
	var b := lerpf(sample(i, j + 1), sample(i + 1, j + 1), tx)
	return lerpf(a, b, tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := step
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


## Index of the grid sample at or below world coordinate v.
func index_of(v: float) -> int:
	return floori((v + half) / step)
