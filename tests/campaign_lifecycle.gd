extends "res://tests/run.gd"

class LifecycleView extends CampaignCinematic:
	# Art decoding is a separate resource gate; lifecycle checks need no substituted image.
	func _set_scene(index: int) -> void:
		if index >= 0 and index < scenes.size():
			active = index

class AdmissionView extends LifecycleView:
	var layout_action := Callable()
	var selection_action := Callable()
	func _layout() -> void:
		super._layout()
		if layout_action.is_valid():
			var action := layout_action
			layout_action = Callable()
			action.call()
	func _set_scene(index: int) -> void:
		super._set_scene(index)
		if selection_action.is_valid():
			var action := selection_action
			selection_action = Callable()
			action.call()

func _run() -> void:
	var scenes: Array = Content.campaign.prologue.slice(0, 2)
	_check(scenes.size() == 2, "Original campaign scenes are available for lifecycle acceptance")
	if scenes.size() != 2:
		_finish_campaign()
		return
	var view := LifecycleView.new()
	var clock := {"now": 1000.0}
	view.clock_msec = func(): return clock.now
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	var signals := {"finished": 0, "finishing": 0}
	view.finished.connect(func(): signals.finished += 1)
	view.finishing.connect(func(): signals.finishing += 1)
	view.play([scenes[0]], "")
	await get_tree().process_frame
	view.finishing.connect(func(): view.play([scenes[1]], ""), CONNECT_ONE_SHOT)
	view.finish()
	_check(view.playing and not view.closing and view.scenes[0].id == scenes[1].id,
		"A synchronous finishing listener can replace the active cinematic")
	_check(view.exit_tween == null or not view.exit_tween.is_valid(), "Retired finishing work cannot allocate a fade for the replacement")
	if view.exit_tween != null and view.exit_tween.is_valid():
		view.exit_tween.custom_step(float(Content.campaign.presentation.skip.fade) + .1)
	_check(view.playing and view.visible and signals.finished == 0, "The old completion cannot close or finish the replacement")
	view.dispose()
	view.play([scenes[0]], "")
	await get_tree().process_frame
	view.play([], "")
	_check(not view.playing and not view.visible and view.scenes.is_empty() and view.sections.is_empty(),
		"Empty scene replacement releases the previous cinematic before completing")
	_check(signals.finished == 1, "Empty source sequence completes immediately once")
	view.play([scenes[0]], "")
	await get_tree().process_frame
	view.finishing.connect(view.dispose, CONNECT_ONE_SHOT)
	view.finish()
	_check(not view.playing and (view.exit_tween == null or not view.exit_tween.is_valid()),
		"Cancellation from the finishing callback leaves no newly scheduled completion")
	if view.exit_tween != null and view.exit_tween.is_valid():
		view.exit_tween.custom_step(float(Content.campaign.presentation.skip.fade) + .1)
	_check(signals.finished == 1, "Cancelled finishing work cannot publish a delayed completion")
	view.play([scenes[0]], "")
	await get_tree().process_frame
	var before: int = signals.finishing
	view.finish()
	view.finish()
	_check(signals.finishing == before + 1, "Repeated finish requests retain the source once-only gate")
	view.exit_tween.custom_step(float(Content.campaign.presentation.skip.fade) + .1)
	_check(signals.finished == 1, "Finishing the visual fade cannot replace the independent source completion timer")
	clock.now += float(Content.campaign.presentation.skip.fade) * 1000
	view.exit_timer.timeout.emit()
	_check(signals.finished == 2 and not view.playing and not view.visible, "Normal fade completes exactly once and disposes the scene")
	view.play([scenes[0]], "")
	await get_tree().process_frame
	view.finish()
	var retired_timer: Timer = view.exit_timer
	view.dispose()
	retired_timer.timeout.emit()
	_check(not view.exit_tween.is_valid() and signals.finished == 2, "Room cancellation kills a pending fade without completing it")
	view.play([scenes[0]], "")
	await get_tree().process_frame
	view.finishing.connect(func(): remove_child(view), CONNECT_ONE_SHOT)
	view.finish()
	_check(not view.is_inside_tree() and not view.exit_tween.is_valid() and signals.finished == 2,
		"Synchronous tree removal cannot schedule a tween outside the scene tree")
	add_child(view)
	view.play([scenes[0]], "")
	await get_tree().process_frame
	view.finish()
	var detached_timer: Timer = view.exit_timer
	remove_child(view)
	_check(detached_timer.is_stopped() and not view.exit_tween.is_valid(), "Detachment stops pending native deadline and visual animation")
	clock.now += float(Content.campaign.presentation.skip.fade) * 1000
	detached_timer.timeout.emit()
	add_child(view)
	_check(not view.playing and not view.visible and signals.finished == 2 and view.exit_timer == null,
		"Reattachment cannot resume or publish retired cinematic completion")
	view.dispose()
	view.free()
	var queued := LifecycleView.new()
	add_child(queued)
	queued.play([scenes[0]], "")
	await get_tree().process_frame
	queued.finishing.connect(queued.queue_free, CONNECT_ONE_SHOT)
	queued.finish()
	_check(queued.is_queued_for_deletion() and queued.exit_tween == null,
		"Queued retirement from finishing cannot allocate delayed completion work")
	await get_tree().process_frame
	await _check_status_replacement(scenes)
	await _check_queued_ancestors(scenes)
	await _check_show_reentrancy(scenes)
	_check_admission_reentrancy(scenes)
	await _check_child_admission_reentrancy(scenes)
	_finish_campaign()

