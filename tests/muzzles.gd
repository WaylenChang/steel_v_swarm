extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json", ["muzzleLaunches"])
	await MuzzleTests.run(self, fixtures.muzzleLaunches)
	print("MUZZLE_PASS" if failures == 0 else "MUZZLE_FAIL", " assertions=", assertions)
	get_tree().quit(0 if failures == 0 else 1)
