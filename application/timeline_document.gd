class_name TimelineDocument
extends RefCounted

## Source-preserving document session. No event-model reserialization is used.
## References: https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
##             https://docs.godotengine.org/en/stable/classes/class_diraccess.html

const CODEC = preload("res://application/timeline_codec.gd")
const UNIX_PLATFORMS = ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD", "macOS", "iOS"]

var content: String = ""
var path: String = ""
var dirty: bool = false
var read_only: bool = false
var diagnostics: Array[String] = []
var last_error: String = ""
var last_backup_path: String = ""
var workspace: RefCounted = null

var _original_content: String = ""
var _original_bytes: PackedByteArray = PackedByteArray()
var _expected_hash: String = ""
var _had_bom: bool = false
var _newline: String = "\n"


func new_document() -> void:
	content = ""
	path = ""
	dirty = false
	read_only = false
	diagnostics.clear()
	last_error = ""
	last_backup_path = ""
	_original_content = ""
	_original_bytes = PackedByteArray()
	_expected_hash = ""
	_had_bom = false
	_newline = "\n"


func open_file(file_path: String) -> Error:
	last_error = ""
	var destination: String = _absolute_path(file_path)
	if destination.is_empty() or destination.get_extension().to_lower() != get_file_extension():
		return _fail(ERR_INVALID_PARAMETER, "Choose a .%s document file." % get_file_extension())
	var read_result: Dictionary = _read_bytes(destination)
	if read_result["error"] == ERR_OUT_OF_MEMORY:
		return _fail(ERR_OUT_OF_MEMORY, "This version supports document files up to 4 MiB, including BOM and line endings.")
	if read_result["error"] != OK:
		return _fail(read_result["error"], "Could not read the document: " + destination)
	var bytes: PackedByteArray = read_result["bytes"]
	if bytes.size() > CODEC.MAX_SOURCE_BYTES:
		return _fail(ERR_OUT_OF_MEMORY, "This version supports documents up to 4 MiB.")
	var has_bom: bool = bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF
	var payload: PackedByteArray = bytes.slice(3) if has_bom else bytes
	if not _is_utf8(payload):
		return _fail(ERR_INVALID_DATA, "The document must use valid UTF-8 text; the original file was not changed.")
	if payload.has(0):
		return _fail(ERR_INVALID_DATA, "The document contains NUL bytes and was not opened.")
	var decoded: String = payload.get_string_from_utf8()
	var next_content: String = CODEC.normalize_source(decoded)
	var validation: Dictionary = validate_content(next_content)
	# Commit only after successful IO/decoding; failed open preserves the old session.
	content = next_content
	path = destination
	dirty = false
	read_only = not validation["supported"]
	diagnostics.assign(validation["diagnostics"])
	_original_content = content
	_original_bytes = bytes
	_expected_hash = _digest(bytes)
	_had_bom = has_bom
	_newline = "\r\n" if decoded.contains("\r\n") else "\n"
	last_backup_path = ""
	return OK


func set_content(text: String, validate_now: bool = true) -> void:
	if read_only:
		last_error = "This document is read-only because it contains unsupported features."
		return
	content = CODEC.normalize_source(text)
	dirty = content != _original_content
	# The UI defers parsing while the user types. Save and preview must still
	# validate synchronously; other callers retain the original default behavior.
	if validate_now:
		var validation: Dictionary = validate_content(content)
		diagnostics.assign(validation["diagnostics"])
	else:
		diagnostics.clear()
	last_error = ""


func validate_content(text: String) -> Dictionary:
	return CODEC.validate_content(text, workspace)


func get_file_extension() -> String:
	return "dtl"


