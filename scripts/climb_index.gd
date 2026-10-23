class_name ClimbIndex
extends RefCounted

var grid: Dictionary = {}

static func after_camp_clearance(routes: Array, camps: Array, buildings: Dictionary) -> Array:
	var accepted: Array = []
	for route: Dictionary in routes:
		var removed := false
		for key: String in ["blocker", "link"]:
			var blocker: Dictionary = route.get(key, {})
			if blocker.is_empty():
				continue
			if CampRules.removes_blocker(blocker, camps, buildings):
				removed = true
				break
		if not removed:
			accepted.append(route)
	return accepted

func configure(routes: Array) -> void:
	grid.clear()
	var rules: Dictionary = Content.balance.movement.climb
	var radius: float = rules.constants.GRAB_R
	var cell: float = rules.cell
	for route: Dictionary in routes:
		for i in range(floori((float(route.x) - radius) / cell), floori((float(route.x) + radius) / cell) + 1):
			for j in range(floori((float(route.z) - radius) / cell), floori((float(route.z) + radius) / cell) + 1):
				var key: int = i * int(rules.keyStride) + j
				if not grid.has(key):
					grid[key] = []
				grid[key].append(route)

func at(x: float, z: float, y: float) -> Dictionary:
	var rules: Dictionary = Content.balance.movement.climb
	var key := floori(x / float(rules.cell)) * int(rules.keyStride) + floori(z / float(rules.cell))
	var best: Dictionary = {}
	var distance: float = rules.constants.GRAB_R
	for route: Dictionary in grid.get(key, []):
		if y < float(route.y0) - float(rules.lowerTolerance) or y > float(route.y1) + float(rules.constants.GRAB_UP):
			continue
		var dx := x - float(route.x)
		var dz := z - float(route.z)
		var candidate := sqrt(dx * dx + dz * dz)
		# Source <= deliberately selects the last route at an equal distance.
		if candidate <= distance:
			distance = candidate
			best = route
	return best
