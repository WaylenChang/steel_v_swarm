extends "res://tests/run.gd"

const ProbeView = preload("res://tests/campaign_chapter_status.gd").ProbeView

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_hint_style.json")
	var data: Dictionary = Content.read_json("res://data/campaign_hint_style.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Campaign hint layout requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 3,
		"Capture original campaign hint styles")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Campaign hint style resource retains original CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current campaign hint capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original campaign hint input: " + path)
	if failures == 0:
		await _check_programs(capture.programs)
		_check_reentrant()
	print("CAMPAIGN_HINT_STYLE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array) -> void:
	for program: Dictionary in programs:
		var view := ProbeView.new()
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(program.size[0], program.size[1])
		view.play(Content.campaign.prologue, "Continue")
		view.set_process(false)
		await get_tree().process_frame
		_check_state(view, program.states[0], "Pending prologue")
		var loader = view.buffer_loader
		for path: String in view.buffer_rules.assets:
			loader._settle(path, null, true)
		loader._settle("fonts", null, true)
		loader._settle("models", null, true)
		_check_state(view, program.states[1], "Ready prologue")
		view.play([Content.campaign.prologue[0]], "Continue")
		view.set_process(false)
		_check_state(view, program.states[1], "Ready chapter")
		view.dispose()
		view.free()

func _check_state(view: ProbeView, state: Dictionary, description: String) -> void:
	var color: Array = state.color
	var expected := Color(float(color[0]), float(color[1]), float(color[2]))
	_check(view.caption.text == state.text, description + " retains original hint text")
	_check(view.caption.get_theme_font_size("font_size") == int(state.fontSize), description + " retains original hint font size")
	_check(view.buffer_status.get_theme_font_size("font_size") == int(state.statusFontSize), description + " retains original status font size")
	_check(view.caption.get_theme_color("font_color").is_equal_approx(expected), description + " retains original hint color")

func _check_reentrant() -> void:
	var view := ProbeView.new()
	add_child(view)
	var observed := {"replacement": false, "loader": null}
	view.caption.theme_changed.connect(func():
		if observed.replacement or view.buffer_loader == null:
			return
		observed.replacement = true
		observed.loader = view.buffer_loader
		view.play([Content.campaign.prologue[0]], "Continue"))
	view.play(Content.campaign.prologue, "Continue")
	_check(observed.replacement and view.playing and view.buffer_loader == null,
		"A hint theme callback can replace a prologue with a chapter")
	_check(observed.loader != null and not observed.loader.started,
		"Replaced playback cannot start the retired buffer")
	view.dispose()
	view.free()
