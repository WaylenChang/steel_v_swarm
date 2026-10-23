class_name RoomMetadata
extends RefCounted

static func sanitize(value: String) -> String:
	var rules: Dictionary = Content.balance.get("rooms", {}).get("names", {})
	if rules.is_empty():
		push_error("Missing original room name rules; regenerate source content")
		return ""
	var filter := RegEx.new()
	if filter.compile(rules.pattern) != OK:
		push_error("Invalid original room name filter")
		return ""
	var result := filter.sub(value, "", true).strip_edges().left(int(rules.maximum))
	return String(rules.fallback) if result.is_empty() else result

static func public_at_creation(value: Variant) -> bool:
	return not (value is bool and not value)
