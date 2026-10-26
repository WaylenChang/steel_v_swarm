class_name AudioMove
extends Node

signal failed(category: String, operation: String, error: Error)

var state := AudioMoveState.new()
var buses: AudioBuses
var bank: NativeAudioMoveBank
var voices: Dictionary = {}
var worker := AudioMoveWorker.new()
var thread := Thread.new()
var context_origin := 0.0
var configured := false
var worker_ready := false
var resources := preload("res://scripts/audio_resource_snapshot.gd").new()

func configure(metadata: Dictionary, routing: AudioBuses, low_power: bool) -> Error:
	if configured or state.disposed or not is_inside_tree() or is_queued_for_deletion():
		return ERR_UNCONFIGURED
	if not is_instance_valid(routing) or routing.is_queued_for_deletion() or not routing.available():
		return ERR_UNCONFIGURED
	if not metadata.has("moveGraphs") or not metadata.has("moveTiming"):
		return ERR_INVALID_DATA
	process_mode = Node.PROCESS_MODE_ALWAYS
	buses = routing
	buses.retiring.connect(_retire, CONNECT_ONE_SHOT)
	state.configure(metadata)
	state.low_power = low_power
	state.refresh_clock = _advance
	state.registered.connect(_register)
	state.target_changed.connect(_target)
	worker.started.connect(_worker_started, Object.CONNECT_DEFERRED)
	configured = true
	return OK

func unlock(origin: float) -> void:
	if not _active() or state.unlocked:
		return
	context_origin = origin
	state.unlocked = true
	_advance()

func set_move(category: String, gain: float, pan: float = 0, rate: float = 1, wet: float = 0) -> void:
	if not _active():
		return
	_advance()
	state.set_move(category, gain, pan, rate, wet)
	if not _active():
		return
	var voice: AudioMoveVoice = voices.get(category)
	if voice == null or voice.activated:
		return
	if not thread.is_started():
		var error := thread.start(worker.run)
		if error != OK:
			voice.mixer.stop()
			voices.erase(category)
			voice.queue_free()
			failed.emit(category, "worker_start", error)
		return
	if worker_ready:
		_activate(category)

func _worker_started() -> void:
	if not _active():
		return
	worker_ready = true
	for category: String in voices.keys():
		_activate(category)

func _activate(category: String) -> void:
	if not _active():
		return
	var voice: AudioMoveVoice = voices.get(category)
	if voice == null or voice.activated:
		return
	var error := voice.activate()
	if error != OK:
		voices.erase(category)
		voice.queue_free()
		failed.emit(category, "activate", error)
		return
	if not worker.add(voice.mixer):
		voices.erase(category)
		voice.free()
		failed.emit(category, "worker_stopped", ERR_UNCONFIGURED)

func set_low_power(on: bool) -> void:
	if configured:
		_advance()
		state.set_low_power(on)

func stop_move() -> void:
	if configured:
		_advance()
		state.stop_move()

func _register(category: String) -> void:
	if not _active():
		return
	if bank == null:
		bank = resources.movement()
	if not _active():
		return
	if bank == null or not bank.valid():
		push_error("Missing original movement audio bank; regenerate and import source audio")
		failed.emit(category, "load_bank", ERR_UNAVAILABLE)
		return
	_advance()
	var voice := AudioMoveVoice.new()
	voices[category] = voice
	add_child(voice)
	if not _active():
		voice.retire()
		return
	var error := voice.configure(category, state.metadata, bank, buses, state.voices[category].values, context_origin)
	if error != OK:
		voices.erase(category)
		voice.free()
		if _active():
			failed.emit(category, "configure", error)
		return
	voice.failed.connect(func(operation: String, failure: Error) -> void: failed.emit(category, operation, failure))

func _target(category: String, key: String, target: float, tau: float, time: float) -> void:
	if not _active():
		return
	var voice: AudioMoveVoice = voices.get(category)
	if voice != null:
		voice.mixer.queue(key, target, tau, time)

func _advance() -> void:
	if _active() and state.unlocked:
		state.advance(maxf(0, buses.context_seconds() - context_origin - state.clock))

func _active() -> bool:
	return configured and not state.disposed and is_inside_tree() and not is_queued_for_deletion()

func _process(_delta: float) -> void:
	_advance()

func _retire() -> void:
	if state.disposed:
		return
	configured = false
	state.dispose()
	if is_instance_valid(buses) and buses.retiring.is_connected(_retire):
		buses.retiring.disconnect(_retire)
	worker.stop()
	if thread.is_started():
		thread.wait_to_finish()
	for voice: AudioMoveVoice in voices.values():
		voice.retire()

func _exit_tree() -> void:
	_retire()
