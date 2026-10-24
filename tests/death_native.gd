extends "res://tests/run.gd"

const DeathSequenceTests = preload("res://tests/death_sequence_suite.gd")

func _run() -> void:
	var reader := preload("res://tests/death_render.gd").new()
	var fixtures: Dictionary = reader._captured_fixtures()
	reader.free()
	_check(not fixtures.is_empty(), "Capture current original death-camera and overlay references")
	if not fixtures.is_empty():
		_sequences(fixtures)
		DeathSequenceTests._overlay(self, fixtures)
	print("DEATH_NATIVE assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _sequences(fixtures: Dictionary) -> void:
	for item: Dictionary in fixtures.deathSequences:
		var sequence := DeathSequenceState.new()
		var draws := {"count": 0}
		var calls: Array = []
		var queries: Array = []
		sequence.random_sample = func():
			var value := float(item.random[int(draws.count) % item.random.size()])
			draws.count += 1
			return value
		var active_sequence: WeakRef = weakref(sequence)
		sequence.output = func(command):
			var row: Dictionary = command.duplicate()
			if row.get("point") is Vector3:
				row.point = [row.point.x, row.point.y, row.point.z]
			if row.get("frame") is Transform3D:
				row.frame = DeathSequenceTests._matrix(row.frame)
			calls.append(row)
			if command.type == "cut" and not item.deferred:
				(active_sequence.get_ref() as DeathSequenceState).finish()
		var surface := func(point: Vector3):
			queries.append([point.x, point.y, point.z])
			return 20 + maxf(0, point.x - 15) * .04
		var seed: Dictionary = item.input.duplicate(true)
		for key: String in ["position", "velocity", "angles"]:
			seed[key] = BodyPose.vector(seed[key])
		seed.eye = preload("res://tests/view_suite.gd").frame(seed.eye)
		_check(sequence.begin(seed, surface), "Original death sequence begins from the last live view")
		DeathSequenceTests._compare(self, sequence, item.initial, calls, queries, int(draws.count))
		for step: Dictionary in item.steps:
			calls.clear()
			queries.clear()
			if step.action in ["respawn", "cut"]:
				sequence.finish()
			else:
				sequence.advance(float(step.delta), surface)
			DeathSequenceTests._compare(self, sequence, step, calls, queries, int(draws.count))
		sequence.output = Callable()
		sequence.random_sample = Callable()
