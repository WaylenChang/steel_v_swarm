class_name AudioAmbience
extends Node

signal bed_failed(id: String, error: Error)

var state := AudioAmbienceState.new()
var buses: AudioBuses
var players: Dictionary = {}
var configured := false
var previous_clock := 0.0
var retired := false

func configure(metadata: Dictionary, routing: AudioBuses) -> Error:
	if retired or state.disposed or not is_inside_tree() or is_queued_for_deletion():
		return ERR_UNCONFIGURED
	if configured:
		return ERR_ALREADY_IN_USE
	if not is_instance_valid(routing) or routing.is_queued_for_deletion() or not routing.available():
		return ERR_UNCONFIGURED
	process_mode = Node.PROCESS_MODE_ALWAYS
	buses = routing
	buses.retiring.connect(_retire, CONNECT_ONE_SHOT)
	state.configure(metadata)
	state.registered.connect(_register)
	previous_clock = buses.context_seconds()
	configured = true
	return OK

func set_ambience(query: Dictionary) -> void:
	if not _active():
		return
	_advance()
	state.set_ambience(query)

func _register(id: String, url: String) -> void:
	if not _active():
		return
	var player := _make_player()
	if not _active():
		player.free()
		return
	player.volume_linear = float(state.beds[id].gain)
	player.play_when_loaded = true
	player.load_failed.connect(func(error: Error) -> void: bed_failed.emit(id, error))
	players[id] = player
	add_child(player)
	if not _active():
		return
	player.open(url, buses.sfx)

func _make_player() -> AudioLoopPlayer:
	return AudioLoopPlayer.new()

func _active() -> bool:
	return configured and not retired and not state.disposed and is_inside_tree() and not is_queued_for_deletion()

func _process(_delta: float) -> void:
	if _active():
		_advance()

func _advance() -> void:
	# The source AudioContext clock advances independently of simulation time scale.
	var now := buses.context_seconds()
	state.advance(now - previous_clock)
	previous_clock = now
	for id: String in players:
		players[id].volume_linear = float(state.beds[id].gain)

func _retire() -> void:
	if retired:
		return
	retired = true
	configured = false
	state.dispose()
	if is_instance_valid(buses) and buses.retiring.is_connected(_retire):
		buses.retiring.disconnect(_retire)
	for player: AudioLoopPlayer in players.values():
		player.retire()
	players.clear()

func _exit_tree() -> void:
	_retire()
