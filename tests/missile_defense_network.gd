extends "res://scripts/main.gd"

var elapsed := 0.0
var started_at := -1.0
var fixture_pilot: BattleUnit
var fixture_carrier_owner: BattleUnit
var stage := 0
var decoy_seen := false
var carrier_seen := false
var phase_seen := false
var reflect_seen := false
var harmless_seen := false

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 16:
		push_error("NETWORK_MISSILE_DEFENSE_TIMEOUT decoy=%s phase=%s reflect=%s harmless=%s" % [decoy_seen, phase_seen, reflect_seen, harmless_seen])
		get_tree().quit(1)
		return
	if Session.dedicated:
		if simulation == null or simulation.pilots.is_empty():
			return
		if fixture_pilot == null:
			for pilot: BattleUnit in simulation.pilots.values():
				if pilot.peer_id > 1:
					fixture_pilot = pilot
			if fixture_pilot == null:
				return
			simulation.set_physics_process(false)
			for unit: BattleUnit in simulation.units.values():
				if unit != fixture_pilot:
					unit.hp = 0
			fixture_pilot.position = Vector3(0, simulation.world.ground_height(0, 0) + 80, 0)
			simulation._spawn_holograms(fixture_pilot, Content.ability("t04", "def"))
			for id: int in simulation.hologram_decoys:
				var decoy: BattleUnit = simulation.units[id]
				decoy.position.y = simulation.world.ground_height(decoy.position.x, decoy.position.z) + 80
			launch(Vector3(0, 80, -30))
			simulation._tick_missiles(0.05)
			if simulation.missiles.size() != 1 or int(simulation.missiles[0].target) not in simulation.hologram_decoys:
				fail("NETWORK_MISSILE_DECOY_ATTRACTION")
				return
			started_at = elapsed
		simulation.clock += delta
		var age := elapsed - started_at
		if age > 0.4 and stage == 0:
			for state: Dictionary in simulation.missiles.duplicate():
				simulation._remove_missile(int(state.id))
			fixture_carrier_owner = simulation.spawn({"kind": Content.heroes.s01.kind, "character": "s01", "peer": 4401,
				"side": "SWARM", "position": fixture_pilot.position + Vector3(10, 0, 0)})
			var point := fixture_carrier_owner.position + Vector3(0, 0, -180)
			point.y = simulation.world.ground_height(point.x, point.z)
			simulation._launch_carriers(fixture_carrier_owner, Content.ability("s01", "atk"), point, simulation._ability_origin(fixture_carrier_owner, "atk"))
			launch(Vector3(10, 80, -30), fixture_carrier_owner)
			simulation._tick_missiles(0.05)
			if simulation.missiles.size() != 1 or int(simulation.missiles[0].target) not in fixture_carrier_owner.carrier_ids:
				fail("NETWORK_MISSILE_ACTIVE_CARRIER_ATTRACTION")
				return
			stage = 1
		if age > 0.8 and stage == 1:
			for state: Dictionary in simulation.missiles.duplicate():
				simulation._remove_missile(int(state.id))
			for id: int in simulation.hologram_decoys:
				simulation._remove_field_unit(id)
			simulation.hologram_decoys.clear()
			for id: int in fixture_carrier_owner.carrier_ids.duplicate():
				simulation._remove_carrier(id)
			fixture_carrier_owner.hp = 0
			fixture_pilot.status.phase_until = simulation.clock + 10
			launch(Vector3(0, 80, -8))
			simulation._tick_missiles(0.05)
			if simulation.missiles.size() != 1 or not simulation.missiles[0].get("lost", false):
				fail("NETWORK_MISSILE_PHASE_ORDER")
				return
			stage = 2
		if age > 1.6 and stage == 2:
			for state: Dictionary in simulation.missiles.duplicate():
				simulation._remove_missile(int(state.id))
			fixture_pilot.status.phase_until = 0
			fixture_pilot.status.reflect_until = simulation.clock + 10
			fixture_pilot.yaw = 0
			var health := fixture_pilot.hp
			var shield := fixture_pilot.shield
			var credits := fixture_pilot.money
			launch(Vector3(0, 80, -8))
			simulation._tick_missiles(0.05)
			if not simulation.missiles.is_empty() or fixture_pilot.hp != health or fixture_pilot.shield != shield or fixture_pilot.money != credits:
				fail("NETWORK_MISSILE_REFLECTION_SETTLEMENT")
				return
			stage = 3
		return
	super._physics_process(delta)
	if decoy_seen and carrier_seen and phase_seen and reflect_seen and harmless_seen:
		print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
		print("NETWORK_MISSILE_DEFENSE_PASS decoy=true active_carrier=true phase=true reflect=true harmless=true")
		Session.stop()
		get_tree().quit()

func launch(point: Vector3, target: BattleUnit = null) -> void:
	if target == null:
		target = fixture_pilot
	simulation._launch_missile({"actor": 0, "side": "SWARM" if target.side == "STEEL" else "STEEL", "target": target.entity_id,
		"position": point, "origin": point, "speed": 40.0, "range": 1000.0, "ttl": 20.0,
		"hp": Content.constants.BASE_MISSILE.HP, "max_hp": Content.constants.BASE_MISSILE.HP,
		"dmg": Content.constants.UNITS.base.guns.dmg, "pen": Content.constants.STRUCT_W.base.pen,
		"r": Content.constants.STRUCT_W.base.r})

func _receive_state(state: Dictionary) -> void:
	super._receive_state(state)
	if Session.dedicated or simulation == null:
		return
	var pilot: BattleUnit = simulation.pilots.get(Session.player_id())
	if pilot == null:
		return
	var missiles: Array = state.get("missiles", [])
	var decoys: Array = state.units.filter(func(unit): return unit.special.get("role") == "hologram")
	decoy_seen = decoy_seen or (not decoys.is_empty() and missiles.size() == 1 and simulation.missile_bodies.size() == 1)
	carrier_seen = carrier_seen or (decoy_seen and missiles.size() == 1 and state.units.any(func(unit): return unit.kind == "kami" and unit.special.get("role") == "carrier"))
	phase_seen = phase_seen or (decoy_seen and decoys.is_empty() and missiles.size() == 1 and pilot.has_status("phase_until", state.clock))
	for event: Dictionary in state.events:
		if event.type == "reflect_hit" and event.get("deflected", false) and int(event.actor) == pilot.entity_id:
			reflect_seen = true
		if event.type == "missile_deflect" and int(event.actor) == pilot.entity_id:
			harmless_seen = missiles.is_empty() and simulation.missile_bodies.is_empty() and not state.events.any(func(other): return other.type == "missile_blast")

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
