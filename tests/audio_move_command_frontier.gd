extends Node

var assertions := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _mixer(fixture: Dictionary, rate: float, frame: int) -> AudioMoveMixer:
	var mixer := AudioMoveMixer.new()
	mixer.sample_rate = rate
	mixer.has_oscillator_input = true
	mixer.controls.configure(fixture, rate)
	mixer.input_controls.configure(fixture, rate)
	mixer.controls.frame = frame - 256
	mixer.input_controls.frame = frame + 256
	return mixer

func _ready() -> void:
	var reference: Dictionary = Content.read_json("res://data/audio_move_automation/48000.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs.get(path) == reference.source.sourceInputs[path], "Command oracle uses the imported original source")
	var fixture: Dictionary
	for candidate: Dictionary in reference.waveforms:
		if candidate.category == "engine":
			fixture = candidate
	for command: Dictionary in fixture.commands:
		var wanted := ceili(float(command.time) * float(reference.sampleRate))
		var mixer := _mixer(fixture, reference.sampleRate, wanted)
		mixer.queue(command.key, command.target, command.tau, command.time)
		_check(mixer._commands(), "Apply a live source command")
		var input_command: bool = command.key == "rate"
		var expected := wanted + 256 if input_command else wanted
		_check(mixer.controls.events[0].frame == expected, "Only oscillator rate needs the generated-input frontier: " + str(command.key))
		_check(mixer.controls.events[0].target == command.target, "Preserve the original source target")
		_check(mixer.late_control_frames == (256 if input_command else 0), "Report actual irrecoverable source frames only")
		_check(mixer.input_controls.events.size() == (1 if input_command else 0), "Output controls do not enter the oscillator input timeline")
		if input_command:
			_check(mixer.input_controls.events[0].frame == expected, "Rate applies to input and output at the same editable frame")
	var first: Dictionary = fixture.commands[0]
	var wanted := ceili(float(first.time) * float(reference.sampleRate))
	var late := _mixer(fixture, reference.sampleRate, wanted)
	late.controls.frame = wanted + 100
	late.queue(first.key, first.target, first.tau, first.time)
	_check(late._commands() and late.controls.events[0].frame == wanted + 100 and late.late_control_frames == 100, "Genuinely late output commands clamp at the consumed output cursor")
	var stopped := _mixer(fixture, reference.sampleRate, wanted)
	stopped.queue(first.key, first.target, first.tau, first.time)
	stopped.stop()
	_check(not stopped._commands() and stopped.controls.events.is_empty() and stopped.input_controls.events.is_empty(), "Retirement cannot apply a pending source command")
	print("AUDIO_MOVE_COMMAND_FRONTIER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
