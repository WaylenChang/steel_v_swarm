class_name AudioGeneratorFeed
extends AudioStream

var playback: AudioStreamGeneratorPlayback

static func startup_frames(interval: float, rate: float) -> int:
	# Godot 4.7.2's AudioStreamPlaybackResampled refills whole 128-frame blocks.
	return clampi(ceili(interval * rate / 128.0) * 128, 128, 4096) * 2

func configure(rate: float) -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = rate
	generator.buffer_length = .25
	playback = generator.instantiate_playback() as AudioStreamGeneratorPlayback
	# Native generator playback holds a raw owner pointer; retain it through fade-out.
	playback.set_meta("_svs_generator", generator)

func _instantiate_playback() -> AudioStreamPlayback:
	# Each private feed belongs to one permanent player and is filled before play().
	return playback

func _get_length() -> float:
	return 0

func _is_monophonic() -> bool:
	return true
