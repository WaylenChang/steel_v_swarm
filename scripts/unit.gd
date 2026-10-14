class_name BattleUnit
extends CharacterBody3D

var entity_id: int
var peer_id: int = 0
var side: String
var kind: String
var character: String = ""
var lane: int = 0
var has_lane := false
var spawn_slot: int = 0
var is_bot := false
var hp := 0.0
var max_hp := 0.0
var shield := 0.0
var max_shield := 0.0
var power := 0.0
var max_power := 0.0
var armor := 0.0
var money := 0.0
var score := 0.0
var deaths := 0
var radius := 1.0
var height := 2.0
var speed := 0.0
var flying := false
var yaw := 0.0
var pitch := 0.0
var input_state: Dictionary = {}
var upgrades: Dictionary = {"lw": 0, "hw": 0, "def": 0, "atk": 0, "hp": 0, "ar": 0, "sp": 0, "ch": 0}
var ammo: Dictionary = {}
var reload_at: Dictionary = {}
var fire_at: Dictionary = {}
var fire_serial := 0
var cooldowns: Dictionary = {}
var buffs: Array = []
var damaged_at := -100.0
var respawn_at := 0.0
var target_position := Vector3.ZERO
var target_yaw := 0.0
var model: Node3D
var camera: Camera3D
var cockpit: CockpitRig
var weapon_pose: AuthorityWeaponPose
var animation_player: AnimationPlayer
var path_follower: PathFollow3D
var reaction_at := 0.0
var bot_target := 0
var aim_anchor := 0
var lock_target := 0
var lock_at := -100.0
var lock_check_at := 0.0
var lock_keep_index := 0
var aim_off_at := -100.0
var gun_cooldowns: Array[float] = []
var animation_until := 0.0
var movement_shape: CollisionShape3D
var hit_area: Area3D
var presentation_visible := true
var view_offset := Vector3.ZERO
var view_offset_ready := false
var camera_cache_frame := -1
var camera_cache_signature: Array = []
var camera_cache_origin := Vector3.ZERO

func configure(info: Dictionary) -> void:
	entity_id = int(info.id)
	peer_id = int(info.get("peer", 0))
	side = info.side
	kind = info.kind
	character = info.get("character", "")
	lane = int(info.get("lane", 0))
	has_lane = info.has("lane")
	spawn_slot = int(info.get("spawn_slot", 0))
	is_bot = info.get("bot", false)
	var unit: Dictionary = Content.constants.UNITS[kind]
	if not character.is_empty():
		var hero: Dictionary = Content.heroes[character]
		radius = hero.radius
		height = hero.height
		armor = hero.armor
		speed = hero.speed
		max_hp = round(unit.hp * hero.mods.get("hp", 1))
		max_shield = round(unit.get("shield", 0) * hero.mods.get("sp", 1))
		max_power = round(unit.get("mp", 0) * hero.mods.get("mp", 1))
		money = Content.constants.ECON.START
	else:
		radius = Content.balance.unitVolumes[kind][side].radius
		height = Content.balance.unitVolumes[kind][side].height
		armor = unit.get("armor", 0)
		speed = unit.get("speed", 0)
		max_hp = unit.hp
	hp = max_hp
	shield = max_shield
	power = max_power
	flying = kind in ["drone", "heli"]
	position = info.position
	target_position = position
	collision_mask = 1 | 4
	movement_shape = CollisionShape3D.new()
	add_child(movement_shape)
	hit_area = Area3D.new()
	hit_area.collision_layer = 2
	hit_area.collision_mask = 0
	hit_area.monitoring = false
	var hit_shape := CollisionShape3D.new()
	var hit_cylinder := CylinderShape3D.new()
	hit_cylinder.radius = radius
	hit_cylinder.height = height
	hit_shape.shape = hit_cylinder
	hit_shape.position.y = height / 2
	hit_area.add_child(hit_shape)
	add_child(hit_area)
	refresh_collision()
	_build_model()
	if not character.is_empty():
		camera = Camera3D.new()
		camera.position = CameraPose.anchor(character, Vector3.ZERO, 0, flying)
		camera.fov = unit.get("fov", 68)
		camera.near = Content.balance.cameraRules.near
		camera.far = 3500
		add_child(camera)
		for slot in ["light", "heavy"]:
			ammo[slot] = Content.weapon(character, slot).mag

