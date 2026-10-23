class_name TrafficLights
extends Node3D
## Signal heads on poles at every signalled junction near the player, one per approach on the right-hand kerb
## before the stop line, showing the LaneGraph phase (red / amber / green). Built procedurally; poles and
## heads near the player only (streamed with a 220 m radius).

const RADIUS := 220.0

var traffic: TrafficManager
var _active := {}         # node -> [[head MeshInstance3D, group], ...]
var _scan := 0.0
var _mats := {}
var _pole_mesh: Mesh
var _head_mesh: ArrayMesh
var _lamps := {}          # "r0"/"r1"/... -> material


func setup(t: TrafficManager) -> void:
	traffic = t
	_build_meshes()


func _build_meshes() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.17, 0.17)
	metal.metallic = 0.6
	metal.roughness = 0.45
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.08
	cyl.height = 3.4
	cyl.radial_segments = 10
	cyl.material = metal
	_pole_mesh = cyl
	# housing + three lens discs; surface 1..3 = red, amber, green (materials swapped per state)
	_head_mesh = ArrayMesh.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.98, 0.26)
	_head_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	_head_mesh.surface_set_material(0, metal)
	for i in 3:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.11
		disc.bottom_radius = 0.11
		disc.height = 0.03
		disc.radial_segments = 16
		var arr := disc.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var y := 0.3 - i * 0.3
		for k in v.size():
			# disc axis Y -> Z (facing +Z), placed on the front of the housing
			var p := v[k]
			v[k] = Vector3(p.x, y - p.z, 0.14 + p.y)
			var q := n[k]
			n[k] = Vector3(q.x, -q.z, q.y)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TANGENT] = null
		_head_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var colors := [Color(1.0, 0.12, 0.08), Color(1.0, 0.62, 0.05), Color(0.15, 1.0, 0.45)]
	for i in 3:
		for on in [false, true]:
			var m := StandardMaterial3D.new()
			m.albedo_color = colors[i] * (1.0 if on else 0.18)
			m.roughness = 0.2
			if on:
				m.emission_enabled = true
				m.emission = colors[i]
				m.emission_energy_multiplier = 5.0
			_lamps["%d%d" % [i, 1 if on else 0]] = m


func _process(delta: float) -> void:
	if traffic == null:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 1.0
		_stream()
	for node: int in _active:
		for h: Array in _active[node]:
			var st := traffic.graph.signal_state(node, int(h[1]), traffic.clock)
			var mi: MeshInstance3D = h[0]
			if int(mi.get_meta("st", -1)) == st:
				continue
			mi.set_meta("st", st)
			# lamp index 0 red, 1 amber, 2 green; state 0 green, 1 amber, 2 red
			var lit := 2 - st
			for i in 3:
				mi.set_surface_override_material(i + 1, _lamps["%d%d" % [i, 1 if i == lit else 0]])


func _stream() -> void:
	var p := Game.player as Node3D
	if p == null:
		return
	var focus := p.global_position
	var net := (get_parent().get_parent() as World).city.net if get_parent() and get_parent().get_parent() is World else null
	if net == null:
		return
	var want := {}
	for node: int in traffic.graph.signals:
		if net.node_pos(node).distance_to(focus) < RADIUS:
			want[node] = true
	for node: int in _active.keys():
		if not want.has(node):
			for h: Array in _active[node]:
				(h[0] as Node).get_parent().queue_free()
			_active.erase(node)
	for node: int in want:
		if not _active.has(node):
			_active[node] = _build_node(net, node)


func _build_node(net: RoadNet, node: int) -> Array:
	var heads := []
	var sig: Dictionary = traffic.graph.signals[node]
	var data := WorldData.get_data()
	for e: Dictionary in net.ends[node]:
		var key := Vector2i(e.road, e.end)
		if not sig.groups.has(key):
			continue
		var w: float = data.roads[e.road].w
		var t: float = net.trim[key]
		var d: Vector2 = e.dir
		var travel := -d                       # cars arrive travelling against the end direction
		var right := Vector2(-travel.y, travel.x)
		var base := net.along_from_node(e, t + 1.2)
		var pos := base + Vector3(right.x, 0, right.y) * (w * 0.5 + 0.7)
		pos.y += CityCell.CURB_H
		var pole := MeshInstance3D.new()
		pole.mesh = _pole_mesh
		add_child(pole)
		pole.global_position = pos + Vector3(0, 1.7, 0)
		var head := MeshInstance3D.new()
		head.mesh = _head_mesh
		pole.add_child(head)
		# face the oncoming cars (looking along the end direction, away from the junction)
		head.global_basis = Basis.looking_at(-Vector3(d.x, 0, d.y), Vector3.UP)
		head.global_position = pos + Vector3(0, 3.05, 0) + Vector3(d.x, 0, d.y) * 0.16
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		heads.append([head, int(sig.groups[key])])
	return heads