func _check_child_admission_reentrancy(scenes: Array) -> void:
	for boundary in ["art", "section", "ending"]:
		for operation in ["replace", "dispose", "queue", "ancestor"]:
			var parent_node := Node.new()
			add_child(parent_node)
			var view := LifecycleView.new()
			parent_node.add_child(view)
			view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			view.size = Vector2(640, 360)
			var parent: Node = view.art_host if boundary == "art" else view.column
			var invoked := {"value": false}
			var on_child := func(child: Node):
				if invoked.value or (boundary == "ending" and not child is VBoxContainer):
					return
				invoked.value = true
				match operation:
					"replace": view.play([scenes[1]], "")
					"dispose": view.dispose()
					"queue": view.queue_free()
					"ancestor": parent_node.queue_free()
			parent.child_entered_tree.connect(on_child)
			view.play(scenes, "")
			_check(invoked.value, "The " + boundary + " admission callback runs synchronously")
			if operation == "replace":
				_check(view.playing and view.scenes.size() == 1 and view.scenes[0].id == scenes[1].id
					and view.art_layers.size() == 1 and view.sections.size() == 1,
					"Replacement during " + boundary + " admission keeps only the replacement scene")
			elif operation == "dispose":
				_check(not view.playing and view.scenes.is_empty() and view.art_layers.is_empty() and view.sections.is_empty(),
					"Disposal during " + boundary + " admission cannot resume old construction")
			else:
				_check((view.is_queued_for_deletion() or parent_node.is_queued_for_deletion()) and not view.playing,
					"Retirement during " + boundary + " admission cannot start playback")
			await get_tree().process_frame
			if operation == "replace":
				_check(view.art_host.get_child_count() == 1 and view.column.get_child_count() == 2,
					"Replacement during " + boundary + " admission releases unadmitted children")
				view.dispose()
				parent_node.free()
			elif operation == "dispose":
				_check(view.art_host.get_child_count() == 0 and view.column.get_child_count() == 0,
					"Disposal during " + boundary + " admission releases unadmitted children")
				parent_node.free()
			elif operation == "queue":
				parent_node.free()

func _check_admission_reentrancy(scenes: Array) -> void:
	for boundary in ["layout", "selection"]:
		var view := AdmissionView.new()
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(640, 360)
		if boundary == "layout":
			view.layout_action = view.dispose
		else:
			view.selection_action = view.dispose
		view.play([scenes[0]], "")
		_check(not view.playing and not view.visible and view.scenes.is_empty()
			and view.buffer_loader == null and not view.is_processing(),
			"Disposal during initial " + boundary + " cannot resume old playback")
		view.free()

func _check_show_reentrancy(scenes: Array) -> void:
	for operation in ["replace", "dispose", "queue"]:
		var view := LifecycleView.new()
		var clock := {"now": 1000.0}
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(640, 360)
		var entered := {"value": false}
		var on_show := func():
			if not view.visible or entered.value:
				return
			entered.value = true
			match operation:
				"replace":
					clock.now = 2000.0
					view.play([scenes[0], scenes[1]], "", 1)
					clock.now = 3000.0
				"dispose": view.dispose()
				"queue": view.queue_free()
		view.visibility_changed.connect(on_show)
		view.play([scenes[0]], "")
		match operation:
			"replace":
				_check(view.playing and view.scenes.size() == 2 and view.active == 1
					and view.sections.size() == 2 and view.art_layers.size() == 2 and view.last_frame_at == 2000.0,
					"A visible callback replacement retains only its new cinematic")
				view.set_process(false)
				await get_tree().process_frame
				_check(view.playing and view.active == 1 and view.sections.size() == 2,
					"Deferred work preserves the replacement selected during visibility")
			"dispose":
				_check(not view.playing and not view.visible and view.scenes.is_empty()
					and view.sections.is_empty() and not view.is_processing(),
					"A visible callback disposal cannot restart the old cinematic")
			"queue":
				_check(view.is_queued_for_deletion() and not view.playing and not view.is_processing(),
					"A visible callback retirement cannot start cinematic processing")
		if operation == "queue":
			await get_tree().process_frame
		else:
			view.dispose()
			view.free()

