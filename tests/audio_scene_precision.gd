extends Node

var assertions := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _words(part: Dictionary) -> PackedFloat64Array:
	return Marshalls.base64_to_raw(part.data).to_float64_array()

func _entities(rows: Array) -> Array:
	var entities: Array = rows.duplicate(true)
	for entity: Dictionary in entities:
		var words := _words(entity.mesh.position)
		entity.mesh.position = {"x": words[0], "y": words[1], "z": words[2]}
		if entity.loco != null:
			words = _words(entity.loco.w)
			entity.loco.w = {"walk": words[0], "run": words[1], "air": words[2]}
	return entities

func _ready() -> void:
	var captured: Dictionary = Content.read_json("res://tests/fixtures/audio_scene_precision.json")
	_check(captured.get("scope") == "original-audio-scene-precision", "Load the original scoped audio scene oracle")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in captured.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == captured.source.inputs[path], "Current precision producer: " + path)
	for path: String in captured.source.sourceInputs:
		_check(provenance.inputs.get(path) == captured.source.sourceInputs[path], "Accepted original audio scene source: " + path)
	if failures > 0:
		get_tree().quit(1)
		return
	var scene := AudioSceneRules.new()
	scene.configure(Content.balance.audio, Content.heroes)
	_check(scene.rules.cell == captured.cell, "Reuse the original collision-grid cell size")
	_check(scene.characters.size() == captured.characters.size(), "Retain the complete original character roster")
	for id: String in captured.characters:
		_check(scene.characters[id].get("visual", {}).get("flight", "") == captured.characters[id].visual.get("flight", ""),
			"Original character flight profile: " + id)
	for index in range(captured.programs.movement.size()):
		var program: Dictionary = captured.programs.movement[index]
		var origin := _words(program.camera.position)
		var right := _words(program.camera.right)
		var camera := Transform3D.IDENTITY
		camera.origin = Vector3(origin[0], origin[1], origin[2])
		camera.basis.x = Vector3(right[0], right[1], right[2])
		var own: Variant = null
		if program.ownWeights != null:
			var weights := _words(program.ownWeights)
			own = {"walk": weights[0], "run": weights[1]}
		var queries: Array = []
		var terrain := func(x: float, z: float) -> int:
			queries.append_array([x, z])
			return 1 if x >= 0 and z <= 0 else 2
		var plans := scene.movement(_entities(program.entities), camera, own, terrain, 1, program.selfBed, program.low)
		var expected: Array = captured.expected.movement[index].calls
		var expected_queries: Variant = captured.expected.movement[index].queries
		_check(queries.is_empty() if expected_queries is Array else PackedFloat64Array(queries).to_byte_array() == Marshalls.base64_to_raw(expected_queries.data),
			"Only the winning remote stomp source queries its original double point: " + program.name)
		_check(plans.size() == expected.size(), "Source category delivery: " + program.name)
		for category in range(mini(plans.size(), expected.size())):
			var plan: Dictionary = plans[category]
			_check(plan.category == expected[category].category, "Preserve original category order")
			var values := PackedFloat64Array([plan.gain, plan.pan, plan.rate, plan.wet])
			_check(values.to_byte_array() == Marshalls.base64_to_raw(expected[category].parameters.data),
				"Original double range, nearest-source, gain and pan words: " + program.name + "/" + plan.category)
	var query := SourceBlockerQuery.new()
	for cell: Dictionary in captured.programs.cells:
		var indices: Array[int] = []
		for row: Dictionary in cell.rows:
			indices.append(query.entries.size())
			query.entries.append(row)
		query.grid[Vector2i(cell.cell[0], cell.cell[1])] = indices
	for index in range(captured.programs.positions.size()):
		var point := _words(captured.programs.positions[index])
		var result := scene.density(query, Vector2(point[0], point[1]))
		_check(PackedFloat64Array([result.bld, result.tree]).to_byte_array() == Marshalls.base64_to_raw(captured.expected.density[index].data),
			"Original double cell interpolation at native coordinate boundaries: " + str(index))
	query.grid.clear()
	var retained := scene.density(query, Vector2(32, 32))
	_check(PackedFloat64Array([retained.bld, retained.tree]).to_byte_array() == Marshalls.base64_to_raw(captured.expected.retained.data),
		"Preserve the original density cache after grid changes")
	for index in range(captured.programs.places.size()):
		var program: Dictionary = captured.programs.places[index]
		var point := _words(program.position)
		var result := scene.place(Vector2(point[0], point[1]), program.ground, program.tunnel,
			{"bld": .25, "tree": .75}, _entities(program.entities))
		var expected: Dictionary = captured.expected.places[index]
		_check(is_inf(result.camp) == expected.unboundedCamp, "No static living source retains infinite camp distance")
		var values := PackedFloat64Array([result.tunnel, result.water, result.swamp,
			0.0 if expected.unboundedCamp else result.camp, result.urban, result.forest])
		_check(values.to_byte_array() == Marshalls.base64_to_raw(expected.parameters.data),
			"Original planar hypot and environment branch words: " + str(index))
	print("AUDIO_SCENE_PRECISION assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
