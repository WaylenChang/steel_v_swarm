extends Node

class PoseProbe extends ProjectileVisual:
	var placements := 0

	func place(point: Vector3, _direction: Vector3, _age: float, _speed: float) -> void:
		position = point
		placements += 1

class PresentationProbe extends ProjectilePresentation:
	func _take(key: String) -> ProjectileVisual:
		if not free_models.has(key):
			free_models[key] = []
		var model: PoseProbe
		if free_models[key].is_empty():
			model = PoseProbe.new()
			add_child(model)
		else:
			model = free_models[key].pop_back()
		model.visible = true
		return model

var assertions := 0
var failures := 0

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(label)

func _ready() -> void:
	var view := PresentationProbe.new()
	add_child(view)
	var first := [{"id": "owner/1", "key": "variant", "position": Vector3(1, 2, 3), "velocity": Vector3.FORWARD, "age": 0.0}]
	var moved := first.duplicate(true)
	moved[0].position = Vector3(9, 8, 7)
	view.sync_rounds(first, 10)
	var model: PoseProbe = view.rounds["owner/1"].model
	_check(model.position == first[0].position and model.placements == 1, "First timestamped owner publication creates one pose")
	view.sync_rounds(moved, 10)
	view.sync_rounds([], 9.9)
	_check(view.rounds.size() == 1 and model.position == first[0].position and model.placements == 1,
		"Equal-clock pose changes and stale absence cannot alter the current mesh")
	view.sync_rounds(moved, 10.1)
	_check(model.position == moved[0].position and model.placements == 2, "Newer publication updates the same pooled identity")
	view.sync_rounds(first, 10)
	_check(model.position == moved[0].position and model.placements == 2, "Stale pose cannot rewind a live projectile")
	view.retire_round("owner/1", 10.2)
	view.retire_round("owner/1", 10.15)
	_check(view.rounds.is_empty() and not model.visible and view.retired_rounds["owner/1"] == 10.2,
		"Delayed terminal replay cannot lower the retirement deadline or return a model twice")
	view.sync_rounds(first, 10.15)
	view.sync_rounds([], 10.2)
	_check(view.rounds.is_empty() and view.retired_rounds.has("owner/1"), "Only a strictly newer absence may release the terminal guard")
	view.sync_rounds([], 10.3)
	_check(not view.retired_rounds.has("owner/1"), "Confirmed newer absence releases retained terminal state")
	view.sync_rounds(first, 10.1)
	view.sync_rounds(first, 10.3)
	_check(view.rounds.is_empty() and not model.visible, "Old and same-clock packets cannot resurrect a released terminal identity")
	_check(view.free_models.variant.size() == 1, "Rejected packets do not allocate or duplicate pool entries")
	var next := first.duplicate(true)
	next[0].id = "owner/2"
	view.sync_rounds(next, 10.4)
	_check(view.rounds["owner/2"].model == model and model.visible, "A later launch reuses the retired variant")
	_check(first[0].position == Vector3(1, 2, 3) and first[0].id == "owner/1", "Presentation leaves captured publication data immutable")
	view.sync_rounds([], 10.5)
	_check(view.rounds.is_empty() and not model.visible and view.free_models.variant.size() == 1, "Current absence retires the model once")
	view.free()
	_native_resources()
	print("PROJECTILE_LIFECYCLE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _native_resources() -> void:
	var view := ProjectilePresentation.new()
	add_child(view)
	var states := [{"id": "native/1", "key": "t06-light-steel", "position": Vector3(4, 5, 6),
		"velocity": Vector3.FORWARD * 120, "age": .25}]
	view.sync_rounds(states, 20)
	var model: ProjectileVisual = view.rounds["native/1"].model
	_check(is_instance_valid(model.source_root) and not model.nodes.is_empty(), "Actual packed projectile resource loads into its live pose")
	var colors := {}
	for id: int in model.animated_materials:
		colors[id] = model.animated_materials[id].albedo_color
	var stale := states.duplicate(true)
	stale[0].position = Vector3(40, 50, 60)
	stale[0].age = 3.0
	view.sync_rounds(stale, 20)
	view.sync_rounds(stale, 19)
	_check(model.position == states[0].position, "Rejected snapshots cannot move the packed native mesh")
	for id: int in colors:
		_check(model.animated_materials[id].albedo_color == colors[id], "Rejected snapshots cannot rewind native material animation")
	view.retire_round("native/1", 20.1)
	view.sync_rounds([], 20.2)
	view.sync_rounds(stale, 20)
	_check(not model.visible and view.rounds.is_empty(), "Packed native mesh remains retired after guard reclamation and stale replay")
	states[0].id = "native/2"
	view.sync_rounds(states, 20.3)
	_check(view.rounds["native/2"].model == model and model.visible, "Actual variant resource returns through the matching pool")
	view.free()