func _check_queued_ancestors(scenes: Array) -> void:
	for boundary in ["before_finish", "finishing", "timer_admission", "completion", "empty"]:
		for queued in ["parent", "ancestor"]:
			var ancestor := Node.new()
			add_child(ancestor)
			var parent := Node.new()
			ancestor.add_child(parent)
			var view := LifecycleView.new()
			var clock := {"now": 1000.0}
			view.clock_msec = func(): return clock.now
			parent.add_child(view)
			var signals := {"finishing": 0, "finished": 0}
			view.finishing.connect(func(): signals.finishing += 1)
			view.finished.connect(func(): signals.finished += 1)
			view.play([scenes[0]], "")
			await get_tree().process_frame
			var retiring: Node = parent if queued == "parent" else ancestor
			match boundary:
				"before_finish":
					retiring.queue_free()
					var token := view.generation
					view.finish()
					view.play([], "")
					view.play([scenes[1]], "")
					_check(signals.finishing == 0 and signals.finished == 0 and view.exit_timer == null
						and view.generation == token and view.scenes[0].id == scenes[0].id,
						"A queued " + queued + " rejects finish and both playback paths")
				"finishing":
					view.finishing.connect(retiring.queue_free, CONNECT_ONE_SHOT)
					view.finish()
					_check(signals.finishing == 1 and signals.finished == 0 and view.exit_timer == null
						and (view.exit_tween == null or not view.exit_tween.is_valid()),
						"A queued " + queued + " during finishing cannot schedule a fade")
				"timer_admission":
					view.child_entered_tree.connect(func(child: Node):
						if child is Timer:
							retiring.queue_free(), CONNECT_ONE_SHOT)
					view.finish()
					_check(signals.finished == 0 and (view.exit_timer == null or view.exit_timer.is_stopped()),
						"A queued " + queued + " during timer admission cannot start completion")
				"completion":
					view.finish()
					retiring.queue_free()
					clock.now += float(Content.campaign.presentation.skip.fade) * 1000
					view.exit_timer.timeout.emit()
					_check(signals.finished == 0, "A queued " + queued + " cannot emit an old completion")
				"empty":
					view.buffer_status.visibility_changed.connect(func():
						if not view.buffer_status.visible:
							retiring.queue_free(), CONNECT_ONE_SHOT)
					view.play([], "")
					_check(signals.finished == 0, "A queued " + queued + " during disposal cannot finish empty playback")
			ancestor.free()

func _check_status_replacement(scenes: Array) -> void:
	for operation in ["dispose", "replace", "empty", "complete"]:
		var view := LifecycleView.new()
		var clock := {"now": 1000.0}
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(640, 360)
		var signals := {"finished": 0, "replaced": 0}
		view.finished.connect(func(): signals.finished += 1)
		view.play([scenes[0]], "")
		await get_tree().process_frame
		view.buffer_status.visibility_changed.connect(func():
			if not view.buffer_status.visible:
				signals.replaced += 1
				view.play([scenes[1]], ""), CONNECT_ONE_SHOT)
		match operation:
			"dispose":
				view.dispose()
			"replace":
				view.play([scenes[0]], "")
			"empty":
				view.play([], "")
			"complete":
				view.finish()
				clock.now += float(Content.campaign.presentation.skip.fade) * 1000
				view.exit_timer.timeout.emit()
		_check(signals.replaced == 1 and view.playing and view.visible and view.scenes.size() == 1 and view.scenes[0].id == scenes[1].id,
			"Status retirement preserves a synchronous replacement during " + operation)
		_check(signals.finished == 0, "Retired completion cannot finish a replacement during " + operation)
		await get_tree().process_frame
		_check(view.playing and view.scenes.size() == 1 and view.scenes[0].id == scenes[1].id,
			"Deferred work preserves the replacement during " + operation)
		view.dispose()
		view.free()
	for operation in ["replace", "empty", "complete"]:
		var view := LifecycleView.new()
		var clock := {"now": 1000.0}
		view.clock_msec = func(): return clock.now
		add_child(view)
		var signals := {"finished": 0}
		view.finished.connect(func(): signals.finished += 1)
		view.play([scenes[0]], "")
		await get_tree().process_frame
		view.buffer_status.visibility_changed.connect(func():
			if not view.buffer_status.visible:
				view.queue_free(), CONNECT_ONE_SHOT)
		match operation:
			"replace":
				view.play([scenes[1]], "")
			"empty":
				view.play([], "")
			"complete":
				view.finish()
				clock.now += float(Content.campaign.presentation.skip.fade) * 1000
				view.exit_timer.timeout.emit()
		_check(view.is_queued_for_deletion() and not view.playing and signals.finished == 0,
			"Queued status retirement cannot restart or finish during " + operation)
		await get_tree().process_frame

func _finish_campaign() -> void:
	print("CAMPAIGN_LIFECYCLE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
