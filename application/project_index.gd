extends RefCounted

const Data = preload("res://application/variable_document.gd")
const TEXT := ["gd", "tscn", "tres", "dtl", "dch", "cfg", "godot", "gdshader", "gdshaderinc", "import", "json"]
var workspace: RefCounted
var resources: Dictionary = {}
var uids: Dictionary = {}
var references: Array[Dictionary] = []
var diagnostics: Array[String] = []
var uncertain: Array[String] = []
var complete := true
var _count := 0
var _case_paths: Dictionary = {}

func scan(target_workspace: RefCounted) -> Dictionary:
	workspace = target_workspace
	resources.clear(); uids.clear(); references.clear(); diagnostics.clear(); uncertain.clear()
	complete = true; _count = 0; _case_paths.clear()
	_scan_directory(workspace.root_path, 0)
	for logical: String in resources:
		var entry: Dictionary = resources[logical]
		var uid: String = entry.uid
		if uid.is_empty(): continue
		if uids.has(uid):
			diagnostics.append("Duplicate UID %s: %s and %s" % [uid, uids[uid], logical])
			uids[uid] = ""
		else: uids[uid] = logical
	for logical: String in resources:
		if resources[logical].has("text"): _references(logical, resources[logical].text)
	for reference: Dictionary in references:
		if reference.target.begins_with("uid://"): reference.resolved = uids.get(reference.target, "")
		else: reference.resolved = reference.target
		if reference.resolved.is_empty() or (not resources.has(reference.resolved) and not reference.resolved.begins_with("res://addons/dialogic/") and not DirAccess.dir_exists_absolute(workspace.resolve_content_path(reference.resolved.trim_suffix("/")))):
			diagnostics.append("Missing or ambiguous dependency: %s:%d → %s" % [reference.source, reference.line, reference.target])
	return {"resources":resources, "uids":uids, "references":references, "diagnostics":diagnostics, "uncertain":uncertain, "complete":complete}

func _scan_directory(absolute: String, depth: int) -> void:
	if depth > 64: _incomplete("Folder depth exceeds 64: " + absolute); return
	if Data._has_link_component(absolute): _incomplete("Symbolic link: " + absolute); return
	var directory := DirAccess.open(absolute)
	if directory == null: _incomplete("Cannot read folder: " + absolute); return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		_count += 1
		if _count > 20000: _incomplete("Project scan exceeds 20000 entries."); break
		var path := absolute.path_join(name)
		var logical: String = workspace.content_path(path)
		if directory.is_link(name): _incomplete("Symbolic link skipped: " + path)
		elif directory.current_is_dir():
			if not name in [".godot", ".git", ".svn"] and logical != "res://addons/dialogic": _scan_directory(path, depth + 1)
		elif not name.contains(".editor-") and not name.ends_with(".bak"):
			if not logical.is_empty(): _add(logical, path)
		name = directory.get_next()
	directory.list_dir_end()

func _incomplete(message: String) -> void:
	complete = false; diagnostics.append(message)

func _add(logical: String, absolute: String) -> void:
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null: _incomplete("Unreadable resource: " + logical); return
	var item := {"path":logical, "absolute":absolute, "kind":logical.get_extension().to_lower(), "bytes":file.get_length(), "uid":""}
	var lower := logical.to_lower()
	if _case_paths.has(lower): diagnostics.append("Case collision: " + logical + " / " + _case_paths[lower])
	_case_paths[lower] = logical
	if item.kind in TEXT and file.get_length() <= 4 * 1024 * 1024:
		var bytes := file.get_buffer(file.get_length())
		if not Data._is_utf8(bytes) or bytes.has(0): uncertain.append("Non-UTF-8 text resource: " + logical)
		else:
			var text := bytes.get_string_from_utf8()
			item["text"] = text
			if item.kind in ["tscn", "tres"]:
				var found := RegEx.create_from_string('^\\[gd_(?:scene|resource)[^\\r\\n]*uid="(uid://[^"\\r\\n]+)"').search(text)
				if found: item.uid = found.get_string(1)
	elif item.kind in ["scn", "res"]: uncertain.append("Binary resource needs native dependency inspection: " + logical)
	elif item.kind in TEXT: uncertain.append("Text resource exceeds 4 MiB: " + logical)
	var import_path := absolute + ".import"
	if FileAccess.file_exists(import_path) and not Data._has_link_component(import_path):
		var found := RegEx.create_from_string('(?m)^uid\\s*=\\s*"(uid://[^"\\r\\n]+)"').search(FileAccess.get_file_as_string(import_path))
		if found: item.uid = found.get_string(1)
	var sidecar := absolute + ".uid"
	if FileAccess.file_exists(sidecar) and not Data._has_link_component(sidecar): item.uid = FileAccess.get_file_as_string(sidecar).strip_edges()
	if not item.uid.is_empty() and not valid_uid(item.uid): diagnostics.append("Invalid UID: " + logical); item.uid = ""
	if item.kind == "uid" and not FileAccess.file_exists(absolute.trim_suffix(".uid")): diagnostics.append("Orphan UID sidecar: " + logical)
	resources[logical] = item

static func valid_uid(uid: String) -> bool:
	var id := ResourceUID.text_to_id(uid)
	return id != ResourceUID.INVALID_ID and ResourceUID.id_to_text(id) == uid

