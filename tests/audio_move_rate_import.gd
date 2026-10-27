extends Node

const Importer = preload("res://tools/audio_move_import.gd")
const Identity = preload("res://scripts/audio_resource_identity.gd")
const Snapshot = preload("res://scripts/audio_resource_snapshot.gd")
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
	var old: Dictionary = Content.read_json("res://data/audio_move.json")
	var original := Importer.build(old, old.source, Content.balance.audio.moveGraphs)
	_check(original != null and Identity.digest(original) == Identity.digest(Snapshot.new().movement()), "Shared movement factory preserves the shipped original resource identity")
	var data: Dictionary = Content.read_json("res://data/audio_move_rates/48000.json")
	_check(data.scope == "original-movement-shared-sfx-rate" and data.sampleRate == 48000, "Explicit movement context capture")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in data.source.sourceInputs:
		_check(provenance.inputs.get(path) == data.source.sourceInputs[path], "Movement capture uses the imported original source: " + path)
	for path: String in data.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == data.source.inputs[path], "Movement context producer is current: " + path)
	var context_path := "res://" + str(data.source.contextProfile.path)
	_check(FileAccess.get_sha256(context_path) == data.source.contextProfile.sha256, "Movement remains bound to the exact original SFX context archive")
	var profile: Dictionary = Content.read_json(context_path)
	_check(data.noise.values == profile.noise.data and data.noiseSha256 == profile.noise.sha256, "Synthesis and movement retain every shared original noise word")
	_check(data.graphs == Content.balance.audio.moveGraphs, "Original movement graphs match the runtime contract")
	var bank := Importer.build(data, data.source, data.graphs)
	if not _valid_bank(bank):
		get_tree().quit(1)
		return
	var path := "user://move-rate-%d-%d.res" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(await Publisher.publish(bank, path, get_tree()) == OK, "Publish an isolated native movement resource without switching the runtime catalogue")
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as NativeAudioMoveBank
	_check(reloaded != null and Identity.digest(bank) == Identity.digest(reloaded), "Matching-rate native movement reload retains its full resource identity")
	_check(reloaded.cycles("engine", 2) == 23 and reloaded.waveform("engine", 2).size() == 24000, "Native 46 Hz engine retains 23 complete source cycles at 48 kHz")
	var changed_cycles := bank.duplicate(true) as NativeAudioMoveBank
	changed_cycles.oscillator_cycles.engine["2"] = 24
	_check(Identity.digest(changed_cycles) != Identity.digest(bank), "Source oscillator cycle count participates in native resource identity")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Remove only the test-owned movement resource")
	for change: String in ["noise", "missing", "duplicate", "fractional", "nonfinite", "cycles", "fractional_cycles"]:
		var invalid := data.duplicate(true)
		match change:
			"noise": invalid.noiseSha256 = old.noiseSha256
			"missing": invalid.oscillators.pop_back()
			"duplicate": invalid.oscillators.append(invalid.oscillators[0].duplicate(true))
			"fractional": invalid.oscillators[0].frames = 2.5
			"cycles": invalid.oscillators[0].cycles = 0
			"fractional_cycles": invalid.oscillators[0].cycles = 1.5
			"nonfinite":
				var bytes := Marshalls.base64_to_raw(invalid.oscillators[0].values)
				bytes.encode_float(0, NAN)
				invalid.oscillators[0].values = Marshalls.raw_to_base64(bytes)
		_check(Importer.build(invalid, invalid.source, invalid.graphs) == null, "Reject an incomplete or mixed movement context: " + change)
	print("AUDIO_MOVE_RATE_IMPORT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _valid_bank(bank: NativeAudioMoveBank) -> bool:
	_check(bank != null and bank.valid(), "Build the complete matching-rate native movement bank")
	if bank == null:
		return false
	_check(bank.noise.mix_rate == 48000 and bank.noise.loop_end == 48000, "Preserve original one-second noise rate and loop extent")
	return true
