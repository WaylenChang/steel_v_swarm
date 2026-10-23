class_name ClimbState
extends RefCounted

var route: Dictionary = {}
var off_until := 0.0
var entered := false
var entered_kind := ""

func release() -> void:
	route = {}
	entered = false
	entered_kind = ""

func advance(delta: float, now: float, state: Dictionary, input: Dictionary, nearest: Callable) -> bool:
	entered = false
	entered_kind = ""
	if not nearest.is_valid() or input.flying or input.dead:
		release()
		return false
	var rules: Dictionary = Content.balance.movement.climb
	var constants: Dictionary = rules.constants
	if not route.is_empty():
		var dx := float(state.x) - float(route.x)
		var dz := float(state.z) - float(route.z)
		if sqrt(dx * dx + dz * dz) > float(constants.GRAB_R) * float(rules.breakRadius) \
				or float(state.y) < float(route.y0) - float(rules.breakBelow) or float(state.y) > float(route.y1) + float(rules.breakAbove):
			release()
	if route.is_empty():
		if now < off_until:
			return false
		var candidate: Dictionary = nearest.call(state.x, state.z, state.y)
		if candidate.is_empty():
			return false
		var gx := float(candidate.x) - float(state.x)
		var gz := float(candidate.z) - float(state.z)
		var distance := sqrt(gx * gx + gz * gz)
		var intent := (float(input.move_x) * gx + float(input.move_z) * gz) / distance if distance > float(rules.intentRadius) else float(input.forward)
		if intent <= float(rules.intentThreshold):
			return false
		route = candidate
		state.charge = 0.0
		state.vertical = 0.0
		state.low_gravity = false
		entered = true
		entered_kind = str(route.kind)
	if input.jump:
		state.impulse_x = float(state.impulse_x) + float(route.nx) * float(constants.KICK)
		state.impulse_z = float(state.impulse_z) + float(route.nz) * float(constants.KICK)
		var jump: float = float(input.jump_speed) if input.jump_speed else float(rules.defaultJump)
		state.vertical = jump * float(rules.kickHeight)
		route = {}
		off_until = now + float(rules.kickOff)
		return false
	state.y = float(state.y) + float(input.forward) * float(constants.SPD) * float(input.cc) * float(input.speed) * delta
	var gain := 1 - exp(-float(rules.stickResponse) * maxf(0, delta))
	state.x = float(state.x) + (float(route.x) - float(state.x)) * gain
	state.z = float(state.z) + (float(route.z) - float(state.z)) * gain
	var friction := exp(-float(rules.friction) * maxf(0, delta))
	state.impulse_x = float(state.impulse_x) * friction
	state.impulse_z = float(state.impulse_z) * friction
	state.vertical = 0.0
	if float(state.y) >= float(route.y1):
		state.x = float(route.tx)
		state.y = float(route.y1)
		state.z = float(route.tz)
		route = {}
		off_until = now + float(rules.topOff)
		return false
	if float(state.y) <= float(route.y0):
		state.x = float(route.bx)
		state.y = float(route.y0)
		state.z = float(route.bz)
		route = {}
		off_until = now + float(rules.bottomOff)
		return false
	state.roll = float(state.roll) * exp(-float(rules.rollResponse) * maxf(0, delta))
	return true
