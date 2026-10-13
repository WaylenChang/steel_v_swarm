extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json")
	await CockpitSuite.run(self, fixtures)
	print("COCKPIT_PASS" if failures.is_empty() else "COCKPIT_FAIL", " poses=", fixtures.cockpitPoses.size(), " ports=", fixtures.cockpitMuzzles.size(), " assertions=", assertions)
	get_tree().quit(0 if failures.is_empty() else 1)
