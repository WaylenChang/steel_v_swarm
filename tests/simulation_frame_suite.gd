extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class FrameWorld extends BattleWorld:
	func sync_fires(_states: Array, _now: float, _dynamics: Dictionary) -> void:
		pass

class ProbeBrain extends RefCounted:
	var simulation: BattleSimulation
	var owner: BattleUnit

	func update(delta: float) -> void:
		simulation.phase("bot", delta)
		simulation.cast(owner, "def", owner.position)

class FrameSimulation extends Helper.SettlementSimulation:
	var trace: Array = []
	var index_count := 0
	var player_steps := 0
	var projectile_steps := 0
	var presentation_steps := 0

	func phase(name: String, delta: float = 0) -> void:
		trace.append({"phase": name, "now": clock, "delta": delta})

	func _tick_player_controls(_delta: float) -> void:
		player_steps += 1

	func _tick_projectiles(_delta: float) -> void:
		projectile_steps += 1

	func _present_authority_actors(_delta: float) -> void:
		presentation_steps += 1

	func _tick_weapon_pose(_unit: BattleUnit, _delta: float) -> void:
		pass

	func _tick_authority_body(_unit: BattleUnit, _delta: float) -> void:
		pass

	func _tick_lock(_unit: BattleUnit) -> void:
		pass

	func _tick_weather(delta: float) -> void:
		phase("weather", delta)
		weather_dynamics = {}

	func spawn_wave() -> void:
		phase("wave")

	func _spawn_airdrop_wave() -> void:
		phase("airdrop_wave")

	func _wave_anchors() -> Dictionary:
		phase("anchors")
		return super._wave_anchors()

	func _tick_casts(delta: float) -> void:
		phase("casts", delta)
		super._tick_casts(delta)

	func _tick_carriers(delta: float) -> void:
		phase("carriers", delta)

	func _tick_civilians(delta: float) -> void:
		phase("civilians", delta)

	func _tick_mines() -> void:
		phase("mines")

	func _tick_ambush(delta: float) -> void:
		phase("ambush", delta)

	func _tick_relays(delta: float) -> void:
		phase("relays", delta)

	func _tick_fires(delta: float) -> void:
		phase("hazards", delta)
		super._tick_fires(delta)

	func _tick_loots(_delta: float) -> void:
		pass

	func _tick_airdrops(delta: float) -> void:
		phase("airdrops", delta)

	func _tick_camps(delta: float) -> void:
		phase("camps", delta)

	func _tick_heal_auras(delta: float) -> void:
		phase("auras", delta)
		super._tick_heal_auras(delta)

	func _tick_clones(delta: float) -> void:
		phase("clones", delta)

	func _tick_cubic_slabs(delta: float) -> void:
		phase("slabs", delta)

	func _tick_fogs(delta: float) -> void:
		phase("fogs", delta)

	func _tick_summons(delta: float) -> void:
		phase("summons", delta)

	func _tick_phase_shift(delta: float) -> void:
		phase("phase", delta)

	func _tick_holograms(delta: float) -> void:
		phase("holograms", delta)

	func _tick_element_states(delta: float) -> void:
		phase("elements", delta)

	func _begin_npc_index() -> void:
		phase("index")
		index_count += 1
		npc_index_active = true

	func _tick_npc(unit: BattleUnit, _delta: float) -> void:
		phase("npc")
		unit.npc_engaged = index_count % 2 == 1

	func _tick_missiles(delta: float) -> void:
		phase("missiles", delta)

	func _record_actor_history(unit: BattleUnit) -> void:
		phase("trail")
		super._record_actor_history(unit)

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("simulationFrames"):
		h._check(false, "Regenerate active original room/frame references")
		return
	for item: Dictionary in fixtures.simulationFrames:
		var simulation := context(h, item)
		for frame: Dictionary in item.frames:
			simulation._physics_process(frame.delta)
			Helper.compare(h, snapshot(simulation), frame.result,
				"Original room/frame order, previous engagement anchors, recovery/cast/fire/aura budgets and report order")
			h._check(not simulation.npc_index_active and simulation.npc_index.is_empty(),
				"Frame targeting index is unavailable after the original final history sample")
		Helper.check_draws(h, simulation, int(item.draws))
		for steps: int in [simulation.player_steps, simulation.projectile_steps, simulation.presentation_steps]:
			h._check(steps == item.frames.size(), "Native controls, kinetic reports and presentation keep their physics cadence")
		var before := snapshot(simulation)
		var seed := simulation.rng.state
		simulation.authoritative = false
		simulation._tick_authority(.125)
		h._check(snapshot(simulation) == before and simulation.rng.state == seed, "Replica combat tick cannot settle or emit")
		simulation.authoritative = true
		simulation.over = true
		simulation._tick_authority(.125)
		h._check(snapshot(simulation) == before and simulation.rng.state == seed, "Finished combat tick cannot settle or emit")
		simulation.free()
	print("SIMULATION_FRAME_REFERENCE_PASS programs=", fixtures.simulationFrames.size())

static func context(h: Node, item: Dictionary) -> FrameSimulation:
	var simulation := FrameSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	# Scalar source anchors only: this component context never builds a playable map.
	simulation.world = FrameWorld.new()
	simulation.add_child(simulation.world)
	for side: String in item.bases:
		var p: Array = item.bases[side]
		simulation.world.bases[side] = Vector3(p[0], p[1], p[2])
	simulation.clock = 10
	simulation.next_wave = 10.125
	simulation.next_airdrop = 10.125
	for input: Dictionary in item.inputs:
		var unit := Helper.actor(simulation, input)
		simulation.pilots.erase(unit.entity_id)
		unit.peer_id = int(input.peer)
		if unit.is_hero():
			simulation.pilots[unit.peer_id] = unit
		unit.is_bot = unit.entity_id == 1
		if unit.entity_id == 3:
			unit.has_lane = true
			unit.npc_has_wave = true
			unit.npc_wave = 1
			unit.npc_progress = 40
			unit.npc_engaged = true
	var owner: BattleUnit = simulation.units[1]
	var brain := ProbeBrain.new()
	brain.simulation = simulation
	brain.owner = owner
	simulation.bot_brains[owner.entity_id] = brain
	simulation.fire_fields.append({"id": 500, "kind": "fire", "position": Vector3.ZERO, "scale": 1,
		"ttl": item.fireTtl, "lightning": false})
	simulation._cast_effect(owner, Content.ability("s08", "def", 1), owner.position)
	simulation.events.clear()
	return simulation

static func snapshot(simulation: FrameSimulation) -> Dictionary:
	var actors: Array = []
	for id: int in [1, 2]:
		var unit: BattleUnit = simulation.units[id]
		actors.append({"id": id, "hp": unit.hp, "shield": unit.shield, "power": unit.power,
			"cast_until": unit.cast_state.start + unit.cast_state.duration if not unit.cast_state.is_empty() else 0.0,
			"aura_until": unit.heal_aura.get("until", 0), "cooldown": unit.cooldowns.get("def", 0)})
	var reports: Array = []
	for event: Dictionary in simulation.events:
		if event.type in ["cast_start", "cast", "heal_aoe", "heal_aura_start", "heal_aura_end"]:
			reports.append({"type": event.type, "peer": simulation.units[int(event.actor)].peer_id})
	var result := {"clock": simulation.clock, "trace": simulation.trace.duplicate(true), "actors": actors,
		"anchors": simulation.wave_anchors.duplicate(), "engaged": simulation.units[3].npc_engaged, "events": reports}
	simulation.trace.clear()
	simulation.events.clear()
	return result
