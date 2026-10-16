class_name RetiredBody
extends RefCounted

var id := 0
var kind := ""
var model: Node3D
var dimensions: Dictionary = {}
var mobile_damage: MobileDamageGeometry
var scene_damage: SceneDamageGeometry
var damage_fx: DamageFxBinding
var neutral := false
var collapsed := false
var dissolve := DissolveBinding.new()
var age := 0.0

static func eligible(unit: BattleUnit) -> bool:
	return unit.model != null

static func capture(unit: BattleUnit, parent: Node3D) -> RetiredBody:
	var view := RetiredBody.new()
	view.id = unit.entity_id
	view.kind = unit.kind
	view.model = unit.model
	view.dimensions = (unit.body.profile.dimensions if unit.body != null else unit.geometry_override).duplicate()
	view.mobile_damage = unit.mobile_damage
	view.scene_damage = unit.scene_damage
	view.damage_fx = unit.damage_fx_binding
	# Source civilian views use civ, independently of gameplay neutrality.
	view.neutral = bool(unit.special.get("neutral", false)) and unit.special.get("role") != "civilian"
	view.collapsed = bool(unit.special.get("collapsed", false))
	var shown := unit.presentation_visible and view.model.visible and not unit.special.get("garrison", false)
	view.model.reparent(parent, true)
	view.model.visible = shown
	view.model.set_meta("source_detached_view", true)
	_pause(view.model)
	return view

static func _pause(node: Node) -> void:
	if node is AnimationPlayer:
		(node as AnimationPlayer).stop(true)
	for child: Node in node.get_children():
		_pause(child)

func begin(effects: CombatEffects) -> bool:
	var profile: Dictionary = Content.balance.destruction.sceneProfiles.get(kind, {})
	var flatten := not neutral and not profile.is_empty()
	var burst := flatten or (neutral and not collapsed)
	if burst and dimensions.is_empty():
		push_error("Removed body requires captured source dimensions")
		dispose()
		return false
	if flatten:
		if profile.get("mobile", false):
			mobile_damage.apply(model, kind, 3)
		else:
			scene_damage.apply(model, kind, id, dimensions, 3)
	if burst:
		effects.scene_damage_burst(id, kind, model.global_position, float(dimensions.height), float(dimensions.radius), 3)
	if flatten:
		if damage_fx.node != null:
			damage_fx.node.visible = false
		effects.retired_body(self, bool(profile.get("mobile", false)))
		return false
	if model.visible and float(Content.balance.destruction.dissolve.OUT_S) > 0 and dissolve.set_progress(model, 1.0, model.global_position) > 0:
		return true
	dispose()
	return false

func advance(delta: float) -> bool:
	age += delta
	var value := DissolveBinding.out_at(age)
	dissolve.set_progress(model, value, dissolve.origin)
	if value > 0:
		return true
	dispose()
	return false

func pose(fraction: float, initial_y: float, mobile: bool) -> void:
	var rules: Dictionary = Content.balance.destruction.removal
	var floor_scale := float(rules.mobileFloor if mobile else rules.staticFloor)
	model.scale.y = initial_y * (floor_scale + (1 - floor_scale) * (fraction if mobile else fraction * fraction))

func dispose() -> void:
	if not is_instance_valid(model):
		return
	dissolve.release()
	mobile_damage.release(true)
	damage_fx.clear()
	model.visible = false
	model.queue_free()
