extends Node

var failures := 0
var assertions := 0

func _ready() -> void:
	var importer := preload("res://tools/import_worlds.gd").new()
	if OS.get_cmdline_user_args().has("--non-glowing"):
		_round_trip(importer)
		importer.free()
		print("WORLD_TEXT_STORAGE assertions=", assertions, " failures=", failures)
		get_tree().quit(0 if failures == 0 else 1)
		return
	var result := importer._mesh({"positions": [0, 0, 0, 1, 0, 0, 0, 1, 0],
		"sourceWorldText": {"glow": [0, 1, 0]}})
	importer.free()
	if result != null:
		push_error("Unsupported original world-text glow was silently accepted")
		get_tree().quit(2)
		return
	print("WORLD_TEXT_IMPORT_REJECTED")
	get_tree().quit(1)

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(description)

func _round_trip(importer: Node) -> void:
	var text := {"language": "local", "scale": 1.0, "count": 1, "dropped": 0,
		"atlas": {"width": 512, "height": 128}, "glow": [0, 0, 0, 0],
		"items": [{"copy": {"t": "Canal"}, "style": "stone"}]}
	var entry := {"positions": [-2, -1, 0, 2, -1, 0, 2, 1, 0, -2, 1, 0],
		"normals": [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], "colors": [],
		"uv": [0, 0, 1, 0, 1, 1, 0, 1], "index": [0, 1, 2, 0, 2, 3], "sourceWorldText": text.duplicate(true)}
	var mesh: ArrayMesh = importer._mesh(entry)
	_check(mesh != null, "Non-glowing original text metadata remains packable")
	if mesh == null:
		return
	_check(mesh.get_meta("source_world_text") == text, "Native mesh retains original text constructor and glow metadata")
	entry.sourceWorldText.items[0].copy.t = "Changed"
	_check(mesh.get_meta("source_world_text") == text, "Native text metadata is isolated from mutable capture records")
	DirAccess.make_dir_recursive_absolute("res://build")
	var path := "res://build/sol-world-text-mesh.res"
	_check(ResourceSaver.save(mesh, path) == OK, "Native world-text metadata can be published as a resource")
	var reloaded := ResourceLoader.load(path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	_check(reloaded != null and reloaded.get_meta("source_world_text") == text, "Native resource reload retains exact original text fields")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "World-text resource fixture removes its own output")
