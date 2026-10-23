class_name FirstPersonShield
extends Node3D

var source_root: Node3D
var material: ShaderMaterial
var character := ""
var visual_random := RandomNumberGenerator.new()

static func available() -> bool:
	if not Content.balance.has("firstPersonShields"):
		return false
	for key: String in Content.heroes:
		if not Content.balance.firstPersonShields.has(key) or not ResourceLoader.exists("res://assets/first_person_shields/%s.scn" % key):
			return false
	return true

func configure(pilot: String, phase: Callable = Callable()) -> bool:
	if source_root != null:
		push_error("First-person shield must be configured only once")
		return false
	visual_random.randomize()
	if not set_character(pilot):
		push_error("Missing original first-person shield scene: " + pilot)
		return false
	var sample := float(phase.call()) if phase.is_valid() else float(visual_random.randi()) / 4294967296.0
	material.set_shader_parameter("uTime", sample * float(Content.balance.bodyRules.shield.timeWindow))
	return true

func set_character(pilot: String) -> bool:
	if source_root != null and character == pilot:
		return true
	var profiles: Dictionary = Content.balance.get("firstPersonShields", {})
	var path := "res://assets/first_person_shields/%s.scn" % pilot
	if not profiles.has(pilot) or not ResourceLoader.exists(path):
		return false
	var root := (load(path) as PackedScene).instantiate() as Node3D
	var materials: Array = root.get_meta("source_materials")
	var next_material := materials[int(profiles[pilot].material)] as ShaderMaterial
	var curve := Content.local_view_curve()
	next_material.set_shader_parameter("curve_knee", curve.knee)
	next_material.set_shader_parameter("curve_inverse_radius", curve.inverse)
	if source_root != null:
		root.transform = source_root.transform
		root.visible = source_root.visible
		next_material.set_shader_parameter("uTime", material.get_shader_parameter("uTime"))
		next_material.set_shader_parameter("uFlash", material.get_shader_parameter("uFlash"))
		source_root.free()
	source_root = root
	material = next_material
	character = pilot
	add_child(source_root)
	return true

func hit(strength: float) -> void:
	if material != null:
		ShieldPresentation.hit(material, strength)

func advance(delta: float, now: float, view_mode: String, defending: bool, shield: float, dead: bool,
		expanded_until: float, cast: Variant = null, cast_duration: float = 0, expanded_override: Variant = null) -> void:
	if source_root == null:
		return
	var expanded := expanded_until > now
	if expanded_override is bool:
		expanded = expanded_override
	source_root.scale.x = float(Content.balance.bodyRules.shield.expand) if expanded else 1.0
	source_root.visible = view_mode == "fpv" and defending and shield > 0 and not dead
	ShieldPresentation.step(material, delta)
	if cast is Dictionary and cast.get("slot") == "def" and now >= float(cast.t0) and now - float(cast.t0) < cast_duration:
		source_root.visible = view_mode == "fpv" and not dead

func update_view(unit: BattleUnit, delta: float, now: float, view_mode: String, owned: Dictionary = {}) -> void:
	set_character(unit.character)
	if source_root == null:
		return
	var cast: Variant = unit.body_presentation.entity.get("castFx") if unit.body_presentation != null else null
	var duration := 0.0
	if unit.body != null:
		duration = float(unit.body.forms.get(unit.body.form, {}).get("combat", {}).get("clips", {}).get("def", {}).get("duration", 0))
	advance(delta, now, view_mode, bool(owned.get("defending", unit.defending)), unit.shield, not unit.alive(),
		float(unit.status.get("shield_expand_until", 0)), cast, duration, owned.get("expanded"))
