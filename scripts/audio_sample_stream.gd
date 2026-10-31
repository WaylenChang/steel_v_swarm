extends RefCounted

# AudioBufferSource uses linear interpolation with a Float32 AudioParam rate.
# Prepare a private device-rate WAV so Godot's cubic pitch interpolator is idle.
static func prepare(source: AudioStreamWAV, rate: float) -> Dictionary:
	if source == null or source.stereo or source.loop_mode != AudioStreamWAV.LOOP_DISABLED \
		or source.format != AudioStreamWAV.FORMAT_16_BITS \
		or not is_finite(rate) or rate <= 0:
		return {}
	var target_rate := int(AudioServer.get_mix_rate())
	var source_bytes := source.data
	if source_bytes.is_empty() or source_bytes.size() % 2 != 0:
		return {}
	var parameter := PackedFloat32Array([rate])[0]
	var step := parameter * (float(source.mix_rate) / target_rate)
	if not is_finite(step) or step <= 0:
		return {}
	var stream := source
	var gain := 1.0
	if step != 1.0:
		var bytes := source_bytes
		var count := bytes.size() / 2
		var extent := ceilf(float(count) / step)
		if count <= 0 or not is_finite(extent) or extent >= (2147483647 - 140) / 2:
			return {}
		var last := float(bytes.decode_s16((count - 1) * 2)) / 32768.0
		var previous := float(bytes.decode_s16(maxi(0, count - 2) * 2)) / 32768.0
		# Interior linear interpolation stays within PCM full scale. The final
		# extrapolation is bounded by its two fraction endpoints; no peak scan or
		# envelope pass is needed for this constant-gain source buffer.
		gain = maxf(1.0, absf(last + (last - previous))) * 32768.0 / 32767.0
		var output := PackedByteArray()
		output.resize(int(extent) * 2)
		var position := 0.0
		var frame := 0
		while position < count:
			var index := int(position)
			var fraction := position - index
			var first := float(bytes.decode_s16(index * 2)) / 32768.0
			var value: float
			if index == count - 1 and index > 0:
				# The original extrapolates from the last two frames at the boundary.
				value = first + (first - previous) * fraction
			else:
				var second := float(bytes.decode_s16(mini(index + 1, count - 1) * 2)) / 32768.0
				value = (1.0 - fraction) * first + fraction * second
			if frame * 2 == output.size():
				output.resize(output.size() + 2)
			output.encode_s16(frame * 2, NativeAudioStem.quantize_pcm16(Vector2(value, 0).x, gain))
			frame += 1
			position += step
		output.resize(frame * 2)
		stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = target_rate
		stream.data = output
	# Godot 4.7.2 EOF drops 64 server lookahead frames, plus four resampler
	# history and two startup frames. Keep this drain entirely after source audio.
	var tail := 70
	var bytes := stream.data
	bytes.resize(bytes.size() + tail * 2)
	var padded := stream.duplicate() as AudioStreamWAV
	padded.mix_rate = target_rate
	padded.data = bytes
	return {"stream": padded, "gain": gain, "rate": 1.0}
