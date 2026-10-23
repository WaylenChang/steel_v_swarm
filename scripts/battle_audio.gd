class_name BattleAudio
extends Node

signal failed(operation: String, error: Error)

var preferences := AudioPreferences.new()
var rules := AudioRules.new()
var budget := AudioVoiceBudget.new()
var samples := AudioSampleLibrary.new()
var synthesis := AudioSynthesisLibrary.new()
var random := RandomNumberGenerator.new()
var buses: AudioBuses
var music: AudioMusic
var ambience: AudioAmbience
var movement: AudioMove
var configured := false
var unlocked := false
var disposed := false
var low_power := false
var clock_origin_usec := 0
var context_origin := 0.0

func configure(metadata: Dictionary, persist: bool = false, low: bool = false) -> Error:
	if configured or disposed:
		return ERR_ALREADY_IN_USE
	if not is_inside_tree():
		return ERR_UNCONFIGURED
	for key: String in ["synthesisIds", "musicTiming", "ambienceTiming", "proceduralMusic", "settings", "samples", "moveGraphs", "moveTiming"]:
		if not metadata.has(key):
			return ERR_INVALID_DATA
	process_mode = Node.PROCESS_MODE_ALWAYS
	low_power = low
	rules.configure(metadata)
	budget.configure(metadata)
	synthesis.configure(metadata)
	preferences.configure(metadata)
	preferences.persist = persist
	preferences.save_failed.connect(func(error: Error) -> void: _failure("save_preferences", error))
	var preference_error := preferences.load_save()
	if preference_error != OK:
		_failure("load_preferences", preference_error)
	random.randomize()
	buses = AudioBuses.new()
	add_child(buses)
	var error := buses.configure()
	if error != OK:
		return error
	music = AudioMusic.new()
	add_child(music)
	error = music.configure(metadata, preferences, buses)
	if error != OK:
		return error
	music.state.low_power = low_power
	music.track_failed.connect(func(_scene: String, failure: Error) -> void: failed.emit("music", failure))
	ambience = AudioAmbience.new()
	add_child(ambience)
	error = ambience.configure(metadata, buses)
	if error != OK:
		return error
	ambience.state.low_power = low_power
	ambience.bed_failed.connect(func(_id: String, failure: Error) -> void: failed.emit("ambience", failure))
	movement = AudioMove.new()
	add_child(movement)
	error = movement.configure(metadata, buses, low_power)
	if error != OK:
		return error
	movement.failed.connect(func(_category: String, operation: String, failure: Error) -> void: _failure("movement_" + operation, failure))
	configured = true
	return OK

func _input(event: InputEvent) -> void:
	if not configured or disposed:
		return
	if event is InputEventKey and event.pressed or event is InputEventMouseButton and event.pressed or event is InputEventScreenTouch and event.pressed:
		unlock()

func unlock() -> void:
	if not configured or disposed or unlocked:
		return
	var effective_gain := VisualPreferences._number(preferences.sfx_volume) if ControlPreferences.truthy(preferences.sfx_on) else 0.0
	if not is_finite(effective_gain) or effective_gain < 0:
		disposed = true
		_failure("unlock_volume" if not is_finite(effective_gain) else "unsupported_sfx_polarity", ERR_INVALID_PARAMETER if not is_finite(effective_gain) else ERR_UNAVAILABLE)
		return
	clock_origin_usec = Time.get_ticks_usec()
	context_origin = buses.context_seconds()
	var error := samples.load_samples(low_power)
	if error != OK:
		_failure("load_samples", error)
	music.state.unlock()
	ambience.state.unlocked = true
	movement.unlock(context_origin)
	unlocked = true

func set_scene(name: String) -> void:
	if configured and not disposed:
		music.state.set_scene(name)

func set_low_power(on: bool) -> void:
	if not configured or disposed:
		return
	low_power = on
	music.state.low_power = on
	ambience.state.low_power = on
	movement.set_low_power(on)
	if not on and unlocked and not samples.loaded:
		var error := samples.load_samples(false)
		if error != OK:
			_failure("load_samples", error)
		music.state.register_current()

func set_ambience(query: Dictionary) -> void:
	if configured and not disposed:
		ambience.set_ambience(query)

func set_move(category: String, gain: float, pan: float = 0, rate: float = 1, wet: float = 0) -> void:
	if _can_play():
		movement.set_move(category, gain, pan, rate, wet)

func stop_move() -> void:
	if configured and not disposed:
		movement.stop_move()

func fire(definition: Variant, slot: String, side: String) -> void:
	if not _can_play():
		return
	var id := rules.fire_id(definition, slot, side)
	if not id.is_empty():
		_play(id, float(rules.rules.ownFire.heavy if slot == "heavy" else rules.rules.ownFire.light), 0)

func on_source_event(event: Dictionary, source_camera: Variant, own_id: Variant) -> void:
	if not _can_play() or not event.has("e"):
		return
	for plan: Dictionary in rules.event_plan(event, source_camera, own_id):
		_play(plan.id, float(plan.gain), float(plan.pan))

func ui(id: String) -> void:
	if not _can_play():
		return
	var plan: Dictionary = rules.rules.ui.get(id, rules.rules.ui.unknown)
	_play(plan.id, float(plan.gain), float(plan.pan))

func _can_play() -> bool:
	return configured and unlocked and not disposed

func _play(id: String, gain: float, pan: float) -> void:
	if not budget.allow(id, _now(), _wall_now()):
		return
	if not is_finite(gain) or gain < 0 or not is_finite(pan):
		_failure("voice_parameters", ERR_INVALID_PARAMETER)
		return
	var voice := AudioVoice.new()
	add_child(voice)
	var error: Error
	var duration: float
	if samples.has_sample(id, low_power):
		var takes: Array = samples.buffers[id]
		var durations: Array = takes.map(func(clip: NativeAudioClip) -> float: return clip.duration())
		var choice := budget.sample_choice(id, durations, _sample_random)
		error = voice.start(takes[int(choice.index)], buses, gain, pan, float(choice.rate))
		duration = float(choice.duration)
	else:
		var definition := synthesis.definition(id)
		if definition == null:
			voice.free()
			if rules.rules.synthesisIds.has(id):
				_failure("load_synthesis", ERR_UNAVAILABLE)
			return
		var stems := synthesis.render(id, gain)
		error = voice.start_synthesis(stems, buses, pan)
		duration = definition.reservation_seconds
	if error != OK:
		voice.free()
		_failure("start_voice", error)
		return
	budget.reserve(duration, _wall_now())

func _sample_random() -> float:
	# Math.random excludes one; native randf includes both endpoints.
	return float(random.randi()) / 4294967296.0

func _now() -> float:
	return buses.context_seconds() - context_origin if unlocked else 0.0

func _wall_now() -> float:
	return (Time.get_ticks_usec() - clock_origin_usec) / 1000000.0

func _process(_delta: float) -> void:
	if _can_play():
		budget.advance(_wall_now())

func _failure(operation: String, error: Error) -> void:
	push_error("Audio " + operation + ": " + error_string(error))
	failed.emit(operation, error)

func _exit_tree() -> void:
	disposed = true
