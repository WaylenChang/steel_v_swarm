extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip_squad_order.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 7,
		"Capture original PiP squad ordering")
	_check(capture.get("defaultSquadCount") == 1, "Original current squad default is one")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current PiP order capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original PiP order source: " + path)
	if failures == 0:
		_check_programs(capture.programs)
	print("PIP_SQUAD_ORDER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array) -> void:
	var saved_power: Variant = Controls.power_pref
	for program: Dictionary in programs:
		Controls.power_pref = "1" if program.low else "0"
		var battle := BattleSimulation.new()
		add_child(battle)
		battle.set_physics_process(false)
		battle.world = BattleWorld.new()
		battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
		battle.add_child(battle.world)
		var pilot := BattleUnit.new()
		pilot.peer_id = 17
		pilot.kind = "drone"
		pilot.character = "s01"
		pilot.hp = 1
		battle.add_child(pilot)
		var rows: Array = []
		for row: Dictionary in program.rows:
			var is_self := bool(row.get("isSelf", false))
			var actor := pilot if is_self else BattleUnit.new()
			if not is_self:
				battle.add_child(actor)
			actor.entity_id = int(row.id)
			actor.peer_id = int(row.get("pid", 17))
			actor.kind = "drone"
			actor.character = "s01"
			actor.hp = 0 if row.get("dead", false) else 1
			actor.model = MeshInstance3D.new()
			actor.model.mesh = BoxMesh.new()
			actor.model.set_meta("pip_id", actor.entity_id)
			actor.add_child(actor.model)
			battle.units[actor.entity_id] = actor
			rows.append({"id": actor.entity_id, "peer": actor.peer_id, "hero": true, "self": is_self,
				"dead": not actor.alive(), "decoy": false, "lost": false, "index": int(row.get("si", 0))})
		var expected: Array = program.selected.map(func(id): return int(id))
		var component := PipViewState.sources(rows, 17, true, false, "STEEL", bool(program.low), float(program.scale), Content.balance.pip)
		_check(component.map(func(row): return row.id) == expected, "Original source order when squad indices are supplied: " + String(program.name))
		var view := PipView.new()
		add_child(view)
		view.update_view(battle, pilot, "STEEL", float(program.scale))
		view._begin_frame()
		var selected: Array = view.pending_tags.filter(func(tag): return PipView.SOURCE_MASKS.has(tag.mask)).map(func(tag): return tag.root.get_meta("pip_id"))
		_check(selected == expected, "Published squad index reaches the PiP view: " + String(program.name)
			+ " expected=" + str(expected) + " actual=" + str(selected))
		view._end_frame()
		view.free()
		battle.free()
	Controls.power_pref = saved_power
