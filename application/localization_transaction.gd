extends RefCounted

## Prepare every file before replacing any. Preserve backups and detect races.
const Document = preload("res://application/timeline_document.gd")

static func change(path: String, after: PackedByteArray) -> Dictionary:
	return {"path":path, "before":FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null, "after":after}

static func matches(item: Dictionary, value: Variant) -> bool:
	if value == null: return not FileAccess.file_exists(item.path) and not Document.new()._is_link(item.path)
	return FileAccess.file_exists(item.path) and FileAccess.get_file_as_bytes(item.path) == value

static func commit(workspace: RefCounted, changes: Array[Dictionary]) -> Dictionary:
	var prepared: Array[Dictionary] = []
	var names := {}
	var stamp := str(Time.get_ticks_usec())
	var writer := Document.new()
	for item: Dictionary in changes:
		if names.has(item.path): return {"error":"A transaction contains duplicate output paths: " + item.path}
		names[item.path] = true
		if workspace.content_path(item.path).is_empty() or not matches(item, item.before): return {"error":"File changed externally or leaves the content root: " + item.path}
		if item.before != null and item.before == item.after: continue
		if item.before != null and writer._check_writable_file(item.path) != OK: return {"error":writer.last_error}
	for item: Dictionary in changes:
		if item.before != null and item.before == item.after: continue
		var parent: String = item.path.get_base_dir()
		if DirAccess.make_dir_recursive_absolute(parent) != OK: cleanup(prepared); return {"error":"Cannot create output folder: " + parent}
		if workspace.content_path(item.path).is_empty(): cleanup(prepared); return {"error":"Output folder changed while preparing files."}
		item["mode"] = FileAccess.get_unix_permissions(item.path) if item.before != null else -1
		item["temp"] = item.path + ".editor-tmp-" + stamp
		item["backup"] = item.path + ".editor-backup-" + stamp + ".bak" if item.before != null else ""
		if FileAccess.file_exists(item.temp) or writer._is_link(item.temp): cleanup(prepared); return {"error":"Temporary path already exists."}
		if not item.backup.is_empty() and (FileAccess.file_exists(item.backup) or writer._is_link(item.backup)): cleanup(prepared); return {"error":"Recovery backup path already exists."}
		prepared.append(item)
		if writer._write_verified(item.temp, item.after, item.mode) != OK: cleanup(prepared); return {"error":"Could not write and verify: " + item.path}
		if item.before != null and writer._write_verified(item.backup, item.before, item.mode) != OK: cleanup(prepared); return {"error":"Could not preserve a backup: " + item.path}
	var committed: Array[Dictionary] = []
	for item: Dictionary in prepared:
		var valid: bool = not workspace.content_path(item.path).is_empty() and matches(item, item.before)
		if not valid or DirAccess.rename_absolute(item.temp, item.path) != OK:
			var failed := rollback(committed, writer)
			cleanup(prepared)
			return {"error":"Commit failed: " + item.path + (". Restored prior files." if failed.is_empty() else ". Recovery backups retained for: " + ", ".join(failed)), "backups":prepared}
		committed.append(item)
	return {"written":committed.size(), "backups":prepared}

static func rollback(items: Array[Dictionary], writer: RefCounted) -> Array[String]:
	var failed: Array[String] = []
	for item: Dictionary in items:
		if not matches(item, item.after): failed.append(item.path); continue
		if item.before == null:
			if DirAccess.remove_absolute(item.path) != OK: failed.append(item.path)
		else:
			var restore: String = item.path + ".editor-restore-" + str(Time.get_ticks_usec())
			if writer._write_verified(restore, item.before, item.mode) != OK or DirAccess.rename_absolute(restore, item.path) != OK: failed.append(item.path)
	return failed

static func cleanup(items: Array[Dictionary]) -> void:
	for item: Dictionary in items:
		if FileAccess.file_exists(item.temp): DirAccess.remove_absolute(item.temp)
