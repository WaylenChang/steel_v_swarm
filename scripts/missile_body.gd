class_name MissileBody
extends StaticBody3D

static var meshes: Array[ArrayMesh] = []
static var shapes: Array[Shape3D] = []

func _ready() -> void:
	collision_layer = 512
	collision_mask = 0
	if meshes.is_empty():
		for part: Dictionary in Content.balance.missile.parts:
			var vertices := PackedVector3Array()
			for vertex: Array in part.vertices:
				vertices.append(Vector3(vertex[0], vertex[1], vertex[2]))
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(part.indices)
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.albedo_color = Color(part.color[0], part.color[1], part.color[2], part.opacity)
			if part.opacity < 1:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.surface_set_material(0, material)
			meshes.append(mesh)
			var shape := mesh.create_trimesh_shape()
			shape.backface_collision = true
			shapes.append(shape)
	for index in range(meshes.size()):
		var model := MeshInstance3D.new()
		model.mesh = meshes[index]
		# Authority collision remains independent of the interpolated source view.
		model.visible = false
		add_child(model)
		var collision := CollisionShape3D.new()
		collision.shape = shapes[index]
		add_child(collision)

func place(point: Vector3, direction: Vector3 = Vector3.ZERO) -> void:
	position = point
	if direction.length_squared() > 0.5:
		quaternion = Quaternion(Vector3.BACK, direction.normalized())
