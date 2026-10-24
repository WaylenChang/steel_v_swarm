extends Node

const Body = preload("res://scripts/dialogue_transcript_body.gd")

var assertions := 0
var failures: Array[String] = []

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_body.json")
	var data: Dictionary = Content.read_json("res://data/dialogue_body.json")
	_check(data == {"formatVersion": capture.formatVersion, "source": capture.source, "rules": capture.rules}, "Native transcript body retains captured CSS rules")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Transcript body capture generator is current")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Transcript body retains original CSS identity")
	var image := Image.create_empty(3, 6, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	for program: Dictionary in capture.programs:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(program.viewport.width, program.viewport.height)
		viewport.disable_3d = true
		add_child(viewport)
		var host := VBoxContainer.new()
		host.size.x = program.width
		viewport.add_child(host)
		var body := Body.new()
		host.add_child(body)
		body.add_portrait(texture, false)
		body.add_portrait(texture, true)
		for height: float in program.heights:
			var row := Control.new()
			row.custom_minimum_size.y = height
			body.rows.add_child(row)
		for frame in range(6):
			await get_tree().process_frame
		var expected: Dictionary = program.state
		_check(body.script_scroll.size == Vector2(expected.script[2], expected.script[3]), "Original visible transcript scrolling box: " + str(program.viewport) + " " + str(program.heights) + " actual=" + str(body.script_scroll.size))
		for portrait in body.portraits:
			_check(portrait.visible == bool(expected.artVisible), "Original 720/721 viewport portrait boundary")
			if portrait.visible:
				_check(portrait.size == Vector2(150, 300) and portrait.position == Vector2(90 if portrait.flip_h else 0, float(expected.body[3]) - 300),
					"Absolute left/right portraits do not affect transcript flow or height")
		for index in range(program.heights.size()):
			var row: Control = body.rows.get_child(index)
			var rectangle := row.get_global_rect()
			var actual := rectangle.position - body.global_position
			# Original unrevealed rows translate their visuals six pixels; compare their layout boxes here.
			var target := Vector2(expected.rows[index][0], expected.rows[index][1] - 6)
			_check(actual == target and rectangle.size == Vector2(expected.rows[index][2], expected.rows[index][3]),
				"Original padding, gap and scrollbar-reserved row box: actual=" + str(Rect2(actual, rectangle.size)) + " expected=" + str(expected.rows[index]))
		viewport.free()
	var previous := SubViewport.new()
	previous.size = Vector2i(360, 640)
	add_child(previous)
	var host := VBoxContainer.new()
	host.size.x = 240
	previous.add_child(host)
	var body := Body.new()
	host.add_child(body)
	var row := Control.new()
	row.custom_minimum_size.y = 500
	body.rows.add_child(row)
	previous.remove_child(host)
	_check(not previous.size_changed.is_connected(body._viewport_changed), "Detached transcript releases its previous viewport listener")
	previous.size = Vector2i(720, 900)
	var destination := SubViewport.new()
	destination.size = Vector2i(721, 641)
	add_child(destination)
	destination.add_child(host)
	for frame in range(6):
		await get_tree().process_frame
	_check(destination.size_changed.is_connected(body._viewport_changed) and body.script_scroll.size.y == 269.21875,
		"Reattached transcript adopts its new viewport and source fractional height")
	previous.free()
	destination.free()
	print("DIALOGUE_BODY assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
