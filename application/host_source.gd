extends RefCounted
const Config = preload("res://application/project_config.gd")
const Data = preload("res://application/variable_document.gd")

static func needs_native(source: String, workspace: RefCounted) -> bool:
	if workspace == null: return false
	if RegEx.create_from_string('(?m)^\\s*(?:do\\s|\\[signal(?:\\s|\\]))').search(source): return true
	var path: String = workspace.root_path.path_join("project.godot")
	if not FileAccess.file_exists(path): return false
	var config := Config.inspect(FileAccess.get_file_as_string(path))
	if config.has("error"): return false
	# An unrelated target Autoload must stay inert during ordinary text/data preview.
	# Native host execution is selected by actual Call/Signal content or extensions.
	var folder: String = str(config.entries.get("dialogic/extensions_folder", {}).get("value", "res://addons/dialogic_additions/"))
	var absolute: String = workspace.resolve_content_path(folder.trim_suffix("/"))
	if not absolute.is_empty() and DirAccess.dir_exists_absolute(absolute):
		for child: String in DirAccess.get_directories_at(absolute):
			if FileAccess.file_exists(absolute.path_join(child).path_join("index.gd")): return true
	return false

static func validate(source: String, workspace: RefCounted) -> Dictionary:
	var issues: Array[Dictionary] = []
	var diagnostics: Array[String] = []
	var config := Config.inspect(FileAccess.get_file_as_string(workspace.root_path.path_join("project.godot"))) if FileAccess.file_exists(workspace.root_path.path_join("project.godot")) else {"entries":{}}
	if source.to_utf8_buffer().size() > 4 * 1024 * 1024 or source.to_utf8_buffer().has(0): diagnostics.append("Timeline must contain at most 4 MiB of UTF-8 text without NUL.")
	if config.has("error"): diagnostics.append("Target project configuration is invalid.")
	var line_number := 0
	var event_count := 0
	for raw: String in source.split("\n"):
		line_number += 1
		var text := raw.strip_edges()
		if text.is_empty() or text.begins_with("#"): continue
		event_count += 1
		var problem := ""
		if text.begins_with("do "):
			var syntax := RegEx.create_from_string('^do\\s+([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*)\\.([A-Za-z_][A-Za-z0-9_]*)\\((.*)\\)\\s*$').search(text)
			if syntax == null: problem = "Use native do Autoload.method(arguments) syntax."
			else:
				var singleton := syntax.get_string(1).get_slice(".", 0)
				var target := str(config.get("entries", {}).get("autoload/" + singleton, {}).get("value", "")).trim_prefix("*")
				if singleton != "Dialogic" and (target.is_empty() or workspace.resolve_content_path(target).is_empty() or not FileAccess.file_exists(workspace.resolve_content_path(target))): problem = "Missing target autoload: " + singleton
		elif text == "[signal]" or text.begins_with("[signal ") or text.begins_with("[signal\t"):
			if not text.ends_with("]"): problem = "Signal shortcode is not closed."
			else:
				var syntax_problem := signal_syntax(text)
				if not syntax_problem.is_empty():
					diagnostics.append("Line %d: %s" % [line_number, syntax_problem]); issues.append({"line":line_number,"column":1,"message":syntax_problem}); continue
				var event := DialogicSignalEvent.new()
				event.from_text(text)
				if event.argument_type not in [0, 1]: problem = "Signal argument type must be String or Dictionary."
				elif event.argument_type == 1:
					var json := JSON.new()
					if json.parse(str(event.argument)) != OK or not json.data is Dictionary: problem = "Dictionary Signal requires a valid JSON object."
		if not problem.is_empty():
			diagnostics.append("Line %d: %s" % [line_number, problem])
			issues.append({"line":line_number, "column":1, "message":problem})
	return {"supported":diagnostics.is_empty(), "diagnostics":diagnostics, "issues":issues, "event_count":event_count, "narration_count":event_count, "comment_count":0, "character_text_count":0, "character_event_count":0, "native_project":true}

static func signal_syntax(text: String) -> String:
	var tail := text.trim_prefix("[signal").trim_suffix("]")
	var regex := RegEx.new()
	regex.compile(r'(?<parameter>[^\s=]*)\s*=\s*"(?<value>(\{[^}]*\}|\[[^]]*\]|([^"]|\\")*|))(?<!\\)\"')
	# Use the fixed Alpha 20 grammar, but require complete and unique parameters.
	var native := DialogicSignalEvent.new()
	var seen := {}
	var cursor := 0
	for found: RegExMatch in regex.search_all(tail):
		if not tail.substr(cursor, found.get_start() - cursor).strip_edges().is_empty(): return "Malformed Signal parameter. Use key=\"value\"."
		var key := found.get_string("parameter")
		if not key in ["arg", "arg_type"] or seen.has(key): return "Unknown or duplicate Signal parameter: " + key
		seen[key] = true; cursor = found.get_end()
	if not tail.substr(cursor).strip_edges().is_empty(): return "Malformed Signal parameter. Use key=\"value\"."
	var parameters := native.parse_shortcode_parameters(text)
	if parameters.has("arg_type") and not str(parameters.arg_type).to_lower() in ["0", "1", "string", "dict", "dictionary"]: return "Signal argument type must be String or Dictionary."
	return ""
