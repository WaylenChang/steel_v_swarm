extends "res://tests/run.gd"

const Buffer = preload("res://scripts/campaign_buffer.gd")

class ControlledBuffer extends Buffer:
	func _request(_name: String, _path: String) -> void:
		pass
	func _process(_delta: float) -> void:
		pass

class ProbeView extends CampaignCinematic:
	func _make_buffer() -> Buffer:
		return ControlledBuffer.new()
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_chapter_status.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 2,
		"Capture original prologue and chapter status programs")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current chapter status capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original chapter status input: " + path)
	if failures == 0:
		await _check_play(capture.programs)
	print("CAMPAIGN_CHAPTER_STATUS assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_play(programs: Array) -> void:
	var prologue: Dictionary = programs[0]
	var chapter: Dictionary = programs[1]
	var view := ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1024, 768)
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	var loader: ControlledBuffer = view.buffer_loader
	_check(loader != null and loader.started, "Original prologue starts one background buffer")
	_check_status(view, prologue.frames[0], "Initial prologue")
	for index in range(7):
		loader._settle(view.buffer_rules.assets[index], null, true)
	_check_status(view, prologue.frames[1], "Pending prologue")
	for path: String in view.buffer_rules.assets:
		loader._settle(path, null, true)
	loader._settle("fonts", null, true)
	loader._settle("models", null, true)
	_check_status(view, prologue.frames[2], "Ready prologue")
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	_check(view.buffer_loader == null, "Original chapter does not start another buffer")
	_check_status(view, chapter.frames[0], "Chapter after prologue")
	loader.progress.emit(1, 12, 8, "retired", false)
	_check_status(view, chapter.frames[1], "Retired prologue callback")
	view._try_skip()
	_check(view.closing, "An already-ready chapter can skip immediately")
	view.dispose()
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	_check_status(view, chapter.frames[0], "Fresh chapter")
	view.dispose()
	view.free()
	var reentrant := ProbeView.new()
	add_child(reentrant)
	var observed := {"status": "", "hint": ""}
	reentrant.buffer_status.visibility_changed.connect(func():
		if reentrant.buffer_status.visible:
			observed.status = reentrant.buffer_status.text
			observed.hint = reentrant.caption.text
			reentrant.dispose(), CONNECT_ONE_SHOT)
	reentrant.play([Content.campaign.prologue[0]], "Continue")
	_check(observed.status == chapter.frames[0].status and observed.hint == chapter.frames[0].hint,
		"Chapter status is ready before visibility callbacks observe it")
	_check(not reentrant.playing and not reentrant.buffer_status.visible and reentrant.buffer_loader == null,
		"A status visibility callback can retire a chapter without restarting it")
	reentrant.free()
	var detached := ProbeView.new()
	add_child(detached)
	detached.buffer_status.visibility_changed.connect(func():
		if detached.buffer_status.visible:
			remove_child(detached), CONNECT_ONE_SHOT)
	detached.play([Content.campaign.prologue[0]], "Continue")
	_check(not detached.is_inside_tree() and not detached.playing and detached.last_frame_at == 0,
		"Status detachment cannot start a retired chapter's frame clock")
	detached.free()
	var queued := ProbeView.new()
	add_child(queued)
	queued.buffer_status.visibility_changed.connect(func():
		if queued.buffer_status.visible:
			queued.queue_free(), CONNECT_ONE_SHOT)
	queued.play(Content.campaign.prologue, "Continue")
	_check(queued.is_queued_for_deletion() and queued.buffer_loader != null and not queued.buffer_loader.started,
		"Queued retirement while showing status cannot start prologue buffering")
	await get_tree().process_frame

func _check_status(view: ProbeView, frame: Dictionary, label: String) -> void:
	_check(view.buffer_status.visible and view.buffer_status.text == frame.status and view.caption.text == frame.hint,
		label + " retains the original visible status and skip hint")
