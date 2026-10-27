extends RefCounted

const Data = preload("res://application/variable_document.gd")
const Config = preload("res://application/project_document.gd")
const Index = preload("res://application/project_index.gd")
const Media = preload("res://application/media_assets.gd")
const Executable = preload("res://application/project_executable.gd")
var pid := -1
var exit_code := -1
var state := "idle"
var last_error := ""
var log_path := ""
var stage_path := ""
var _files: Dictionary = {}

static func log_reports_failure(text: String) -> bool:
	return text.contains("SCRIPT ERROR") or text.contains("ERROR:") or text.contains("[Dialogic] Call event failed:") or (text.contains("[Dialogic] Expression") and text.contains("failed to parse:"))

func running() -> bool:
	if pid <= 0: return false
	var code := OS.get_process_exit_code(pid)
	if code >= 0 or not OS.is_process_running(pid):
		exit_code = code; pid = -1; state = "ended" if code == 0 else "failed"
		return false
	return true

func stop() -> void:
	if running(): OS.kill(pid)
	pid = -1; state = "stopped"
	_cleanup_payload()

func start(workspace: RefCounted, mode: String = "project", entry: String = "", source_override: String = "", headless: bool = false) -> Dictionary:
	stop()
	exit_code = -1; state = "preparing"; log_path = ""
	var prepared := prepare(workspace, mode, entry, source_override)
	if prepared.has("error"): last_error = prepared.error; return prepared
	var pack_path: String = stage_path.path_join("target.pck")
	var packer := PCKPacker.new()
	if packer.pck_start(pack_path) != OK: return _fail("Cannot create target preview pack.")
	for logical: String in _files:
		if packer.add_file("res://" + logical, _files[logical]) != OK: return _fail("Cannot pack target resource: " + logical)
	if packer.flush() != OK: return _fail("Cannot finish target preview pack.")
	log_path = stage_path.path_join("target.log")
	var executable := OS.get_executable_path()
	var args := PackedStringArray(["--log-file", log_path, "--rendering-method", "gl_compatibility"])
	if OS.has_feature("editor"):
		args.append_array(["--main-pack", pack_path])
	else:
		var target := stage_path.path_join("target_preview.exe" if OS.get_name() == "Windows" else "target_preview.x86_64")
		var error := Executable.embed(executable, pack_path, target)
		if not error.is_empty(): return _fail(error)
		executable = target
	# Startup driver flags are consumed by Godot before get_cmdline_args().
	if AudioServer.get_driver_name() == "Dummy": args.append_array(["--audio-driver", "Dummy"])
	if headless: args.append("--headless")
	args.append_array(["--", "--page-mode", mode, "--page-entry", prepared.entry])
	var log := FileAccess.open(log_path, FileAccess.WRITE)
	if log == null: return _fail("Cannot create the target process log.")
	log.store_string("Starting independent target preview…\n"); log.close()
	pid = OS.create_process(executable, args)
	if pid <= 0: return _fail("Could not start the independent target process.")
	state = "running"
	return {"pid":pid, "log":log_path, "stage":stage_path, "pack":pack_path, "executable":executable, "entry":prepared.entry}

