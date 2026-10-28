extends "res://tests/pip_native.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip_publication.json")
	_check(capture.get("formatVersion") == 1 and capture.get("steps") is Array and capture.steps.size() == 11,
		"Capture original decoy selection across authority and snapshot boundaries")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current PiP publication capture input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original PiP publication source identity: " + path)
	if failures == 0:
		_check_publication(capture.steps)
	print("PIP_PUBLICATION assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_publication(steps: Array) -> void:
	var saved_power: Variant = Controls.power_pref
	Controls.power_pref = "0"
	var battle := BattleSimulation.new()
	add_child(battle)
	battle.set_physics_process(false)
	battle.world = BattleWorld.new()
	battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
	battle.add_child(battle.world)
	var pilot := BattleUnit.new()
	pilot.peer_id = 17
	pilot.kind = "robot"
	pilot.hp = 1
	battle.add_child(pilot)
	var view := PipView.new()
	add_child(view)
	var actors := {}
	for step: Dictionary in steps:
		match str(step.action):
			"spawn-7", "spawn-9":
				var id := 7 if step.action == "spawn-7" else 9
				var actor := BattleUnit.new()
				actor.entity_id = id
				actor.peer_id = 17
				actor.side = "STEEL"
				actor.kind = "decoy"
				actor.hp = 1
				actor.special = {"role": "carrier", "owner_peer": 17}
				battle.add_child(actor)
				actor.model = MeshInstance3D.new()
				actor.model.mesh = BoxMesh.new()
				actor.model.set_meta("pip_id", id)
				actor.add_child(actor.model)
				battle.units[id] = actor
				actors[id] = actor
			"lose-7": actors[7].special.lost = true
			"recover-7": actors[7].special.lost = false
			"remove-7":
				battle.units.erase(7)
				actors[7].queue_free()
				actors.erase(7)
		var authority_rows: Array = []
		for actor: BattleUnit in battle.units.values():
			authority_rows.append({"id": actor.entity_id, "lost": bool(actor.special.get("lost", false))})
		var expected_authority: Array = step.authority.map(func(row): return {"id": int(row.id), "lost": bool(row.lost)})
		_check(authority_rows == expected_authority, "Native authority follows the controlled source program: " + str(step.action))
		if str(step.action).begins_with("publish-") or step.action == "snapshot-empty":
			var rows: Array = step.published.map(func(row): return {"id": int(row.id)})
			# The test isolates presentation membership from unrelated damage effects.
			var dedicated := Session.dedicated
			Session.dedicated = true
			battle.apply_presentation_view({"units": rows, "clock": 0.0, "events": []})
			Session.dedicated = dedicated
		if step.action == "snapshot-empty":
			view.update_view(battle, pilot, "STEEL")
		view._begin_frame()
		var selected: Array = view.pending_tags.map(func(tag): return tag.root.get_meta("pip_id"))
		var expected: Array = step.selected.map(func(id): return int(id))
		_check(selected == expected, "PiP selection waits for the received snapshot: " + str(step.action)
			+ " expected=" + str(expected) + " actual=" + str(selected))
		view._end_frame()
	view.free()
	battle.free()
	Controls.power_pref = saved_power
