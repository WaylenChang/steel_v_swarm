class_name DamageFxBinding
extends RefCounted

var node: DamageFx
var stage := 0

func set_stage(destination: int, parent: Node3D, kind: String, size: Dictionary, sample: Callable = Callable()) -> bool:
	if destination < 0 or destination == stage:
		return false
	if destination == 0:
		clear()
		return true
	if node == null:
		if size.is_empty():
			push_error("Persistent damage FX require captured model dimensions")
			return false
		var profile: Dictionary = Content.balance.destruction.sceneProfiles.get(kind, {})
		var fresh := DamageFx.new()
		parent.add_child(fresh)
		if not fresh.configure(DamageFx.source_dimensions(size), profile.get("fire", true), profile.is_empty(), sample):
			fresh.free()
			return false
		node = fresh
	stage = destination
	node.set_stage(destination)
	return true

func clear() -> void:
	if is_instance_valid(node):
		node.free()
	node = null
	stage = 0
