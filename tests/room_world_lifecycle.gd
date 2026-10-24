extends Node

const ResourceTests = preload("res://tests/room_world_resources_suite.gd")
const PrebuildTests = preload("res://tests/room_world_prebuild_suite.gd")

var assertions := 0
var failures: Array[String] = []

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func():
		push_error("ROOM_WORLD_LIFECYCLE_TIMEOUT")
		get_tree().quit(1))
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	await ResourceTests.run(self)
	await PrebuildTests.run(self)
	print("ROOM_WORLD_LIFECYCLE assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
