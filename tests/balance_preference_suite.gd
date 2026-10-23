extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class RecordedPreferences extends BalancePreferences:
	var writes: Array = []
	var fail_writes := false

	func _save() -> void:
		if fail_writes:
			save_failed.emit(ERR_CANT_CREATE)
			return
		writes.append(snapshot())

static func run(h: Node, fixtures: Dictionary) -> void:
	if not Content.balance.has("balancePreferences") or not fixtures.has("balanceLoads"):
		h._check(false, "Regenerate original balance preference references")
		return
	var rules: Dictionary = Content.balance.balancePreferences
	for fixture: Dictionary in fixtures.balanceReads:
		var preferences := BalancePreferences.new()
		preferences.configure(rules)
		Helper.compare(h, preferences.snapshot(), fixture.values, "Original inaccessible, empty or malformed storage initializes factory values")
		h._check(preferences.is_default() == fixture.isDefault, "Failed reads retain default state")
	var queried := BalancePreferences.new()
	queried.configure(rules, fixtures.balanceQueries.saved)
	for query: Dictionary in fixtures.balanceQueries.queries:
		Helper.compare(h, queried.pref(query.key), query.pref, "Original preference lookup and unknown-key fallback")
		Helper.compare(h, queried.multiplier(str(query.key).trim_prefix("stat_")), query.multiplier, "Original stat lookup preserves case-sensitive mpCost and rejects curve aliases")
	var live := BalancePreferences.new()
	live.configure(rules)
	var observed := {"values": {}}
	var callback := func(values: Dictionary): observed.values = values
	live.changed.connect(callback)
	live.set_value("stat_speed", 2)
	Helper.compare(h, observed.values.stat_speed, fixtures.balanceLiveNotification.before, "Balance subscribers receive the current live values")
	live.changed.disconnect(callback)
	live.set_value("stat_speed", 3)
	Helper.compare(h, observed.values.stat_speed, fixtures.balanceLiveNotification.after, "Disconnecting a subscriber does not turn its previously received live reference into a snapshot")
	for fixture: Dictionary in fixtures.balanceLoads:
		var preferences := BalancePreferences.new()
		preferences.configure(rules, fixture.saved)
		Helper.compare(h, preferences.snapshot(), fixture.values, "Original balance load ignores unknown keys and normalizes explicit null/coercible values")
		h._check(preferences.is_default() == fixture.isDefault, "Original balance default-state predicate")
	for fixture: Dictionary in fixtures.balanceChanges:
		var preferences := RecordedPreferences.new()
		preferences.configure(rules)
		var notifications: Array = []
		preferences.changed.connect(func(values: Dictionary): notifications.append(values.duplicate()))
		Helper.compare(h, preferences.set_value(fixture.key, fixture.input), fixture.result, "Original balance clamp and tenth rounding")
		var snapshot := preferences.snapshot()
		snapshot.stat_speed = 999
		Helper.compare(h, preferences.snapshot(), fixture.updated, "Balance snapshots are independent copies")
		h._check(preferences.is_default() == fixture.isDefault, "Changed balance default state")
		preferences.set_value(fixture.key, fixture.input)
		preferences.reset()
		preferences.reset()
		Helper.compare(h, preferences.snapshot(), fixture.final, "Original balance reset restores every known knob")
		Helper.compare(h, notifications, fixture.notifications, "Unknown keys, identical writes and repeated resets do not notify")
		var writes: Array = []
		for write: Dictionary in fixture.writes:
			writes.append(write.value)
		Helper.compare(h, preferences.writes, writes, "Original balance persistence occurs before each change notification")
	for fixture: Dictionary in fixtures.balanceCurves:
		var preferences := BalancePreferences.new()
		preferences.configure(rules, fixture.saved)
		Helper.compare(h, preferences.curve(fixture.item, fixture.level), fixture.value, "Original combat/defense curve bounds and unaliased def/atk keys")
	var failing := RecordedPreferences.new()
	failing.configure(rules)
	failing.fail_writes = true
	var notifications: Array = []
	var failures: Array = []
	failing.changed.connect(func(values: Dictionary): notifications.append(values.duplicate()))
	failing.save_failed.connect(func(error: Error): failures.append(error))
	failing.set_value("stat_speed", 2)
	failing.reset()
	Helper.compare(h, notifications, fixtures.balanceWriteFailure.notifications, "Storage failure does not suppress in-memory balance changes or subscribers")
	Helper.compare(h, failing.snapshot(), fixtures.balanceWriteFailure.values, "Reset remains effective after failed storage")
	h._check(failures.size() == 2, "Native persistence errors remain observable")
	_storage(h, rules)
	_panel(h, rules)
	_definitions(h, fixtures, rules)

