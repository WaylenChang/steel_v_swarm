extends "res://scripts/main.gd"

var fixture_ready := false
var fixture_pilot: BattleUnit
var missile_snapshot_seen := false
var missile_event_seen := false
var fixture_elapsed := 0.0

func _physics_process(delta: float) -> void:
	if Session.launch_announced:
		fixture_elapsed += delta
	if fixture_elapsed > 15:
		push_error("NETWORK_MISSILE_TIMEOUT ready=%s snapshot=%s event=%s state=%s" % [fixture_ready, missile_snapshot_seen, missile_event_seen, smoke_state_seen])
		get_tree().quit(1)
		return
	if Session.dedicated:
		if simulation == null or simulation.pilots.is_empty():
			return
		if not fixture_ready:
			for pilot: BattleUnit in simulation.pilots.values():
				if pilot.peer_id > 1:
					fixture_pilot = pilot
			if fixture_pilot == null:
				return
			simulation.set_physics_process(false)
			var base: BattleUnit
			for unit: BattleUnit in simulation.units.values():
				if unit.kind == "base" and unit.side != fixture_pilot.side:
					base = unit
			var point := base.position + Vector3(0, 0, 70)
			point.y = simulation.world.ground_height(point.x, point.z) + 40
			fixture_pilot.position = point
			simulation._tick_base_guns(base, Content.constants.UNITS.base.guns, 0.05)
			if simulation.missiles.size() != 2:
				push_error("NETWORK_BASE_LAUNCH_MISSING")
				get_tree().quit(1)
				return
			simulation._tick_missiles(0.2)
			fixture_ready = true
			print("MISSILE_FIXTURE_READY missiles=", simulation.missiles.size())
		else:
			simulation.clock += delta
			if fixture_pilot.input_state.get("fire", false):
				fixture_pilot.yaw = fixture_pilot.input_state.get("yaw", fixture_pilot.yaw)
				fixture_pilot.pitch = fixture_pilot.input_state.get("pitch", fixture_pilot.pitch)
				simulation.fire(fixture_pilot, "light")
		return
	super._physics_process(delta)
	if missile_snapshot_seen and missile_event_seen:
		print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
		print("NETWORK_MISSILE_PASS snapshot=true nativeGeometry=true interception=true")
		Session.stop()
		get_tree().quit()

func _receive_state(state: Dictionary) -> void:
	super._receive_state(state)
	if Session.dedicated or simulation == null:
		return
	var pilot: BattleUnit = simulation.pilots.get(Session.player_id())
	if pilot == null:
		return
	var states: Array = state.get("missiles", [])
	if not states.is_empty():
		var id := int(states[0].id)
		if simulation.missile_bodies.has(id) and states[0].hp > 0 and states[0].max_hp == Content.constants.BASE_MISSILE.HP:
			missile_snapshot_seen = true
			var offset: Vector3 = simulation.missile_bodies[id].position - pilot.view_origin()
			yaw = atan2(-offset.x, -offset.z)
			pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
			Input.action_press("fire")
	for event: Dictionary in state.events:
		if event.type == "missile_intercept" and int(event.actor) == pilot.entity_id and pilot.money > Content.constants.ECON.START:
			missile_event_seen = true
