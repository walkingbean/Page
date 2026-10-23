class_name VariableDocument
extends RefCounted

## Native Alpha 20 variables belong to the selected content root's project.godot.
## Only the variables value is replaced; unrelated configuration remains opaque.
## ConfigFile.parse can construct Objects, so host objects/resources are never
## parsed or instantiated. The variable dictionary only accepts data values.
## References: https://docs.godotengine.org/en/4.7/classes/class_configfile.html
##             https://docs.dialogic.pro/variables.html

const MAX_CONFIG_BYTES: int = 4 * 1024 * 1024
## VariantWriter uses MAX_RECURSION=100; retain a lower bound so preserved
## nested values can be duplicated and serialized without silent truncation.
const MAX_CONFIG_NESTING: int = 64
const UNIX_PLATFORMS = ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD", "macOS", "iOS"]

var root_path: String = ""
var file_path: String = ""
var values: Dictionary = {}
var dirty: bool = false
var read_only: bool = false
var last_error: String = ""
var diagnostics: Array[String] = []
var override_warning: String = ""
var last_backup_path: String = ""

var _saved: Dictionary = {}
var _original_bytes := PackedByteArray()
var _original_text: String = ""
var _expected_hash: String = ""
var _existed: bool = false
var _had_bom: bool = false
var _newline: String = "\n"
var _layout: Dictionary = {}


func open_root(absolute_path: String) -> Error:
	last_error = ""
	if not absolute_path.is_absolute_path() or absolute_path.begins_with("res://") or absolute_path.begins_with("user://"):
		return _fail(ERR_INVALID_PARAMETER, "Choose an absolute content folder for variables.")
	var candidate: String = absolute_path.simplify_path().trim_suffix("/")
	if not _valid_root(candidate):
		return _fail(ERR_FILE_BAD_PATH, "The content folder must be readable and must not contain symbolic links.")
	var target: String = candidate.path_join("project.godot")
	if _has_link_component(target) or DirAccess.dir_exists_absolute(target):
		return _fail(ERR_FILE_BAD_PATH, "The variable configuration must be a regular project.godot file, without symbolic links.")
	var exists: bool = FileAccess.file_exists(target)
	var bytes := PackedByteArray()
	if exists:
		var loaded: Dictionary = _read_bytes(target)
		if loaded["error"] != OK:
			return _fail(loaded["error"], "Could not read project.godot (maximum 4 MiB); the current variable session was retained.")
		bytes = loaded["bytes"]
	var has_bom: bool = bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF
	var payload: PackedByteArray = bytes.slice(3) if has_bom else bytes
	var next_layout: Dictionary = {}
	var next_values: Dictionary = {}
	var next_diagnostics: Array[String] = []
	var next_text: String = ""
	if not _is_utf8(payload) or payload.has(0):
		next_diagnostics.append("project.godot must contain valid UTF-8 without NUL bytes. It remains read-only.")
	else:
		next_text = payload.get_string_from_utf8()
		next_layout = _scan_config(next_text)
		if next_layout.has("error"):
			next_diagnostics.append(next_layout["error"])
		elif next_layout.get("variable_start", -1) >= 0:
			var raw: String = next_text.substr(next_layout["variable_start"], next_layout["variable_end"] - next_layout["variable_start"])
			if _has_constructor(raw):
				next_diagnostics.append("Object and resource constructors are not allowed in editable variable data. The original configuration remains read-only.")
			else:
				var parsed: Dictionary = _parse_value(raw)
				if parsed.has("error") or not parsed.get("value") is Dictionary:
					next_diagnostics.append("dialogic/variables must be a valid native Dictionary. The original configuration remains read-only.")
				else:
					next_values = parsed["value"].duplicate(true)
	# Commit only after path and file IO succeed. Malformed data is visible but protected.
	root_path = candidate
	file_path = target
	values = next_values
	_saved = next_values.duplicate(true)
	diagnostics = next_diagnostics
	read_only = not diagnostics.is_empty()
	dirty = false
	_original_bytes = bytes
	_original_text = next_text
	_expected_hash = _digest(bytes)
	_existed = exists
	_had_bom = has_bom
	_newline = "\r\n" if next_text.contains("\r\n") else "\n"
	_layout = next_layout
	last_backup_path = ""
	_update_override_warning()
	return OK


