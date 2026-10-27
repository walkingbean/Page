extends "res://addons/dialogic/Modules/Save/subsystem_save.gd"

## Native Save API and binary state format, with preview-owned slot directories.
const Source = preload("res://application/media_source.gd")
var session: RefCounted
var save_root := ""
var last_error := ""
var transaction_slot := ""
var transaction_path := ""
var load_pending := false
signal load_completed(error: Error)

func _problem(message: String, code := ERR_INVALID_DATA) -> Error:
	last_error = message
	if session != null and is_instance_valid(session.window): session.window.report_save_error(message)
	return code

func _safe(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	return not preload("res://application/content_workspace.gd")._has_link_component(absolute)

func _make_sure_slot_dir_exists() -> Error:
	if save_root.is_empty() or not _safe(save_root): return _problem("Preview save folder is unavailable or linked.")
	return DirAccess.make_dir_recursive_absolute(save_root)

func get_slot_path(slot_name: String) -> String:
	if slot_name == transaction_slot and not transaction_path.is_empty(): return transaction_path
	return save_root.path_join(slot_name)

func get_slot_names() -> Array[String]:
	var names: Array[String] = []
	if not _safe(save_root) or not DirAccess.dir_exists_absolute(save_root): return names
	for name: String in DirAccess.get_directories_at(save_root):
		if Source.slot_error(name).is_empty() and _safe(get_slot_path(name)): names.append(name)
	names.sort(); return names

func add_empty_slot(slot_name: String) -> Error:
	var problem := Source.slot_error(slot_name)
	if not problem.is_empty() or slot_name.is_empty(): return _problem("Invalid save slot: " + problem)
	if _make_sure_slot_dir_exists() != OK or not _safe(get_slot_path(slot_name)): return _problem("Cannot create preview slot.", ERR_CANT_CREATE)
	return DirAccess.make_dir_recursive_absolute(get_slot_path(slot_name))

func save(slot_name := "", is_autosave := false, thumbnail_mode := ThumbnailMode.TAKE_AND_STORE, slot_info := {}) -> Error:
	last_error = ""
	if is_autosave and not autosave_enabled: return OK
	if session == null or not session.saved_content or session.content_fingerprint.is_empty(): return _problem("Save the timeline and select its content folder before creating a preview save.")
	if session.fingerprint() != session.content_fingerprint: return _problem("Content changed since preview started. Restart preview before saving.")
	var actual: String = slot_name if not slot_name.is_empty() else get_default_slot()
	var problem := Source.slot_error(actual)
	if not problem.is_empty(): return _problem(problem)
	if not transaction_slot.is_empty() or load_pending: return _problem("A preview state operation is already in progress.", ERR_BUSY)
	if _make_sure_slot_dir_exists() != OK: return ERR_CANT_CREATE
	var target := save_root.path_join(actual)
	var backup := target + ".previous"
	var stage := target + ".pending"
	if not _safe(target) or not _safe(backup) or not _safe(stage): return _problem("Linked slot directories are not followed.")
	if _remove_directory(stage) != OK or _remove_directory(backup) != OK: return _problem("A previous incomplete slot operation requires attention.", ERR_CANT_CREATE)
	transaction_slot = actual; transaction_path = stage
	var error := save_file(actual, "state.txt", dialogic.get_full_state())
	if error == OK and not slot_info.is_empty(): error = save_file(actual, "info.txt", slot_info)
	if error == OK and thumbnail_mode != ThumbnailMode.NONE:
		if thumbnail_mode == ThumbnailMode.TAKE_AND_STORE: take_thumbnail()
		error = save_slot_thumbnail(actual)
	transaction_slot = ""; transaction_path = ""
	if error != OK: _remove_directory(stage); return _problem("Preview save failed; the previous slot was retained.", error)
	var existed := DirAccess.dir_exists_absolute(target)
	if existed:
		error = DirAccess.rename_absolute(target, backup)
		if error != OK: _remove_directory(stage); return _problem("Could not preserve the previous slot.", error)
	error = DirAccess.rename_absolute(stage, target)
	if error == OK: error = set_latest_slot(actual)
	if error != OK:
		_remove_directory(target)
		if existed: DirAccess.rename_absolute(backup, target)
		return _problem("Save commit failed; the previous slot and index were retained.", error)
	_remove_directory(backup)
	saved.emit({"slot_name":actual, "is_autosave":is_autosave})
	return OK

func _remove_directory(path: String) -> Error:
	if not _safe(path): return ERR_INVALID_DATA
	if not DirAccess.dir_exists_absolute(path): return OK
	if not DirAccess.get_directories_at(path).is_empty(): return ERR_INVALID_DATA
	for file: String in DirAccess.get_files_at(path):
		if not _safe(path.path_join(file)): return ERR_INVALID_DATA
	for file: String in DirAccess.get_files_at(path):
		var error := DirAccess.remove_absolute(path.path_join(file))
		if error != OK: return error
	return DirAccess.remove_absolute(path)

func load(slot_name := "") -> Error:
	last_error = ""
	if load_pending: return _problem("A load is already in progress.", ERR_BUSY)
	if session == null or not session.saved_content: return _problem("A saved, matching content timeline is required to load a preview slot.")
	if session.fingerprint() != session.content_fingerprint: return _problem("Content changed since preview started. Restart preview before loading.")
	var actual: String = slot_name if not slot_name.is_empty() else get_default_slot()
	if not Source.slot_error(actual).is_empty(): return _problem("Invalid save slot.")
	var state: Variant = load_file(actual, "state.txt", null)
	if not state is DialogicSaveState: return _problem(last_error if not last_error.is_empty() else "Slot has no valid Dialogic state.")
	if not state.timeline.is_empty() and not ResourceLoader.has_cached(state.timeline): return _problem("Saved timeline is not part of this preview graph.")
	var timeline: DialogicTimeline = ResourceLoader.load(state.timeline) if not state.timeline.is_empty() else null
	if timeline != null and (state.event_index < 0 or state.event_index >= timeline.events.size()): return _problem("Saved event index is outside the current timeline.")
	var index_error := set_latest_slot(actual)
	if index_error != OK: return _problem("Could not update the preview slot index.", index_error)
	load_pending = true
	session.window.call_deferred("restore_saved_state", state)
	return OK

func save_file(slot_name: String, file_name: String, data: Variant) -> Error:
	if slot_name.is_empty(): slot_name = get_default_slot()
	if file_name not in ["state.txt", "info.txt"]: return _problem("Unsupported preview slot file.")
	if add_empty_slot(slot_name) != OK: return ERR_CANT_CREATE
	var path := get_slot_path(slot_name).path_join(file_name)
	for suffix: String in ["", ".tmp", ".sha256", ".sha256.tmp", ".bak", ".sha256.bak"]:
		if not _safe(path + suffix): return _problem("Linked save files are not followed.")
	var password := get_encryption_password()
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE) if password.is_empty() else FileAccess.open_encrypted_with_pass(path + ".tmp", FileAccess.WRITE, password)
	if file == null: return _problem("Could not write preview save.", ERR_CANT_CREATE)
	file.store_var(session.map_value(data, true), true); file.flush()
	var error := file.get_error(); file.close()
	if error != OK: return _problem("Could not finish preview save.", error)
	var digest := FileAccess.get_sha256(path + ".tmp")
	var receipt := ConfigFile.new(); receipt.set_value("save", "sha256", digest); receipt.set_value("save", "content", session.content_fingerprint)
	var signature := _signature(digest, session.content_fingerprint, true)
	if signature.is_empty(): return _problem("Could not create preview save integrity key.", ERR_CANT_CREATE)
	receipt.set_value("save", "signature", signature)
	if receipt.save(path + ".sha256.tmp") != OK: return _problem("Could not write save integrity information.", ERR_CANT_CREATE)
	# Retain the previous complete slot pair until both new files are installed.
	if FileAccess.file_exists(path):
		if DirAccess.rename_absolute(path, path + ".bak") != OK: return _problem("Could not preserve the previous save.", ERR_CANT_CREATE)
	if FileAccess.file_exists(path + ".sha256"): DirAccess.rename_absolute(path + ".sha256", path + ".sha256.bak")
	error = DirAccess.rename_absolute(path + ".tmp", path)
	if error == OK: error = DirAccess.rename_absolute(path + ".sha256.tmp", path + ".sha256")
	if error != OK:
		if FileAccess.file_exists(path + ".bak"): DirAccess.rename_absolute(path + ".bak", path)
		if FileAccess.file_exists(path + ".sha256.bak"): DirAccess.rename_absolute(path + ".sha256.bak", path + ".sha256")
		return _problem("Save commit failed; previous files were retained.", error)
	return OK

