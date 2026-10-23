class_name AudioMusicEnvelope
extends RefCounted

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

func value_at(now: float) -> float:
	if disconnected:
		return 0
	var elapsed := maxf(0, now - anchor_time)
	if ramping:
		if now >= ramp_end:
			return ramp_gain
		return anchor_gain * pow(ramp_gain / anchor_gain, elapsed / (ramp_end - anchor_time))
	if time_constant > 0:
		return target + (anchor_gain - target) * exp(-elapsed / time_constant)
	return anchor_gain

func set_volume(now: float, volume: float) -> void:
	if disconnected:
		return
	var previous := value_at(maxf(anchor_time, now - 1.0 / sample_rate))
	anchor_time = now
	anchor_gain = previous
	if ramping and now < ramp_end:
		# A target inserted before the pending ramp becomes its new starting value.
		# The original future ramp endpoint remains scheduled.
		return
	ramping = false
	target = volume
	time_constant = float(rules.volumeTimeConstant)

func release(now: float) -> void:
	if disconnected:
		return
	var previous := anchor_gain if ramping and now < ramp_end else value_at(maxf(anchor_time, now - 1.0 / sample_rate))
	# Source cancelScheduledValues removes the future ramp, rather than holding it.
	ramping = false
	anchor_time = now
	anchor_gain = previous
	target = float(rules.releaseGain)
	time_constant = float(rules.releaseTimeConstant)
	retirement_time = now + float(rules.retirementSeconds)

func disconnect_output() -> void:
	disconnected = true
