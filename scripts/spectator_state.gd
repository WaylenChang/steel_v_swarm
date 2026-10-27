class_name SpectatorState
extends RefCounted

signal notice(message: String)

var rules: Dictionary = {}
var mode := ""
var pid := ""
var position := Vector3.ZERO
var camera_position := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var fov := 0.0
var camera_fov := 0.0
var _anchor_position := Vector3.ZERO
var _anchor_x := 0.0
var _anchor_y := 0.0
var _anchor_z := 0.0
var anchor: Vector3:
	get:
		return _anchor_position
	set(value):
		_anchor_position = value
		_anchor_x = float(value.x)
		_anchor_y = float(value.y)
		_anchor_z = float(value.z)
var anchor_ok := false
var follow_yaw := 0.0
var hidden: Dictionary = {}

func configure(metadata: Dictionary, center: Vector3, ceiling: float, initial_fov: float) -> void:
	rules = metadata
	mode = str(rules.camera.VIEWS[0])
	pid = ""
	position = center + Vector3.UP * float(rules.startHeight)
	position.y = minf(position.y, ceiling)
	camera_position = Vector3.ZERO
	yaw = 0.0
	pitch = rules.startPitch
	fov = initial_fov
	camera_fov = initial_fov
	anchor = Vector3.ZERO
	anchor_ok = false
	follow_yaw = 0.0
	hidden = {}

static func source_pid(player: int) -> String:
	return "b" + str(-player) if player < 0 else str(player)

static func roster(actors: Array) -> Array:
	var result: Array = []
	for actor: Dictionary in actors:
		if actor.get("hero", false) and not str(actor.get("pid", "")).is_empty() and actor.get("act", true) != false:
			result.append(actor)
	# Native IDs use only decimal digits and the lowercase source bot prefix.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.pid) < str(b.pid) if a.side == b.side else str(a.side) < str(b.side))
	return result

func _nearest(list: Array) -> Dictionary:
	var nearest: Dictionary = list[0]
	var nearest_distance := _distance_squared(position, nearest.position)
	for index in range(1, list.size()):
		var actor: Dictionary = list[index]
		var distance := _distance_squared(position, actor.position)
		if not (nearest_distance <= distance):
			nearest = actor
			nearest_distance = distance
	return nearest

static func _distance_squared(first: Vector3, second: Vector3) -> float:
	# Three.js compares scalar doubles without rounding the squared distance to Vector3 precision.
	return _distance_squared_xyz(float(first.x), float(first.y), float(first.z), second)

static func _distance_squared_xyz(x: float, y: float, z: float, second: Vector3) -> float:
	var dx := x - float(second.x)
	var dy := y - float(second.y)
	var dz := z - float(second.z)
	return dx * dx + dy * dy + dz * dz

func target(actors: Array) -> Dictionary:
	for actor: Dictionary in roster(actors):
		if str(actor.pid) == pid:
			return actor
	return {}

func target_name(actor: Dictionary) -> String:
	var side := str(actor.get("side", ""))
	var character := str(actor.get("ch", ""))
	if rules.names.has(character + ":" + side):
		return str(rules.names[character + ":" + side])
	return str(actor.get("pid", rules.unknownName)) + str(rules.sideSuffix.get(side, ""))

func _announce(actor: Dictionary) -> void:
	if mode == "god":
		notice.emit(rules.ui.god)
	else:
		notice.emit(str(rules.ui.follow).replace("{view}", str(rules.camera.NAMES[mode])).replace("{name}", target_name(actor)))

func select_mode(value: String, actors: Array) -> void:
	var next := value if value in rules.camera.VIEWS else str(rules.camera.VIEWS[0])
	var none := false
	if next != "god" and pid.is_empty():
		var list := roster(actors)
		if list.is_empty():
			next = "god"
			none = true
		else:
			pid = str(_nearest(list).pid)
			anchor_ok = false
	var previous := mode
	mode = next
	if mode == "god":
		pid = ""
		anchor_ok = false
		if previous != "god":
			pitch = minf(pitch, rules.camera.ORBIT_PITCH)
	elif previous == "god" or previous == "fpv":
		pitch = 0.0 if mode == "fpv" else float(rules.camera.TPS_PITCH if mode == "tps" else rules.camera.ORBIT_PITCH)
	if none:
		notice.emit(rules.ui.noneMode)
	else:
		_announce(target(actors))

