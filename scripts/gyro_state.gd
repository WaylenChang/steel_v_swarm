class_name GyroState
extends RefCounted

signal look(change: Vector2)
signal failed(reason: String)

var rules: Dictionary
var active := false
var preference := "auto"
var path := ""
var sensitivity := 1.0
var invert := false
var have := false
var yaw := 0.0
var pitch := 0.0
var raw := Vector2.ZERO
var accumulated := Vector2.ZERO
var events := 0
var usable := 0
var started_at := 0.0
var note := ""

func _init(metadata: Dictionary) -> void:
	rules = metadata

func start(source: String, now: float) -> void:
	active = true
	preference = source
	note = ""
	_use("motion" if source == "motion" else "orient", now)

func _use(source: String, now: float) -> void:
	path = source
	started_at = now
	have = false
	events = 0
	usable = 0
	raw = Vector2.ZERO

func stop() -> void:
	active = false
	have = false

func reset_basis() -> void:
	have = false

static func motion_delta(rate: Vector3, delta: float, screen_angle: float, maximum: float) -> Vector2:
	var s := sin(screen_angle)
	var c := cos(screen_angle)
	return Vector2(rate.x * s + rate.y * c, rate.x * c - rate.y * s) * clampf(delta, 0, maximum)

# Both sensor vectors must use the same screen-relative frame. Zero/parallel
# readings cannot define a pose and must never become an identity quaternion.
static func sensor_forward(gravity: Vector3, magnetic: Vector3) -> Vector3:
	if not gravity.is_finite() or not magnetic.is_finite() or gravity.length_squared() < 0.000001:
		return Vector3.ZERO
	var up := -gravity.normalized()
	var north := magnetic - up * magnetic.dot(up)
	if north.length_squared() < 0.000001:
		return Vector3.ZERO
	north = north.normalized()
	var east := north.cross(up).normalized()
	return Vector3(-east.z, -up.z, north.z)

func orientation(forward: Vector3, now: float) -> void:
	if not active or path != "orient":
		return
	events += 1
	if not forward.is_finite() or forward.length_squared() < 0.000001:
		return
	usable += 1
	var direction := forward.normalized()
	var next_yaw := atan2(-direction.x, -direction.z)
	var next_pitch := asin(clampf(direction.y, -1, 1))
	if not have:
		have = true
		yaw = next_yaw
		pitch = next_pitch
		return
	var change := Vector2(wrapf(next_yaw - yaw, -PI, PI), next_pitch - pitch)
	yaw = next_yaw
	pitch = next_pitch
	if absf(change.x) > rules.GYRO_JUMP or absf(change.y) > rules.GYRO_JUMP:
		return
	_emit(change)
	if preference == "auto" and raw.y >= rules.GYRO_YAW_PROOF and raw.x < rules.GYRO_YAW_DEAD:
		note = "gyro_yaw_fallback"
		_use("motion", now)

func motion(rate: Vector3, delta: float, valid: bool = true, screen_angle: float = 0.0) -> void:
	if not active or path != "motion":
		return
	events += 1
	if not valid or not rate.is_finite():
		return
	usable += 1
	if not have:
		have = true
		return
	if delta <= 0:
		return
	var change := motion_delta(rate, delta, screen_angle, rules.GYRO_DT_MAX)
	if absf(change.x) <= rules.GYRO_JUMP and absf(change.y) <= rules.GYRO_JUMP:
		_emit(change)

func _emit(change: Vector2) -> void:
	raw += change.abs()
	var output := Vector2(0 if absf(change.x) < rules.GYRO_DEAD else change.x,
		0 if absf(change.y) < rules.GYRO_DEAD else change.y)
	output *= float(rules.GYRO_BASE) * sensitivity
	if invert:
		output.y = -output.y
	accumulated += output
	if output != Vector2.ZERO:
		look.emit(output)

func watchdog(now: float) -> void:
	if not active or usable > 0 or now - started_at < rules.GYRO_WD_MS:
		return
	if path == "orient" and preference == "auto":
		note = "gyro_data_fallback"
		_use("motion", now)
	else:
		active = false
		failed.emit("gyro_orientation_missing" if path == "orient" else "gyro_motion_missing")
