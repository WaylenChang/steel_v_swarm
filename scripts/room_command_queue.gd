class_name RoomCommandQueue
extends RefCounted

var capacity := 0
var connected := false
var pending: Array[Dictionary] = []

func send(message: Dictionary, deliver: Callable, immediate: bool = false) -> bool:
	if connected:
		if deliver.call(message):
			return true
		connected = false
	elif immediate:
		return false
	if capacity <= 0:
		return false
	if pending.size() >= capacity:
		pending.pop_front()
	pending.append(message.duplicate(true))
	return false

func flush(deliver: Callable) -> void:
	if not connected:
		return
	while not pending.is_empty():
		if not deliver.call(pending[0]):
			connected = false
			return
		pending.pop_front()

func clear() -> void:
	pending.clear()
	connected = false
