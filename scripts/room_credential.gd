class_name RoomCredential
extends RefCounted

const SAVE_PATH := "user://connection.cfg"

var path := SAVE_PATH
var persist := false
var record: Dictionary = {}
var revision := ""

static func valid(value: Dictionary) -> bool:
	return value.get("address") is String and not String(value.address).is_empty() and value.get("port") is int and int(value.port) >= 1 and int(value.port) <= 65535 and value.get("token") is String and not String(value.token).is_empty()

func load_save() -> Error:
	if not persist:
		return OK
	record = {}
	revision = ""
	var file := ConfigFile.new()
	var error := file.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return OK
	if error != OK:
		return error
	if not file.has_section("seat"):
		return OK
	for key: String in ["address", "port", "token"]:
		if not file.has_section_key("seat", key):
			return ERR_INVALID_DATA
	var value := {"address": file.get_value("seat", "address"), "port": file.get_value("seat", "port"), "token": file.get_value("seat", "token")}
	if not valid(value):
		return ERR_INVALID_DATA
	record = value
	var saved_revision = file.get_value("recovery", "revision", "")
	if not saved_revision is String:
		record = {}
		return ERR_INVALID_DATA
	revision = saved_revision
	return OK

func remember(address: String, port: int, token: String) -> Error:
	var value := {"address": address, "port": port, "token": token}
	if not valid(value):
		return ERR_INVALID_DATA
	record = value
	var previous := revision
	revision = Crypto.new().generate_random_bytes(16).hex_encode()
	var error := _save()
	if error != OK:
		revision = previous
	return error

func clear(force: bool = false) -> Error:
	record = {}
	if persist:
		var current := ConfigFile.new()
		var error := current.load(path)
		if error == ERR_FILE_NOT_FOUND:
			revision = ""
			return OK
		if error != OK:
			return error
		# A revoked older process must not erase its successor's saved seat.
		if not force and current.get_value("recovery", "revision", "") != revision:
			revision = ""
			return OK
	revision = ""
	return _save()

func _save() -> Error:
	if not persist:
		return OK
	var file := ConfigFile.new()
	for key: String in record:
		file.set_value("seat", key, record[key])
	if not record.is_empty():
		file.set_value("recovery", "revision", revision)
	return file.save(path)