func _build_model() -> void:
	var file := "res://assets/models/reference/%s.glb" % character if not character.is_empty() else "res://assets/models/factions/%s_%s.glb" % [side.to_lower(), kind]
	if ResourceLoader.exists(file):
		var scene: PackedScene = load(file)
		model = scene.instantiate()
		add_child(model)
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		var bounds := AABB()
		var initialized := false
		for mesh in meshes:
			var box: AABB = (model.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			bounds = bounds.merge(box) if initialized else box
			initialized = true
		if initialized and bounds.size.y > 0:
			var factor := height / bounds.size.y
			model.scale = Vector3.ONE * factor
			model.position.y = -bounds.position.y * factor
		animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	else:
		model = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(radius * 2, height, radius * 2)
		model.mesh = mesh
		model.position.y = height / 2
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(Content.constants.SIDES[side].color)
		model.material_override = material
		add_child(model)

func is_hero() -> bool:
	return not character.is_empty()

func ensure_weapon_pose() -> void:
	if is_hero() and (weapon_pose == null or weapon_pose.character != character):
		weapon_pose = AuthorityWeaponPose.new()
		weapon_pose.configure(character)

func ensure_cockpit() -> void:
	if cockpit != null or camera == null:
		return
	cockpit = CockpitRig.new()
	camera.add_child(cockpit)
	cockpit.configure(character)

func alive() -> bool:
	return hp > 0

func eye() -> Vector3:
	return global_position + Vector3.UP * height * Content.constants.SELF_F.eye

func view_eye_height() -> float:
	return CameraPose.eye_height(character, flying) if is_hero() else height * Content.constants.SELF_F.eye

func view_origin() -> Vector3:
	if not is_hero():
		return eye()
	var parent := get_parent()
	if parent is BattleSimulation and parent.authoritative:
		return parent.camera_origin(self)
	return global_position + (Basis(Vector3.UP, rotation.y) * view_offset if view_offset_ready else CameraPose.anchor(character, Vector3.ZERO, rotation.y, flying))

func sync_view_camera() -> void:
	if camera != null:
		var parent := get_parent()
		if parent is BattleSimulation and parent.authoritative:
			camera.global_transform = aim_transform()
		else:
			camera.global_position = view_origin()
			camera.rotation = Vector3(pitch, 0, 0)

func visual_dimensions() -> Dictionary:
	var geometry: Dictionary = Content.balance.modelGeometry
	return geometry.heroes.get(character, {}) if is_hero() else geometry.units.get(kind, {}).get(side, {})

func aim_point() -> Vector3:
	var dimensions := visual_dimensions()
	if dimensions.is_empty():
		return Vector3(NAN, NAN, NAN)
	# Source acquisition uses the spawn-time measured centre even when the body rotates or morphs.
	return global_position + Vector3.UP * dimensions.centre

func sight_origin() -> Vector3:
	return global_position + Vector3.UP * (Content.constants.LOS.TOWER_EYE_M if kind == "tower" else Content.constants.LOS.EYE_M)

func sight_target() -> Vector3:
	return global_position + Vector3.UP * (Content.constants.LOS.TOWER_EYE_M if kind in ["base", "tower"] else Content.constants.LOS.TGT_M)

func sight_radius() -> float:
	var reach: float = Content.constants.UNITS[kind].get("sight", 0)
	return reach * Content.constants.GAME.AIM_SIGHT_MULT if is_hero() and input_state.get("aim", false) else reach

func refresh_collision() -> void:
	if movement_shape == null or hit_area == null:
		return
	collision_layer = 4 if alive() and (is_hero() or kind in Content.constants.COLLIDE_KINDS) else 0
	hit_area.collision_layer = 2 if alive() else 0
	var spec := {"r": radius, "bot": 0.0, "top": height}
	if is_hero():
		spec = Content.heroes[character].colliders["air" if flying else "ground"]
	var cylinder := CylinderShape3D.new()
	cylinder.radius = spec.r
	cylinder.height = spec.top - spec.bot
	movement_shape.shape = cylinder
	movement_shape.position.y = (spec.top + spec.bot) / 2

func aim_direction() -> Vector3:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD

func aim_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), view_origin())

