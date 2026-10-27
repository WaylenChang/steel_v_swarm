extends Node

var assertions := 0
var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	var rate := AudioServer.get_mix_rate()
	# Exercise the native resampler off its block boundary, without driver timing.
	for driver_frames: int in [64, 128, 240, 441, 480, 512, 960, 1024, 4096]:
		var interval := float(driver_frames) / rate
		var budget := AudioGeneratorFeed.startup_frames(interval, rate)
		var feed := AudioGeneratorFeed.new()
		feed.configure(rate)
		var playback := feed.playback
		playback.start()
		playback.mix_audio(1.0, 64)
		_check(playback.get_skips() == 0, "Native interpolation history advances before the first ring refill")
		var frames := PackedVector2Array()
		frames.resize(budget)
		frames.fill(Vector2(.125, -.125))
		_check(playback.push_buffer(frames), "The two-period budget fits the original native feed")
		var mixed := playback.mix_audio(1.0, driver_frames * 2)
		_check(mixed.size() == driver_frames * 2 and playback.get_skips() == 0,
			"Native resampler consumes two driver periods without a partial-block underrun: %d" % driver_frames)
		_check(mixed[-1] == Vector2(.125, -.125), "The aligned refill retains both native channels")
		playback.stop()
	var old := AudioGeneratorFeed.new()
	for history: int in [66, 194]:
		var feed := AudioGeneratorFeed.new()
		feed.configure(rate)
		feed.playback.start()
		feed.playback.mix_audio(1.0, 127)
		var budget := AudioGeneratorFeed.startup_frames(480.0 / rate, rate)
		var aligned := AudioMoveMixer.new()
		aligned.output = feed.playback
		aligned.inputs.assign([{"startup_discard": history}])
		_check(aligned.prime_output(budget), "Replace discarded input history with whole native startup refills")
		_check(aligned.startup_budget_frames == budget and aligned.input_ahead == budget, "History replacement preserves the original service and input-ahead budgets")
		_check(aligned.startup_history_frames == ceili(float(history) / 128) * 128, "Startup history is reported separately from service headroom")
		feed.playback.mix_audio(1.0, history)
		feed.playback.mix_audio(1.0, 960)
		_check(feed.playback.get_skips() == 0, "Two native periods remain available after stripped input history: " + str(history))
		feed.playback.stop()
		var shortened := AudioGeneratorFeed.new()
		shortened.configure(rate)
		shortened.playback.start()
		shortened.playback.mix_audio(1.0, 127)
		var samples := PackedVector2Array()
		samples.resize(budget)
		shortened.playback.push_buffer(samples)
		shortened.playback.mix_audio(1.0, history)
		shortened.playback.mix_audio(1.0, 960)
		_check(shortened.playback.get_skips() > 0, "Reproduce history removal consuming the original service reserve")
		shortened.playback.stop()
	old.configure(rate)
	old.playback.start()
	old.playback.mix_audio(1.0, 64)
	var short_fill := PackedVector2Array()
	short_fill.resize(960)
	_check(old.playback.push_buffer(short_fill), "Reproduce the former 480-frame driver budget")
	old.playback.mix_audio(1.0, 960)
	_check(old.playback.get_skips() > 0, "The original 960-frame budget misses the final native refill by 64 frames")
	var mixer := AudioMoveMixer.new()
	mixer.output = old.playback
	mixer.controls.frame = 17
	_check(not mixer.pump(), "An actual native underrun terminates the mixer explicitly")
	var fault := mixer.snapshot()
	_check(fault.failure == "output_underrun" and fault.frames == 17 and fault.output_skips > 0,
		"Failure diagnostics report current native cursors instead of a stale successful batch")
	old.playback.stop()
	print("AUDIO_GENERATOR_BUFFERS assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
