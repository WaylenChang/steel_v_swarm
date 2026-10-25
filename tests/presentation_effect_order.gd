extends Node

class RecordedCombat extends CombatEffects:
	var events: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _pose(effect: Dictionary, fraction: float, delta: float = 0.0) -> void:
		events.append({"op": "fade", "id": effect.id, "fractionBits": _bits(fraction), "deltaBits": _bits(delta)})
		super._pose(effect, fraction, delta)
	func _drop(effect: Dictionary) -> void:
		events.append({"op": "drop", "id": effect.id})
		super._drop(effect)
	static func _bits(value: float) -> String:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, value)
		return bytes.hex_encode()

class RecordedTraces extends ProjectilePresentation:
	var events: Array[Dictionary] = []
	func advance_effect(effect: Dictionary, delta: float) -> void:
		if _active() and traces.has(effect):
			var ttl := float(effect.ttl) - delta
			var age := float(effect.age) + delta
			var fraction := maxf(0, ttl / (ttl + age))
			events.append({"op": "fade", "id": effect.id, "fractionBits": RecordedCombat._bits(fraction), "deltaBits": RecordedCombat._bits(delta)})
		super.advance_effect(effect, delta)
	func _release_trace(effect: Dictionary) -> void:
		events.append({"op": "drop", "id": effect.id})
		super._release_trace(effect)

var assertions := 0
var failures: Array[String] = []
var reference: Dictionary

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _source() -> void:
	reference = Content.read_json("res://data/presentation_effect_order.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(reference.formatVersion == 1, "Load original mixed effect update programs")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Current effect oracle producer: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Imported original effect dependency: " + path)
	_check(int(reference.maximum) == int(Content.balance.npcShots.limits.maximum), "Original shared effect capacity")

func _double(hex: String) -> float:
	return hex.hex_decode().decode_double(0)

func _append(world: BattleWorld, records: Array, items: Array) -> void:
	for item: Dictionary in items:
		var record: Dictionary
		var duration := _double(item.get("durationBits", item.ttlBits))
		if item.kind == "tracer":
			world.projectile_visuals.tracer(Vector3.ZERO, Vector3.ONE, Color.WHITE, duration)
			record = world.projectile_visuals.traces.back()
			record.id = int(item.id)
		else:
			var owner := world.combat_effects
			record = {"id": int(item.id), "key": "missile_smoke", "type": "missile_smoke", "obj": owner._take("missile_smoke")}
			owner._push(record, duration)
		record.ttl = _double(item.ttlBits)
		if item.has("ageBits"):
			record.age = _double(item.ageBits)
		record.kind = item.kind
		records.append(record)

func _mixed() -> void:
	for program: Dictionary in reference.cases:
		var world := BattleWorld.new()
		add_child(world)
		var combat := RecordedCombat.new()
		var traces := RecordedTraces.new()
		world.combat_effects = combat
		world.projectile_visuals = traces
		world.add_child(combat)
		world.add_child(traces)
		world.ensure_combat_effects()
		var events: Array[Dictionary] = []
		combat.events = events
		traces.events = events
		var records: Array = []
		_append(world, records, program.initial)
		for frame: Dictionary in program.frames:
			_append(world, records, frame.added)
			events.clear()
			world.step_projectile_visuals(_double(frame.deltaBits))
			_check(events.size() == frame.events.size(), "Original mixed effect event count")
			for index in range(mini(events.size(), frame.events.size())):
				var actual_event: Dictionary = events[index]
				var expected_event: Dictionary = frame.events[index]
				_check(actual_event.op == expected_event.op and int(actual_event.id) == int(expected_event.id),
					"Original mixed oldest-first trimming and reverse fade/expiry event order")
				if expected_event.op == "fade":
					_check(actual_event.get("fractionBits") == expected_event.fractionBits
						and actual_event.get("deltaBits") == expected_event.deltaBits, "Original exact fade fraction and frame delta")
			var remaining: Array = []
			remaining.append_array(combat.effects)
			remaining.append_array(traces.traces)
			remaining.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.order < right.order)
			_check(remaining.size() == frame.remaining.size(), "Mixed effect count after source frame")
			for index in range(mini(remaining.size(), frame.remaining.size())):
				var actual: Dictionary = remaining[index]
				var expected: Dictionary = frame.remaining[index]
				_check(actual.id == int(expected.id) and RecordedCombat._bits(actual.ttl) == expected.ttlBits
					and RecordedCombat._bits(actual.age) == expected.ageBits, "Original ordered survivors retain exact TTL/age bits")
				if expected.opacity != null:
					_check(absf(actual.line.material_override.albedo_color.a - float(expected.opacity)) < .0000001,
						"Original tracer fade reaches the retained native material")
		world.free()

