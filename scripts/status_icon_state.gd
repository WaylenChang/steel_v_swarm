class_name StatusIconState
extends RefCounted

var rules: Dictionary = {}
var maximum: Dictionary = {}
var burn_at := 0.0

func configure(metadata: Dictionary) -> void:
	rules = metadata
	if rules.is_empty():
		push_error("Missing original status-icon metadata; regenerate source controls")

func reset() -> void:
	maximum.clear()
	burn_at = 0

func observe(values: Dictionary, now: float, spectating := false) -> Array:
	if rules.is_empty() or spectating:
		return []
	var result: Array = []
	var active := {}
	var freeze := float(values.get("freezeLeft", 0))
	var stun := float(values.get("stunLeft", 0))
	var emp := float(values.get("empLeft", 0))
	var slow := float(values.get("slowLeft", 0))
	var bleed := float(values.get("bleedLeft", 0))
	var factor := float(values.get("slowF", .6))
	if factor == 0:
		factor = .6
	_push(result, active, "freeze", freeze)
	if stun > 0 and emp > 0:
		_push(result, active, "stun", minf(stun, emp))
		if stun > emp + .1:
			_push(result, active, "paralyze", stun)
		if emp > stun + .1:
			_push(result, active, "emp", emp)
	else:
		_push(result, active, "paralyze", stun)
		_push(result, active, "emp", emp)
	if slow > 0 and not (bleed > 0 and factor > .5):
		_push(result, active, "freeze" if factor <= .4 else "slow", slow)
	if bleed > 0:
		var dot := "burn" if burn_at != 0 and now - burn_at < float(rules.burnWindow) else "bleed"
		if slow > 0 and factor > .5:
			_push(result, active, "poison", minf(bleed, slow))
			if bleed > slow + .1:
				_push(result, active, dot, bleed)
		else:
			_push(result, active, dot, bleed)
	for id: String in ["blind", "conf", "mark", "unbal", "hiSup", "stealth", "inv"]:
		_push(result, active, id, float(values.get(id + "Left", 0)), id in ["stealth", "inv"])
	var mods: Array = values.get("selfMods", []).filter(func(item): return float(item[2]) > 0)
	if not mods.is_empty():
		var seconds := INF
		for item: Array in mods:
			seconds = minf(seconds, float(item[2]))
		_push(result, active, "mod", seconds, true, mods.size())
	for item: Array in values.get("_buffsLeft", []):
		_push(result, active, str(item[0]), float(item[1]), true)
	for id: String in maximum.keys():
		if not active.has(id):
			maximum.erase(id)
	# Godot's sort_custom is unstable. Source JS keeps declaration order for ties.
	for index in range(1, result.size()):
		var item: Dictionary = result[index]
		var at := index
		while at > 0 and float(result[at - 1].remS) > float(item.remS):
			result[at] = result[at - 1]
			at -= 1
		result[at] = item
	return result

func _push(result: Array, active: Dictionary, id: String, seconds: float, positive := false, stacks: Variant = null) -> void:
	if not seconds > 0:
		return
	active[id] = true
	if not maximum.has(id) or seconds > float(maximum[id]):
		maximum[id] = seconds
	var item := {"id": id, "remS": seconds, "positive": positive, "label": rules.labels.get(id, id), "maxS": maximum[id]}
	if stacks != null:
		item.stacks = stacks
	result.append(item)
