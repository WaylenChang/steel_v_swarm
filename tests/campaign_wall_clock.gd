extends "res://tests/run.gd"

class ProbeView extends CampaignCinematic:
	var frames := 0
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer
	func _update_scene() -> void:
		pass
	func _process(delta: float) -> void:
		frames += 1
		super._process(delta)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	super._ready()

func _run() -> void:
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for name: String in ["campaign_crawl", "campaign_art", "campaign_pose", "campaign_hold", "campaign_transition"]:
		var capture: Dictionary = Content.read_json("res://tests/fixtures/" + name + ".json")
		_check(capture.get("source") is Dictionary, "Load original cinematic clock reference: " + name)
		if not capture.get("source") is Dictionary:
			continue
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current cinematic clock reference: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original cinematic clock source identity: " + path)
	if failures == 0:
		for sample: Dictionary in [{"paused": false, "scale": 0.0}, {"paused": true, "scale": 1.0}, {"paused": true, "scale": 0.0}]:
			await _check_wall_clock(sample)
	print("CAMPAIGN_WALL_CLOCK assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_wall_clock(sample: Dictionary) -> void:
	failure_scope = "campaign_wall_clock_paused_%s_scale_%s" % [sample.paused, sample.scale]
	var parent := Node.new()
	parent.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(parent)
	var view := ProbeView.new()
	parent.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play([Content.campaign.prologue[0]], "Continue")
	for index in range(3):
		await get_tree().process_frame
	var layer: CampaignArtLayer = view.art_layers[0]
	if layer.tween != null and layer.tween.is_valid():
		layer.tween.kill()
	layer.opacity = 0
	layer.selected = false
	layer.transition.clear()
	var art_started := Time.get_ticks_usec()
	layer.select(true)
	layer.set_pose({"scale": 1.2, "x": 10, "y": -10})
	view.hold_indicator.begin(Vector2(100, 100), Vector2(640, 360))
	view.hold_indicator.advance(.5)
	var initial_frames := view.frames
	var old_scale := Engine.time_scale
	Engine.time_scale = float(sample.scale)
	get_tree().paused = bool(sample.paused)
	await _wait_wall(300000)
	var art_elapsed := float(Time.get_ticks_usec() - art_started) / 1000000.0
	var curve: Array = layer.rules.curve
	var expected_opacity := HurtFlashState.bezier_values(clampf(art_elapsed / float(layer.rules.duration), 0, 1),
		float(curve[0]), float(curve[1]), float(curve[2]), float(curve[3]))
	print("CAMPAIGN_WALL_SAMPLE ", JSON.stringify({"paused": sample.paused, "scale": sample.scale,
		"frames": view.frames - initial_frames, "art": layer.opacity, "pose": layer.pose_progress,
		"elapsed": art_elapsed, "expected_art": expected_opacity, "hold": view.hold_indicator.opacity, "dash": view.hold_indicator.dash_offset,
		"dash_target": view.hold_indicator.dash_target}))
	_check(view.frames > initial_frames, "Original cinematic animation frame continues on wall time")
	# This wall-scheduling gate is coarse; campaign_art retains the exact browser raster checks.
	_check(absf(layer.opacity - expected_opacity) < .12 and layer.pose_progress > .5,
		"Original art and camera transitions follow wall time")
	_check(view.hold_indicator.opacity > .9, "Original hold opacity continues on wall time")
	_check(absf(view.hold_indicator.dash_offset - view.hold_indicator.dash_target) < .02,
		"Original hold progress transition continues on wall time")
	var mouse := InputEventMouseButton.new()
	mouse.position = Vector2(100, 100)
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await get_tree().process_frame
	_check(view.held_at >= 0, "Cinematic input remains available during the original wall-clock animation")
	mouse = InputEventMouseButton.new()
	mouse.position = Vector2(100, 100)
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	Input.parse_input_event(mouse)
	await get_tree().process_frame
	_check(view.held_at < 0, "Releasing cinematic input cancels the hold while gameplay is paused")
	var completed := {"count": 0, "at": 0.0}
	view.finished.connect(func(): completed.count += 1; completed.at = view._now_msec())
	var started := view._now_msec()
	view.finish()
	await _wait_wall(200000)
	print("CAMPAIGN_EXIT_SAMPLE ", JSON.stringify({"paused": sample.paused, "scale": sample.scale,
		"elapsed": view._now_msec() - started, "opacity": view.fade_opacity, "playing": view.playing}))
	_check(view.playing and view.fade_opacity < .8, "Original exit fade advances before its wall deadline")
	await _wait_wall(600000)
	_check(completed.count == 1 and completed.at - started >= float(Content.campaign.presentation.skip.fade) * 1000,
		"Original exit completes once after its wall deadline")
	get_tree().paused = false
	Engine.time_scale = old_scale
	view.free()
	parent.free()

func _wait_wall(microseconds: int) -> void:
	var deadline := Time.get_ticks_usec() + microseconds
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
