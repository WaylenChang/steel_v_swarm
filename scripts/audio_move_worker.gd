class_name AudioMoveWorker
extends RefCounted

signal started

var mutex := Mutex.new()
var pending: Array[AudioMoveMixer] = []
var quitting := false

func add(mixer: AudioMoveMixer) -> bool:
	mutex.lock()
	var accepted := not quitting
	if accepted:
		pending.append(mixer)
	mutex.unlock()
	return accepted

func stop() -> void:
	mutex.lock()
	quitting = true
	pending.clear()
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
		# Players start in admission order, so their earlier buffers expire first.
		var index := 0
		while index < active.size():
			if active[index].pump():
				index += 1
			else:
				active.remove_at(index)
		OS.delay_usec(1000)
