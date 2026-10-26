extends Node

var assertions := 0
var failures := 0

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(label)

func _ready() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/touch_reset.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array, "Capture the original touch reset program")
	for path: String in capture.source.inputs:
		_check(FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n").sha256_text() == capture.source.inputs[path],
			"Touch reset producer remains current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Touch reset original source identity: " + path)
	_check(capture.rules == Content.balance.mobile.look, "Touch reset retains original input thresholds")
	if failures == 0:
		for item: Dictionary in capture.cases:
			var state := TouchState.new(capture.rules)
			state.look_fire = item.initial.lookFire
			state.blocked = item.initial.blocked
			state.look_id = 1
			state.fire_arm = true
			state.tap_at = 1000
			state.axis = Vector2.ONE
			state.move_stick.id = 2
			state.move_stick.vector = Vector2.ONE
			state.look_stick.id = 3
			state.look_stick.vector = Vector2.ONE
			for offset in range(item.initial.held.size()):
				state.held[offset + 4] = item.initial.held[offset]
			state.taps[9] = {"action": "reload"}
			var events := []
			state.command.connect(func(action, on): events.append({"type": "command", "action": action, "on": on}))
			state.reset()
			_check(events == item.events, "Source gesture/button fire handoff and release order remain unchanged")
			_check(item.cleared and _clear(state), "Source reset clears all pointers, armed taps and movement")
		_reentrant_reset()
		_replacement()
		_admission()
		_interrupted_look()
		_stick_replacement()
	print("TOUCH_RESET assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _clear(state: TouchState) -> bool:
	return state.held.is_empty() and state.taps.is_empty() and state.look_id == TouchState.NONE and not state.look_fire and not state.fire_arm and state.tap_at == 0 and state.axis == Vector2.ZERO and state.move_stick.id == TouchState.NONE and state.move_stick.vector == Vector2.ZERO and state.look_stick.id == TouchState.NONE and state.look_stick.vector == Vector2.ZERO

func _reentrant_reset() -> void:
	var state := TouchState.new(Content.balance.mobile.look)
	state.held = {1: "fire", 2: "jump"}
	var events := []
	var reference: WeakRef = weakref(state)
	state.command.connect(func(action, on):
		events.append([action, on])
		if events.size() == 1:
			reference.get_ref().reset())
	state.reset()
	_check(events == [["fire", false], ["jump", false]] and _clear(state), "Nested reset releases each old hold once")

func _replacement() -> void:
	var state := TouchState.new(Content.balance.mobile.look)
	state.held = {1: "fire", 2: "fire", 3: "jump"}
	var reference: WeakRef = weakref(state)
	var events := []
	state.command.connect(func(action, on):
		events.append([action, on])
		if events.size() == 1:
			reference.get_ref().button_down("fire", 8, Vector2.ZERO, 1000))
	state.reset()
	_check(state.held == {8: "fire"} and events == [["fire", false], ["fire", true], ["jump", false]],
		"Old reset retains a newly admitted hold and cannot release its replacement")

func _admission() -> void:
	for action: String in ["fire", "reload"]:
		var state := TouchState.new(Content.balance.mobile.look)
		var reference: WeakRef = weakref(state)
		var commands := []
		state.command.connect(func(name, on): commands.append([name, on]))
		state.haptic.connect(func(_milliseconds): reference.get_ref().set_blocked(true))
		state.button_down(action, 1, Vector2.ZERO, 1000)
		_check(state.blocked and _clear(state) and commands.is_empty(), "Haptic callback blocking cancels old button admission: " + action)

func _interrupted_look() -> void:
	for tick: bool in [false, true]:
		var state := TouchState.new(Content.balance.mobile.look)
		state.look_down(1, Vector2.ZERO, 1000)
		state.fire_arm = true
		state.look_stick.vector = Vector2.ONE
		var reference: WeakRef = weakref(state)
		var events := []
		state.command.connect(func(action, on):
			events.append([action, on])
			if action == "fire" and on:
				reference.get_ref().set_blocked(true))
		state.look.connect(func(_change): events.append(["look"]))
		state.haptic.connect(func(_milliseconds): events.append(["haptic"]))
		if tick:
			state.tick(0.016, 1200)
		else:
			state.move(1, Vector2(20, 0))
		_check(state.blocked and _clear(state) and events == [["fire", true], ["fire", false]],
			"Blocked fire callbacks cancel old look and haptic continuations")

func _stick_replacement() -> void:
	for release: bool in [false, true]:
		var state := TouchState.new(Content.balance.mobile.look)
		state.stick_down(true, 1, Vector2.ZERO, Vector2.ZERO, 50)
		var reference: WeakRef = weakref(state)
		var interrupted := [false]
		state.command.connect(func(action, _on):
			if action == "sprint" and not interrupted[0]:
				interrupted[0] = true
				var current: TouchState = reference.get_ref()
				current.reset()
				current.button_down("reload" if not release else "fire", 1, Vector2.ZERO, 1000))
		if release:
			state.up(1, Vector2.ZERO, 1000)
			_check(state.held == {1: "fire"}, "Interrupted stick release cannot release a newly admitted same-ID hold")
		else:
			state.move(1, Vector2(50, 0))
			_check(state.taps.has(1) and state.taps[1].action == "reload", "Interrupted stick movement cannot erase a new same-ID tap")
