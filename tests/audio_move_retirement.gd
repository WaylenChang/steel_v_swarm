extends Node

var assertions := 0
var failures: Array[String] = []

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var stopped := AudioMoveWorker.new()
	var pending := AudioMoveMixer.new()
	var pending_reference: WeakRef = weakref(pending)
	_check(stopped.add(pending), "A live worker accepts a pending mixer")
	pending = null
	stopped.stop()
	_check(stopped.pending.is_empty(), "Stopping a not-yet-started worker releases its pending mixer ownership")
	_check(pending_reference.get_ref() == null, "Stopping releases the worker's final pending mixer reference")
	_check(not stopped.add(AudioMoveMixer.new()), "Stopped ownership is reported explicitly to the caller")
	_check(stopped.pending.is_empty(), "A stopped worker cannot retain a newly submitted mixer")
	var sink := StringName("MoveRetirement_%d" % get_instance_id())
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, str(sink))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(sink), true)
	var buses := AudioBuses.new()
	add_child(buses)
	_check(buses.configure() == OK, "Retirement probe uses a live native routing context")
	AudioServer.set_bus_send(AudioServer.get_bus_index(buses.sfx), sink)
	var movement := AudioMove.new()
	add_child(movement)
	_check(movement.configure(Content.balance.audio, buses, false) == OK, "A fresh movement owner configures normally")
	movement.unlock(buses.context_seconds())
	movement.set_move("stomp", .8, 0, 1, 0)
	var deadline := Time.get_ticks_msec() + 5000
	while (not movement.voices.has("stomp") or not movement.voices.stomp.activated) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(movement.voices.has("stomp") and movement.voices.stomp.activated, "Movement retirement starts from an active native worker and voice")
	var voice: AudioMoveVoice = movement.voices.get("stomp")
	var bank := movement.bank
	var initial: Dictionary = movement.state.voices.stomp.values.duplicate(true)
	remove_child(movement)
	_check(not movement.thread.is_started() and movement.state.disposed and not movement.configured,
		"Detachment joins the worker and permanently retires its state")
	_check(voice.mixer.stopping and not voice.output_player.playing,
		"A retired movement voice stops its mixer and native player")
	add_child(movement)
	_check(movement.configure(Content.balance.audio, buses, false) == ERR_UNCONFIGURED,
		"Reattachment cannot report success for a permanently disposed movement owner")
	_check(voice.configure("stomp", Content.balance.audio, bank, buses, initial, 0) == ERR_UNCONFIGURED,
		"A retired voice rejects reconfiguration instead of reusing stopped mixer state")
	movement.free()
	var fresh := AudioMove.new()
	add_child(fresh)
	_check(fresh.configure(Content.balance.audio, buses, false) == OK, "A new movement owner can use the surviving routing context")
	fresh.unlock(buses.context_seconds())
	fresh.set_move("stomp", .8)
	deadline = Time.get_ticks_msec() + 5000
	while (not fresh.voices.has("stomp") or not fresh.voices.stomp.activated) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(fresh.voices.has("stomp") and fresh.voices.stomp.activated and fresh.thread.is_started(),
		"Fresh ownership starts an independent native worker after retirement")
	deadline = Time.get_ticks_msec() + 5000
	while int(fresh.voices.stomp.mixer.snapshot().get("frames", 0)) == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(int(fresh.voices.stomp.mixer.snapshot().get("frames", 0)) > 0,
		"The replacement worker consumes actual native mixer frames")
	fresh.free()
	var early := AudioMove.new()
	add_child(early)
	_check(early.configure(Content.balance.audio, buses, false) == OK, "A startup-retirement probe starts from a fresh owner")
	early.unlock(buses.context_seconds())
	early.set_move("stomp", .8)
	remove_child(early)
	await get_tree().process_frame
	_check(not early.worker_ready and not early.voices.stomp.activated and not early.thread.is_started(),
		"A deferred worker-start callback cannot activate a retired movement owner")
	early.free()
	var rejected := AudioMove.new()
	add_child(rejected)
	_check(rejected.configure(Content.balance.audio, buses, false) == OK, "A closed-worker probe has valid native routing")
	rejected.worker.stop()
	var errors: Array = []
	rejected.failed.connect(func(category, operation, error): errors.append([category, operation, error]))
	rejected.unlock(buses.context_seconds())
	rejected.set_move("stomp", .8)
	deadline = Time.get_ticks_msec() + 5000
	while errors.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(errors == [["stomp", "worker_stopped", ERR_UNCONFIGURED]] and rejected.voices.is_empty() and rejected.worker.pending.is_empty(),
		"Rejected worker ownership reports one failure and immediately releases the activated voice")
	rejected.free()
	var queued := AudioMove.new()
	add_child(queued)
	queued.queue_free()
	_check(queued.configure(Content.balance.audio, buses, false) == ERR_UNCONFIGURED,
		"Queued retirement rejects new movement configuration before allocating voices")
	var queued_voice := AudioMoveVoice.new()
	add_child(queued_voice)
	queued_voice.queue_free()
	_check(queued_voice.configure("stomp", Content.balance.audio, bank, buses, initial, 0) == ERR_UNCONFIGURED,
		"Queued voice retirement rejects new native route allocation")
	var queued_start := AudioMove.new()
	add_child(queued_start)
	_check(queued_start.configure(Content.balance.audio, buses, false) == OK, "Queued startup probe configures before retirement")
	queued_start.unlock(buses.context_seconds())
	queued_start.set_move("stomp", .8)
	queued_start.queue_free()
	var commands: int = queued_start.voices.stomp.mixer.commands.size()
	queued_start._worker_started()
	queued_start.set_move("stomp", .4)
	_check(not queued_start.worker_ready and not queued_start.voices.stomp.activated and queued_start.voices.stomp.mixer.commands.size() == commands,
		"Queued retirement blocks deferred startup and later control submission immediately")
	var reentrant := AudioMove.new()
	add_child(reentrant)
	_check(reentrant.configure(Content.balance.audio, buses, false) == OK, "Registration retirement starts from a valid owner")
	reentrant.unlock(buses.context_seconds())
	reentrant.state.registered.connect(func(_category): reentrant.queue_free(), CONNECT_ONE_SHOT)
	reentrant.set_move("stomp", .8)
	_check(reentrant.is_queued_for_deletion() and not reentrant.thread.is_started() and reentrant.voices.stomp.mixer.commands.is_empty(),
		"Retirement from registration cannot enqueue controls or start an obsolete worker")
	var early_listener := AudioMove.new()
	add_child(early_listener)
	early_listener.state.registered.connect(func(_category): early_listener.queue_free(), CONNECT_ONE_SHOT)
	_check(early_listener.configure(Content.balance.audio, buses, false) == OK, "A registration listener can precede internal binding")
	early_listener.unlock(buses.context_seconds())
	early_listener.set_move("stomp", .8)
	_check(early_listener.voices.is_empty() and early_listener.bank == null and not early_listener.thread.is_started(),
		"Retirement before the internal registration callback prevents native voice and bank allocation")
	await get_tree().process_frame
	var names: Array[StringName] = buses.owned.duplicate()
	buses.free()
	deadline = Time.get_ticks_msec() + 2000
	while names.any(func(name): return AudioServer.get_bus_index(name) >= 0) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(names.all(func(name): return AudioServer.get_bus_index(name) < 0), "Retirement leaves no owned routing buses behind")
	var index := AudioServer.get_bus_index(sink)
	if index > 0:
		AudioServer.remove_bus(index)
	print("AUDIO_MOVE_RETIREMENT assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
