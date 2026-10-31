extends RefCounted

const WaveBank = preload("res://scripts/native_audio_move_waves.gd")
const MoveImport = preload("res://tools/audio_move_import.gd")
const Identity = preload("res://scripts/audio_resource_identity.gd")
const PRODUCERS: Array[String] = [
	"tools/capture_audio_move_oscillators.mjs", "tools/audio_move_oscillator_capture.mjs",
	"tools/audio_move_wave_capture.mjs", "tools/audio_move_wave_model.mjs", "tools/audio_param_capture.mjs",
	"tools/source_numeric_transfer.mjs", "tools/fixture_json.mjs",
]

static func build(captured: Dictionary, movement: NativeAudioMoveBank) -> WaveBank:
	if captured.get("formatVersion") != 1 or captured.get("scope") != "original-movement-isolated-oscillators" or captured.get("rateOscillatorsQualified") != false:
		return null
	if movement == null or not movement.valid() or not captured.get("source") is Dictionary or not captured.get("waveTables") is Dictionary:
		return null
	var origin: Dictionary = captured.source
	if not _current(origin):
		return null
	var parent: Dictionary = Content.read_json("res://" + str(origin.movementProfile.path))
	if parent.get("scope") != "original-movement-shared-sfx-rate" or not parent.get("source") is Dictionary or not parent.get("graphs") is Dictionary or not parent.get("noiseSha256") is String:
		return null
	if not parent.source.get("inputs") is Dictionary:
		return null
	for path: Variant in parent.source.inputs:
		if origin.inputs.get(path) != parent.source.inputs[path]:
			return null
	var program: Dictionary = Content.read_json("res://" + str(origin.programProfile.path))
	if program.get("scope") != "original-movement-rate-waveforms" or program.get("sampleRate") != captured.get("sampleRate") or not program.get("source") is Dictionary:
		return null
	for key: String in ["movementProfile", "contextProfile", "audioSha256", "sourceInputs", "chromiumVersion", "jsFlags"]:
		if program.source.get(key) != origin.get(key):
			return null
	if not program.source.get("inputs") is Dictionary:
		return null
	for path: Variant in program.source.inputs:
		if origin.inputs.get(path) != program.source.inputs[path]:
			return null
	var expected := MoveImport.build(parent, parent.source, parent.graphs)
	var movement_hash := Identity.digest(movement)
	if expected == null or movement_hash.is_empty() or movement_hash != Identity.digest(expected):
		return null
	for key: String in ["audioSha256", "sourceInputs", "contextProfile", "chromiumVersion", "jsFlags"]:
		if not origin.has(key) or origin[key] != parent.source.get(key):
			return null
	var captured_tables: Dictionary = captured.waveTables
	if captured.get("sampleRate") != parent.get("sampleRate") or captured_tables.get("sampleRate") != captured.sampleRate or movement.noise.mix_rate != captured.sampleRate:
		return null
	if not captured_tables.get("types") is Array or captured_tables.types.size() != WaveBank.SHAPES.size():
		return null
	var result := WaveBank.new()
	result.sample_rate = int(captured.sampleRate)
	result.movement_hash = movement_hash
	result.source = origin.duplicate(true)
	result.graphs = parent.graphs.duplicate(true)
	for entry: Variant in captured_tables.types:
		if not entry is Dictionary or not entry.get("type") is String or not entry.type in WaveBank.SHAPES or result.tables.has(entry.type):
			return null
		var oscillator := WaveBank.Oscillator.new()
		if oscillator.configure(captured_tables, entry.type) != OK:
			return null
		result.tables[entry.type] = oscillator.tables
	return result if result.valid() else null

static func _current(origin: Dictionary) -> bool:
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for key: String in ["sourceInputs", "inputs"]:
		if not origin.get(key) is Dictionary or origin[key].is_empty():
			return false
		for path: Variant in origin[key]:
			if not _local_path(path) or not NativeAudioCatalogue._valid_hash(origin[key][path]):
				return false
			if key == "sourceInputs":
				if provenance.get("inputs", {}).get(path) != origin[key][path]:
					return false
			else:
				var resource_path := "res://" + str(path)
				if not FileAccess.file_exists(resource_path):
					return false
				var text := FileAccess.get_file_as_string(resource_path).replace("\r\n", "\n").replace("\r", "\n")
				if text.sha256_text() != origin[key][path]:
					return false
	for key: String in ["movementProfile", "programProfile", "contextProfile"]:
		var entry: Variant = origin.get(key)
		if not entry is Dictionary or not _local_path(entry.get("path")) or not NativeAudioCatalogue._valid_hash(entry.get("sha256")):
			return false
		var path := "res://" + str(entry.path)
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != entry.sha256:
			return false
	for path: String in PRODUCERS:
		if not origin.inputs.has(path):
			return false
	return true

static func _local_path(value: Variant) -> bool:
	return value is String and not value.is_empty() and not value.contains("\\") and not value.contains(":") and not value.begins_with("/") and value.simplify_path() == value and not ".." in value.split("/")
