extends Node

var assertions := 0
var failures := 0

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAILURE: " + label)

func _ready() -> void:
	await _run_tests()
	print("FLASH_CAMPAIGN_REPLAY assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _stub_art_cache() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	for scene: Dictionary in Content.campaign.get("prologue", []):
		for key: String in ["img", "bg"]:
			if scene.has(key):
				var p := "res://" + String(scene[key])
				Content.art_cache[p] = tex
				Content.art_cache[p + "/mipmaps"] = tex
	for chapter_id: String in Content.campaign.get("scenes", {}):
		for side_key: String in Content.campaign.scenes[chapter_id]:
			for scene: Dictionary in Content.campaign.scenes[chapter_id][side_key]:
				for key: String in ["img", "bg"]:
					if scene.has(key):
						var p := "res://" + String(scene[key])
						Content.art_cache[p] = tex
						Content.art_cache[p + "/mipmaps"] = tex
	for chapter: Dictionary in Content.campaign.get("chapters", []):
		for side_key: String in ["STEEL", "SWARM"]:
			if chapter.has(side_key) and chapter[side_key].has("img"):
				var p := "res://" + String(chapter[side_key].img)
				Content.art_cache[p] = tex
				Content.art_cache[p + "/mipmaps"] = tex

func _run_tests() -> void:
	_stub_art_cache()

	var progress := CampaignProgress.new()
	var ending_data: Dictionary = Content.read_json("res://data/campaign_ending.json")
	var expected_chapter_replay_label: String = ending_data.rules.chapter.button
	var expected_prologue_label: String = ending_data.rules.prologue.button
	var expected_deploy_label: String = Content.label("story_deploy")
	var expected_briefing_label: String = Content.label("story_back_brief")

	_check(expected_chapter_replay_label == "▶ 返回戰區簡報", "Captured chapter return label has arrow")
	_check(expected_briefing_label == "返回戰區簡報", "Shared briefing label is arrowless")
	_check(expected_deploy_label == "▶ 出擊", "Deploy label is ▶ 出擊")
	_check(expected_prologue_label == "▶ 進入戰術終端", "Prologue terminal label is ▶ 進入戰術終端")

	var ui := CampaignUi.new()
	add_child(ui)
	ui.open(progress, "STEEL")
	var chapter := CampaignRules.chapter(0)
	ui.pilot = chapter.STEEL.heroes[0]
	await get_tree().process_frame

	# 1. Test chapter replay (_play_intro(false))
	var deployed := [false]
	ui.deployment_requested.connect(func(_settings: Dictionary): deployed[0] = true)

	ui._play_intro(false)
	await get_tree().process_frame

	_check(ui.cinematic.visible, "Cinematic visible during chapter replay")
	var replay_btn: Button = ui.cinematic.get("finish_button")
	_check(replay_btn != null and replay_btn.text == expected_chapter_replay_label,
		"Chapter replay displays captured chapter return label: " + (replay_btn.text if replay_btn != null else "null"))

	# Finish chapter replay returns to briefing without deploying
	ui.cinematic.finish()
	ui.cinematic.exit_deadline = 0
	ui.cinematic._complete_exit(ui.cinematic.generation)
	await get_tree().process_frame
	_check(not deployed[0], "Chapter replay finish does not trigger deployment")
	_check(not ui.cinematic.visible, "Cinematic hidden after chapter replay finish")

	# 2. Test deployment intro (_play_intro(true))
	ui._play_intro(true)
	await get_tree().process_frame

	_check(ui.cinematic.visible, "Cinematic visible during deployment intro")
	var deploy_btn: Button = ui.cinematic.get("finish_button")
	_check(deploy_btn != null and deploy_btn.text == expected_deploy_label,
		"Deployment intro displays deployment label: " + (deploy_btn.text if deploy_btn != null else "null"))

	ui.cinematic.finish()
	ui.cinematic.exit_deadline = 0
	ui.cinematic._complete_exit(ui.cinematic.generation)
	await get_tree().process_frame
	_check(deployed[0], "Deployment intro finish triggers deployment")

	# 3. Test separate briefing button retaining its own label and behavior
	ui._show_brief(0)
	await get_tree().process_frame
	var intro_btn: Button = null
	for child in ui.brief.get_children():
		if child is HBoxContainer:
			for btn in child.get_children():
				if btn is Button and btn.text == Content.label("story_intro"):
					intro_btn = btn
	_check(intro_btn != null, "Briefing section contains story_intro button")
	_check(expected_briefing_label == "返回戰區簡報", "Separate briefing button retains arrowless label")

	# 4. Test prologue terminal label
	ui._play_prologue()
	await get_tree().process_frame
	var prologue_btn: Button = ui.cinematic.get("finish_button")
	_check(prologue_btn != null and prologue_btn.text == expected_prologue_label,
		"Prologue terminal displays captured prologue button label: " + (prologue_btn.text if prologue_btn != null else "null"))

	ui.cinematic.finish()
	ui.cinematic.exit_deadline = 0
	ui.cinematic._complete_exit(ui.cinematic.generation)
	await get_tree().process_frame

	remove_child(ui)
	ui.free()
	await get_tree().process_frame
