extends Node

const ClipTests = preload("res://tests/audio_clip_suite.gd")
const SynthesisTests = preload("res://tests/audio_synthesis_suite.gd")

var assertions := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _near(actual: float, expected: float, description: String) -> void:
	_check(absf(actual - expected) < .000001, description + " actual=" + str(actual) + " expected=" + str(expected))

func _run() -> void:
	if not Content.balance.has("audio"):
		_check(false, "Import original source audio metadata before native resource verification")
	else:
		ClipTests.run(self)
		SynthesisTests.run(self, Content.balance.audio)
	print("AUDIO_RESOURCES assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
