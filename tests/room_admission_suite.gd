extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const SessionScript = preload("res://scripts/session.gd")

class ProgressProbe extends CampaignProgress:
	var writes := 0
	func mark_cleared(_side: String, _id: String) -> Error:
		writes += 1
		return OK

class ResultProbe extends "res://scripts/main.gd":
	var overlays := 0
	func _ready() -> void:
		add_child(room_world_resources)
		room_world_prebuild.resources = room_world_resources
		add_child(room_world_prebuild)
	func _overlay(_panel: Control, _shown: bool) -> void:
		overlays += 1

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("roomAdmission"):
		h._check(false, "Regenerate original room spectator/player admission")
		return
	for item: Dictionary in fixtures.roomAdmission:
		var seats := RoomSeats.new()
		for index in item.definitions.size():
			var member: Dictionary = item.definitions[index]
			seats.add(42 + index, 100 + index, "fixture-" + str(index), str(member.side) if member.side != null else "", member.mode)
			seats.members[42 + index].connected = member.connected
		for index in int(item.bots):
			seats.bots[-index - 1] = {"side": "STEEL", "character": "", "name": "fixture"}
		var error := seats.admission_error(item.mode, int(item.capacity), item.superMode)
		h._check(error == item.errorKey and error.is_empty() == item.accepted, "Original held player/global bot capacity, SUPER policy and spectator bypass: " + str(item.phase))
		if item.accepted:
			var mode := RoomSeats.join_mode(item.mode)
			h._check(seats.add(1000, 2000, "new-opaque-token", "", mode), "Allocate a fresh logical observer/player seat")
			var member: Dictionary = seats.members[1000]
			Helper.compare(h, {"mode": member.mode, "side": member.side, "ready": member.ready, "loaded": member.loaded, "connected": member.connected},
				item.result, "Original admitted clients have no faction/hero and independent readiness/loading flags")
			if mode == "spectator":
				h._check(not seats.choose_side(1000, "STEEL", int(item.capacity), item.superMode), "Spectators cannot acquire a player faction")
				h._check(not seats.choose_character(1000, "t01", Content.heroes), "Spectators cannot choose a player character")
				var ready := seats.all_ready()
				var loaded := seats.all_loaded()
				seats.set_ready(1000, true)
				seats.set_loaded(1000)
				h._check(seats.all_ready() == ready and seats.all_loaded() == loaded, "Spectator flags cannot satisfy or block launch gates")
				var sided := 0
				for record: Dictionary in seats.members.values():
					if record.mode == "player" and not String(record.side).is_empty():
						record.ready = true
						record.loaded = true
						sided += 1
				seats.members[1000].ready = false
				seats.members[1000].loaded = false
				h._check(seats.all_ready() == (sided > 0) and seats.all_loaded() == (sided > 0), "An unready/unloaded observer never delays otherwise ready sided humans")
	_observer_results(h)
	_campaign_roster(h)

static func _campaign_roster(h: Node) -> void:
	var pilot: String = Content.campaign.chapters[0].STEEL.heroes[0]
	var session := SessionScript.new()
	h.add_child(session)
	session.active = true
	session.config = CampaignRules.settings(0, "STEEL", pilot)
	session.seats.add(42, 1000, "campaign-player", "STEEL", "player", pilot)
	session.seats.add(43, 1001, "campaign-spectator", "", "spectator", "")
	session.seats.set_ready(42, true)
	session.roster = [{"peer": 42, "side": "STEEL", "character": pilot, "mode": "player", "bot": false},
		{"peer": 43, "side": "", "character": "", "mode": "spectator", "bot": false}]
	session.start_battle()
	h._check(session.phase == "loading" and session.started, "A spectator does not prevent the authored single-player campaign from preparing")
	var observers: Array = session.roster.filter(func(member): return member.get("mode") == "spectator")
	h._check(observers.size() == 1 and int(observers[0].peer) == 43, "Authored roster replacement retains observer identity for world preparation and reconnect")
	var expected := CampaignRules.roster(0, "STEEL", pilot, 42)
	h._check(session.roster.size() == expected.size() + 1, "Spectator admission adds no fabricated campaign actor")
	session.free()

static func _observer_results(h: Node) -> void:
	var saved := {"config": Session.config, "mode": Session.chosen_mode, "side": Session.chosen_side, "dedicated": Session.dedicated}
	Session.config = {"campaign": {"side": "STEEL", "index": 0, "chapter": "ch1"}}
	Session.dedicated = false
	var probe := ResultProbe.new()
	h.add_child(probe)
	probe.set_process(false)
	probe.set_physics_process(false)
	probe.campaign_dialogue = CampaignDialogue.new()
	probe.add_child(probe.campaign_dialogue)
	probe.notice = Label.new()
	probe.add_child(probe.notice)
	var progress := ProgressProbe.new()
	probe.campaign_progress = progress
	for state: Array in [["spectator", ""], ["player", ""], ["spectator", "STEEL"]]:
		Session.chosen_mode = state[0]
		Session.chosen_side = state[1]
		h._check(not probe._campaign_participant(), "Only the authored campaign player owns local campaign progression")
		probe._result("STEEL")
		h._check(progress.writes == 0 and not probe.campaign_result_saved and probe.overlays > 0,
			"Observing a winning campaign never writes chapter unlocks or opens personal campaign results")
	Session.config = saved.config
	Session.chosen_mode = saved.mode
	Session.chosen_side = saved.side
	Session.dedicated = saved.dedicated
	probe.free()