func refresh() -> Error:
	if dirty:
		return _fail(ERR_BUSY, "Save or discard variable changes before refreshing their configuration.")
	return open_root(root_path)


func discard_changes() -> Error:
	return open_root(root_path)


static func valid_identifier(identifier: String) -> bool:
	return RegEx.create_from_string(r"\A[A-Za-z_][A-Za-z0-9_]*\z").search(identifier) != null


func is_editable(identifier: String) -> bool:
	if read_only or not valid_identifier(identifier) or not values.has(identifier) or not values[identifier] is String:
		return false
	var keys: Array = values.keys()
	var index: int = keys.find(identifier)
	return index >= 0 and keys[index] is String


func add_variable(identifier: String, value: String = "") -> Error:
	return update_variable("", identifier, value)


func set_value(identifier: String, value: String) -> Error:
	return update_variable(identifier if values.has(identifier) else "", identifier, value)


func update_variable(previous: String, identifier: String, value: String) -> Error:
	if read_only or root_path.is_empty():
		return _fail(ERR_UNAVAILABLE, "Select a writable variable configuration before editing.")
	if not valid_identifier(identifier):
		return _fail(ERR_INVALID_PARAMETER, "Variable names must match [A-Za-z_][A-Za-z0-9_]*; names are case-sensitive.")
	if not previous.is_empty() and not is_editable(previous):
		return _fail(ERR_UNAVAILABLE, "Only existing flat String variables with supported names can be edited.")
	if identifier != previous and values.has(identifier):
		return _fail(ERR_ALREADY_EXISTS, "A variable or read-only item already uses that exact name.")
	if not previous.is_empty() and previous != identifier:
		values.erase(previous)
	values[identifier] = value
	_update_dirty()
	last_error = ""
	return OK


func rename_variable(previous: String, identifier: String) -> Error:
	if not is_editable(previous):
		return _fail(ERR_UNAVAILABLE, "Only supported String variables can be renamed.")
	return update_variable(previous, identifier, values[previous])


func remove_variable(identifier: String) -> Error:
	if not is_editable(identifier):
		return _fail(ERR_UNAVAILABLE, "Only supported String variables can be removed.")
	values.erase(identifier)
	_update_dirty()
	last_error = ""
	return OK


func saved_values() -> Dictionary:
	return _saved.duplicate(true)


func runtime_values() -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in _saved:
		if key is String and valid_identifier(key) and _saved[key] is String:
			result[key] = _saved[key]
	return result


func check_current() -> Error:
	last_error = ""
	if not _valid_root(root_path) or _has_link_component(file_path) or DirAccess.dir_exists_absolute(file_path):
		return _fail(ERR_FILE_BAD_PATH, "The variable content folder or configuration path is unavailable or contains a symbolic link.")
	var exists: bool = FileAccess.file_exists(file_path)
	if _existed:
		if not exists:
			return _fail(ERR_BUSY, "project.godot was removed outside this app. Refresh or discard after preserving your draft.")
		var check: Dictionary = _read_bytes(file_path)
		if check["error"] != OK or _digest(check["bytes"]) != _expected_hash:
			return _fail(ERR_BUSY, "project.godot changed or became unreadable outside this app. Refresh or discard after preserving your draft.")
	elif exists:
		return _fail(ERR_ALREADY_EXISTS, "project.godot appeared outside this app. It was not overwritten; resolve the new configuration first.")
	_update_override_warning()
	return OK


func preview_error() -> String:
	if check_current() != OK:
		return last_error
	if read_only:
		return "\n".join(diagnostics)
	if not override_warning.is_empty():
		return override_warning
	if dirty:
		return "Save or discard variable changes before previewing."
	return ""


