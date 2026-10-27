extends "res://application/timeline_document.gd"

## Native extension sources are edited without instantiating their scripts.
## Compilation happens in the isolated target process, not the editor.
var extension := "gd"
const ALLOWED := ["gd", "tscn", "tres", "dtl", "dch", "cfg", "godot", "gdshader", "gdshaderinc", "json", "txt"]

func get_file_extension() -> String:
	return extension

func open_source(target_workspace: RefCounted, logical: String) -> Error:
	var absolute: String = target_workspace.resolve_content_path(logical)
	if absolute.is_empty() or logical.begins_with("res://addons/dialogic/"): return _fail(ERR_FILE_BAD_PATH, "Choose a target source outside the fixed Dialogic dependency.")
	if not logical.get_extension() in ALLOWED: return _fail(ERR_UNAVAILABLE, "This resource is not an editable native text file.")
	workspace = target_workspace
	extension = logical.get_extension()
	return open_file(absolute)

func validate_content(text: String) -> Dictionary:
	var problem := ""
	if text.to_utf8_buffer().size() > CODEC.MAX_SOURCE_BYTES or text.to_utf8_buffer().has(0): problem = "Source must be UTF-8 text without NUL, at most 4 MiB."
	if extension == "godot":
		var parsed := preload("res://application/project_document.gd").inspect(text)
		if parsed.has("error"): problem = parsed.error
	return {"supported":problem.is_empty(), "diagnostics":[problem] if not problem.is_empty() else []}

func save_file(file_path: String = "") -> Error:
	var target := file_path if not file_path.is_empty() else path
	if workspace == null or workspace.content_path(target).is_empty() or workspace.content_path(target).begins_with("res://addons/dialogic/"): return _fail(ERR_FILE_BAD_PATH, "Source must remain inside the target project, outside the fixed dependency.")
	return super.save_file(target)
