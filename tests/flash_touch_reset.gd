extends Node

var assertions := 0
var failures := 0

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAILURE: " + label)

func _create_controls() -> NativeTouchControls:
	Controls.configure(Content.balance.mobile)
	Controls.set_scheme("pad")
	var controls := NativeTouchControls.new()
	controls.size = Vector2(1280, 720)
	controls.configure(Controls)
	return controls

func _ready() -> void:
	_test_fresh_holds()
	_test_reentry_mirror_retained()
	_test_same_pointer_replacement()
	_test_nested_resets()
	_test_focus_out_reset()
	_test_overlay_reset()
	_test_node_retirement()
	print("FLASH_TOUCH_RESET assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _test_fresh_holds() -> void:
	var controls := _create_controls()
	add_child(controls)
	controls.sync(true, false)

	_check(controls.held.is_empty(), "Initial held mirror is empty")
	controls.state.button_down("fire", 1, Vector2.ZERO, 1000)
	controls.state.button_down("jump", 2, Vector2.ZERO, 1000)
	_check(controls.held.get("fire", false) == true, "Fresh fire hold mirrored in controls")
	_check(controls.held.get("jump", false) == true, "Fresh jump hold mirrored in controls")
	_check(controls.state.held.size() == 2, "TouchState holds both pointers")

	controls.state.up(1, Vector2.ZERO, 1050)
	_check(not controls.held.has("fire"), "Released fire hold erased from controls mirror")
	_check(controls.held.get("jump", false) == true, "Retained jump hold remains in mirror")

	controls.state.up(2, Vector2.ZERO, 1050)
	_check(controls.held.is_empty(), "All holds released results in empty mirror")
	remove_child(controls)
	controls.free()

func _test_reentry_mirror_retained() -> void:
	var controls := _create_controls()
	add_child(controls)
	controls.sync(true, false)

	controls.state.button_down("fire", 1, Vector2.ZERO, 1000)
	controls.state.button_down("jump", 2, Vector2.ZERO, 1000)

	var events: Array = []
	var ref: WeakRef = weakref(controls)
	var admitted := false
	controls.command.connect(func(action: String, on: bool):
		events.append([action, on])
		if action == "fire" and not on and not admitted:
			admitted = true
			var c: NativeTouchControls = ref.get_ref()
			if c != null:
				c.state.button_down("fire", 8, Vector2.ZERO, 1050))

	controls.reset()

	_check(controls.state.held == {8: "fire"}, "TouchState retains admitted hold on pointer 8")
	_check(controls.held.get("fire", false) == true, "Control mirror retains newly admitted fire hold")
	_check(not controls.held.has("jump"), "Released jump hold erased from mirror")
	_check(events == [["fire", false], ["fire", true], ["jump", false]],
		"Commands emitted in source order with replacement admitted during reset")
	remove_child(controls)
	controls.free()

func _test_same_pointer_replacement() -> void:
	var controls := _create_controls()
	add_child(controls)
	controls.sync(true, false)

	controls.state.button_down("fire", 1, Vector2.ZERO, 1000)
	controls.state.button_down("jump", 2, Vector2.ZERO, 1000)

	var events: Array = []
	var ref: WeakRef = weakref(controls)
	var admitted := false
	controls.command.connect(func(action: String, on: bool):
		events.append([action, on])
		if action == "fire" and not on and not admitted:
			admitted = true
			var c: NativeTouchControls = ref.get_ref()
			if c != null:
				c.state.button_down("fire", 1, Vector2.ZERO, 1050))

	controls.reset()

	_check(controls.state.held == {1: "fire"}, "TouchState retains same-pointer replacement")
	_check(controls.held == {"fire": true}, "Control mirror retains same-pointer replacement")
	_check(events == [["fire", false], ["fire", true], ["jump", false]],
		"Old holds release once in source order with same-pointer replacement")
	remove_child(controls)
	controls.free()

func _test_nested_resets() -> void:
	var controls := _create_controls()
	add_child(controls)
	controls.sync(true, false)

	controls.state.button_down("fire", 1, Vector2.ZERO, 1000)
	controls.state.button_down("jump", 2, Vector2.ZERO, 1000)

	var events: Array = []
	var ref: WeakRef = weakref(controls)
	var nested_done := false
	controls.command.connect(func(action: String, on: bool):
		events.append([action, on])
		if action == "fire" and not on and not nested_done:
			nested_done = true
			var c: NativeTouchControls = ref.get_ref()
			if c != null:
				c.reset())

	controls.reset()

	_check(controls.held.is_empty(), "Nested reset leaves mirror empty when no hold readmitted")
	_check(controls.state.held.is_empty(), "Nested reset leaves state held empty")
	_check(events == [["fire", false], ["jump", false]], "Nested reset releases each old hold once")
	remove_child(controls)
	controls.free()

func _test_focus_out_reset() -> void:
	var controls := _create_controls()
	add_child(controls)
	controls.sync(true, false)

	controls.state.button_down("fire", 1, Vector2.ZERO, 1000)
	controls.state.button_down("jump", 2, Vector2.ZERO, 1000)
	_check(controls.held.size() == 2, "Two holds active before focus out")

	controls.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(controls.held.is_empty(), "Focus out clears held mirror")
	_check(controls.state.held.is_empty(), "Focus out clears TouchState held")
	remove_child(controls)
	controls.free()

func _test_overlay_reset() -> void:
	var controls := _create_controls()
	add_child(controls)
	controls.sync(true, false)

	controls.state.button_down("fire", 1, Vector2.ZERO, 1000)
	_check(controls.held.get("fire", false) == true, "Fire active before overlay block")

	# Simulating overlay open: in_battle=true, blocked=true
	controls.sync(true, true)
	_check(controls.held.is_empty(), "Overlay block clears held mirror")
	_check(controls.state.held.is_empty(), "Overlay block clears TouchState held")
	_check(not controls.visible, "Controls hidden when blocked by overlay")
	remove_child(controls)
	controls.free()

func _test_node_retirement() -> void:
	var controls := _create_controls()
	add_child(controls)
	controls.sync(true, false)

	controls.state.button_down("fire", 1, Vector2.ZERO, 1000)
	controls.state.button_down("jump", 2, Vector2.ZERO, 1000)

	var events: Array = []
	controls.command.connect(func(action: String, on: bool): events.append([action, on]))

	# Retirement via remove_child and queue_free triggers _exit_tree()
	remove_child(controls)
	_check(controls.held.is_empty(), "Exit tree resets held mirror on retirement")
	_check(controls.state.held.is_empty(), "Exit tree resets TouchState on retirement")
	_check(events == [["fire", false], ["jump", false]], "Exit tree releases old holds once in source order")
	controls.free()