func save() -> Error:
	last_error = ""
	if read_only:
		return _fail(ERR_UNAVAILABLE, "This variable configuration is read-only and will not be rewritten.")
	var conflict: Error = check_current()
	if conflict != OK:
		return conflict
	var validation: String = _pending_error()
	if not validation.is_empty():
		return _fail(ERR_INVALID_DATA, validation)
	_update_dirty()
	if not dirty and _existed:
		return OK
	var permission_error: Error = _check_write_permissions()
	if permission_error != OK:
		return permission_error
	var serialized: String = var_to_str(values).replace("\n", _newline)
	var next_text: String
	if not _existed:
		next_text = "config_version=5" + _newline + _newline + "[dialogic]" + _newline + "variables=" + serialized + _newline
	elif _layout.get("variable_start", -1) >= 0:
		next_text = _original_text.substr(0, _layout["variable_start"]) + serialized + _original_text.substr(_layout["variable_end"])
	else:
		var insertion: int = _layout.get("dialogic_end", -1)
		if insertion >= 0:
			var before: String = _original_text.substr(0, insertion)
			var separator: String = "" if before.is_empty() or before.ends_with("\n") else _newline
			next_text = before + separator + "variables=" + serialized + _newline + _original_text.substr(insertion)
		else:
			var separator: String = "" if _original_text.is_empty() or _original_text.ends_with("\n") else _newline
			next_text = _original_text + separator + _newline + "[dialogic]" + _newline + "variables=" + serialized + _newline
	var bytes := PackedByteArray([0xEF, 0xBB, 0xBF]) if _had_bom else PackedByteArray()
	bytes.append_array(next_text.to_utf8_buffer())
	if bytes.size() > MAX_CONFIG_BYTES:
		return _fail(ERR_OUT_OF_MEMORY, "The variable configuration exceeds 4 MiB after encoding; reduce the data before saving.")
	var next_layout: Dictionary = _scan_config(next_text)
	if next_layout.has("error"):
		return _fail(ERR_INVALID_DATA, "Could not safely update the original configuration: " + next_layout["error"])
	var mode: int = FileAccess.get_unix_permissions(file_path) if _existed and OS.get_name() in UNIX_PLATFORMS else -1
	var suffix: String = "%s-%s" % [Time.get_ticks_usec(), get_instance_id()]
	var temporary: String = file_path + ".editor-tmp-" + suffix
	if FileAccess.file_exists(temporary) or _has_link_component(temporary):
		return _fail(ERR_ALREADY_EXISTS, "A temporary path already exists; retry saving.")
	var write_error: Error = _write_verified(temporary, bytes, mode)
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return _fail(write_error, "Could not write and verify the temporary configuration; your draft is retained.")
	conflict = check_current()
	if conflict != OK:
		DirAccess.remove_absolute(temporary)
		return conflict
	var backup: String = ""
	if _existed:
		backup = file_path + ".editor-backup-" + suffix + ".bak"
		if FileAccess.file_exists(backup) or _has_link_component(backup):
			DirAccess.remove_absolute(temporary)
			return _fail(ERR_ALREADY_EXISTS, "A recovery path already exists; retry saving.")
		write_error = _write_verified(backup, _original_bytes, mode)
		if write_error != OK:
			DirAccess.remove_absolute(temporary)
			DirAccess.remove_absolute(backup)
			return _fail(write_error, "Could not preserve the original configuration; it was not changed.")
		last_backup_path = backup
		conflict = check_current()
		if conflict != OK:
			DirAccess.remove_absolute(temporary)
			return conflict
	# Keep a verified recovery copy because replacement is not crash-atomic on all platforms.
	var replace_error: Error = DirAccess.rename_absolute(temporary, file_path)
	if replace_error != OK:
		DirAccess.remove_absolute(temporary)
		if not backup.is_empty() and not FileAccess.file_exists(file_path):
			var recovery_error: Error = _write_verified(file_path, _original_bytes, mode)
			if recovery_error != OK:
				return _fail(replace_error, "Replacement and recovery failed. Verified original: " + backup)
		return _fail(replace_error, "Could not replace project.godot. Verified recovery copy: " + backup)
	var verify: Dictionary = _read_bytes(file_path)
	if verify["error"] != OK or verify["bytes"] != bytes:
		return _fail(ERR_FILE_CORRUPT, "The saved configuration could not be verified. Recovery copy: " + backup)
	_original_text = next_text
	_original_bytes = bytes
	_expected_hash = _digest(bytes)
	_layout = next_layout
	_saved = values.duplicate(true)
	_existed = true
	dirty = false
	return OK


func _pending_error() -> String:
	for key: Variant in _saved:
		if not (key is String and valid_identifier(key) and _saved[key] is String):
			if not values.has(key) or var_to_str(values[key]) != var_to_str(_saved[key]):
				return "Unsupported variable data must remain unchanged."
	for key: Variant in values:
		if _saved.has(key) and not (key is String and valid_identifier(key) and _saved[key] is String):
			continue
		if not key is String or not valid_identifier(key) or not values[key] is String:
			return "Only flat String variables with valid ASCII names can be created or edited."
	return ""