func _references(logical: String, text: String) -> void:
	var offset := 0
	var line_number := 0
	var native_index := RegEx.create_from_string('(?m)^\\s*extends\\s+DialogicIndexer\\s*(?:#.*)?$').search(text) != null
	var reassigned_folder := RegEx.create_from_string('(?m)\\bthis_folder\\s*(?::[^=\\n]+)?(?:=|\\+=|:=)|^\\s*func\\s+\\w+\\([^\\n)]*\\bthis_folder\\b').search(text) != null
	for line: String in text.split("\n"):
		line_number += 1
		var physical_length := line.length() + 1
		var stripped := line.strip_edges()
		if stripped.begins_with("#") or stripped.begins_with(";"): offset += physical_length; continue
		if logical.get_extension() == "gd": line = _without_comment(line)
		# Quoted native paths are concrete references; arbitrary free text is not.
		for found: RegExMatch in RegEx.create_from_string('["\'](\\*?(?:res|uid)://[^"\'\\r\\n]+)["\']').search_all(line):
			var raw_path := found.get_string(1)
			var path := raw_path.trim_prefix("*")
			if logical.get_extension() in ["tscn", "tres"] and stripped.begins_with("[gd_") and path.begins_with("uid://"): continue
			references.append({"source":logical, "target":path, "line":line_number, "start":offset + found.get_start(1) + (1 if raw_path.begins_with("*") else 0), "end":offset + found.get_end(1), "kind":"path"})
		if logical.get_extension() == "gd":
			# DialogicIndexer defines this_folder as its script's parent directory.
			# Preserve the whole expression span so a move can replace it with an
			# absolute native path without relying on the original folder.
			for found: RegExMatch in RegEx.create_from_string('(?<![A-Za-z0-9_.])this_folder\\.path_join\\s*\\(').search_all(line):
				if not _is_code_at(line, found.get_start()): continue
				var literal := RegEx.create_from_string('^\\s*(["\'])([^"\'\\\\\\r\\n]*)\\1\\s*\\)').search(line.substr(found.get_end()))
				var valid := native_index and not reassigned_folder and literal != null
				var relative := literal.get_string(2) if literal != null else ""
				var expression_end := found.get_end() + literal.get_end() if literal != null else line.length()
				valid = valid and not relative.is_empty() and not relative.begins_with("/") and not relative.contains("://") and not line.substr(expression_end).strip_edges().begins_with(".")
				if valid:
					var path := logical.get_base_dir().path_join(relative).simplify_path()
					if workspace.resolve_content_path(path).is_empty(): valid = false
					else: references.append({"source":logical, "target":path, "line":line_number, "start":offset + found.get_start(), "end":offset + expression_end, "kind":"index_path"})
				if not valid: uncertain.append("Dynamic extension index path: " + logical + ":" + str(line_number))
			for found: RegExMatch in RegEx.create_from_string('(?:load|preload|load_threaded_request)\\s*\\(\\s*([^\\n]*)').search_all(line):
				var expression := found.get_string(1)
				if RegEx.create_from_string('^["\'](?:res|uid)://[^"\']+["\']\\s*\\)').search(expression) == null: uncertain.append("Dynamic resource expression: " + logical + ":" + str(line_number))
		if logical.get_extension() == "dtl": _dialogic_references(logical, line, offset, line_number)
		offset += physical_length

func _dialogic_references(logical: String, line: String, offset: int, line_number: int) -> void:
	var stripped := line.strip_edges()
	var timeline_start := line.find("jump ")
	if timeline_start >= 0 and stripped.begins_with("jump "):
		var target := stripped.trim_prefix("jump ").strip_edges()
		var slash := target.rfind("/")
		if slash >= 0:
			var identifier := target.left(slash)
			var start := line.find(identifier, timeline_start + 5)
			_add_content_reference(logical, identifier, "dtl", offset + start, offset + start + identifier.length(), line_number, false)
		return
	var found := RegEx.create_from_string('^(?:\\s*(?:join|leave)\\s+|\\s*)("[^"\\n]+"|[^\\s:()]+)(?=\\s*(?:[:(]|\\bat\\b|$))').search(line)
	if found == null: return
	var raw := found.get_string(1)
	var identifier := raw.trim_prefix('"').trim_suffix('"')
	if identifier in ["--All--", "_", "return"]: return
	_add_content_reference(logical, identifier, "dch", offset + found.get_start(1), offset + found.get_end(1), line_number, raw.begins_with('"'))

func _add_content_reference(logical: String, identifier: String, extension: String, start: int, end: int, line_number: int, quoted: bool) -> void:
	var matches: Array[String] = []
	for path: String in resources:
		if path.get_extension() == extension and path.get_file().get_basename() == identifier: matches.append(path)
	if matches.size() == 1: references.append({"source":logical, "target":matches[0], "line":line_number, "start":start, "end":end, "kind":extension, "quoted":quoted})
	elif matches.size() > 1: diagnostics.append("Ambiguous content identifier: " + logical + ":" + str(line_number) + " " + identifier)

func dependencies(logical: String) -> Array[Dictionary]:
	return references.filter(func(item: Dictionary): return item.source == logical)

func incoming(logical: String) -> Array[Dictionary]:
	return references.filter(func(item: Dictionary): return item.get("resolved", "") == logical)

static func _is_code_at(line: String, position: int) -> bool:
	var quote := ""
	var escaped := false
	for i in position:
		if escaped: escaped = false; continue
		if not quote.is_empty():
			if line[i] == "\\": escaped = true
			elif line[i] == quote: quote = ""
		elif line[i] in ['"', "'"]: quote = line[i]
	return quote.is_empty()

static func _without_comment(line: String) -> String:
	var quote := ""
	var escaped := false
	for i in line.length():
		if escaped: escaped = false; continue
		if not quote.is_empty():
			if line[i] == "\\": escaped = true
			elif line[i] == quote: quote = ""
		elif line[i] in ['"', "'"]: quote = line[i]
		elif line[i] == "#": return line.left(i)
	return line