func save_file(file_path: String = "") -> Error:
	last_error = ""
	if read_only:
		return _fail(ERR_UNAVAILABLE, "Unsupported documents remain read-only and are never rewritten.")
	var target: String = _absolute_path(file_path) if not file_path.is_empty() else path
	if target.is_empty() or target.get_extension().to_lower() != get_file_extension():
		return _fail(ERR_INVALID_PARAMETER, "Choose a destination with the .%s extension." % get_file_extension())
	var bytes: PackedByteArray = _encoded_content()
	if bytes.size() > CODEC.MAX_SOURCE_BYTES:
		return _fail(ERR_OUT_OF_MEMORY, "The saved file exceeds 4 MiB after preserving its BOM and line endings. Shorten the text before saving.")
	var validation: Dictionary = validate_content(content)
	diagnostics.assign(validation["diagnostics"])
	if not validation["supported"]:
		return _fail(ERR_UNAVAILABLE, "The edited source contains unsupported features. Correct it before saving.")
	var is_current: bool = not path.is_empty() and _same_path(target, path)
	var exists: bool = FileAccess.file_exists(target)
	if (exists or _is_link(target)) and not is_current:
		return _fail(ERR_ALREADY_EXISTS, "Save As will not overwrite another file. Choose a new filename.")
	if is_current:
		var conflict: Error = _check_current_file(target)
		if conflict != OK:
			return conflict
		if not dirty:
			return OK
		var permission_error: Error = _check_writable_file(target)
		if permission_error != OK:
			return permission_error
	var unix_permissions: int = FileAccess.get_unix_permissions(target) if is_current and OS.get_name() in UNIX_PLATFORMS else -1
	var parent: String = target.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		return _fail(ERR_FILE_BAD_PATH, "The destination folder does not exist.")
	var suffix: String = "%s-%s" % [Time.get_ticks_usec(), get_instance_id()]
	var temporary: String = target + ".editor-tmp-" + suffix
	if FileAccess.file_exists(temporary):
		return _fail(ERR_ALREADY_EXISTS, "A temporary file already exists; retry saving.")
	var write_error: Error = _write_verified(temporary, bytes, unix_permissions)
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return _fail(write_error, "Could not write and verify the temporary file; the original is unchanged.")
	var backup: String = ""
	if is_current:
		var conflict: Error = _check_current_file(target)
		if conflict != OK:
			DirAccess.remove_absolute(temporary)
			return conflict
		backup = target + ".editor-backup-" + suffix + ".bak"
		var backup_error: Error = _write_verified(backup, _original_bytes, unix_permissions)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			DirAccess.remove_absolute(backup)
			return _fail(backup_error, "Could not preserve the previous version; the original is unchanged.")
		last_backup_path = backup
		conflict = _check_current_file(target)
		if conflict != OK:
			DirAccess.remove_absolute(temporary)
			return conflict
	elif FileAccess.file_exists(target) or _is_link(target):
		DirAccess.remove_absolute(temporary)
		return _fail(ERR_ALREADY_EXISTS, "The destination appeared while saving; it was not overwritten.")
	# Godot's Windows rename can remove the destination before moving the file.
	# Retain a verified backup; this is recoverable replacement, not a crash-atomic promise.
	var replace_error: Error = DirAccess.rename_absolute(temporary, target)
	if replace_error != OK:
		DirAccess.remove_absolute(temporary)
		if not backup.is_empty() and not FileAccess.file_exists(target):
			var recovery_error: Error = _write_verified(target, _original_bytes, unix_permissions)
			if recovery_error != OK:
				return _fail(replace_error, "Could not replace the document (error %d), and restoring it also failed (error %d). The verified recovery copy remains at: %s" % [replace_error, recovery_error, backup])
		return _fail(replace_error, "Could not replace the document. Recovery copy: " + backup)
	var verify: Dictionary = _read_bytes(target)
	if verify["error"] != OK or verify["bytes"] != bytes:
		return _fail(ERR_FILE_CORRUPT, "The final file could not be verified. Recovery copy: " + backup)
	path = target
	_original_content = content
	_original_bytes = bytes
	_expected_hash = _digest(bytes)
	dirty = false
	return OK


func _encoded_content() -> PackedByteArray:
	if content == _original_content and not path.is_empty():
		return _original_bytes
	var bytes: PackedByteArray = PackedByteArray([0xEF, 0xBB, 0xBF]) if _had_bom else PackedByteArray()
	bytes.append_array(content.replace("\n", _newline).to_utf8_buffer())
	return bytes


