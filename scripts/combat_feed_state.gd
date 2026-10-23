class_name CombatFeedState
extends RefCounted

var last_serial := 0
var slope_warning_at := NAN
var slope_publication := -INF

func clear() -> void:
	last_serial = 0
	slope_warning_at = NAN
	slope_publication = -INF

func slope_notice(blocked: bool, now: float, publication: float) -> Array:
	if publication <= slope_publication:
		return []
	slope_publication = publication
	if is_nan(slope_warning_at):
		slope_warning_at = float(Content.balance.movement.slope.warningInitial)
	if not MovementRules.slope_warn(now, slope_warning_at, blocked, 0, 0):
		return []
	slope_warning_at = now
	return [Content.balance.movement.slope.warningText]

func accept(event: Dictionary) -> bool:
	var serial := int(event.get("notice_serial", 0))
	if serial <= last_serial:
		return false
	last_serial = serial
	return true

static func messages(event: Dictionary, actor: int, peer: int, side: String = "STEEL") -> Array:
	if not Content.balance.has("combatFeed"):
		push_error("Missing original combat feed metadata; regenerate source content")
		return []
	var rules: Dictionary = Content.balance.combatFeed
	var own := int(event.get("actor", 0)) == actor or int(event.get("notice_peer", event.get("peer", 0))) == peer
	match str(event.get("type", "")):
		"climb_grab":
			var text: String = Content.balance.movement.climb.notices.get(event.get("kind", ""), "")
			return [text] if own and not text.is_empty() else []
		"die":
			var kind: String = event.get("kind", "")
			if kind == "civilian" or kind == "decoy" and not own:
				return []
			return rules.die.get("%s:%s" % [event.get("side", ""), kind], [])
		"collapse":
			return rules.collapse.get("%s:%d" % [event.get("kind", ""), int(bool(event.get("electric", false)))], [])
		"burn":
			return rules.private["burn_strong" if float(event.get("factor", 1)) >= float(rules.strongBurnThreshold) else "burn"] if own else []
		"cleanse", "heal_aura_start", "freeze":
			return rules.private[event.type] if own else []
		"lightning_strike":
			var result: Array = []
			for point: Dictionary in event.get("points", []):
				if int(point.id) == actor or point.id is String and point.id == str(peer):
					result.append_array(rules.private.lightning)
			return result
		"buy":
			return rules.buy.get("%s:%d" % [event.get("item", ""), int(event.get("level", -1))], []) if own else []
		"assist", "penalty":
			if not own or event.type == "penalty" and float(event.amount) <= 0:
				return []
			return rules.private[event.type].map(func(text): return str(text).format({"value": str(int(event.amount))}))
		"wave":
			return rules.private.wave.map(func(text): return str(text).format({"wave": str(int(event.wave))}))
		"respawn", "revive":
			return rules.private.respawn if event.side == side else []
		"creep_upgrade":
			return rules.creep.get("%d:%d:%d" % [int(event.lane), int(event.level), int(own)], []) if event.side == side else []
		"cast_start":
			if not own:
				return []
			var text: Array = rules.castStart.get("%s:%s" % [event.get("character", ""), event.get("slot", "")], [])
			if text.is_empty():
				return []
			var seconds := "%.1f" % CssDecimal.fixed(float(event.get("duration", 0)), 1)
			return text.map(func(message): return str(message).format({"duration": seconds}))
		"cast":
			var text: Array = rules.cast.get("%s:%s:%d:%d" % [event.get("character", ""), event.get("slot", ""), int(event.get("side", "") == side), int(bool(event.get("interrupted", false)))], [])
			var percentage := str(int(floorf(float(event.get("fraction", 1)) * 100 + .5)))
			return text.map(func(message): return str(message).format({"percent": percentage}))
	return []
