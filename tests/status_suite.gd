extends RefCounted

class SettlementSimulation extends BattleSimulation:
	func _missile_target_altitude(target: BattleUnit) -> float:
		return float(target.get_meta("relative_altitude", target.position.y))

	func _height_difference(first: BattleUnit, second: BattleUnit) -> float:
		if first == null or second == null:
			return 0.0
		return float(first.get_meta("absolute_eye", 0)) - float(second.get_meta("absolute_eye", 0))

class ReferenceSimulation extends BattleSimulation:
	var hits: Array = []
	var blasts: Array = []
	var controls: Array = []
	var capture_interrupt := false
	var interrupted_fraction := -1.0

	func acquire_target(_unit: BattleUnit, _reach: float, _fov: bool = false) -> BattleUnit:
		return units.get(2)

	func _npc_acquire_cached(_unit: BattleUnit, _profile: Dictionary) -> BattleUnit:
		return units.get(2)

	func _unit_level(_unit: BattleUnit) -> int:
		return 0

	func _place_solid(unit: BattleUnit, offset: Vector2) -> void:
		unit.position += Vector3(offset.x, 0, offset.y)

	func _missile_target_altitude(target: BattleUnit) -> float:
		return float(target.get_meta("relative_altitude", target.position.y))

	func _height_difference(first: BattleUnit, second: BattleUnit) -> float:
		if first == null or second == null:
			return 0.0
		return float(first.get_meta("absolute_eye", 0)) - float(second.get_meta("absolute_eye", 0))

	func damage(_attacker: BattleUnit, target: BattleUnit, definition: Dictionary, amount: float,
			_friendly: bool = false, _context: Dictionary = {}, _attack_modifiers: bool = true) -> void:
		hits.append({"target": target.entity_id, "amount": amount, "pen": definition.get("pen", 0)})

	func blast(_unit: BattleUnit, definition: Dictionary, impact: Vector3, _friendly: bool = false,
			_relative_heights: bool = false, impact_level: int = -1, npc_damage: float = NAN) -> void:
		var record := {"definition": definition, "point": [impact.x, impact.y, impact.z], "level": impact_level}
		if is_finite(npc_damage):
			record.npc_damage = npc_damage
		blasts.append(record)

	func _apply_cc(_unit: BattleUnit, added: Dictionary, center: Vector3, radius: float) -> void:
		controls.append({"added": added, "point": [center.x, 0, center.z], "radius": radius})

	func _cast_effect(unit: BattleUnit, definition: Dictionary, center: Vector3, fraction: float = 1.0, once: bool = true, count_override: int = -1) -> void:
		if capture_interrupt:
			interrupted_fraction = fraction
		else:
			super._cast_effect(unit, definition, center, fraction, once, count_override)

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["statusMath", "statusCritical", "statusDodge", "statusElements", "statusCharges", "statusAbilities", "statusInterruptions", "statusSettlement", "statusPhase", "statusBash", "statusNpcFire"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original status references with tools/import_source.mjs before final verification: " + key)
			return
	for item: Dictionary in fixtures.statusMath:
		match item.type:
			"altitude":
				var factors := StatusRules.critical_factors(item.gap)
				h._near(factors.rate, item.rate, "Source altitude critical rate")
				h._near(factors.damage, item.damage, "Source altitude critical bonus")
				h._near(StatusRules.suppression_strength(item.gap), item.suppression, "Source discontinuous suppression floor")
			"miss": h._near(StatusRules.miss_probability(item.dodge, item.suppression, item.unbalanced, item.weather), item.result, "Source independent miss probabilities")
			"shield": h._near(StatusRules.shield_kind_factor(item.kind, item.blast, item.boosted, item.slot), item.result, "Source defensive shield kind and attack state")
			"selfBoost": compare(h, StatusRules.self_attack_boost(item.character, int(item.level), int(item.light), int(item.heavy)), item.result, "Original self attack budget " + item.character)
			"evasionFloor": h._near(StatusRules.evasion_min_speed(), item.result, "Source evasion threshold shares the mobility compression curve")
	for item: Dictionary in fixtures.statusCritical:
		var simulation := ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = item.now
		for input: Dictionary in item.inputs:
			actor(simulation, input)
		var attacker: BattleUnit = simulation.units[1]
		h._near(simulation._roll_critical(attacker, simulation.units[2], item.definition, 100), item.result, "Original critical roll and altitude bonus")
		h._check(attacker.status.get("phase_critical", false) == item.forced, "Original phase critical consumes once without rolling RNG")
		var reports := simulation.events.filter(func(event): return event.type == "crit")
		h._check(reports.size() == (0 if item.report == null else 1), "Only an actual critical hit emits its source report")
		if item.report != null and not reports.is_empty():
			h._near(reports[0].amount, item.report, "Original critical report rounding")
		check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.statusDodge:
		var simulation := ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = item.now
		var attacker := actor(simulation, item.attacker)
		var target := actor(simulation, item.target)
		h._near(simulation._dodge_probability(target, attacker), item.result, "Original motion gate, perfect dodge, altitude and suppression: " + target.character)
		simulation.free()
	for item: Dictionary in fixtures.statusElements:
		var simulation := ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		var attacker := actor(simulation, item.attacker)
		var target := actor(simulation, item.target)
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			if step.has("delta"):
				simulation._tick_element_buildup(target, step.delta)
			else:
				simulation._apply_hit_emp(item.definition, target)
				simulation._apply_hit_elements(attacker, item.definition, target)
			compare_state(h, target, step.state)
		check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.statusSettlement:
		var simulation := SettlementSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		for input: Dictionary in item.actors:
			actor(simulation, input)
		var attacker: BattleUnit = simulation.units[1]
		var target: BattleUnit = simulation.units[2]
		if item.cast != null:
			target.cast_state = {"start": item.cast.start, "duration": item.cast.dur,
				"definition": Content.ability("s08", "def"), "point": target.position, "level": 1}
			target.status.cast_lock_until = 20
		var context: Dictionary = item.context.duplicate(true)
		var key := "blast" if context.has("blast") else "origin"
		context[key] = Vector3(context[key][0], context[key][1], context[key][2])
		simulation.damage(attacker, target, item.definition, item.definition.dmg, false, context)
		for expected: Dictionary in item.result:
			compare_state(h, simulation.units[int(expected.id)], expected)
		h._near(attacker.damage_out, item.damage_out, "Original actual shield and armored HP loss feeds damage accounting and vamp")
		h._check(target.assists.has(attacker.peer_id) == item.assisted, "Only a damaging hostile settlement stamps a permanent assist")
		check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.statusCharges:
		var simulation := ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = item.now
		var unit := actor(simulation, {"character": item.character, "id": 1, "side": "STEEL", "position": [0, 0, 0]})
		unit.cooldowns[item.slot] = item.cooldown
		unit.ability_charges[item.slot] = {"max": 1, "recharge_at": item.deadlines.duplicate()}
		var ready := simulation._ready_charges(unit, item.slot, Content.ability(item.character, item.slot, int(item.level)))
		h._check(ready == int(item.ready), "Original independent charge capacity")
		h._near(unit.cooldowns[item.slot], item.resultCooldown, "Original spare charge leaves no shared cooldown")
		compare(h, unit.ability_charges[item.slot].recharge_at, item.resultDeadlines, "Original inclusive recharge expiry")
		simulation.free()
	for item: Dictionary in fixtures.statusAbilities:
		var simulation := ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = item.now
		for input: Dictionary in item.actors:
			actor(simulation, input)
		var caster: BattleUnit = simulation.units[1]
		var definition := Content.ability(item.character, item.slot, int(item.level))
		h._check(simulation._ability_supported(definition, item.character), "Source effect implementation accepts its authored fixture")
		simulation._cast_effect(caster, definition, Vector3.ZERO, item.fraction, item.once)
		for expected: Dictionary in item.result:
			compare_state(h, simulation.units[int(expected.id)], expected)
		compare(h, simulation.vision_until, item.vision, "Original team vision window")
		compare(h, simulation.hits, item.hits, "Original raw EMP spell damage")
		compare(h, simulation.blasts, item.blasts, "Original strike scatter, blast definitions and ground layer")
		compare(h, simulation.controls, item.cc, "Original unscaled secondary control effects")
		check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.statusInterruptions:
		var simulation := ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.capture_interrupt = true
		simulation.clock = item.now
		var unit := actor(simulation, {"character": item.character, "id": 1, "side": "STEEL", "position": [0, 0, 0]})
		unit.status.cast_lock_until = 40
		unit.cast_state = {"start": item.start, "duration": item.duration, "definition": Content.ability(item.character, "def", int(item.level)), "point": Vector3.ZERO, "level": item.level}
		simulation._interrupt_cast(unit)
		h._near(simulation.interrupted_fraction, item.fraction, "Original interrupted cast clamps elapsed time before squaring")
		h._check(unit.cast_state.is_empty() and unit.status.cast_lock_until == item.lock, "Original cast clears before applying its interrupted effect")
		simulation.free()
	for item: Dictionary in fixtures.statusPhase:
		var simulation := ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		var unit := actor(simulation, item.input)
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			simulation.hits.clear()
			simulation.blasts.clear()
			simulation.controls.clear()
			simulation._tick_ability_states(1.0 / 60)
			compare(h, unit.status, step.state.status, "Original phase expiry and guaranteed next critical")
			compare(h, simulation.blasts, step.blasts, "Phase expiry applies the original ground blast exactly once")
			compare(h, simulation.controls, step.cc, "Phase exit pushes rather than pulls nearby enemies")
		simulation.free()
	for item: Dictionary in fixtures.statusBash:
		var simulation := ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = item.now
		for input: Dictionary in item.inputs:
			actor(simulation, input)
		simulation._tick_shield_bash(simulation.units[1], item.delta)
		compare(h, simulation.hits, item.hits, "Original shield bash front sector, range and shield gates")
		for expected: Dictionary in item.result:
			var unit: BattleUnit = simulation.units[int(expected.id)]
			h._check(unit.position.distance_to(Vector3(expected.position[0], expected.position[1], expected.position[2])) < 0.00001, "Original shield bash outward displacement")
		simulation.free()
	for item: Dictionary in fixtures.statusNpcFire:
		var simulation := ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = item.now
		for input: Dictionary in item.inputs:
			actor(simulation, input)
		simulation._tick_npc(simulation.units[1], 1.0 / 60)
		compare(h, simulation.hits, item.hits, "Original NPC direct damage excludes hero weapon counters")
		compare(h, simulation.blasts, item.blasts, "Original NPC and structure weapons use authored blast radii")
		h._check(simulation.events.any(func(event): return event.type == "shot") == item.shot, "Original EMP weapon gate still emits no accepted fire")
		check_draws(h, simulation, int(item.draws))
		simulation.free()
	print("STATUS_REFERENCE_PASS math=", fixtures.statusMath.size(), " dodge=", fixtures.statusDodge.size(), " elements=", fixtures.statusElements.size(),
		" charges=", fixtures.statusCharges.size(), " abilities=", fixtures.statusAbilities.size(), " interruptions=", fixtures.statusInterruptions.size())

static func actor(simulation: BattleSimulation, input: Dictionary) -> BattleUnit:
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.entity_id = int(input.id)
	unit.peer_id = int(input.id)
	unit.character = input.character
	unit.kind = Content.heroes[unit.character].kind if not unit.character.is_empty() else input.kind
	unit.side = input.side
	unit.position = Vector3(input.position[0], input.position[1], input.position[2])
	for property: String in ["hp", "max_hp", "shield", "max_shield", "power", "max_power", "armor", "respawn_at", "damaged_at"]:
		if input.has(property):
			unit.set(property, float(input[property]))
	if unit.is_hero():
		unit.radius = Content.heroes[unit.character].radius
		unit.height = Content.heroes[unit.character].height
	else:
		unit.radius = Content.balance.unitVolumes[unit.kind][unit.side].radius
		unit.height = Content.balance.unitVolumes[unit.kind][unit.side].height
	unit.hp = float(input.get("hp", 200))
	unit.ammo = input.get("ammo", {}).duplicate(true)
	unit.reload_at = input.get("reload_at", {}).duplicate(true)
	unit.upgrades = input.get("upgrades", unit.upgrades).duplicate(true)
	unit.status = input.get("status", {}).duplicate(true)
	unit.defending = input.get("defending", false)
	if input.has("velocity"):
		unit.velocity = Vector3(input.velocity[0], input.velocity[1], input.velocity[2])
	unit.set_meta("absolute_eye", input.get("absolute_eye", 0))
	unit.set_meta("relative_altitude", input.get("relative_altitude", 0))
	for modifier: Dictionary in input.get("buffs", []):
		unit.buffs.append({"until": modifier.until, "mul": {modifier.key: modifier.value}, "break_on_hit": modifier.break_on_hit})
	simulation.units[unit.entity_id] = unit
	simulation.next_id = maxi(simulation.next_id, unit.entity_id + 1)
	if unit.is_hero():
		simulation.pilots[unit.peer_id] = unit
	return unit

static func compare_state(h: Node, unit: BattleUnit, expected: Dictionary) -> void:
	for property: String in ["hp", "shield", "power", "respawn_at", "damaged_at"]:
		h._near(float(unit.get(property)), float(expected[property]), "Original effect state: " + property)
	h._check(unit.alive() != expected.dead and unit.defending == expected.defending, "Original alive and defense states")
	compare(h, unit.status, expected.status, "Original status state")
	var modifiers: Array = []
	for buff: Dictionary in unit.buffs:
		for key: String in buff.mul:
			modifiers.append({"key": key, "value": buff.mul[key], "until": buff.until, "break_on_hit": buff.get("break_on_hit", false)})
	compare(h, modifiers, expected.buffs, "Original fraction-scaled modifiers")
	if expected.bleed != null:
		compare(h, unit.bleed, expected.bleed, "Original attributed bleed")
	if expected.aura != null:
		compare(h, unit.heal_aura, expected.aura, "Original heal aura")
		if expected.aura.sp_hps == null:
			h._check(float(unit.heal_aura.until) <= 10, "Zero-fraction source aura expires before its non-finite shield rate can settle")
	for slot: String in ["light", "heavy"]:
		var capacity: float = Content.weapon(unit.character, slot, int(unit.upgrades.hw if slot == "heavy" else unit.upgrades.lw) + 1).mag
		h._near(float(unit.ammo.get(slot, capacity)), float(expected.ammo.get(slot, capacity)), "Original lazy refill and native materialized magazine agree")
	compare(h, unit.reload_at, expected.reload_at, "Original reload reset")

static func check_draws(h: Node, simulation: BattleSimulation, count: int) -> void:
	var expected := SourceRng.new(42)
	for index in range(count):
		expected.next()
	h._check(simulation.rng.state == expected.state, "Original short circuit preserves the combat RNG draw count")

static func compare(h: Node, actual: Variant, expected: Variant, label: String) -> void:
	if expected == null:
		return
	if expected is Dictionary:
		h._check(actual is Dictionary, label + " dictionary")
		if actual is Dictionary:
			for key in expected:
				if expected[key] == null:
					continue
				h._check(actual.has(key), label + " key=" + str(key))
				if actual.has(key):
					compare(h, actual[key], expected[key], label + "/" + str(key))
	elif expected is Array:
		h._check(actual is Array and actual.size() == expected.size(), label + " array size")
		if actual is Array:
			for index in range(mini(actual.size(), expected.size())):
				compare(h, actual[index], expected[index], label + "/" + str(index))
	elif expected is float or expected is int:
		h._check(actual is float or actual is int, label + " number")
		if actual is float or actual is int:
			h._check(absf(float(actual) - float(expected)) <= maxf(0.000001, absf(float(expected)) * 0.000001), label + " source scalar")
	else:
		h._check(actual == expected, label + " source value")
