class_name AudioMovePlan
extends RefCounted

static func compile(graph: Dictionary) -> Dictionary:
	var nodes: Array = graph.get("nodes", [])
	var edges: Array = graph.get("connections", [])
	if nodes.is_empty() or not graph.has("g"):
		return {}
	var rate_nodes := {}
	for binding: Dictionary in graph.rate:
		rate_nodes["%d:%s" % [binding.parameter.node, binding.parameter.parameter]] = binding.base
	var modulation := {}
	var lfos := {}
	for edge: Dictionary in edges:
		if not edge.to is Dictionary:
			continue
		if edge.to.parameter != "gain":
			return _unsupported()
		var trim: Dictionary = nodes[int(edge.from)]
		if trim.kind != "createGain":
			return _unsupported()
		var inputs := _inputs(edges, int(edge.from))
		if inputs.size() != 1:
			return _unsupported()
		var oscillator: Dictionary = nodes[int(inputs[0].from)]
		if oscillator.kind != "createOscillator":
			return _unsupported()
		var frequency := float(oscillator.parameters.frequency.initial)
		lfos[int(oscillator.id)] = {"node": int(oscillator.id), "frequency": frequency,
			"rate_scaled": rate_nodes.has("%d:frequency" % oscillator.id)}
		modulation[int(edge.to.node)] = {"node": int(oscillator.id), "depth": float(trim.parameters.gain.initial)}
	var branches: Array[Dictionary] = []
	for source: Dictionary in nodes:
		if source.kind not in ["createOscillator", "createBufferSource"] or lfos.has(int(source.id)):
			continue
		var branch := {"source": int(source.id), "kind": "noise" if source.kind == "createBufferSource" else "oscillator",
			"frequency": float(source.parameters.frequency.initial) if source.kind == "createOscillator" else 0.0,
			"rate_scaled": rate_nodes.has("%d:frequency" % source.id), "gain": 1.0, "weight": "constant", "modulation": {}, "filters": []}
		if branch.kind == "noise" and (source.get("buffer") != "sharedNoise" or not source.get("loop", false)):
			return _unsupported()
		var current: int = source.id
		var visited := {}
		while current != int(graph.g):
			if visited.has(current):
				return _unsupported()
			visited[current] = true
			var outputs := _outputs(edges, current)
			if outputs.size() != 1 or not outputs[0].to is int and not outputs[0].to is float:
				return _unsupported()
			current = int(outputs[0].to)
			if current == int(graph.g):
				break
			var node: Dictionary = nodes[current]
			if node.kind == "createBiquadFilter":
				if not branch.modulation.is_empty() or AudioSourceFilter.create(node) == null:
					return _unsupported()
				branch.filters.append({"node": current, "captured": node, "rate_scaled": rate_nodes.has("%d:frequency" % current)})
			elif node.kind == "createGain":
				if current == graph.get("dry"):
					branch.weight = "dry"
				elif current == graph.get("wet"):
					branch.weight = "wet"
				elif modulation.has(current):
					if not branch.modulation.is_empty():
						return _unsupported()
					branch.modulation = modulation[current].duplicate()
					branch.modulation.offset = float(node.parameters.gain.initial)
				else:
					branch.gain *= float(node.parameters.gain.initial)
			else:
				return _unsupported()
		branches.append(branch)
	return {"branches": branches, "lfos": lfos}

static func _inputs(edges: Array, node: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for edge: Dictionary in edges:
		if (edge.to is int or edge.to is float) and int(edge.to) == node:
			result.append(edge)
	return result

static func _outputs(edges: Array, node: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for edge: Dictionary in edges:
		if int(edge.from) == node and not edge.to is Dictionary:
			result.append(edge)
	return result

static func _unsupported() -> Dictionary:
	push_error("Unsupported original movement audio graph; no replacement bed is substituted")
	return {}
