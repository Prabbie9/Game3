class_name Collectibles
extends Node3D
## Thirty hidden lucky coins around the island: in the parks and the plaza, on the pier and the boardwalk, by the
## lifeguard towers, in the port, behind houses in the hills and suburbs, at the lookout. $100 each, and a bonus
## for the full set. Found ones are kept in Game.collected (saved with the game).

const COUNT := 30
const REWARD := 100
const BONUS := 10000
## lot kind -> how many coins go in lots of that kind
const PLAN := {"park": 3, "plaza": 1, "pier": 1, "lookout": 1, "lifeguard": 4, "boardwalk": 3, "crane": 2,
	"container_yard": 2, "port_sheds": 2, "parking": 2, "mansion": 2, "industrial": 3, "house": 3, "beachfront": 1}

var spots: Array[Vector3] = []
var _coins := {}   # id -> Node3D
static var _mesh: Mesh
static var _mat: StandardMaterial3D


func _ready() -> void:
	_plan()
	refresh()


## Coins not yet found are out in the world; found ones are gone (after loading a save).
func refresh() -> void:
	for i in spots.size():
		var found := Game.collected.has(i)
		if found and _coins.has(i):
			(_coins[i] as Node).queue_free()
			_coins.erase(i)
		elif not found and not _coins.has(i):
			_make(i)


## Deterministic spots from the baked layout: a corner of a lot (yards and margins, not inside buildings).
func _plan() -> void:
	var data := WorldData.get_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7071
	for kind: String in PLAN:
		var lots: Array = data.lots.filter(func(l): return l.kind == kind)
		for k in mini(int(PLAN[kind]), lots.size()):
			var l: Dictionary = lots[rng.randi() % lots.size()]
			lots.erase(l)
			var x0 := float(l.x0)
			var z0 := float(l.z0)
			var x1 := float(l.x1)
			var z1 := float(l.z1)
			var p: Vector3
			if kind in ["park", "plaza", "pier", "lookout", "lifeguard", "boardwalk", "crane", "parking"]:
				p = Vector3(lerpf(x0, x1, rng.randf_range(0.3, 0.7)), 0, lerpf(z0, z1, rng.randf_range(0.3, 0.7)))
			else:
				var cx := x0 + 2.0 if rng.randf() < 0.5 else x1 - 2.0
				var cz := z0 + 2.0 if rng.randf() < 0.5 else z1 - 2.0
				p = Vector3(cx, 0, cz)
			if kind == "plaza":
				p = Vector3(lerpf(x0, x1, 0.15), 0, lerpf(z0, z1, 0.15))   # by the corner, not in the pool
			if kind == "lookout":
				p = data.lookout + Vector3(3.0, 0, 2.0)
			spots.append(p)
	while spots.size() > COUNT:
		spots.pop_back()


func _make(i: int) -> void:
	if _mesh == null:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.22
		cyl.height = 0.05
		cyl.radial_segments = 24
		_mesh = cyl
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(1.0, 0.78, 0.25)
		_mat.metallic = 1.0
		_mat.roughness = 0.25
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.7, 0.2)
		_mat.emission_energy_multiplier = 0.6
	var c := Area3D.new()
	c.collision_layer = 0
	c.collision_mask = 2
	c.monitorable = false
	c.set_meta("id", i)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.9
	cs.shape = sh
	c.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	mi.rotation.x = PI * 0.5
	mi.visibility_range_end = 160.0
	c.add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.4)
	glow.light_energy = 0.6
	glow.omni_range = 2.5
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 40.0
	glow.distance_fade_length = 20.0
	c.add_child(glow)
	add_child(c)
	c.position = spots[i] + Vector3(0, 400.0, 0)   # settled onto the ground when it is loaded
	c.set_meta("settled", false)
	c.body_entered.connect(_on_body.bind(c))
	_coins[i] = c


func _physics_process(delta: float) -> void:
	var p := Game.player as Node3D
	if p == null:
		return
	var city := (Game.world as World).city if Game.world else null
	for i: int in _coins:
		var c: Node3D = _coins[i]
		if not is_instance_valid(c):
			continue
		if not c.get_meta("settled") and city and Vector2(c.position.x - p.global_position.x, c.position.z - p.global_position.z).length() < 150.0:
			_settle(c, city)
		(c.get_child(1) as Node3D).rotation.y += delta * 2.0



## Puts a coin on the ground at its spot, or close by if something (a bench, a planter, a wall) stands there.
func _settle(c: Node3D, city: City) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.45
	q.shape = ball
	q.collision_mask = 1 | 16
	for r: float in [0.0, 1.5, 3.0, 4.5]:
		for k in (1 if r == 0.0 else 8):
			var x := c.position.x + cos(k * TAU / 8.0) * r
			var z := c.position.z + sin(k * TAU / 8.0) * r
			var y := city.ground_y(x, z)
			if is_nan(y):
				return
			q.transform = Transform3D(Basis(), Vector3(x, y + 0.75, z))
			if space.intersect_shape(q, 1).is_empty():
				c.position = Vector3(x, y + 0.8, z)
				c.set_meta("settled", true)
				return
	c.position.y = city.ground_y(c.position.x, c.position.z) + 0.8
	c.set_meta("settled", true)

func _on_body(body: Node, c: Area3D) -> void:
	if body != Game.player:
		return
	var id: int = c.get_meta("id")
	if Game.collected.has(id):
		return
	Game.collected.append(id)
	Game.money += REWARD
	Audio.play_at(Audio.stream("world/coins.ogg"), c.global_position, 0.0, 1.2)
	var n := Game.collected.size()
	if n >= COUNT:
		Game.money += BONUS
		Game.message("Lucky coin %d of %d! That's all of them: $%d bonus." % [n, COUNT, BONUS])
	else:
		Game.message("Lucky coin %d of %d found. +$%d" % [n, COUNT, REWARD])
	_coins.erase(id)
	c.queue_free()
