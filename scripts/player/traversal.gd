class_name Traversal
extends RefCounted
## Obstacle analysis for vaulting and climbing. Returns a plan for the player's action system.

const MASK := 1 | 16  # world + props
## Ledges at least this high are climbed with a jump to a braced hang first; lower ones straight from the wall.
const HANG_ABOVE := 1.55
## Lowest/highest climbable ledge, highest vaultable obstacle.
const CLIMB_MIN := 1.0
const CLIMB_MAX := 2.4
const VAULT_MAX := 1.35
## Distance from the action start to the planted hands along the facing (metres), per clip.
const PLANT := {"vault": 1.03, "vault_high": 1.35, "jump_hang": 0.45, "climb": 0.27}


## Looks ahead of a character at `xf` (origin at the feet, facing -Z). Returns {} or
## {"type": "vault"|"climb", "clip": String, "start": Transform3D, "height": float}.
static func analyse(world: World3D, xf: Transform3D, exclude: Array[RID]) -> Dictionary:
	var space := world.direct_space_state
	var fwd := -xf.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var feet := xf.origin
	# 1) something in front at knee and waist height
	var hit := _ray(space, feet + Vector3(0, 0.45, 0), feet + Vector3(0, 0.45, 0) + fwd * 1.3, exclude)
	if hit.is_empty():
		return {}
	var n: Vector3 = hit.normal
	if absf(n.y) > 0.35:
		return {}  # a slope, not a wall
	var wall_dir := -Vector3(n.x, 0, n.z).normalized()
	var wall_pt: Vector3 = hit.position
	# 2) find its top a little way in
	var probe := wall_pt + wall_dir * 0.2
	var top_hit := _ray(space, Vector3(probe.x, feet.y + 2.6, probe.z), Vector3(probe.x, feet.y + 0.2, probe.z), exclude)
	if top_hit.is_empty() or top_hit.normal.y < 0.7:
		return {}
	var height: float = top_hit.position.y - feet.y
	if height < 0.5 or height > CLIMB_MAX:
		return {}
	# 3) headroom on top
	if not _ray(space, top_hit.position + Vector3(0, 0.05, 0), top_hit.position + Vector3(0, 1.75, 0), exclude).is_empty():
		return {}
	var face := Basis.looking_at(wall_dir, Vector3.UP)
	# 4) thin obstacle (fence, barrier, bench) and low enough -> vault; else climb onto it
	var far_probe := wall_pt + wall_dir * 0.85
	var far_top := _ray(space, Vector3(far_probe.x, feet.y + height + 0.3, far_probe.z), Vector3(far_probe.x, feet.y + 0.1, far_probe.z), exclude)
	var thin: bool = far_top.is_empty() or (float(far_top.position.y) - feet.y) < height - 0.3
	if thin and height <= VAULT_MAX:
		# landing zone must be clear at chest height and have ground near our level
		var land := wall_pt + wall_dir * 2.2
		if not _ray(space, wall_pt + wall_dir * 0.4 + Vector3(0, height + 0.4, 0), land + Vector3(0, 1.2, 0), exclude).is_empty():
			return {}
		var g := _ray(space, land + Vector3(0, 1.0, 0), land + Vector3(0, -1.5, 0), exclude)
		if g.is_empty():
			return {}
		var clip := "vault" if height < 0.95 else "vault_high"
		# hands land on the middle of the top
		var y_top := feet.y + height - 0.08
		var back := _ray(space, Vector3(wall_pt.x, y_top, wall_pt.z) + wall_dir * 1.0, Vector3(wall_pt.x, y_top, wall_pt.z), exclude)
		var thick := 0.3 if back.is_empty() else clampf((back.position - wall_pt).dot(wall_dir), 0.05, 0.85)
		var plant := wall_pt + wall_dir * thick * 0.5
		var start := Transform3D(face, Vector3(plant.x, feet.y, plant.z) - wall_dir * float(PLANT[clip]))
		return {"type": "vault", "clip": clip, "start": start, "height": height}
	if height >= CLIMB_MIN:
		var clip := "jump_hang" if height >= HANG_ABOVE else "climb"
		var start := Transform3D(face, Vector3(wall_pt.x, feet.y, wall_pt.z) - wall_dir * float(PLANT[clip]))
		return {"type": "climb", "clip": clip, "start": start, "height": height}
	return {}


static func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, MASK)
	q.exclude = exclude
	return space.intersect_ray(q)
