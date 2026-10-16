extends RefCounted

class RecordedEffects extends CombatEffects:
	var bursts: Array = []
	func _ready() -> void:
		pass
	func scene_damage_burst(id: int, _kind: String, _point: Vector3, _height: float, _radius: float, stage: int) -> void:
		bursts.append({"id": id, "stage": stage})
	func _pose(effect: Dictionary, fraction: float, delta: float = 0.0) -> void:
		if effect.obj != null:
			super._pose(effect, fraction, delta)
	func _drop(effect: Dictionary) -> void:
		if effect.obj != null:
			super._drop(effect)

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("bodyRemoval") or not Content.balance.destruction.has("removal"):
		h._check(false, "Regenerate original body removal and shared effect retirement references")
		return
	for authority: bool in [false, true]:
		for item: Dictionary in fixtures.bodyRemoval:
			_case(h, item, authority)
	_exclusions(h)
	print("BODY_REMOVAL_REFERENCE_PASS fixtures=", fixtures.bodyRemoval.size())

static func _case(h: Node, item: Dictionary, authority: bool) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.authoritative = authority
	var world := BattleWorld.new()
	simulation.world = world
	simulation.add_child(world)
	var effects := RecordedEffects.new()
	world.combat_effects = effects
	world.add_child(effects)
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.entity_id = 42
	unit.kind = item.kind
	unit.hp = 0
	unit.max_hp = 100
	unit.geometry_override = {"height": 6.0, "radius": 3.0}
	unit.model = Node3D.new()
	unit.add_child(unit.model)
	unit.model.scale = h._reference_vector(item.scale)
	unit.model.rotation = Vector3(.13, .21, -.17)
	unit.model.position = Vector3(12, 20, -9)
	unit.model.visible = item.visible
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = StandardMaterial3D.new()
	unit.model.add_child(mesh)
	var shared := mesh.mesh
	var material := mesh.material_override
	unit.damage_fx_binding.node = DamageFx.new()
	unit.model.add_child(unit.damage_fx)
	unit.damage_fx_binding.stage = 2
	simulation.units[42] = unit
	simulation.victim_reports[42] = {"hp": 100.0}
	var rng_before := simulation.rng.state
	var projectile_before := simulation.projectile_rng.state
	var removed := {"count": 0}
	simulation.unit_view_removed.connect(func(_model): removed.count += 1)
	var original_frame := unit.model.global_transform
	simulation._retain_removed_body(unit)
	var view: RetiredBody = simulation.retired_bodies[42]
	var model := view.model
	h._check(model.global_transform.is_equal_approx(original_frame), "Retirement retains the last rendered world frame")
	h._check(model.get_parent() == simulation and removed.count == 1, "Detached body leaves the actor and its occlusion registry")
	unit.free()
	simulation.units.erase(42)
	var reports := [{"type": "die", "actor": 42}] if item.dissolve else []
	simulation._present_retired_bodies(reports)
	_compare(h, effects, view, item.initial, item.kind)
	for index in range(item.frames.size()):
		var frame: Dictionary = item.frames[index]
		if item.evict and index == 1:
			for _padding in range(int(Content.balance.npcShots.limits.maximum)):
				effects.effects.append({"type": "padding", "obj": null, "ttl": 100.0, "age": 0.0})
		effects.advance(float(frame.delta))
		_compare(h, effects, view, frame, item.kind)
	var count := effects.bursts.size()
	simulation._present_retired_bodies(reports)
	h._check(effects.bursts.size() == count and simulation.retired_bodies.is_empty(), "Repeated death packets cannot restart a removed body")
	h._check(simulation.rng.state == rng_before and simulation.projectile_rng.state == projectile_before,
		"Presentation retirement preserves both authority RNG streams")
	h._check((shared as BoxMesh).size == Vector3.ONE and (material as StandardMaterial3D).albedo_color == Color.WHITE,
		"Retirement damage never modifies shared source resources")
	simulation.free()

static func _compare(h: Node, effects: RecordedEffects, view: RetiredBody, expected: Dictionary, kind: String) -> void:
	var attached := is_instance_valid(view.model) and not view.model.is_queued_for_deletion()
	h._check(attached == bool(expected.attached), "Original removed body lifetime: " + kind)
	h._check(effects.effects.size() == int(expected.effects), "Original shared removal effect budget and expiry")
	h._check(effects.bursts == expected.bursts, "Removal emits one destination-stage burst before world events")
	if not attached:
		return
	h._check(view.model.visible == bool(expected.visible), "Original invisible bodies retain their visibility during flattening")
	h._check(view.model.scale.distance_to(h._reference_vector(expected.scale)) < .00001, "Original mobile linear and static quadratic removal curves")
	var profile: Dictionary = Content.balance.destruction.sceneProfiles[kind]
	var stage := view.mobile_damage.stage if profile.get("mobile", false) else view.scene_damage.stage
	h._check(stage == int(expected.stage), "Removed known profiles receive stage-three damage")
	h._check(view.damage_fx.node.visible == bool(expected.fxVisible), "Persistent damage FX freeze and hide on body removal")

static func _exclusions(h: Node) -> void:
	var unit := BattleUnit.new()
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	simulation.add_child(unit)
	unit.model = Node3D.new()
	unit.add_child(unit.model)
	unit.kind = "robot"
	simulation._retain_removed_body(unit)
	h._check(simulation.retired_bodies.is_empty() and unit.model.get_parent() == unit,
		"Unobserved authority removals cannot create models outside the viewer's visibility history")
	unit.special.neutral = true
	h._check(RetiredBody.eligible(unit), "Neutral objects retain their separate dissolve lifecycle")
	unit.special.clear()
	unit.kind = "missing_source_profile"
	h._check(RetiredBody.eligible(unit), "Unknown profiles retain their source material dissolve gate")
	simulation.free()
