extends "res://application/timeline_document.gd"

const Native = preload("res://application/native_resource.gd")
const SCRIPT_PATH := "res://addons/dialogic/Modules/Glossary/glossary_resource.gd"
var glossary: DialogicGlossary
var model: Dictionary = {}

func _init() -> void:
	new_document()

func new_document() -> void:
	super.new_document()
	glossary = DialogicGlossary.new()
	model = {"sections": [
		{"kind":"gd_resource", "attrs":{"type":"Resource", "script_class":"DialogicGlossary", "load_steps":2, "format":3}, "props":{}},
		{"kind":"ext_resource", "attrs":{"type":"Script", "path":SCRIPT_PATH, "id":"1"}, "props":{}},
		{"kind":"resource", "attrs":{}, "props":{"script":Native.make_reference("ExtResource", "1"), "entries":{}, "enabled":true, "_translation_id":"", "_translation_keys":{}}}
	]}
	content = Native.serialize(model)
	_original_content = content

func get_file_extension() -> String:
	return "tres"

func open_file(file_path: String, source_workspace: RefCounted = null) -> Error:
	if source_workspace != null: workspace = source_workspace
	if workspace != null and workspace.content_path(file_path).is_empty(): return _fail(ERR_FILE_BAD_PATH, "Choose a glossary inside the content root.")
	var error := super.open_file(file_path)
	if error != OK: return error
	var checked := inspect(content)
	glossary = checked.get("glossary")
	model = checked.get("model", {})
	return OK

func validate_content(text: String) -> Dictionary:
	var checked := inspect(text)
	return {"supported": not checked.has("error"), "diagnostics": [checked.error] if checked.has("error") else []}

static func inspect(text: String) -> Dictionary:
	var parsed := Native.scan(text)
	if parsed.has("error"): return parsed
	var props := {}
	var script_id := ""
	for section: Dictionary in parsed.model.sections:
		if section.kind == "sub_resource": return {"error":"Glossary subresources require the extension stage; the file remains read-only."}
		if section.kind == "ext_resource":
			if section.attrs.get("type") != "Script" or section.attrs.get("path") != SCRIPT_PATH or not script_id.is_empty(): return {"error":"Only the bundled alpha-20 glossary script is accepted."}
			script_id = section.attrs.id
		if section.kind == "resource": props = section.props
	if script_id.is_empty() or props.get("script") != Native.make_reference("ExtResource", script_id): return {"error":"Invalid native glossary script reference."}
	for key: String in props:
		if not key in ["script", "resource_name", "entries", "enabled", "_translation_id", "_translation_keys"]: return {"error":"Unknown glossary root property remains read-only: " + key}
	if not props.get("entries", {}) is Dictionary or not props.get("enabled", true) is bool or not props.get("_translation_id", "") is String or not props.get("_translation_keys", {}) is Dictionary: return {"error":"Invalid glossary property types."}
	var checked := entries_error(props.get("entries", {}))
	if not checked.is_empty(): return {"error":checked}
	var resource := DialogicGlossary.new()
	for key: String in ["entries", "enabled", "_translation_id", "_translation_keys"]:
		if props.has(key): resource.set(key, props[key])
	return {"model":parsed.model, "glossary":resource}

static func entries_error(entries: Dictionary) -> String:
	var names := {}
	for key: Variant in entries:
		if not key is String: return "Glossary keys must be strings."
		var value: Variant = entries[key]
		if value is String:
			if not entries.get(value) is Dictionary: return "Glossary alias points to a missing entry: " + key
			continue
		if not value is Dictionary or value.get("name") != key or key.strip_edges().is_empty() or key.begins_with("Glossary/"): return "Glossary entries require unique, nonempty names without the reserved Glossary/ prefix."
		if not Native.finite_data(value): return "Glossary data must contain finite native values."
		for field: String in ["name", "title", "text", "extra", "_translation_id"]:
			if value.has(field) and not value[field] is String: return "Glossary string field has an invalid type: " + field
		for field: String in ["enabled", "case_sensitive"]:
			if value.has(field) and not value[field] is bool: return "Glossary flag must be boolean: " + field
		if value.has("color") and not value.color is Color: return "Glossary color must be a Color."
		if not value.get("alternatives", []) is Array: return "Glossary alternatives must be a native Array."
		var all: Array = [key]
		all.append_array(value.get("alternatives", []))
		for word: Variant in all:
			if not word is String or word.strip_edges().is_empty() or word.begins_with("Glossary/") or names.has(word.strip_edges()): return "Duplicate, empty or reserved glossary name/alias: " + str(word)
			names[word.strip_edges()] = key
			var regex := RegEx.new()
			if regex.compile(word) != OK: return "The native glossary name is not a valid regular expression: " + word
	for word: String in names:
		if word != names[word] and entries.get(word) != names[word]: return "Glossary alias index does not match alternatives: " + word
	return ""

func sync_resource() -> Error:
	for section: Dictionary in model.sections:
		if section.kind == "resource":
			for key: String in ["entries", "enabled", "_translation_id", "_translation_keys"]: section.props[key] = glossary.get(key)
	var next := Native.serialize(model)
	var checked := inspect(next)
	if checked.has("error"): return _fail(ERR_INVALID_DATA, checked.error)
	set_content(next)
	return OK

func set_entry(old_name: String, fields: Dictionary) -> Error:
	if read_only: return _fail(ERR_UNAVAILABLE, "This glossary remains read-only.")
	var entries: Dictionary = glossary.entries.duplicate(true)
	var item: Dictionary = entries.get(old_name, {}).duplicate(true) if entries.get(old_name, {}) is Dictionary else {}
	item.merge(fields, true)
	item.erase("regex_options")
	var name: String = str(item.get("name", "")).strip_edges()
	item.name = name
	for key: String in entries.keys():
		if key == old_name or (entries[key] is String and entries[key] == old_name): entries.erase(key)
	if entries.has(name): return _fail(ERR_ALREADY_EXISTS, "Another glossary entry already uses this name.")
	entries[name] = item
	for alias: Variant in item.get("alternatives", []):
		if not alias is String or entries.has(alias.strip_edges()): return _fail(ERR_ALREADY_EXISTS, "Duplicate or invalid glossary alias.")
		entries[alias.strip_edges()] = name
	var problem := entries_error(entries)
	if not problem.is_empty(): return _fail(ERR_INVALID_DATA, problem)
	glossary.entries = entries
	return sync_resource()

func remove_entry(name: String) -> Error:
	if read_only: return _fail(ERR_UNAVAILABLE, "This glossary remains read-only.")
	for key: String in glossary.entries.keys():
		if key == name or (glossary.entries[key] is String and glossary.entries[key] == name): glossary.entries.erase(key)
	return sync_resource()

func save_file(file_path: String = "") -> Error:
	var target := file_path if not file_path.is_empty() else path
	if workspace != null and workspace.content_path(target).is_empty(): return _fail(ERR_FILE_BAD_PATH, "Save inside the content root without symbolic links.")
	return super.save_file(file_path)
