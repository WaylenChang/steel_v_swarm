extends Node

const MusicTests = preload("res://tests/audio_music_suite.gd")
const AmbienceTests = preload("res://tests/audio_ambience_suite.gd")
const MovementTests = preload("res://tests/audio_move_suite.gd")
const SceneTests = preload("res://tests/audio_scene_suite.gd")
const LocalFireTests = preload("res://tests/local_fire_suite.gd")
const FeedbackTests = preload("res://tests/local_feedback_suite.gd")

var assertions := 0
var failures: Array[String] = []
var section := "provenance"

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(section + ": " + description)
		push_error(failures[-1])

func _near(actual: float, expected: float, description: String) -> void:
	_check(absf(actual - expected) < .000001, description + " actual=" + str(actual) + " expected=" + str(expected))

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://data/audio_lifecycle.json")
	_check(capture.get("formatVersion") == 1 and capture.get("fixtures") is Dictionary and capture.get("source") is Dictionary,
		"Generate original audio lifecycle references before native verification")
	if not failures.is_empty():
		_finish()
		return
	var source: Dictionary = capture.source
	_check(source.get("inputs") is Dictionary and not source.inputs.is_empty() and
		source.get("sourceInputs") is Dictionary and not source.sourceInputs.is_empty(), "Lifecycle capture retains complete source/generator identity")
	if not failures.is_empty():
		_finish()
		return
	for path: String in source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == source.inputs[path], "Original lifecycle generator is current: " + path)
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == source.sourceInputs[path], "Original source matches the imported runtime metadata: " + path)
	if not failures.is_empty():
		_finish()
		return
	var fixtures: Dictionary = capture.fixtures
	var metadata: Dictionary = Content.balance.audio
	section = "streamed music state"
	MusicTests.run(self, fixtures, metadata)
	section = "ambience state/envelopes"
	AmbienceTests.run(self, fixtures, metadata)
	section = "movement state/bank"
	MovementTests.run(self, fixtures, metadata)
	section = "location/source selection"
	SceneTests.run(self, fixtures, metadata)
	section = "immediate local fire"
	LocalFireTests.run(self, fixtures)
	section = "shared fire/cast warning clocks"
	FeedbackTests.run(self, fixtures)
	_finish()

func _finish() -> void:
	print("AUDIO_LIFECYCLE assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
