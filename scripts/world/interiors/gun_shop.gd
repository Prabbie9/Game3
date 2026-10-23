class_name GunShop
extends Node3D
## The downtown gun shop across the street from the start: a one-storey brick store you walk into, with shop
## windows, a counter with a clerk behind it, weapons racked on the back wall and ammo on the side shelves.
## Step up to the counter and press interact to browse (ShopMenu). Unbranded: the sign just says GUNS & AMMO.
## Built in world space on the lot WorldData.RESERVED[0] keeps free of city buildings.

## Footprint (world x0, z0, x1, z1): door in the z1 (street) wall.
const X0 := 14.0
const X1 := 32.0
const Z0 := -24.0
const Z1 := -12.0
const H := 4.2
const T := 0.3
const DOOR := [22.0, 24.2]
const WINDOWS := [[15.6, 20.6], [25.6, 30.6]]
const WIN_Y := [0.9, 2.9]
const COUNTER_Z := -19.0

var clerk: Pedestrian
var _base := CityCell.CURB_H
var _preview: Node3D
var _preview_id := ""
var _clerk_gone_t := 0.0
var _spawned_once := false
var _body: StaticBody3D


func _ready() -> void:
	add_to_group("interactables")
	var city: City = Game.world.city if Game.world else null
	var b := MeshBatch.new()
	var y0 := _base
	var y1 := _base + H
	# floor, ceiling, roof
	b.flat("floor", X0 + T, Z0 + T, X1 - T, Z1 - T, y0 + 0.02)
	b.quad("ceiling", Vector3(X0, y1 - 0.3, Z0), Vector3(X1, y1 - 0.3, Z0), Vector3(X1, y1 - 0.3, Z1), Vector3(X0, y1 - 0.3, Z1),
		Vector2(X0, Z0), Vector2(X1, Z0), Vector2(X1, Z1), Vector2(X0, Z1))
	b.box("roof", Vector3((X0 + X1) * 0.5, y1 - 0.12, (Z0 + Z1) * 0.5), Vector3(X1 - X0 + 0.4, 0.24, Z1 - Z0 + 0.4))
	b.box("trim", Vector3((X0 + X1) * 0.5, y1 + 0.25, Z1 + 0.05), Vector3(X1 - X0 + 0.5, 0.5, T + 0.2))
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	add_child(_body)
	_shape(Vector3((X0 + X1) * 0.5, y1 - 0.12, (Z0 + Z1) * 0.5), Vector3(X1 - X0, 0.24, Z1 - Z0))
	# back and side walls (brick outside, plaster inside)
	_solid_wall(Vector3(X0, y0, Z0), Vector3(X1, y0, Z0), false)
	_solid_wall(Vector3(X0, y0, Z1), Vector3(X0, y0, Z0), false)
	_solid_wall(Vector3(X1, y0, Z0), Vector3(X1, y0, Z1), false)
	# street wall: pieces around the door and the two shop windows
	var xs := [X0, WINDOWS[0][0], WINDOWS[0][1], DOOR[0], DOOR[1], WINDOWS[1][0], WINDOWS[1][1], X1]
	for i in xs.size() - 1:
		var a: float = xs[i]
		var c: float = xs[i + 1]
		var mid := Vector3((a + c) * 0.5, 0, Z1)
		var w := c - a
		match i:
			1, 5:  # window: wall below and above, glass between
				_wall_piece(b, mid, w, 0.0, WIN_Y[0])
				_wall_piece(b, mid, w, WIN_Y[1], H)
				_glass(Vector3(mid.x, y0 + (WIN_Y[0] + WIN_Y[1]) * 0.5, Z1), Vector3(w, WIN_Y[1] - WIN_Y[0], 0.04))
			3:  # door: lintel only
				_wall_piece(b, mid, w, 2.6, H)
			_:
				_wall_piece(b, mid, w, 0.0, H)
	# counter with a dark top; display case on it
	var cz := COUNTER_Z
	b.box("counter", Vector3(23.0, y0 + 0.45, cz), Vector3(12.0, 0.9, 0.7))
	b.box("counter_top", Vector3(23.0, y0 + 0.92, cz), Vector3(12.2, 0.04, 0.8))
	_shape(Vector3(23.0, y0 + 0.5, cz), Vector3(12.0, 1.0, 0.7))
	_glass(Vector3(20.0, y0 + 1.12, cz), Vector3(3.0, 0.36, 0.6), false)
	# side shelves with ammo boxes
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for side: float in [X0 + T + 0.3, X1 - T - 0.3]:
		b.box("shelf", Vector3(side, y0 + 1.1, -15.5), Vector3(0.5, 2.2, 5.0))
		_shape(Vector3(side, y0 + 1.1, -15.5), Vector3(0.5, 2.2, 5.0))
		for lvl in 4:
			var sy := y0 + 0.35 + lvl * 0.5
			var z := -17.7
			while z < -13.4:
				var bw := rng.randf_range(0.18, 0.32)
				b.color = [Color(0.55, 0.12, 0.1), Color(0.18, 0.3, 0.16), Color(0.75, 0.6, 0.2), Color(0.15, 0.2, 0.35)][rng.randi() % 4]
				b.box("boxes", Vector3(side + (0.05 if side < 23.0 else -0.05), sy + 0.11, z + bw * 0.5), Vector3(0.3, 0.22, bw - 0.02))
				z += bw
		b.color = Color.WHITE
	# back wall pegboard
	b.box("pegboard", Vector3(23.0, y0 + 2.0, Z0 + T * 0.5 + 0.03), Vector3(12.0, 2.4, 0.04))
	# ceiling light panels
	for lx: float in [18.0, 23.0, 28.0]:
		for lz: float in [-15.0, -21.0]:
			b.box("light_panel", Vector3(lx, y1 - 0.32, lz), Vector3(1.2, 0.04, 0.3))
	# sign board over the door
	b.box("sign", Vector3(23.0, y0 + 3.35, Z1 + 0.22), Vector3(7.0, 0.9, 0.12))
	var arrays := b.commit()
	var mats := {}
	for key: String in arrays:
		mats[key] = _material(city, key)
	var mi := MeshInstance3D.new()
	var am := ArrayMesh.new()
	for key: String in arrays:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays[key], [], {}, City.MESH_FLAGS)
		am.surface_set_material(am.get_surface_count() - 1, mats[key])
	mi.mesh = am
	add_child(mi)
	_sign()
	_lights()
	_rack()
	_spawn_clerk()


