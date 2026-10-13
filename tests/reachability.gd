extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json")
	await ReachabilitySuite.run(self, fixtures.reachability)
	print("REACHABILITY_PASS" if failures.is_empty() else "REACHABILITY_FAIL", " cases=", fixtures.reachability.size(), " assertions=", assertions)
	get_tree().quit(0 if failures.is_empty() else 1)
