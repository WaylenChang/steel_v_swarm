extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	await CameraTests.run(self, Content.read_json("res://data/fixtures.json"))
	print("CAMERA_PASS" if failures.is_empty() else "CAMERA_FAIL", " assertions=", assertions)
	get_tree().quit(0 if failures.is_empty() else 1)
