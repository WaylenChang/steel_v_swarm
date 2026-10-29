extends Node

const Buffer = preload("res://scripts/campaign_buffer.gd")
const Loading = preload("res://tests/audio_loop_loading.gd")

class ControlledBuffer extends Buffer:
	var immediate := false
	func _request(_name: String, _path: String) -> void:
		if immediate:
			_settle(_name, null, true)
	func _process(_delta: float) -> void:
		pass

class BufferView extends CampaignCinematic:
	var progress_action := Callable()
	var immediate := false
	func _make_buffer() -> Buffer:
		var loader := ControlledBuffer.new()
		loader.immediate = immediate
		if progress_action.is_valid():
			loader.progress.connect(progress_action, CONNECT_ONE_SHOT)
		return loader
	func _set_scene(index: int) -> void:
		if index >= 0 and index < scenes.size():
			active = index

var assertions := 0
var failures: Array[String] = []
var reference: Dictionary

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _source() -> void:
	reference = Content.read_json("res://data/campaign_buffer.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(reference.formatVersion == 1, "Load original campaign cache and warning programs")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Current campaign buffer capture: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Original campaign cache input agrees with shared metadata: " + path)

func _programs() -> void:
	for program: Dictionary in reference.programs:
		var buffer := ControlledBuffer.new()
		add_child(buffer)
		var events: Array[Dictionary] = []
		buffer.progress.connect(func(loaded, total, percent, name, ready):
			events.append({"loaded": loaded, "total": total, "pct": percent, "name": name, "ready": ready}))
		buffer.begin(reference.rules)
		for frame: Dictionary in program.frames:
			buffer._settle(frame.name, null, not program.reject)
			var event: Dictionary = events.back()
			_check(event.loaded == int(frame.loaded) and event.total == int(frame.total)
				and event.pct == int(frame.pct) and event.name == frame.name and event.ready == frame.ready,
				"Original image/font/model success and error completions retain progress rounding and order")
		_check(buffer.complete and buffer.percent == 100, "Every original cache attempt unlocks gesture skipping")
		buffer._settle("models", null, true)
		_check(events.size() == program.frames.size(), "Duplicate decoder callbacks cannot count a second completion")
		buffer.retire()
		buffer._settle(reference.rules.assets[0], null, true)
		_check(events.size() == program.frames.size(), "Retired cache callbacks cannot publish into a later play")
		buffer.free()

func _view() -> BufferView:
	var view := BufferView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1024, 768)
	return view

func _gestures() -> void:
	var view := _view()
	var clock := {"now": 1000.0}
	view.clock_msec = func(): return clock.now
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	var buffer := view.buffer_loader
	_check(buffer != null and not buffer.complete and view.playing and not view.closing,
		"Original prologue starts playing while cache jobs remain incomplete")
	for step: Dictionary in reference.skip:
		if step.complete:
			for name: String in buffer.paths:
				buffer._settle(name, null, true)
		view._try_skip()
		_check(view.closing == (int(step.finished) > 0) and view.buffer_warning_timers.size() == int(step.warnings),
			"Original pending gestures warn while completed gestures enter finish")
		if not step.complete:
			_check(view.buffer_status.text == String(reference.rules.warning).replace("{percent}", str(buffer.percent)),
				"Original warning includes the current completed-attempt percentage")
	view.dispose()
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	view._try_skip()
	var first: Timer = view.buffer_warning_timers[0]
	clock.now += 1000
	view._try_skip()
	_check(view.buffer_warning_timers.size() == 2, "Repeated warnings retain independent original timeouts")
	clock.now += float(reference.rules.warningMsec) - 1000 - .001
	first.timeout.emit()
	_check(view.buffer_warning and view.buffer_warning_timers.size() == 2, "An early native warning timer retains the strict wall deadline")
	clock.now += .001
	first.timeout.emit()
	_check(not view.buffer_warning and view.buffer_warning_timers.size() == 1,
		"The earlier warning expires without being extended by the later gesture")
	var stale := view.buffer_loader
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	var old_caption := view.caption.text
	stale.progress.emit(12, 12, 100, "models", true)
	_check(view.buffer_loader == null and view.caption.text == old_caption and view.caption.text == reference.rules.readyHint
		and view.buffer_status.visible and view.buffer_status.text == reference.rules.ready,
		"Replacing the prologue with a ready chapter rejects the previous progress callback")
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	view.finish_button.pressed.emit()
	_check(view.closing and not view.buffer_loader.complete, "The original finish button bypasses the gesture readiness gate")
	view.dispose()
	view.free()

