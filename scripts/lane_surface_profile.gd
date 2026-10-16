class_name LaneSurfaceProfile
extends RefCounted

var grid: Dictionary = {}
var lanes: Array = []

func configure(paths: Array, ground: Callable, surface: Callable) -> void:
	grid.clear()
	lanes.clear()
	var rules: Dictionary = Content.balance.bodyRules.presentation.laneSurface
	for path: Array in paths:
		if path.size() < 2:
			lanes.append(null)
			continue
		var cumulative := WaveRules.cumulative(path)
		var total := float(cumulative[-1])
		var height: float = ground.call(float(path[0][0]), float(path[0][1]))
		var distance := 0.0
		var samples: Array = []
		while distance <= total:
			var index := 1
			while index < path.size() - 1 and float(cumulative[index]) < distance:
				index += 1
			var segment := float(cumulative[index]) - float(cumulative[index - 1])
			var fraction := (distance - float(cumulative[index - 1])) / (segment if segment != 0 else 1.0)
			var x := float(path[index - 1][0]) + (float(path[index][0]) - float(path[index - 1][0])) * fraction
			var z := float(path[index - 1][1]) + (float(path[index][1]) - float(path[index - 1][1])) * fraction
			height = surface.call(Vector3(x, height + float(rules.seedStep), z))
			assert(is_finite(height), "Original lane surface samples require complete terrain coverage")
			var sample := {"x": x, "z": z, "y": height}
			samples.append(sample)
			var key := Vector2i(floori(x / float(rules.cell)), floori(z / float(rules.cell)))
			if not grid.has(key):
				grid[key] = []
			grid[key].append(sample)
			distance += float(rules.segment)
		lanes.append({"samples": samples})

func at(x: float, z: float) -> Variant:
	var rules: Dictionary = Content.balance.bodyRules.presentation.laneSurface
	var radius := float(rules.radius)
	var cell := float(rules.cell)
	var best: Variant = null
	var square := radius * radius
	for i in range(floori((x - radius) / cell), floori((x + radius) / cell) + 1):
		for j in range(floori((z - radius) / cell), floori((z + radius) / cell) + 1):
			for sample: Dictionary in grid.get(Vector2i(i, j), []):
				var dx := float(sample.x) - x
				var dz := float(sample.z) - z
				var distance := dx * dx + dz * dz
				if distance < square:
					square = distance
					best = float(sample.y)
	return best
