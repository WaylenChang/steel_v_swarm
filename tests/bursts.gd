extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	await BurstTests.run(self, Content.read_json("res://data/fixtures.json"))
	print("BURST_PASS" if failures.is_empty() else "BURST_FAIL", " assertions=", assertions)
	get_tree().quit(0 if failures.is_empty() else 1)