func load_file(slot_name: String, file_name: String, default: Variant) -> Variant:
	if slot_name.is_empty(): slot_name = get_default_slot()
	if not Source.slot_error(slot_name).is_empty() or not file_name in ["state.txt", "info.txt"]: last_error = "Invalid slot or file."; return default
	var path := get_slot_path(slot_name).path_join(file_name)
	if not _safe(path) or not _safe(path + ".sha256"): last_error = "Linked save files are not followed."; return default
	var receipt := ConfigFile.new()
	if receipt.load(path + ".sha256") != OK or receipt.get_value("save", "sha256", "") != FileAccess.get_sha256(path): last_error = "Save is missing, damaged or was changed externally."; return default
	if receipt.get_value("save", "content", "") != session.content_fingerprint: last_error = "The save belongs to different content or preview language. Restore the matching content and language before loading."; return default
	var signature := _signature(receipt.get_value("save", "sha256", ""), session.content_fingerprint, false)
	if signature.is_empty() or signature != receipt.get_value("save", "signature", ""): last_error = "Save authentication failed. Only this application's own preview saves may be loaded."; return default
	var password := get_encryption_password()
	var file := FileAccess.open(path, FileAccess.READ) if password.is_empty() else FileAccess.open_encrypted_with_pass(path, FileAccess.READ, password)
	if file == null or file.get_length() > 32 * 1024 * 1024: last_error = "Save is unreadable or exceeds 32 MiB."; return default
	var value: Variant = file.get_var(true)
	if file.get_error() != OK: last_error = "Save decoding failed."; return default
	return session.map_value(value, false)