func _check_current_file(target: String) -> Error:
	var check: Dictionary = _read_bytes(target)
	if check["error"] != OK:
		return _fail(ERR_BUSY, "The file was removed or became unreadable outside this app. Save As to a new file.")
	if _digest(check["bytes"]) != _expected_hash:
		return _fail(ERR_BUSY, "The file changed outside this app. Reopen it or Save As to a new file.")
	return OK


func _check_writable_file(target: String) -> Error:
	if _is_link(target):
		return _fail(ERR_UNAVAILABLE, "Saving would replace this symbolic link. Save As to a new regular file instead.")
	var protected: bool = false
	if OS.get_name() in UNIX_PLATFORMS:
		var write_bits: int = FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_WRITE_GROUP | FileAccess.UNIX_WRITE_OTHER
		protected = (FileAccess.get_unix_permissions(target) & write_bits) == 0
	elif OS.get_name() == "Windows":
		protected = FileAccess.get_read_only_attribute(target)
	if protected:
		return _fail(ERR_FILE_NO_PERMISSION, "The current file is read-only. Save As to a new filename.")
	# READ_WRITE does not truncate. Check effective access as well as explicit
	# read-only bits, since a rename alone can bypass a file's write protection.
	var writable: FileAccess = FileAccess.open(target, FileAccess.READ_WRITE)
	if writable == null:
		return _fail(ERR_FILE_NO_PERMISSION, "The current file is not writable. Save As to a new filename.")
	writable.close()
	return OK


static func _is_link(target: String) -> bool:
	var directory: DirAccess = DirAccess.open(target.get_base_dir())
	return directory != null and directory.is_link(target.get_file())


func _write_verified(target: String, bytes: PackedByteArray, unix_permissions: int = -1) -> Error:
	var output: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		return FileAccess.get_open_error()
	# Apply the source mode before writing content so neither the temporary
	# file nor retained recovery copy exposes private source bytes by default.
	if unix_permissions >= 0:
		var permission_error: Error = FileAccess.set_unix_permissions(target, unix_permissions)
		if permission_error != OK or FileAccess.get_unix_permissions(target) != unix_permissions:
			output.close()
			return ERR_FILE_NO_PERMISSION
	var stored: bool = output.store_buffer(bytes)
	output.flush()
	var error: Error = output.get_error()
	output.close()
	if not stored or error != OK:
		return ERR_FILE_CANT_WRITE
	var check: Dictionary = _read_bytes(target)
	if check["error"] != OK or check["bytes"] != bytes:
		return ERR_FILE_CORRUPT
	return OK


static func _read_bytes(target: String) -> Dictionary:
	var input: FileAccess = FileAccess.open(target, FileAccess.READ)
	if input == null:
		return {"error": FileAccess.get_open_error(), "bytes": PackedByteArray()}
	var length: int = input.get_length()
	if length > CODEC.MAX_SOURCE_BYTES:
		input.close()
		return {"error": ERR_OUT_OF_MEMORY, "bytes": PackedByteArray()}
	var bytes: PackedByteArray = input.get_buffer(length)
	var error: Error = input.get_error()
	input.close()
	if bytes.size() != length or (error != OK and error != ERR_FILE_EOF):
		return {"error": ERR_FILE_CANT_READ, "bytes": PackedByteArray()}
	return {"error": OK, "bytes": bytes}


static func _digest(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		context.update(bytes)
	return context.finish().hex_encode()


static func _absolute_path(value: String) -> String:
	if value.begins_with("user://") or value.begins_with("res://"):
		return ProjectSettings.globalize_path(value).simplify_path()
	if not value.is_absolute_path():
		return ""
	return value.simplify_path()


static func _same_path(first: String, second: String) -> bool:
	if OS.get_name() == "Windows":
		return first.to_lower() == second.to_lower()
	return first == second


static func _is_utf8(bytes: PackedByteArray) -> bool:
	var offset: int = 0
	while offset < bytes.size():
		var lead: int = bytes[offset]
		var width: int = 1
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
