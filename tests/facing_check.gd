extends Node
## House faces look outwards: every triangle of a house's walls, doors, gable ends and plinth has its normal
## pointing away from its house, so from outside you see the walls rather than straight through them (they used
## to face in). Builds city cells directly (no rendering).
## godot --headless --path . res://tests/runner.tscn -- res://tests/facing_check.gd

const HOUSE_KEYS := ["facade_res:", "door", "shutter", "gable", "plinth"]

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	_run.call_deferred()


## Fraction of the triangles of the surfaces matching `prefixes` whose normal points away from the nearest centre.
func _outward(c: CityCell, prefixes: Array, centres: Array) -> Vector2i:
	var good := 0
	var total := 0
	for key: String in c.meshes:
		if not prefixes.any(func(p): return key.begins_with(p)):
			continue
		var arr: Array = c.meshes[key]
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var tri := idx.size() / 3 if not idx.is_empty() else v.size() / 3
		for t in tri:
			var i0 := idx[t * 3] if not idx.is_empty() else t * 3
			var i1 := idx[t * 3 + 1] if not idx.is_empty() else t * 3 + 1
			var i2 := idx[t * 3 + 2] if not idx.is_empty() else t * 3 + 2
			var m := (v[i0] + v[i1] + v[i2]) / 3.0
			var n := (nrm[i0] + nrm[i1] + nrm[i2]).normalized()
			if Vector2(n.x, n.z).length() < 0.5:
				continue   # (flat bits: sills, tops)
			var best: Vector2 = centres[0]
			for ct: Vector2 in centres:
				if ct.distance_squared_to(Vector2(m.x, m.z)) < best.distance_squared_to(Vector2(m.x, m.z)):
					best = ct
			total += 1
			if Vector2(m.x, m.z).direction_to(best).dot(Vector2(n.x, n.z)) < 0.0:
				good += 1
	return Vector2i(good, total)


func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	var city := world.city
	var d := WorldData.get_data()
	# (downtown blocks hold several buildings per lot, so "away from the lot centre" doesn't hold for their backs)
	for spot: Array in [["Las Lomas", Vector3(-280, 0, -760)], ["Las Lomas west", Vector3(-600, 0, -900)], ["Las Lomas east", Vector3(100, 0, -1000)]]:
		var k := city.cell_of(spot[1].x, spot[1].z)
		var c := CityCell.new(k, d, city.net)
		c.build(city._cell_roads.get(k, []), city._cell_nodes.get(k, []), city._cell_lots.get(k, []))
		var centres := []
		var houses := 0
		for i: int in city._cell_lots.get(k, []):
			var l: Dictionary = d.lots[i]
			centres.append(Vector2((l.x0 + l.x1) * 0.5, (l.z0 + l.z1) * 0.5))
			if l.kind == "house":
				houses += 1
		if centres.is_empty():
			continue
		var r := _outward(c, HOUSE_KEYS, centres)
		_check(houses > 0 and r.y > 0 and r.x == r.y, "%s: %d houses, walls / doors / gables / plinths facing out (%d of %d triangles)" % [spot[0], houses, r.x, r.y])
	print("FACING CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