func _reentrant() -> void:
	var buffer := ControlledBuffer.new()
	add_child(buffer)
	buffer.progress.connect(func(_loaded, _total, _percent, _name, _ready): buffer.retire(), CONNECT_ONE_SHOT)
	buffer.begin(reference.rules)
	buffer._settle(reference.rules.assets[0], null, true)
	buffer._settle("fonts", null, true)
	_check(buffer.retired and buffer.completed.size() == 1, "Progress retirement seals the cache before a later completion")
	buffer.free()
	var view := _view()
	view.child_entered_tree.connect(func(child: Node):
		if child is Buffer:
			view.dispose())
	view.play(Content.campaign.prologue, "Continue")
	_check(not view.playing and view.buffer_loader == null, "Reentrant loader admission cannot restart a disposed cinematic")
	view.free()
	view = _view()
	view.immediate = true
	var clock := {"now": 1000.0}
	view.clock_msec = func(): return clock.now
	var replaced := view
	view.progress_action = func(_loaded, _total, _percent, _name, _ready):
		replaced.progress_action = Callable()
		clock.now = 2000
		replaced.play([Content.campaign.prologue[0]], "Continue")
		clock.now = 3000
	view.play(Content.campaign.prologue, "Continue")
	_check(view.playing and view.buffer_loader == null and view.last_frame_at == 2000,
		"Synchronous cache progress replacement cannot resume the old playback clock")
	view.dispose()
	view.free()
	view = _view()
	var warned := view
	view.play(Content.campaign.prologue, "Continue")
	view.child_entered_tree.connect(func(child: Node):
		if child is Timer:
			warned.dispose())
	view._try_skip()
	_check(not view.playing and view.buffer_warning_timers.is_empty(), "Warning timer admission cannot schedule work after reentrant disposal")
	view.free()

func _native_requests() -> void:
	var buffer := Buffer.new()
	add_child(buffer)
	buffer.begin(reference.rules)
	_check(buffer.completed.is_empty(), "Cached and failed image attempts remain asynchronous like original browser events")
	var old_scale := Engine.time_scale
	Engine.time_scale = 0
	get_tree().paused = true
	var deadline := Time.get_ticks_msec() + 5000
	while not buffer.complete and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(buffer.complete and buffer.completed.size() == reference.rules.assets.size() + 2,
		"Actual native resource attempts and empty model batch settle while gameplay is paused at zero speed")
	get_tree().paused = false
	Engine.time_scale = old_scale
	_check(Buffer.retained.has("res://assets/fonts/NotoSansTC.ttf"), "The real native font resource is retained for subsequent consumers")
	buffer.free()
	var decoder := Loading.HeldAudioLoader.new()
	ResourceLoader.add_resource_format_loader(decoder, true)
	buffer = Buffer.new()
	add_child(buffer)
	buffer.begin({"assets": [], "modelAssets": []}, Loading.PATH)
	deadline = Time.get_ticks_msec() + 5000
	var started := decoder.started.try_wait()
	while not started and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		started = decoder.started.try_wait()
	_check(started, "The native decoder is confirmed live before cache retirement")
	var guard := Loading.DecodeGuard.new()
	guard.release = decoder.release
	var thread := Thread.new()
	_check(thread.start(guard.run) == OK, "A decoder guard can release an incorrectly blocking retirement")
	var tracked: WeakRef = weakref(buffer)
	remove_child(buffer)
	buffer.free()
	_check(tracked.get_ref() == null and not guard.timed_out, "Cache retirement releases its owner without waiting for native decoding")
	guard.returned.post()
	thread.wait_to_finish()
	deadline = Time.get_ticks_msec() + 5000
	while ResourceLoader.load_threaded_get_status(Loading.PATH) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(ResourceLoader.load_threaded_get_status(Loading.PATH) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"The shared native drain finishes the abandoned request independently")
	ResourceLoader.remove_resource_format_loader(decoder)

func _paused_warning() -> void:
	var view := _view()
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	view._try_skip()
	var old_scale := Engine.time_scale
	Engine.time_scale = 0
	get_tree().paused = true
	var deadline := Time.get_ticks_msec() + int(reference.rules.warningMsec) + 1000
	while view.buffer_warning and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not view.buffer_warning and view.buffer_warning_timers.is_empty(), "Real warning timers keep wall deadlines during SceneTree pause and zero gameplay speed")
	get_tree().paused = false
	Engine.time_scale = old_scale
	view.dispose()
	view.free()

func _run() -> void:
	_source()
	if failures.is_empty():
		_programs()
		_gestures()
		_reentrant()
		await _native_requests()
		await _paused_warning()
	await get_tree().process_frame
	print("CAMPAIGN_BUFFER_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
