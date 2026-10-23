class_name EmergencyServices
extends Node
## Calls the ambulance and the fire brigade. Someone lying dead or hurt in the street brings an ambulance
## (siren, through red lights); a paramedic gets out, kneels over them and brings them round. A burning car
## brings a fire engine; a firefighter sprays the flames out. Afterwards they drive on as normal traffic.
## Units come only while the player is around (they are part of the streamed traffic).

const SCAN := 2.0
const DELAY := 12.0      # seconds after an incident before the call goes out

var traffic: TrafficManager
var _t := 0.0
var _incidents := {}     # target node (Pedestrian / Vehicle) -> seconds known
var _jobs: Array = []    # {kind, unit: TrafficCar, target: Node3D, crew: Pedestrian, t, phase}


func _physics_process(delta: float) -> void:
	if traffic == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = SCAN
		_scan()
	for i in range(_jobs.size() - 1, -1, -1):
		if not _run_job(_jobs[i], delta):
			_jobs.remove_at(i)


func _busy(kind: String) -> bool:
	return _jobs.any(func(j): return j.kind == kind)


func _scan() -> void:
	var p := Game.player as Node3D
	if p == null:
		return
	for n: Node in get_tree().get_nodes_in_group("pedestrians"):
		var ped := n as Pedestrian
		if ped.state == Pedestrian.State.DEAD and not ped.has_meta("attended") and ped.global_position.distance_to(p.global_position) < 120.0:
			_incidents[ped] = float(_incidents.get(ped, 0.0)) + SCAN
	for n: Node in get_tree().get_nodes_in_group("vehicles"):
		var v := n as Vehicle
		if v and v.damage and v.damage.burning() and not v.has_meta("attended") and v.global_position.distance_to(p.global_position) < 140.0:
			_incidents[v] = float(_incidents.get(v, 0.0)) + SCAN
	for k in _incidents.keys():
		if not is_instance_valid(k):
			_incidents.erase(k)
			continue
		if float(_incidents[k]) < DELAY:
			continue
		var kind := "ambulance" if k is Pedestrian else "firetruck"
		if _busy(kind):
			continue
		var node := k as Node3D
		var unit := traffic.dispatch(kind, node.global_position)
		if unit:
			node.set_meta("attended", true)
			_incidents.erase(k)
			_jobs.append({"kind": kind, "unit": unit, "target": node, "crew": null, "t": 0.0, "phase": 0})


## Returns false when the job is over.
func _run_job(j: Dictionary, delta: float) -> bool:
	var unit: TrafficManager.TrafficCar = j.unit
	j.t += delta
	if not is_instance_valid(unit.v) or not is_instance_valid(j.target) or j.t > 120.0 or not traffic.cars.has(unit):
		print_verbose("EMS job %s ended: unit %s target %s t %.0f" % [j.kind, is_instance_valid(unit.v), is_instance_valid(j.target), j.t])
		if is_instance_valid(j.crew):
			j.crew.queue_free()
		if is_instance_valid(unit.v):
			traffic.stand_down(unit)
		return false
	var target: Node3D = j.target
	match int(j.phase):
		0:  # on the way
			if unit.arrived:
				j.phase = 1
				j.t = 0.0
				var crew := Pedestrian.new()
				crew.character_file = Population.CHARACTERS.keys()[randi() % Population.CHARACTERS.size()]
				crew.female = Population.CHARACTERS[crew.character_file]
				crew.stay_put = true
				get_parent().add_child(crew)
				var side := unit.v.global_basis.x * (1.4 + unit.v._bounds.size.x * 0.5)
				crew.global_position = unit.v.global_position + side + Vector3(0, 0.2, 0)
				crew.goal = _spot(target)
				crew.state = Pedestrian.State.WALK
				crew.remove_from_group("pedestrians")  # not part of the crowd logic
				j.crew = crew
		1:  # crew walks over
			var crew: Pedestrian = j.crew
			if not is_instance_valid(crew) or not crew.is_alive():
				traffic.stand_down(unit)
				return false
			crew.goal = _spot(target)
			if crew.state == Pedestrian.State.IDLE or crew.global_position.distance_to(crew.goal) < 0.8 or j.t > 25.0:
				var to := target.global_position - crew.global_position
				crew.rotation.y = atan2(-to.x, -to.z)
				crew.state = Pedestrian.State.ACT
				crew.act_time = 9999.0
				crew.visual.play_loop("kneel" if j.kind == "ambulance" else "idle")
				if j.kind == "firetruck":
					j.spray = _make_spray(crew, target)
				j.phase = 2
				j.t = 0.0
		2:  # working on it
			if j.t > (8.0 if j.kind == "ambulance" else 6.0):
				if j.kind == "ambulance" and target is Pedestrian:
					(target as Pedestrian).revive()
				elif target is Vehicle:
					(target as Vehicle).damage.extinguish()
				if j.has("spray") and is_instance_valid(j.spray):
					j.spray.queue_free()
				var crew: Pedestrian = j.crew
				crew.visual.travel("ground")
				crew.goal = unit.v.global_position + unit.v.global_basis.x * 1.6
				crew.state = Pedestrian.State.WALK
				j.phase = 3
				j.t = 0.0
		3:  # back in and away
			var crew: Pedestrian = j.crew
			if not is_instance_valid(crew) or crew.global_position.distance_to(unit.v.global_position) < 2.8 or j.t > 15.0:
				if is_instance_valid(crew):
					crew.queue_free()
				traffic.stand_down(unit)
				return false
	return true


## Where the crew stands: beside the body, or a couple of metres off the burning car.
func _spot(target: Node3D) -> Vector3:
	var at := target.global_position
	if target is Pedestrian:
		at = (target as Pedestrian).ragdoll.hips_transform().origin
		return Vector3(at.x + 0.7, at.y, at.z)
	var p := Game.player as Node3D
	var away := (p.global_position - at) if p else Vector3.FORWARD
	away.y = 0.0
	return at + away.normalized() * 4.0


func _make_spray(crew: Pedestrian, target: Node3D) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.amount = 60
	e.lifetime = 0.8
	var pm := ParticleProcessMaterial.new()
	var to := (target.global_position + Vector3(0, 0.8, 0)) - (crew.global_position + Vector3(0, 1.2, 0))
	pm.direction = to.normalized()
	pm.spread = 6.0
	pm.initial_velocity_min = to.length() * 1.1
	pm.initial_velocity_max = to.length() * 1.4
	pm.gravity = Vector3(0, -6, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	pm.color = Color(0.85, 0.9, 1.0, 0.55)
	e.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	q.material = VehicleDamage._billboard(false)
	e.draw_pass_1 = q
	e.local_coords = false
	e.visibility_aabb = AABB(Vector3(-10, -5, -10), Vector3(20, 10, 20))
	crew.add_child(e)
	e.position = Vector3(0, 1.2, -0.4)
	e.emitting = true
	return e
