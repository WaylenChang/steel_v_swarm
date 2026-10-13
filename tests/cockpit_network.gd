extends "res://scripts/main.gd"

var fixture_pilot: BattleUnit
var elapsed := 0.0
var heavy_at := 0.0
var light_seen := false
var heavy_seen := false
var reload_seen := false
var pose_seen := false
var zoom_seen := false
var death_seen := false

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 16:
		push_error("NETWORK_COCKPIT_TIMEOUT light=%s heavy=%s reload=%s pose=%s zoom=%s death=%s" % [light_seen, heavy_seen, reload_seen, pose_seen, zoom_seen, death_seen])
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
			fixture_pilot.position = Vector3(0, simulation.world.ground_height(0, 0) + 100, 0)
			for unit: BattleUnit in simulation.units.values():
				if unit != fixture_pilot:
					unit.hp = 0
		simulation.clock += delta
		fixture_pilot.yaw = fixture_pilot.input_state.get("yaw", 0)
		fixture_pilot.pitch = fixture_pilot.input_state.get("pitch", 0)
		if not light_seen:
			simulation.fire(fixture_pilot, "light")
			light_seen = fixture_pilot.fire_at.has("light")
		elif fixture_pilot.input_state.get("aim", false) and not heavy_seen:
			simulation.fire_controls[fixture_pilot.entity_id] = simulation.lob_control(fixture_pilot, Content.weapon(fixture_pilot.character, "heavy"))
			simulation.fire(fixture_pilot, "heavy")
			heavy_seen = fixture_pilot.fire_at.has("heavy")
			heavy_at = elapsed
		elif heavy_seen and elapsed - heavy_at > 1:
			fixture_pilot.hp = 0
		if simulation.units.values().any(func(unit): return unit.cockpit != null):
			push_error("NETWORK_COCKPIT_ALLOCATED_ON_DEDICATED_SERVER")
			get_tree().quit(1)
		return
	selected_slot = "heavy" if reload_seen and pose_seen else "light"
	if selected_slot == "heavy":
		Input.action_press("aim")
	super._physics_process(delta)
	if simulation == null:
		return
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot == null or pilot.cockpit == null:
		return
	if selected_slot == "heavy" and pilot.camera.fov == Content.constants.UNITS[pilot.kind].zoomFov:
		var rig := pilot.cockpit
		zoom_seen = rig.gun.get_children().all(func(child): return child == rig.flash or not child.visible)
	if death_seen and not pilot.cockpit.visible and light_seen and heavy_seen and reload_seen and pose_seen and zoom_seen:
		print("NETWORK_PASS peer=", multiplayer.get_unique_id(), " units=", simulation.units.size())
		print("NETWORK_COCKPIT_PASS feedback=true reload=true pose=true zoom=true death=true")
		Input.action_release("aim")
		Session.stop()
		get_tree().quit()

func _receive_state(state: Dictionary) -> void:
	super._receive_state(state)
	if Session.dedicated or simulation == null:
		return
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot == null or pilot.cockpit == null:
		return
	for event: Dictionary in state.events:
		if event.type != "weapon_fire" or int(event.actor) != pilot.entity_id:
			continue
		if pilot.cockpit.kick != 1:
			push_error("NETWORK_COCKPIT_ACCEPTED_FIRE_FEEDBACK_MISSING")
			get_tree().quit(1)
			return
		if pilot.cockpit.weapons.last_serial != int(event.serial) or not pilot.cockpit.flash.visible or pilot.cockpit.flash_heavy != (event.slot == "heavy"):
			push_error("NETWORK_COCKPIT_WEAPON_SEQUENCE_OR_FLASH_MISSING")
			get_tree().quit(1)
			return
		if event.slot == "light" and not light_seen:
			light_seen = true
			Session.act("reload", "light")
		elif event.slot == "heavy":
			heavy_seen = true
			if not state.fire_control.has("elevation") or pilot.cockpit.control != state.fire_control:
				push_error("NETWORK_COCKPIT_PRIVATE_ELEVATION_MISSING")
				get_tree().quit(1)
	if pilot.reload_at.has("light") and selected_slot == "light":
		reload_seen = true
		pose_seen = pose_seen or pilot.cockpit.gun.transform.origin.distance_to(Vector3(0, 0, pilot.cockpit.profile.baseZ)) > 0.01
	death_seen = death_seen or not pilot.alive()