func _material(city: City, key: String) -> Material:
	match key:
		"floor":
			return city._pbr("wood_floor_deck", 1.6, Color(0.62, 0.5, 0.4)) if city else StandardMaterial3D.new()
		"ext":
			return city._pbr("brick_wall_09", 2.2, Color(0.85, 0.72, 0.62)) if city else StandardMaterial3D.new()
		"int":
			return city._pbr("plastered_wall_02", 2.5, Color(0.92, 0.9, 0.84)) if city else StandardMaterial3D.new()
		"roof":
			return city._pbr("concrete_pavement", 2.0, Color(0.6, 0.6, 0.6)) if city else StandardMaterial3D.new()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = key == "boxes"
	match key:
		"ceiling":
			m.albedo_color = Color(0.86, 0.86, 0.84)
		"trim":
			m.albedo_color = Color(0.12, 0.13, 0.14)
			m.roughness = 0.5
		"counter":
			m.albedo_color = Color(0.32, 0.22, 0.15)
			m.roughness = 0.6
		"counter_top":
			m.albedo_color = Color(0.08, 0.08, 0.09)
			m.roughness = 0.25
		"shelf":
			m.albedo_color = Color(0.4, 0.4, 0.42)
			m.metallic = 0.6
			m.roughness = 0.45
		"boxes":
			m.roughness = 0.8
		"pegboard":
			m.albedo_color = Color(0.55, 0.45, 0.34)
			m.roughness = 0.9
		"light_panel":
			m.albedo_color = Color(1, 1, 1)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.97, 0.9)
			m.emission_energy_multiplier = 3.0
		"sign":
			m.albedo_color = Color(0.07, 0.07, 0.08)
			m.roughness = 0.4
	return m


