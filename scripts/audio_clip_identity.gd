extends RefCounted

static func matches(clip: NativeAudioClip, id: String, expected: String) -> bool:
	return expected.length() == 64 and clip != null and clip.source.get("layer") == "sample" and clip.source.get("id") == id and digest(clip) == expected

static func digest(clip: NativeAudioClip) -> String:
	if clip == null or not clip.valid():
		return ""
	var streams: Array[AudioStreamWAV] = clip.panned.duplicate()
	if clip.centered != null:
		streams.append(clip.centered)
	var layouts: Array = []
	for stream in streams:
		layouts.append({"format": stream.format, "rate": stream.mix_rate, "stereo": stream.stereo,
			"loop": stream.loop_mode, "begin": stream.loop_begin, "end": stream.loop_end, "bytes": stream.data.size()})
	var header := {"version": 1, "source": clip.source, "channels": clip.channel_count,
		"panned": clip.panned.size(), "centered": clip.centered != null, "streams": layouts}
	var gains := PackedFloat64Array([clip.centered_gain, clip.reservation_seconds])
	gains.append_array(PackedFloat64Array(clip.panned_gains))
	var encoded := PackedByteArray()
	encoded.resize(gains.size() * 8)
	for index in range(gains.size()):
		encoded.encode_double(index * 8, gains[index])
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(JSON.stringify(header, "", true, true).to_utf8_buffer())
	hash.update(encoded)
	for stream in streams:
		hash.update(stream.data)
	return hash.finish().hex_encode()
