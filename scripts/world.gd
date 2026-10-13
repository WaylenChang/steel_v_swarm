class_name BattleWorld
extends Node3D

var paths: Array[Path3D] = []
var bases: Dictionary
var bounds: Dictionary
var ambience: AudioStreamPlayer
var native_data: Resource
var ceiling := 110.0
var hero_spawns: Dictionary
var arc_preview: MeshInstance3D
var arc_mesh: ImmediateMesh
var arc_material: StandardMaterial3D
var terrain_rids: Array[RID] = []
var missile_obstruction_rids: Array[RID] = []
var layers := StructureLayers.new()

func build(map_data: Dictionary, environment: Dictionary) -> void:
	bounds = map_data.bounds
	hero_spawns = map_data.hero_spawns
	if map_data.has("native_world"):
		if not ResourceLoader.exists(map_data.native_world):
			push_error("Required native world resource is missing: " + str(map_data.native_world))
			get_tree().quit(1)
			return
		native_data = load(map_data.native_world)
		var key: String = map_data.native_world.get_file().get_basename()
		if not Content.structures.has(key):
			push_error("Required source structure profile is missing: " + key)
			get_tree().quit(1)
			return
		layers.configure(Content.structures[key], native_data.decks, native_data.tunnels)
		if native_data.bounds != bounds:
			push_error("Native world bounds do not match the selected map")
			get_tree().quit(1)
			return
		add_child(native_data.scene.instantiate())
		ceiling = native_data.ceiling
		await get_tree().physics_frame
		await get_tree().physics_frame
	bases = {}
	for side in map_data.bases:
		var point: Array = map_data.bases[side]
		bases[side] = Vector3(point[0], ground_height(point[0], point[1]), point[1])
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("253c36")
	floor_material.roughness = 0.95
	var size := Vector3(bounds.maxX - bounds.minX, 2, bounds.maxZ - bounds.minZ)
	var center := Vector3((bounds.minX + bounds.maxX) / 2, -1, (bounds.minZ + bounds.maxZ) / 2)
	if native_data == null:
		var floor_body := _box(size, center, floor_material, true)
		floor_body.collision_layer = 1 | 8
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color("27383e")
	var wall_bottom: float = native_data.min_height - 20 if native_data != null else 0.0
	var wall_height: float = ceiling - wall_bottom + Content.constants.TARGET_H.tower
	for x in [bounds.minX, bounds.maxX]:
		_box(Vector3(4, wall_height, size.z + 4), Vector3(x, wall_bottom + wall_height / 2, center.z), wall_material, true)
	for z in [bounds.minZ, bounds.maxZ]:
		_box(Vector3(size.x + 4, wall_height, 4), Vector3(center.x, wall_bottom + wall_height / 2, z), wall_material, true)
	for lane_index in range(map_data.lanes.size()):
		var lane: Array = map_data.lanes[lane_index]
		var path := Path3D.new()
		path.curve = Curve3D.new()
		path.curve.bake_interval = 2.0
		for point_index in range(lane.size()):
			var point: Array = lane[point_index]
			var height: float = native_data.lane_heights[lane_index][point_index] if native_data != null else 0.0
			path.curve.add_point(Vector3(point[0], height, point[1]))
		paths.append(path)
		add_child(path)
		if native_data == null:
			_build_road(lane)
	var environment_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("16314b")
	sky_material.sky_horizon_color = Color("9caeab")
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b3c4d6")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = environment.get("weather", "clear") == "fog"
	env.fog_density = 0.004 if env.fog_enabled else 0.0
	if environment.get("time", "day") == "night":
		env.ambient_light_energy = 0.2
		sky_material.sky_top_color = Color("050c1c")
		sky_material.sky_horizon_color = Color("1d3240")
	environment_node.environment = env
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.4 if environment.get("time", "day") == "day" else 0.4
	sun.shadow_enabled = true
	add_child(sun)
	if not Session.dedicated and DisplayServer.get_name() != "headless" and ResourceLoader.exists("res://assets/audio/amb/base.ogg"):
		ambience = AudioStreamPlayer.new()
		ambience.stream = load("res://assets/audio/amb/base.ogg")
		ambience.volume_db = -24
		add_child(ambience)
		ambience.play()