## A full-height wall from a to b (seen from outside, left to right): brick outside, plaster inside, collision.
func _solid_wall(a: Vector3, c: Vector3, _unused: bool) -> void:
	var b := MeshBatch.new()
	var d := (c - a).normalized()
	var n := Vector3(d.z, 0, -d.x)  # outward
	b.wall("ext", a + n * T * 0.5, c + n * T * 0.5, H)
	b.wall("int", c - n * T * 0.5, a - n * T * 0.5, H - 0.3)
	_add_batch(b)
	var mid := (a + c) * 0.5
	_shape(mid + Vector3(0, H * 0.5, 0), Vector3(absf(c.x - a.x) + (T if absf(d.z) > 0.5 else 0.0), H, absf(c.z - a.z) + (T if absf(d.x) > 0.5 else 0.0)))


## Street-wall piece between heights h0..h1 (metres above the floor) centred on mid (x, -, Z1), width w.
func _wall_piece(_b: MeshBatch, mid: Vector3, w: float, h0: float, h1: float) -> void:
	var b := MeshBatch.new()
	var y := _base + h0
	var a := Vector3(mid.x - w * 0.5, y, Z1)
	var c := Vector3(mid.x + w * 0.5, y, Z1)
	b.wall("ext", a + Vector3(0, 0, T * 0.5), c + Vector3(0, 0, T * 0.5), h1 - h0, h0)
	b.wall("int", c - Vector3(0, 0, T * 0.5), a - Vector3(0, 0, T * 0.5), minf(h1, H - 0.3) - h0, h0)
	# reveals (the thickness at openings)
	if h0 > 0.0:
		b.quad("ext", Vector3(a.x, y, Z1 + T * 0.5), Vector3(c.x, y, Z1 + T * 0.5), Vector3(c.x, y, Z1 - T * 0.5), Vector3(a.x, y, Z1 - T * 0.5),
			Vector2(0, 0), Vector2(w, 0), Vector2(w, T), Vector2(0, T))
	if h1 < H:
		var yt := _base + h1
		b.quad("ext", Vector3(a.x, yt, Z1 - T * 0.5), Vector3(c.x, yt, Z1 - T * 0.5), Vector3(c.x, yt, Z1 + T * 0.5), Vector3(a.x, yt, Z1 + T * 0.5),
			Vector2(0, 0), Vector2(w, 0), Vector2(w, T), Vector2(0, T))
	_add_batch(b)
	_shape(Vector3(mid.x, _base + (h0 + h1) * 0.5, Z1), Vector3(w, h1 - h0, T))


func _add_batch(b: MeshBatch) -> void:
	var city: City = Game.world.city if Game.world else null
	var arrays := b.commit()
	var am := ArrayMesh.new()
	for key: String in arrays:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays[key], [], {}, City.MESH_FLAGS)
		am.surface_set_material(am.get_surface_count() - 1, _material(city, key))
	var mi := MeshInstance3D.new()
	mi.mesh = am
	add_child(mi)


func _shape(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	cs.position = c
	_body.add_child(cs)


static var _glass_mat: StandardMaterial3D


func _glass(c: Vector3, s: Vector3, solid := true) -> void:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.albedo_color = Color(0.7, 0.82, 0.86, 0.18)
		_glass_mat.roughness = 0.05
		_glass_mat.metallic = 0.4
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = _glass_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = c
	add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.set_meta("surface", FX.Surface.GLASS)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s
		cs.shape = bs
		sb.add_child(cs)
		sb.position = c
		add_child(sb)


func _sign() -> void:
	var l := Label3D.new()
	l.text = "GUNS  &  AMMO"
	l.font = UITheme.heading
	l.font_size = 160
	l.pixel_size = 0.004
	l.modulate = Color(1.0, 0.32, 0.22)
	l.outline_size = 0
	l.shaded = false
	l.position = Vector3(23.0, _base + 3.35, Z1 + 0.29)
	add_child(l)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.35, 0.25)
	glow.light_energy = 0.8
	glow.omni_range = 4.0
	glow.position = Vector3(23.0, _base + 3.1, Z1 + 1.0)
	add_child(glow)
	var open := Label3D.new()
	open.text = "OPEN"
	open.font = UITheme.heading
	open.font_size = 96
	open.pixel_size = 0.004
	open.modulate = Color(0.4, 1.0, 0.55)
	open.shaded = false
	open.position = Vector3(18.1, _base + 2.3, Z1 - 0.05)
	add_child(open)


