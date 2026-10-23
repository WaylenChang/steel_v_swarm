class_name SceneryPresentation
extends RefCounted

var owned_meshes: Dictionary = {}
var batches: Array[MultiMeshInstance3D] = []
var landmarks: Array = []
var trains: Array[SceneryTrainMotion] = []
var motions: Array[SceneryMotion] = []
static var wind_time := 0.0
static var wind_phase := 0.0
static var wave_phase := 0.0
static var gust_phase := 0.0
static var wildlife_activity := 1.0

func configure(root: Node3D, train_sources: Array = [], motion_sources: Array = []) -> bool:
	owned_meshes.clear()
	batches.clear()
	landmarks.clear()
	trains.clear()
	motions.clear()
	var random := RandomNumberGenerator.new()
	random.randomize()
	var phases := {}
	var pivots := {}
	for node: Node3D in root.find_children("*", "Node3D", true, false):
		if node.has_meta("source_motion_id"):
			pivots[int(node.get_meta("source_motion_id"))] = node
	for source: Dictionary in motion_sources:
		if not pivots.has(int(source.id)):
			push_error("Missing original scenery motion pivot")
			return false
		var motion := SceneryMotion.new()
		var phase: Variant = null
		if source.has("clockGroup"):
			var clock := int(source.clockGroup)
			if not phases.has(clock):
				phases[clock] = _random_phase(random)
			phase = phases[clock]
		if not motion.configure(pivots[int(source.id)], source, phase):
			return false
		motions.append(motion)
	if not train_sources.is_empty():
		for source: Dictionary in train_sources:
			var train := SceneryTrainMotion.new()
			if not train.configure(root, source, _random_phase(random)):
				return false
			trains.append(train)
	for node: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		var key: String = node.get_meta("source_building_key", "")
		if not key.is_empty():
			if not owned_meshes.has(key):
				owned_meshes[key] = []
			owned_meshes[key].append(node)
		if node.has_meta("source_camp_landmark"):
			landmarks.append({"node": node, "spec": node.get_meta("source_camp_landmark")})
		if node.get_meta("source_camp_building_batch", false):
			var batch := node as MultiMeshInstance3D
			if batch == null or batch.multimesh == null:
				push_error("Original instanced building clearance requires its source MultiMesh")
				return false
			batch.multimesh = batch.multimesh.duplicate()
			batches.append(batch)
	return true

static func _random_phase(random: RandomNumberGenerator) -> float:
	var phase := random.randf()
	while phase >= 1.0:
		phase = random.randf()
	return phase

func advance(delta: float, weather: Dictionary) -> void:
	# Original stepCelWind integrates elapsed time independently of weather frequency.
	var step := clampf(delta, 0, 0.25) if is_finite(delta) else 0.0
	wind_time += step
	wind_phase += step * float(weather.get("windFreq", 1))
	wave_phase += step * float(weather.get("waveSpeed", 1))
	gust_phase += step * WeatherRules.wind_profile(weather).w
	wildlife_activity = WeatherRules.wildlife_activity(weather)
	for train: SceneryTrainMotion in trains:
		train.advance(delta)
	for motion: SceneryMotion in motions:
		motion.advance(delta, wind_time, weather)

func clear_camps(camps: Array, buildings: Dictionary) -> void:
	for key: String in buildings:
		for node: GeometryInstance3D in owned_meshes.get(key, []):
			if is_instance_valid(node):
				node.visible = false
	var radius: float = Content.constants.THIRD.BLD_CLEAR_R
	for landmark: Dictionary in landmarks:
		var node: GeometryInstance3D = landmark.node
		if not is_instance_valid(node) or not node.visible:
			continue
		var spec: Dictionary = landmark.spec
		for camp: Dictionary in camps:
			var dx := float(spec.x) - float(camp.x)
			var dz := float(spec.z) + float(camp.z)
			if sqrt(dx * dx + dz * dz) - float(spec.r) < radius:
				node.visible = false
				break
	for batch: MultiMeshInstance3D in batches:
		if not is_instance_valid(batch):
			continue
		for index in range(batch.multimesh.instance_count):
			var frame := batch.multimesh.get_instance_transform(index)
			if CampRules.clears_building_instance(frame, camps):
				batch.multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))
