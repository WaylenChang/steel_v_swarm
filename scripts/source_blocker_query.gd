class_name SourceBlockerQuery
extends RefCounted

var entries: Array = []
var grid: Dictionary = {}
var seen: Dictionary = {}
var indexed_count := -1

func ensure(blockers: Array) -> void:
	if not is_same(entries, blockers) or indexed_count != blockers.size():
		configure(blockers)

func clear() -> void:
	entries = []
	grid.clear()
	seen.clear()
	indexed_count = -1

func configure(blockers: Array) -> void:
	clear()
	entries = blockers
	indexed_count = blockers.size()
	var identities := {}
	var cell := float(Content.balance.minimap.fog.cell)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var key := hash(entry)
		var identity := index
		for previous: int in identities.get(key, []):
			if is_same(entries[previous], entry):
				identity = previous
				break
		if identity == index:
			if not identities.has(key):
				identities[key] = []
			identities[key].append(index)
		var radius := sqrt(float(entry.hw2) * float(entry.hw2) + float(entry.hd2) * float(entry.hd2)) if entry.get("hw2") != null else float(entry.r)
		StructureLayers._index(grid, identity, entry.x, entry.z, entry.x, entry.z, radius, cell)

func near(point: Vector2, radius: float) -> Array:
	var cell := float(Content.balance.minimap.fog.cell)
	var first := Vector2i(floori((point.x - radius) / cell), floori((point.y - radius) / cell))
	var last := Vector2i(floori((point.x + radius) / cell), floori((point.y + radius) / cell))
	var result: Array = []
	if first == last:
		for index: int in grid.get(first, []):
			result.append(entries[index])
		return result
	seen.clear()
	# Source cell order is observable when the minimap truncates its shadows.
	for i in range(first.x, last.x + 1):
		for j in range(first.y, last.y + 1):
			for index: int in grid.get(Vector2i(i, j), []):
				if not seen.has(index):
					seen[index] = true
					result.append(entries[index])
	return result
