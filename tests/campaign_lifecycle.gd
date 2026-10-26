extends "res://tests/run.gd"

class LifecycleView extends CampaignCinematic:
	# Art decoding is a separate resource gate; lifecycle checks need no substituted image.
	func _set_scene(index: int) -> void:
		if index >= 0 and index < scenes.size():
			active = index

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
	_finish_campaign()

func _finish_campaign() -> void:
	print("CAMPAIGN_LIFECYCLE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
