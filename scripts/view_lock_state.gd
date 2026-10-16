class_name ViewLockState
extends RefCounted

signal cycled(index: int, count: int)

var hold := false
var cycle := false
var target := 0
var previous := 0
var last_seek := 0.0
var lit := false

func press(on: bool) -> void:
	hold = on
	if on:
		cycle = true
	else:
		target = 0

func clear_dead() -> void:
	target = 0
	previous = 0
	lit = false

func advance(delta: float, now: float, angles: Vector2, eye: Vector3, reach: float, disabled: bool,
		acquire: Callable, point_at: Callable) -> Vector2:
	if not hold or disabled:
		target = 0
		cycle = false
		lit = false
		return Vector2.ZERO
	if cycle:
		cycle = false
		last_seek = now
		var roster: Array = acquire.call(previous, true) if reach > 0 else []
		var prior := -1
		var chosen := -1
		for index: int in range(roster.size()):
			if int(roster[index].id) == previous:
				prior = index
			if chosen < 0 or float(roster[index].off) < float(roster[chosen].off):
				chosen = index
		if prior >= 0:
			chosen = (prior + 1) % roster.size()
		target = int(roster[chosen].id) if chosen >= 0 else 0
		previous = target
		cycled.emit(chosen + 1, roster.size())
	elif now - last_seek >= float(Content.balance.view.seekInterval):
		last_seek = now
		target = int(acquire.call(target, false)) if reach > 0 else 0
		if target != 0:
			previous = target
	var point: Vector3 = point_at.call(target) if target != 0 else Vector3(INF, INF, INF)
	if not point.is_finite():
		target = 0
		lit = false
		return Vector2.ZERO
	lit = true
	var offset := point - eye
	var flat := Vector2(offset.x, offset.z).length()
	if flat < float(Content.balance.view.flatMinimum):
		return Vector2.ZERO
	var difference := atan2(-offset.x, -offset.z) - angles.x
	difference = atan2(sin(difference), cos(difference))
	return Vector2(CombatMath.view_lock_step(difference, delta),
		CombatMath.view_lock_step(atan2(offset.y, flat) - angles.y, delta))
