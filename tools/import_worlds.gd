extends Node

const WorldData = preload("res://scripts/native_world_data.gd")
const TERRAIN_LAYER := 8
const STRUCTURE_LAYER := 16

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := "res://assets/worlds"
	DirAccess.make_dir_recursive_absolute(output)
	var directory := DirAccess.open("res://data/worlds")
	if directory == null:
		push_error("World source bundles are missing")
		get_tree().quit(1)
		return
	var selected: Array = Array(OS.get_cmdline_user_args())
	for file in directory.get_files():
		if not file.ends_with(".json") or (not selected.is_empty() and not selected.any(func(id): return file.begins_with(id + "_"))):
			continue
		var data: Dictionary = Content.read_json("res://data/worlds/" + file)
		var scene_root := Node3D.new()
		scene_root.name = "SourceWorld"
		for i in range(data.meshes.size()):
			var entry: Dictionary = data.meshes[i]
			var instance := MeshInstance3D.new()
			instance.name = "SourceMesh_%d" % i
			instance.mesh = _mesh(entry)
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = not entry.colors.is_empty()
			material.albedo_color = Color(entry.albedo[0], entry.albedo[1], entry.albedo[2], entry.opacity)
			material.roughness = 0.95
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			if entry.transparent:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			instance.material_override = material
			scene_root.add_child(instance)
			instance.owner = scene_root
			if entry.terrain:
				var body := StaticBody3D.new()
				body.name = "TerrainCollision"
				body.collision_layer = 1 | TERRAIN_LAYER
				instance.add_child(body)
				body.owner = scene_root
				var collision := CollisionShape3D.new()
				collision.shape = instance.mesh.create_trimesh_shape()
				collision.shape.backface_collision = true
				body.add_child(collision)
				collision.owner = scene_root
		var structure_body := StaticBody3D.new()
		structure_body.name = "StructureCollision"
		structure_body.collision_layer = 1 | STRUCTURE_LAYER
		scene_root.add_child(structure_body)
		structure_body.owner = scene_root
		for deck in data.decks:
			_ribbon(structure_body, scene_root, deck, deck.y1 - data.collision.deckThickness, deck.y2 - data.collision.deckThickness, deck.y1, deck.y2)
			# The source deck query has rectangular endpoint tolerance beyond its rendered mesh.
			for cap in _end_caps(deck, data.collision.deckEndTolerance):
				var height: float = deck.y1 if cap.start else deck.y2
				_ribbon(structure_body, scene_root, cap, height - data.collision.deckThickness, height - data.collision.deckThickness, height, height)
		var floors := Node3D.new()
		floors.name = "TunnelFloors"
		scene_root.add_child(floors)
		floors.owner = scene_root
		var roof_body := _body(scene_root, "TunnelRoofs", 64)
		var wall_body := _body(scene_root, "TunnelWalls", 128)
		var column_body := _body(scene_root, "StructureColumns", 256)
		for tunnel_index in range(data.tunnels.size()):
			var tunnel: Dictionary = data.tunnels[tunnel_index]
			var floor_body := StaticBody3D.new()
			floor_body.name = "Floor_%d" % tunnel_index
			floor_body.collision_layer = 1 | 32
			floors.add_child(floor_body)
			floor_body.owner = scene_root
			_floor(floor_body, scene_root, tunnel, tunnel.fy1, tunnel.fy2)
			if not tunnel.get("open", false):
				_ribbon(roof_body, scene_root, tunnel, tunnel.cy1, tunnel.cy2, tunnel.cy1 + data.collision.roofThickness, tunnel.cy2 + data.collision.roofThickness)
			for side in [-1, 1]:
				var bit := 1 if side == 1 else 2
				if (int(tunnel.get("gal", 0)) & bit) != 0:
					continue
				var wall: Dictionary = tunnel.duplicate()
				var direction := Vector2(tunnel.x2 - tunnel.x1, tunnel.z2 - tunnel.z1).normalized()
				var normal := Vector2(direction.y, -direction.x)
				wall.x1 += normal.x * side * tunnel.hw
				wall.z1 += normal.y * side * tunnel.hw
				wall.x2 += normal.x * side * tunnel.hw
				wall.z2 += normal.y * side * tunnel.hw
				_wall(wall_body, scene_root, wall, tunnel.fy1, tunnel.fy2, tunnel.get("by1", tunnel.cy1), tunnel.get("by2", tunnel.cy2))
		for column in data.columns:
			var collision := CollisionShape3D.new()
			collision.position = Vector3(column.x, column.y + column.h / 2, column.z)
			if column.has("hw2") and column.has("hd2"):
				var box := BoxShape3D.new()
				box.size = Vector3(column.hw2 * 2, column.h, column.hd2 * 2)
				collision.shape = box
				collision.rotation.y = column.get("ry", 0)
			else:
				var cylinder := CylinderShape3D.new()
				cylinder.radius = column.r
				cylinder.height = column.h
				collision.shape = cylinder
			column_body.add_child(collision)
			collision.owner = scene_root
		var resource := WorldData.new()
		resource.scene = PackedScene.new()
		if resource.scene.pack(scene_root) != OK:
			push_error("Cannot pack world: " + file)
			get_tree().quit(1)
			return
		resource.bounds = data.bounds
		resource.source = data.source
		resource.decks = data.decks
		resource.tunnels = data.tunnels
		resource.columns = data.columns
		resource.probes = data.probes
		resource.lane_heights = data.laneHeights
		resource.deck_probes = data.deckProbes
		resource.min_height = data.minH
		resource.max_height = data.maxH
		resource.average_height = data.avgH
		resource.ceiling = data.ceiling
		var target := output + "/" + file.get_basename() + ".res"
		var error := ResourceSaver.save(resource, target, ResourceSaver.FLAG_COMPRESS)
		scene_root.free()
		if error != OK:
			push_error(error_string(error))
			get_tree().quit(1)
			return
		print("WORLD_IMPORTED ", file.get_basename())
	get_tree().quit()