static func _panel(h: Node, rules: Dictionary) -> void:
	var preferences := BalancePreferences.new()
	preferences.configure(rules)
	var first := BalanceSettings.new()
	var second := BalanceSettings.new()
	h.add_child(first)
	h.add_child(second)
	first.configure(preferences)
	second.configure(preferences)
	var shown: Array = []
	for group: Dictionary in rules.ui.groups:
		shown.append_array(group.keys)
	h._check(first.widgets.keys() == shown and second.widgets.keys() == shown, "Both native settings mounts preserve source knob order and omit unmatched def/atk catalog entries")
	var key: String = shown[0]
	first.widgets[key].slider.value = 2.1
	h._check(preferences.pref(key) == 2.1 and second.widgets[key].slider.value == 2.1, "Native slider commits source-normalized values and synchronizes the other mount")
	h._check(not first.reset_button.disabled and not second.reset_button.disabled, "Changed preferences enable both reset buttons")
	second.reset_button.pressed.emit()
	h._check(preferences.is_default() and first.reset_button.disabled and second.reset_button.disabled, "Native reset updates all mounted sliders without recursive writes")
	first.free()
	second.free()

static func _definitions(h: Node, fixtures: Dictionary, rules: Dictionary) -> void:
	if not rules.has("definitions") or not fixtures.has("balanceDefinitionPrograms"):
		h._check(false, "Regenerate original startup and live balance definition references")
		return
	var factory := Content.heroes.duplicate(true)
	for program: Dictionary in fixtures.balanceDefinitionPrograms:
		var preferences := BalancePreferences.new()
		preferences.configure(rules, program.saved)
		var definitions := BalanceDefinitions.new()
		definitions.configure(preferences, rules.definitions)
		var client := ClientWeaponDefinitions.new()
		client.profile = definitions
		var original_building := definitions.building.duplicate(true)
		var original_mid := definitions.range_mid.duplicate()
		for frame: Dictionary in program.frames:
			if frame.operation != null:
				preferences.set_value(frame.operation[0], frame.operation[1])
			for row: Dictionary in frame.rows:
				for slot: String in ["light", "heavy"]:
					var weapon := definitions.weapon(row.ch, slot, row.level)
					var actual := {}
					for key: String in ["dmg", "range", "rate", "rate0", "reload", "fanMaxBuildingHits", "heavyMp"]:
						actual[key] = weapon[key]
					actual.merge({"building": weapon.vs.building, "burstCount": weapon.burst.count, "burstGap": weapon.burst.gap,
						"flightCap": weapon.projectile.flightCap, "fuel": weapon.projectile.fuel})
					Helper.compare(h, actual, row.weapons[slot], "Original initialized/live balance weapon fields and dependent budgets: %s/%s/%s" % [row.ch, slot, row.level])
				for slot: String in ["def", "atk"]:
					var ability := definitions.ability(row.ch, slot, row.level)
					var actual := {}
					for key: String in ["dmg", "heal", "cd", "mp", "range"]:
						actual[key] = ability[key]
					Helper.compare(h, actual, row.abilities[slot], "Original balance ability fields preserve missing curve aliases")
				Helper.compare(h, definitions.speed(row.ch), row.speed, "Original tuned ground mobility")
				Helper.compare(h, definitions.speed(row.ch, true), row.flySpeed, "Original tuned flight mobility")
			for charge: Dictionary in frame.charge:
				Helper.compare(h, definitions.charge(charge.level), charge.value, "Original charging curve clamps its preference interpolation without clamping base extrapolation")
			Helper.compare(h, definitions.shot_trail_seconds(), frame.shotTrailSeconds, "Original first-use shot history horizon remains cached across slider changes")
			Helper.compare(h, definitions.combat_reach(), frame.combatReach, "Original first-use combat reach covers weapons, abilities and carrier arcs")
			Helper.compare(h, definitions.view_curve(), frame.viewCurve, "Original horizon and curvature follow the cached local combat reach")
			for character: String in frame.botProfiles:
				Helper.compare(h, definitions.bot_profile(character), frame.botProfiles[character], "Original first-use role classification, weighted normalization and buy order survive later slider changes")
			_settlement(h, definitions, frame.settlement)
			for slot: String in ["light", "heavy"]:
				var own := client.own_weapon("t01", slot, frame.clientWeapons.lightLevel, frame.clientWeapons.heavyLevel)
				var other := client.other_weapon("t01", slot)
				for key: String in frame.clientWeapons.own[slot]:
					Helper.compare(h, own[key], frame.clientWeapons.own[slot][key], "Original own weapon cache refreshes both slots on character/weapon-level changes")
					Helper.compare(h, other[key], frame.clientWeapons.other[slot][key], "Original remote visual weapon cache retains the first resolved level-one values")
			h._check(definitions.building == original_building and definitions.range_mid == original_mid, "Live sliders preserve initialization-time building tuning and geometric midpoint caches")
	h._check(Content.heroes == factory, "Independent balance profiles do not mutate imported factory content")

