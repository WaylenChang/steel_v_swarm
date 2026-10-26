extends Node

const WorldMeshes = preload("res://tools/source_world_meshes.gd")
const FIXTURES := "res://artifacts/agy/oracle-validation/world-source-storage/"

class RejectionReader extends WorldMeshes:
	var rejections: Array[String] = []
	func _fail(message: String) -> void:
		valid = false
		rejections.append(message)

var assertions := 0
var failures: Array[String] = []

func _ready() -> void:
	for name: String in ["native-raw-case.json", "native-case.json"]:
		_run_case(name)
	_rejections()
	_path_verification()
	print("WORLD_STORAGE assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run_case(name: String) -> void:
	if not FileAccess.file_exists(FIXTURES + name):
		_check(false, "Generate world storage fixtures with node --test tests/world_source.test.mjs")
		return
	var fixture: Dictionary = Content.read_json(FIXTURES + name)
	var manifest: Dictionary = Content.read_json(fixture.manifest)
	var reader := WorldMeshes.new(manifest, fixture.resourceRoot)
	var meshes: Array = []
	for mesh: Dictionary in reader:
		_check(reader.index == meshes.size(), name + ": native traversal preserves mesh indices")
		meshes.append(mesh)
	_check(reader.valid and meshes.size() == int(fixture.meshCount), name + ": every source mesh decodes natively")
	if not reader.valid or meshes.size() != 3:
		return
	_check(meshes.map(func(mesh): return mesh.name) == ["ground", "clone", "small"], name + ": native traversal preserves source order")
	_check(reader.has_climb_mesh and meshes[1].sourceClimb, name + ": feature metadata survives chunk traversal")
	_check(meshes[0].attributes.position.values is PackedFloat64Array,
		name + ": attribute metadata retains packed float64 storage")
	_check(meshes[0].positions == meshes[1].positions and meshes[0].instances == meshes[1].instances,
		name + ": shared content-addressed sidecars decode identically")
	_check(meshes[2].nested.flags == [true, false, null], name + ": nonnumeric feature fields retain their types")
	_check_bits(meshes[0], fixture, name + ": decoded")
	var resource := Resource.new()
	resource.set_meta("meshes", meshes)
	var path := "user://world-storage-%d.res" % Time.get_ticks_usec()
	var saved := ResourceSaver.save(resource, path)
	_check(saved == OK, name + ": native numeric metadata saves as a resource")
	if saved != OK:
		return
	var reloaded := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	_check(reloaded != null and reloaded != resource, name + ": reload reads a new resource from disk")
	if reloaded != null:
		var stored: Array = reloaded.get_meta("meshes", [])
		_check(stored == meshes, name + ": native resource reload preserves all mesh fields")
		if stored.size() == meshes.size():
			_check_bits(stored[0], fixture, name + ": reloaded")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
		name + ": temporary native resource is released and removed")

func _rejections() -> void:
	for version: Variant in [null, false, "2", -1, 0, 2.5, 3]:
		var reader := RejectionReader.new({"worldSourceVersion": version, "meshes": [{"name": "legacy"}]})
		_check(not reader.valid and reader.rejections == ["Unsupported source world mesh storage version"],
			"Explicit unsupported versions cannot fall through to legacy mesh storage: " + str(version))
	var legacy := RejectionReader.new({"meshes": [{"name": "legacy", "positions": [0.0, 0.25, -1.5]}]})
	var rows := []
	for mesh: Dictionary in legacy:
		rows.append(mesh)
	_check(legacy.valid and legacy.rejections.is_empty() and rows.size() == 1 and rows[0].name == "legacy",
		"Unversioned original legacy storage remains readable")
	var empty := RejectionReader.new({"worldSourceVersion": 2, "meshCount": 0, "meshChunks": []})
	_check(empty.valid and empty.rejections.is_empty(), "A completed empty storage manifest remains valid")
	var marker := RejectionReader.new({"meshes": []})
	var result: Variant = marker._decode({"nested": {"$sourceArray": 0}})
	_check(not marker.valid and marker.rejections == ["Unfinished source numeric transfer"] and result.nested == null,
		"Unfinished numeric transfer markers are rejected even in nested metadata")
	for sha: String in ["g".repeat(64), "A".repeat(64), "0".repeat(63), "-".repeat(64), "-" + "0".repeat(63), "+" + "0".repeat(63)]:
		var invalid := RejectionReader.new({"meshes": []})
		var bytes := invalid._read_bytes({"sha256": sha, "bytes": 8}, "/buffers/", ".f64")
		_check(not invalid.valid and bytes.is_empty() and invalid.rejections == ["Invalid source world buffer declaration"],
			"Invalid SHA declarations fail without invoking a native decoder or file read: " + sha)