func _body(scene_root: Node3D, label: String, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1 | layer
	scene_root.add_child(body)
	body.owner = scene_root
	return body

func _end_caps(segment: Dictionary, tolerance: float) -> Array:
	var a := Vector2(segment.x1, segment.z1)
	var b := Vector2(segment.x2, segment.z2)
	if a == b or tolerance <= 0:
		return []
	var direction := (b - a).normalized()
	var start := a - direction * tolerance
	var finish := b + direction * tolerance
	return [
		{"x1": start.x, "z1": start.y, "x2": a.x, "z2": a.y, "hw": segment.hw, "start": true},
		{"x1": b.x, "z1": b.y, "x2": finish.x, "z2": finish.y, "hw": segment.hw, "start": false}]

func _mesh(entry: Dictionary) -> ArrayMesh:
	var positions := PackedVector3Array()
	for i in range(0, entry.positions.size(), 3):
		positions.append(Vector3(entry.positions[i], entry.positions[i + 1], entry.positions[i + 2]))
	var normals := PackedVector3Array()
	for i in range(0, entry.normals.size(), 3):
		normals.append(Vector3(entry.normals[i], entry.normals[i + 1], entry.normals[i + 2]))
	var colors := PackedColorArray()
	for i in range(0, entry.colors.size(), 3):
		colors.append(Color(entry.colors[i], entry.colors[i + 1], entry.colors[i + 2]))
	var indices := PackedInt32Array()
	# Godot's front-face winding is opposite Three.js; vertices and normals stay unchanged.
	for i in range(0, entry.index.size(), 3):
		indices.append_array(PackedInt32Array([int(entry.index[i]), int(entry.index[i + 2]), int(entry.index[i + 1])]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_INDEX] = indices
	if normals.size() == positions.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if colors.size() == positions.size():
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _ribbon(body: StaticBody3D, scene_root: Node3D, segment: Dictionary, bottom_a: float, bottom_b: float, top_a: float, top_b: float) -> void:
	var a := Vector3(segment.x1, 0, segment.z1)
	var b := Vector3(segment.x2, 0, segment.z2)
	if a == b or (top_a <= bottom_a and top_b <= bottom_b):
		return
	var right: Vector3 = (b - a).normalized().cross(Vector3.UP) * segment.hw
	var vertices := PackedVector3Array()
	for record in [[a, bottom_a, top_a], [b, bottom_b, top_b]]:
		for side in [-1, 1]:
			for y in [record[1], record[2]]:
				var point: Vector3 = record[0] + right * side
				point.y = y
				vertices.append(point)
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	shape.margin = 0.0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	collision.owner = scene_root

func _wall(body: StaticBody3D, scene_root: Node3D, segment: Dictionary, bottom_a: float, bottom_b: float, top_a: float, top_b: float) -> void:
	if top_a <= bottom_a and top_b <= bottom_b:
		return
	var a := Vector3(segment.x1, bottom_a, segment.z1)
	var b := Vector3(segment.x2, bottom_b, segment.z2)
	var c := Vector3(segment.x1, top_a, segment.z1)
	var d := Vector3(segment.x2, top_b, segment.z2)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(PackedVector3Array([a, b, c, c, b, d]))
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	collision.owner = scene_root

func _floor(body: StaticBody3D, scene_root: Node3D, segment: Dictionary, height_a: float, height_b: float) -> void:
	var a := Vector3(segment.x1, height_a, segment.z1)
	var b := Vector3(segment.x2, height_b, segment.z2)
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	if flat == Vector3.ZERO:
		return
	var right: Vector3 = flat.normalized().cross(Vector3.UP) * segment.hw
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(PackedVector3Array([a - right, a + right, b - right, a + right, b + right, b - right]))
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	collision.owner = scene_root

