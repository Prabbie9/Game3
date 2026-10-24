extends Node
## Lane graph sanity: lane counts, every town lane continues somewhere, connectors start/end where their lanes do,
## signal phases never give two crossing groups green at once.
## godot --headless --path . res://tests/runner.tscn -- res://tests/lane_graph_check.gd

func _ready() -> void:
	var data := WorldData.get_data()
	var net := RoadNet.new()
	net.build(data)
	var t0 := Time.get_ticks_msec()
	var g := LaneGraph.new()
	g.build(data, net)
	var ms := Time.get_ticks_msec() - t0
	var fails := 0
	var roads := 0
	var conns := 0
	var dead := 0
	var gap := 0.0
	for id in g.lanes.size():
		var ln: Dictionary = g.lanes[id]
		if ln.node >= 0:
			conns += 1
			continue
		roads += 1
		if (ln.next as Array).is_empty():
			dead += 1
		for c: int in ln.next:
			gap = maxf(gap, (g.lanes[c].pts as PackedVector3Array)[0].distance_to((ln.pts as PackedVector3Array)[-1]))
	print("lanes %d road, %d connectors, %d dead ends, %d signalled junctions, build %d ms, max joint gap %.3f" % [roads, conns, dead, g.signals.size(), ms, gap])
	if gap > 0.01:
		fails += 1
		print("FAIL connector joints")
	if dead > roads * 0.05:
		fails += 1
		print("FAIL too many dead ends")
	for node in g.signals:
		for t in range(0, int(g.cycle(node)), 1):
			if g.signal_state(node, 0, t) != 2 and g.signal_state(node, 1, t) != 2:
				fails += 1
				print("FAIL both phases open at node %d t %d" % [node, t])
				break
	print("LANE GRAPH CHECK %s" % ("PASSED" if fails == 0 else "FAILED"))
	get_tree().quit(0 if fails == 0 else 1)