func _path_verification() -> void:
	var root := "user://world-storage-integrity-%d" % Time.get_ticks_usec()
	for folder: String in ["buffers", "mesh_chunks"]:
		_check(DirAccess.make_dir_recursive_absolute(root + "/" + folder) == OK,
			"Storage verification probe directory is created")
	var original := "[{\"name\":\"verified\"}]".to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(original)
	var sha := hash.finish().hex_encode()
	var corrupted := original.duplicate()
	corrupted[0] = corrupted[0] ^ 1
	var paths := [root + "/buffers/" + sha + ".f64", root + "/buffers/" + sha + ".f64.gz", root + "/mesh_chunks/" + sha + ".json.gz"]
	var folders := ["/buffers/", "/buffers/", "/mesh_chunks/"]
	var extensions := [".f64", ".f64.gz", ".json.gz"]
	for source in range(paths.size()):
		for destination in range(paths.size()):
			if source == destination:
				continue
			for path: String in paths:
				var output := FileAccess.open(path, FileAccess.WRITE)
				_check(output != null, "Storage verification probe file opens")
				if output == null:
					return
				output.store_buffer(corrupted if path == paths[destination] else original)
				output.close()
			var reader := RejectionReader.new({"meshes": []}, root)
			var spec := {"sha256": sha, "bytes": original.size(), "path": paths[source]}
			_check(reader._read_bytes(spec, folders[source], extensions[source]) == original and reader.valid,
				"Original bytes verify before another storage path is read")
			spec.path = paths[destination]
			var rejected := reader._read_bytes(spec, folders[destination], extensions[destination])
			_check(not reader.valid and rejected.is_empty() and reader.rejections == ["Source world buffer hash mismatch: " + paths[destination]],
				"A verified digest cannot authenticate a different storage path: %d -> %d" % [source, destination])
	var shared := RejectionReader.new({"meshes": []}, root)
	for offset in range(paths.size()):
		var output := FileAccess.open(paths[offset], FileAccess.WRITE)
		_check(output != null, "Valid shared-digest probe file opens")
		if output == null:
			return
		output.store_buffer(original)
		output.close()
		var spec := {"sha256": sha, "bytes": original.size(), "path": paths[offset]}
		_check(shared._read_bytes(spec, folders[offset], extensions[offset]) == original and shared.valid,
			"Identical bytes remain valid under each complete storage path")
		_check(shared._read_bytes(spec, folders[offset], extensions[offset]) == original and shared.valid,
			"Repeated reads of an authenticated storage path remain valid")
	for path: String in paths:
		_check(DirAccess.remove_absolute(path) == OK, "Storage verification probe file is released")
	for suffix: String in ["/buffers", "/mesh_chunks", ""]:
		_check(DirAccess.remove_absolute(root + suffix) == OK, "Storage verification probe directory is released")

func _check_bits(mesh: Dictionary, fixture: Dictionary, label: String) -> void:
	for entry: Dictionary in fixture.checks:
		var values: Array = mesh[entry.key]
		var numbers := PackedFloat64Array()
		if entry.spec.shape.size() == 1:
			numbers = PackedFloat64Array(values)
		else:
			for row: Array in values:
				_check(row.size() == int(entry.spec.shape[1]), label + ": matrix width matches the source shape")
				numbers.append_array(PackedFloat64Array(row))
		var bytes := numbers.to_byte_array()
		var expected_bytes := 8
		for extent: float in entry.spec.shape:
			expected_bytes *= int(extent)
		_check(bytes.size() == expected_bytes, label + ": numeric byte extent matches the source shape")
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		_check(hash.finish().hex_encode() == entry.numericSha256, label + ": every float64 bit matches the original writer input")
