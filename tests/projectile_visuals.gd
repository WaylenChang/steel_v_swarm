extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	await ProjectileVisualTests.run(self, Content.read_json("res://data/fixtures.json"))
	print("PROJECTILE_VISUAL_PASS" if failures.is_empty() else "PROJECTILE_VISUAL_FAIL", " assertions=", assertions)
	get_tree().quit(0 if failures.is_empty() else 1)
