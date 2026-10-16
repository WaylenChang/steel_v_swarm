class_name DissolveBinding
extends RefCounted

const SURFACE = """
uniform float source_progress = 1.0;
uniform vec3 source_origin = vec3(0.0);
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform bool vertex_colour = false;
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float alpha_test = 0.0;
uniform float curve_knee = 0.0;
uniform float curve_inverse = 0.0;
varying vec3 source_point;
void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	source_point = world.xyz - source_origin;
	float d = max(0.0, length(world.xz - CAMERA_POSITION_WORLD.xz) - curve_knee);
	world.y -= d * d * curve_inverse;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}
void fragment() {
	if (celDissolve(source_point, source_progress)) { discard; }
	vec4 colour = albedo * (use_texture ? texture(albedo_texture, UV) : vec4(1.0));
	if (vertex_colour) { colour *= COLOR; }
	if (colour.a < alpha_test) { discard; }
	ALBEDO = colour.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = emission.rgb * emission_energy;
#ifdef SOURCE_ALPHA
	ALPHA = colour.a;
#endif
}
"""

static var shaders: Dictionary = {}
var materials: Dictionary = {}
var bindings: Array[Dictionary] = []
var outlines: Array[Node3D] = []
var count := 0
var progress := 1.0
var origin := Vector3.ZERO
var collected := false

static func available() -> bool:
	return Content.balance.get("destruction", {}).get("dissolve", {}).has("shaderFunctions")

static func out_at(time: float) -> float:
	var duration := float(Content.balance.destruction.dissolve.OUT_S)
	var t := clampf(time / duration, 0, 1) if duration > 0 else 1.0
	return 1 - t * t * (3 - 2 * t)

func set_progress(root: Node3D, value: float, anchor: Variant = null) -> int:
	if not collected:
		_collect(root)
		collected = true
	progress = clampf(value, 0, 1)
	if anchor is Vector3:
		origin = anchor
	for material: ShaderMaterial in materials.values():
		material.set_shader_parameter("source_progress", progress)
		material.set_shader_parameter("source_origin", origin)
	for node: Node3D in outlines:
		if is_instance_valid(node):
			node.visible = progress >= 1
	return count

func _collect(node: Node3D) -> void:
	var geometry := ViewOcclusion._geometry(node)
	if geometry != null:
		if node.get_meta("isOutline", false):
			outlines.append(node)
		else:
			var target := node as GeometryInstance3D
			var slots: Array = node.get_meta("source_dissolve_slots", [])
			for enabled: bool in slots:
				if enabled:
					count += 1
			var originals: Array[Material] = []
			var replacements: Array[Material] = []
			for surface in range(geometry.get_surface_count()):
				var active := ViewOcclusion._material(target, surface)
				originals.append(target.get_surface_override_material(surface) if target is MeshInstance3D else geometry.surface_get_material(surface))
				replacements.append(_material(active))
				if slots.is_empty() and active != null and active.get_meta("source_dissolve", false):
					count += 1
			var binding := {"node": target, "override": target.material_override, "originals": originals, "mesh": geometry, "replacements": replacements}
			bindings.append(binding)
			if target.material_override != null:
				target.material_override = _material(target.material_override)
			elif target is MeshInstance3D:
				for surface in range(replacements.size()):
					target.set_surface_override_material(surface, replacements[surface])
			else:
				var batch := target as MultiMeshInstance3D
				var instances := batch.multimesh.duplicate() as MultiMesh
				instances.mesh = geometry.duplicate() as Mesh
				for surface in range(replacements.size()):
					instances.mesh.surface_set_material(surface, replacements[surface])
				binding.private_mesh = instances.mesh
				batch.multimesh = instances
	for child: Node in node.get_children():
		if child is Node3D:
			_collect(child)

func _material(original: Material) -> Material:
	if original == null or not original.get_meta("source_dissolve", false):
		return original
	if materials.has(original):
		return materials[original]
	if not original is BaseMaterial3D:
		push_error("Dissolve requires a captured native body surface")
		return original
	var source := original as BaseMaterial3D
	var material := ShaderMaterial.new()
	material.shader = _shader(source)
	for property: StringName in original.get_meta_list():
		material.set_meta(property, original.get_meta(property))
	material.set_shader_parameter("albedo", source.albedo_color)
	material.set_shader_parameter("albedo_texture", source.albedo_texture)
	material.set_shader_parameter("use_texture", source.albedo_texture != null)
	material.set_shader_parameter("vertex_colour", source.vertex_color_use_as_albedo)
	material.set_shader_parameter("roughness", source.roughness)
	material.set_shader_parameter("metallic", source.metallic)
	material.set_shader_parameter("emission", source.emission if source.emission_enabled else Color.BLACK)
	material.set_shader_parameter("emission_energy", source.emission_energy_multiplier if source.emission_enabled else 0.0)
	material.set_shader_parameter("alpha_test", float(source.get_meta("source_alpha_test", 0)))
	var curve: Dictionary = Content.balance.bodyRules.curve
	material.set_shader_parameter("curve_knee", curve.knee)
	material.set_shader_parameter("curve_inverse", curve.inverse)
	materials[original] = material
	return material

static func _shader(source: BaseMaterial3D) -> Shader:
	var modes: Array[String] = ["cull_disabled" if source.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_front" if source.cull_mode == BaseMaterial3D.CULL_FRONT else "cull_back"]
	modes.append("depth_draw_never" if source.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED else "depth_draw_always" if source.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS else "depth_draw_opaque")
	modes.append("blend_add" if source.blend_mode == BaseMaterial3D.BLEND_MODE_ADD else "blend_mix")
	if source.no_depth_test:
		modes.append("depth_test_disabled")
	if source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		modes.append("unshaded")
	var key := ",".join(modes) + ("/alpha" if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else "")
	if not shaders.has(key):
		var shader := Shader.new()
		shader.code = "shader_type spatial;\nrender_mode " + ",".join(modes) + ";\n" \
			+ ("#define SOURCE_ALPHA\n" if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else "") \
			+ str(Content.balance.destruction.dissolve.shaderFunctions) + "\n" + SURFACE
		shaders[key] = shader
	return shaders[key]

func release() -> void:
	for binding: Dictionary in bindings:
		if not is_instance_valid(binding.node):
			continue
		var node: GeometryInstance3D = binding.node
		if node.material_override != null and materials.values().has(node.material_override):
			node.material_override = binding.override
		elif node is MeshInstance3D:
			for surface in range(mini(binding.originals.size(), node.mesh.get_surface_count())):
				if node.get_surface_override_material(surface) == binding.replacements[surface]:
					node.set_surface_override_material(surface, binding.originals[surface])
		elif node is MultiMeshInstance3D:
			var mesh: Mesh = node.multimesh.mesh
			var owned: bool = mesh == binding.get("private_mesh")
			for surface in range(mini(binding.originals.size(), mesh.get_surface_count())):
				var replaced: bool = mesh.surface_get_material(surface) == binding.replacements[surface]
				owned = owned and replaced
				if replaced:
					mesh.surface_set_material(surface, binding.originals[surface])
			if owned:
				node.multimesh.mesh = binding.mesh
	for outline: Node3D in outlines:
		if is_instance_valid(outline):
			outline.visible = true
	materials.clear()
	bindings.clear()
	outlines.clear()
	count = 0
	collected = false
