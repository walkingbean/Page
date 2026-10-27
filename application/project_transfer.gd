extends RefCounted
const Data = preload("res://application/variable_document.gd")
const Index = preload("res://application/project_index.gd")
const Config = preload("res://application/project_document.gd")

static func export_native(workspace: RefCounted, destination: String) -> Dictionary:
	if not destination.is_absolute_path() or destination.begins_with("res://") or destination.begins_with("user://") or Data._has_link_component(destination): return {"error":"Choose an absolute, unlinked destination folder."}
	var target := destination.simplify_path().trim_suffix("/")
	if target == workspace.root_path or target.begins_with(workspace.root_path + "/") or workspace.root_path.begins_with(target + "/"): return {"error":"Destination must be separate from the source project."}
	if DirAccess.dir_exists_absolute(target) or FileAccess.file_exists(target): return {"error":"Choose a new destination folder; existing content will not be overwritten."}
	var index := Index.new(); index.scan(workspace)
	if not index.complete: return {"error":"Cannot transfer an incomplete project scan."}
	var project := Config.new()
	if project.open_project(workspace) != OK or project.read_only: return {"error":"Invalid native project configuration."}
	var stage := target + ".editor-transfer-" + str(Time.get_ticks_usec())
	if DirAccess.dir_exists_absolute(stage) or DirAccess.make_dir_recursive_absolute(stage) != OK: return {"error":"Cannot prepare the destination folder."}
	var manifest := {}
	for logical: String in index.resources:
		var path: String = index.resources[logical].absolute
		var relative := logical.trim_prefix("res://")
		if relative == "project.binary": continue
		var output := stage.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK or DirAccess.copy_absolute(path, output) != OK or FileAccess.get_sha256(path) != FileAccess.get_sha256(output): return {"error":"Transfer failed; recovery staging retained: " + stage + "\nResource: " + logical}
		manifest[relative] = FileAccess.get_sha256(path)
	var zip := ZIPReader.new()
	if zip.open("res://runtime/native_runtime.zip") != OK: return {"error":"Fixed native dependency support is missing. Staging: " + stage}
	for relative: String in zip.get_files():
		if not relative.begins_with("addons/dialogic/") or relative.ends_with("/"): continue
		var output := stage.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK: return {"error":"Cannot create dependency folder. Staging: " + stage}
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null: return {"error":"Cannot transfer fixed dependency. Staging: " + stage}
		file.store_buffer(zip.read_file(relative)); file.close()
	zip.close()
	var existing_dependency: String = workspace.root_path.path_join("addons/dialogic")
	if DirAccess.dir_exists_absolute(existing_dependency):
		var verification: String = preload("res://application/project_runtime.gd").new()._verify_dependency(existing_dependency, stage.path_join("addons/dialogic"))
		if not verification.is_empty(): return {"error":verification + "\nStaging: " + stage}
	# Native project bootstrapping, only when the target did not define these settings.
	if project.value("autoload/Dialogic") == null: project.set_value("autoload/Dialogic", "*res://addons/dialogic/Core/DialogicGameHandler.gd")
	var plugins: Variant = project.value("editor_plugins/enabled", PackedStringArray())
	if not plugins is PackedStringArray and not plugins is Array: return {"error":"Invalid editor plugin list. Staging: " + stage}
	if not "res://addons/dialogic/plugin.cfg" in plugins: plugins.append("res://addons/dialogic/plugin.cfg")
	project.set_value("editor_plugins/enabled", PackedStringArray(plugins))
	if project.value("input/dialogic_default_action") == null:
		project.set_literal("input/dialogic_default_action", '{"deadzone":0.5,"events":[Object(InputEventKey,"keycode":4194309),Object(InputEventMouseButton,"button_index":1)]}')
	var file := FileAccess.open(stage.path_join("project.godot"), FileAccess.WRITE)
	if file == null: return {"error":"Cannot finish project configuration. Staging: " + stage}
	var bytes: PackedByteArray = project.content.replace("\n", project._newline).to_utf8_buffer()
	if project._had_bom: bytes = PackedByteArray([239, 187, 191]) + bytes
	file.store_buffer(bytes); file.close()
	for relative: String in manifest:
		if FileAccess.get_sha256(workspace.root_path.path_join(relative)) != manifest[relative]: return {"error":"Source changed during transfer. Staging retained: " + stage}
	if DirAccess.dir_exists_absolute(target) or FileAccess.file_exists(target) or Data._has_link_component(target) or DirAccess.rename_absolute(stage, target) != OK: return {"error":"Destination changed or commit failed. Staging retained: " + stage}
	return {"destination":target, "source_files":manifest.size(), "source_sha256":manifest}
