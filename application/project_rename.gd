extends RefCounted
const Transaction = preload("res://application/project_transaction.gd")

static func plan(index: RefCounted, source: String, destination: String) -> Dictionary:
	if not index.complete: return {"error":"A complete project scan is required before renaming."}
	if not index.uncertain.is_empty(): return {"error":"Resolve unknown dependencies before renaming:\n" + "\n".join(index.uncertain)}
	if not index.resources.has(source) or source.begins_with("res://addons/dialogic/") or source.get_extension() in ["uid", "import"]: return {"error":"Choose a target resource; UID and import sidecars move with their resource."}
	if source in ["res://project.godot", "res://override.cfg"]: return {"error":"Native project configuration names are fixed."}
	if source.get_file() == "index.gd" and RegEx.create_from_string('(?m)^\\s*extends\\s+DialogicIndexer\\s*(?:#.*)?$').search(str(index.resources[source].get("text", ""))) != null: return {"error":"Native extension index.gd must keep its discovery name and folder."}
	if source == destination or source.get_extension() != destination.get_extension(): return {"error":"Keep the native resource extension and choose a different path."}
	var target: String = index.workspace.resolve_content_path(destination)
	if target.is_empty() or destination.begins_with("res://addons/dialogic/"): return {"error":"Rename must stay inside the target project."}
	for part: String in destination.trim_prefix("res://").split("/"):
		if part.is_empty() or part.ends_with(".") or part.ends_with(" ") or RegEx.create_from_string('[<>:"|?*\\x00-\\x1f]').search(part) or part.get_basename().to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]: return {"error":"Invalid portable filename: " + part}
	for logical: String in index.resources:
		if logical.to_lower() in [destination.to_lower(), destination.to_lower() + ".uid", destination.to_lower() + ".import"]: return {"error":"Destination already exists or collides by case: " + logical}
	var by_file := {}
	for reference: Dictionary in index.incoming(source):
		if reference.target.begins_with("uid://"): continue
		if not by_file.has(reference.source): by_file[reference.source] = []
		by_file[reference.source].append(reference)
	var changes: Array[Dictionary] = []
	var summaries: Array[String] = []
	var edited_sidecars := {}
	var moved: PackedByteArray = FileAccess.get_file_as_bytes(index.resources[source].absolute)
	for logical: String in by_file:
		var original: PackedByteArray = FileAccess.get_file_as_bytes(index.resources[logical].absolute)
		var text := original.get_string_from_utf8()
		var ordered: Array = by_file[logical]
		ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.start > b.start)
		for reference: Dictionary in ordered:
			var replacement := destination
			if reference.kind == "index_path": replacement = JSON.stringify(destination)
			if reference.kind in ["dch", "dtl"]:
				replacement = destination.get_file().get_basename()
				if reference.kind == "dch" and (reference.get("quoted", false) or replacement.contains(" ")): replacement = '"' + replacement + '"'
			text = text.left(reference.start) + replacement + text.substr(reference.end)
		if logical == source: moved = encode_preserved(original, text)
		elif logical in [source + ".uid", source + ".import"]: edited_sidecars[logical] = encode_preserved(original, text)
		else: changes.append({"path":index.resources[logical].absolute, "before":original, "after":encode_preserved(original, text)})
		summaries.append("%s: %d reference(s)" % [logical, ordered.size()])
	changes.append({"path":target, "before":null, "after":moved})
	changes.append({"path":index.resources[source].absolute, "before":FileAccess.get_file_as_bytes(index.resources[source].absolute), "after":null})
	for suffix: String in [".uid", ".import"]:
		var sidecar: String = index.resources[source].absolute + suffix
		if FileAccess.file_exists(sidecar):
			var bytes := FileAccess.get_file_as_bytes(sidecar)
			changes.append({"path":target + suffix, "before":null, "after":edited_sidecars.get(source + suffix, bytes)})
			changes.append({"path":sidecar, "before":bytes, "after":null})
	return {"source":source, "destination":destination, "changes":changes, "summary":summaries, "uid":index.resources[source].uid, "root":index.workspace.root_path}

static func commit(index: RefCounted, prepared: Dictionary) -> Dictionary:
	if prepared.has("error"): return prepared
	if prepared.get("root", "") != index.workspace.root_path: return {"error":"Rename belongs to another project."}
	return Transaction.commit(index.workspace, prepared.changes)

static func encode_preserved(original: PackedByteArray, text: String) -> PackedByteArray:
	var result := text.to_utf8_buffer()
	if original.size() >= 3 and original.slice(0, 3) == PackedByteArray([239, 187, 191]): result = PackedByteArray([239, 187, 191]) + result
	return result
