class_name NativeAudioCatalogue
extends Resource

@export var sample_paths: Dictionary = {}
@export var sample_hashes: Dictionary = {}
@export var failures: Dictionary = {}
@export var source: Dictionary = {}
@export var complete_resources := false
@export var synthesis_ids: Array[String] = []
@export var resource_paths: Dictionary = {}
@export var resource_hashes: Dictionary = {}

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
	if not complete_resources:
		return synthesis_ids.is_empty() and resource_paths.is_empty() and resource_hashes.is_empty()
	var expected: Array[String] = ["music_menu", "music_battle", "movement"]
	for id: String in synthesis_ids:
		var key := "synthesis_" + id
		if not id.is_valid_identifier() or expected.has(key):
			return false
		expected.append(key)
	if synthesis_ids.is_empty() or resource_paths.size() != expected.size() or resource_hashes.size() != expected.size():
		return false
	for key: String in expected:
		var hash: Variant = resource_hashes.get(key)
		var path: Variant = resource_paths.get(key)
		if not _valid_hash(hash) or not path is String or path != "res://assets/audio/native/%s_%s.res" % [key, hash]:
			return false
	return true

static func _valid_hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.lstrip("0123456789abcdef").is_empty()
