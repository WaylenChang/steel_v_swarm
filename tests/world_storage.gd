extends Node

const WorldMeshes = preload("res://tools/source_world_meshes.gd")
const FIXTURES := "res://artifacts/agy/oracle-validation/world-source-storage/"

var assertions := 0
var failures: Array[String] = []

func _ready() -> void:
	for name: String in ["native-raw-case.json", "native-case.json"]:
		_run_case(name)
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
