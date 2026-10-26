extends Node

const Collectible = preload("res://scripts/collectible_presentation.gd")

class AnchorWorld extends BattleWorld:
	func source_height(_x: float, _z: float) -> float:
		return 7

var assertions := 0
var failures: Array[String] = []
var reference: Dictionary
var held: Array[Collectible] = []
var resources: Array[WeakRef] = []

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _source() -> void:
	reference = Content.read_json("res://tests/fixtures/collectible_owner.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(reference.formatVersion == 1, "Load original collectible constructors and snapshot/frame methods")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Current collectible producer: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Original collectible dependency agrees with imported metadata: " + path)
	_check(Content.constants.AIRDROP.LAND_S == reference.rules.landing and Content.constants.AIRDROP.DROP_H == reference.rules.height,
		"Original descent constants remain unchanged")

func _drop(id: int = 1) -> Dictionary:
	return {"id": id, "position": Vector3(12, 7, -8), "size": "S", "landing": true}

func _loot(id: int = 2) -> Dictionary:
	return {"id": id, "position": Vector3(12, 7, -8)}

func _sync(view: Collectible, states: Array, now: float = 5) -> void:
	view.call("sync", states, now)

func _track(root: Node3D) -> void:
	resources.append(weakref(root))
	var binding: SourceOutlineBinding = root.get_meta("source_outline_binding", null)
	if binding != null:
		for item: Dictionary in binding.bindings:
			resources.append(weakref(item.material))

func _programs() -> void:
	for program: Dictionary in reference.programs:
		var drop := AirdropPresentation.new()
		var loot := LootPresentation.new()
		var wall := {"now": 5.0}
		drop.wall_clock = func(): return wall.now
		loot.wall_clock = func(): return wall.now
		add_child(drop)
		add_child(loot)
		drop.set_process(false)
		loot.set_process(false)
		var admissions: Array[Vector3] = []
		for view: Collectible in [drop, loot]:
			view.child_entered_tree.connect(func(child: Node) -> void:
				if child is Node3D:
					admissions.append(child.position)
					_track(child))
		for frame: Dictionary in program.frames:
			wall.now = str(frame.wallBits).hex_decode().decode_double(0)
			var point := Vector3(frame.point[0], frame.point[1], frame.point[2])
			var drop_state := {"id": 1, "position": point, "size": "L" if frame.replace else program.size,
				"landing": not program.landing if frame.replace else program.landing}
			var loot_state := {"id": 2, "position": point, "ammo": program.kind != "ammo" if frame.replace else program.kind == "ammo"}
			if (program.kind != "affix" if frame.replace else program.kind == "affix"):
				loot_state.affix = true
			drop.sync([drop_state] if frame.present else [], 100000)
			loot.sync([loot_state] if frame.present else [], -100000)
			var delta := str(frame.deltaBits).hex_decode().decode_double(0)
			drop._process(delta)
			loot._process(delta)
			var expected: Dictionary = frame.result
			_check(drop.entries.size() + loot.entries.size() == int(expected.children), "Original active collectible membership after repeated/removal packets")
			_check(admissions.size() == int(expected.created), "Existing IDs retain the original first-admission model and metadata")
			for index in range(mini(admissions.size(), expected.admissions.size())):
				var original: Array = expected.admissions[index]
				_check(admissions[index] == Vector3(original[0], original[1], original[2]), "Original terrain/world pose is complete before scene admission")
			if expected.drop != null:
				var record: Dictionary = drop.entries[1]
				var original: Dictionary = expected.drop
				_check(record.root.position == Vector3(original.position[0], original.position[1], original.position[2]), "Original descent pose and stable first-observation anchor")
				_check(_bits(record.born) == original.bornBits and record.landing == original.landing,
					"Duplicate snapshots cannot replace initial landing or birth time")
				_check(_bits(record.root_yaw) == original.rootYawBits and _bits(record.crate_yaw) == original.crateYawBits,
					"Original root/crate rotation state survives native ownership checks")
				_check(record.crate.position.y == Vector3(0, original.crateY, 0).y and record.chute.visible == original.chute
					and record.groundChute.visible == original.groundChute and record.halo.visible == original.halo,
					"Original landing visibility and crate bob remain unchanged")
			if expected.loot != null:
				var record: Dictionary = loot.entries[2]
				var original: Dictionary = expected.loot
				_check(record.root.position == Vector3(original.position[0], original.position[1], original.position[2])
					and _bits(record.yaw) == original.yawBits and record.body.position.y == Vector3(0, original.bodyY, 0).y,
					"Original loot pose and double yaw survive repeated metadata and ID reuse")
		for view: Collectible in [drop, loot]:
			view.retire()
			held.append(view)

func _closed(view: Collectible, state: Dictionary) -> void:
	var before := [view.clock, view.revision, view.get_child_count()]
	_sync(view, [state], 99999)
	view.call("_process", 99.0)
	view.retire()
	_check(view.retired and view.entries.is_empty() and not view.wall_clock.is_valid() and not view.visible,
		"Terminal collectible ownership clears resources, clocks and processing")
	_check(before == [view.clock, view.revision, view.get_child_count()], "Late commands cannot resume or allocate a closed presenter")

