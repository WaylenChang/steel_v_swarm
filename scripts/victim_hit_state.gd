class_name VictimHitState
extends RefCounted

static func reaction(previous: Dictionary, current: Dictionary, hero: bool) -> Dictionary:
	if previous.is_empty():
		return {}
	var drop := float(previous.get("shield", 0)) - float(current.get("shield", 0))
	if hero and current.get("defending", false) and float(current.get("shield", 0)) > 0 and drop > 0:
		return {"shielded": true, "flash": minf(2.5, ShieldPresentation.hit_strength(drop) * 1.6)}
	return {"shielded": false, "flash": 0.0} if float(current.hp) < float(previous.hp) else {}

static func self_reaction(previous: Dictionary, current: Dictionary) -> Dictionary:
	if previous.is_empty() or current.get("dead", false) or int(previous.get("view_reset", 0)) != int(current.get("view_reset", 0)):
		return {}
	var vital := float(current.hp) + float(current.shield)
	if vital >= float(previous.hp) + float(previous.shield) - .5:
		return {}
	var drop := float(previous.shield) - float(current.shield)
	var shielded: bool = current.get("defending", false) and float(current.shield) > 0 and drop > .5
	return {"shielded": shielded, "flash": minf(2.5, ShieldPresentation.hit_strength(drop) * 1.6) if shielded else 0.0}
