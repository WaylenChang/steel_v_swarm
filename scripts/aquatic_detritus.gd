class_name AquaticDetritus
extends RefCounted

var particles: Array = []
var seeds: PackedFloat32Array
var positions: PackedFloat32Array
var mesh: ArrayMesh

static func create_node(source: Dictionary) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	for offset in range(0, source.positions.size(), 3):
		vertices.append(Vector3(source.positions[offset], source.positions[offset + 1], source.positions[offset + 2]))
		colours.append(Color(source.colours[offset], source.colours[offset + 1], source.colours[offset + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	var points := ArrayMesh.new()
	points.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/aquatic_points.gdshader")
	material.set_shader_parameter("source_size", float(source.material.size))
	material.set_shader_parameter("source_opacity", float(source.material.opacity))
	material.set_shader_parameter("source_colour", BodyPose.vector(source.material.colour))
	material.set_shader_parameter("source_vertex_colours", bool(source.material.vertexColors))
	material.set_shader_parameter("source_size_attenuation", bool(source.material.sizeAttenuation))
	material.set_shader_parameter("source_pixel_ratio", float(source.material.get("pixelRatio", 1)))
	points.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.name = "AquaticPoints_%d" % int(source.batches[0].id)
	node.mesh = points
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("source_aquatic_points", int(source.batches[0].id))
	return node

func configure(node: MeshInstance3D, source: Dictionary) -> bool:
	var original := node.mesh as ArrayMesh
	if original == null or original.get_surface_count() != 1 or original.surface_get_primitive_type(0) != Mesh.PRIMITIVE_POINTS:
		push_error("Missing original aquatic point primitive")
		return false
	mesh = original.duplicate() as ArrayMesh
	if mesh == null or mesh.surface_get_array_len(0) != source.particles.size():
		push_error("Invalid original aquatic point buffer")
		return false
	var stride := RenderingServer.mesh_surface_get_format_vertex_stride(mesh.surface_get_format(0), mesh.surface_get_array_len(0))
	if stride != 12:
		push_error("Original aquatic points require uncompressed native float32 vertex storage")
		return false
	node.mesh = mesh
	RenderingServer.instance_set_ignore_culling(node.get_instance(), true)
	particles = source.particles.duplicate(true)
	seeds = PackedFloat32Array(source.seeds)
	positions = PackedFloat32Array(source.positions)
	return true

func advance(delta: float, now: float) -> void:
	for index in range(particles.size()):
		var part: Dictionary = particles[index]
		if float(part.surfaceY) <= float(part.floorY):
			continue
		part.y = float(part.y) - float(part.spd) * delta * 0.5
		if float(part.y) < float(part.floorY):
			part.y = part.surfaceY
		positions[index * 3] = float(part.x) + sin(now * 0.4 + float(seeds[index])) * 0.12
		positions[index * 3 + 1] = part.y
		positions[index * 3 + 2] = float(part.z) + cos(now * 0.3 + float(seeds[index])) * 0.12
	# Position-only float32 storage; colours and saved scene buffers remain intact.
	mesh.surface_update_vertex_region(0, 0, positions.to_byte_array())
