extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_backdrop.json")
	var data: Dictionary = Content.read_json("res://data/campaign_backdrop.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 12,
		"Capture original cinematic backdrop geometry")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Runtime backdrop data retains the original browser rules")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current cinematic backdrop capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original cinematic backdrop source identity: " + path)
		_check(float(Content.campaign.presentation.art.backgroundScale) == float(capture.rules.scale),
			"Shared and dedicated source backdrop scale agree")
	if failures == 0:
		_check_cases(capture.cases)
	print("CAMPAIGN_BACKDROP assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(cases: Array) -> void:
	var layer := CampaignArtLayer.new()
	add_child(layer)
	for index in cases.size():
		var sample: Dictionary = cases[index]
		var size := Vector2(float(sample.size[0]), float(sample.size[1]))
		layer.layout_art(size)
		var expected := Rect2(float(sample.backdrop[0]), float(sample.backdrop[1]), float(sample.backdrop[2]), float(sample.backdrop[3]))
		var actual := Rect2(layer.background.position, layer.background.size)
		failure_scope = "campaign_backdrop_" + str(sample.size)
		_check(actual.position.distance_to(expected.position) < .0002 and actual.size.distance_to(expected.size) < .0002,
			"Original inset and transformed background bounds at " + str(sample.size) + " source=" + str(expected) + " native=" + str(actual))
		_check(layer.background.scale == Vector2.ONE, "Backdrop scale is baked into the rendered box exactly once")
		layer.pose = {"scale": 1.2, "x": -9.0, "y": 11.0}
		layer._apply_pose()
		_check(Rect2(layer.background.position, layer.background.size) == actual,
			"Foreground pan and zoom leave the original backdrop stationary")
	layer.free()
