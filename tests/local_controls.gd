extends Node

const CastTests = preload("res://tests/local_cast_suite.gd")
const DefenseTests = preload("res://tests/local_defense_suite.gd")
const StatusTests = preload("res://tests/local_status_suite.gd")
const EffectTests = preload("res://tests/control_effect_suite.gd")
const Helper = preload("res://tests/status_suite.gd")

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
	var capture: Dictionary = Content.read_json("res://tests/fixtures/local_controls.json")
	_check(capture.get("formatVersion") == 1 and capture.get("fixtures") is Dictionary and
		capture.get("source") is Dictionary and capture.get("metadata") is Dictionary,
		"Generate original local controls references before native verification")
	if not failures.is_empty():
		_finish()
		return
	var source: Dictionary = capture.source
	_check(source.get("inputs") is Dictionary and not source.inputs.is_empty() and
		source.get("sourceInputs") is Dictionary and not source.sourceInputs.is_empty(), "Local controls retain source/generator identity")
	if not failures.is_empty():
		_finish()
		return
	for path: String in source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == source.inputs[path], "Local controls generator is current: " + path)
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == source.sourceInputs[path], "Local controls match imported source: " + path)
	if not failures.is_empty():
		_finish()
		return
	for key: String in capture.metadata:
		Helper.compare(self, Content.balance.controls.get(key), capture.metadata[key], "Original local controls metadata: " + key)
	if not failures.is_empty():
		_finish()
		return
	CastTests.run(self, capture.fixtures)
	DefenseTests.run(self, capture.fixtures)
	StatusTests.run(self, capture.fixtures)
	EffectTests.run(self, capture.fixtures)
	_finish()

func _finish() -> void:
	print("LOCAL_CONTROLS assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
