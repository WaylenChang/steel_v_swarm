extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_nearest.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 18
		and capture.get("groupCases") is Array and capture.groupCases.size() == 6
		and capture.get("edgeCases") is Array and capture.edgeCases.size() == 5,
		"Capture original spectator nearest-target programs")
	if failures > 0:
		_finish_nearest()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Spectator nearest capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Spectator nearest source identity: " + path)
	_check(Content.balance.spectator.camera == capture.cameraRules, "Spectator camera settings match the captured source")
	if failures == 0:
		_check_cases(capture.cases + capture.groupCases)
		_check_edge_cases(capture.edgeCases)
	_finish_nearest()

func _check_cases(cases: Array) -> void:
	for sample: Dictionary in cases:
		failure_scope = "spectator_nearest_" + String(sample.name) + "_" + String(sample.action)
		var state := SpectatorState.new()
		state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
		state.position = Vector3(sample.camera[0], sample.camera[1], sample.camera[2])
		state.anchor_ok = true
		var rows: Array = []
		for row: Dictionary in sample.rows:
			var item := row.duplicate(true)
			item.position = Vector3(row.position[0], row.position[1], row.position[2])
			rows.append(item)
		for reference: Dictionary in sample.distances:
			var actor: Dictionary = rows.filter(func(row): return row.pid == reference.pid)[0]
			var bytes := PackedByteArray()
			bytes.resize(8)
			bytes.encode_double(0, SpectatorState._distance_squared(state.position, actor.position))
			_check(bytes.hex_encode() == reference.bits, "Squared distance retains original double operation order")
		var messages: Array = []
		state.notice.connect(func(message: String): messages.append(message))
		if sample.action == "follow":
			state.follow(0, rows)
		else:
			state.select_mode("fpv", rows)
		var roster: Array = state.roster(rows).map(func(row): return row.pid)
		_check(state.pid == sample.result.pid, "Original nearest player wins without an early Float32 distance tie")
		_check(state.mode == sample.result.mode and state.pitch == sample.result.pitch,
			"Nearest selection enters the original first-person view")
		_check(state.anchor_ok == sample.result.anchorOk, "Changing target invalidates the old follow anchor")
		_check(roster == sample.result.roster, "Original filtered and sorted roster keeps stable tie order")
		_check(messages == sample.result.messages, "Nearest selection retains the original notice")
		if sample.name == "xy-near-tie":
			var first: Vector3 = rows[3].position
			var second: Vector3 = rows[0].position
			_check(state.position.distance_squared_to(first) == state.position.distance_squared_to(second),
				"The native Float32 squared-distance boundary really collapses this source distinction")

func _check_edge_cases(cases: Array) -> void:
	for sample: Dictionary in cases:
		failure_scope = "spectator_nearest_" + String(sample.name)
		var state := SpectatorState.new()
		state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
		state.position = Vector3.ZERO
		var rows: Array = []
		for row: Dictionary in sample.rows:
			var actor := row.duplicate(true)
			actor.position = Vector3(_number(row.position[0]), _number(row.position[1]), _number(row.position[2]))
			rows.append(actor)
		for reference: Dictionary in sample.distances:
			var actor: Dictionary = rows.filter(func(row): return row.pid == reference.pid)[0]
			var distance := SpectatorState._distance_squared(state.position, actor.position)
			var kind := "nan" if is_nan(distance) else "finite" if is_finite(distance) else "infinity"
			_check(kind == reference.kind, "Non-finite squared distance retains the original result kind")
		state.follow(0, rows)
		_check(state.pid == sample.pid, "Non-finite comparisons retain the original stable reduction order")

func _number(value: Variant) -> float:
	if value is String:
		if value == "NaN":
			return NAN
		if value == "Infinity":
			return INF
	return float(value)

func _finish_nearest() -> void:
	print("SPECTATOR_NEAREST assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
