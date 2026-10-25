extends Node

const Importer = preload("res://tools/import_worlds.gd")
const Publisher = preload("res://tools/source_resource_publisher.gd")

var assertions := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var directory := "res://build/sol-world-shader-%d" % Time.get_ticks_usec()
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create an isolated publication directory")
	# These programs exercise dependency storage, not source water shading.
	var code := "// Publication probe\nfloat publication_probe() { return 0.25; }\n"
	var result := await Importer._publish_marine_program(code, directory, get_tree())
	_check(result.error.is_empty() and result.program != null, "Publish and reload a fresh shader dependency")
	if result.program != null:
		await _verify_dependency(code, directory, result.program)
	var files := DirAccess.open(directory).get_files()
	for file: String in files:
		_check(not file.contains("partial"), "Completed and rejected publication leaves no incomplete dependency")
		_check(DirAccess.remove_absolute(directory.path_join(file)) == OK, "Remove the test-owned dependency")
	_check(DirAccess.remove_absolute(directory) == OK, "Remove the isolated publication directory")
	print("WORLD_SHADER_PUBLICATION assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _verify_dependency(code: String, directory: String, program: ShaderInclude) -> void:
	var path := directory.path_join(code.sha256_text() + ".gdshaderinc")
	_check(program.resource_path == path and program.code == code, "The shader retains its final content-addressed include path")
	_check(FileAccess.get_sha256(path) == code.sha256_text(), "Native publication retains the exact UTF-8 program bytes")
	var resource := Resource.new()
	resource.set_meta("program", program)
	var resource_path := directory.path_join("world-dependency.res")
	_check(await Publisher.publish(resource, resource_path, get_tree()) == OK, "Publish a resource retaining the external include")
	var reloaded := ResourceLoader.load(resource_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	_check(reloaded != null and reloaded != resource, "Reload the containing resource from disk")
	if reloaded != null:
		var dependency: ShaderInclude = reloaded.get_meta("program")
		_check(dependency != program and dependency.code == code and dependency.resource_path == path,
			"Disk reload independently retains the complete external dependency")
	var modified := FileAccess.get_modified_time(path)
	program.code = code + "// Reader-local mutation\n"
	var reused := await Importer._publish_marine_program(code, directory, get_tree())
	_check(reused.error.is_empty() and reused.program != null, "Reuse a verified existing publication")
	if reused.program != null:
		_check(reused.program != program and reused.program.code == code, "A new import ignores stale cached reader state")
	_check(program.code != code, "Reimport does not mutate a retained reader")
	_check(FileAccess.get_modified_time(path) == modified and FileAccess.get_sha256(path) == code.sha256_text(),
		"Reuse preserves the existing dependency file")
	var sentinel := "Rejected existing bytes\n"
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(sentinel)
	output.close()
	var rejected := await Importer._publish_marine_program(code, directory, get_tree())
	_check(rejected.program == null and rejected.error.begins_with("Corrupt original native marine shader include:"),
		"Reject a corrupt content-addressed dependency before native loading")
	_check(FileAccess.get_file_as_string(path) == sentinel, "A rejected existing file is never overwritten")
	if reused.program != null:
		_check(reused.program.code == code, "A failed import leaves an earlier loaded dependency intact")