func _crowding() -> void:
	var world := BattleWorld.new()
	add_child(world)
	var combat := RecordedCombat.new()
	var traces := RecordedTraces.new()
	world.combat_effects = combat
	world.projectile_visuals = traces
	world.add_child(combat)
	world.add_child(traces)
	world.ensure_combat_effects()
	# Count-only probes isolate source admission gates from effect construction.
	for item: Dictionary in reference.crowd:
		combat.effects.clear()
		traces.traces.clear()
		combat.low_power = item.low
		for index in range(int(item.count)):
			if index % 2 == 0:
				traces.traces.append({"line": null})
			else:
				combat.effects.append({})
		_check(combat.crowded() == item.result, "Original full/low quality crowding includes both owners")
	combat.effects.clear()
	traces.traces.clear()
	traces.retire()
	combat.effects.resize(int(Content.balance.npcShots.limits.normal) - 1)
	combat.low_power = false
	_check(not combat.crowded(), "A retired tracer owner contributes no live effects")
	combat.effects.clear()
	world.free()

func _invalid_delta() -> void:
	var combat := RecordedCombat.new()
	add_child(combat)
	var effect := {"id": 1, "key": "missile_smoke", "type": "missile_smoke", "obj": combat._take("missile_smoke")}
	combat._push(effect, .1)
	combat.events.clear()
	for delta: float in [NAN, INF, -INF, -.1]:
		combat.advance(delta)
	_check(combat.events.is_empty() and effect.ttl == .1 and effect.age == 0, "Invalid presentation deltas cannot mutate effects")
	combat.free()

func _retirement_during_trim() -> void:
	var world := BattleWorld.new()
	add_child(world)
	var combat := RecordedCombat.new()
	var traces := RecordedTraces.new()
	world.combat_effects = combat
	world.projectile_visuals = traces
	world.add_child(combat)
	world.add_child(traces)
	world.ensure_combat_effects()
	var records: Array = []
	var items: Array = []
	for index in range(int(reference.maximum) + 1):
		items.append({"id": index, "kind": "tracer", "ttlBits": RecordedCombat._bits(.3)})
	items.append({"id": int(reference.maximum) + 1, "kind": "combat", "ttlBits": RecordedCombat._bits(.3)})
	_append(world, records, items)
	var first_line: MeshInstance3D = traces.traces[0].line
	first_line.visibility_changed.connect(func() -> void:
		if not first_line.visible:
			traces.retire())
	combat.events.clear()
	world.step_projectile_visuals(.05)
	_check(traces.retired and traces.traces.is_empty(), "Overflow visibility callback can retire the tracer owner")
	_check(combat.effects.size() == 1 and combat.events.size() == 1 and combat.events[0].op == "fade",
		"Retiring one owner cannot skip or repeat the other owner's reverse update")
	world.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Effect order acceptance requires the real renderer")
		get_tree().quit(1)
		return
	_source()
	_mixed()
	_crowding()
	_invalid_delta()
	_retirement_during_trim()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("PRESENTATION_EFFECT_ORDER_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
