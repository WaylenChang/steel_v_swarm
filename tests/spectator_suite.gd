extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not Content.balance.has("spectator") or not fixtures.has("spectatorPrograms") or not fixtures.has("spectatorHud"):
		h._check(false, "Regenerate original spectator methods and camera profiles")
		return
	h._check(SpectatorState.source_pid(-12) == "b12" and SpectatorState.source_pid(12) == "12", "Native logical player IDs retain source bot identity ordering")
	for item: Dictionary in fixtures.spectatorHud:
		var state := SpectatorState.new()
		state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
		state.mode = item.view
		state.pid = item.pid
		var actual: Variant = state.hud(item.actors, item.side)
		if item.result == null:
			h._check(actual == null, "Original spectator HUD rejects a playing faction")
			continue
		Helper.compare(h, actual, item.result, "Original spectator HUD shares weapon/ability and upgrade display contract")
		if item.result.follow:
			for key: String in ["lift", "mobil", "morph"]:
				h._check(actual[key] == null, "Remote spectator resource stays unknown: " + key)
			for key: String in ["light", "heavy"]:
				h._check(actual[key].ammo == null, "Remote spectator magazines stay unknown")
	for program: Dictionary in fixtures.spectatorPrograms:
		var state := SpectatorState.new()
		var environment := {"surface": float(program.initial.get("surface", 0)), "ceiling": float(program.initial.get("ceiling", 10000)), "hit": null}
		state.configure(Content.balance.spectator, Vector3.ZERO, environment.ceiling, 68)
		var actors: Dictionary = {}
		var messages: Array = []
		state.notice.connect(func(value): messages.append(value))
		for frame: Dictionary in program.steps:
			messages.clear()
			var operation: Dictionary = frame.operation
			if operation.has("add"):
				var actor: Dictionary = operation.add.duplicate(true)
				actor.position = h._reference_vector(actor.position)
				actor.visible = actor.get("visible", true)
				actors[actor.pid] = actor
			if operation.has("update"):
				var actor: Dictionary = actors[operation.update.pid]
				for key: String in operation.update:
					actor[key] = h._reference_vector(operation.update[key]) if key == "position" else operation.update[key]
			if operation.has("remove"):
				actors.erase(operation.remove)
			if operation.has("position"):
				state.position = h._reference_vector(operation.position)
			for key: String in ["surface", "ceiling", "hit"]:
				if operation.has(key):
					environment[key] = operation[key]
			if operation.has("yaw"):
				state.yaw = operation.yaw
			if operation.has("pitch"):
				state.pitch = operation.pitch
			if operation.has("mode"):
				state.select_mode(operation.mode, actors.values())
			if operation.has("follow"):
				state.follow(operation.follow, actors.values())
			if operation.get("cycle", false):
				state.cycle(actors.values())
			if operation.has("zoom"):
				state.zoom(operation.zoom)
			if operation.has("delta"):
				var surface := func(_point: Vector3) -> float: return environment.surface
				var collision := func(start: Vector3, end: Vector3) -> Dictionary:
					return {} if environment.hit == null else {"position": start + start.direction_to(end) * float(environment.hit)}
				var pull := func(start: Vector3, end: Vector3) -> Vector3: return CameraPose._pull(start, end, collision, surface)
				var visibility := state.advance(operation.delta, actors.values(), operation.get("axis", {"f": 0, "r": 0, "mag": 0, "boost": false}),
					operation.get("up", false), operation.get("down", false) or operation.get("ctrl", false), surface, environment.ceiling, pull)
				for command: Dictionary in visibility:
					command.actor.visible = command.visible
			var visible := {}
			var roster: Array = []
			for actor: Dictionary in actors.values():
				visible[actor.pid] = actor.visible
			for actor: Dictionary in state.roster(actors.values()):
				roster.append(actor.pid)
			Helper.compare(h, {"mode": state.mode, "pid": state.pid, "position": _array(state.position), "camera": _array(state.camera_position),
				"yaw": state.yaw, "pitch": state.pitch, "fov": state.fov, "cameraFov": state.camera_fov, "anchor": _array(state.anchor),
				"anchorOk": state.anchor_ok, "followYaw": state.follow_yaw, "hidden": state.hidden.get("pid", ""),
				"roster": roster, "visible": visible, "messages": messages}, frame.result, "Original spectator trace: " + str(program.label))

static func _array(point: Vector3) -> Array:
	return [point.x, point.y, point.z]
