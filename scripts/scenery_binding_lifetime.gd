class_name SceneryBindingLifetime
extends Node

var controller: WeakRef
var generation := 0

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or controller == null:
		return
	var target: RefCounted = controller.get_ref()
	controller = null
	if target != null:
		target.call("_retire_binding", generation, get_instance_id())
