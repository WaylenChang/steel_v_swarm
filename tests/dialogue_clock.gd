extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_native.json")
	var program: Dictionary = capture.programs[0]
	var scene: Dictionary = program.frames[0].scene.duplicate(true)
	scene.lines = scene.lines.slice(0, 1)
	var seconds: float = program.frames[0].state.timers[0]
	var view := CampaignDialogue.new()
	var clock := {"now": 1000.0}
	view.clock_msec = func(): return clock.now
	add_child(view)
	view.radio(scene)
	var timer: Timer = view.timers[0]
	var deadline: float = clock.now + seconds * 1000
	clock.now = deadline - .001
	timer.timeout.emit()
	_check(view.at == 1 and view.fade == null and view.timers == [timer], "An early native timeout retains the original line until its absolute wall deadline")
	_near(timer.time_left, .000001, "An early native timeout waits only the remaining source deadline")
	clock.now = deadline
	timer.timeout.emit()
	_check(view.fade != null and view.timers.size() == 1, "Exact source line deadline starts retirement once")
	var fade_timer: Timer = view.timers[0]
	var bar := view.bar
	timer.timeout.emit()
	_check(view.bar == bar and view.timers == [fade_timer], "A delivered callback cannot schedule a duplicate retirement")
	clock.now += float(Content.campaign.presentation.radioFade) * 1000 - .001
	fade_timer.timeout.emit()
	_check(view.bar == bar and view.timers == [fade_timer], "An early removal callback retains the original bar")
	clock.now += .001
	fade_timer.timeout.emit()
	_check(view.bar == null and view.timers.is_empty(), "The original absolute retirement deadline releases the bar")
	view.radio(scene)
	var retired: Timer = view.timers[0]
	view.radio(scene)
	var replacement := view.bar
	clock.now += seconds * 1000
	retired.timeout.emit()
	_check(view.bar == replacement and (view.fade == null or not view.fade.is_valid()) and view.timers.size() == 1, "A retired timer cannot advance its replacement")
	view.clear()
	view.clock_msec = Callable()
	var speed := Engine.time_scale
	for scale_factor in [0.0, .25, 3.0]:
		Engine.time_scale = scale_factor
		get_tree().paused = true
		var delivered := {"at": -1.0}
		var started := float(Time.get_ticks_usec()) / 1000
		var delay: float = Content.campaign.presentation.transcript.delay
		view._after(delay, func(): delivered.at = float(Time.get_ticks_usec()) / 1000)
		var bound := started + 1000
		while delivered.at < 0 and float(Time.get_ticks_usec()) / 1000 < bound:
			await get_tree().process_frame
		_check(delivered.at >= started + delay * 1000 and delivered.at < bound, "Native presentation timers keep the source wall deadline during paused zero/slow/fast gameplay")
		view.radio(scene)
		view._step()
		var visible_bar := view.bar
		var end := float(Time.get_ticks_usec()) / 1000 + 1100
		while is_instance_valid(view.bar) and float(Time.get_ticks_usec()) / 1000 < end:
			await get_tree().process_frame
		_check(view.bar == null and not is_instance_valid(visible_bar), "Paused zero/slow/fast gameplay cannot freeze native radio retirement")
		_check(view.fade == null or not view.fade.is_valid(), "Radio exit tween reaches completion while gameplay is paused")
		view.clear()
	get_tree().paused = false
	Engine.time_scale = speed
	view.free()
	print("DIALOGUE_CLOCK assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