func cycle(actors: Array) -> void:
	var index: int = rules.camera.VIEWS.find(mode)
	select_mode(str(rules.camera.VIEWS[(0 if index < 0 else index + 1) % rules.camera.VIEWS.size()]), actors)

func follow(step: Variant, actors: Array) -> void:
	if step == null:
		select_mode("god", actors)
		return
	var list := roster(actors)
	if list.is_empty():
		notice.emit(rules.ui.noneFollow)
		return
	var actor: Dictionary
	if int(step) == 0 and pid.is_empty():
		actor = _nearest(list)
	else:
		var index := -1
		for i in list.size():
			if str(list[i].pid) == pid:
				index = i
				break
		actor = list[posmod(0 if index < 0 else index + int(step), list.size())]
	if pid != str(actor.pid):
		anchor_ok = false
	pid = str(actor.pid)
	if mode == "god":
		select_mode("fpv", actors)
	else:
		_announce(actor)

func zoom(wheel_delta: float) -> void:
	var factor: float = rules.camera.FOV_STEP if wheel_delta > 0 else 1.0 / float(rules.camera.FOV_STEP)
	fov = clampf(fov * factor, rules.camera.FOV_MIN, rules.camera.FOV_MAX)

# Same HUD contract as the source player panel. Unknown private clocks stay null.
func hud(actors: Array, side: String = "") -> Variant:
	if not side.is_empty():
		return null
	var actor := target(actors)
	var view_name: String = rules.camera.NAMES.get(mode, rules.camera.NAMES.god)
	if actor.is_empty():
		return {"spec": true, "follow": false, "who": rules.ui.hudFree.get(mode, rules.ui.hudFree.god), "hp": 0, "max": 1}
	var character := str(actor.get("ch", ""))
	var display: Dictionary = rules.display.get(character, {})
	var ab: Dictionary = actor.get("ab", {})
	var power: float = actor.get("mp", 0)
	var result := {"spec": true, "follow": true,
		"who": str(rules.ui.hudFollow["unknown" if display.is_empty() else "character"]).replace("{name}", target_name(actor)).replace("{machine}", str(display.get("machine", ""))).replace("{view}", view_name),
		"ch": character, "hp": actor.hp, "max": actor.max, "dead": actor.get("dead", false), "rs": actor.get("rs", 0),
		"upg": actor.get("up"), "money": actor.get("money", 0), "kn": actor.get("kn", 0), "atBase": false, "aiming": false,
		"sp": actor.get("sp", 0), "msp": actor.get("maxSp", 1) if actor.get("maxSp", 0) else 1,
		"mp": power, "mm": actor.get("mm", 1) if actor.get("mm", 0) else 1,
		"lift": null, "mobil": null, "morph": null, "emp": actor.get("emp", 0), "stealth": 0}
	if not display.is_empty():
		result.code = display.code
		result.machine = display.machine
	for slot: String in ["light", "heavy"]:
		var level: float = ab.get(slot, 1) if ab.get(slot, 0) else 1
		var weapon: Dictionary = Content.local_weapon(character, slot, level) if Content.heroes.has(character) else {}
		result[slot] = {"name": weapon.get("name", rules.unknownName), "lvl": level if not weapon.is_empty() else 0,
			"ammo": null, "mag": weapon.get("mag", 0), "reload": 0, "reloadMax": weapon.get("reload", 0)}
	for slot: String in ["def", "atk"]:
		var level: float = ab.get(slot, 1) if ab.get(slot, 0) else 1
		var ability: Dictionary = Content.local_ability(character, slot, level) if Content.heroes.has(character) else {}
		if ability.is_empty():
			result[slot] = {"name": rules.unknownName, "lvl": 0, "cd": 0, "cdMax": 0, "mp": 0, "ready": false}
			continue
		var index := 0 if slot == "def" else 1
		var cooldowns: Array = actor.get("cds", [])
		var cooldown: float = cooldowns[index] if cooldowns.size() > index else 0.0
		var cost := floorf(float(ability.mp) + 0.5)
		result[slot] = {"name": ability.name, "lvl": level, "cd": cooldown,
			"cdMax": ability.cd if ability.get("cd", 0) else rules.abilityFallbackCd, "mp": cost, "ready": cooldown <= 0 and power >= cost}
	return result

