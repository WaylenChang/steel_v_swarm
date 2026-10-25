class_name AudioSampleLibrary
extends RefCounted

const CATALOGUE_PATH := "res://assets/audio/native/catalogue.res"
const ClipIdentity = preload("res://scripts/audio_clip_identity.gd")

var catalogue: NativeAudioCatalogue
var buffers: Dictionary = {}
var loaded := false
var resources := preload("res://scripts/audio_resource_snapshot.gd").new()

func load_samples(low_power: bool) -> Error:
	# Low-power startup never loads the PCM catalogue or marks it registered.
	if low_power or loaded:
		return OK
	var candidate := _load_catalogue()
	if candidate == null or not candidate.valid():
		push_error("Missing original native audio catalogue; regenerate source audio")
		return ERR_UNAVAILABLE
	var decoded := {}
	for id: String in candidate.sample_paths:
		var takes: Array[NativeAudioClip] = []
		for index in range(candidate.sample_paths[id].size()):
			var path: String = candidate.sample_paths[id][index]
			var clip := _load_clip(path)
			if not ClipIdentity.matches(clip, id, candidate.sample_hashes[id][index]):
				push_error("Missing or invalid imported source audio clip: " + path)
				return ERR_INVALID_DATA
			takes.append(clip)
		if not takes.is_empty():
			decoded[id] = takes
	catalogue = candidate
	buffers = decoded
	loaded = true
	return OK

func _load_catalogue() -> NativeAudioCatalogue:
	return resources.snapshot()

func _load_clip(path: String) -> NativeAudioClip:
	return load(path) as NativeAudioClip if ResourceLoader.exists(path) else null

func has_sample(id: String, low_power: bool) -> bool:
	return not low_power and not buffers.get(id, []).is_empty()
