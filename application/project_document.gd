extends "res://application/timeline_document.gd"

## Target configuration is text, never ProjectSettings for the editor process.
const Data = preload("res://application/variable_document.gd")
var target_path := ""
var entries: Dictionary = {}

func get_file_extension() -> String:
	return "godot"

func open_project(target_workspace: RefCounted) -> Error:
	workspace = target_workspace
	target_path = workspace.root_path.path_join("project.godot")
	if workspace.content_path(target_path).is_empty(): return _fail(ERR_FILE_BAD_PATH, "Choose a regular target project folder.")
	if FileAccess.file_exists(target_path):
		var result := open_file(target_path)
		if result != OK: return result
	else:
		new_document()
		content = "config_version=5\n\n[application]\nconfig/name=\"Dialogic Project\"\n"
		_original_content = content
	entries = inspect(content).get("entries", {})
	return OK

func validate_content(text: String) -> Dictionary:
	var parsed := inspect(text)
	return {"supported":not parsed.has("error"), "diagnostics":[parsed.error] if parsed.has("error") else []}

func save_file(_file_path: String = "") -> Error:
	if workspace == null or workspace.content_path(target_path).is_empty(): return _fail(ERR_FILE_BAD_PATH, "The project path changed.")
	var error := super.save_file(target_path)
	if error == OK: entries = inspect(content).get("entries", {})
	return error

func value(key: String, fallback: Variant = null) -> Variant:
	return inspect(content).get("entries", {}).get(key, {}).get("value", fallback)

func set_value(key: String, new_value: Variant) -> Error:
	if read_only: return _fail(ERR_UNAVAILABLE, "Configuration is read-only.")
	if not valid_key(key): return _fail(ERR_INVALID_PARAMETER, "Use section/key with a valid native key.")
	if key == "autoload/Dialogic" and new_value != "*res://addons/dialogic/Core/DialogicGameHandler.gd": return _fail(ERR_INVALID_PARAMETER, "Dialogic is reserved for the fixed native handler.")
	var literal := var_to_str(new_value)
	if Data._has_constructor(literal): return _fail(ERR_INVALID_DATA, "Object and resource constructors must be edited in their native source, without evaluation here.")
	var checked := Data._parse_value(literal)
	if checked.has("error"): return _fail(ERR_INVALID_DATA, checked.error)
	return set_literal(key, literal)

func set_literal(key: String, literal: String) -> Error:
	if read_only or not valid_key(key): return _fail(ERR_INVALID_PARAMETER, "Invalid or read-only configuration key.")
	var check := inspect("[value]\nentry=" + literal + "\n")
	if check.has("error") or check.entries.size() != 1: return _fail(ERR_INVALID_DATA, "Invalid native value.")
	var parsed := inspect(content)
	if parsed.has("error"): return _fail(ERR_INVALID_DATA, parsed.error)
	var next := content
	if parsed.entries.has(key):
		var span: Dictionary = parsed.entries[key]
		next = content.left(span.start) + literal + content.substr(span.end)
	else:
		var section := key.get_slice("/", 0)
		var native_key := key.substr(section.length() + 1)
		var statement := native_key + "=" + literal + "\n"
		if parsed.sections.has(section):
			var at: int = parsed.sections[section]
			next = content.left(at) + ("\n" if at > 0 and content[at - 1] != "\n" else "") + statement + content.substr(at)
		else: next += "\n[" + section + "]\n" + statement
	set_content(next)
	entries = inspect(content).get("entries", {})
	return OK

func remove_value(key: String) -> Error:
	if read_only: return _fail(ERR_UNAVAILABLE, "Configuration is read-only.")
	var parsed := inspect(content)
	if parsed.has("error"): return _fail(ERR_INVALID_DATA, parsed.error)
	if parsed.entries.has(key):
		var span: Dictionary = parsed.entries[key]
		set_content(content.left(span.statement) + content.substr(span.next))
	entries = inspect(content).get("entries", {})
	return OK

func set_autoload(singleton: String, logical: String, global_name: bool = true) -> Error:
	if not singleton.is_valid_identifier() or singleton == "Dialogic" or ClassDB.class_exists(singleton): return _fail(ERR_INVALID_PARAMETER, "Choose a unique host name; Dialogic and engine classes are reserved.")
	if workspace == null or workspace.resolve_content_path(logical).is_empty() or not FileAccess.file_exists(workspace.resolve_content_path(logical)) or not logical.get_extension() in ["gd", "tscn", "scn"]: return _fail(ERR_FILE_BAD_PATH, "Autoload needs an existing target script or scene.")
	return set_value("autoload/" + singleton, ("*" if global_name else "") + logical)

func reorder_autoload(singleton: String, offset: int) -> Error:
	var parsed := inspect(content)
	if parsed.has("error") or read_only: return _fail(ERR_INVALID_DATA, "Invalid configuration.")
	var list: Array = parsed.entries.keys().filter(func(key: String): return key.begins_with("autoload/"))
	var index := list.find("autoload/" + singleton)
	if index < 0 or index + offset < 0 or index + offset >= list.size(): return ERR_INVALID_PARAMETER
	var a: Dictionary = parsed.entries[list[index]]
	var b: Dictionary = parsed.entries[list[index + offset]]
	if a.statement > b.statement:
		var swap := a; a = b; b = swap
	var left := content.substr(a.statement, a.next - a.statement)
	var right := content.substr(b.statement, b.next - b.statement)
	set_content(content.left(a.statement) + right + content.substr(a.next, b.statement - a.next) + left + content.substr(b.next))
	entries = inspect(content).get("entries", {})
	return OK

static func valid_key(key: String) -> bool:
	return preload("res://application/project_config.gd").valid_key(key)

static func inspect(text: String) -> Dictionary:
	return preload("res://application/project_config.gd").inspect(text)
