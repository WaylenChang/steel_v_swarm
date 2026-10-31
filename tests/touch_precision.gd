extends Node

var assertions := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _words(part: Dictionary) -> PackedFloat64Array:
	return Marshalls.base64_to_raw(part.data).to_float64_array()

func _point(words: PackedFloat64Array, offset: int = 0) -> Vector2:
	return Vector2(words[offset], words[offset + 1])

func _owner(rules: Dictionary, events: Array) -> TouchState:
	var state := TouchState.new(rules)
	state.command.connect(func(action, on): events.append({"type": "command", "action": action, "on": on}))
	state.look.connect(func(change): events.append({"type": "look", "change": change}))
	state.haptic.connect(func(milliseconds): events.append({"type": "haptic", "milliseconds": milliseconds}))
	return state

func _events(actual: Array, expected: Array, label: String) -> void:
	_check(actual.size() == expected.size(), "Original event count: " + label)
	for index in range(mini(actual.size(), expected.size())):
		var event: Dictionary = actual[index]
		var original: Dictionary = expected[index]
		_check(event.type == original.type, "Original event order: " + label)
		if event.type != original.type:
			continue
		if event.type == "look":
			var point := _point(_words(original.source))
			_check(PackedVector2Array([event.change]).to_byte_array() == PackedVector2Array([point]).to_byte_array(),
				"Source double look reaches the unchanged native Vector2 boundary: " + label)
		elif event.type == "command":
			_check(event.action == original.action and event.on == original.on, "Original strict command decision: " + label)
		else:
			_check(event.milliseconds == original.milliseconds, "Original haptic dispatch: " + label)

func _state(state: TouchState, expected: Dictionary, label: String) -> void:
	var scalars := PackedFloat64Array([state.move_stick.x, state.move_stick.y, state.move_stick.mag,
		state.look_stick.x, state.look_stick.y, state.look_stick.mag])
	_check(scalars.to_byte_array() == Marshalls.base64_to_raw(expected.scalars.data),
		"Preserve original double stick direction/magnitude independently of native vector storage: " + label)
	var axis := _point(_words(expected.axis))
	_check(PackedVector2Array([state.axis]).to_byte_array() == PackedVector2Array([axis]).to_byte_array(),
		"Original movement axes reach native storage: " + label)
	_check(PackedFloat64Array([state.tap_at, state.down_at]).to_byte_array() == Marshalls.base64_to_raw(expected.clocks.data),
		"Original tap/hold clocks: " + label)
	_check(state.look_id == expected.lookId and state.fire_arm == expected.fireArm and state.look_fire == expected.lookFire,
		"Original double-tap and drag eligibility: " + label)
	var held := {}
	for pointer: int in state.held:
		held[str(pointer)] = state.held[pointer]
	var taps: Array[int] = []
	for pointer: float in expected.taps:
		taps.append(int(pointer))
	_check(held == expected.held and state.taps.keys() == taps, "Original held/tap ownership: " + label)

func _ready() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/touch_precision.json")
	_check(capture.get("scope") == "original-touch-native-boundary-precision", "Load the original touch precision corpus")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current touch precision producer: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Accepted original touch source: " + path)
	var rules: Dictionary = Content.balance.mobile.look
	var values := _words(capture.ruleValues)
	for index in range(capture.ruleNames.size()):
		var name: String = capture.ruleNames[index]
		_check(PackedFloat64Array([rules[name]]).to_byte_array() == PackedFloat64Array([values[index]]).to_byte_array(),
			"Retain the original double threshold without retuning: " + name)
	if failures > 0:
		get_tree().quit(1)
		return
	for index in range(capture.sticks.size()):
		var input: Dictionary = capture.sticks[index]
		var original: Dictionary = capture.expected.sticks[index]
		var words := _words(input.values)
		var events: Array = []
		var state := _owner(rules, events)
		state.sensitivity = words[5]
		state.stick_down(true, 1, _point(words), _point(words, 2), words[4])
		state.stick_down(false, 2, _point(words), _point(words, 2), words[4])
		state.tick(words[6], 1000)
		_events(events, original.active.events, input.name)
		_state(state, original.active.state, input.name)
		var vector := TouchState.stick_vector(_point(words), _point(words, 2), words[4], rules.STICK_DEAD)
		_check(PackedVector2Array([vector]).to_byte_array() == PackedVector2Array([state.move_stick.vector]).to_byte_array(),
			"The existing stick-vector API shares the same source computation")
		events.clear()
		state.up(1, Vector2.ZERO, 1000)
		state.up(2, Vector2.ZERO, 1000)
		state.reset()
		state.tick(.016, 1000)
		_events(events, original.released.events, input.name + "/release")
		_state(state, original.released.state, input.name + "/release")
	for index in range(capture.gestures.size()):
		var input: Dictionary = capture.gestures[index]
		var events: Array = []
		var state := _owner(rules, events)
		for frame in range(input.steps.size()):
			events.clear()
			var step: Dictionary = input.steps[frame]
			var words := _words(step.values)
			var point := _point(words)
			match step.kind:
				"button": state.button_down(step.action, 1, point, words[2])
				"lookDown": state.look_down(1, point, words[2])
				"move": state.move(1, point)
				"up": state.up(1, point, words[2], step.get("cancel", false))
				"tick": state.tick(words[3], words[2])
				"reset": state.reset()
				"blocked": state.set_blocked(step.value)
			var original: Dictionary = capture.expected.gestures[index][frame]
			_events(events, original.events, input.name + "/" + str(frame))
			_state(state, original.state, input.name + "/" + str(frame))
	print("TOUCH_PRECISION assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
