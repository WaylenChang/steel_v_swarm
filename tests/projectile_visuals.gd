extends "res://tests/run.gd"

func _run() -> void:
	await get_tree().process_frame
	await ProjectileVisualTests.run(self, Content.read_json("res://data/fixtures.json", Content.fixture_sections_for(ProjectileVisualTests)))
	print("PROJECTILE_VISUAL_PASS" if failures == 0 else "PROJECTILE_VISUAL_FAIL", " assertions=", assertions)
	get_tree().quit(0 if failures == 0 else 1)
