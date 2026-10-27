extends RefCounted

const QUANTUM := 128
const CONVERGENCE := 0.00004539992976248485

var sample_rate := 0
var frame := 0
var value := 0.0
var target := 0.0
var time_constant := 0.0
var event_time := 0.0
var active := false
var events: Array[Dictionary] = []

func configure(initial: float, rate: float) -> Error:
	if not is_finite(initial) or not is_finite(Vector2(initial, 0).x) or not is_finite(rate) or rate < 8000 or rate > 384000 or rate != floor(rate):
		return ERR_INVALID_DATA
	sample_rate = int(rate)
	frame = 0
	value = Vector2(initial, 0).x
	target = value
	time_constant = 0
	event_time = 0
	active = false
	events.clear()
	return OK

func queue(next_target: float, time: float, tau: float) -> Error:
	if sample_rate == 0:
		return ERR_UNCONFIGURED
	if not is_finite(next_target) or not is_finite(Vector2(next_target, 0).x) or not is_finite(time) or time < 0 or not is_finite(tau) or tau < 0 or not is_finite(Vector2(tau, 0).x):
		return ERR_INVALID_DATA
	if time * sample_rate < frame:
		return ERR_BUSY
	if tau > 0 and Vector2(tau, 0).x == 0:
		return ERR_UNAVAILABLE
	var entry := {"target": Vector2(next_target, 0).x, "time": time, "tau": tau}
	for index in range(events.size()):
		if ceili(float(events[index].time) * sample_rate) == ceili(time * sample_rate) and (float(events[index].tau) == 0) != (tau == 0):
			return ERR_UNAVAILABLE
		if events[index].time == time:
			events[index] = entry
			return OK
		if events[index].time > time:
			events.insert(index, entry)
			return OK
	events.append(entry)
	return OK

func render(count: int) -> PackedFloat32Array:
	# A source AudioParam advances whole render quanta, independently of device refills.
	if sample_rate == 0 or count <= 0 or count % QUANTUM != 0:
		return PackedFloat32Array()
	var output := PackedFloat32Array()
	output.resize(count)
	var finish := frame + count
	var written := 0
	while frame < finish:
		var fresh := false
		# A target ending exactly at the next quantum is visited once with an empty
		# span before its successor; that visit advances its previous last sample.
		if active and time_constant > 0 and frame % QUANTUM == 0 and not events.is_empty() and float(events[0].time) * sample_rate == frame:
			var previous_step := Vector2(1.0 - exp(-1.0 / (sample_rate * time_constant)), 0).x
			value = Vector2(value + Vector2(Vector2(target - value, 0).x * previous_step, 0).x, 0).x
		while not events.is_empty() and ceili(float(events[0].time) * sample_rate) <= frame:
			var event: Dictionary = events.pop_front()
			target = event.target
			time_constant = Vector2(float(event.tau), 0).x
			event_time = event.time
			active = true
			fresh = true
		var end := mini(finish, (frame / QUANTUM + 1) * QUANTUM)
		if not events.is_empty():
			end = mini(end, ceili(float(events[0].time) * sample_rate))
		if not active or time_constant == 0:
			if active:
				value = target
			while frame < end:
				output[written] = value
				written += 1
				frame += 1
			continue
		var c0 := Vector2(1.0 - exp(-1.0 / (sample_rate * time_constant)), 0).x
		if fresh:
			# The Float32 subtraction still rounds when the event starts on an exact sample.
			value = Vector2(target + Vector2(value - target, 0).x * exp(-(float(frame) / sample_rate - event_time) / time_constant), 0).x
		else:
			value = Vector2(value + Vector2(Vector2(target - value, 0).x * c0, 0).x, 0).x
		var difference := absf(Vector2(target - value, 0).x)
		var converged := float(frame) / sample_rate > event_time + 10 * time_constant
		converged = converged or (absf(value) < CONVERGENCE if target == 0 else difference < Vector2(CONVERGENCE * absf(value), 0).x)
		if converged:
			value = target
			while frame < end:
				output[written] = value
				written += 1
				frame += 1
			continue
		var c1 := Vector2(c0 * Vector2(2.0 - c0, 0).x, 0).x
		var step2 := Vector2(Vector2(c0 - 3.0, 0).x * c0, 0).x
		var c2 := Vector2(c0 * Vector2(step2 + 3.0, 0).x, 0).x
		var step3 := Vector2(Vector2(4.0 - c0, 0).x * c0, 0).x
		step3 = Vector2(step3 - 6.0, 0).x
		step3 = Vector2(c0 * step3, 0).x
		var c3 := Vector2(c0 * Vector2(step3 + 4.0, 0).x, 0).x
		while frame + 4 <= end:
			var delta := Vector2(target - value, 0).x
			var products := Vector4(0, delta * c0, delta * c1, delta * c2)
			var samples := Vector4(value, value + products.y, value + products.z, value + products.w)
			for point in range(4):
				output[written + point] = samples[point]
			value = Vector2(value + Vector2(delta * c3, 0).x, 0).x
			written += 4
			frame += 4
		while frame < end:
			output[written] = value
			value = Vector2(value + Vector2(Vector2(target - value, 0).x * c0, 0).x, 0).x
			written += 1
			frame += 1
		value = output[written - 1]
	return output
