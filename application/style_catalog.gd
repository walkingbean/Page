extends RefCounted

const Native = preload("res://application/native_resource.gd")
var _workspace_ref: WeakRef
var workspace: RefCounted:
	get: return _workspace_ref.get_ref() if _workspace_ref != null else null
	set(value): _workspace_ref = weakref(value) if value != null else null
var settings: RefCounted
var styles: Dictionary = {}
var paths: Dictionary = {}
var diagnostics: Array[String] = []

func refresh(source_workspace: RefCounted) -> void:
	workspace = source_workspace
	styles.clear(); paths.clear(); diagnostics.clear()
	settings = load("res://application/text_settings_document.gd").new()
	var error: Error = settings.open_root(workspace)
	if error != OK or settings.read_only:
		diagnostics.append(settings.last_error if error != OK else "\n".join(settings.diagnostics))
		return
	var list: Array = settings.values.get("layout/style_list", []).duplicate()
	var default_path: String = settings.values.get("layout/default_style", "")
	if not default_path.is_empty() and not default_path in list: list.append(default_path)
	var directory: Dictionary = settings.values.get("layout/style_directory", {})
	for value: Variant in directory.values():
		if not value is String: diagnostics.append("Style directory paths must be strings."); continue
		if not value.is_empty() and not value in list: list.append(value)
	var cache := {}
	for path: Variant in list:
		if not path is String: diagnostics.append("Invalid style path."); continue
		var checked := Native.inspect_path(path, workspace, [], cache)
		if checked.has("error") or not checked.get("resource") is DialogicStyle:
			diagnostics.append(path + ": " + checked.get("error", "Expected native DialogicStyle."))
			continue
		var style: DialogicStyle = checked.resource
		if styles.has(style.name) and paths[style.name] != path:
			diagnostics.append("Duplicate style name: " + style.name)
			continue
		styles[style.name] = style
		paths[style.name] = path
		styles[path] = style
		paths[path] = path
		if path == default_path: styles[""] = style; paths[""] = path
	for name: Variant in directory:
		if not name is String or not directory[name] is String: continue
		if directory[name].is_empty(): continue
		if styles.has(directory[name]):
			if styles.has(name) and paths[name] != directory[name]: diagnostics.append("Conflicting native style directory entry: " + name)
			else: styles[name] = styles[directory[name]]; paths[name] = directory[name]

func error_for(name: String) -> String:
	if not diagnostics.is_empty(): return "\n".join(diagnostics)
	if name.is_empty() and not styles.has(""): return ""
	return "" if styles.has(name) else "Style '%s' was not found in the selected content root's native style index." % name

func register(logical: String, make_default := false, clear_default := false) -> Error:
	var document = load("res://application/text_settings_document.gd").new()
	var error: Error = document.open_root(workspace)
	if error != OK: diagnostics.assign([document.last_error]); return error
	var loaded := Native.inspect_path(logical, workspace, [], {})
	if loaded.has("error") or not loaded.get("resource") is DialogicStyle: diagnostics.assign([loaded.get("error", "Expected native style.")]); return ERR_INVALID_DATA
	var list: Array = document.values.get("layout/style_list", []).duplicate()
	if not logical in list: list.append(logical)
	var directory: Dictionary = document.values.get("layout/style_directory", {}).duplicate()
	for alias: Variant in directory.keys():
		if directory[alias] == logical: directory.erase(alias)
	var names := {}
	for path: String in list:
		var item := Native.inspect_path(path, workspace, [], {})
		if item.has("error") or not item.get("resource") is DialogicStyle: diagnostics.assign([item.get("error", "Invalid style index resource.")]); return ERR_INVALID_DATA
		if names.has(item.resource.name) or (directory.has(item.resource.name) and directory[item.resource.name] != path): diagnostics.assign(["Another style already uses this name."]); return ERR_ALREADY_EXISTS
		names[item.resource.name] = path
		directory[item.resource.name] = path
	var default_path: String = logical if make_default else document.values.get("layout/default_style", "")
	if clear_default and default_path == logical: default_path = ""
	if not default_path.is_empty(): directory[""] = default_path
	else: directory.erase("")
	for key: String in {"layout/style_list":list, "layout/style_directory":directory, "layout/default_style":default_path}:
		error = document.set_value(key, {"layout/style_list":list, "layout/style_directory":directory, "layout/default_style":default_path}[key])
		if error != OK: diagnostics.assign([document.last_error]); return error
	error = document.save_file()
	if error != OK: diagnostics.assign([document.last_error]); return error
	refresh(workspace)
	return OK

