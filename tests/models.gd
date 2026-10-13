extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json")
	await ModelSuite.run(self, fixtures.modelCentres)
	print("MODEL_CENTRE_PASS" if failures.is_empty() else "MODEL_CENTRE_FAIL", " cases=", fixtures.modelCentres.size(), " assertions=", assertions)
	get_tree().quit(0 if failures.is_empty() else 1)
