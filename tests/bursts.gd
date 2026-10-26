extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	await BurstTests.run(self, Content.read_json("res://data/fixtures.json", Content.fixture_sections_for(BurstTests)))
	print("BURST_PASS" if failures == 0 else "BURST_FAIL", " assertions=", assertions)
	get_tree().quit(0 if failures == 0 else 1)
