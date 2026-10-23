extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const SessionScript = preload("res://scripts/session.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("deploymentPrograms") or not fixtures.has("roomEnvironmentResolved") or not fixtures.has("roomSeasonalWeights"):
		h._check(false, "Regenerate original deployment/environment-selection references")
		return
	for program: Dictionary in fixtures.deploymentPrograms:
		var preferences := DeploymentPreferences.new()
		preferences.values = program.initial.duplicate(true)
		var super_mode := false
		var current_size := float(Content.constants.TEAM.DEFAULT)
		for frame: Dictionary in program.frames:
			var operation: Array = frame.operation
			match operation[0]:
				"mode":
					super_mode = operation[1]
					var selected := preferences.enter(super_mode, current_size)
					current_size = float(selected.team_size)
					for key: String in ["team_size", "room_name", "venue_id", "env", "bot_difficulty"]:
						Helper.compare(h, selected[key], frame.selected[key], "Original mode preference restore, inheritance, invalid environment values and qualified map recall: " + key)
				"team": preferences.remember_field("teamSize", "superTeamSize", operation[1], super_mode)
				"room": preferences.remember_field("roomName", "superRoomName", DeploymentPreferences.trim(operation[1]), super_mode)
				"env": preferences.remember_field("env", "superEnv", operation[1], super_mode)
				"name": preferences.remember_name(operation[1])
				"character": preferences.remember_character(operation[1], operation[2] if operation[2] != null else "")
				"patch": preferences.patch(operation[1])
			Helper.compare(h, preferences.values, frame.values, "Original shallow preference merge preserves unknown keys and mode-specific namespaces")
			h._check(preferences.player_name == frame.playerName, "Original player-name trim/fallback storage remains separate from server sanitization")
			if operation[0] == "team":
				current_size = float(operation[1])
	for fixture: Dictionary in fixtures.roomEnvironmentResolved:
		var cursor := {"value": 0}
		var next_random := func() -> float:
			var result := float(fixture.rolls[int(cursor.value) % fixture.rolls.size()])
			cursor.value += 1
			return result
		var result := WeatherRules.resolve_environment(fixture.env, next_random)
		Helper.compare(h, result, fixture.result, "Original room environment resolution and season/lunar/time/weather sampling order")
		h._check(int(cursor.value) == int(fixture.draws), "Fixed choices do not consume room random draws; invalid lunar values draw exactly once")
	for fixture: Dictionary in fixtures.roomSeasonalWeights:
		h._check(WeatherRules.pick_seasonal_weather(fixture.season, fixture.roll) == fixture.result, "Original seasonal weather weights preserve strict boundary and terminal fallback")
	_storage(h)

static func _storage(h: Node) -> void:
	var saved := DeploymentPreferences.new()
	saved.persist = true
	saved.path = "user://deployment-fixture-%d.cfg" % Time.get_ticks_usec()
	h._check(saved.load_save() == OK and saved.values.is_empty(), "Missing deployment profile starts with source defaults")
	saved.patch({"teamSize": 2, "superTeamSize": 5, "env": {"season": "winter"}, "lastChar": null, "futureField": {"v": 7}})
	saved.remember_name("  Pilot_1  ")
	var restored := DeploymentPreferences.new()
	restored.persist = true
	restored.path = saved.path
	h._check(restored.load_save() == OK and restored.values == saved.values and restored.player_name == "Pilot_1", "Native ConfigFile round trip retains separate mode preferences, null choices and player name")
	restored.patch({"anotherProcess": "new"})
	restored.remember_name("Pilot_2")
	saved.patch({"teamSize": 3})
	h._check(saved.values.get("anotherProcess") == "new" and saved.player_name == "Pilot_2", "Preference patches reread current storage instead of overwriting another process's unrelated fields/name")
	h._check(restored.load_save() == OK and restored.values == saved.values, "Separate preference objects observe each other's committed top-level patches")
	var session := SessionScript.new()
	h.add_child(session)
	session.deployment = restored
	session.stop()
	h._check(session.deployment.values == saved.values and session.deployment.player_name == "Pilot_2", "Transport/seat shutdown does not erase independent deployment preferences")
	session.free()
	h._check(DirAccess.remove_absolute(ProjectSettings.globalize_path(saved.path)) == OK, "Remove isolated deployment fixture file")