func _update_dirty() -> void:
	dirty = var_to_str(values) != var_to_str(_saved)


func _check_write_permissions() -> Error:
	var write_bits: int = FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_WRITE_GROUP | FileAccess.UNIX_WRITE_OTHER
	if OS.get_name() in UNIX_PLATFORMS and (FileAccess.get_unix_permissions(root_path) & write_bits) == 0:
		return _fail(ERR_FILE_NO_PERMISSION, "The content folder is not writable; variable changes are retained.")
	if not _existed:
		return OK
	if OS.get_name() in UNIX_PLATFORMS and (FileAccess.get_unix_permissions(file_path) & write_bits) == 0:
		return _fail(ERR_FILE_NO_PERMISSION, "project.godot is read-only; variable changes are retained.")
	if OS.get_name() == "Windows" and FileAccess.get_read_only_attribute(file_path):
		return _fail(ERR_FILE_NO_PERMISSION, "project.godot has the read-only attribute; variable changes are retained.")
	var writable: FileAccess = FileAccess.open(file_path, FileAccess.READ_WRITE)
	if writable == null:
		return _fail(ERR_FILE_NO_PERMISSION, "project.godot is not writable; variable changes are retained.")
	writable.close()
	return OK


func _update_override_warning() -> void:
	override_warning = ""
	if _layout.get("variable_override", false):
		override_warning = "Platform-specific dialogic/variables overrides require a later version; preview is unavailable."
	var override_path: String = root_path.path_join("override.cfg")
	if _has_link_component(override_path) or DirAccess.dir_exists_absolute(override_path):
		override_warning = "The target override.cfg cannot be safely inspected; preview is unavailable."
		return
	if not FileAccess.file_exists(override_path):
		return
	var result: Dictionary = _read_bytes(override_path)
	if result["error"] != OK or not _is_utf8(result["bytes"]) or result["bytes"].has(0):
		override_warning = "The target override.cfg is unreadable or invalid; preview is unavailable."
		return
	var text: String = result["bytes"].get_string_from_utf8().trim_prefix(String.chr(0xFEFF))
	var layout: Dictionary = _scan_config(text)
	if layout.has("error") or layout.get("variable_start", -1) >= 0 or layout.get("variable_override", false):
		override_warning = "Target variable overrides in override.cfg are outside this version's scope; preview is unavailable."


