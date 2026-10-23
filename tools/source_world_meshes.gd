extends RefCounted

var valid := true
var index := -1
var has_climb_mesh := false
var _root: String
var _legacy: Array = []
var _chunks: Array = []
var _rows: Array = []
var _chunk := 0
var _row := -1
var _count := 0
var _current: Dictionary = {}
var _verified := {}

func _init(source: Dictionary, resource_root: String = "res://data/worlds") -> void:
	_root = resource_root
	if source.get("worldSourceVersion") == 2:
		if not source.get("meshChunks") is Array or not _integer(source.get("meshCount")):
			_fail("Invalid source world mesh manifest")
			return
		_chunks = source.meshChunks
		_count = int(source.meshCount)
		var total := 0
		for chunk: Variant in _chunks:
			if not chunk is Dictionary or not _integer(chunk.get("start")) or not _integer(chunk.get("count")) or int(chunk.start) != total or int(chunk.count) <= 0:
				_fail("Invalid source world chunk order/count")
				return
			total += int(chunk.count)
		if total != _count:
			_fail("Incomplete source world mesh manifest")
	elif source.get("meshes") is Array:
		_legacy = source.meshes
		_count = _legacy.size()
	else:
		_fail("Missing original world meshes")

func _iter_init(_state: Array) -> bool:
	index = -1
	_chunk = 0
	_row = -1
	_rows = []
	has_climb_mesh = false
	return _advance()

func _iter_next(_state: Array) -> bool:
	return _advance()

func _iter_get(_state: Variant) -> Dictionary:
	return _current

func _advance() -> bool:
	if not valid or index + 1 >= _count:
		return false
	var entry: Variant
	if not _chunks.is_empty():
		_row += 1
		if _row >= _rows.size():
			_rows = _read_chunk(_chunks[_chunk])
			_chunk += 1
			_row = 0
			if not valid:
				return false
		var encoded: Variant = _rows[_row]
		_rows[_row] = null
		entry = _decode(encoded)
	else:
		entry = _decode(_legacy[index + 1])
	if not valid:
		return false
	if not entry is Dictionary:
		_fail("Original world mesh is not a record")
		return false
	index += 1
	_current = entry
	has_climb_mesh = has_climb_mesh or bool(entry.get("sourceClimb", false))
	return true

func _read_chunk(chunk: Dictionary) -> Array:
	if not _integer(chunk.get("plainBytes")) or int(chunk.plainBytes) <= 0 or int(chunk.plainBytes) > 128 * 1024 * 1024:
		_fail("Invalid source world chunk extent")
		return []
	var bytes := _read_bytes(chunk, "/mesh_chunks/", ".json.gz")
	if not valid:
		return []
	var plain := bytes.decompress(int(chunk.plainBytes), FileAccess.COMPRESSION_GZIP)
	if plain.size() != int(chunk.plainBytes):
		_fail("Source world chunk decompression mismatch")
		return []
	var parser := JSON.new()
	if parser.parse(plain.get_string_from_utf8()) != OK or not parser.data is Array or parser.data.size() != int(chunk.count):
		_fail("Invalid source world mesh chunk")
		return []
	return parser.data

func _read_bytes(spec: Dictionary, folder: String, extension: String) -> PackedByteArray:
	var sha: Variant = spec.get("sha256")
	if not sha is String or sha.length() != 64 or sha.hex_decode().size() != 32 or not _integer(spec.get("bytes")) or int(spec.bytes) <= 0 or int(spec.bytes) > 2147483647:
		_fail("Invalid source world buffer declaration")
		return PackedByteArray()
	var expected := _root + folder + str(sha) + extension
	if spec.get("path") != expected:
		_fail("Invalid source world buffer path")
		return PackedByteArray()
	var file := FileAccess.open(expected, FileAccess.READ)
	if file == null or file.get_length() != int(spec.bytes):
		_fail("Missing/truncated source world buffer: " + expected)
		return PackedByteArray()
	var bytes := file.get_buffer(int(spec.bytes))
	file.close()
	if bytes.size() != int(spec.bytes):
		_fail("Incomplete source world buffer read: " + expected)
		return PackedByteArray()
	if not _verified.has(sha):
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		if hash.finish().hex_encode() != sha:
			_fail("Source world buffer hash mismatch: " + expected)
			return PackedByteArray()
		_verified[sha] = true
	return bytes

func _decode(value: Variant, packed_metadata := false) -> Variant:
	if value is Dictionary:
		if value.has("$sourceNumericArray"):
			var spec: Variant = value["$sourceNumericArray"]
			if value.size() != 1 or not spec is Dictionary or spec.get("encoding") not in ["float64le", "float64le-gzip"] or not spec.get("shape") is Array or spec.shape.size() not in [1, 2]:
				_fail("Invalid source numeric array declaration")
				return null
			var count := 1
			for extent: Variant in spec.shape:
				if not _integer(extent) or int(extent) <= 0 or int(extent) > 268435455 / count:
					_fail("Invalid source numeric array extent")
					return null
				count *= int(extent)
			var compressed: bool = spec.encoding == "float64le-gzip"
			if not compressed and spec.get("bytes") != count * 8:
				_fail("Source numeric array storage mismatch")
				return null
			var bytes := _read_bytes(spec, "/buffers/", ".f64.gz" if compressed else ".f64")
			if not valid:
				return null
			if compressed:
				bytes = bytes.decompress(count * 8, FileAccess.COMPRESSION_GZIP)
				if bytes.size() != count * 8:
					_fail("Source numeric array decompression mismatch")
					return null
			var numbers := bytes.to_float64_array()
			if spec.shape.size() == 1:
				return numbers if packed_metadata else Array(numbers)
			var rows := []
			var width := int(spec.shape[1])
			for offset in range(0, count, width):
				rows.append(numbers.slice(offset, offset + width) if packed_metadata else Array(numbers.slice(offset, offset + width)))
			return rows
		for key: Variant in value:
			value[key] = _decode(value[key], packed_metadata or key in ["attributes", "celGeometry"])
	elif value is Array:
		if packed_metadata and value.all(func(number): return (number is int or number is float) and is_finite(float(number))):
			return PackedFloat64Array(value)
		for offset in range(value.size()):
			value[offset] = _decode(value[offset], packed_metadata)
	return value

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) == floorf(float(value))

func _fail(message: String) -> void:
	valid = false
	push_error(message)