func _signature(digest: String, content_hash: String, create_key: bool) -> String:
	var path := save_root.path_join("integrity.key")
	if not _safe(path): return ""
	if not FileAccess.file_exists(path) and create_key:
		var key_file := FileAccess.open(path, FileAccess.WRITE)
		if key_file == null: return ""
		key_file.store_buffer(Crypto.new().generate_random_bytes(32)); key_file.close()
	var key := FileAccess.get_file_as_bytes(path)
	if key.size() != 32: return ""
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, (digest + ":" + content_hash).to_utf8_buffer()).hex_encode()

func set_global_info(key: String, value: Variant) -> Error:
	if _make_sure_slot_dir_exists() != OK: return ERR_CANT_CREATE
	var path := save_root.path_join("global_info.txt")
	for suffix: String in ["", ".tmp", ".bak"]:
		if not _safe(path + suffix): return _problem("Linked global save information is not followed.")
	var config := ConfigFile.new()
	var password := get_encryption_password()
	if FileAccess.file_exists(path):
		var read_error := config.load(path) if password.is_empty() else config.load_encrypted_pass(path, password)
		if read_error != OK: return _problem("Global preview save information is damaged or uses a different password.")
	config.set_value("main", key, session.map_value(value, true))
	var error := config.save(path + ".tmp") if password.is_empty() else config.save_encrypted_pass(path + ".tmp", password)
	if error != OK: return error
	var existed := FileAccess.file_exists(path)
	if existed:
		if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
		error = DirAccess.rename_absolute(path, path + ".bak")
		if error != OK: return error
	error = DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK and existed: DirAccess.rename_absolute(path + ".bak", path)
	if error == OK and existed: DirAccess.remove_absolute(path + ".bak")
	return error

func get_global_info(key: String, default: Variant) -> Variant:
	var path := save_root.path_join("global_info.txt")
	if not _safe(path): return default
	var config := ConfigFile.new()
	var password := get_encryption_password()
	var error := config.load(path) if password.is_empty() else config.load_encrypted_pass(path, password)
	if error != OK: return default
	return session.map_value(config.get_value("main", key, default), false)

func get_latest_slot() -> String:
	var value: String = get_global_info("latest_save_slot", "")
	return value if has_slot(value) else ""

func set_latest_slot(slot_name: String) -> Error:
	return set_global_info("latest_save_slot", slot_name)

func delete_slot(slot_name: String) -> Error:
	if slot_name.is_empty() or not Source.slot_error(slot_name).is_empty() or not _safe(get_slot_path(slot_name)): return _problem("Invalid preview slot.")
	var directory := get_slot_path(slot_name)
	for file: String in DirAccess.get_files_at(directory):
		if not _safe(directory.path_join(file)): return _problem("Linked slot files are not deleted.")
	for file: String in DirAccess.get_files_at(directory):
		var error := DirAccess.remove_absolute(directory.path_join(file))
		if error != OK: return _problem("Could not remove slot file.", error)
	return DirAccess.remove_absolute(directory)

func take_thumbnail() -> void:
	if session != null and session.window.get_viewport().get_texture() != null: latest_thumbnail = session.window.get_viewport().get_texture().get_image()

func save_slot_thumbnail(slot_name: String) -> Error:
	var path := get_slot_path(slot_name).path_join("thumbnail.png")
	if latest_thumbnail == null or not _safe(path): return ERR_UNAVAILABLE
	return latest_thumbnail.save_png(path)
