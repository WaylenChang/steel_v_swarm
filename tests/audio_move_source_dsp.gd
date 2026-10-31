extends Node

const SourceDsp = preload("res://scripts/audio_move_source_dsp.gd")
const Importer = preload("res://tools/audio_move_import.gd")
const WaveImport = preload("res://tools/audio_move_wave_import.gd")
var assertions := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	var archive: Dictionary = Content.read_json("res://data/audio_move_oscillators/48000.json")
	var program: Dictionary = Content.read_json("res://data/audio_move_rate_waveforms/48000.json")
	var movement: Dictionary = Content.read_json("res://data/audio_move_rates/48000.json")
	var bank := WaveImport.build(archive, Importer.build(movement, movement.source, movement.graphs))
	_check(bank != null, "Authenticate the original native wave-bank cohort")
	if bank == null:
		get_tree().quit(1)
		return
	for automated: bool in [false, true]:
		for fixture: Dictionary in program.waveforms:
			var graph: Dictionary = movement.graphs[fixture.category]
			var dsp := SourceDsp.new()
			_check(dsp.configure(graph, AudioMovePlan.compile(graph), fixture, 48000, bank) == OK, "Admit the complete original graph source DSP")
			if automated:
				for command: Dictionary in fixture.commands:
					_check(dsp.queue(command.key, command.target, command.tau, command.time) == OK, "Queue original source command")
			var input: PackedFloat32Array = dsp.render_input(48000)
			var output: Dictionary = dsp.render_output(48000)
			var witnesses: Array = archive.oscillators if automated else archive.waveTables.constantProbes
			for witness: Dictionary in witnesses:
				if witness.category != fixture.category:
					continue
				var actual: PackedFloat32Array = input if fixture.category == "engine" else output.modulation
				_check(actual.to_byte_array() == Marshalls.base64_to_raw(witness.values), "The mixer source adapter preserves k-rate/a-rate oscillator words")
			if not automated:
				continue
			for probe: Dictionary in archive.parameterProbes:
				for origin: Dictionary in probe.origins:
					if origin.category != fixture.category or origin.wet != fixture.wet:
						continue
					var actual := PackedFloat32Array()
					if origin.key in ["gain", "pan", "wet", "dry"]:
						actual = output[origin.key]
					elif str(origin.key).begins_with("rate:"):
						var node := int(str(origin.key).split(":")[1])
						if not output.filters.has(node):
							continue
						actual = output.filters[node]
					_check(actual.to_byte_array() == Marshalls.base64_to_raw(probe.values), "Physical mixer parameters preserve independent original curves: " + str(origin.key))
	var fixture: Dictionary = program.waveforms[0].duplicate(true)
	fixture.rate = .5
	var graph: Dictionary = movement.graphs.rotor
	_check(SourceDsp.new().configure(graph, AudioMovePlan.compile(graph), fixture, 48000, bank) == ERR_UNAVAILABLE, "Unqualified non-unity initial rates remain unavailable")
	_check(SourceDsp.new().configure(graph, AudioMovePlan.compile(graph), program.waveforms[0], 44100, bank) == ERR_UNAVAILABLE, "A different device-rate wave bank cannot be admitted")
	for kind: String in ["createOscillator", "createBiquadFilter"]:
		var detuned := graph.duplicate(true)
		for node: Dictionary in detuned.nodes:
			if node.kind == kind:
				node.parameters.detune = {"initial": 1, "events": []}
				break
		_check(SourceDsp.new().configure(detuned, AudioMovePlan.compile(detuned), program.waveforms[0], 48000, bank) == ERR_INVALID_DATA, "Uncaptured graphs cannot select an approximate source path")
	print("AUDIO_MOVE_SOURCE_DSP_PASS " if failures == 0 else "AUDIO_MOVE_SOURCE_DSP_FAIL ", assertions, " assertions, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
