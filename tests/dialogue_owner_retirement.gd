extends Node

var assertions := 0
var failures := 0

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_owner.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Dialogue owner producer is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Dialogue owner retains original cancellation source: " + path)
	if failures == 0:
		_replay(capture.programs)
		_layer_visibility()
		await _native_lifetimes()
	print("DIALOGUE_OWNER_RETIREMENT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _layer_visibility() -> void:
	var host := Control.new()
	host.hide()
	add_child(host)
	var layer := preload("res://scripts/dialogue_radio_layer.gd").new()
	host.add_child(layer)
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"A layer initially attached under a hidden owner does not render")
	host.show()
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"Showing the owner starts the isolated renderer")
	remove_child(host)
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"Detaching an owner stops the isolated renderer")
	host.hide()
	add_child(host)
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"Reattaching a hidden owner does not start its renderer")
	host.show()
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"Showing a reattached owner resumes its renderer")
	layer.hide()
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"Hiding the layer stops its renderer")
	remove_child(host)
	add_child(host)
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"A hidden layer remains stopped after reattachment")
	layer.show()
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"Showing the layer after reattachment resumes rendering")
	remove_child(host)
	add_child(host)
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"Reattaching a visible owner resumes its renderer")
	layer.retire()
	host.hide()
	host.show()
	_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"A retired renderer cannot restart when its owner changes visibility")
	host.free()

func _view(clock: Dictionary) -> CampaignDialogue:
	var view := CampaignDialogue.new()
	view.clock_msec = func(): return clock.now
	add_child(view)
	return view

func _seed(view: CampaignDialogue) -> Sprite2D:
	var group := preload("res://scripts/dialogue_radio_layer.gd").new()
	view.radio_group = group
	view.add_child(group)
	group.layout_radio(Vector2(96, 80))
	view.bar = PanelContainer.new()
	group.content.add_child(view.bar)
	view.at = 1
	view.total = 1
	return group

func _replay(programs: Array) -> void:
	for program: Dictionary in programs:
		var clock := {"now": 0.0}
		var view := _view(clock)
		var delivered: Array = []
		var deadlines: Dictionary = {}
		for frame: Dictionary in program.frames:
			clock.now = float(frame.now)
			match frame.action:
				"schedule":
					var id: String = frame.id
					view._after_msec(float(frame.delay), func(): delivered.append(id))
					deadlines[view.timers[-1].get_instance_id()] = clock.now + float(frame.delay)
				"deliver":
					var first: Timer = view.timers[0]
					first.timeout.emit()
				"clear": view.clear()
				"dispose": view.dispose()
			_check(delivered == frame.delivered, "Original tracked timer delivery and cancellation order")
			var remaining: Array = []
			for timer: Timer in view.timers:
				remaining.append(deadlines[timer.get_instance_id()] - clock.now)
			_check(remaining == frame.timers, "Original timer deadlines survive only in the current generation")
		view.free()

