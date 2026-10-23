class_name ActorSnapshot
extends RefCounted

# Full BattleUnit snapshots are internal. Transport publication selects the owner.
const OWNER_FIELDS := ["ammo", "reload_at", "cooldowns", "ability_charges", "charge", "lift", "pitch",
	"view_yaw", "view_mode", "view_fov", "view_reset", "view_offset", "cast", "deaths"]
const PUBLIC_DEADLINES := ["emp_until", "blind_until", "stun_until", "slow_until", "confuse_until",
	"mark_until", "unbalanced_until", "freeze_until"]
const ROLES := ["civilian", "hazard", "carrier", "clone", "summon", "hologram", "slab", "third"]
const CONTROL_FIELDS := {"freezeLeft": "freeze_until", "stunLeft": "stun_until", "slowLeft": "slow_until",
	"confLeft": "confuse_until", "markLeft": "mark_until", "invLeft": "inv_until",
	"empLeft": "emp_until", "blindLeft": "blind_until", "unbalLeft": "unbalanced_until"}

static func abilities(unit: BattleUnit, now: float) -> Dictionary:
	var result := {"levels": {}, "cooldowns": [], "charges": []}
	for slot: String in ["light", "heavy", "def", "atk"]:
		result.levels[slot] = unit.combat_level(slot)
	var multiple := false
	for slot: String in ["def", "atk"]:
		var definition: Dictionary = Content.ability(unit.character, slot, unit.combat_level(slot)) if Content.heroes.has(unit.character) else {}
		var capacity := maxi(1, int(definition.get("charges", 1)))
		var charge: Dictionary = unit.ability_charges.get(slot, {})
		var allocated := unit.ability_charges.has(slot)
		var summary := AbilityChargeState.inspect(capacity, unit.cooldowns.get(slot, 0), charge, now, allocated)
		# Original chg appears only once an independently charged slot is allocated.
		# Single-charge tiers retain any old allocated max/queue without pruning it.
		var maximum := int(charge.max) if charge.get("max", 0) else 1
		if allocated and capacity > 1:
			maximum = int(summary.maximum)
		var deadlines: Array = summary.deadlines if capacity > 1 else charge.get("recharge_at", [])
		var deadline: float = deadlines.min() if int(summary.ready) < maximum and not deadlines.is_empty() else summary.cooldown
		var next := maxf(0, floorf((deadline - now) * 10.0 + 0.5) / 10.0)
		result.cooldowns.append(0.0 if int(summary.ready) > 0 else next)
		multiple = multiple or maximum > 1
		result.charges.append([summary.ready, maximum, next])
	if not multiple:
		result.erase("charges")
	return result

static func project(unit: BattleUnit, viewer: BattleUnit, now: float) -> Dictionary:
	var owned := unit.is_pilot() and unit == viewer
	var state := unit.snapshot(owned)
	state.special = special(state.special, unit.kind)
	if not unit.status.get("lightning_scorch", {}).is_empty():
		state.charred = true
	if unit.is_hero() and unit.side == Content.constants.SUPER_SIDE:
		state.super_level = int(unit.upgrades.get("super", 0))
	if unit.is_pilot():
		state.max_power = unit.max_power
		state.public_abilities = abilities(unit, now)
	else:
		for key: String in ["power", "max_power", "money", "score", "upgrades"]:
			state.erase(key)
	if not owned:
		for key: String in OWNER_FIELDS:
			state.erase(key)
		state.status = public_status(unit, now)
		state.buffs = public_buffs(unit.buffs, now) if unit.is_hero() else []
		state.defending = unit.is_hero() and unit.defending and unit.shield > 0
		state.shield_expanded = state.defending and float(unit.status.get("shield_expand_until", 0)) > now
		var cast: Variant = cast_remaining(unit, now)
		if cast != null:
			state.cast_remaining = cast
	return state

