extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_pose.json")
	var data: Dictionary = Content.read_json("res://data/campaign_pose.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Cinematic pose capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Cinematic pose retains original camera functions and CSS identity")
	_check(data.source == capture.source and data.rules == capture.rules, "Native foreground transition resource equals original source")
	if failures > 0:
		_finish_pose()
		return
	var imported: Array = []
	for scene: Dictionary in Content.campaign.prologue:
		imported.append(scene.camera)
	for chapter: Dictionary in Content.campaign.scenes.values():
		for faction: Array in chapter.values():
			for scene: Dictionary in faction:
				imported.append(scene.camera)
	for program: Dictionary in capture.programs:
		_check(imported.has(program.camera), "Original captured camera exists unchanged in native campaign metadata")
		var layer = preload("res://scripts/campaign_art_layer.gd").new()
		add_child(layer)
		layer.layout_art(Vector2(1000, 500))
		for sample: Dictionary in program.frames:
			var layout := Vector2(sample.layout[0], sample.layout[1])
			if layer.size != layout:
				var previous: Tween = layer.pose_tween
				var displayed: Dictionary = layer.pose.duplicate()
				layer.layout_art(layout)
				_check(layer.pose_tween == previous and layer.pose == displayed, "Resizing preserves the running source transform transition")
			if sample.select:
				var target := CampaignRules.camera_pose(program.camera, sample.progress, program.landscape)
				layer.set_pose(target)
				_check(layer.pose_target == sample.target, "Original toFixed camera targets retain exact binary half-tie behavior")
			if layer.pose_tween != null and layer.pose_tween.is_valid():
				layer.pose_tween.pause()
				layer.pose_tween.custom_step(sample.delta)
			for key: String in ["x", "y", "scale"]:
				_near(layer.pose[key], sample.pose[key], "Original typed CSS transform interpolation, retarget and reversal: " + key)
			_check(layer.image.scale == Vector2(sample.pose.scale, sample.pose.scale) or absf(layer.image.scale.x - sample.pose.scale) < .000001,
				"Presented native foreground scale follows the browser interpolation")
			_check(layer.background.scale == Vector2.ONE and layer.background.position == (layer.size - layer.background.size) / 2,
				"Foreground pan and zoom leave the source background fixed")
			if sample.settled:
				var base := (float(sample.layout[1]) - float(sample.imageSize)) / 2
				var expected := Vector2(base + float(sample.imageSize) * float(sample.target.x) / 100,
					base + float(sample.imageSize) * float(sample.target.y) / 100)
				_check(layer.image.position == expected and layer.image.scale == Vector2(sample.target.scale, sample.target.scale),
					"Original settled percent translation and scale quantize only at native storage")
		layer.cancel()
		_check(layer.pose_tween == null or not layer.pose_tween.is_valid(), "Retired foreground cannot continue a transform transition")
		layer.free()
	_finish_pose()

func _finish_pose() -> void:
	print("CAMPAIGN_POSE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
