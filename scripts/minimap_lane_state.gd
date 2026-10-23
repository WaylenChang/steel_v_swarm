class_name MinimapLaneState
extends RefCounted

static func classify(lanes: Array, queries: Dictionary) -> Array:
	var result: Array = []
	var rules: Dictionary = Content.balance.minimap.lanes
	for lane: Variant in lanes:
		var classified: Array = []
		if lane != null:
			for sample: Dictionary in lane.samples:
				var grade := "ground"
				var tunnel: Variant = queries.tunnel.call(sample.x, sample.z)
				if tunnel != null and not tunnel.is_empty() and not tunnel.open and float(sample.y) + float(rules.tunnelClearance) < float(tunnel.ceil) and absf(float(sample.y) - float(tunnel.floor)) < float(rules.tunnelTolerance):
					grade = "tunnel"
				else:
					var deck: Variant = queries.deck.call(sample.x, sample.z)
					if deck != null and float(deck) > float(queries.ground.call(sample.x, sample.z)) + float(rules.bridgeExcess) and absf(float(sample.y) - float(deck)) < float(rules.bridgeTolerance):
						grade = "bridge"
				classified.append({"x": sample.x, "z": sample.z, "grade": grade})
		result.append(classified)
	return result

static func groups(lanes: Array, ids: Array) -> Array:
	var result: Array = []
	for index in lanes.size():
		var samples: Array = lanes[index]
		var start := 0
		while start < samples.size() - 1:
			var grade: String = samples[start].grade
			var end := start + 1
			while end < samples.size() - 1 and samples[end].grade == grade:
				end += 1
			var points: Array = []
			for point in range(start, end + 1):
				points.append([samples[point].x, samples[point].z])
			result.append({"points": points, "grade": grade, "lane": int(ids[index]) if index < ids.size() and ids[index] != null else index})
			start = end
	return result
