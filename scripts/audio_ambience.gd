class_name AudioAmbience
extends Node

signal bed_failed(id: String, error: Error)

var state := AudioAmbienceState.new()
var buses: AudioBuses
var players: Dictionary = {}
var configured := false
var previous_clock := 0.0

func configure(metadata: Dictionary, routing: AudioBuses) -> Error:
	if configured:
		return ERR_ALREADY_IN_USE
	if not is_inside_tree() or routing == null or not routing.available():
		return ERR_UNCONFIGURED
	process_mode = Node.PROCESS_MODE_ALWAYS
	buses = routing
	state.configure(metadata)
	state.registered.connect(_register)
	previous_clock = buses.context_seconds()
	configured = true
	return OK

func set_ambience(query: Dictionary) -> void:
	if not configured:
		return
	_advance()
	state.set_ambience(query)

func _register(id: String, url: String) -> void:
	var player := AudioLoopPlayer.new()
	player.volume_linear = float(state.beds[id].gain)
	player.play_when_loaded = true
	player.load_failed.connect(func(error: Error) -> void: bed_failed.emit(id, error))
	add_child(player)
	players[id] = player
	player.open(url, buses.sfx)

func _process(_delta: float) -> void:
	if configured and not state.disposed:
		_advance()

func _advance() -> void:
	# The source AudioContext clock advances independently of simulation time scale.
	var now := buses.context_seconds()
	state.advance(now - previous_clock)
	previous_clock = now
	for id: String in players:
		players[id].volume_linear = float(state.beds[id].gain)

func _exit_tree() -> void:
	if not configured:
		return
	state.dispose()
	for player: AudioLoopPlayer in players.values():
		player.stop()
