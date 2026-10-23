extends RefCounted

const SessionScript = preload("res://scripts/session.gd")
const Helper = preload("res://tests/status_suite.gd")
const Admission = preload("res://tests/room_admission_suite.gd")

class RestartSession extends SessionScript:
	var roll := 0.75
	var draws := 0
	var worlds_available := true
	func _room_roll() -> float:
		draws += 1
		return roll
	func _recipe_worlds_available(_settings: Dictionary) -> bool:
		return worlds_available

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("quickRestartPrograms"):
		h._check(false, "Regenerate original full-session capture and quick-restart references")
		return
	for program: Dictionary in fixtures.quickRestartPrograms:
		var preferences := DeploymentPreferences.new()
		preferences.values = {"unrelated": "retained"}
		for frame: Dictionary in program.frames:
			preferences.record_match(program.settings, frame.players, 1)
			var actual := preferences.values.duplicate(true)
			if actual.get("lastSession") is Dictionary:
				actual.lastSession.erase("native")
			Helper.compare(h, actual, frame.preferences, "Original recordGameSession eligibility, resolved roles, ordered bots and exact locked battle configuration")
		var record: Dictionary = preferences.values.lastSession.duplicate(true)
		var recipe := MatchRecipe.prepare(record)
		h._check(not recipe.is_empty(), "A supported original match recipe remains replayable")
		if recipe.is_empty():
			continue
		Helper.compare(h, recipe.player, program.record.player, "Original quick-restart player selection")
		Helper.compare(h, recipe.bots, program.record.bots, "Original ordered saved-bot deployment")
		h._check(not recipe.settings.is_public and recipe.settings.ctrl == program.creation.ctrl and recipe.settings.team_size == program.creation.teamSize and recipe.settings.room_name == program.creation.roomName, "Original private fresh room reuses recorded size, name and controls")
		for roll in [0.25, 0.75]:
			var session := RestartSession.new()
			h.add_child(session)
			session.roll = roll
			session.chosen_name = "Fixture_User"
			session.deployment.values = preferences.values.duplicate(true)
			var error := session.quick_restart()
			h._check(error == OK and session.phase == "loading" and session.started and session.simulation == null and not session.world_prepared, "Quick restart shares normal room readiness/preparation without early authority population " + str(program.kind) + " error=" + error_string(error))
			if error == OK:
				var member: Dictionary = session.seats.members[1]
				h._check(member.side == recipe.player.side and member.character == recipe.player.ch and member.ready and not member.loaded, "Original quick-start pickSide/pickChar/ready sequence")
				var bots: Array = []
				for player: int in session.seats.bots:
					var bot: Dictionary = session.seats.bots[player]
					bots.append({"side": bot.side, "ch": bot.character if not String(bot.character).is_empty() else null})
				Helper.compare(h, bots, recipe.bots, "Original addBot/setBotChar ordering preserves exact full saved roster")
				var expected_env: Dictionary = program.creation.battleConfig.env.duplicate(true)
				expected_env["bot_difficulty"] = program.creation.botDiff
				Helper.compare(h, session.config.env, expected_env, "Saved concrete environment/lunar day survives recreation without extra random draws")
				h._check(session.draws == 1 and not session.config.is_public, "Only source base-assignment roll consumes a room float at fixed-environment restart")
				var before := bool(recipe.settings.campaign.swapped) if recipe.settings.has("campaign") else bool(recipe.settings.swapped)
				var after := bool(session.config.campaign.swapped) if session.config.has("campaign") else bool(session.config.swapped)
				h._check(after == (before != (roll < 0.5)), "Fresh-room base swap is relative to the saved assignment")
				h._check(not session.story_mode(), "Authored arena replay retains siege geometry without personal campaign context")
			session.stop()
			session.free()
		var invalid := record.duplicate(true)
		invalid.native.template = "stale-template"
		h._check(MatchRecipe.prepare(invalid).is_empty(), "Changed imported geometry cannot silently replace a saved map")
		invalid = record.duplicate(true)
		invalid.battleConfig.bases.STEEL[0] += 1.0
		h._check(MatchRecipe.prepare(invalid).is_empty(), "Modified saved geometry cannot be ignored in favor of another map")
		invalid = record.duplicate(true)
		invalid.bots.append({"side": "invalid", "ch": null})
		h._check(MatchRecipe.prepare(invalid).is_empty(), "Malformed bot recipes reject before a room is created")
		invalid = record.duplicate(true)
		invalid.player.ch = "missing-character"
		h._check(MatchRecipe.prepare(invalid).is_empty(), "Unavailable saved heroes cannot turn into fabricated random substitutes")
		if not record.native.settings.has("campaign"):
			var moved := record.duplicate(true)
			moved.native.settings.map_index = -100
			h._check(not MatchRecipe.prepare(moved).is_empty(), "Stable qualified map IDs recover from changed menu indices")
			moved.native.map_id = "missing-imported-venue"
			h._check(MatchRecipe.prepare(moved).is_empty(), "Missing stable map IDs cannot clamp to a different preset")
		var unavailable := RestartSession.new()
		h.add_child(unavailable)
		unavailable.worlds_available = false
		unavailable.deployment.values = preferences.values.duplicate(true)
		h._check(not unavailable.can_quick_restart() and unavailable.quick_restart() == ERR_UNAVAILABLE and not unavailable.active, "Missing native world captures reject before transport/seat creation")
		unavailable.free()
		_storage(h, record)
	_story_result(h)

static func _storage(h: Node, record: Dictionary) -> void:
	var saved := DeploymentPreferences.new()
	saved.persist = true
	saved.path = "user://quick-restart-fixture-%d.cfg" % Time.get_ticks_usec()
	saved.patch({"lastSession": record})
	var restored := DeploymentPreferences.new()
	restored.persist = true
	restored.path = saved.path
	h._check(restored.load_save() == OK and not restored.restart_recipe().is_empty(), "Full geometry/role/environment recipe remains valid after native file round trip")
	h._check(DirAccess.remove_absolute(ProjectSettings.globalize_path(saved.path)) == OK, "Remove isolated saved-match fixture file")

static func _story_result(h: Node) -> void:
	var old_config: Dictionary = Session.config
	var old_mode: String = Session.chosen_mode
	var old_side: String = Session.chosen_side
	var old_dedicated: bool = Session.dedicated
	Session.config = {"campaign": {"index": 0, "chapter": CampaignRules.chapter(0).id, "side": "STEEL"}, "quick_restart": true}
	Session.chosen_mode = "player"
	Session.chosen_side = "STEEL"
	Session.dedicated = false
	var view := Admission.ResultProbe.new()
	h.add_child(view)
	var progress := Admission.ProgressProbe.new()
	view.campaign_progress = progress
	view.notice = Label.new()
	view.add_child(view.notice)
	view.campaign_dialogue = CampaignDialogue.new()
	view.add_child(view.campaign_dialogue)
	view._result("STEEL")
	h._check(progress.writes == 0 and view.overlays == 1, "A quick replay of a story arena cannot unlock personal chapters or route into story results")
	view.free()
	Session.config = old_config
	Session.chosen_mode = old_mode
	Session.chosen_side = old_side
	Session.dedicated = old_dedicated
