extends "res://tests/run.gd"

const Hold = preload("res://scripts/campaign_hold.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_hold.json")
	var resource: Dictionary = Content.read_json("res://data/campaign_hold.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Hold capture generator is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Hold oracle retains original CSS, markup and handler identity")
	_check(resource == {"formatVersion": capture.formatVersion, "source": capture.source, "rules": capture.rules, "plateSha256": capture.plateSha256},
		"Dedicated native hold resource equals source capture")
	_check(FileAccess.get_sha256(capture.rules.plate) == capture.plateSha256, "Original static ring and caption pixels retain their source hash")
	var texture := ResourceLoader.load(capture.rules.image, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	_check(texture != null and texture.get_meta("source", {}) == capture.source and texture.get_meta("plateSha256", "") == capture.plateSha256,
		"Reloaded native hold resource retains original source identity")
	var plate := Image.new()
	var decoded := plate.load_png_from_buffer(FileAccess.get_file_as_bytes(capture.rules.plate)) == OK
	_check(decoded and texture != null and texture.get_image().get_data() == plate.get_data(),
		"Native hold publication preserves transparent source pixels without alpha-border retuning")
	if failures > 0:
		_finish_hold()
		return
	for program: Dictionary in capture.programs:
		var hold := Hold.new()
		add_child(hold)
		var elapsed := 0.0
		var target := -1.0
		for frame: Dictionary in program.frames:
			var changed := target != float(frame.target)
			target = frame.target
			if program.channel == "opacity":
				if changed:
					hold.opacity_tween = preload("res://scripts/css_transition.gd").start(hold, "opacity", target,
						hold.rules.opacityDuration, hold.opacity_tween, hold.opacity_transition, hold._ease)
			else:
				hold._set_offset(target)
			var tween: Tween = hold.opacity_tween if program.channel == "opacity" else hold.dash_tween
			if changed:
				elapsed = 0
			if tween != null and tween.is_valid():
				tween.pause()
				tween.custom_step(maxf(0, float(frame.time) - elapsed))
			elapsed = frame.time
			var presented: float = hold.opacity if program.channel == "opacity" else hold.dash_offset
			var tolerance := .000001 if program.channel == "opacity" else .00051
			_check(absf(presented - float(frame.value)) < tolerance, "Original browser hold ease, dash smoothing and reversing-shortened transitions")
			if program.channel == "opacity":
				_check(absf(hold.group.self_modulate.a - presented) < .000001, "Hold opacity reaches the complete native canvas group in the same frame")
		hold.reset()
		_check(hold.opacity == 0 and not hold.active and hold.opacity_transition.is_empty() and hold.dash_transition.is_empty(),
			"Retired hold presentation kills both transitions and discards reversal state")
		hold.free()
	for program: Dictionary in capture.motion:
		var hold := Hold.new()
		add_child(hold)
		var began := 0.0
		for frame: Dictionary in program.frames:
			match frame.operation.type:
				"begin":
					began = frame.operation.time
					hold.begin(Vector2(program.point[0], program.point[1]), Vector2(program.viewport[0], program.viewport[1]))
				"cancel": hold.cancel()
				"frame": hold.advance((float(frame.operation.time) - began) / (float(Content.campaign.presentation.skip.hold) * 1000))
			_check(hold.active == frame.active, "Original active hold and cancel state")
			_check(hold.global_position == Vector2(frame.position[0], frame.position[1]), "Original zero-coordinate fallback, fractional pointer and small-viewport clamp order")
			_near(hold.dash_target, frame.offset, "Original double circumference and per-frame dash target")
			if hold.opacity_tween != null and hold.opacity_tween.is_valid():
				hold.opacity_tween.pause()
			if hold.dash_tween != null and hold.dash_tween.is_valid():
				hold.dash_tween.pause()
		hold.reset()
		hold.free()
	var restarted := Hold.new()
	add_child(restarted)
	restarted.begin(Vector2(100, 100), Vector2(1024, 768))
	var first_fade: Tween = restarted.opacity_tween
	first_fade.pause()
	first_fade.custom_step(.04)
	var first_opacity: float = restarted.opacity
	restarted.begin(Vector2(200, 200), Vector2(1024, 768))
	_check(restarted.opacity_tween == first_fade and restarted.opacity == first_opacity,
		"Restarting an active pointer hold coalesces source class removal/addition without restarting opacity")
	restarted.reset()
	restarted.free()
	_finish_hold()

func _finish_hold() -> void:
	print("CAMPAIGN_HOLD assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