func simulate_movement(delta: float) -> void:
	if not alive() or speed <= 0:
		return
	var motion: Vector2 = input_state.get("move", Vector2.ZERO)
	yaw = float(input_state.get("yaw", yaw))
	pitch = float(input_state.get("pitch", pitch))
	rotation.y = yaw
	if camera != null:
		camera.rotation.x = pitch
		var unit_stats: Dictionary = Content.constants.UNITS[kind]
		camera.fov = unit_stats.get("zoomFov", 35) if input_state.get("aim", false) else unit_stats.get("fov", 68)
	var move_basis := Basis(Vector3.UP, yaw)
	if flying and is_hero():
		move_basis *= Basis(Vector3.RIGHT, pitch)
	var direction := move_basis * Vector3(motion.x, 0, motion.y)
	var current_speed := speed
	if input_state.get("sprint", false):
		current_speed *= Content.balance.movement.sprint
	if is_hero() and flying:
		current_speed = Content.heroes[character].flySpeed
		if input_state.get("sprint", false):
			current_speed *= Content.balance.movement.sprint
	for buff in buffs:
		current_speed *= buff.get("mul", {}).get("speed", 1.0)
	# Bot and player commands share this movement path and the same collision solver.
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed
	if flying:
		var vertical_speed: float = Content.constants.UNITS[kind].get("vspeed", current_speed)
		velocity.y = direction.y * current_speed + float(input_state.get("vertical", 0)) * vertical_speed
	else:
		velocity.y -= Content.constants.AIR.GRAV * delta
		if input_state.get("jump", false) and is_on_floor():
			velocity.y = Content.constants.UNITS[kind].get("jump", 0)
		input_state["jump"] = false
	move_and_slide()
	if flying and position.y < 1:
		position.y = 1
	sync_view_camera()
	if animation_player != null and Time.get_ticks_msec() / 1000.0 > animation_until:
		var clip := "run" if motion.length() > 0.01 else "idle"
		if animation_player.has_animation(clip) and animation_player.current_animation != clip:
			animation_player.play(clip, 0.12)

func play_action(action: String) -> void:
	if animation_player != null and animation_player.has_animation(action):
		animation_player.play(action, 0.05)
		animation_until = Time.get_ticks_msec() / 1000.0 + animation_player.get_animation(action).length

func apply_snapshot(state: Dictionary, instant: bool = false) -> void:
	var previous_flight := flying
	var was_alive := alive()
	hp = state.hp
	max_hp = state.max_hp
	shield = state.shield
	max_shield = state.max_shield
	power = state.power
	money = state.money
	score = state.score
	deaths = state.deaths
	ammo = state.ammo
	upgrades = state.upgrades
	reload_at = state.reload_at
	cooldowns = state.cooldowns
	respawn_at = state.respawn_at
	flying = state.flying
	view_offset = state.get("view_offset", Vector3.ZERO)
	view_offset_ready = state.has("view_offset")
	if previous_flight != flying or was_alive != alive():
		refresh_collision()
	target_position = state.position
	target_yaw = state.yaw
	yaw = state.yaw
	pitch = state.pitch
	if instant:
		global_position = target_position
		rotation.y = target_yaw
	visible = alive()
	if camera != null:
		camera.rotation.x = pitch
		sync_view_camera()

func interpolate(delta: float) -> void:
	global_position = global_position.lerp(target_position, 1.0 - exp(-12.0 * delta))
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))
	sync_view_camera()

func snapshot() -> Dictionary:
	return {"id": entity_id, "peer": peer_id, "side": side, "kind": kind, "character": character,
		"lane": lane, "bot": is_bot, "position": global_position, "yaw": yaw, "pitch": pitch,
		"hp": hp, "max_hp": max_hp, "shield": shield, "max_shield": max_shield,
		"power": power, "money": money, "score": score, "deaths": deaths,
		"ammo": ammo.duplicate(), "upgrades": upgrades.duplicate(), "reload_at": reload_at.duplicate(),
		"cooldowns": cooldowns.duplicate(), "respawn_at": respawn_at, "flying": flying,
		"view_offset": Basis(Vector3.UP, -yaw) * (view_origin() - global_position) if is_hero() else Vector3.ZERO}
