class_name BodyMaterials
extends RefCounted

static func standard(node: Node3D) -> BaseMaterial3D:
	var material: Material
	if node is MeshInstance3D:
		material = node.get_active_material(0)
	elif node is MultiMeshInstance3D:
		material = node.material_override if node.material_override != null else node.multimesh.mesh.surface_get_material(0)
	else:
		assert(false, "Source body material requires its original mesh node")
	assert(material is BaseMaterial3D, "Source body emission requires an imported standard material")
	return material as BaseMaterial3D

static func emission(material: BaseMaterial3D) -> float:
	return float(material.get_meta("source_emissive_intensity", material.emission_energy_multiplier))

static func set_emission(material: BaseMaterial3D, value: float) -> void:
	material.set_meta("source_emissive_intensity", value)
	material.emission_energy_multiplier = value

static func set_opacity(material: Material, value: float) -> void:
	material.set_meta("source_opacity", value)
	if material is BaseMaterial3D:
		var native := material as BaseMaterial3D
		var color := native.albedo_color
		color.a = value
		native.albedo_color = color
	else:
		assert(material is ShaderMaterial, "Unsupported source body opacity material")