# Native role/model tags describe public scene identity, never authority plans.
# Civilian input is already sanitized by BattleUnit.snapshot's spy boundary.
static func special(value: Dictionary, kind: String) -> Dictionary:
	var result := {}
	var role := str(value.get("role", ""))
	if role in ROLES:
		result.role = role
	for key: String in ["neutral", "garrison", "collapsed", "siege_locked"]:
		if value.get(key, false):
			result[key] = true
	if value.get("boss", false):
		result.boss = true
		result.boss_segment = int(value.get("boss_segment", 0))
	match role:
		"civilian":
			for key: String in ["civil_side", "profession", "following", "fleeing"]:
				if value.has(key):
					result[key] = value[key]
		"hazard":
			if value.get("scale", 0):
				result.scale = value.scale
			if kind == "relay" and float(value.get("relay_charge", 0)) > 0:
				result.relay_progress = mini(100, floori(float(value.relay_charge) / float(Content.constants.FIELD.RELAY.CHANNEL_S) * 100.0 + 0.5))
				result.relay_side = value.get("relay_side", "")
		"carrier":
			for key: String in ["model_key", "owner_peer"]:
				if value.has(key):
					result[key] = value[key]
			if kind == "decoy" and value.get("lost", false):
				result.lost = true
			if kind == "hyper":
				result.phase = "dive" if value.get("phase") == "dive" else "climb"
		"third":
			result.third = true
	return result

static func deadline_remaining(deadline: float, now: float) -> float:
	return floorf((deadline - now) * 10.0 + .5) / 10.0 if deadline > now else 0.0

static func control_status(unit: BattleUnit, now: float) -> Dictionary:
	var result := {}
	for field: String in CONTROL_FIELDS:
		result[field] = deadline_remaining(float(unit.status.get(CONTROL_FIELDS[field], 0)), now)
	result.bleedLeft = deadline_remaining(float(unit.bleed.get("until", 0)), now)
	var cast: Variant = cast_remaining(unit, now)
	result.castLeft = float(cast) if cast != null else 0.0
	return result

static func cast_remaining(unit: BattleUnit, now: float) -> Variant:
	if not unit.is_hero():
		return null
	var cast_end: float = float(unit.cast_state.get("start", 0)) + float(unit.cast_state.get("duration", 0))
	var cast_lock: float = unit.status.get("cast_lock_until", 0)
	var end := cast_end if cast_end > now else cast_lock
	return deadline_remaining(end, now) if end > now else null

static func status_icon_details(unit: BattleUnit, now: float) -> Dictionary:
	var result := {"stealthLeft": deadline_remaining(float(unit.status.get("stealth_until", 0)), now),
		"slowF": unit.status.get("slow_factor", .6) if float(unit.status.get("slow_until", 0)) > now else .6,
		"hiSupLeft": 0.0, "selfMods": [], "_buffsLeft": []}
	if float(unit.status.get("sup_until", 0)) > now and float(unit.status.get("sup_factor", 0)) > 0:
		result.hiSupLeft = floorf((float(unit.status.sup_until) - now) * 100.0 + .5) / 100.0
	for buff: Dictionary in public_buffs(unit.buffs, now):
		var remaining := floorf(float(buff.until) - now + .5)
		if buff.has("affix"):
			result._buffsLeft.append([buff.affix, remaining])
		else:
			for key: String in buff.mul:
				result.selfMods.append([key, buff.mul[key], remaining])
	return result

static func public_status(unit: BattleUnit, now: float) -> Dictionary:
	var result := {}
	var keys: Array = PUBLIC_DEADLINES.duplicate()
	if unit.is_hero():
		keys.append_array(["stealth_until", "inv_until"])
	for key: String in keys:
		var deadline: float = unit.status.get(key, 0)
		if deadline > now:
			result[key] = now + floorf((deadline - now) * 10.0 + 0.5) / 10.0
	if float(unit.status.get("slow_until", 0)) > now:
		result.slow_factor = unit.status.get("slow_factor", 0.6)
	if float(unit.status.get("sup_until", 0)) > now and float(unit.status.get("sup_factor", 0)) > 0:
		result.sup_until = now + floorf((float(unit.status.sup_until) - now) * 100.0 + 0.5) / 100.0
		result.sup_factor = floorf(float(unit.status.sup_factor) * 100.0 + 0.5) / 100.0
	if float(unit.bleed.get("until", 0)) > now:
		result.bleed_until = now + floorf((float(unit.bleed.until) - now) * 10.0 + 0.5) / 10.0
	return result

static func public_buffs(buffs: Array, now: float) -> Array:
	var result: Array = []
	for buff: Dictionary in buffs:
		if float(buff.get("until", 0)) <= now:
			continue
		var value := {"until": now + floorf(float(buff.until) - now + 0.5), "mul": buff.get("mul", {}).duplicate(true)}
		if buff.has("affix"):
			value.affix = buff.affix
		result.append(value)
	return result

static func event(value: Dictionary, owned: bool) -> Dictionary:
	var result := value.duplicate(true)
	if not owned and result.get("type") == "weapon_fire":
		result.erase("empty_heavy")
		result.erase("aim_request")
	return result
