extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json")
	await FootprintSuite.run(self, fixtures.shotFootprints)
	print("FOOTPRINT_PASS" if failures.is_empty() else "FOOTPRINT_FAIL", " cases=", fixtures.shotFootprints.size(), " assertions=", assertions)
	get_tree().quit(0 if failures.is_empty() else 1)
