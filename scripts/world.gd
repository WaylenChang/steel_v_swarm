class_name BattleWorld
extends Node3D

signal build_progress

var build_complete := false
var build_error := ""

var paths: Array[Path3D] = []
var lane_points: Array = []
var lane_distances: Array = []
var bases: Dictionary
var bounds: Dictionary
var native_data: Resource
var ceiling := 110.0
var hero_spawns: Dictionary
var arc_preview: MeshInstance3D
var arc_mesh: ImmediateMesh
var arc_material: StandardMaterial3D
var terrain_rids: Array[RID] = []
var missile_obstruction_rids: Array[RID] = []
var layers := StructureLayers.new()
var projectile_visuals: ProjectilePresentation
var missile_view_collision := Callable()
var skill_fields: SkillFieldPresentation
var weather_visuals: WeatherPresentation
var water_y: Variant = null
var water_meshes: Array[MeshInstance3D] = []
var authority_height_grid: Dictionary = {}
var fire_visuals: FirePresentation
var loot_visuals: LootPresentation
var mine_visuals: MinePresentation
var airdrop_visuals: AirdropPresentation
var active_columns: Array = []
var blocker_query := SourceBlockerQuery.new()
var active_roof_platforms: Array = []
var weather_obstacles: Array = []
var cleared_camps: Array[Dictionary] = []
var cleared_camp_keys: Dictionary = {}
var lane_surface := LaneSurfaceProfile.new()
var visual_frozen := false
var combat_effects: CombatEffects
var climb_index := ClimbIndex.new()
var climb_visuals := ClimbPresentation.new()
var scenery_view := SceneryPresentation.new()
var marine_view: MarinePresentation
var wildlife_view: WildlifePresentation
var petal_view: PetalPresentation
var aquatic_view: AquaticPresentation

func clear_camp_columns(camps: Array) -> void:
	if native_data == null:
		push_error("Camp clearance requires original native world content")
		return
	var changed := false
	for camp: Dictionary in camps:
		var key := "%d,%d" % [int(floorf(float(camp.x) + 0.5)), int(floorf(float(camp.z) + 0.5))]
		if not cleared_camp_keys.has(key):
			cleared_camp_keys[key] = true
			cleared_camps.append({"x": camp.x, "z": camp.z})
			changed = true
	if not changed:
		return
	var obstacles: Array = native_data.water_profile.get("obstacles", [])
	var clearance := CampRules.clearance(obstacles, cleared_camps)
	var buildings: Dictionary = CampRules.cleared_buildings(native_data.source_buildings, cleared_camps) if native_data.supports_captured else clearance.buildings
	scenery_view.clear_camps(cleared_camps, buildings)
	if native_data.climbs_captured:
		climb_index.configure(ClimbIndex.after_camp_clearance(native_data.climb_routes, cleared_camps, buildings))
	var removed := {}
	for index in range(native_data.columns.size()):
		var column: Dictionary = native_data.columns[index]
		if CampRules.removes_blocker(column, cleared_camps, buildings):
			removed[index] = true
	active_roof_platforms = native_data.roof_platforms.duplicate(true)
	for platform: Dictionary in active_roof_platforms:
		if buildings.has(platform.get("buildingKey", "")):
			platform.active = false
	for shape: CollisionShape3D in find_children("*", "CollisionShape3D", true, false):
		if shape.has_meta("source_column_index") and removed.has(int(shape.get_meta("source_column_index"))):
			shape.set_deferred("disabled", true)
		if shape.has_meta("source_roof_platform_index"):
			shape.set_deferred("disabled", active_roof_platforms[int(shape.get_meta("source_roof_platform_index"))].get("active", true) == false)
	active_columns = []
	for index in range(native_data.columns.size()):
		if not removed.has(index):
			active_columns.append(native_data.columns[index])
	layers.configure_supports(active_columns, active_roof_platforms)
	weather_obstacles = []
	for index in range(obstacles.size()):
		if index not in clearance.removed:
			weather_obstacles.append(obstacles[index])

func sync_airdrops(states: Array, now: float) -> void:
	if Session.dedicated or DisplayServer.get_name() == "headless":
		return
	if airdrop_visuals == null and states.is_empty():
		return
	if airdrop_visuals == null:
		airdrop_visuals = AirdropPresentation.new()
		airdrop_visuals.wall_clock = BodyPresentation.time_now
		add_child(airdrop_visuals)
	var poses: Array = []
	for state: Dictionary in states:
		var height := source_height(state.x, state.z)
		if not is_finite(height):
			push_error("Airdrop has no original terrain anchor")
			continue
		poses.append({"id": state.id, "position": Vector3(state.x, height, state.z), "size": state.size, "landing": state.landing})
	airdrop_visuals.sync(poses, now)

