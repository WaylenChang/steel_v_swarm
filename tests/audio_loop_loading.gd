extends Node

const URL := "audio/__sol_loading__/held.sol_audio"
const PATH := "res://assets/" + URL
const UNSUPPORTED_URL := "audio/__sol_loading__/unsupported.sol_audio"
const UNSUPPORTED_PATH := "res://assets/" + UNSUPPORTED_URL

class HeldAudioLoader extends ResourceFormatLoader:
	var started := Semaphore.new()
	var release := Semaphore.new()
	var loads := 0
	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["sol_audio"])
	func _handles_type(type: StringName) -> bool:
		return type in [&"AudioStream", &"AudioStreamOggVorbis", &"AudioStreamWAV", &"Resource"]
	func _get_resource_type(path: String) -> String:
		if path == PATH:
			return "AudioStreamOggVorbis"
		if path == UNSUPPORTED_PATH:
			return "AudioStreamWAV"
		return ""
	func _exists(path: String) -> bool:
		return path in [PATH, UNSUPPORTED_PATH]
	func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
		loads += 1
		if path == UNSUPPORTED_PATH:
			return AudioStreamWAV.new()
		started.post()
		release.wait()
		return AudioStreamOggVorbis.new()

class DecodeGuard extends RefCounted:
	var returned := Semaphore.new()
	var release: Semaphore
	var timed_out := false
	func run() -> void:
		var deadline := Time.get_ticks_msec() + 3000
		while not returned.try_wait():
			if Time.get_ticks_msec() >= deadline:
				timed_out = true
				break
			OS.delay_msec(1)
		release.post()

var assertions := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var loader := HeldAudioLoader.new()
	ResourceLoader.add_resource_format_loader(loader, true)
	var player := AudioLoopPlayer.new()
	add_child(player)
	var callbacks: Array = []
	player.loaded.connect(func(): callbacks.append("loaded"))
	player.load_failed.connect(func(_error): callbacks.append("failed"))
	var error := player.open(URL, &"Master")
	_check(error == OK, "Pending audio uses the native threaded ResourceLoader request")
	if error != OK:
		player.free()
		ResourceLoader.remove_resource_format_loader(loader)
		_finish()
		return
	var deadline := Time.get_ticks_msec() + 5000
	var started := loader.started.try_wait()
	while not started and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		started = loader.started.try_wait()
	_check(started, "The audio decoder is confirmed live and held on its worker")
	if not started:
		loader.release.post()
		player.free()
		ResourceLoader.remove_resource_format_loader(loader)
		_finish()
		return
	var survivor := AudioLoopPlayer.new()
	add_child(survivor)
	var survivor_callbacks: Array = []
	survivor.loaded.connect(func(): survivor_callbacks.append("loaded"))
	survivor.load_failed.connect(func(_error): survivor_callbacks.append("failed"))
	var survivor_error := survivor.open(URL, &"Master")
	_check(survivor_error == OK, "Another audio player can share the confirmed live decode request")
	if survivor_error != OK:
		loader.release.post()
		player.free()
		survivor.free()
		ResourceLoader.remove_resource_format_loader(loader)
		_finish()
		return
	var guard := DecodeGuard.new()
	guard.release = loader.release
	var thread := Thread.new()
	var thread_error := thread.start(guard.run)
	_check(thread_error == OK, "A separate guard can release the decoder if teardown blocks")
	if thread_error != OK:
		loader.release.post()
		player.free()
		survivor.free()
		ResourceLoader.remove_resource_format_loader(loader)
		_finish()
		return
	player.free()
	guard.returned.post()
	thread.wait_to_finish()
	_check(not guard.timed_out, "Audio teardown returns before a pending decoder is released")
	deadline = Time.get_ticks_msec() + 5000
	while ResourceLoader.load_threaded_get_status(PATH) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(ResourceLoader.load_threaded_get_status(PATH) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"The detached decoder request is collected after completion")
	_check(callbacks.is_empty() and loader.loads == 1, "A retired audio player publishes no stale readiness or failure callbacks")
	_check(survivor_callbacks == ["loaded"] and survivor.stream != null,
		"Retiring one consumer does not consume another player's shared decode completion")
	survivor.free()
	await _unsupported_case()
	ResourceLoader.remove_resource_format_loader(loader)
	_rejected_case("assets/audio/bgm/menu.ogg", ERR_INVALID_PARAMETER)
	_rejected_case("audio/../bgm/menu.ogg", ERR_INVALID_PARAMETER)
	_rejected_case("audio/__sol_loading__/missing.ogg", ERR_FILE_NOT_FOUND)
	var sink := StringName("AudioLoopFixture_%d" % get_instance_id())
	AudioServer.add_bus()
	var sink_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(sink_index, str(sink))
	AudioServer.set_bus_mute(sink_index, true)
	for url: String in ["audio/bgm/menu.ogg", "audio/bgm/menu-mobile.ogg", "audio/bgm/battle.mp3", "audio/bgm/battle-mobile.mp3"]:
		await _codec_case(url, sink)
	sink_index = AudioServer.get_bus_index(sink)
	if sink_index > 0:
		await AudioBuses._retire(get_tree(), [sink])
	_finish()

