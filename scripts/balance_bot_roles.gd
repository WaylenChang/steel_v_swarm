class_name BalanceBotRoles
extends RefCounted

var definition_ref: WeakRef
var definitions: BalanceDefinitions:
	get: return definition_ref.get_ref()
var profiles: Dictionary = {}

func configure(profile_definitions: BalanceDefinitions) -> void:
	definition_ref = weakref(profile_definitions)
	profiles = {}

func profile(character: String) -> Dictionary:
	if profiles.is_empty():
		_build()
	return profiles[character]

func _features(character: String) -> Dictionary:
	var values: Dictionary = definitions.rules.staticRoleFeatures[character].duplicate()
	values.fire = 0.0
	values.zone = 0.0
	values.siege = 0.0
	values.mob = definitions.speed(character, Content.heroes[character].kind == "drone")
	for slot: String in ["light", "heavy"]:
		var weapon := definitions.weapon(character, slot)
		values.fire += CombatMath.weapon_dps(weapon)
		values.zone += CombatMath.zone_area(weapon)
		values.siege += definitions._building_dps(character, slot, 1)
	return values

func _build() -> void:
	var features := {}
	var bands := {}
	for character: String in Content.heroes:
		features[character] = _features(character)
		for key: String in features[character]:
			var value := maxf(.000001, float(features[character][key]))
			if not bands.has(key):
				bands[key] = {"lo": value, "hi": value}
			else:
				bands[key].lo = minf(float(bands[key].lo), value)
				bands[key].hi = maxf(float(bands[key].hi), value)
	var roles: Array = Content.constants.BOT_ROLE_KEYS
	var counts := {}
	for role: String in roles:
		counts[role] = 0
	for character: String in features:
		for key: String in features[character]:
			var value := float(features[character][key])
			if Content.constants.BOT_ROLE_FEATS[key].get("ratio", false):
				features[character][key] = clampf(value, 0, 1)
			else:
				var span := log(float(bands[key].hi) / float(bands[key].lo))
				features[character][key] = clampf(log(maxf(.000001, value) / float(bands[key].lo)) / span, 0, 1) if span > .000000001 else .5
		var selected: String = roles[0]
		var best := -INF
		for role: String in roles:
			var score := 0.0
			for key: String in Content.constants.BOT_ROLES[role].w:
				score += float(Content.constants.BOT_ROLES[role].w[key]) * (float(features[character].get(key, .5)) - .5)
			if score > best:
				best = score
				selected = role
		profiles[character] = {"role": selected}
		counts[selected] += 1
	var norms := {}
	for key: String in Content.constants.BOT_ROLE.KNOBS:
		var total := 0.0
		for role: String in roles:
			total += int(counts[role]) * log(float(Content.constants.BOT_ROLES[role].mul.get(key, 1)))
		norms[key] = exp(total / profiles.size()) if not profiles.is_empty() else 1.0
	for character: String in profiles:
		var role: String = profiles[character].role
		var tactics: Dictionary = Content.constants.BOT_TACTIC.duplicate()
		for key: String in Content.constants.BOT_ROLE.KNOBS:
			var limits: Array = Content.constants.BOT_ROLE.KNOBS[key]
			var base := float(tactics[key]) if is_finite(float(tactics[key])) else float(Content.constants.BOT_TACTIC_BASE[key])
			tactics[key] = clampf(base * float(Content.constants.BOT_ROLES[role].mul.get(key, 1)) / float(norms[key]), limits[0], limits[1])
		BotRules.tactic_cross(tactics)
		profiles[character].tactic = tactics
		profiles[character].buy = Content.constants.BOT_ROLES[role].buy