func sync_mines(states: Array) -> void:
	if Session.dedicated or DisplayServer.get_name() == "headless":
		return
	if mine_visuals == null and states.is_empty():
		return
	if mine_visuals == null:
		mine_visuals = MinePresentation.new()
		add_child(mine_visuals)
	var poses: Array = []
	for state: Dictionary in states:
		var surface := source_height(state.x, state.z)
		if not is_finite(surface):
			push_error("Mine has no source terrain anchor")
			continue
		poses.append({"id": state.id, "position": Vector3(state.x, surface + 0.05, state.z)})
	mine_visuals.sync(poses)

func update_mine_view(observer: Vector3, now: float) -> void:
	if mine_visuals != null:
		mine_visuals.update_view(observer, now)

func sync_loots(states: Array, now: float) -> void:
	if Session.dedicated or DisplayServer.get_name() == "headless":
		return
	if loot_visuals == null and states.is_empty():
		return
	if loot_visuals == null:
		loot_visuals = LootPresentation.new()
		loot_visuals.wall_clock = BodyPresentation.time_now
		add_child(loot_visuals)
	loot_visuals.sync(states, now)

func sync_fires(states: Array, now: float, dynamics: Dictionary) -> void:
	if Session.dedicated or DisplayServer.get_name() == "headless":
		return
	if fire_visuals == null and states.is_empty():
		return
	if fire_visuals == null:
		fire_visuals = FirePresentation.new()
		add_child(fire_visuals)
	fire_visuals.sync(states, now, dynamics)

func authority_height(x: float, z: float) -> Variant:
	return EnvironmentRules.authority_height(authority_height_grid, x, z)

func source_height(x: float, z: float) -> float:
	if native_data == null:
		return NAN
	return EnvironmentRules.height_at(native_data.terrain_heights, native_data.terrain_grid, bounds, x, z)

func water_code(x: float, z: float) -> int:
	if native_data == null or native_data.water_profile.is_empty():
		return 0
	var dry := EnvironmentRules.in_dry_band(x, z, native_data.water_profile.dryBands)
	var border := EnvironmentRules.in_border_band(x, z, native_data.water_profile.get("borderMask", {}))
	return EnvironmentRules.ground_code(source_height(x, z), water_y, [], dry, border)

func wet_at(x: float, z: float) -> int:
	return EnvironmentRules.wet_at(native_data.water_profile.wetGrid, x, z) if native_data != null and not native_data.water_profile.is_empty() else 0

func water_plane(x: float, z: float) -> Variant:
	var code := water_code(x, z)
	return float(water_y) + (float(Content.constants.WATER.SWAMP_BAND) if code == 2 else 0.0) if code > 0 and water_y != null else null

func sync_weather(dynamics: Dictionary, _surface: Dictionary, hour: float, schedule: Dictionary, season: String, seed_value: int = 0) -> void:
	if dynamics.is_empty():
		return
	visual_frozen = bool(dynamics.get("isFrozen", false))
	if native_data != null and native_data.water_profile.get("baseY") != null:
		var shift := EnvironmentRules.tide(hour, schedule.lunarDay, native_data.water_profile.isMarine)
		water_y = float(native_data.water_profile.baseY) + shift
		for mesh: MeshInstance3D in water_meshes:
			mesh.position.y = shift
	if weather_visuals == null:
		weather_visuals = WeatherPresentation.new()
		add_child(weather_visuals)
		weather_visuals.configure(seed_value)
	var span := maxf(float(bounds.maxX) - float(bounds.minX), float(bounds.maxZ) - float(bounds.minZ))
	weather_visuals.sync(dynamics, hour, schedule, season, span)

func present_lightning(points: Array) -> void:
	if weather_visuals != null:
		weather_visuals.strike(points)

func sync_fogs(states: Array, side: String, now: float) -> void:
	if skill_fields == null and states.is_empty():
		return
	if skill_fields == null:
		skill_fields = SkillFieldPresentation.new()
		add_child(skill_fields)
	skill_fields.sync_fogs(states, side, now)

func ensure_projectile_visuals() -> ProjectilePresentation:
	if not is_instance_valid(projectile_visuals) or projectile_visuals.retired or projectile_visuals.is_queued_for_deletion():
		if is_instance_valid(projectile_visuals):
			projectile_visuals.queue_free()
		projectile_visuals = ProjectilePresentation.new()
		add_child(projectile_visuals)
	projectile_visuals.missile_collision = missile_view_collision
	return projectile_visuals

func ensure_combat_effects() -> CombatEffects:
	if combat_effects == null:
		combat_effects = CombatEffects.new()
		combat_effects.low_power = Controls.low_power()
		add_child(combat_effects)
	return combat_effects

