class_name NativeAudioMoveBank
extends Resource

const PATH := "res://assets/audio/native/movement.res"

@export var noise: AudioStreamWAV
@export var noise_gain := 1.0
@export var oscillators: Dictionary = {}
@export var source: Dictionary = {}

func valid() -> bool:
	if noise == null or noise.stereo or noise.mix_rate <= 0 or noise.loop_mode != AudioStreamWAV.LOOP_FORWARD or noise.loop_begin != 0 or noise.loop_end != noise.mix_rate:
		return false
	if not is_finite(noise_gain) or noise_gain <= 0:
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
