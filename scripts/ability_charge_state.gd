class_name AbilityChargeState
extends RefCounted

# Publication and HUD queries must not prune or otherwise mutate authority queues.
static func inspect(maximum: int, cooldown: float, charge: Dictionary, now: float, allocated: bool) -> Dictionary:
	maximum = maxi(1, maximum)
	var deadlines: Array = charge.get("recharge_at", []).filter(func(value): return float(value) > now)
	var ready: int
	if maximum <= 1:
		ready = 1 if cooldown <= now else 0
	elif not allocated:
		ready = maximum
	else:
		ready = maxi(0, maximum - deadlines.size())
		cooldown = 0.0 if ready > 0 else float(deadlines.min())
	return {"maximum": maximum, "ready": ready, "deadlines": deadlines, "cooldown": cooldown}
