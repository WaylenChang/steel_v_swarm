extends Node

const NoiseImport = preload("res://tools/audio_noise_import.gd")
const Identity = preload("res://scripts/audio_resource_identity.gd")
const Snapshot = preload("res://scripts/audio_resource_snapshot.gd")

class Importer extends "res://tools/import_audio.gd":
	var captured: NativeAudioMoveBank
	var errors: Array[String] = []
	func _ready() -> void:
		pass
	func _publish_resource(_catalogue: NativeAudioCatalogue, key: String, resource: Resource) -> bool:
		if key != "movement" or not resource is NativeAudioMoveBank:
			return false
		captured = resource
		return true
	func _fail(message: String) -> void:
		errors.append(message)

var assertions := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _hash(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var move: Dictionary = Content.read_json("res://data/audio_move.json")
	var probes: Dictionary = Content.read_json("res://data/audio_probes.json")
	var profile: Dictionary = Content.read_json("res://data/audio_sfx_rates/48000.json")
	var old := NoiseImport.decode(move.noise, move.noiseSha256)
	_check(not old.is_empty() and old.to_byte_array() == Marshalls.base64_to_raw(move.noise.values), "Decode the complete original movement noise without changing float words")
	_check(old.to_byte_array() == NoiseImport.decode(probes.noise, probes.noise.sha256, "data").to_byte_array(), "Source synthesis and movement share exactly the same original noise bytes")
	var current := NoiseImport.decode(profile.noise, profile.noise.sha256, "data")
	_check(current.size() == 48000 and current.to_byte_array() == Marshalls.base64_to_raw(profile.noise.data), "Decode the independent device-rate source noise without resampling")
	_check(NoiseImport.decode(profile.noise, move.noiseSha256, "data").is_empty(), "Reject the other capture's noise identity even when its declaration is valid")
	for patch: Dictionary in [{"encoding": "float64le"}, {"frames": 0}, {"frames": 47359}, {"frames": 47360.5}, {"frames": "47360"}, {"sampleRate": 7999}, {"sampleRate": 384001}, {"sampleRate": INF}, {"values": 1}, {"values": ""}]:
		var invalid: Dictionary = move.noise.duplicate(true)
		invalid.merge(patch, true)
		_check(NoiseImport.decode(invalid, move.noiseSha256).is_empty(), "Reject unsupported original noise storage: " + str(patch.keys()))
	for fingerprint: Variant in [null, 1, "invalid", "f".repeat(64)]:
		_check(NoiseImport.decode(move.noise, fingerprint).is_empty(), "Reject missing, malformed or incorrect raw-noise fingerprints")
	for symbol: String in ["!", "=", " ", "\n"]:
		var invalid: Dictionary = move.noise.duplicate(true)
		invalid.values = symbol + str(invalid.values).substr(1)
		_check(NoiseImport.decode(invalid, move.noiseSha256).is_empty(), "Reject invalid base64 without invoking a failing native decoder")
	var bytes := old.to_byte_array()
	bytes[0] = bytes[0] ^ 1
	var altered: Dictionary = move.noise.duplicate(true)
	altered.values = Marshalls.raw_to_base64(bytes)
	_check(NoiseImport.decode(altered, move.noiseSha256).is_empty(), "Same-size noise corruption cannot keep the original fingerprint")
	for nonfinite: float in [NAN, INF, -INF]:
		bytes = old.to_byte_array()
		bytes.encode_float(0, nonfinite)
		altered.values = Marshalls.raw_to_base64(bytes)
		_check(NoiseImport.decode(altered, _hash(bytes)).is_empty(), "Reject nonfinite float words even under a matching raw fingerprint")
	var importer := Importer.new()
	add_child(importer)
	_check(await importer._movement(move.source, NativeAudioCatalogue.new()) and importer.errors.is_empty(), "The actual movement importer accepts verified source noise")
	_check(importer.captured != null and Identity.digest(importer.captured) == Identity.digest(Snapshot.new().movement()), "Verified noise import preserves the shipped movement resource identity")
	importer.free()
	print("AUDIO_NOISE_IMPORT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