func clip_shot(origin: Vector3, target: Vector3) -> Dictionary:
	return NpcShotMotion.clip(origin, target, obstruction_hit)

func sync_projectile_view(states: Array, clock: float = NAN) -> void:
	if projectile_visuals == null and states.is_empty():
		return
	ensure_projectile_visuals().sync_rounds(states, clock)

func step_projectile_visuals(delta: float) -> void:
	if projectile_visuals != null:
		projectile_visuals.advance(delta, visual_collision, _visual_shell_impact)
	if combat_effects != null:
		combat_effects.advance(delta)

func _visual_shell_impact(point: Vector3, radius: float, color: int) -> void:
	ensure_combat_effects().spark(point, radius, color)

func visual_collision(start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	query.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func build(map_data: Dictionary, _environment: Dictionary) -> void:
	build_complete = false
	build_error = ""
	build_progress.emit()
	bounds = map_data.bounds
	hero_spawns = map_data.hero_spawns
	if map_data.has("native_world"):
		var path := WorldVariant.path(map_data.native_world, _environment)
		if path.is_empty() or not ResourceLoader.exists(path):
			_build_failed("Required seasonal native world resource is missing: " + str(path))
			return
		native_data = load(path) as NativeWorldData
		if native_data == null or native_data.scene == null:
			_build_failed("Native world resource has no valid terrain scene: " + path)
			return
		if not Session.dedicated and native_data.minimap_base == null:
			_build_failed("Missing original minimap terrain raster; regenerate native worlds")
			return
		if not WorldVariant.matches_identity(native_data.source.get("identity", {}), WorldVariant.identity(map_data.native_world, _environment)) or not native_data.slabs_captured:
			_build_failed("Native world season/identity or original accepted structure layers are missing; regenerate native worlds")
			return
		active_columns = native_data.columns.duplicate(true)
		active_roof_platforms = native_data.roof_platforms.duplicate(true)
		if native_data.supports_captured and (not native_data.structure_pads.get("tower") is Array or not native_data.structure_pads.get("base") is Array):
			_build_failed("Missing original tower/base platform anchors; regenerate native worlds")
			return
		weather_obstacles = native_data.water_profile.get("obstacles", []).duplicate(true)
		layers.configure(native_data.authority_slabs, native_data.decks, native_data.tunnels)
		layers.configure_supports(active_columns, active_roof_platforms)
		if native_data.bounds != bounds:
			_build_failed("Native world bounds do not match the selected map")
			return
		if native_data.terrain_grid < 2 or native_data.terrain_heights.size() != native_data.terrain_grid * native_data.terrain_grid or native_data.water_profile.is_empty():
			_build_failed("Required original terrain/water profile is missing; regenerate native worlds")
			return
		if native_data.water_profile.get("borderBands", false) and not EnvironmentRules.valid_border_mask(native_data.water_profile.get("borderMask")):
			_build_failed("Missing/invalid original border dry mask; regenerate native worlds")
			return
		water_y = native_data.water_profile.baseY
		var source_scene: Node3D = native_data.scene.instantiate()
		add_child(source_scene)
		build_progress.emit()
		if not scenery_view.configure(source_scene, native_data.source_trains if native_data.trains_captured else [],
				native_data.source_motions if native_data.motions_captured else []):
			_build_failed("Native scenery animation bindings are invalid")
			return
		if native_data.marine_captured:
			marine_view = MarinePresentation.new()
			if not marine_view.configure(native_data.source_marine, bounds, func(): return water_y, water_code):
				_build_failed("Original marine presentation metadata is invalid")
				return
			if not marine_view.bind_surfaces(source_scene, native_data.source_marine, native_data.marine_depth_field):
				_build_failed("Original marine surface bindings are invalid")
				return
		if native_data.wildlife_captured:
			wildlife_view = WildlifePresentation.new()
			var dry_band := func(x: float, z: float): return EnvironmentRules.in_dry_band(x, z, native_data.water_profile.dryBands)
			if not wildlife_view.configure(source_scene, native_data.source_wildlife, Controls.low_power(), source_height, water_code, dry_band,
					func(): return water_y, Visuals.snapshot(), SceneryPresentation.wildlife_activity):
				_build_failed("Original wildlife presentation bindings are invalid")
				return
		if native_data.petals_captured:
			petal_view = PetalPresentation.new()
			if not petal_view.configure(source_scene, native_data.source_petals, native_data.source.identity.season, Controls.low_power(), source_height, water_code):
				_build_failed("Original petal presentation bindings are invalid")
				return
		if native_data.aquatics_captured:
			aquatic_view = AquaticPresentation.new()
			if not aquatic_view.configure(source_scene, native_data.source_aquatics):
				_build_failed("Original aquatic presentation bindings are invalid")
				return
		if native_data.climbs_captured:
			climb_index.configure(native_data.climb_routes)
			if not climb_visuals.configure(source_scene, native_data.climb_routes):
				_build_failed("Original climbing presentation bindings are invalid")
				return
		for mesh: MeshInstance3D in source_scene.find_children("*", "MeshInstance3D", true, false):
			if mesh.get_meta("source_tide_water", false):
				water_meshes.append(mesh)
		if not SourceOutlineBinding.install(source_scene):
			_build_failed("Original world outline bindings are invalid")
			return
		authority_height_grid = EnvironmentRules.decode_height_grid(native_data.water_profile.get("heightGrid", {}))
		if authority_height_grid.is_empty() or not native_data.water_profile.has("obstacles"):
			_build_failed("Original weather height/obstacle profile is missing; regenerate native worlds")
			return
		ceiling = native_data.ceiling
		build_progress.emit()
		await get_tree().physics_frame
		if not is_inside_tree() or is_queued_for_deletion():
			return
		await get_tree().physics_frame
		if not is_inside_tree() or is_queued_for_deletion():
			return
	bases = {}
	for side in map_data.bases:
		var point: Array = map_data.bases[side]
		bases[side] = Vector3(point[0], structure_height("base", point[0], point[1]), point[1])
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
		lane_points.append(lane.duplicate(true))
		lane_distances.append(WaveRules.cumulative(lane))
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
	build_complete = true
	build_progress.emit()

func _build_failed(reason: String) -> void:
	build_error = reason
	push_error(reason)

func prepare_lane_surface() -> void:
	if native_data != null:
		lane_surface.configure(lane_points, source_height, visual_surface)

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
	point.y = (visual_flight_surface(point.x, point.z) if native_data != null else ground_height(point.x, point.z)) + (Content.constants.FLIGHT.HOVER_M if flying else 0.1)
	return point

func spawn_heading(side: String, slot: int) -> float:
	var direction: Array = hero_spawns[side][slot].direction
	return atan2(-direction[0], -direction[1])

func ground_height(x: float, z: float) -> float:
	return _height_at(x, z, 8)

func pad_height(kind: String, x: float, z: float) -> Variant:
	if native_data == null or not native_data.structure_pads.has(kind):
		return null
	var tolerance: float = Content.balance.structure.structurePadTolerance
	for pad: Dictionary in native_data.structure_pads[kind]:
		if absf(float(pad.x) - x) < tolerance and absf(float(pad.z) - z) < tolerance:
			return float(pad.y)
	return null

func structure_height(kind: String, x: float, z: float) -> float:
	var pad: Variant = pad_height(kind, x, z)
	return float(pad) if pad != null else ground_height(x, z)

func climb_query() -> Callable:
	return climb_index.at if native_data != null and native_data.climbs_captured else Callable()

func step_scenery(delta: float, weather: Dictionary) -> void:
	scenery_view.advance(delta, weather)
	if wildlife_view != null:
		wildlife_view.advance(delta, SceneryPresentation.wind_time, {"activity": WeatherRules.wildlife_activity(weather)})
	if petal_view != null:
		petal_view.advance(delta, weather)
	if aquatic_view != null:
		aquatic_view.advance(delta, SceneryPresentation.wind_time)
	if marine_view != null:
		marine_view.advance(delta, SceneryPresentation.wind_time, weather, scenery_view.motions)
		marine_view.sync_lighting(weather_visuals)
	if native_data != null and native_data.climbs_captured:
		climb_visuals.advance(delta)

func flight_reference(x: float, z: float) -> float:
	return _height_at(x, z, 8 | 16 | 32 | 64)

func visual_surface(point: Vector3) -> float:
	var ground := source_height(point.x, point.z)
	if not is_finite(ground):
		return NAN
	var surface := layers.projectile_surface(point, ground)
	var tunnel := layers.tunnel_at(Vector2(point.x, point.z))
	if not tunnel.is_empty() and point.y < float(tunnel.ceil):
		return surface
	return EnvironmentRules.ice_surface(surface, point.y, water_plane(point.x, point.z), visual_frozen)

func visual_flight_surface(x: float, z: float) -> float:
	var surface := source_height(x, z)
	if not is_finite(surface):
		return NAN
	return layers.projectile_surface(Vector3(x, INF, z), surface)

func visual_deck(x: float, z: float) -> Variant:
	return layers.deck_height(Vector2(x, z), float(Content.balance.structure.deckMargin))

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
	material.albedo_color = Color(Content.side_info(side).color)
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
	var color := Color(Content.side_info(control.side).color)
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

