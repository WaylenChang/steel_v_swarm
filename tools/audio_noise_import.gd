extends RefCounted

static func decode(captured: Dictionary, expected_hash: Variant, payload_key: String = "values") -> PackedFloat32Array:
	if captured.get("encoding") != "float32le" or not NativeAudioCatalogue._valid_hash(expected_hash):
		return []
	for key: String in ["sampleRate", "frames"]:
		if not (captured.get(key) is int or captured.get(key) is float) or not is_finite(float(captured[key])):
			return []
	var rate := float(captured.sampleRate)
	if rate < 8000 or rate > 384000 or rate != floor(rate) or float(captured.frames) != rate:
		return []
	if not captured.get(payload_key) is String:
		return []
	var payload: String = captured[payload_key]
	if payload.length() != ceili(rate * 4 / 3.0) * 4:
		return []
	var unpadded := payload.rstrip("=")
	if payload.length() - unpadded.length() > 2 or not unpadded.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/").is_empty():
		return []
	var bytes := Marshalls.base64_to_raw(payload)
	if bytes.size() != int(rate) * 4 or Marshalls.raw_to_base64(bytes) != payload:
		return []
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish().hex_encode() != expected_hash:
		return []
	var values := bytes.to_float32_array()
	for value: float in values:
		if not is_finite(value):
			return []
	return values
