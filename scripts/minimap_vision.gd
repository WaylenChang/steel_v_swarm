class_name MinimapVision
extends RefCounted

var pulse_until := 0.0
var events_seen := CombatFeedState.new()

func clear() -> void:
	pulse_until = 0
	events_seen.clear()

func observe(event: Dictionary, viewer: String, now: float) -> void:
	if not events_seen.accept(event) or event.get("side", "") != viewer:
		return
	if event.type == "relay":
		pulse_until = now + float(Content.constants.FIELD.RELAY.VISION_S)
	elif event.type == "cast" and Content.heroes.has(event.get("character", "")) and event.get("slot", "") in ["def", "atk"]:
		if not event.has("level"):
			push_error("Public cast report is missing its original accepted ability level")
			return
		var ability := Content.ability(event.character, event.slot, float(event.level))
		var duration := float(ability.get("vision", 0))
		if duration != 0:
			pulse_until = maxf(pulse_until, now + duration)

static func sources(rows: Array, view: Dictionary) -> Array:
	var result: Array = []
	var aim := float(Content.constants.GAME.AIM_SIGHT_MULT) if view.aiming else 1.0
	var fog := NpcRules.fog_sight(float(view.fog))
	for row: Dictionary in rows:
		if row.side != view.side or row["self"] or row.dead or float(row.hp) <= 0 or row.decoy and row.lost:
			continue
		var sight: Variant = Content.constants.UNITS.get(row.kind, {}).get("sight")
		if sight == null:
			continue
		result.append([row.point.x, row.point.y, float(sight) * (aim if row.hero and row.peer == view.peer else 1.0) * fog])
	if not view.dead and not String(view.kind).is_empty():
		var sight: Variant = Content.constants.UNITS.get(view.kind, {}).get("sight")
		if sight != null:
			result.append([view.point.x, view.point.y, float(sight) * aim * fog])
	return result

static func shadows(point: Vector2, radius: float, blockers: Array) -> Variant:
	if blockers.is_empty():
		return null
	var result: Array = []
	var rules: Dictionary = Content.balance.minimap.fog
	var far := radius * float(rules.farFactor)
	for blocker: Dictionary in blockers:
		var extent := minf(float(rules.maximumRadius), float(blocker.r))
		if extent < float(rules.minimumRadius):
			continue
		var dx := float(blocker.x) - float(point.x)
		var dz := float(blocker.z) - float(point.y)
		if absf(dx) > radius + extent or absf(dz) > radius + extent:
			continue
		var distance := sqrt(dx * dx + dz * dz)
		if distance <= extent or distance - extent >= radius or extent / distance < float(rules.minimumAngleRatio):
			continue
		var bearing := atan2(dz, dx)
		var angle := asin(extent / distance)
		var tangent := sqrt(distance * distance - extent * extent)
		var c0 := cos(bearing - angle)
		var s0 := sin(bearing - angle)
		var c1 := cos(bearing + angle)
		var s1 := sin(bearing + angle)
		result.append([[point.x + c0 * tangent, point.y + s0 * tangent],
			[point.x + c0 * far, point.y + s0 * far],
			[point.x + c1 * far, point.y + s1 * far],
			[point.x + c1 * tangent, point.y + s1 * tangent]])
		if result.size() >= int(rules.maximumShadows):
			break
	return result
