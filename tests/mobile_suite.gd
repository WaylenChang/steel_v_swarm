extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const ControlsTests = preload("res://tests/controls_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["mobileDevice", "mobilePreferences", "mobileTouchPreferences", "mobileModes", "touchPrograms", "gyroPrograms", "mobileFlight"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original mobile/control oracle: " + key)
			return
	for item: Dictionary in fixtures.mobileDevice:
		h._check(ControlPreferences.device_scheme(item.touch, item.coarse, item.noHover, Vector2(item.width, item.height)) == item.result, "Original touch/hybrid/coarse/screen-size device selection")
	for item: Dictionary in fixtures.mobilePreferences:
		h._check(ControlPreferences.source_bool(item.value) == item.result, "Original strict boolean preference normalization")
	for item: Dictionary in fixtures.mobileTouchPreferences:
		var path := "user://mobile_preferences_fixture.cfg"
		var file := ConfigFile.new()
		for key: String in item.saved:
			file.set_value("input", key, item.saved[key])
		h._check(file.save(path) == OK, "Prepare a native preference fixture without touching player settings")
		var preferences := ControlPreferences.new()
		preferences.configure(Content.balance.mobile)
		preferences.load_save(path)
		Helper.compare(h, preferences.values, item.result, "Original sensitivity clamp, invalid source and legacy screen handedness")
		h._check(preferences.save(path) == OK, "Native control preference persistence")
		var restored := ControlPreferences.new()
		restored.configure(Content.balance.mobile)
		restored.load_save(path)
		Helper.compare(h, restored.values, item.result, "Native persisted controls retain original effective preferences")
		preferences.free()
		restored.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for item: Dictionary in fixtures.mobileModes:
		var preferences := ControlPreferences.new()
		preferences.persist = false
		preferences.configure(Content.balance.mobile)
		preferences.pref = item.pref
		preferences.device_pick = item.device
		for step: Dictionary in item.steps:
			var accepted := true
			match step.kind:
				"pref": accepted = preferences.set_pref(step.value)
				"scheme": accepted = preferences.set_scheme(step.value)
				"room": preferences.set_room(step.value)
			if step.kind != "room":
				h._check(accepted == step.accepted, "Original room restriction rejects individual scheme changes")
			Helper.compare(h, {"pref": preferences.pref, "mode": preferences.mode(), "scheme": preferences.scheme(), "locked": not preferences.room.is_empty()}, step.result, "Original preference/room/scheme layers")
		preferences.free()
	for item: Dictionary in fixtures.touchPrograms:
		var state := TouchState.new(Content.balance.mobile.look)
		state.sensitivity = item.sensitivity
		var events: Array = []
		state.command.connect(func(action, on): events.append({"type": "command", "action": action, "on": on}))
		state.look.connect(func(change): events.append({"type": "look", "change": [change.x, change.y]}))
		state.haptic.connect(func(milliseconds): events.append({"type": "haptic", "milliseconds": milliseconds}))
		for step: Dictionary in item.steps:
			events.clear()
			var id := int(step.get("id", 1))
			var point := vector(step.get("point", [0, 0]))
			match step.kind:
				"lookDown": state.look_down(id, point, step.at)
				"button": state.button_down(step.action, id, point, step.at)
				"stick": state.stick_down(step.movement, id, point, Vector2(70, 70), 70)
				"move": state.move(id, point)
				"up": state.up(id, point, step.at, step.get("cancel", false))
				"tick": state.tick(step.delta, step.at)
				"reset": state.reset()
				"blocked": state.set_blocked(step.value)
			Helper.compare(h, events, step.events, "Original touch dispatch order: " + item.name)
			var held: Dictionary = {}
			for pointer: int in state.held:
				held[str(pointer)] = state.held[pointer]
			var move: Vector2 = state.move_stick.vector
			var look: Vector2 = state.look_stick.vector
			Helper.compare(h, {"axis": [state.axis.x, state.axis.y], "lookId": state.look_id, "fireArm": state.fire_arm,
				"lookFire": state.look_fire, "tapAt": state.tap_at, "movement": [move.x, move.y],
				"lookStick": [look.x, look.y], "held": held, "taps": state.taps.keys()}, step.result, "Original touch state: " + item.name)
			h._check(state.held.size() == step.result.held.size(), "Touch release removes all original held pointers")
	for item: Dictionary in fixtures.gyroPrograms:
		var state := GyroState.new(Content.balance.mobile.look)
		state.sensitivity = item.sensitivity
		state.invert = item.invert
		state.start(item.source, 1000)
		var outputs: Array = []
		var failures: Array = []
		state.look.connect(func(change): outputs.append([change.x, change.y]))
		state.failed.connect(func(reason): failures.append(reason))
		for step: Dictionary in item.steps:
			outputs.clear()
			failures.clear()
			match step.kind:
				"motion": state.motion(vector3(step.rate) * PI / 180.0, step.delta, true, deg_to_rad(item.screenAngle))
				"orient": state.orientation(GyroState.sensor_forward(vector3(step.gravity), vector3(step.magnetic)), step.at)
				"reset": state.reset_basis()
				"watchdog": state.watchdog(step.at)
			Helper.compare(h, outputs, step.outputs, "Original gyro axes/dead-zone/gain/pitch sign: " + item.name)
			h._check((not failures.is_empty()) == bool(step.failed), "Original gyro watchdog and forced-source failure")
			Helper.compare(h, {"active": state.active, "path": state.path, "have": state.have, "raw": [state.raw.x, state.raw.y],
				"accumulated": [state.accumulated.x, state.accumulated.y], "events": state.events, "usable": state.usable}, step.result, "Original gyro baseline/jump/wrap/fallback: " + item.name)
	h._check(GyroState.sensor_forward(Vector3.ZERO, Vector3.ONE) == Vector3.ZERO, "Missing gravity never fabricates a sensor orientation")
	h._check(GyroState.sensor_forward(Vector3.DOWN, Vector3.UP) == Vector3.ZERO, "Parallel magnetic/gravity readings cannot establish heading")
	for item: Dictionary in fixtures.mobileFlight:
		var motion := vector(item.motion)
		var direction := InputRules.movement_basis(item.yaw, item.pitch, true, item.level) * Vector3(motion.x, 0, motion.y)
		h._check(direction.distance_to(vector3(item.result)) < 0.00001, "Original level-move flight preserves horizontal strafe and pitch-relative forward motion")
	var simulation: BattleSimulation = ControlsTests.context(h)
	var unit: BattleUnit = ControlsTests.actor(simulation, "t01")
	for value: Variant in [true, false, "true", 1, {}, Vector2.ONE]:
		simulation.submit_input(1, {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0, "level_move": value})
		h._check(bool(unit.input_state.level_move) == (value is bool and value), "Only an explicit input boolean enables authority level-move")
	unit.hp = 0
	simulation.submit_input(1, {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0, "fire": true})
	h._check(not unit.input_state.fire, "Dead input cannot leave a live firing request queued for respawn")
	simulation.free()

static func vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
