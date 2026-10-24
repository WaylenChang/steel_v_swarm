extends Node

var failures := 0
var assertions := 0

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var selected: Dictionary = Content.read_json("res://data/fixtures.json", ["rng"])
	_check(selected.keys() == ["rng"] and not selected.rng.is_empty(), "Requested fixture sections retain dictionary compatibility without loading unrelated cases")
	var registry := Content.fixture_registry
	var producers: Dictionary = registry.get("producers", {})
	_check(not producers.is_empty(), "Captured fixture sections identify their actual migration producers")
	for producer: Dictionary in producers.values():
		_check(producer.get("format") == "migration-generator-sha256-v1" and producer.get("node", "") is String and not producer.get("node", "").is_empty()
			and not producer.get("inputs", {}).is_empty(), "Producer identity retains the generator format, offline runtime and complete input hashes")
	var checked_parts := 0
	for key: String in registry.sectionOrder:
		var section: Dictionary = registry.sections[key]
		_check(producers.has(section.get("producer", "")), "Every complete fixture section retains its captured producer: " + key)
		var rows := 0
		for index in section.parts.size():
			var value: Variant = Content.read_fixture_part(key, index)
			_check(section.kind == "value" or value != null, "Source fixture partition decodes with its original hash: " + key)
			if section.kind == "array":
				rows += value.size()
			checked_parts += 1
			value = null
		if section.kind == "array":
			_check(rows == int(section.count), "Every captured case remains in original section order: " + key)
		await get_tree().process_frame
	print("FIXTURE_REGISTRY_%s assertions=%d failures=%d sections=%d parts=%d" % ["PASS" if failures == 0 else "FAIL", assertions, failures, registry.sections.size(), checked_parts])
	get_tree().quit(0 if failures == 0 else 1)
