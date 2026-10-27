extends RefCounted

const Document = preload("res://application/timeline_document.gd")
const Data = preload("res://application/variable_document.gd")

static func snapshot(path: String) -> Variant:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

static func unchanged(path: String, bytes: Variant) -> bool:
	if Data._has_link_component(path) or DirAccess.dir_exists_absolute(path): return false
	return not FileAccess.file_exists(path) if bytes == null else FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes

static func commit(workspace: RefCounted, changes: Array[Dictionary]) -> Dictionary:
	var names := {}
	var writer := Document.new()
	var prepared: Array[Dictionary] = []
	for change: Dictionary in changes:
		if names.has(change.path) or workspace.content_path(change.path).is_empty() or not unchanged(change.path, change.before): return {"error":"Stale or invalid transaction path: " + change.path}
		names[change.path] = true
		if change.before != null and writer._check_writable_file(change.path) != OK: return {"error":writer.last_error}
	var stamp := str(Time.get_ticks_usec())
	for change: Dictionary in changes:
		var item := change.duplicate()
		item["mode"] = FileAccess.get_unix_permissions(item.path) if item.before != null else -1
		item["temp"] = item.path + ".editor-tmp-" + stamp
		item["backup"] = item.path + ".editor-backup-" + stamp + ".bak"
		if DirAccess.make_dir_recursive_absolute(item.path.get_base_dir()) != OK or workspace.content_path(item.path).is_empty(): _cleanup(prepared); return {"error":"Cannot prepare directory: " + item.path}
		if FileAccess.file_exists(item.temp) or FileAccess.file_exists(item.backup) or Data._has_link_component(item.temp) or Data._has_link_component(item.backup): _cleanup(prepared); return {"error":"Recovery path already exists."}
		prepared.append(item)
		if item.after != null and writer._write_verified(item.temp, item.after, item.mode) != OK: _cleanup(prepared); return {"error":"Cannot prepare output: " + item.path}
		if item.before != null and writer._write_verified(item.backup, item.before, item.mode) != OK: _cleanup(prepared); return {"error":"Cannot preserve recovery backup: " + item.path}
	# Recheck the complete plan before the first mutation, then each entry at commit.
	for item: Dictionary in prepared:
		if not unchanged(item.path, item.before): _cleanup(prepared); return {"error":"Project changed after preview: " + item.path}
	var written: Array[Dictionary] = []
	for item: Dictionary in prepared:
		var error := ERR_BUSY
		if unchanged(item.path, item.before) and not workspace.content_path(item.path).is_empty():
			error = DirAccess.remove_absolute(item.path) if item.after == null else DirAccess.rename_absolute(item.temp, item.path)
		if error != OK:
			var recovery: Array[String] = []
			written.reverse()
			for previous: Dictionary in written:
				if not unchanged(previous.path, previous.after): recovery.append(previous.backup); continue
				if previous.before == null:
					if DirAccess.remove_absolute(previous.path) != OK: recovery.append(previous.path)
				else:
					var restore: String = previous.path + ".editor-restore-" + stamp
					if writer._write_verified(restore, previous.before, previous.mode) != OK or DirAccess.rename_absolute(restore, previous.path) != OK: recovery.append(previous.backup)
			_cleanup(prepared)
			return {"error":"Transaction failed: " + item.path + (". Original files restored." if recovery.is_empty() else ". Recovery required: " + ", ".join(recovery)), "recovery":recovery}
		written.append(item)
	_cleanup(prepared)
	return {"written":written.size(), "backups":prepared.map(func(item: Dictionary): return item.backup if item.before != null else "")}

static func _cleanup(prepared: Array[Dictionary]) -> void:
	for item: Dictionary in prepared:
		if FileAccess.file_exists(item.temp): DirAccess.remove_absolute(item.temp)
