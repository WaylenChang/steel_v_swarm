extends RefCounted

# Godot 4.7.2 WAV decoding divides signed samples by 32767. Source PCM and
# captured normalization gains use the standard 32768 denominator.
static func native_gain(stream: AudioStream, source_gain: float) -> float:
	return source_gain * (32767.0 / 32768.0) if stream is AudioStreamWAV else source_gain
