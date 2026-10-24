class_name AudioMusicEnvelope
extends RefCounted

# Original Web Audio render quantum and AudioParam target-convergence contract.
# https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/modules/webaudio/audio_param_handler.cc
const RENDER_QUANTUM := 128.0
const TARGET_TIME_CONSTANTS := 10.0

var rules: Dictionary = {}
var sample_rate := 48000.0
var anchor_time := 0.0
var anchor_gain := 0.0
var ramp_end := INF
var ramp_gain := 0.0
var ramping := false
var target := 0.0
var time_constant := 0.0
var retirement_time := INF
var disconnected := false
var pending_time := INF
var pending_volume := 0.0
var leading_gain := 0.0
var leading_until := -INF
var _single_value := PackedFloat32Array([0.0])
var _target_samples := PackedFloat32Array()
var _target_first_frame := 0
var _target_next_frame := 0
var _target_buffer_frame := 0
var _target_tail := 0.0
var _target_start_time := 0.0
var _target_coefficients := PackedFloat32Array()

func configure(metadata: Dictionary, rate: float) -> void:
	rules = metadata.proceduralMusic
	sample_rate = rate

func start(now: float, volume: float, enabled: bool = true) -> void:
	anchor_time = now
	anchor_gain = float(rules.initialGain)
	ramp_gain = maxf(float(rules.minimumGain), volume if enabled else float(rules.minimumGain))
	ramp_end = now + float(rules.attackSeconds)
	ramping = true
	time_constant = 0
	retirement_time = INF
	disconnected = false
	pending_time = INF
	leading_until = -INF

func value_at(now: float) -> float:
	if disconnected:
		return 0
	_commit_pending()
	return _value(now)

func _value(now: float) -> float:
	if now < leading_until:
		return leading_gain
	var elapsed := maxf(0, now - anchor_time)
	if ramping:
		if now >= ramp_end:
			return ramp_gain
		return anchor_gain * pow(ramp_gain / anchor_gain, elapsed / (ramp_end - anchor_time))
	if time_constant > 0:
		return _target_value(now)
	return anchor_gain

func set_volume(now: float, volume: float) -> void:
	if disconnected:
		return
	if pending_time != now:
		_commit_pending()
	if ramping and now < ramp_end:
		# Same-clock setters replace an event before the audio quantum renders it.
		pending_time = now
		pending_volume = volume
		return
	var previous := _boundary_value(now, false)
	_begin_target(now, previous, volume, float(rules.volumeTimeConstant))
	ramping = false

func release(now: float) -> void:
	if disconnected:
		return
	if pending_time >= now:
		pending_time = INF
	else:
		_commit_pending()
	var previous := _boundary_value(now, ramping and now <= ramp_end)
	# Source cancelScheduledValues removes the future ramp, rather than holding it.
	ramping = false
	_begin_target(now, previous, float(rules.releaseGain), float(rules.releaseTimeConstant))
	retirement_time = now + float(rules.retirementSeconds)

func _boundary_value(now: float, retained_set: bool) -> float:
	var frame := roundi(now * sample_rate)
	# The source retains a SetValue event at an exact/new frame, even when it
	# fills zero samples; a fractional frame just below it skips that event.
	if now * sample_rate < frame:
		return _value((frame - 1) / sample_rate)
	return anchor_gain if retained_set else _value(frame / sample_rate)

func _begin_target(now: float, previous: float, gain: float, constant: float) -> void:
	var frame := ceili(now * sample_rate)
	leading_gain = previous
	leading_until = frame / sample_rate
	anchor_time = leading_until
	anchor_gain = gain + (previous - gain) * exp(-(anchor_time - now) / constant)
	target = gain
	time_constant = constant
	_target_start_time = now
	_reset_target()

func _commit_pending() -> void:
	if not is_finite(pending_time):
		return
	var now := pending_time
	pending_time = INF
	var previous := _boundary_value(now, true)
	_begin_target(now, previous, pending_volume, float(rules.volumeTimeConstant))
	# A pending source ramp replaces SetTarget with its calculated SetValue.
	time_constant = 0.0

func _float32(value: float) -> float:
	_single_value[0] = value
	return _single_value[0]

func _reset_target() -> void:
	_target_first_frame = roundi(anchor_time * sample_rate)
	_target_next_frame = _target_first_frame
	_target_buffer_frame = _target_first_frame
	_target_tail = _float32(anchor_gain)
	_target_samples.clear()
	var coefficient := _float32(1.0 - exp(-1.0 / (sample_rate * _float32(time_constant))))
	# Source SIMD evaluates four float32 recurrence steps, then carries the last
	# rendered sample into the next quantum. A closed exponential loses that
	# rounding and can converge early, especially at high output sample rates.
	_target_coefficients = PackedFloat32Array([
		coefficient,
		_float32(coefficient * _float32(2.0 - coefficient)),
		_float32(coefficient * _float32(_float32(_float32(coefficient - 3.0) * coefficient) + 3.0)),
		_float32(coefficient * _float32(_float32(coefficient * _float32(_float32(_float32(4.0 - coefficient) * coefficient) - 6.0)) + 4.0))])

func _target_value(now: float) -> float:
	var frame := roundi(now * sample_rate)
	if frame < _target_buffer_frame:
		_reset_target()
	while frame >= _target_next_frame:
		_render_target_quantum()
	return _target_samples[frame - _target_buffer_frame]

func _render_target_quantum() -> void:
	var first := _target_next_frame
	var count := int(RENDER_QUANTUM) - first % int(RENDER_QUANTUM)
	_target_buffer_frame = first
	_target_samples.resize(count)
	var gain := _target_tail
	var source_target := _float32(target)
	if first > _target_first_frame:
		gain = _float32(gain + _float32(_float32(source_target - gain) * _target_coefficients[0]))
	var threshold := exp(-TARGET_TIME_CONSTANTS)
	var converged := absf(gain) < threshold if source_target == 0 else absf(source_target - gain) < threshold * absf(gain)
	if first / sample_rate > _target_start_time + TARGET_TIME_CONSTANTS * _float32(time_constant) or converged:
		_target_samples.fill(source_target)
	else:
		var index := 0
		while index + 4 <= count:
			var difference := _float32(source_target - gain)
			_target_samples[index] = gain
			for offset in range(1, 4):
				_target_samples[index + offset] = _float32(gain + _float32(difference * _target_coefficients[offset - 1]))
			gain = _float32(gain + _float32(difference * _target_coefficients[3]))
			index += 4
		while index < count:
			_target_samples[index] = gain
			gain = _float32(gain + _float32(_float32(source_target - gain) * _target_coefficients[0]))
			index += 1
	_target_tail = _target_samples[count - 1]
	_target_next_frame = first + count

func disconnect_output() -> void:
	disconnected = true
