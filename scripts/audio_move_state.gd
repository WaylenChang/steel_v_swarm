class_name AudioMoveState
extends RefCounted

signal registered(category: String)
signal target_changed(category: String, key: String, target: float, tau: float, time: float)

var metadata: Dictionary = {}
var voices: Dictionary = {}
var unlocked := false
var low_power := false
var disposed := false
var clock := 0.0
var refresh_clock := Callable()

func configure(rules: Dictionary) -> void:
	metadata = rules
	voices.clear()
	clock = 0

func set_move(category: String, gain: float, pan: float = 0, rate: float = 1, wet: float = 0) -> void:
	if disposed or not unlocked or low_power:
		return
	if not metadata.moveGraphs.has(category):
		push_error("Unsupported original movement audio category: " + category)
		return
	if not is_finite(gain) or not is_finite(pan) or not is_finite(rate) or not is_finite(wet):
		push_error("Movement audio controls must be finite")
		return
	var timing: Dictionary = metadata.moveTiming
	if not voices.has(category):
		if gain <= float(timing.creationThreshold):
			return
		var graph: Dictionary = metadata.moveGraphs[category]
		voices[category] = {"category": category, "values": {"gain": float(graph.nodes[int(graph.g)].parameters.gain.initial),
			"pan": float(graph.nodes[int(graph.pan)].parameters.pan.initial), "rate": 1.0,
			"wet": float(graph.nodes[int(graph.wet)].parameters.gain.initial) if graph.wet != null else 0.0}, "targets": {}}
		registered.emit(category)
	if refresh_clock.is_valid():
		refresh_clock.call()
	var voice: Dictionary = voices[category]
	_target(voice, "gain", maxf(float(timing.gainFloor), clampf(gain, 0, 1) * float(metadata.movement[category])), timing.timeConstant)
	_target(voice, "pan", clampf(pan, -1, 1), timing.timeConstant)
	_target(voice, "rate", clampf(rate, timing.minimumRate, timing.maximumRate), timing.timeConstant)
	if metadata.moveGraphs[category].wet != null:
		_target(voice, "wet", clampf(wet, 0, 1), timing.timeConstant)

func _target(voice: Dictionary, key: String, target: float, time_constant: float) -> void:
	voice.targets[key] = {"target": target, "time": clock, "tau": time_constant}
	target_changed.emit(voice.category, key, target, time_constant, clock)

func set_low_power(on: bool) -> void:
	low_power = on
	if on:
		stop_move()

func stop_move() -> void:
	if disposed or not unlocked:
		return
	for voice: Dictionary in voices.values():
		_target(voice, "gain", metadata.moveTiming.gainFloor, metadata.moveTiming.stopTimeConstant)

func advance(seconds: float) -> void:
	if disposed or not is_finite(seconds) or seconds <= 0:
		return
	clock += seconds
	for voice: Dictionary in voices.values():
		for key: String in voice.targets:
			var automation: Dictionary = voice.targets[key]
			voice.values[key] = float(automation.target) + (float(voice.values[key]) - float(automation.target)) * exp(-seconds / float(automation.tau))

func dispose() -> void:
	disposed = true
