class_name AuthorityWeaponPose
extends RefCounted

var profile: Dictionary
var character: String
var weapons := WeaponPresentation.new()
var bursts := BurstPresentationQueue.new()
var accepted_serial := -1
var rest: Dictionary = {}
var local: Dictionary = {}
var graph: Dictionary = {}
var caches: Dictionary = {}
var cache_id := 0
var gun := Transform3D.IDENTITY
var kick := 0.0
var clock := -INF
var slot := "light"
var form := "ground"

func configure(pilot: String) -> void:
	character = pilot
	profile = Content.balance.cockpit[character]
	weapons.configure(profile)
	for spec: Dictionary in profile.poseGraph:
		var m: Array = spec.matrix
		rest[int(spec.id)] = Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])),
			Vector3(m[12], m[13], m[14]))
		graph[int(spec.id)] = spec
	local = rest.duplicate()
	for i in range(profile.muzzleCache.points.size()):
		var point: Array = profile.muzzleCache.points[i]
		caches[i] = Vector3(point[0], point[1], point[2])
	cache_id = int(profile.muzzleCache.current)
	gun = CockpitPose.transform_for(profile, Vector3.ZERO, 0, 0)
	_sync_emitter("light", false)

func fire(serial: int, fired_slot: String, at: float, definition: Dictionary = {}) -> bool:
	if serial <= accepted_serial or at < clock or (is_finite(weapons.last_fire_at) and at < weapons.last_fire_at):
		return false
	if not weapons.fire(maxi(serial, weapons.last_serial + 1), fired_slot, at):
		return false
	accepted_serial = serial
	bursts.schedule(definition, at, {"slot": fired_slot})
	kick = 1
	return true

func advance(delta: float, now: float, selected: String, flying: bool, definition: Dictionary,
		reload_end: float = NAN, elevation: float = 0, alive: bool = true) -> bool:
	if not is_finite(now) or not is_finite(delta) or delta <= 0 or now <= clock or selected not in ["light", "heavy"]:
		return false
	clock = now
	slot = selected
	form = "air" if flying and profile.motion.has("air") else "ground"
	for echo: Dictionary in bursts.take_due(now):
		if not alive:
			continue
		muzzle(Transform3D.IDENTITY, echo.payload.slot, flying)
		weapons.fire(weapons.last_serial + 1, echo.payload.slot, now)
		kick = 1
	weapons.advance(delta, now)
	var poses := weapons.pose(form, now)
	local = rest.duplicate()
	for binding: Dictionary in profile.bindings:
		var id := int(binding.target)
		var transform: Transform3D = local[id]
		var spec: Dictionary = poses[binding.source]
		var scale := Vector3(spec.scale[0], spec.scale[1], spec.scale[2])
		transform.basis = Basis(WeaponPresentation.source_rotation(spec)) if binding.rotate else transform.basis.orthonormalized()
		transform.basis = transform.basis.scaled_local(scale)
		var parent: int = graph[id].parent
		var parent_name: String = graph[parent].name if graph.has(parent) else profile.poseGunName
		if binding.translate and parent_name == spec.parent:
			transform.origin = Vector3(spec.position[0], spec.position[1], spec.position[2])
		local[id] = transform
	# Source caches the current emitter before moving the gun root; launch queries use the next emitter.
	_sync_emitter(selected, flying)
	kick = maxf(0, kick - delta * Content.balance.cockpitRules.kickDecay)
	var reload := Vector3.ZERO
	if is_finite(reload_end):
		var progress := 1 - maxf(0, reload_end - now) / maxf(0.001, definition.reload)
		reload = CockpitPose.reload_offset(definition, progress)
	gun = CockpitPose.transform_for(profile, reload, elevation, kick)
	return true

func muzzle(camera: Transform3D, fired_slot: String, flying: bool, next: bool = true, remember: bool = true) -> Vector3:
	if fired_slot not in ["light", "heavy"]:
		return Vector3(NAN, NAN, NAN)
	var active := "air" if flying and profile.motion.has("air") else "ground"
	var state: Dictionary = weapons.sequences[active][fired_slot]
	var index := posmod(int(state.index) + 1, state.times.size()) if next else maxi(0, int(state.index))
	var id := int(profile.emissions[active][fired_slot][index])
	var point: Vector3 = _port(id) if id >= 0 else caches[cache_id]
	if id >= 0 and remember:
		caches[cache_id] = point
	return camera * gun * point

func current_muzzle(camera: Transform3D) -> Vector3:
	return camera * gun * caches[cache_id]

func _sync_emitter(selected: String, flying: bool) -> void:
	var active := "air" if flying and profile.motion.has("air") else "ground"
	var index := maxi(0, int(weapons.sequences[active][selected].index))
	var id := int(profile.emissions[active][selected][index])
	if id >= 0:
		caches[cache_id] = _port(id)
	else:
		var set: Dictionary = profile.muzzleCache.forms[active]
		cache_id = int(set.get(selected, set.get("light", set.get("heavy"))))

func _port(id: int) -> Vector3:
	var point := Vector3.ZERO
	while id != int(profile.nodes.gun):
		point = local[id] * point
		id = int(graph[id].parent)
	return point
