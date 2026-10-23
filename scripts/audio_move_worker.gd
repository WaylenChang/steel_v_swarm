class_name AudioMoveWorker
extends RefCounted

signal started

var mutex := Mutex.new()
var pending: Array[AudioMoveMixer] = []
var quitting := false

func add(mixer: AudioMoveMixer) -> void:
	mutex.lock()
	pending.append(mixer)
	mutex.unlock()

func stop() -> void:
	mutex.lock()
	quitting = true
	mutex.unlock()

func run() -> void:
	var active: Array[AudioMoveMixer] = []
	started.emit()
	while true:
		mutex.lock()
		var done := quitting
		active.append_array(pending)
		pending.clear()
		mutex.unlock()
		if done:
			return
		for index in range(active.size() - 1, -1, -1):
			if not active[index].pump():
				active.remove_at(index)
		OS.delay_usec(2000)