func prepare(workspace: RefCounted, mode: String = "project", entry: String = "", source_override: String = "") -> Dictionary:
	last_error = ""; _files.clear()
	if not mode in ["project", "timeline", "scene", "editor"]: return _fail("Unknown target entry mode.")
	var index := Index.new()
	index.scan(workspace)
	if not index.complete: return _fail("Target scan is incomplete:\n" + "\n".join(index.diagnostics))
	for problem: String in index.diagnostics:
		if problem.begins_with("Duplicate UID") or problem.begins_with("Case collision") or problem.begins_with("Invalid UID"): return _fail(problem)
	var config := Config.new()
	if config.open_project(workspace) != OK or config.read_only: return _fail("Cannot read target project.godot: " + config.last_error + "\n" + "\n".join(config.diagnostics))
	if FileAccess.file_exists(workspace.root_path.path_join("override.cfg")):
		var override := Config.inspect(FileAccess.get_file_as_string(workspace.root_path.path_join("override.cfg")))
		if override.has("error"): return _fail("Invalid target override.cfg: " + override.error)
		for key: String in override.entries:
			if key.contains("/") and config.set_literal(key, override.entries[key].literal) != OK: return _fail(config.last_error)
	stage_path = ProjectSettings.globalize_path("user://project_previews/" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(Time.get_ticks_usec()))
	var payload := stage_path.path_join("project")
	if DirAccess.make_dir_recursive_absolute(payload) != OK: return _fail("Cannot create independent preview directory.")
	var seed_error := _seed(payload)
	if not seed_error.is_empty(): return _fail(seed_error)
	for logical: String in index.resources:
		if logical.get_extension() == "import": continue
		var relative := logical.trim_prefix("res://")
		if relative in ["project.binary", "project.godot", "override.cfg"] or relative.begins_with("__page_preview/"): continue
		if not _copy(index.resources[logical].absolute, payload.path_join(relative)): return _fail("Cannot copy target resource: " + logical)
		_files[relative] = payload.path_join(relative)
	# Pinned native dependency must not silently replace a modified target plugin.
	var target_dialogic: String = workspace.root_path.path_join("addons/dialogic")
	if DirAccess.dir_exists_absolute(target_dialogic):
		var verification := _verify_dependency(target_dialogic, payload.path_join("addons/dialogic"))
		if not verification.is_empty(): return _fail(verification)
	# Convert supported media to ordinary native resources for a release runtime.
	for logical: String in index.resources:
		var kind: String = index.resources[logical].kind
		if kind in Media.IMAGES or kind in Media.AUDIO or kind in ["ttf", "otf", "woff", "woff2"]:
			var error := _prepare_media(logical, index.resources[logical].absolute, payload, workspace)
			if not error.is_empty(): return _fail(error)
	var classes_error := _classes(payload, index)
	if not classes_error.is_empty(): return _fail(classes_error)
	var uid_error := _uid_cache(payload)
	if not uid_error.is_empty(): return _fail(uid_error)
	if entry.begins_with("uid://"): entry = index.uids.get(entry, "")
	if mode == "project":
		entry = str(config.value("application/run/main_scene", ""))
		if entry.begins_with("uid://"): entry = index.uids.get(entry, "")
	if mode == "timeline" and not source_override.is_empty():
		if entry.is_empty(): entry = "res://__page_preview/buffer.dtl"
		if not _write(payload, entry.trim_prefix("res://"), source_override.to_utf8_buffer()): return _fail("Cannot prepare timeline buffer.")
	if not entry.begins_with("res://") or not _files.has(entry.trim_prefix("res://")): return _fail("Target entry is missing: " + entry)
	# Native resource directories are derived from the selected target only.
	var characters := {}; var timelines := {}
	for logical: String in index.resources:
		var kind: String = index.resources[logical].kind
		if not kind in ["dch", "dtl"]: continue
		var name := logical.get_file().get_basename()
		var directory: Dictionary = characters if kind == "dch" else timelines
		if directory.has(name): return _fail("Ambiguous Dialogic identifier: " + name)
		directory[name] = logical
	config.set_value("dialogic/directories/dch_directory", characters)
	config.set_value("dialogic/directories/dtl_directory", timelines)
	# Force only preview plumbing; target singletons retain their native relative order.
	config.set_value("autoload/Dialogic", "*res://addons/dialogic/Core/DialogicGameHandler.gd")
	config.set_value("application/run/main_scene", "res://__page_preview/entry.tscn")
	config.set_value("application/config/name", str(config.value("application/config/name", "Target")) + " — PAGE preview")
	config.set_value("application/config/use_custom_user_dir", true)
	config.set_value("application/config/custom_user_dir_name", "PAGE_Editor_Target_Preview/" + stage_path.get_file())
	config.set_value("application/config/disable_project_settings_override", true)
	config.set_value("application/run/flush_stdout_on_print", true)
	config.set_value("rendering/renderer/rendering_method", "gl_compatibility")
	config.set_value("editor_plugins/enabled", PackedStringArray())
	if config.value("input/dialogic_default_action") == null:
		config.set_literal("input/dialogic_default_action", '{"deadzone":0.5,"events":[Object(InputEventKey,"keycode":4194309),Object(InputEventMouseButton,"button_index":1)]}')
	if not _write(payload, "project.godot", config.content.to_utf8_buffer()): return _fail("Cannot write preview configuration.")
	var entry_script := FileAccess.get_file_as_bytes(payload.path_join("__page_preview/entry.gd"))
	if entry_script.is_empty(): return _fail("The packaged target runner source is missing.")
	if not _write(payload, "__page_preview/entry.gd", entry_script): return _fail("Cannot prepare target entry script.")
	if not _write(payload, "__page_preview/entry.tscn", '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://__page_preview/entry.gd" id="1"]\n[node name="PAGE_Target" type="Node"]\nscript = ExtResource("1")\n'.to_utf8_buffer()): return _fail("Cannot prepare target entry scene.")
	return {"entry":entry, "stage":stage_path, "files":_files.size(), "index_diagnostics":index.diagnostics}

func _seed(payload: String) -> String:
	var zip := ZIPReader.new()
	if zip.open("res://runtime/native_runtime.zip") != OK: return "Native runtime support is missing. Run tools/prepare_runtime.py after importing the Source project."
	for relative: String in zip.get_files():
		if relative.ends_with("/"): continue
		if relative.is_absolute_path() or relative.contains("..") or relative.contains("\\"): return "Invalid native runtime support path."
		if not _write(payload, relative, zip.read_file(relative)): return "Cannot prepare fixed dependency: " + relative
	zip.close()
	return ""

