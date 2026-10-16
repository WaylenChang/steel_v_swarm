class_name SplatPaintState
extends RefCounted

var live: Dictionary = {}

func sync(entries: Array) -> Dictionary:
	var added: Array[Dictionary] = []
	var removed: Array[int] = []
	var seen := {}
	for entry: Dictionary in entries:
		var id := int(entry.id)
		seen[id] = true
		if not live.has(id):
			var drops: Array = []
			for drop: Dictionary in entry.drops:
				drops.append({"x": CssDecimal.fixed(float(drop.x), 2), "y": CssDecimal.fixed(float(drop.y), 2), "r": CssDecimal.fixed(float(drop.r), 2)})
			live[id] = {"id": id, "left": CssDecimal.fixed(float(entry.u) * 100, 2) / 100,
				"top": CssDecimal.fixed(float(entry.v) * 100, 2) / 100, "drops": drops}
			added.append(live[id])
		var alpha := float(entry.get("a", 0))
		live[id].opacity = CssDecimal.fixed(clampf(0 if is_nan(alpha) else alpha, 0, 1), 3)
	for id: int in live.keys():
		if not seen.has(id):
			removed.append(id)
			live.erase(id)
	return {"added": added, "removed": removed}