static func _settlement(h: Node, definitions: BalanceDefinitions, fixture: Dictionary) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.authoritative = true
	simulation.balance_profile = definitions
	var server := BattleSimulation.new()
	h.add_child(server)
	server.set_physics_process(false)
	for kind: String in fixture.bounties:
		Helper.compare(h, simulation.bounty_for_kind(kind), fixture.bounties[kind], "Original local authority bounty multiplier")
		h._near(server.bounty_for_kind(kind), float(Content.constants.ECON.BOUNTY[kind]), "Remote authority retains factory bounty independently of local preferences")
	for respawn: Dictionary in fixture.respawns:
		Helper.compare(h, simulation.respawn_delay(respawn.kind, respawn.deaths), respawn.value, "Original per-player death count and respawn multiplier")
	for item: Dictionary in fixture.cases:
		var unit := _settlement_actor(simulation, item, "STEEL")
		for step: Dictionary in item.steps:
			unit.upgrades[step.item] = step.level
			simulation._apply_upgrade(unit, step.item)
			_compare_settlement(h, unit, step.result)
		unit.free()
		var super_unit := _settlement_actor(simulation, item, Content.constants.SUPER_SIDE)
		for step: Dictionary in item.superSteps:
			simulation._set_super_level(super_unit, step.level)
			_compare_settlement(h, super_unit, step.result)
		super_unit.free()
	simulation.free()
	server.free()

static func _settlement_actor(simulation: BattleSimulation, fixture: Dictionary, side: String) -> BattleUnit:
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.character = fixture.character
	unit.kind = Content.heroes[unit.character].kind
	unit.side = side
	unit.special = {"boss": fixture.boss}
	for key: String in ["hp", "max_hp", "shield", "max_shield", "armor"]:
		unit.set(key, fixture.initial[key])
	unit.upgrades = fixture.initial.upgrades.duplicate()
	unit.ammo = fixture.initial.ammo.duplicate()
	unit.reload_at = fixture.initial.reload.duplicate()
	return unit

static func _compare_settlement(h: Node, unit: BattleUnit, expected: Dictionary) -> void:
	var actual := {"alive": unit.alive(), "upgrades": unit.upgrades, "ammo": unit.ammo, "reload": unit.reload_at}
	for key: String in ["hp", "max_hp", "shield", "max_shield", "armor"]:
		actual[key] = unit.get(key)
	Helper.compare(h, actual, expected, "Original live/dead/BOSS/super health, shield and armor settlement under changed curves")
	if unit.hp <= 0 and unit.alive():
		var packet := unit.snapshot(false)
		h._check(packet.dead == false, "Health upgrade does not synthesize a death when current HP becomes nonpositive")
		var replica := BattleUnit.new()
		unit.get_parent().add_child(replica)
		replica.character = unit.character
		replica.kind = unit.kind
		replica.side = unit.side
		replica.apply_snapshot(packet, true)
		h._check(replica.alive(), "Public death state distinguishes a surviving health adjustment from a killed body")
		packet.dead = true
		replica.apply_snapshot(packet, true)
		h._check(not replica.alive() and not replica.visible, "A later death snapshot clears the upgrade survival state")
		packet.dead = false
		packet.hp = packet.max_hp
		replica.apply_snapshot(packet, true)
		h._check(replica.alive() and replica.visible, "A respawn snapshot restores ordinary positive-health presentation")
		replica.free()

static func _storage(h: Node, rules: Dictionary) -> void:
	var saved := BalancePreferences.new()
	saved.configure(rules)
	saved.persist = true
	saved.save_path = "user://balance-fixture-%d.cfg" % Time.get_ticks_usec()
	h._check(saved.load_save() == OK and saved.is_default(), "Missing balance profile uses original defaults")
	saved.set_value("stat_speed", 2.05)
	saved.set_value("upg_hp_end", 3.4)
	var restored := BalancePreferences.new()
	restored.configure(rules)
	restored.persist = true
	restored.save_path = saved.save_path
	h._check(restored.load_save() == OK and restored.snapshot() == saved.snapshot(), "Native ConfigFile retains normalized curve and stat preferences")
	var malformed := FileAccess.open(saved.save_path, FileAccess.WRITE)
	malformed.store_string("[broken")
	malformed.close()
	h._check(restored.load_save() != OK and restored.is_default(), "Malformed balance storage restores defaults and reports its read error")
	h._check(DirAccess.remove_absolute(ProjectSettings.globalize_path(saved.save_path)) == OK, "Remove isolated balance profile")
