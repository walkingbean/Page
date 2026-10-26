class_name ContentWorkspace
extends RefCounted

## Content res:// paths belong to root_path, never to this editor's own res://.
## Workspace discovery never rewrites project.godot or Dialogic global metadata.
const CHARACTER_DOCUMENT = preload("res://application/character_document.gd")
const MAX_PNG_BYTES: int = 32 * 1024 * 1024
const MAX_PNG_DIMENSION: int = 8192
const MAX_SCAN_ENTRIES: int = 20000
const SKIP_DIRECTORIES: Array[String] = [".godot", ".git", ".svn", "addons"]

var root_path: String = ""
var variable_document: RefCounted = null
var style_catalog: RefCounted
var text_settings: RefCounted
var characters: Dictionary = {}
var timelines: Array[String] = []
var diagnostics: Array[String] = []
var last_error: String = ""
var _scanned_entries: int = 0
var _scan_complete: bool = true


func open_root(absolute_path: String) -> Error:
	last_error = ""
	if not absolute_path.is_absolute_path() or absolute_path.begins_with("res://") or absolute_path.begins_with("user://"):
		return _fail(ERR_INVALID_PARAMETER, "Choose an absolute content folder path.")
	var candidate: String = absolute_path.simplify_path().trim_suffix("/")
	if candidate.is_empty() or not DirAccess.dir_exists_absolute(candidate) or _has_link_component(candidate):
		return _fail(ERR_FILE_BAD_PATH, "The content folder must exist and must not contain symbolic links in its path.")
	root_path = candidate
	return refresh()


func refresh() -> Error:
	last_error = ""
	if root_path.is_empty() or not DirAccess.dir_exists_absolute(root_path) or _has_link_component(root_path):
		characters.clear()
		timelines.clear()
		style_catalog = null
		text_settings = null
		diagnostics.assign(["The content folder is unavailable; character references have been disabled."])
		return _fail(ERR_FILE_BAD_PATH, diagnostics[0])
	characters.clear()
	timelines.clear()
	diagnostics.clear()
	style_catalog = load("res://application/style_catalog.gd").new()
	style_catalog.refresh(self)
	text_settings = style_catalog.settings
	diagnostics.append_array(style_catalog.diagnostics)
	_scanned_entries = 0
	_scan_complete = true
	var paths: Array[String] = []
	_scan(root_path, paths)
	paths.sort()
	var folded_ids: Dictionary = {}
	for absolute: String in paths:
		if absolute.get_extension().to_lower() == "dtl":
			timelines.append(absolute)
			continue
		var identifier: String = absolute.get_file().get_basename()
		var document = CHARACTER_DOCUMENT.new()
		var error: Error = document.open_file(absolute, self)
		var issues: Array[String] = []
		if error != OK:
			issues.append(document.last_error)
		else:
			issues.assign(document.diagnostics)
		if not valid_identifier(identifier):
			issues.append("Character filename contains reserved or unsafe identifier characters.")
		var entry: Dictionary = {"path": absolute, "resource": document.character if error == OK else null, "supported": error == OK and not document.read_only and issues.is_empty(), "diagnostics": issues, "portrait_path": document.portrait_path if error == OK else ""}
		var folded: String = identifier.to_lower()
		if folded_ids.has(folded):
			var previous_id: String = folded_ids[folded]
			var message: String = "Ambiguous character identifier '%s': %s and %s. Rename one file (case-only changes are insufficient)." % [identifier, content_path(characters[previous_id]["path"]), content_path(absolute)]
			characters[previous_id]["supported"] = false
			characters[previous_id]["diagnostics"].append(message)
			entry["supported"] = false
			entry["diagnostics"].append(message)
			diagnostics.append(message)
		else:
			folded_ids[folded] = identifier
		if not characters.has(identifier):
			characters[identifier] = entry
		for issue: String in issues:
			diagnostics.append(content_path(absolute) + ": " + issue)
	if not _scan_complete:
		var message: String = "Content scan was incomplete; character references are disabled until every content folder can be scanned."
		diagnostics.append(message)
		for identifier: String in characters:
			characters[identifier]["supported"] = false
			characters[identifier]["diagnostics"].append(message)
	return OK


func has_character(identifier: String) -> bool:
	return characters.has(identifier) and characters[identifier]["supported"]


func get_character(identifier: String) -> DialogicCharacter:
	if not has_character(identifier):
		return null
	return characters[identifier]["resource"]


func get_character_error(identifier: String) -> String:
	if not characters.has(identifier):
		return "Character '%s' was not found in the content folder." % identifier
	return "\n".join(characters[identifier]["diagnostics"])


