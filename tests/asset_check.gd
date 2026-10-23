extends Node
## Asset check (also run in CI before export): characters are textured, every animation clip resolves,
## key models/textures load. Catches assets that import fine but silently lose data on a fresh checkout.
## godot --headless --path . res://tests/runner.tscn -- res://tests/asset_check.gd

var fails := 0


func _check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		print("FAIL  %s %s" % [name, detail])
		fails += 1


func _ready() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/mixamo_manifest.json"))
	for c in manifest.characters:
		var path := "res://assets/source/mixamo/characters/%s" % _snake(c)
		var ps: PackedScene = load(path)
		_check("character loads", ps != null, path)
		if ps:
			var n := ps.instantiate()
			for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
				var m := mi.mesh.surface_get_material(0) as BaseMaterial3D
				_check("character mesh textured", m != null and m.albedo_texture != null, "%s/%s" % [c, mi.name])
			n.free()
	# baked world data and every city prop model
	var d := WorldData.get_data()
	_check("world heightmap", FileAccess.get_file_as_bytes(WorldData.DIR + "height.bin").size() == d.n * d.n * 2)
	_check("world layout", d.roads.size() > 300 and d.lots.size() > 300, "%d roads %d lots" % [d.roads.size(), d.lots.size()])
	_check("world nature map", d.nature != null and d.nature.get_width() >= 1024)
	PropCatalog.prepare()
	for name: String in PropCatalog.SOURCES:
		var m := PropCatalog.mesh(name)
		_check("prop mesh", m != null and m.get_surface_count() > 0, name)
	var lib := AnimLib.get_library()
	for clip in AnimLib.CLIPS:
		_check("animation clip", lib.has_animation(clip), clip)
	for p in ["res://assets/models/sketchfab/generic_cars/scene.gltf", "res://assets/models/sketchfab/pistol/scene.gltf",
			"res://assets/models/sketchfab/fan_palm/scene.gltf", "res://assets/textures/polyhaven/asphalt_02/albedo.jpg",
			"res://assets/fonts/Oswald-SemiBold.ttf"]:
		_check("asset loads", load(p) != null, p)
	print("ASSET CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


static func _snake(name: String) -> String:
	var base := name.get_basename()
	var out := ""
	for ch in base:
		out += ch if ch.is_valid_identifier() or ch.is_valid_int() else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_").to_lower() + ".fbx"
