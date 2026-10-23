class_name Ocean
extends Node3D
## The sea around Port Solano: a wave grid that follows the camera in whole grid steps (so waves stay put in
## the world) plus a flat apron to the horizon, and a WaterVolume so the player can swim anywhere offshore.

const GRID := 200      # quads per side of the wave grid
const CELL := 6.0      # metres per quad
const APRON := 9000.0

var level := -2.0
var _grid: MeshInstance3D
var _apron: MeshInstance3D
var _mat: ShaderMaterial


func setup(sea_level: float, world_half: float) -> void:
	level = sea_level
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/ocean.gdshader")
	var water_mat := WaterVolume._material()
	_mat.set_shader_parameter("ripple_a", water_mat.get_shader_parameter("ripple_a"))
	_mat.set_shader_parameter("ripple_b", water_mat.get_shader_parameter("ripple_b"))
	var pm := PlaneMesh.new()
	pm.size = Vector2(GRID * CELL, GRID * CELL)
	pm.subdivide_width = GRID - 1
	pm.subdivide_depth = GRID - 1
	_grid = MeshInstance3D.new()
	_grid.name = "WaveGrid"
	_grid.mesh = pm
	_grid.material_override = _mat
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid.extra_cull_margin = 4.0
	add_child(_grid)
	# horizon apron: a big ring around the wave grid (4 quads), slightly lower so it never pokes through
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := GRID * CELL * 0.5 - CELL
	var R := APRON
	for q: Array in [[-R, -R, R, -r], [-R, r, R, R], [-R, -r, -r, r], [r, -r, R, r]]:
		var a := Vector3(q[0], 0, q[1])
		var b := Vector3(q[2], 0, q[1])
		var c := Vector3(q[2], 0, q[3])
		var d := Vector3(q[0], 0, q[3])
		for v in [a, b, d, b, c, d]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	_apron = MeshInstance3D.new()
	_apron.name = "Apron"
	_apron.mesh = st.commit()
	_apron.material_override = _mat
	_apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apron.position.y = -0.15
	add_child(_apron)
	var vol := WaterVolume.new()
	vol.name = "Sea"
	vol.show_surface = false
	vol.size = Vector3(APRON * 2.0, 60.0, APRON * 2.0)
	vol.position = Vector3(0, level - 30.0, 0)
	add_child(vol)
	position.y = level


func follow(cam_pos: Vector3) -> void:
	var gx := snappedf(cam_pos.x, CELL * 2.0)
	var gz := snappedf(cam_pos.z, CELL * 2.0)
	_grid.global_position = Vector3(gx, level, gz)
	_apron.global_position = Vector3(gx, level - 0.15, gz)
