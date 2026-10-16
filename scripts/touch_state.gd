class_name TouchState
extends RefCounted

signal command(action: String, on: bool)
signal look(change: Vector2)
signal haptic(milliseconds: int)

const NONE := -1
const HOLD := ["fire", "aim", "jump", "dive", "lock"]

var rules: Dictionary
var sensitivity := 1.0
var blocked := false
var axis := Vector2.ZERO
var move_stick := {"id": NONE, "vector": Vector2.ZERO, "centre": Vector2.ZERO, "radius": 1.0}
var look_stick := {"id": NONE, "vector": Vector2.ZERO, "centre": Vector2.ZERO, "radius": 1.0}
var look_id := NONE
var look_position := Vector2.ZERO
var down_position := Vector2.ZERO
var down_at := 0.0
var tap_position := Vector2.ZERO
var tap_at := 0.0
var fire_arm := false
var look_fire := false
var held: Dictionary = {}
var taps: Dictionary = {}

func _init(metadata: Dictionary) -> void:
	rules = metadata

static func stick_vector(point: Vector2, centre: Vector2, radius: float, dead: float) -> Vector2:
	var offset := point - centre
	var length := offset.length()
	var magnitude := minf(1, length / radius)
	magnitude = 0.0 if magnitude < dead else (magnitude - dead) / (1 - dead)
	if magnitude <= 0 or length < 0.001:
		return Vector2.ZERO
	return Vector2(offset.x, -offset.y) / length * magnitude

func owns(id: int) -> bool:
	return id == look_id or id == move_stick.id or id == look_stick.id or held.has(id) or taps.has(id)

func stick_down(movement: bool, id: int, point: Vector2, centre: Vector2, radius: float) -> void:
	var stick := move_stick if movement else look_stick
	if blocked or stick.id != NONE or owns(id) or radius <= 0:
		return
	stick.id = id
	stick.centre = centre
	stick.radius = radius
	_move_stick(stick, point, movement)

func _move_stick(stick: Dictionary, point: Vector2, movement: bool) -> void:
	stick.vector = stick_vector(point, stick.centre, stick.radius, rules.STICK_DEAD)
	if movement:
		axis = Vector2(stick.vector.x, -stick.vector.y)
		command.emit("sprint", stick.vector.length() >= rules.SPRINT_MAG)

func look_down(id: int, point: Vector2, now: float) -> void:
	if blocked or look_id != NONE or owns(id):
		return
	look_id = id
	fire_arm = tap_at > 0 and now - tap_at <= rules.TAP_GAP_MS and point.distance_to(tap_position) <= rules.TAP_SLOP_PX
	tap_at = 0
	down_at = now
	down_position = point
	look_position = point

func button_down(action: String, id: int, point: Vector2, now: float) -> void:
	if blocked or owns(id):
		return
	haptic.emit(6 if action == "fire" else 10)
	if action in HOLD:
		held[id] = action
		command.emit(action, true)
	else:
		taps[id] = {"action": action, "position": point, "at": now}

func move(id: int, point: Vector2) -> void:
	if id == look_id:
		var change := point - look_position
		look_position = point
		if not blocked:
			if fire_arm and not look_fire and point.distance_to(down_position) >= rules.TAP_FIRE_PX:
				_set_look_fire(true)
			look.emit(-change * float(rules.TOUCH_RAD_PX) * sensitivity)
	for movement: bool in [true, false]:
		var stick := move_stick if movement else look_stick
		if id == stick.id and not blocked:
			_move_stick(stick, point, movement)
	if taps.has(id) and point.distance_to(taps[id].position) > rules.TAP_SLOP_PX:
		taps.erase(id)

func up(id: int, point: Vector2, now: float, cancelled: bool = false) -> void:
	if id == look_id:
		look_id = NONE
		var tap := not look_fire and now - down_at <= rules.TAP_MS and point.distance_to(down_position) <= rules.TAP_SLOP_PX
		# The original look-pad cancellation uses its normal release handler.
		tap_at = now if tap and not fire_arm else 0.0
		tap_position = down_position
		fire_arm = false
		_set_look_fire(false)
	for movement: bool in [true, false]:
		var stick := move_stick if movement else look_stick
		if id == stick.id:
			stick.id = NONE
			stick.vector = Vector2.ZERO
			if movement:
				axis = Vector2.ZERO
				command.emit("sprint", false)
	if taps.has(id):
		var tap: Dictionary = taps[id]
		taps.erase(id)
		if not cancelled and not blocked and now - float(tap.at) <= rules.TAP_MS and point.distance_to(tap.position) <= rules.TAP_SLOP_PX:
			command.emit(tap.action, true)
	if held.has(id):
		var action: String = held[id]
		held.erase(id)
		if action != "fire" or not look_fire:
			command.emit(action, false)

func tick(delta: float, now: float) -> void:
	if look_fire and blocked:
		_set_look_fire(false)
	if fire_arm and not look_fire and look_id != NONE and now - down_at >= rules.TAP_FIRE_MS:
		_set_look_fire(true)
	for id: int in taps.keys():
		if now - float(taps[id].at) > rules.TAP_MS:
			taps.erase(id)
	var vector: Vector2 = look_stick.vector
	var magnitude := vector.length()
	if not blocked and magnitude > 0:
		var speed: float = rules.LOOK_RAD_S * sensitivity * pow(magnitude, rules.LOOK_CURVE) * delta
		look.emit(Vector2(-vector.x, vector.y) / magnitude * speed)

func _set_look_fire(on: bool) -> void:
	if look_fire == on or on and blocked:
		return
	look_fire = on
	if not on and "fire" in held.values():
		return
	command.emit("fire", on)
	if on:
		haptic.emit(6)

func set_blocked(on: bool) -> void:
	if blocked == on:
		return
	blocked = on
	if blocked:
		reset()

func reset() -> void:
	axis = Vector2.ZERO
	look_id = NONE
	_set_look_fire(false)
	fire_arm = false
	tap_at = 0
	for stick: Dictionary in [move_stick, look_stick]:
		stick.id = NONE
		stick.vector = Vector2.ZERO
	for action: String in held.values():
		command.emit(action, false)
	held.clear()
	taps.clear()