# Actors are presentation rows with interpolated positions, not authority units.
# Visibility commands retain the prior row until its FPV body has been restored.
func advance(delta: float, actors: Array, axis: Dictionary, rising: bool, descending: bool,
		surface: Callable, ceiling: float, pull: Callable) -> Array:
	var actor := target(actors)
	if not pid.is_empty() and actor.is_empty():
		select_mode("god", actors)
	var view := mode if not actor.is_empty() else "god"
	var hide: Dictionary = actor if view == "fpv" else {}
	var visibility: Array = []
	if not hidden.is_empty() and not is_same(hidden, hide):
		visibility.append({"actor": hidden, "visible": not hidden.get("dead", false)})
		hidden = {}
	var c: Dictionary = rules.camera
	if not actor.is_empty():
		var profile: Dictionary = rules.profiles.get(str(actor.get("ch", "")), rules.fallbacks.get(str(actor.side), rules.fallbacks[""]))
		var height: float = profile.height
		var point: Vector3 = actor.position
		if view in c.LOCK_VIEWS or not anchor_ok or sqrt(_distance_squared_xyz(_anchor_x, _anchor_y, _anchor_z, point)) > float(c.SNAP_M):
			anchor = point
			anchor_ok = true
		else:
			var weight := 1.0 - exp(-maxf(0.0, float(c.POS_K)) * maxf(0.0, delta))
			_anchor_x += (float(point.x) - _anchor_x) * weight
			_anchor_y += (float(point.y) - _anchor_y) * weight
			_anchor_z += (float(point.z) - _anchor_z) * weight
			_anchor_position = Vector3(_anchor_x, _anchor_y, _anchor_z)
		follow_yaw = CameraPose.angle_step(follow_yaw, actor.get("ry", follow_yaw), c.FPV_YAW_K if view == "fpv" else c.YAW_K, delta)
		position = anchor
		if view == "fpv":
			var eye: Dictionary = profile.air if float(actor.get("heroY", 0)) > float(c.FLY_M) else profile.ground
			yaw = follow_yaw
			if not actor.get("dead", false):
				visibility.append({"actor": actor, "visible": false})
			hidden = actor
			camera_position = anchor + Vector3(-sin(yaw) * height * float(eye.f), height * float(eye.e), -cos(yaw) * height * float(eye.f))
		else:
			if view == "tps":
				yaw = follow_yaw
			var distance := maxf(c.MIN_DIST, height * float(c.DIST_F))
			var aim := anchor + Vector3.UP * height * float(c.AIM_F)
			camera_position = aim + Vector3(sin(yaw) * distance * cos(pitch), -sin(pitch) * distance, cos(yaw) * distance * cos(pitch))
			camera_position = pull.call(aim, camera_position)
			var floor_height: float = float(surface.call(camera_position)) + float(c.FLOOR_M)
			if camera_position.y < floor_height:
				camera_position.y = floor_height
	else:
		var speed: float = float(c.MOVE_MPS) * (float(c.BOOST_F) if axis.boost else 1.0)
		var step: float = speed * delta / maxf(1.0, axis.mag)
		position += Vector3(-sin(yaw) * float(axis.f) + cos(yaw) * float(axis.r), 0, -cos(yaw) * float(axis.f) - sin(yaw) * float(axis.r)) * step
		if rising:
			position.y += speed * delta
		if descending:
			position.y -= speed * delta
		var floor_height: float = float(surface.call(position)) + float(c.FLOOR_M)
		if position.y < floor_height:
			position.y = floor_height
		if position.y > ceiling:
			position.y = maxf(floor_height, ceiling)
		camera_position = position
	if absf(camera_fov - fov) > float(rules.fovThreshold):
		camera_fov = fov
	return visibility
