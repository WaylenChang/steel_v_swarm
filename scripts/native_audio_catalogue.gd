class_name NativeAudioCatalogue
extends Resource

@export var sample_paths: Dictionary = {}
@export var sample_hashes: Dictionary = {}
@export var failures: Dictionary = {}
@export var source: Dictionary = {}

func valid() -> bool:
	if not _valid_hash(source.get("audioSha256")) or sample_hashes.size() != sample_paths.size():
		return false
	for id: Variant in sample_paths:
		if not id is String or not id.is_valid_identifier() or not sample_paths[id] is Array or not sample_hashes.get(id) is Array:
			return false
		if sample_paths[id].size() != sample_hashes[id].size():
			return false
		for index in range(sample_paths[id].size()):
			var path: Variant = sample_paths[id][index]
			var hash: Variant = sample_hashes[id][index]
			if not _valid_hash(hash):
				return false
			if not path is String or path != "res://assets/audio/native/%s_%s.res" % [id, hash]:
				return false
	return true

static func _valid_hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value == value.to_lower() and value.is_valid_hex_number(false)
