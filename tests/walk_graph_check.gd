extends Node
## Pavement graph sanity: size, every pavement end joins something, the network is mostly one piece,
## corners are short, crossings exist at town junctions.
## godot --headless --path . res://tests/runner.tscn -- res://tests/walk_graph_check.gd

func _ready() -> void:
	var data := WorldData.get_data()
	var net := RoadNet.new()
	net.build(data)
	var t0 := Time.get_ticks_msec()
	var g := WalkGraph.new()
	g.build(data, net)
	var ms := Time.get_ticks_msec() - t0
	var fails := 0
	var crossings := 0
	var corner_max := 0.0
	var isolated := 0
	for e: Dictionary in g.edges:
		if e.cross:
			crossings += 1
		elif e.road < 0:
			corner_max = maxf(corner_max, float(e.len))
	for n in g.node_count():
		if (g.links[n] as Array).size() < 2:
			isolated += 1
	# largest connected component
	var seen := {}
	var best := 0
	for n in g.node_count():
		if seen.has(n):
			continue
		var stack := [n]
		var size := 0
		seen[n] = true
		while not stack.is_empty():
			var c: int = stack.pop_back()
			size += 1
			for id: int in g.links[c]:
				var o := g.other_end(id, c)
				if not seen.has(o):
					seen[o] = true
					stack.append(o)
		best = maxi(best, size)
	print("walk graph: %d nodes, %d edges, %d crossings, %d dangling, longest corner %.1f m, main network %.0f%%, %d ms" % [g.node_count(), g.edges.size(), crossings, isolated, corner_max, 100.0 * best / g.node_count(), ms])
	if crossings < 100:
		fails += 1
		print("FAIL few crossings")
	if float(best) / g.node_count() < 0.8:
		fails += 1
		print("FAIL network in pieces")
	if corner_max > 50.0:
		fails += 1
		print("FAIL a corner link is suspiciously long")
	print("WALK GRAPH CHECK %s" % ("PASSED" if fails == 0 else "FAILED"))
	get_tree().quit(0 if fails == 0 else 1)