func _unsupported_case() -> void:
	var player := AudioLoopPlayer.new()
	add_child(player)
	var errors: Array = []
	player.load_failed.connect(func(error): errors.append(error))
	_check(player.open(UNSUPPORTED_URL, &"Master") == OK, "Unsupported codec fixture reaches the native decoder result gate")
	var deadline := Time.get_ticks_msec() + 5000
	while errors.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(errors == [ERR_FILE_UNRECOGNIZED] and player.stream == null and player.pending_path.is_empty(),
		"A loaded unsupported stream fails explicitly without becoming a fabricated music fallback")
	_check(ResourceLoader.load_threaded_get_status(UNSUPPORTED_PATH) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"Unsupported decoder results are collected before reporting failure")
	player.free()

func _rejected_case(url: String, expected: Error) -> void:
	var player := AudioLoopPlayer.new()
	add_child(player)
	var errors: Array = []
	player.load_failed.connect(func(error): errors.append(error))
	_check(player.open(url, &"Master") == expected and errors == [expected] and player.pending_path.is_empty(),
		"Unavailable or invalid music URLs report one explicit failure without a pending load: " + url)
	player.free()

func _codec_case(url: String, sink: StringName) -> void:
	var shared := load("res://assets/" + url) as AudioStream
	_check(shared is AudioStreamOggVorbis or shared is AudioStreamMP3, url + ": original track has a supported native codec")
	if shared == null:
		return
	var original_loop: Variant = shared.get("loop")
	var original_offset: Variant = shared.get("loop_offset")
	var first := AudioLoopPlayer.new()
	var second := AudioLoopPlayer.new()
	add_child(first)
	add_child(second)
	var errors: Array = []
	first.load_failed.connect(func(error): errors.append(error))
	second.load_failed.connect(func(error): errors.append(error))
	var first_error := first.open(url, sink)
	var second_error := second.open(url, sink)
	_check(first_error == OK and second_error == OK, url + ": concurrent players register their own native load requests")
	var deadline := Time.get_ticks_msec() + 5000
	while (first.stream == null or second.stream == null) and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(errors.is_empty() and first.stream != null and second.stream != null, url + ": both native loads finish without codec errors")
	if first.stream != null and second.stream != null:
		_check(first.stream != shared and second.stream != shared and first.stream != second.stream,
			url + ": each player owns its loop properties instead of mutating the imported stream")
		_check(first.stream.get("loop") and first.stream.get("loop_offset") == 0.0 and
			second.stream.get("loop") and second.stream.get("loop_offset") == 0.0,
			url + ": native loops start at the original full-track boundary")
		first.stream.set("loop_offset", .25)
		_check(second.stream.get("loop_offset") == 0.0 and shared.get("loop_offset") == original_offset,
			url + ": per-player loop edits cannot leak to another instance or its source")
		first.stream.set("loop_offset", 0.0)
		_check(not first.playing and not second.playing, url + ": readiness alone never starts a retained music track")
		first.play()
		await get_tree().create_timer(.08, true, false, true).timeout
		first.stream_paused = true
		await get_tree().create_timer(.05, true, false, true).timeout
		var paused := first.get_playback_position()
		_check(paused > 0.0 and first.has_stream_playback(), url + ": pausing retains the decoded playback instance and position")
		await get_tree().create_timer(.05, true, false, true).timeout
		_check(first.get_playback_position() == paused, url + ": paused music does not advance with wall time")
		first.stream_paused = false
		await get_tree().create_timer(.08, true, false, true).timeout
		_check(first.get_playback_position() > paused and not second.playing,
			url + ": resume advances the retained position without starting another track")
	first.free()
	second.free()
	_check(shared.get("loop") == original_loop and shared.get("loop_offset") == original_offset,
		url + ": teardown leaves the imported codec resource unchanged")

func _finish() -> void:
	print("AUDIO_LOOP_LOADING assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
