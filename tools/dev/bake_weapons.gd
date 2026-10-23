extends Node
## Bakes the weapon glTFs into normalized static scenes: skinned meshes baked to their pose, barrel along -Z, top
## along +Y, real-world length, origin at the firing grip, with Marker3D children "Muzzle" and "Support" (the
## other hand). Run with a renderer (skin baking needs one):
##   xvfb-run -a godot --path . res://tests/runner.tscn -- res://tools/dev/bake_weapons.gd
## Output: assets/models/weapons/<id>.scn (committed; the game only instantiates these).

const SRC := "res://assets/models/sketchfab/%s/scene.gltf"
const OUT := "res://assets/models/weapons/%s.scn"

## id -> source, length (m), muzzle axis in the file, grip and support as [fraction along from the rear,
## fraction of height from the bottom], muzzle height fraction.
const WEAPONS := {
	"smg": {"src": "smg_mp5", "length": 0.66, "axis": "+x", "grip": [0.36, 0.32], "support": [0.6, 0.55], "muzzle_h": 0.72},
	"rifle": {"src": "rifle_m4", "length": 0.86, "axis": "+x", "grip": [0.33, 0.32], "support": [0.6, 0.6], "muzzle_h": 0.7},
	"shotgun": {"src": "shotgun_870", "length": 1.0, "axis": "+x", "grip": [0.2, 0.3], "support": [0.6, 0.62], "muzzle_h": 0.8},
	"sniper": {"src": "sniper_svd", "length": 1.18, "axis": "+x", "grip": [0.24, 0.35], "support": [0.5, 0.55], "muzzle_h": 0.62},
	"launcher": {"src": "launcher_rpg", "length": 0.95, "axis": "+x", "grip": [0.47, 0.18], "support": [0.6, 0.18], "muzzle_h": 0.6},
	"grenade": {"src": "grenade_frag", "length": 0.11, "axis": "+y", "grip": [0.45, 0.5], "support": [0.45, 0.5], "muzzle_h": 0.5},
	"knife": {"src": "knife_combat", "length": 0.3, "axis": "+x", "grip": [0.16, 0.5], "support": [0.16, 0.5], "muzzle_h": 0.5},
	"bat": {"src": "bat_baseball", "length": 0.86, "axis": "-x", "grip": [0.1, 0.5], "support": [0.22, 0.5], "muzzle_h": 0.5},
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/models/weapons"))
	var only: Array = get_meta("args", [])
	for id: String in WEAPONS:
		if not only.is_empty() and not id in only:
			continue
		var cfg: Dictionary = WEAPONS[id]
		var src: Node3D = (load(SRC % cfg.src) as PackedScene).instantiate()
		add_child(src)
		await get_tree().process_frame
		# collect every mesh in world space, skinned ones baked to their current pose
		var parts := []
		for mi: MeshInstance3D in src.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = mi.mesh
			if mi.skin:
				var baked := mi.bake_mesh_from_current_skeleton_pose()
				if baked:
					for s in baked.get_surface_count():
						var m := mi.get_active_material(s)
						baked.surface_set_material(s, m)
					mesh = baked
			else:
				var copy := mesh.duplicate() as Mesh
				for s in copy.get_surface_count():
					copy.surface_set_material(s, mi.get_active_material(s))
				mesh = copy
			parts.append([mesh, mi.global_transform])
		src.queue_free()
		var bb := AABB()
		for i in parts.size():
			var a: AABB = (parts[i][1] as Transform3D) * (parts[i][0] as Mesh).get_aabb()
			bb = a if i == 0 else bb.merge(a)
		# axis: rotate the file's muzzle axis onto -Z, keep +Y up (grenade: its long axis is up already)
		var rot := Basis.IDENTITY
		match String(cfg.axis):
			"+x":
				rot = Basis(Vector3.UP, PI * 0.5)
			"-x":
				rot = Basis(Vector3.UP, -PI * 0.5)
		var long_len: float = bb.size.y if cfg.axis == "+y" else bb.size.x
		var k: float = cfg.length / long_len
		var norm := Transform3D(rot.scaled(Vector3.ONE * k), Vector3.ZERO)
		var nb := AABB()
		for i in parts.size():
			var a: AABB = (norm * (parts[i][1] as Transform3D)) * (parts[i][0] as Mesh).get_aabb()
			nb = a if i == 0 else nb.merge(a)
		# rear = +Z end, front (muzzle) = -Z end
		var at := func(f: Array) -> Vector3:
			return Vector3(nb.get_center().x, nb.position.y + nb.size.y * float(f[1]), nb.end.z - nb.size.z * float(f[0]))
		var grip: Vector3 = at.call(cfg.grip)
		var root := Node3D.new()
		root.name = id
		for i in parts.size():
			var mi := MeshInstance3D.new()
			mi.name = "Part%d" % i
			mi.mesh = parts[i][0]
			mi.transform = Transform3D(Basis.IDENTITY, -grip) * norm * (parts[i][1] as Transform3D)
			root.add_child(mi)
			mi.owner = root
		var muzzle := Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = Vector3(nb.get_center().x, nb.position.y + nb.size.y * float(cfg.muzzle_h), nb.position.z) - grip
		root.add_child(muzzle)
		muzzle.owner = root
		var support := Marker3D.new()
		support.name = "Support"
		support.position = (at.call(cfg.support) as Vector3) - grip
		root.add_child(support)
		support.owner = root
		var ps := PackedScene.new()
		ps.pack(root)
		var err := ResourceSaver.save(ps, OUT % id, ResourceSaver.FLAG_COMPRESS)
		print("baked %s: %d parts, size %s, err %d" % [id, parts.size(), nb.size.snapped(Vector3.ONE * 0.01), err])
		root.free()
	get_tree().quit()
