class_name MarineWaveSources
extends RefCounted

var sources := PackedVector4Array()
var shapes := PackedVector4Array()

func configure(count: int, initial_sources: Array = [], initial_shapes: Array = []) -> bool:
	if count <= 0 or (not initial_sources.is_empty() and initial_sources.size() != count) or (not initial_shapes.is_empty() and initial_shapes.size() != count):
		push_error("Invalid original marine wave-source capacity")
		return false
	sources.resize(count)
	shapes.resize(count)
	sources.fill(Vector4.ZERO)
	shapes.fill(Vector4.ZERO)
	for channel in range(2):
		var records: Array = initial_sources if channel == 0 else initial_shapes
		for index in range(records.size()):
			var values: Array = records[index]
			if values.size() != 4:
				push_error("Invalid original marine wave-source packet")
				return false
			var packet := Vector4(values[0], values[1], values[2], values[3])
			if not packet.is_finite():
				push_error("Non-finite original marine wave-source packet")
				return false
			if channel == 0:
				sources[index] = packet
			else:
				shapes[index] = packet
	return true

func set_sources(records: Variant) -> void:
	var slot := 0
	if records is Array:
		for record: Variant in records:
			if slot >= sources.size():
				break
			if not record is Dictionary:
				continue
			var valid := true
			for key: String in ["x", "z", "dx", "dz", "length", "beam", "speed"]:
				var value: Variant = record.get(key)
				if not (value is int or value is float) or not is_finite(float(value)):
					valid = false
					break
			if not valid or float(record.length) <= 0 or float(record.beam) <= 0 or float(record.speed) < 0:
				continue
			var dx := float(record.dx)
			var dz := float(record.dz)
			var scale_value := maxf(absf(dx), absf(dz))
			if scale_value == 0:
				continue
			var nx := dx / scale_value
			var nz := dz / scale_value
			var magnitude := scale_value * sqrt(nx * nx + nz * nz)
			if magnitude <= 0.000001:
				continue
			sources[slot] = Vector4(record.x, record.z, dx / magnitude, dz / magnitude)
			shapes[slot] = Vector4(record.length, record.beam, record.speed, 1)
			slot += 1
	# Original inactive slots retain their previous origins/headings, clearing only shape.
	for index in range(slot, shapes.size()):
		shapes[index] = Vector4.ZERO

func update_vessels(motions: Array[SceneryMotion], frozen: bool) -> void:
	if frozen:
		return
	var records := []
	for motion: SceneryMotion in motions:
		if not motion.spec.has("wave") or not is_instance_valid(motion.pivot):
			continue
		var position := motion.pivot.position
		records.append({"x": position.x, "z": position.z, "dx": sin(motion.angles.y), "dz": cos(motion.angles.y),
			"length": motion.spec.wave.length, "beam": motion.spec.wave.beam, "speed": motion.spec.wave.speed})
	set_sources(records)
