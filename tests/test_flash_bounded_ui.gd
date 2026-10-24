extends Node

const StatusIconSuite = preload("res://tests/status_icon_suite.gd")
const CombatFeedSuite = preload("res://tests/combat_feed_suite.gd")
const VisualSettingsScript = preload("res://scripts/visual_settings.gd")

var checks_passed := 0
var checks_failed := 0

func _check(condition: bool, message: String) -> void:
	if condition:
		checks_passed += 1
	else:
		checks_failed += 1
		push_error("FAILED: " + message)

func _near(a: float, b: float, message: String, tolerance := 0.001) -> void:
	_check(absf(a - b) <= tolerance, "%s: expected %f, got %f" % [message, b, a])

func _ready() -> void:
	print("--- Running Flash Bounded UI & Settings Suite ---")
	_test_native_ui()
	_test_visual_settings()
	_test_settings_panels()
	_test_room_editors()
	_test_boss_hud()
	_test_status_icons_and_combat_feed()
	print("--- Flash Bounded UI Suite Finished: %d passed, %d failed ---" % [checks_passed, checks_failed])
	if checks_failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)

func _test_native_ui() -> void:
	var p := NativeUi.panel(Vector2(400, 300))
	_check(p != null and p is PanelContainer, "NativeUi.panel returns PanelContainer")
	p.free()
	var b := NativeUi.button("Test", func(): pass)
	_check(b != null and b.text == "Test", "NativeUi.button returns Button with text")
	b.free()
	var l := NativeUi.label("LabelTest", 16)
	_check(l != null and l.text == "LabelTest", "NativeUi.label returns Label")
	l.free()
	var prose := NativeUi.prose("ProseTest", 14)
	_check(prose != null and prose is RichTextLabel, "NativeUi.prose returns RichTextLabel")
	prose.free()

func _test_visual_settings() -> void:
	var vs = VisualSettingsScript.new()
	add_child(vs)
	vs.configure(Visuals)
	_check(vs.preset_select != null, "VisualSettings creates preset selector")
	_check(vs.lang_select != null, "VisualSettings creates world text language selector")
	_check(vs.reset_button != null, "VisualSettings creates reset button")
	
	# Test preset selection with valid presets from Content
	var initial_preset := Visuals.preset_id
	var test_preset := "sakura" if initial_preset != "sakura" else "neon"
	Visuals.select_preset(test_preset)
	vs._sync()
	_check(Visuals.preset_id == test_preset, "VisualPreferences switches preset")
	_check(not Visuals.is_default(), "VisualPreferences is not default when modified")
	
	# Test reset
	vs.reset_button.emit_signal("pressed")
	_check(Visuals.is_default(), "Reset button returns VisualPreferences to default")
	vs.queue_free()

func _test_settings_panels() -> void:
	Content.initialize_local_balance(false)
	var bs := BalanceSettings.new()
	add_child(bs)
	bs.configure(Content.balance_preferences)
	_check(bs.widgets.size() > 0, "BalanceSettings generates knob sliders")
	_check(bs.reset_button != null, "BalanceSettings creates reset button")
	bs.queue_free()

	var cs := ControlSettings.new()
	add_child(cs)
	cs.configure(Controls, NativeGyro.new())
	_check(cs.mode_select != null, "ControlSettings creates mode selector")
	_check(cs.scheme_select != null, "ControlSettings creates scheme selector")
	cs.queue_free()

func _test_room_editors() -> void:
	var rpe := RoomPlayerEditor.new()
	add_child(rpe)
	_check(rpe.sides != null, "RoomPlayerEditor creates sides OptionButton")
	_check(rpe.characters != null, "RoomPlayerEditor creates character OptionButton")
	rpe.queue_free()

	var rbe := RoomBotEditor.new()
	add_child(rbe)
	_check(rbe.difficulty != null, "RoomBotEditor creates difficulty OptionButton")
	_check(rbe.difficulty.item_count > 0, "RoomBotEditor populates bot difficulty options")
	_check(rbe.add_buttons.size() == 2, "RoomBotEditor creates add buttons for both sides")
	rbe.queue_free()

func _test_boss_hud() -> void:
	var hud := BossHud.new()
	add_child(hud)
	_check(hud.title != null, "BossHud creates title Label")
	_check(not hud.visible, "BossHud starts hidden")
	hud.queue_free()

func _test_status_icons_and_combat_feed() -> void:
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string("res://data/fixtures.json"))
	if error != OK:
		_check(false, "Failed to parse fixtures.json for Flash UI tests")
		return
	var registry: Dictionary = parser.data
	var sections := SourceFixtureSections.load_sections(registry, "res://data/fixtures.json", ["statusIcons", "statusIconRender", "combatFeed"])
	_check(sections.has("statusIcons") and sections.has("statusIconRender"), "Loaded status icon fixture sections")
	_check(sections.has("combatFeed"), "Loaded combat feed fixture sections")
	
	StatusIconSuite.run(self, sections)
	CombatFeedSuite.run(self, sections)
