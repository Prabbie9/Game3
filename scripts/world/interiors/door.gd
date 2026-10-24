class_name Door
extends Node3D
## A hinged door (hinge at this node, the leaf runs along +X, opening inwards to -Z): swings open when the player
## or anyone else comes within reach and closes again behind them.

@export var width := 1.3
@export var height := 2.4
@export var color := Color(0.18, 0.2, 0.22)
@export var flip := false   # the leaf runs along -X instead (the right-hand leaf of a pair)

const OPEN := deg_to_rad(95.0)
const REACH := 2.2
var _leaf: AnimatableBody3D
var _angle := 0.0
var _open := false
var _close_t := 0.0
static var _mat: StandardMaterial3D
static var _glass: StandardMaterial3D


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = color
		_mat.roughness = 0.45
		_mat.metallic = 0.5
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.7, 0.82, 0.86, 0.25)
		_glass.roughness = 0.05
	_leaf = AnimatableBody3D.new()
	_leaf.collision_layer = 1
	_leaf.sync_to_physics = true
	add_child(_leaf)
	# frame (top, bottom, sides) and a glass panel; handle on the far side
	var w := width
	for part: Array in [[Vector3(w * 0.5, 0.06, 0), Vector3(w, 0.12, 0.05)], [Vector3(w * 0.5, height - 0.06, 0), Vector3(w, 0.12, 0.05)],
			[Vector3(0.06, height * 0.5, 0), Vector3(0.12, height, 0.05)], [Vector3(w - 0.06, height * 0.5, 0), Vector3(0.12, height, 0.05)],
			[Vector3(w * 0.5, 1.0, 0), Vector3(w, 0.12, 0.05)]]:
		_box(part[0], part[1], _mat)
	_box(Vector3(w * 0.5, (height + 1.0) * 0.5, 0), Vector3(w - 0.2, height - 1.2, 0.02), _glass)
	_box(Vector3(w * 0.5, 0.55, 0), Vector3(w - 0.2, 0.86, 0.03), _mat)
	_box(Vector3(w - 0.16, 1.0, 0.06), Vector3(0.04, 0.3, 0.04), _mat)
	_box(Vector3(w - 0.16, 1.0, -0.06), Vector3(0.04, 0.3, 0.04), _mat)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, height, 0.06)
	cs.shape = bs
	cs.position = Vector3(w * (-0.5 if flip else 0.5), height * 0.5, 0)
	_leaf.add_child(cs)


func _box(p: Vector3, s: Vector3, m: Material) -> void:
	if flip:
		p.x = -p.x
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	_leaf.add_child(mi)


func _near() -> bool:
	var mid := global_transform * Vector3(width * (-0.5 if flip else 0.5), 1.0, 0)
	var p := Game.player as Node3D
	if p and p.global_position.distance_to(mid) < REACH:
		return true
	for n: Node in get_tree().get_nodes_in_group("pedestrians"):
		if (n as Node3D).global_position.distance_to(mid) < REACH * 0.8:
			return true
	return false


func _physics_process(delta: float) -> void:
	var want := _near()
	if want:
		_close_t = 1.2
	else:
		_close_t -= delta
	var open := want or _close_t > 0.0
	if open != _open:
		_open = open
		Audio.play_at(Audio.stream("vehicles/door_open.ogg" if open else "vehicles/door_close.ogg"), global_transform * Vector3(width * (-0.5 if flip else 0.5), 1.2, 0), -10.0, 0.75)
	_angle = move_toward(_angle, OPEN if _open else 0.0, delta * 3.0)
	_leaf.transform = Transform3D(Basis(Vector3.UP, -_angle if flip else _angle), Vector3.ZERO)   # swings to -Z (inwards)
