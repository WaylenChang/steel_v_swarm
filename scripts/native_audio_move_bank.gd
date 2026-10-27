class_name NativeAudioMoveBank
extends Resource

const PATH := "res://assets/audio/native/movement.res"

@export var noise: AudioStreamWAV
@export var noise_gain := 1.0
@export var oscillators: Dictionary = {}
@export var oscillator_cycles: Dictionary = {}
@export var source: Dictionary = {}

func valid() -> bool:
	if noise == null or noise.stereo or noise.mix_rate <= 0 or noise.loop_mode != AudioStreamWAV.LOOP_FORWARD or noise.loop_begin != 0 or noise.loop_end != noise.mix_rate:
		return false
	if not is_finite(noise_gain) or noise_gain <= 0:
		return false
	for category: Variant in oscillator_cycles:
		if not category is String or not oscillator_cycles[category] is Dictionary or not oscillators.get(category) is Dictionary:
			return false
		for node: Variant in oscillator_cycles[category]:
			var count: Variant = oscillator_cycles[category][node]
			if not node is String or not oscillators[category].has(node) or not count is int or count < 1:
				return false
	for category: String in ["engine", "rotor", "wingflap", "stomp"]:
		if not oscillators.get(category) is Dictionary or oscillators[category].is_empty():
			return false
		for waveform: Variant in oscillators[category].values():
			if not waveform is PackedFloat32Array or waveform.size() < 2:
				return false
	return true

func waveform(category: String, node: int) -> PackedFloat32Array:
	return oscillators.get(category, {}).get(str(node), PackedFloat32Array())

func cycles(category: String, node: int) -> int:
	return int(oscillator_cycles.get(category, {}).get(str(node), 1))
