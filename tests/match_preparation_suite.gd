extends RefCounted

class RejectedSimulation extends BattleSimulation:
	var errors: Array[String] = []

	func _setup_failed(reason: String) -> void:
		# Capture expected rejection diagnostics without polluting engine-error checks.
		if not setup_error.is_empty():
			return
		setup_complete = false
		setup_error = reason
		errors.append(reason)
		failure_reported.emit(reason)

static func run(h: Node, _fixtures: Dictionary) -> void:
	var map_data := Content.map_variant(0, 1)
	var environment := {"season": "summer", "time": "day", "weather": "clear"}
	for state: String in ["unprepared", "failed", "building", "road_only", "wrong_map", "detached", "missing_scene", "wrong_identity"]:
		var battle := RejectedSimulation.new()
		h.add_child(battle)
		battle.set_physics_process(false)
		battle.prepared_map = map_data.duplicate(true)
		battle.prepared_environment = environment.duplicate(true)
		battle.setup_complete = state != "unprepared"
		if state == "failed":
			battle.setup_error = "Original world preparation failure"
		if state != "unprepared":
			battle.world = BattleWorld.new()
			battle.add_child(battle.world)
			battle.world.build_complete = state != "building"
		if state == "wrong_map":
			battle.prepared_map = {}
		if state == "detached":
			battle.remove_child(battle.world)
		if state in ["missing_scene", "wrong_identity"]:
			# Deliberately invalid resources exercise rejection, never a playable map.
			battle.world.native_data = NativeWorldData.new()
			if state == "wrong_identity":
				battle.world.native_data.scene = PackedScene.new()
		var seed := battle.rng.state
		var source_map := map_data.duplicate(true)
		h._check(not battle.begin_match(map_data, []), "Unprepared authority match is rejected: " + state)
		h._check(not battle.setup_error.is_empty() and not battle.match_initialized and not battle.is_physics_processing(),
			"Rejected match cannot start authority physics: " + state)
		h._check(battle.units.is_empty() and battle.pilots.is_empty() and battle.mines.is_empty() and battle.hazard_blockers.is_empty()
			and battle.rng.state == seed and battle.next_id == 1 and battle.wave == 0 and battle.next_wave == 0 and battle.next_airdrop == 0,
			"Rejection precedes structures, prefill, hazards, timers and combat RNG: " + state)
		h._check(map_data == source_map, "Rejected launch does not mutate the source map: " + state)
		var first_error := battle.setup_error
		var error_count := battle.errors.size()
		h._check(not battle.begin_match(map_data, []) and battle.setup_error == first_error and battle.errors.size() == error_count,
			"Repeated launch retains the first failure without duplicate failure events: " + state)
		if state == "detached":
			battle.world.free()
		battle.free()
	for authority: bool in [false, true]:
		var battle := RejectedSimulation.new()
		h.add_child(battle)
		battle.set_physics_process(false)
		battle.authoritative = authority
		battle.match_initialized = authority
		h._check(not battle.begin_match(map_data, []) and battle.errors.is_empty(),
			"Replicas and repeated initialized matches cannot enter population or report a new setup failure")
		battle.free()
	for authority: bool in [false, true]:
		var battle := RejectedSimulation.new()
		h.add_child(battle)
		var road_only := map_data.duplicate(true)
		road_only.erase("native_world")
		var seed := battle.rng.state
		await battle.setup(road_only, [], environment, authority, true)
		h._check(not battle.setup_complete and battle.world == null and battle.setup_error.contains("road-only")
			and battle.rng.state == seed and battle.units.is_empty() and not battle.is_physics_processing(),
			"Both authority and replicas reject missing authored world identity before construction")
		battle.free()
