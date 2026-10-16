class_name MissilePresentation
extends Node3D

var missile_id := 0
var model: ProjectileVisual
var dimensions: Dictionary = {}
var target := Vector3.ZERO
var previous := Vector3.ZERO
var age := 0.0
var smoke := 0.0
var mobile_damage := MobileDamageGeometry.new()
var damage_fx := DamageFxBinding.new()
var ray := MissileViewRay.new()

static func available() -> bool:
	return Content.balance.get("missile", {}).get("presentation", {}).has("rayParts") and Content.balance.get("projectileVisual", {}).get("profiles", {}).has("sam-source") \
		and ResourceLoader.exists("res://assets/projectiles/sam-source.scn") and ResourceLoader.exists("res://assets/npc_effects/missile_smoke.scn")

func configure(id: int, point: Vector3) -> bool:
	if not available() or model != null or not point.is_finite():
		push_error("Missile presentation requires its original projectile scene and source terrain height")
		return false
	missile_id = id
	var rules: Dictionary = Content.balance.missile.presentation
	dimensions = rules.dimensions
	ray.configure(rules.rayParts)
	scale = Vector3.ONE * float(rules.scale)
	position = point
	target = point
	previous = Vector3.ZERO
	model = ProjectileVisual.new()
	add_child(model)
	model.configure("sam-source")
	return true

func observe(state: Dictionary, point: Vector3, effects: CombatEffects) -> void:
	if not point.is_finite():
		push_error("Missile presentation requires a finite source terrain point")
		return
	var health := float(state.get("hp", NAN))
	var maximum := float(state.get("max_hp", 0))
	if is_finite(health) and maximum > 0:
		var destination := SceneDamageGeometry.health_stage(health, maximum)
		if mobile_damage.stage >= 0 and destination > mobile_damage.stage:
			effects.scene_damage_burst(missile_id, "missile", position, float(dimensions.height), float(dimensions.radius), destination)
		mobile_damage.apply(self, "missile", destination)
		damage_fx.set_stage(DamageFx.observed_stage("missile", health, maximum, {}), self, "missile", dimensions, effects._sample_random)
	previous = target
	target = point

func advance(delta: float, effects: CombatEffects) -> void:
	if not is_finite(delta) or delta < 0:
		return
	age += delta
	position = position.lerp(target, 1 - exp(-10 * delta))
	var direction := target - previous
	if direction.length_squared() > .5:
		quaternion = SourceQuaternion.from_unit_vectors(Vector3.BACK, SourceQuaternion.vector_normalized(direction))
	model.step_fx(age, 260)
	smoke += delta
	if smoke > .06:
		smoke = 0
		effects.missile_smoke(position)

func release(effects: CombatEffects, burst: bool) -> void:
	if burst:
		effects.scene_damage_burst(missile_id, "missile", position, float(dimensions.height), float(dimensions.radius), 3)
	damage_fx.clear()
	mobile_damage.release(true)
	visible = false
