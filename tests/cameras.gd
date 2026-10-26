extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	await CameraTests.run(self, Content.read_json("res://data/fixtures.json", Content.fixture_sections_for(CameraTests)))
	print("CAMERA_PASS" if failures == 0 else "CAMERA_FAIL", " assertions=", assertions)
	get_tree().quit(0 if failures == 0 else 1)
