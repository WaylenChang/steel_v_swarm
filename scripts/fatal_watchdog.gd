class_name FatalWatchdog
extends RefCounted

var rules: Dictionary = {}
var shown := false
var load_started := 0
var load_progress := 0
var local_loaded := false
var last_snapshot := 0
var last_frame := 0
var disconnected_at := 0
var hidden := false
var hidden_at := 0

func loading(now: int) -> void:
	load_started = now
	load_progress = now
	local_loaded = false
	last_snapshot = now
	disconnected_at = 0

func launched(now: int) -> void:
	last_snapshot = now
	disconnected_at = 0

func snapshot(now: int) -> void:
	last_snapshot = now

func visibility(value: bool, now: int) -> void:
	if hidden == value:
		return
	hidden = value
	if hidden:
		hidden_at = now
		return
	var elapsed := now - hidden_at if hidden_at > 0 else 0
	hidden_at = 0
	if load_started > 0:
		load_started += elapsed
	if load_progress > 0:
		load_progress += elapsed
	last_frame = now
	last_snapshot = now
	disconnected_at = 0

func reveal(phase: String, force: bool = false) -> bool:
	if shown or not force and phase not in ["loading", "game"]:
		return false
	shown = true
	return true

func reason(phase: String, connected: bool, battle: bool, now: int) -> String:
	if rules.is_empty() or hidden or shown or phase not in ["loading", "game"]:
		return ""
	if connected:
		disconnected_at = 0
	else:
		if disconnected_at == 0:
			disconnected_at = now
		if now - disconnected_at > int(rules.NET_MS):
			return "fatal_network"
	if phase == "loading":
		if not local_loaded:
			if load_progress > 0 and now - load_progress > int(rules.LOAD_MS) or load_started > 0 and now - load_started > int(rules.LOAD_MS) * 2:
				return "fatal_loading"
		elif load_started > 0 and now - load_started > int(rules.LOAD_MS) * 2:
			return "fatal_waiting"
	if phase == "game" and battle:
		if last_snapshot > 0 and now - last_snapshot > int(rules.SNAP_MS):
			return "fatal_snapshot"
		if now - last_frame > int(rules.SNAP_MS):
			return "fatal_frame"
	return ""