static func _scan_config(source: String) -> Dictionary:
	var result: Dictionary = {"variable_start": -1, "variable_end": -1, "dialogic_end": -1, "variable_override": false}
	var section: String = ""
	var seen_sections: Dictionary = {}
	var seen_keys: Dictionary = {}
	var index: int = 0
	while index < source.length():
		var statement_start: int = index
		while index < source.length() and source[index] in [" ", "\t", "\r", "\n"]:
			index += 1
		if index >= source.length():
			break
		if source[index] == ";":
			index = _after_line(source, index)
			continue
		if source[index] == "[":
			var header_start: int = index
			var end: int = source.find("]", index + 1)
			var newline: int = source.find("\n", index)
			if end < 0 or (newline >= 0 and newline < end):
				return {"error": "Malformed section header in project.godot; configuration remains read-only."}
			var line_end: int = source.find("\n", end + 1)
			if line_end < 0:
				line_end = source.length()
			var tail: String = source.substr(end + 1, line_end - end - 1).strip_edges()
			if not tail.is_empty() and not tail.begins_with(";"):
				return {"error": "Unexpected content after a section header; configuration remains read-only."}
			if section == "dialogic":
				result["dialogic_end"] = header_start
			section = source.substr(index + 1, end - index - 1).strip_edges()
			if section.is_empty() or seen_sections.has(section):
				return {"error": "Empty or repeated configuration sections cannot be safely updated."}
			seen_sections[section] = true
			index = line_end + 1
			continue
		var key_start: int = index
		var in_quote: bool = false
		var escaped: bool = false
		while index < source.length():
			var character: String = source[index]
			if in_quote:
				if escaped:
					escaped = false
				elif character == "\\":
					escaped = true
				elif character == "\"":
					in_quote = false
			elif character == "\"":
				in_quote = true
			elif character == "=":
				break
			elif character in ["\n", "\r", ";"]:
				return {"error": "A configuration assignment is missing '='; the file remains read-only."}
			index += 1
		if index >= source.length() or in_quote:
			return {"error": "Incomplete configuration assignment; the file remains read-only."}
		var raw_key: String = source.substr(key_start, index - key_start).strip_edges()
		var key_config := ConfigFile.new()
		if raw_key.is_empty() or key_config.parse("[key]\n" + raw_key + "=0\n") != OK or key_config.get_section_keys("key").size() != 1:
			return {"error": "Invalid configuration key; the file remains read-only."}
		var key: String = key_config.get_section_keys("key")[0]
		var identity: String = section + "\n" + key
		if seen_keys.has(identity):
			return {"error": "Duplicate configuration key '%s/%s' cannot be safely updated." % [section, key]}
		seen_keys[identity] = true
		index += 1
		while index < source.length() and source[index] in [" ", "\t", "\r", "\n"]:
			index += 1
		var value_start: int = index
		var span: Dictionary = _value_span(source, index)
		if span.has("error"):
			return span
		var value_end: int = span["end"]
		var raw_value: String = source.substr(value_start, value_end - value_start)
		if raw_value.is_empty():
			return {"error": "A configuration value is missing; the file remains read-only."}
		# Unrelated host objects remain opaque. Their constructors are never called.
		if not _has_constructor(raw_value):
			var parsed: Dictionary = _parse_value(raw_value)
			if parsed.has("error"):
				return {"error": "Invalid native value for '%s/%s'; the file remains read-only." % [section, key]}
		if section == "dialogic":
			if key == "variables":
				result["variable_start"] = value_start
				result["variable_end"] = value_end
			elif key.begins_with("variables."):
				result["variable_override"] = true
		index = span["next"]
		if index <= statement_start:
			return {"error": "Configuration parsing did not advance; the file remains read-only."}
	if section == "dialogic":
		result["dialogic_end"] = source.length()
	return result


static func _value_span(source: String, start: int) -> Dictionary:
	var stack: Array[String] = []
	var in_quote: bool = false
	var escaped: bool = false
	var last_nonspace: int = start
	var index: int = start
	while index < source.length():
		var character: String = source[index]
		if in_quote:
			last_nonspace = index + 1
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == "\"":
				in_quote = false
		elif character == "\"":
			in_quote = true
			last_nonspace = index + 1
		elif character == ";":
			if stack.is_empty():
				return {"end": last_nonspace, "next": _after_line(source, index)}
			index = _after_line(source, index)
			continue
		elif character in ["{", "[", "("]:
			stack.append(character)
			if stack.size() > MAX_CONFIG_NESTING:
				return {"error": "Configuration nesting exceeds %d levels; the file remains read-only." % MAX_CONFIG_NESTING}
			last_nonspace = index + 1
		elif character in ["}", "]", ")"]:
			var opening: String = {"}": "{", "]": "[", ")": "("}[character]
			if stack.is_empty() or stack.pop_back() != opening:
				return {"error": "Unbalanced configuration value; the file remains read-only."}
			last_nonspace = index + 1
		elif character in ["\n", "\r"] and stack.is_empty():
			return {"end": last_nonspace, "next": _after_line(source, index)}
		elif not character in [" ", "\t", "\r", "\n"]:
			last_nonspace = index + 1
		index += 1
	if in_quote or not stack.is_empty():
		return {"error": "Unterminated string or container in project.godot; it remains read-only."}
	return {"end": last_nonspace, "next": source.length()}


static func _parse_value(text: String) -> Dictionary:
	var config := ConfigFile.new()
	var error: Error = config.parse("[data]\nvalue=" + text + "\n__end__=true\n")
	if error != OK or not config.has_section_key("data", "__end__") or config.get_value("data", "__end__", false) != true:
		return {"error": "Invalid native Variant."}
	var keys: PackedStringArray = config.get_section_keys("data")
	if keys.size() > 2:
		return {"error": "Unexpected assignment inside a native value."}
	return {"value": config.get_value("data", "value") if config.has_section_key("data", "value") else null}


