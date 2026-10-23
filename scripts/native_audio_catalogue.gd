class_name NativeAudioCatalogue
extends Resource

@export var sample_paths: Dictionary = {}
@export var failures: Dictionary = {}
@export var source: Dictionary = {}

func valid() -> bool:
	for id: Variant in sample_paths:
		if not id is String or not sample_paths[id] is Array:
			return false
		for path: Variant in sample_paths[id]:
			if not path is String or not path.begins_with("res://assets/audio/native/") or path.contains(".."):
				return false
	return true