func _exit_tree() -> void:
	if ambience != null:
		ambience.stop()
		ambience.stream = null

func _build_road(points: Array) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := 7.0
	for i in range(points.size() - 1):
		var a := Vector3(points[i][0], 0.035, points[i][1])
		var b := Vector3(points[i + 1][0], 0.035, points[i + 1][1])
		var right := (b - a).normalized().cross(Vector3.UP) * width
		for vertex in [a - right, a + right, b - right, b - right, a + right, b + right]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("41494c")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	add_child(instance)

func _box(size: Vector3, center: Vector3, material: Material, solid: bool) -> StaticBody3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = center
	add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.position = center
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		return body
	return null

func obstruction_hit(start: Vector3, end: Vector3, include_slabs: bool = true) -> Dictionary:
	var excluded: Array[RID] = terrain_rids if include_slabs else missile_obstruction_rids
	if excluded.is_empty():
		for body in find_children("*", "StaticBody3D", true, false):
			if int(body.collision_layer) & (8 if include_slabs else 8 | 16 | 32 | 64):
				excluded.append(body.get_rid())
	var query := PhysicsRayQueryParameters3D.create(start, end, 1, excluded)
	query.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func spawn_position(side: String, slot: int = 0, flying: bool = false) -> Vector3:
	var source_position: Array = hero_spawns[side][slot].position
	var point := Vector3(source_position[0], 0, source_position[1])
	point.y = ground_height(point.x, point.z) + (Content.constants.FLIGHT.HOVER_M if flying else 0.1)
	return point

func spawn_heading(side: String, slot: int) -> float:
	var direction: Array = hero_spawns[side][slot].direction
	return atan2(-direction[0], -direction[1])

func ground_height(x: float, z: float) -> float:
	return _height_at(x, z, 8)

func flight_reference(x: float, z: float) -> float:
	return _height_at(x, z, 8 | 16 | 32 | 64)

func _height_at(x: float, z: float, mask: int) -> float:
	if native_data == null:
		return 0.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(x, ceiling + 100, z), Vector3(x, native_data.min_height - 100, z), mask))
	return hit.position.y if not hit.is_empty() else NAN

func tracer(start: Vector3, end: Vector3, side: String) -> void:
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.055
	cylinder.bottom_radius = 0.055
	cylinder.height = maxf(0.01, start.distance_to(end))
	beam.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(Content.constants.SIDES[side].color)
	beam.material_override = material
	add_child(beam)
	beam.global_position = (start + end) / 2
	if start.distance_squared_to(end) > 0.001:
		beam.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	var tween := create_tween()
	tween.tween_interval(0.08)
	tween.tween_callback(beam.queue_free)

func aim_arc(control: Dictionary) -> void:
	if arc_preview == null and control.is_empty():
		return
	if arc_preview == null:
		arc_preview = MeshInstance3D.new()
		arc_mesh = ImmediateMesh.new()
		arc_material = StandardMaterial3D.new()
		arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		arc_preview.mesh = arc_mesh
		arc_preview.material_override = arc_material
		arc_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arc_preview)
	arc_preview.visible = not control.is_empty()
	if control.is_empty():
		return
	var colors: Dictionary = Content.balance.projectilePreview.colors
	var color := Color(Content.constants.SIDES[control.side].color)
	for key in ["close", "blocked", "aa", "high"]:
		if (not control.ok if key == "blocked" else control.get(key, false)):
			color = Color.hex((int(colors[key]) << 8) | 0xff)
			break
	arc_material.albedo_color = color
	arc_mesh.clear_surfaces()
	var points: PackedVector3Array = control.points
	if points.size() < 2:
		return
	arc_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(0, points.size() - 1, 2):
		arc_mesh.surface_add_vertex(points[index])
		arc_mesh.surface_add_vertex(points[index + 1])
	arc_mesh.surface_end()

