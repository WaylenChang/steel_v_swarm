extends "res://scripts/main.gd"

var fixture_pilot: BattleUnit
var fixture_target: BattleUnit
var fixture_elapsed := 0.0
var fixture_started := 0.0
var clear_seen := false
var warning_seen := false
var measured_centre_seen := false
var target_id := 0

func _physics_process(delta: float) -> void:
	fixture_elapsed += delta
	if fixture_elapsed > 15:
		push_error("NETWORK_REACHABILITY_TIMEOUT active=%s started=%s fixture=%s state=%s clear=%s warning=%s" %
			[Session.active, Session.started, fixture_pilot != null, smoke_state_seen, clear_seen, warning_seen])
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
			fixture_pilot.position = Vector3(0, simulation.world.ground_height(0, 0) + 100, 0)
			fixture_target = simulation.spawn({"kind": "morph", "character": "m08", "side": "SWARM",
				"position": fixture_pilot.position + Vector3(0, 0, -100)})
			fixture_started = fixture_elapsed
		else:
			simulation.clock += delta
			fixture_pilot.yaw = fixture_pilot.input_state.get("yaw", 0)
			fixture_pilot.pitch = fixture_pilot.input_state.get("pitch", 0)
			fixture_target.position.z = -1500 if fixture_elapsed - fixture_started > 5 else -10 if fixture_elapsed - fixture_started > 2 else -100
			if not simulation.snapshot().reachability.is_empty():
				push_error("NETWORK_REACHABILITY_PRIVACY")
				get_tree().quit(1)
		return
	selected_slot = "heavy"
	Input.action_press("aim")
	super._physics_process(delta)

func _receive_state(state: Dictionary) -> void:
	super._receive_state(state)
	if Session.dedicated or simulation == null:
		return
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot == null:
		return
	for unit: Dictionary in state.units:
		if unit.hp <= 0 or unit.side == pilot.side or not Content.heroes.has(unit.character):
			continue
		var offset: Vector3 = unit.position + Vector3.UP * Content.balance.modelGeometry.heroes[unit.character].centre - pilot.view_origin()
		yaw = atan2(-offset.x, -offset.z)
		pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	var advice: Dictionary = state.get("reachability", {})
	if not advice.is_empty():
		target_id = int(advice.target)
		var target: BattleUnit = simulation.units.get(target_id)
		if target == null or advice.slot != "heavy":
			push_error("NETWORK_REACHABILITY_INVALID_TARGET")
			get_tree().quit(1)
			return
		var offset := target.aim_point() - pilot.view_origin()
		yaw = atan2(-offset.x, -offset.z)
		pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
		measured_centre_seen = measured_centre_seen or absf(target.visual_dimensions().centre - target.height / 2) > 0.01
		clear_seen = clear_seen or (advice.ok and not advice.warn and ammo_label.text.contains(Content.label("reach_clear")))
		warning_seen = warning_seen or (advice.ok and advice.warn and ammo_label.text.contains(Content.label("reach_warning")))
	elif clear_seen and warning_seen and measured_centre_seen and target_id != 0 and not state.units.any(func(unit): return int(unit.id) == target_id):
		print("NETWORK_PASS peer=", multiplayer.get_unique_id(), " units=", simulation.units.size())
		print("NETWORK_REACHABILITY_PASS clear=true warning=true hidden=true hud=true measuredCentre=true")
		Session.stop()
		get_tree().quit()