func _lights() -> void:
	for lx: float in [18.0, 28.0]:
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.96, 0.88)
		o.light_energy = 1.6
		o.omni_range = 9.0
		o.position = Vector3(lx, _base + H - 0.6, -18.0)
		o.distance_fade_enabled = true
		o.distance_fade_begin = 60.0
		o.distance_fade_length = 20.0
		add_child(o)


## The back wall: every gun on hooks, side on, barrels pointing right.
func _rack() -> void:
	var ids := ["pistol", "smg", "shotgun", "rifle", "sniper", "launcher", "knife", "bat"]
	var spots := [[18.0, 2.75], [21.5, 2.75], [25.5, 2.75], [29.0, 2.75], [19.0, 1.75], [23.0, 1.75], [26.4, 1.75], [28.8, 1.75]]
	for i in ids.size():
		var m := _model(ids[i])
		add_child(m)
		var p: Array = spots[i]
		m.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(p[0], _base + p[1], Z0 + T * 0.5 + 0.09))


func _model(id: String) -> Node3D:
	if id == "pistol":
		return WeaponModel.build("pistol")[0]
	return (load("res://assets/models/weapons/%s.scn" % id) as PackedScene).instantiate()


func _spawn_clerk() -> void:
	if not NPCDriver.is_ready("ch21_nonpbr"):
		return
	clerk = Pedestrian.new()
	clerk.character_file = "ch21_nonpbr"
	clerk.stay_put = true
	add_child(clerk)
	clerk.global_position = Vector3(23.0, _base + 0.02, COUNTER_Z - 1.0)
	clerk.rotation.y = 0.0
	_clerk_gone_t = 0.0
	_spawned_once = true


func _physics_process(delta: float) -> void:
	if clerk == null and not _spawned_once:
		_spawn_clerk()
	# a clerk who was killed (or ran off) is replaced once the player has left the area
	elif clerk == null or not is_instance_valid(clerk) or not clerk.is_alive():
		_clerk_gone_t += delta
		var p := Game.player as Node3D
		if _clerk_gone_t > 30.0 and p and p.global_position.distance_to(Vector3(23, 0, -18)) > 80.0:
			if clerk and is_instance_valid(clerk):
				clerk.queue_free()
			clerk = null
			_spawn_clerk()
	if _preview:
		_preview.rotate_y(delta * 0.8)


func is_open() -> bool:
	return clerk != null and is_instance_valid(clerk) and clerk.is_alive() and clerk.state != Pedestrian.State.FLEE


# --- interactable ------------------------------------------------------------

func interact_point() -> Vector3:
	return Vector3(23.0, _base, COUNTER_Z + 1.2)


func interact_range() -> float:
	return 3.2


func interact_prompt(_p: Node) -> String:
	return "Browse weapons" if is_open() else ""


func interact(p: Node) -> void:
	if not is_open():
		return
	var menu := ShopMenu.new()
	menu.shop = self
	Game.world.add_child(menu)
	menu.open(p as Player)


## Show the weapon being browsed on the counter, turning slowly.
func preview(id: String) -> void:
	if id == _preview_id:
		return
	_preview_id = id
	if _preview:
		_preview.queue_free()
		_preview = null
	if id == "" or id == "armor":
		return
	_preview = Node3D.new()
	add_child(_preview)
	_preview.position = Vector3(23.0, _base + 1.25, COUNTER_Z)
	var m := _model(id)
	_preview.add_child(m)
	# centre the model over the turntable
	m.position = Vector3(0, 0, 0.25 if id != "grenade" else 0.0)