func _callbacks() -> void:
	for is_drop in [false, true]:
		var view: Collectible = AirdropPresentation.new() if is_drop else LootPresentation.new()
		add_child(view)
		var state := _drop(1) if is_drop else _loot(1)
		var second := state.duplicate(true)
		second.id = 2
		_sync(view, [state, second])
		var records: Array = view.entries.values()
		var root: Node3D = records[0].root
		_track(root)
		root.visibility_changed.connect(func() -> void:
			_check(view.entries.is_empty() and records[0].is_empty() and records[1].is_empty(),
				"Retirement seals all entry references before the first native visibility callback")
			_sync(view, [state]), CONNECT_ONE_SHOT)
		view.retire()
		_closed(view, state)
		held.append(view)
		view = AirdropPresentation.new() if is_drop else LootPresentation.new()
		add_child(view)
		_sync(view, [state, second])
		var removed: Dictionary = view.entries[1]
		var removed_root: Node3D = removed.root
		_track(removed_root)
		var removing_owner := view
		removed_root.visibility_changed.connect(func() -> void:
			_check(removed.is_empty() and not removing_owner.entries.has(1), "Removal seals its record before reentrant replacement")
			_sync(removing_owner, [state]), CONNECT_ONE_SHOT)
		_sync(view, [])
		_check(view.entries.keys() == [1] and view.entries[1].root != removed_root,
			"Removal callback can reuse an ID without the superseded sweep removing its replacement")
		view.retire()
		_closed(view, state)
		held.append(view)
		view = AirdropPresentation.new() if is_drop else LootPresentation.new()
		add_child(view)
		var fresh := state.duplicate(true)
		fresh.id = 9
		var replaced := {"done": false}
		var owner := view
		view.child_entered_tree.connect(func(_child: Node) -> void:
			if not replaced.done:
				replaced.done = true
				_sync(owner, [fresh]))
		_sync(view, [state, second])
		_check(view.entries.keys() == [9], "A reentrant admission snapshot supersedes every remaining old admission")
		_check(view.entries[9].root.has_meta("source_outline_binding"), "A retained reentrant admission already owns its completed native outline binding")
		view.retire()
		_closed(view, state)
		held.append(view)
		view = AirdropPresentation.new() if is_drop else LootPresentation.new()
		add_child(view)
		var clock_owner := view
		view.wall_clock = func():
			clock_owner.retire()
			return 123.0
		_sync(view, [state], 99)
		_check(view.retired and view.clock == 0 and view.entries.is_empty(), "Clock-provider retirement cannot resume stale synchronization")
		_closed(view, state)
		held.append(view)
		var queued: Collectible = AirdropPresentation.new() if is_drop else LootPresentation.new()
		add_child(queued)
		queued.queue_free()
		_sync(queued, [state])
		queued.call("_process", 1.0)
		_check(queued.entries.is_empty() and queued.clock == 0 and queued.revision == 0,
			"Queued owners reject late synchronization and frame updates before exit")
	var drop := AirdropPresentation.new()
	add_child(drop)
	drop.set_process(false)
	var wall := {"now": 5.0}
	drop.wall_clock = func(): return wall.now
	drop.sync([_drop()], 0)
	drop._process(0)
	var record: Dictionary = drop.entries[1]
	_track(record.root)
	record.chute.visibility_changed.connect(drop.retire, CONNECT_ONE_SHOT)
	wall.now += float(Content.constants.AIRDROP.LAND_S) + .01
	drop._process(.2)
	_check(drop.retired and record.is_empty(), "Landing visibility retirement stops the pending crate/halo continuation")
	_closed(drop, _drop())
	held.append(drop)

func _world() -> void:
	var world := AnchorWorld.new()
	add_child(world)
	var drops := [{"id": 1, "x": 12, "z": -8, "size": "S", "landing": true}]
	var loots := [_loot()]
	world.sync_airdrops(drops, 0)
	world.sync_loots(loots, 0)
	var old_drop := world.airdrop_visuals
	var old_loot := world.loot_visuals
	remove_child(world)
	_check(old_drop.retired and old_loot.retired and old_drop.entries.is_empty() and old_loot.entries.is_empty(),
		"World detachment closes dynamic collectible owners")
	add_child(world)
	world.sync_airdrops(drops, 0)
	world.sync_loots(loots, 0)
	_check(world.airdrop_visuals != old_drop and world.loot_visuals != old_loot
		and not world.airdrop_visuals.retired and not world.loot_visuals.retired,
		"Reattached worlds acquire fresh collectible owners")
	world.free()
	var explicit := LootPresentation.new()
	explicit.sync([], 9)
	explicit._process(.2)
	_check(explicit.clock == 9.2, "An unattached fresh fixture retains the existing explicit-clock contract")
	explicit.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Collectible ownership qualification requires a real renderer")
		get_tree().quit(1)
		return
	_source()
	if failures.is_empty():
		_programs()
		_callbacks()
		_world()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in resources:
		_check(resource.get_ref() == null, "Retired roots/private outline materials release after the rendered frame while owners remain retained")
	for view: Collectible in held:
		_check(view.get_child_count() == 0, "Closed collectible presenters retain no staged child resources")
		view.free()
	held.clear()
	print("COLLECTIBLE_RETIREMENT_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
