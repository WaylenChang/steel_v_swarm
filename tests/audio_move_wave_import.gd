extends Node

const WaveBank = preload("res://scripts/native_audio_move_waves.gd")
const Importer = preload("res://tools/audio_move_wave_import.gd")
const MoveImport = preload("res://tools/audio_move_import.gd")
const Identity = preload("res://scripts/audio_resource_identity.gd")
const Publisher = preload("res://tools/source_resource_publisher.gd")
var assertions := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var archive: Dictionary = Content.read_json("res://data/audio_move_oscillators/48000.json")
	var movement: Dictionary = Content.read_json("res://data/audio_move_rates/48000.json")
	var bank := MoveImport.build(movement, movement.source, movement.graphs)
	var waves := Importer.build(archive, bank)
	_check(waves != null, "Admit complete original tables with current producers, parents and movement identity")
	if waves == null:
		get_tree().quit(1)
		return
	var digest := Identity.digest(waves)
	var path := "user://sol-move-waves-%d-%d.res" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(not digest.is_empty() and await Publisher.publish(waves, path, get_tree()) == OK, "Publish the native packed wave bank in isolation")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as WaveBank
	_check(loaded != null and Identity.digest(loaded) == digest, "Native disk reload preserves the complete resource identity")
	if loaded == null:
		get_tree().quit(1)
		return
	for shape: String in WaveBank.SHAPES:
		for index in range(waves.tables[shape].size()):
			_check(loaded.tables[shape][index].to_byte_array() == waves.tables[shape][index].to_byte_array(), "Native reload preserves every original Float32 table word")
	for witness: Dictionary in archive.oscillators + archive.waveTables.probes + archive.waveTables.constantProbes:
		var oscillator := WaveBank.Oscillator.new()
		_check(oscillator.configure_native(loaded.sample_rate, loaded.tables[witness.type]) == OK, "Admit reloaded oscillator tables")
		var modes := PackedByteArray()
		if witness in archive.waveTables.constantProbes:
			modes.resize(int(witness.frames) / 128)
			modes.fill(0)
			modes[0] = 1
		var actual := oscillator.render(Marshalls.base64_to_raw(witness.frequencyValues).to_float32_array(), modes)
		_check(actual.to_byte_array() == Marshalls.base64_to_raw(witness.values), "Reloaded tables retain bit-exact source k-rate/a-rate and boundary samples")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Remove only the test-owned native resource")
	for change: String in ["word", "source", "movement", "graph", "rate", "range", "shape", "nonfinite"]:
		var changed := loaded.duplicate(true) as WaveBank
		match change:
			"word": changed.tables.sine[0][0] += .125
			"source": changed.source.audioSha256 = "0".repeat(64)
			"movement": changed.movement_hash = "0".repeat(64)
			"graph": changed.graphs.engine.nodes[2].parameters.frequency.initial += 1
			"rate": changed.sample_rate = 44100
			"range": changed.tables.sine.pop_back()
			"shape": changed.tables.triangle = changed.tables.sine
			"nonfinite": changed.tables.sine[0][0] = NAN
		_check(Identity.digest(changed) != digest, "Every table, source, cohort, graph and layout change invalidates the expected resource identity: " + change)
	_check(Identity.digest(loaded) == digest, "Mutating another resource leaves a retained reader unchanged")
	var positive_zero := loaded.duplicate(true) as WaveBank
	var negative_zero := loaded.duplicate(true) as WaveBank
	positive_zero.tables.sine[0][0] = 0.0
	negative_zero.tables.sine[0][0] = PackedByteArray([0, 0, 0, 128]).decode_float(0)
	_check(Identity.digest(positive_zero) != Identity.digest(negative_zero), "Native identity distinguishes source signed-zero table words")
	for change: String in ["scope", "qualified", "source", "producer", "missing_producer", "missing_parent_producer", "parent", "missing_parent", "wrong_parent", "escape", "duplicate", "missing", "range", "nonfinite", "base64", "rate"]:
		var invalid := archive.duplicate(true)
		match change:
			"scope": invalid.scope = "other"
			"qualified": invalid.rateOscillatorsQualified = true
			"source": invalid.source.sourceInputs["public/js/audio.js"] = "0".repeat(64)
			"producer": invalid.source.inputs["tools/audio_move_wave_capture.mjs"] = "0".repeat(64)
			"missing_producer": invalid.source.inputs.erase("tools/audio_move_wave_capture.mjs")
			"missing_parent_producer": invalid.source.inputs.erase("tools/capture_audio_move_rate.mjs")
			"parent": invalid.source.movementProfile.sha256 = "0".repeat(64)
			"missing_parent": invalid.source.erase("programProfile")
			"wrong_parent": invalid.source.programProfile = invalid.source.contextProfile
			"escape": invalid.source.contextProfile.path = "../outside.json"
			"duplicate": invalid.waveTables.types[1] = invalid.waveTables.types[0]
			"missing": invalid.waveTables.types.pop_back()
			"range": invalid.waveTables.types[0].tables.pop_back()
			"nonfinite":
				var bytes := Marshalls.base64_to_raw(invalid.waveTables.types[0].tables[0].values)
				bytes.encode_float(0, NAN)
				invalid.waveTables.types[0].tables[0].values = Marshalls.raw_to_base64(bytes)
			"base64": invalid.waveTables.types[0].tables[0].values += "!"
			"rate": invalid.sampleRate = 44100
		_check(Importer.build(invalid, bank) == null, "Reject malformed or stale wave-bank publication: " + change)
	var other_bank := bank.duplicate(true) as NativeAudioMoveBank
	other_bank.oscillators.engine["2"][0] += .125
	_check(Importer.build(archive, other_bank) == null, "Reject a changed movement resource despite matching source declarations")
	var legacy: Dictionary = Content.read_json("res://data/audio_move.json")
	_check(Importer.build(archive, MoveImport.build(legacy, legacy.source, Content.balance.audio.moveGraphs)) == null, "Reject movement from another shared-noise context")
	var buses := AudioBuses.new()
	add_child(buses)
	_check(buses.configure() == OK, "Configure native admission routes")
	var voice := AudioMoveVoice.new()
	add_child(voice)
	_check(voice.configure("engine", Content.balance.audio, other_bank, buses, {"gain": 1, "pan": 0, "rate": 1, "wet": 0}, 0, loaded) == ERR_INVALID_DATA, "Voice rejects another movement identity before allocating native players")
	_check(voice.input_players.is_empty() and voice.output_player == null and voice.routes.is_empty(), "Rejected admission reserves no native stream or bus")
	voice.free()
	var owner := AudioMove.new()
	add_child(owner)
	var wrong_rate := loaded.duplicate(true) as WaveBank
	wrong_rate.sample_rate = 44100
	_check(owner.configure(Content.balance.audio, buses, false, wrong_rate) == ERR_UNAVAILABLE and owner.wave_bank == null, "Reject a different device-rate bank before retaining resources")
	var malformed := loaded.duplicate(true) as WaveBank
	malformed.tables.erase("sine")
	_check(owner.configure(Content.balance.audio, buses, false, malformed) == ERR_INVALID_DATA and owner.wave_bank == null, "Reject incomplete native tables before owner configuration")
	_check(owner.configure(Content.balance.audio, buses, false, loaded) == OK, "Configure the optional native wave-bank owner")
	loaded.tables.sine[0][0] += .25
	_check(Identity.digest(owner.wave_bank) == digest, "Owner retains an isolated resource snapshot after caller mutation")
	remove_child(owner)
	_check(owner.wave_bank == null and owner.state.disposed, "Terminal owner exit releases its native wave-bank snapshot")
	add_child(owner)
	_check(owner.configure(Content.balance.audio, buses, false, waves) == ERR_UNCONFIGURED, "Reattachment cannot revive a retired bank owner")
	owner.free()
	buses.free()
	print("AUDIO_MOVE_WAVE_IMPORT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
