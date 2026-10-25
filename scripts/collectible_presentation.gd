extends Node3D

var entries: Dictionary = {}
var clock := 0.0
var wall_clock := Callable()
var retired := false
var revision := 0

func _active() -> bool:
	return not retired and not is_queued_for_deletion()

func _current(token: int) -> bool:
	return _active() and token == revision

func _sample_clock(fallback: float, token: int) -> bool:
	if not _current(token):
		return false
	var sampled := float(wall_clock.call()) if wall_clock.is_valid() else fallback
	if not _current(token):
		return false
	clock = sampled
	return true

func _release_entry(id: int) -> void:
	if not entries.has(id):
		return
	var entry: Dictionary = entries[id]
	var root: Node3D = entry.root
	entries.erase(id)
	entry.clear()
	# Seal ownership before native visibility/tree callbacks can publish another snapshot.
	_release_root(root)

func _release_root(root: Node3D) -> void:
	if is_instance_valid(root):
		root.visible = false
		if is_instance_valid(root):
			root.queue_free()

func retire() -> void:
	if retired:
		return
	retired = true
	revision += 1
	set_process(false)
	wall_clock = Callable()
	var roots: Array[Node3D] = []
	for entry: Dictionary in entries.values():
		roots.append(entry.root)
		entry.clear()
	entries.clear()
	for root: Node3D in roots:
		_release_root(root)
	visible = false

func _exit_tree() -> void:
	retire()
