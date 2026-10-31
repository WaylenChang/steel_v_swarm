extends Resource

const Oscillator = preload("res://scripts/audio_move_oscillator.gd")
const SHAPES: Array[String] = ["sine", "square", "sawtooth"]

@export var sample_rate := 0
@export var tables: Dictionary = {}
@export var graphs: Dictionary = {}
@export var movement_hash := ""
@export var source: Dictionary = {}

func valid() -> bool:
	if not NativeAudioCatalogue._valid_hash(movement_hash) or not NativeAudioCatalogue._valid_hash(source.get("audioSha256")):
		return false
	if tables.size() != SHAPES.size() or graphs.size() != 4:
		return false
	for category: String in ["engine", "rotor", "wingflap", "stomp"]:
		if not graphs.get(category) is Dictionary or graphs[category].is_empty():
			return false
	for shape: String in SHAPES:
		if not tables.get(shape) is Array or Oscillator.new().configure_native(sample_rate, tables[shape]) != OK:
			return false
	return true