func runtime_characters() -> Dictionary:
	var result: Dictionary = {}
	for identifier: String in characters:
		if has_character(identifier):
			var original: DialogicCharacter = characters[identifier]["resource"]
			var clone: DialogicCharacter = original.duplicate(true)
			result[identifier] = clone
	return result


func timeline_paths() -> Array[String]:
	return timelines.duplicate()


func resolve_content_path(logical_path: String) -> String:
	if root_path.is_empty() or not DirAccess.dir_exists_absolute(root_path) or not logical_path.begins_with("res://"):
		return ""
	var relative: String = logical_path.trim_prefix("res://")
	if relative.contains("\\") or relative.contains(":") or relative.to_utf8_buffer().has(0) or relative.begins_with("/"):
		return ""
	for part: String in relative.split("/"):
		if part in ["", ".", ".."]:
			return ""
	var absolute: String = root_path.path_join(relative).simplify_path()
	if not _inside_root(absolute) or _has_link_component(absolute):
		return ""
	return absolute


func content_path(absolute_path: String) -> String:
	if not absolute_path.is_absolute_path() or absolute_path.begins_with("res://") or absolute_path.begins_with("user://") or absolute_path.contains("\\"):
		return ""
	for part: String in absolute_path.split("/"):
		if part == "..":
			return ""
	var absolute: String = absolute_path.simplify_path()
	if root_path.is_empty() or not DirAccess.dir_exists_absolute(root_path) or not _inside_root(absolute) or _has_link_component(absolute):
		return ""
	return "res://" + absolute.substr(root_path.length()).trim_prefix("/")


func import_portrait(absolute_png: String) -> String:
	last_error = ""
	if root_path.is_empty() or not absolute_png.is_absolute_path() or absolute_png.begins_with("res://") or absolute_png.begins_with("user://"):
		last_error = "Choose a content folder and an absolute PNG file path."
		return ""
	var problem: String = validate_png(absolute_png)
	if not problem.is_empty():
		last_error = problem
		return ""
	var directory: String = resolve_content_path("res://portraits")
	if directory.is_empty():
		last_error = "The portraits folder must not be a symbolic link."
		return ""
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if mkdir_error != OK:
		last_error = "Could not create the portraits folder (error %d)." % mkdir_error
		return ""
	var base: String = absolute_png.get_file().get_basename().validate_filename()
	if base.is_empty() or base == "." or base == "..":
		base = "portrait"
	var destination: String = directory.path_join(base + ".png")
	var suffix: int = 2
	while FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination) or _has_link_component(destination):
		destination = directory.path_join("%s_%d.png" % [base, suffix])
		suffix += 1
		if suffix > 10000:
			last_error = "No unused portrait filename is available."
			return ""
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(absolute_png)
	# Revalidate a snapshot; the source could have changed after the first read.
	if bytes.size() > MAX_PNG_BYTES or not _valid_png_bytes(bytes).is_empty():
		last_error = "The selected PNG changed or is no longer readable."
		return ""
	if FileAccess.file_exists(destination) or _has_link_component(destination):
		last_error = "The portrait destination appeared during import; it was not overwritten."
		return ""
	var output: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		last_error = "Could not create the portrait copy."
		return ""
	var stored: bool = output.store_buffer(bytes)
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if not stored or write_error != OK or FileAccess.get_file_as_bytes(destination) != bytes:
		DirAccess.remove_absolute(destination)
		last_error = "Could not verify the portrait copy."
		return ""
	return content_path(destination)


static func validate_png(absolute_png: String) -> String:
	if absolute_png.get_extension().to_lower() != "png":
		return "Portraits must be PNG files."
	var input: FileAccess = FileAccess.open(absolute_png, FileAccess.READ)
	if input == null:
		return "Portrait PNG is missing or unreadable: " + absolute_png
	if input.get_length() > MAX_PNG_BYTES:
		input.close()
		return "Portrait PNG exceeds the 32 MiB limit."
	var bytes: PackedByteArray = input.get_buffer(input.get_length())
	input.close()
	return _valid_png_bytes(bytes)


static func _valid_png_bytes(bytes: PackedByteArray) -> String:
	var signature: PackedByteArray = PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	if bytes.size() < 33 or bytes.slice(0, 8) != signature or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return "Portrait file is not a valid PNG."
	var width: int = (int(bytes[16]) << 24) | (int(bytes[17]) << 16) | (int(bytes[18]) << 8) | int(bytes[19])
	var height: int = (int(bytes[20]) << 24) | (int(bytes[21]) << 16) | (int(bytes[22]) << 8) | int(bytes[23])
	if width < 1 or height < 1 or width > MAX_PNG_DIMENSION or height > MAX_PNG_DIMENSION or width * height > 16 * 1024 * 1024:
		return "Portrait PNG exceeds 8192 pixels per side or 16 megapixels."
	var image: Image = Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.is_empty():
		return "Portrait PNG cannot be decoded."
	return ""


