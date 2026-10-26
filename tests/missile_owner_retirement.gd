extends Node

class RecordedEffects extends CombatEffects:
	var bursts: Array[Dictionary] = []
	var callback := Callable()
	func _ready() -> void:
		pass
	func scene_damage_burst(id: int, _kind: String, point: Vector3, _height: float, _radius: float, stage: int) -> void:
		bursts.append({"id": id, "stage": stage, "position": point})
		if callback.is_valid():
			callback.call()

class StepModel extends ProjectileVisual:
	var after_step := Callable()
	func step_fx(clock: float, speed: float) -> void:
		super.step_fx(clock, speed)
		if after_step.is_valid():
			after_step.call()

var assertions := 0
var failures: Array[String] = []
var reference: Dictionary
var retired_resources: Array[WeakRef] = []
var held_owners: Array[MissilePresentation] = []

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _source() -> void:
	reference = Content.read_json("res://tests/fixtures/missile_owner.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(reference.formatVersion == 1, "Load original missile owner methods")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Current missile ownership capture: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Original missile input agrees with imported provenance: " + path)

func _view() -> MissilePresentation:
	var view := MissilePresentation.new()
	add_child(view)
	_check(view.configure(7, Vector3(12, 20, -9)), "Load the original packed SAM projectile")
	return view

func _track(view: MissilePresentation) -> void:
	retired_resources.append(weakref(view.model))
	for material: Material in view.model.animated_materials.values():
		retired_resources.append(weakref(material))

func _closed(view: MissilePresentation, effects: RecordedEffects) -> void:
	var before := [view.position, view.target, view.previous, view.age, view.smoke, effects.bursts.size(), effects.effects.size(), view.get_child_count()]
	view.observe({"hp": 0.0, "max_hp": 100.0}, Vector3(99, 100, 101), effects)
	view.advance(.5, effects)
	view.release(effects, true)
	view.retire()
	_check(not view.configure(8, Vector3.ZERO), "A retired missile cannot be configured again")
	_check(before == [view.position, view.target, view.previous, view.age, view.smoke, effects.bursts.size(), effects.effects.size(), view.get_child_count()],
		"Late commands cannot move, emit, allocate or fracture a retired missile")
	_check(view.retired and not view.visible and view.model == null and view.ray.parts.is_empty()
		and view.mobile_damage.root == null and view.damage_fx.node == null, "Terminal ownership releases model, damage and private ray references")

func _programs() -> void:
	for program: Dictionary in reference.programs:
		var effects := RecordedEffects.new()
		add_child(effects)
		var view := _view()
		_track(view)
		for frame: Dictionary in program.frames:
			view.observe({}, _point(frame.point), effects)
			view.advance(str(frame.deltaBits).hex_decode().decode_double(0), effects)
			_check(view.position.distance_to(_point(frame.position)) < .00001, "Original exponential missile interpolation")
			var rotation := Quaternion(frame.quaternion[0], frame.quaternion[1], frame.quaternion[2], frame.quaternion[3])
			_check(absf(view.quaternion.dot(rotation)) > .999999, "Original strict heading gate and positive-Z projectile direction")
			_check(_bits(view.age) == frame.ageBits and _bits(view.smoke) == frame.smokeBits, "Exact source missile age and smoke clock")
			_check(effects.effects.size() == frame.puffs.size(), "Original strict smoke deadline emits at most one puff per frame")
			for index in range(mini(effects.effects.size(), frame.puffs.size())):
				_check(effects.effects[index].obj.position.distance_to(_point(frame.puffs[index])) < .00001, "Original smoke follows the interpolated missile")
		view.release(effects, not program.first.bursts.is_empty())
		_check(effects.bursts.size() == program.first.bursts.size() and int(program.first.disposed) == 1
			and int(program.first.count) == 0, "Original silent versus matching impact removal")
		if not effects.bursts.is_empty():
			var expected: Dictionary = program.first.bursts[0]
			_check(effects.bursts[0].id == int(expected.id) and effects.bursts[0].stage == int(expected.stage)
				and effects.bursts[0].position.distance_to(_point(expected.position)) < .00001, "Original final fracture point and stage")
		_closed(view, effects)
		_check(effects.bursts.size() == program.after.bursts.size() and effects.effects.size() == int(program.after.puffs),
			"Repeated source removal and native late updates remain silent")
		held_owners.append(view)
		effects.free()