func runtime(resources: Array[Resource], prefix: String, asset_cache: Dictionary) -> Dictionary:
	if not diagnostics.is_empty(): return Native.failure("\n".join(diagnostics))
	var directory := {}
	var by_path := {}
	var clones := {}
	var mapped_styles := {}
	for name: String in styles:
		var logical: String = paths[name]
		if not by_path.has(logical):
			var clone := _clone_style(styles[name], clones)
			var mapped := _map_style(clone, resources, prefix, asset_cache, mapped_styles)
			if not mapped.is_empty(): return Native.failure(mapped)
			var virtual := prefix.path_join("style_%d.tres" % resources.size())
			clone.take_over_path(virtual); resources.append(clone)
			by_path[logical] = virtual
		directory[name] = by_path[logical]
	return {"directory": directory}

func _clone_style(style: DialogicStyle, clones: Dictionary) -> DialogicStyle:
	# Native layout reuse compares inheritance roots by object identity. Keep
	# one private clone per content resource across the entire style directory.
	var identity := style.get_instance_id()
	if clones.has(identity): return clones[identity]
	var clone: DialogicStyle = style.duplicate(false)
	clones[identity] = clone
	clone.layer_list = style.layer_list.duplicate()
	clone.layer_info = {}
	for id: String in style.layer_info:
		var layer: DialogicStyleLayer = style.layer_info[id].duplicate(false)
		layer.overrides = style.layer_info[id].overrides.duplicate(true)
		clone.layer_info[id] = layer
	clone.inherits = _clone_style(style.inherits, clones) if style.inherits != null else null
	return clone

func _map_style(style: DialogicStyle, resources: Array[Resource], prefix: String, cache: Dictionary, mapped_styles: Dictionary) -> String:
	var identity := style.get_instance_id()
	if mapped_styles.has(identity): return ""
	mapped_styles[identity] = true
	if style.inherits != null:
		var issue := _map_style(style.inherits, resources, prefix, cache, mapped_styles)
		if not issue.is_empty(): return issue
	for id: String in style.layer_info:
		var info := style.get_layer_inherited_info(id)
		var schema := Native.schema(info.path)
		var layer: DialogicStyleLayer = style.layer_info[id]
		for key: String in layer.overrides:
			if schema.get(key, {}).get("hint") != PROPERTY_HINT_FILE: continue
			var decoded := Native.decode(layer.overrides[key])
			var logical: String = decoded.get("value", layer.overrides[key])
			if logical.is_empty() or Native.is_bundled(logical): continue
			if not cache.has(logical):
				var asset := Native.inspect_path(logical, workspace, [], {})
				if asset.has("error"): return asset.error
				var virtual := prefix.path_join("asset_%d.%s" % [resources.size(), logical.get_extension()])
				asset.resource.take_over_path(virtual); resources.append(asset.resource); cache[logical] = virtual
			layer.overrides[key] = var_to_str(cache[logical])
	return ""

static func presentation_capabilities(style: DialogicStyle) -> Dictionary:
	var paths: Array[String] = []
	for id: String in style.get_layer_inherited_list(): paths.append(style.get_layer_inherited_info(id).path)
	var bubble_base: bool = style.get_layer_inherited_info("").path == Native.PARTS + "Base_TextBubble/text_bubble_base.tscn"
	var bubble_layer: bool = Native.PARTS + "Layer_Textbubble/text_bubble_layer.tscn" in paths
	var bubble: bool = bubble_base and bubble_layer
	var text: bool = bubble or Native.PARTS + "Layer_VN_Textbox/vn_textbox_layer.tscn" in paths or Native.PARTS + "Layer_SpeakerPortraitTextbox/textbox_with_speaker_portrait.tscn" in paths
	# The fixed bubble base's text callback needs its matching dynamic layer.
	if bubble_base and not bubble_layer: text = false
	return {"text": text, "choice": bubble or Native.PARTS + "Layer_VN_Choices/vn_choice_layer.tscn" in paths, "input": Native.PARTS + "Layer_TextInput/text_input_layer.tscn" in paths}