static func _has_constructor(text: String) -> bool:
	# Scan bare identifiers directly. Do not build a character-by-character copy
	# of a potentially multi-megabyte string just to blank its quoted contents.
	var index: int = 0
	while index < text.length():
		var character: String = text[index]
		if character == "\"":
			index += 1
			while index < text.length():
				if text[index] == "\\":
					index += 2
				elif text[index] == "\"":
					index += 1
					break
				else:
					index += 1
			continue
		if character == ";":
			index = _after_line(text, index)
			continue
		var code: int = text.unicode_at(index)
		if code == 95 or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			var start: int = index
			index += 1
			while index < text.length():
				code = text.unicode_at(index)
				if not (code == 95 or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57)):
					break
				index += 1
			if text.substr(start, index - start) in ["Object", "Resource", "ExtResource", "SubResource"]:
				var following: int = index
				while following < text.length():
					if text[following] in [" ", "\t", "\r", "\n"]:
						following += 1
					elif text[following] == ";":
						following = _after_line(text, following)
					else:
						break
				if following < text.length() and text[following] == "(":
					return true
			continue
		index += 1
	return false


static func _after_line(text: String, index: int) -> int:
	var newline: int = text.find("\n", index)
	return text.length() if newline < 0 else newline + 1


static func _valid_root(path: String) -> bool:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path) or _has_link_component(path):
		return false
	if OS.get_name() in UNIX_PLATFORMS:
		var mode: int = FileAccess.get_unix_permissions(path)
		var read_bits: int = FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_READ_OTHER
		var execute_bits: int = FileAccess.UNIX_EXECUTE_OWNER | FileAccess.UNIX_EXECUTE_GROUP | FileAccess.UNIX_EXECUTE_OTHER
		if (mode & read_bits) == 0 or (mode & execute_bits) == 0:
			return false
	return DirAccess.open(path) != null


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


static func _read_bytes(target: String) -> Dictionary:
	var input: FileAccess = FileAccess.open(target, FileAccess.READ)
	if input == null:
		return {"error": FileAccess.get_open_error(), "bytes": PackedByteArray()}
	var length: int = input.get_length()
	if length > MAX_CONFIG_BYTES:
		input.close()
		return {"error": ERR_OUT_OF_MEMORY, "bytes": PackedByteArray()}
	var bytes: PackedByteArray = input.get_buffer(length)
	var error: Error = input.get_error()
	input.close()
	if bytes.size() != length or (error != OK and error != ERR_FILE_EOF):
		return {"error": ERR_FILE_CANT_READ, "bytes": PackedByteArray()}
	return {"error": OK, "bytes": bytes}


static func _write_verified(target: String, bytes: PackedByteArray, mode: int) -> Error:
	var output: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		return FileAccess.get_open_error()
	if mode >= 0:
		var permission_error: Error = FileAccess.set_unix_permissions(target, mode)
		if permission_error != OK or FileAccess.get_unix_permissions(target) != mode:
			output.close()
			return ERR_FILE_NO_PERMISSION
	var stored: bool = output.store_buffer(bytes)
	output.flush()
	var error: Error = output.get_error()
	output.close()
	if not stored or error != OK:
		return ERR_FILE_CANT_WRITE
	var check: Dictionary = _read_bytes(target)
	return OK if check["error"] == OK and check["bytes"] == bytes else ERR_FILE_CORRUPT


static func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		context.update(bytes)
	return context.finish().hex_encode()


static func _is_utf8(bytes: PackedByteArray) -> bool:
	var offset: int = 0
	while offset < bytes.size():
		var lead: int = bytes[offset]
		var width: int
		if lead <= 0x7F:
			width = 1
		elif lead >= 0xC2 and lead <= 0xDF:
			width = 2
		elif lead >= 0xE0 and lead <= 0xEF:
			width = 3
		elif lead >= 0xF0 and lead <= 0xF4:
			width = 4
		else:
			return false
		if offset + width > bytes.size():
			return false
		for extra: int in range(1, width):
			if bytes[offset + extra] < 0x80 or bytes[offset + extra] > 0xBF:
				return false
		if width == 3 and ((lead == 0xE0 and bytes[offset + 1] < 0xA0) or (lead == 0xED and bytes[offset + 1] > 0x9F)):
			return false
		if width == 4 and ((lead == 0xF0 and bytes[offset + 1] < 0x90) or (lead == 0xF4 and bytes[offset + 1] > 0x8F)):
			return false
		offset += width
	return true


func _fail(error: Error, message: String) -> Error:
	last_error = message
	return error
