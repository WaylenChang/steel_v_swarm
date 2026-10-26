extends RefCounted

const Identity = preload("res://scripts/audio_resource_identity.gd")
const CATALOGUE_PATH := "res://assets/audio/native/catalogue.res"

var catalogue: NativeAudioCatalogue
var attempted := false
var resources: Dictionary = {}

func snapshot() -> NativeAudioCatalogue:
	if catalogue == null:
		attempted = true
		var candidate := _read_catalogue()
		if candidate != null and candidate.valid():
			catalogue = candidate
	return catalogue

func synthesis(id: String) -> NativeAudioSynthesis:
	return _resource("synthesis_" + id) as NativeAudioSynthesis

func music(mood: String) -> NativeAudioClip:
	return _resource("music_" + mood) as NativeAudioClip

func movement() -> NativeAudioMoveBank:
	return _resource("movement") as NativeAudioMoveBank

func _resource(key: String) -> Resource:
	if resources.has(key):
		return resources[key]
	var current := snapshot()
	if current == null or not current.complete_resources or not current.resource_paths.has(key):
		return null
	var candidate := _read_resource(current.resource_paths[key])
	if candidate == null or Identity.digest(candidate) != current.resource_hashes[key]:
		return null
	var source_hash: String = current.source.audioSha256
	if key == "movement":
		if not candidate is NativeAudioMoveBank or not candidate.source.get("audioSha256") is String or candidate.source.audioSha256 != source_hash:
			return null
	elif key.begins_with("synthesis_"):
		if not candidate is NativeAudioSynthesis or not candidate.source.get("id") is String or not candidate.source.get("audioSha256") is String:
			return null
		if candidate.source.id != key.trim_prefix("synthesis_") or candidate.source.audioSha256 != source_hash:
			return null
	elif key in ["music_menu", "music_battle"]:
		if not candidate is NativeAudioClip or not candidate.source.get("id") is String or not candidate.source.get("layer") is String or not candidate.source.get("sha256") is String:
			return null
		if candidate.source.id != key or candidate.source.layer != "procedural_music" or candidate.source.sha256 != source_hash or candidate.centered == null or candidate.channel_count != 0:
			return null
	else:
		return null
	resources[key] = candidate
	return candidate

func _read_catalogue() -> NativeAudioCatalogue:
	return ResourceLoader.load(CATALOGUE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as NativeAudioCatalogue if ResourceLoader.exists(CATALOGUE_PATH) else null

func _read_resource(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) if ResourceLoader.exists(path) else null
