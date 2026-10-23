extends SceneTree
## Synchronize generated project, export and scene branding before exporting.
## --check reports configuration drift without writing files.
## godot --headless --path . --script res://tools/apply_branding.gd [-- --check]

const Identity = preload("res://application/app_identity.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var validation: Dictionary = Identity.validate_config()
	if not validation["valid"]:
		_fail("\n".join(validation["errors"]))
		return
	var values: Dictionary = validation["values"]
	var paths: Array[String] = ["res://project.godot", "res://export_presets.cfg", "res://ui/components/resource_sidebar.tscn", "res://ui/components/top_navigation.tscn"]
	var originals: Array[String] = []
	for path: String in paths:
		if not FileAccess.file_exists(path):
			_fail("Missing generated configuration: " + path)
			return
		originals.append(FileAccess.get_file_as_string(path))
	var project: String = originals[0]
	project = _set_key(project, "application", "config/name", values["project_name"])
	project = _set_key(project, "application", "config/version", values["version"])
	project = _set_key(project, "application", "config/icon", values["app_icon_svg"])
	project = _set_key(project, "application", "config/use_custom_user_dir", true)
	project = _set_key(project, "application", "config/custom_user_dir_name", values["user_data_directory"])
	var presets: String = originals[1]
	var config := ConfigFile.new()
	if config.parse(presets) != OK:
		_fail("Cannot parse export_presets.cfg.")
		return
	var core_version: String = str(values["version"]).split("-")[0].split("+")[0] + ".0"
	for section: String in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var platform: String = str(config.get_value(section, "platform", ""))
		var extension := ".exe" if platform == "Windows Desktop" else ".x86_64"
		var folder := "windows" if platform == "Windows Desktop" else "linux"
		if platform not in ["Windows Desktop", "Linux"]:
			continue
		presets = _set_key(presets, section, "export_path", "builds/%s/%s%s" % [folder, values["artifact_stem"], extension])
		# All resources includes logos referenced only by branding.cfg. Exported
		# runtime resolves imported SVG textures when source bytes are omitted.
		presets = _set_key(presets, section, "include_filter", "*.dtl,*.dch,*.cfg,*.txt,*.svg")
		presets = _set_key(presets, section, "exclude_filter", "tests/*,docs/*,builds/*,tools/*,examples/*,*.md")
		if platform == "Windows Desktop":
			presets = _set_key(presets, section + ".options", "application/modify_resources", true)
			presets = _set_key(presets, section + ".options", "application/icon", values["app_icon_svg"])
			presets = _set_key(presets, section + ".options", "application/product_name", values["project_name"])
			presets = _set_key(presets, section + ".options", "application/file_description", values["project_name"])
			presets = _set_key(presets, section + ".options", "application/file_version", core_version)
			presets = _set_key(presets, section + ".options", "application/product_version", core_version)
	var sidebar: String = _set_scene_texture(originals[2], "2_logo", values["logo_svg"])
	var navigation: String = _set_scene_texture(originals[3], "1_home", values["app_icon_svg"])
	if sidebar.is_empty() or navigation.is_empty():
		_fail("The branding texture entries are missing from the interface scenes.")
		return
	var updated: Array[String] = [project, presets, sidebar, navigation]
	for text: String in [project, presets]:
		if ConfigFile.new().parse(text) != OK:
			_fail("Generated metadata is invalid; no files were changed.")
			return
	var changed: bool = updated != originals
	if "--check" in OS.get_cmdline_user_args():
		if changed:
			_fail("Branding metadata is out of date. Run this command without --check before exporting.")
			return
		print("BRANDING_CHECK_RESULT: synchronized")
		quit(0)
		return
	if changed and not _commit_files(paths, originals, updated):
		return
	for folder: String in ["res://builds/windows", "res://builds/linux"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	print("BRANDING_APPLY_RESULT: " + str(values["project_name"]) + " " + str(values["version"]))
	quit(0)


func _set_key(source: String, section: String, key: String, value: Variant) -> String:
	var lines: PackedStringArray = source.split("\n", true)
	var first: int = -1
	var last: int = lines.size()
	for index: int in lines.size():
		var line: String = lines[index].strip_edges()
		if line == "[" + section + "]":
			first = index
		elif first >= 0 and line.begins_with("["):
			last = index
			break
	var replacement: String = key + "=" + var_to_str(value)
	if first < 0:
		return source.trim_suffix("\n") + "\n\n[" + section + "]\n\n" + replacement + "\n"
	for index: int in range(first + 1, last):
		if lines[index].split("=", true, 1)[0].strip_edges() == key:
			lines[index] = replacement
			return "\n".join(lines)
	lines.insert(first + 1, replacement)
	return "\n".join(lines)


func _set_scene_texture(source: String, resource_id: String, path: String) -> String:
	var lines: PackedStringArray = source.split("\n", true)
	for index: int in lines.size():
		var line: String = lines[index].strip_edges()
		if line.begins_with("[ext_resource ") and line.ends_with('id="' + resource_id + '"]'):
			lines[index] = '[ext_resource type="Texture2D" path=' + var_to_str(path) + ' id="' + resource_id + '"]'
			return "\n".join(lines)
	return ""


func _commit_files(paths: Array[String], originals: Array[String], updated: Array[String]) -> bool:
	# All candidates are prepared before the first source file is replaced.
	# Restore original text if an ordinary write fails; this is not crash-atomic.
	for index: int in paths.size():
		var error: Error = _write_verified(paths[index], updated[index])
		if error != OK:
			var recovery_errors: Array[String] = []
			for restore: int in range(index + 1):
				if _write_verified(paths[restore], originals[restore]) != OK:
					recovery_errors.append(paths[restore])
			_fail("Could not update branding metadata (error %d)." % error + (" Restore these files from your Source backup: " + ", ".join(recovery_errors) if not recovery_errors.is_empty() else " Original metadata restored."))
			return false
	return true


func _write_verified(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written: bool = file.store_string(text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if not written or error != OK or FileAccess.get_file_as_string(path) != text:
		return ERR_FILE_CANT_WRITE
	return OK


func _fail(message: String) -> void:
	printerr("BRANDING_ERROR: " + message)
	quit(1)