func _write(payload: String, relative: String, bytes: PackedByteArray) -> bool:
	var path := payload.path_join(relative)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes); file.flush(); file.close()
	if FileAccess.get_file_as_bytes(path) != bytes: return false
	_files[relative] = path
	return true

func _copy(source: String, destination: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK: return false
	return DirAccess.copy_absolute(source, destination) == OK and FileAccess.get_sha256(source) == FileAccess.get_sha256(destination)

func _verify_dependency(target: String, fixed: String) -> String:
	if Data._has_link_component(target): return "Target Dialogic contains a symbolic link: " + target
	for file: String in DirAccess.get_files_at(target):
		if file.ends_with(".import") or file.contains(".editor-"): continue
		if Data._has_link_component(target.path_join(file)): return "Target Dialogic contains a symbolic link: " + target.path_join(file)
		if not FileAccess.file_exists(fixed.path_join(file)) or FileAccess.get_sha256(target.path_join(file)) != FileAccess.get_sha256(fixed.path_join(file)): return "Target Dialogic differs from the pinned Alpha 20 dependency: " + target.path_join(file)
	for folder: String in DirAccess.get_directories_at(target):
		if folder.begins_with("."): continue
		var error := _verify_dependency(target.path_join(folder), fixed.path_join(folder))
		if not error.is_empty(): return error
	return ""

func _prepare_media(logical: String, absolute: String, payload: String, workspace: RefCounted) -> String:
	if FileAccess.file_exists(absolute + ".import") and not Data._has_link_component(absolute + ".import"):
		var metadata := FileAccess.get_file_as_string(absolute + ".import")
		if not Data._has_constructor(metadata):
			var imported := ConfigFile.new()
			if imported.parse(metadata) == OK:
				var outputs: Variant = imported.get_value("deps", "dest_files", [])
				var available: bool = (outputs is Array or outputs is PackedStringArray) and not outputs.is_empty()
				for path: String in outputs:
					var resolved: String = workspace.resolve_content_path(path)
					if resolved.is_empty() or not FileAccess.file_exists(resolved): available = false; break
				if available:
					for path: String in outputs:
						var relative := path.trim_prefix("res://")
						if not _copy(workspace.resolve_content_path(path), payload.path_join(relative)): return "Cannot copy target import: " + path
						_files[relative] = payload.path_join(relative)
					if _write(payload, logical.trim_prefix("res://") + ".import", metadata.to_utf8_buffer()): return ""
					return "Cannot copy target import metadata."
	var kind := logical.get_extension().to_lower()
	var resource: Resource
	if kind in Media.IMAGES:
		var image := Image.load_from_file(absolute)
		if image == null or image.is_empty(): return "Cannot decode target image: " + logical
		resource = ImageTexture.create_from_image(image)
	elif kind in Media.AUDIO: resource = Media.audio(absolute)
	else:
		var font := FontFile.new()
		if font.load_dynamic_font(absolute) != OK: return "Cannot decode target font: " + logical
		resource = font
	if resource == null: return "Cannot decode target media: " + logical
	var relative := ".godot/imported/page_" + logical.sha256_text() + ".res"
	var destination := payload.path_join(relative)
	if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK or ResourceSaver.save(resource, destination) != OK: return "Cannot prepare native media: " + logical
	_files[relative] = destination
	var config := ConfigFile.new()
	if FileAccess.file_exists(absolute + ".import"):
		var original := ConfigFile.new()
		var text := FileAccess.get_file_as_string(absolute + ".import")
		if not Data._has_constructor(text) and original.parse(text) == OK and original.has_section_key("remap", "uid"): config.set_value("remap", "uid", original.get_value("remap", "uid"))
	config.set_value("remap", "importer", "keep")
	config.set_value("remap", "type", resource.get_class())
	config.set_value("remap", "path", "res://" + relative)
	config.set_value("deps", "source_file", logical)
	config.set_value("deps", "dest_files", ["res://" + relative])
	var import_relative := logical.trim_prefix("res://") + ".import"
	if config.save(payload.path_join(import_relative)) != OK: return "Cannot prepare resource remap: " + logical
	_files[import_relative] = payload.path_join(import_relative)
	return ""

func _classes(payload: String, index: RefCounted) -> String:
	var config := ConfigFile.new()
	if config.load(payload.path_join(".godot/global_script_class_cache.cfg")) != OK: return "Native global class cache is missing."
	var classes: Array = config.get_value("", "list", [])
	var names := {}
	for item: Dictionary in classes: names[str(item["class"])] = str(item.path)
	for logical: String in index.resources:
		var resource: Dictionary = index.resources[logical]
		if resource.kind != "gd" or not resource.has("text"): continue
		var text: String = resource.text
		var found := RegEx.create_from_string('(?m)^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)').search(text)
		if found == null: continue
		var name := found.get_string(1)
		if names.has(name) or ClassDB.class_exists(name): return "Duplicate or reserved global class: " + name
		var base := _script_base(logical, index, [])
		if base.is_empty(): return "Cyclic or unresolved base script: " + logical
		classes.append({"base":base, "class":name, "icon":"", "is_abstract":text.contains("@abstract"), "is_tool":text.contains("@tool"), "language":"GDScript", "path":logical})
		names[name] = logical
	config.set_value("", "list", classes)
	return "" if config.save(payload.path_join(".godot/global_script_class_cache.cfg")) == OK else "Cannot save target global classes."

func _uid_cache(payload: String) -> String:
	var identities := {}
	for relative: String in _files:
		var uid := ""
		var target := "res://" + relative
		if relative.ends_with(".uid"):
			uid = FileAccess.get_file_as_string(_files[relative]).strip_edges(); target = target.trim_suffix(".uid")
		elif relative.get_extension() in ["tscn", "tres", "import"]:
			var text := FileAccess.get_file_as_string(_files[relative])
			var found := RegEx.create_from_string('(?m)^(?:\\[gd_[^\\n]*?\\s|)uid\\s*=\\s*"(uid://[^"]+)"').search(text)
			if found: uid = found.get_string(1); target = target.trim_suffix(".import")
		if uid.is_empty(): continue
		var id := ResourceUID.text_to_id(uid)
		if not Index.valid_uid(uid): return "Invalid target UID: " + relative
		if identities.has(id) and identities[id] != target: return "Target UID collides with another resource: " + uid
		identities[id] = target
	var file_path := payload.path_join(".godot/uid_cache.bin")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null: return "Cannot write target UID cache."
	# Godot 4.7.1 resource_uid.cpp: count(u32), id(u64), UTF-8 byte count(u32), bytes.
	file.store_32(identities.size())
	for id: int in identities:
		var bytes: PackedByteArray = str(identities[id]).to_utf8_buffer()
		file.store_64(id); file.store_32(bytes.size()); file.store_buffer(bytes)
	file.close(); _files[".godot/uid_cache.bin"] = file_path
	return ""

func _fail(message: String) -> Dictionary:
	last_error = message; state = "failed"
	return {"error":message}

func _script_base(logical: String, index: RefCounted, visited: Array) -> String:
	if logical in visited: return ""
	visited.append(logical)
	var text: String = index.resources.get(logical, {}).get("text", "")
	var found := RegEx.create_from_string('(?m)^\\s*extends\\s+([A-Za-z_][A-Za-z0-9_]*|"[^"\\n]+"|\'[^\'\\n]+\')').search(text)
	if found == null: return "RefCounted"
	var base := found.get_string(1)
	if base.begins_with('"') or base.begins_with("'"):
		var path := base.substr(1, base.length() - 2)
		if not path.begins_with("res://"): path = logical.get_base_dir().path_join(path).simplify_path()
		if not index.resources.has(path): return ""
		var named := RegEx.create_from_string('(?m)^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)').search(index.resources[path].get("text", ""))
		return named.get_string(1) if named else _script_base(path, index, visited)
	return base

func _cleanup_payload() -> void:
	# Only files created for this runner instance are disposable; logs remain.
	if stage_path.is_empty() or not stage_path.begins_with(ProjectSettings.globalize_path("user://project_previews/")) or Data._has_link_component(stage_path): return
	var directory := DirAccess.open(stage_path)
	if directory == null: return
	if directory.is_link("project"): DirAccess.remove_absolute(stage_path.path_join("project"))
	else: _remove_tree(stage_path.path_join("project"))
	for name: String in ["target.pck", "target_preview.exe", "target_preview.x86_64"]:
		var file := stage_path.path_join(name)
		if FileAccess.file_exists(file): DirAccess.remove_absolute(file)
	_files.clear()

func _remove_tree(path: String) -> void:
	if Data._has_link_component(path) or not DirAccess.dir_exists_absolute(path): return
	var directory := DirAccess.open(path)
	if directory == null: return
	directory.include_hidden = true
	for name: String in directory.get_files():
		var file := path.path_join(name)
		# Remove a link itself inside our own directory, never its destination.
		if directory.is_link(name) or not Data._has_link_component(file): DirAccess.remove_absolute(file)
	for name: String in directory.get_directories():
		if directory.is_link(name): DirAccess.remove_absolute(path.path_join(name))
		else: _remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