static func valid_identifier(identifier: String) -> bool:
	if identifier.is_empty() or identifier in ["_", "--All--"] or identifier != identifier.strip_edges():
		return false
	for index: int in identifier.length():
		var ch: String = identifier[index]
		if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127 or ch in ["/", "\\", ":", "\"", "'", "{", "}", "[", "]", "(", ")"]:
			return false
	return true


func _inside_root(absolute: String) -> bool:
	var base: String = root_path.to_lower() if OS.get_name() == "Windows" else root_path
	var candidate: String = absolute.to_lower() if OS.get_name() == "Windows" else absolute
	return candidate == base or candidate.begins_with(base + "/")


static func _has_link_component(absolute: String) -> bool:
	var current: String = absolute.simplify_path()
	while not current.is_empty():
		var parent: String = current.get_base_dir()
		if parent == current:
			break
		var directory: DirAccess = DirAccess.open(parent)
		if directory != null and directory.is_link(current.get_file()):
			return true
		current = parent
	return false


func _scan(directory_path: String, found: Array[String], depth: int = 0) -> void:
	if not _scan_complete:
		return
	if depth > 64:
		diagnostics.append("Workspace folder nesting exceeds 64 levels; choose a smaller content folder.")
		_scan_complete = false
		return
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		diagnostics.append("Could not read folder: " + directory_path)
		_scan_complete = false
		return
	if directory.list_dir_begin() != OK:
		diagnostics.append("Could not list folder: " + directory_path)
		_scan_complete = false
		return
	var name: String = directory.get_next()
	while not name.is_empty():
		_scanned_entries += 1
		if _scanned_entries > MAX_SCAN_ENTRIES:
			diagnostics.append("Workspace scan stopped at 20000 entries; choose a smaller content folder.")
			_scan_complete = false
			break
		var path: String = directory_path.path_join(name)
		if directory.is_link(name):
			diagnostics.append("Skipped symbolic link: " + path)
		elif directory.current_is_dir():
			if not name in SKIP_DIRECTORIES:
				_scan(path, found, depth + 1)
				if not _scan_complete:
					break
		elif name.get_extension().to_lower() in ["dch", "dtl"]:
			found.append(path)
		name = directory.get_next()
	directory.list_dir_end()


func _fail(error: Error, message: String) -> Error:
	last_error = message
	return error


func style_error(name_value: String) -> String:
	return style_catalog.error_for(name_value) if style_catalog != null else ("" if name_value.is_empty() else "Choose a content folder containing this style.")

func import_text_asset(absolute_path: String) -> String:
	last_error = ""
	if absolute_path.get_extension().to_lower() == "png": return import_portrait(absolute_path)
	if not absolute_path.is_absolute_path() or _has_link_component(absolute_path) or not absolute_path.get_extension().to_lower() in ["ttf", "otf"]:
		last_error = "Choose a regular TTF, OTF or PNG file."; return ""
	var bytes := FileAccess.get_file_as_bytes(absolute_path)
	if bytes.is_empty() or bytes.size() > 32 * 1024 * 1024:
		last_error = "Font file must be nonempty and at most 32 MiB."; return ""
	var font := FontFile.new()
	if font.load_dynamic_font(absolute_path) != OK: last_error = "The selected font could not be decoded."; return ""
	var folder := resolve_content_path("res://fonts")
	if folder.is_empty() or DirAccess.make_dir_recursive_absolute(folder) != OK: last_error = "Cannot create the content font folder."; return ""
	var basename := absolute_path.get_file().get_basename().validate_filename()
	var suffix := absolute_path.get_extension().to_lower()
	var destination := folder.path_join(basename + "." + suffix)
	var index := 1
	while FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination) or _has_link_component(destination):
		index += 1
		if index > 10000: last_error = "No unused font filename is available."; return ""
		destination = folder.path_join(basename + "_" + str(index) + "." + suffix)
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null: last_error = "Cannot write the imported font."; return ""
	file.store_buffer(bytes); file.flush(); var error := file.get_error(); file.close()
	if error != OK or FileAccess.get_file_as_bytes(destination) != bytes:
		DirAccess.remove_absolute(destination); last_error = "Font copy verification failed."; return ""
	return content_path(destination)