func _native_lifetimes() -> void:
	var clock := {"now": 0.0}
	var view := _view(clock)
	var group := _seed(view)
	var group_ref: WeakRef = weakref(group)
	var material_ref: WeakRef = weakref(group.material)
	view.track(0)
	view._step()
	var old_timer: Timer = view.timers[0]
	var old_fade: Tween = view.fade
	var calls: Array = []
	view._after_msec(180, func(): calls.append("old"))
	get_tree().paused = true
	remove_child(view)
	_check(view.timers.is_empty() and old_timer.is_stopped(), "Paused detachment stops all pending native deadlines")
	_check(view.radio_group == null and view.bar == null and view.speaker == null and view.line_label == null,
		"Detachment releases all borrowed radio nodes before native callbacks")
	_check(not old_fade.is_valid() and view.fade == null and view.entrance == null, "Detachment kills and releases native animations")
	_check(not view.track_label.visible, "Detached dialogue cannot retain a stage overlay")
	clock.now = 5000.0
	old_timer.timeout.emit()
	view._after_msec(0, func(): calls.append("detached"))
	view.radio({"title": "", "note": "", "lines": [{"ch": "t06", "t": ""}]})
	_check(view.timers.is_empty() and view.radio_group == null and calls.is_empty(), "Detached commands and stale timeout cannot restart playback")
	add_child(view)
	_check(view.radio_group == null and view.timers.is_empty(), "Reattachment requires fresh playback")
	_seed(view)
	view._after_msec(10, func(): calls.append("fresh"))
	clock.now += 10
	view.timers[0].timeout.emit()
	_check(calls == ["fresh"], "Fresh playback works after reattachment")
	get_tree().paused = false
	view.clear()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(group_ref.get_ref() == null and material_ref.get_ref() == null, "Closed retained owner releases radio viewport and private material")

	for method in ["clear", "dispose", "expiry"]:
		var old_group := _seed(view)
		view.track(0)
		old_group.visibility_changed.connect(func():
			if not old_group.visible:
				view.clear()
				_seed(view)
				view.track(1)
				view._after_msec(50, func(): calls.append("replacement")), CONNECT_ONE_SHOT)
		if method == "expiry":
			view._step()
			clock.now += 1000
			view.timers[0].timeout.emit()
		else:
			view.call(method)
		_check(view.radio_group != null and view.radio_group != old_group and view.at == 1 and view.total == 1,
			"Synchronous " + method + " visibility callback retains replacement radio ownership")
		_check(view.timers.size() == 1 and view.track_label.visible, "Old cleanup cannot erase replacement deadlines or track")
		view.clear()

	_seed(view)
	view.clock_msec = func():
		view.clear()
		return clock.now
	view._after_msec(10, func(): calls.append("interrupted"))
	_check(view.timers.is_empty(), "Clock callback cancellation cannot allocate a timer afterward")
	view.clock_msec = func(): return clock.now
	view._after_msec(10, func(): calls.append("interrupted-timeout"))
	var interrupted: Timer = view.timers[0]
	view.clock_msec = func():
		view.clear()
		return clock.now
	clock.now += 10
	interrupted.timeout.emit()
	_check(view.timers.is_empty() and not calls.has("interrupted-timeout"), "Clock cancellation during delivery cannot resume the old callback")
	view.clock_msec = func(): return clock.now
	view.child_entered_tree.connect(func(child: Node):
		if child is Timer:
			view.clear(), CONNECT_ONE_SHOT)
	view._after_msec(10, func(): calls.append("admission"))
	_check(view.timers.is_empty(), "Timer admission is owned before synchronous tree callbacks")
	view.child_entered_tree.connect(func(child: Node):
		if child.get_script() == preload("res://scripts/dialogue_radio_layer.gd"):
			view.clear(), CONNECT_ONE_SHOT)
	view.radio({"title": "", "note": "", "lines": [{"ch": "t06", "t": ""}]})
	_check(view.radio_group == null and view.bar == null and view.timers.is_empty(), "Radio admission can cancel before its layer is ready")
	var early := preload("res://scripts/dialogue_radio_layer.gd").new()
	early.retire()
	view.add_child(early)
	_check(early.viewport == null and early.content == null and early.material == null, "A retired layer cannot allocate render resources on late admission")
	early.free()
	var scene := {"title": "", "note": "", "lines": [{"ch": "t06", "t": ""}]}
	for kind in ["portrait", "speaker"]:
		var cancelled := {"done": false}
		var interrupt := func(node: Node):
			if cancelled.done or not view.is_ancestor_of(node):
				return
			if (kind == "portrait" and node is TextureRect) or (kind == "speaker" and node == view.speaker):
				cancelled.done = true
				view.clear()
		get_tree().node_added.connect(interrupt)
		view.radio(scene)
		get_tree().node_added.disconnect(interrupt)
		_check(cancelled.done and view.radio_group == null and view.timers.is_empty(), "Radio construction stops after " + kind + " admission cancels its generation")
	var host := VBoxContainer.new()
	add_child(host)
	host.child_entered_tree.connect(func(_child: Node): view.clear(), CONNECT_ONE_SHOT)
	view.transcript(host, scene)
	_check(host.get_child_count() == 1 and view.timers.is_empty(), "Transcript cancellation during host admission cannot construct or schedule later rows")
	host.free()
	for removal in ["detach", "queue"]:
		var transcript_host := VBoxContainer.new()
		add_child(transcript_host)
		view.transcript(transcript_host, scene)
		var row: Control = transcript_host.get_child(2).rows.get_child(0)
		var pending: Timer = view.timers[0]
		if removal == "detach":
			remove_child(transcript_host)
		else:
			transcript_host.queue_free()
		clock.now += 1000
		pending.timeout.emit()
		_check(not row.revealed and view.timers.is_empty(), "A " + removal + " transcript host cannot reveal or scroll from an old deadline")
		if removal == "detach":
			transcript_host.free()
	view.dispose()
	view.queue_free()
	view._after_msec(10, func(): calls.append("queued"))
	view.track(0)
	_check(view.timers.is_empty() and not view.track_label.visible, "Queued owner rejects late timer and stage commands")
	await get_tree().process_frame
