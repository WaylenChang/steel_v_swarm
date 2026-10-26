class_name AudioSynthesisLibrary
extends RefCounted

var ids: Array = []
var definitions: Dictionary = {}
var cache: Array[Dictionary] = []
var capacity := 0
var resources := preload("res://scripts/audio_resource_snapshot.gd").new()

func configure(metadata: Dictionary) -> void:
	ids = metadata.synthesisIds
	capacity = int(metadata.maxVoices)
	definitions.clear()
	cache.clear()

func definition(id: String) -> NativeAudioSynthesis:
	if not ids.has(id):
		return null
	if definitions.has(id):
		return definitions[id]
	var resource := resources.synthesis(id)
	if resource == null or not resource.valid() or resource.source.get("id") != id:
		push_error("Missing original synthesis stems; regenerate and import complete source audio: " + id)
		return null
	definitions[id] = resource
	return resource

func render(id: String, gain: float) -> Array[Dictionary]:
	for index in range(cache.size()):
		var entry: Dictionary = cache[index]
		if entry.id == id and entry.gain == gain:
			cache.remove_at(index)
			cache.append(entry)
			return entry.rendered
	var synthesis := definition(id)
	if synthesis == null:
		return []
	var rendered := synthesis.render(gain)
	if rendered.is_empty():
		return rendered
	cache.append({"id": id, "gain": gain, "rendered": rendered})
	while cache.size() > capacity:
		cache.pop_front()
	return rendered