func _callbacks() -> void:
	var effects := RecordedEffects.new()
	add_child(effects)
	var view := _view()
	_track(view)
	var terminal_view := view
	effects.callback = func() -> void: terminal_view.release(effects, true)
	view.release(effects, true)
	_check(effects.bursts.size() == 1, "Seal retirement before the fracture callback can reenter release")
	_closed(view, effects)
	held_owners.append(view)
	effects.callback = Callable()
	effects.bursts.clear()
	view = _view()
	_track(view)
	view.observe({"hp": 100.0, "max_hp": 100.0}, view.position, effects)
	var observed := view
	var old_target := view.target
	effects.callback = func() -> void: observed.release(effects, false)
	view.observe({"hp": 49.0, "max_hp": 100.0}, Vector3(50, 60, 70), effects)
	_check(view.target == old_target and view.retired and view.damage_fx.node == null,
		"Damage-burst retirement stops the pending health and target continuation")
	_closed(view, effects)
	held_owners.append(view)
	effects.callback = Callable()
	effects.free()

func _detach_and_admission() -> void:
	var effects := RecordedEffects.new()
	add_child(effects)
	var view := _view()
	_track(view)
	remove_child(view)
	add_child(view)
	_closed(view, effects)
	held_owners.append(view)
	view = MissilePresentation.new()
	add_child(view)
	var admitted := view
	view.child_entered_tree.connect(func(child: Node) -> void:
		if child is ProjectileVisual:
			admitted.retire())
	_check(not view.configure(7, Vector3.ZERO), "Reentrant native child admission can retire missile construction")
	_closed(view, effects)
	held_owners.append(view)
	view = _view()
	_track(view)
	view.queue_free()
	view.release(effects, true)
	_check(effects.bursts.is_empty(), "Queued owner disposal cannot turn a late release into an impact")
	effects.free()

func _model_callback() -> void:
	var effects := RecordedEffects.new()
	add_child(effects)
	var view := _view()
	_track(view)
	view.model.queue_free()
	var model := StepModel.new()
	view.add_child(model)
	model.configure("sam-source")
	view.model = model
	_track(view)
	model.after_step = view.retire
	view.advance(.1, effects)
	_check(view.retired and view.smoke == 0 and effects.effects.is_empty(),
		"Projectile model callback retirement stops the pending smoke continuation")
	_closed(view, effects)
	held_owners.append(view)
	effects.free()

func _damaged_owner() -> void:
	var effects := RecordedEffects.new()
	effects.random_sample = func() -> float: return .5
	add_child(effects)
	var view := _view()
	_track(view)
	view.observe({"hp": 24.0, "max_hp": 100.0}, view.position, effects)
	_check(view.mobile_damage.initialized and view.damage_fx.node != null, "Retirement starts with actual damaged geometry and persistent FX")
	retired_resources.append(weakref(view.damage_fx.node))
	for particle: Dictionary in view.damage_fx.node.smoke:
		retired_resources.append(weakref(particle.node.mesh))
		retired_resources.append(weakref(particle.node.material_override))
	for material: Material in view.mobile_damage.material_copies.values():
		retired_resources.append(weakref(material))
	view.retire()
	_closed(view, effects)
	held_owners.append(view)
	view = _view()
	_track(view)
	var admitted := view
	view.child_entered_tree.connect(func(child: Node) -> void:
		if child is DamageFx:
			admitted.retire())
	view.observe({"hp": 24.0, "max_hp": 100.0}, Vector3(50, 60, 70), effects)
	_check(view.retired and view.target == Vector3(12, 20, -9), "Damage helper admission retirement cannot resume the target continuation")
	_closed(view, effects)
	held_owners.append(view)
	effects.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Missile owner acceptance requires a real renderer")
		get_tree().quit(1)
		return
	_source()
	if not failures.is_empty():
		get_tree().quit(1)
		return
	_programs()
	_callbacks()
	_detach_and_admission()
	_model_callback()
	_damaged_owner()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in retired_resources:
		_check(resource.get_ref() == null, "Retired packed missiles and private animation materials release after the rendered frame")
	for owner: MissilePresentation in held_owners:
		_check(is_instance_valid(owner) and owner.get_child_count() == 0, "Retirement releases children even while the closed owner is retained")
		owner.free()
	held_owners.clear()
	print("MISSILE_OWNER_RETIREMENT_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
