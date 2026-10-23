class_name AudioEvent
extends RefCounted

# Wire events use source server Z; imported native scenes use source visual Z.
static func source_event(event: Dictionary, actor_peer: int = 0) -> Dictionary:
	var kind: String = event.get("type", "")
	var mine := kind == "mine_blast"
	if kind in ["mine_blast", "missile_blast", "missile_intercept", "missile_deflect"]:
		kind = "boom"
	if kind not in ["shot", "plasma", "die", "boom", "cast", "crit", "buy", "sam", "airfall", "airdrop", "relay", "lock"]:
		return {}
	# Physical projectile steps are native presentation updates, not source shots.
	if kind == "shot" and event.get("physical", false):
		return {}
	var result := {"e": kind}
	if actor_peer != 0 or event.has("peer") or event.has("shooter_peer"):
		result.pid = event.get("peer", event.get("shooter_peer", actor_peer))
	for key: String in ["side", "slot", "kind"]:
		if event.has(key):
			result[key] = event[key]
	if kind in ["lock", "sam"]:
		result.tpid = event.get("target_peer")
	if kind == "sam" and event.get("position") is Vector3:
		var point: Vector3 = event.position
		result.from = [point.x, -point.z]
	elif kind != "shot":
		var point: Variant = event.get("point") if kind == "cast" else event.get("position")
		if point is Vector3:
			result.x = point.x
			result.z = -point.z
		# Source deaths/casts/airdrop/relay omit height, even on raised terrain.
		if kind in ["boom", "plasma", "crit"] and not mine:
			if not event.has("audio_height"):
				push_error("Missing original event altitude for audio: " + kind)
				return {}
			result.y = event.audio_height
	if event.has("radius"):
		result.r = event.radius
	return result
