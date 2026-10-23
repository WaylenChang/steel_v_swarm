extends RefCounted

static func publish(resource: Resource, target: String, tree: SceneTree) -> Error:
	var temporary := target.get_base_dir().path_join(".%s.partial-%d-%d.%s" % [target.get_file().get_basename(), OS.get_process_id(), Time.get_ticks_usec(), target.get_extension()])
	var error := ResourceSaver.save(resource, temporary, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		return error
	for attempt in range(60):
		error = DirAccess.rename_absolute(temporary, target)
		if error == OK:
			return OK
		if attempt < 59:
			await tree.create_timer(0.5).timeout
	push_error("Cannot publish native source resource; complete resource retained: " + temporary)
	return error
