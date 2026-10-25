extends "res://application/timeline_document.gd"

## Restricted, inert reader for the native LayeredPortrait scene format. Never
## ResourceLoader.load() a content-root scene or its external scripts.
const SCRIPT := "res://addons/dialogic/Modules/LayeredPortrait/custom_layered_portrait.gd"
const BASE_SCRIPT := "res://addons/dialogic/Modules/LayeredPortrait/layered_portrait.gd"
const PROPERTIES := ["position", "scale", "rotation", "visible", "z_index", "modulate", "offset", "centered", "flip_h", "flip_v", "fix_offset"]
var model: Dictionary = {}

func get_file_extension() -> String:
	return "tscn"

func open_file(file_path: String, source_workspace: RefCounted = null) -> Error:
	workspace = source_workspace
	var error := super.open_file(file_path)
	if error == OK:
		model = validate_content(content).get("model", {})
	return error

func save_file(file_path: String = "") -> Error:
	var target := _absolute_path(file_path) if not file_path.is_empty() else path
	if workspace == null or workspace.content_path(target).is_empty():
		return _fail(ERR_FILE_BAD_PATH, "Save the layered scene inside the selected content folder.")
	return super.save_file(file_path)

func update_model(next: Dictionary) -> Error:
	if read_only:
		return _fail(ERR_UNAVAILABLE, "Unsupported scene remains read-only.")
	var text := serialize(next)
	var checked := validate_content(text)
	if not checked.supported:
		return _fail(ERR_INVALID_DATA, "\n".join(checked.diagnostics))
	if next == model:
		return OK
	model = checked.model
	set_content(text)
	return OK

func validate_content(text: String) -> Dictionary:
	return inspect(text, workspace)

static func inspect_path(logical: String, source_workspace: RefCounted) -> Dictionary:
	if not logical.begins_with("res://") or logical.get_extension() != "tscn" or logical.begins_with("res://addons/"):
		return failure("Choose a native layered .tscn inside the content folder; other custom scenes require a later version.")
	var absolute: String = source_workspace.resolve_content_path(logical)
	if absolute.is_empty() or not FileAccess.file_exists(absolute):
		return failure("Layered scene is missing or leaves the content folder: " + logical)
	var bytes := FileAccess.get_file_as_bytes(absolute)
	if bytes.size() > 4 * 1024 * 1024 or bytes.has(0) or bytes.get_string_from_utf8().to_utf8_buffer() != bytes:
		return failure("Layered scene must be valid UTF-8, without NUL, at most 4 MiB.")
	return inspect(bytes.get_string_from_utf8(), source_workspace)

static func inspect(text: String, source_workspace: RefCounted) -> Dictionary:
	if text.to_utf8_buffer().size() > 4 * 1024 * 1024 or text.to_utf8_buffer().has(0):
		return failure("Layered scene exceeds 4 MiB or contains NUL.")
	var nodes: Array[Dictionary] = []
	var metadata: Dictionary = {}
	var resources: Dictionary = {}
	var paths: Dictionary = {}
	var unique_ids: Dictionary = {}
	var current := -1
	var seen_header := false
	var root_script := false
	var header_re := RegEx.create_from_string('^\\[([a-z_]+)(.*?)\\]$')
	var attr_re := RegEx.create_from_string('([a-z_]+)=("[^"\\r\\n]*"|[0-9]+)')
	for source_line: String in text.trim_prefix(String.chr(0xFEFF)).split("\n"):
		var line := source_line.strip_edges()
		if line.is_empty() or line.begins_with(";"): continue
		if line.begins_with("["):
			var header := header_re.search(line)
			if header == null: return failure("Invalid native scene header.")
			var attrs: Dictionary = {}
			var rest := header.get_string(2)
			for attr: RegExMatch in attr_re.search_all(rest):
				if attrs.has(attr.get_string(1)): return failure("Duplicate scene attribute.")
				attrs[attr.get_string(1)] = attr.get_string(2).trim_prefix('"').trim_suffix('"')
				rest = rest.replace(attr.get_string(), "")
			if not rest.strip_edges().is_empty(): return failure("Unknown scene header data remains read-only.")
			current = -1
			match header.get_string(1):
				"gd_scene":
					if seen_header or attrs.get("format", "") != "3": return failure("Expected one Godot format 3 scene header.")
					for key: String in attrs:
						if not key in ["load_steps", "format", "uid"]: return failure("Unknown scene header attribute.")
					seen_header = true
					if attrs.has("uid"): metadata["scene_uid"] = attrs.uid
				"ext_resource":
					if not seen_header or not nodes.is_empty(): return failure("Resource declarations must precede scene nodes.")
					for key: String in attrs:
						if not key in ["type", "path", "id", "uid"]: return failure("Unknown external resource attribute.")
					var id: String = attrs.get("id", "")
					var resource_path: String = attrs.get("path", "")
					if id.is_empty() or resources.has(id): return failure("Missing or duplicate resource id.")
					if attrs.get("type") == "Script":
						if not resource_path in [SCRIPT, BASE_SCRIPT]: return failure("External or custom scripts are not executed.")
					elif attrs.get("type") == "Texture2D":
						if source_workspace == null or resource_path.get_extension().to_lower() != "png": return failure("Layer sprites require content-root PNG images.")
						var absolute: String = source_workspace.resolve_content_path(resource_path)
						if absolute.is_empty(): return failure("Layer image leaves the content folder.")
						var problem: String = source_workspace.validate_png(absolute)
						if not problem.is_empty(): return failure(problem)
					else: return failure("Only the bundled layered script and PNG textures are supported.")
					resources[id] = attrs
				"node":
					if not seen_header or nodes.size() >= 1024: return failure("Invalid scene or more than 1024 layers.")
					for key: String in attrs:
						if not key in ["name", "type", "parent", "unique_id"]: return failure("Instanced, inherited or custom nodes remain read-only.")
					var name_value: String = attrs.get("name", "")
					var parent: String = attrs.get("parent", "")
					var type: String = attrs.get("type", "")
					if name_value.is_empty() or name_value in [".", ".."] or RegEx.create_from_string('[/:@"%{}\\[\\]\\x00-\\x1f]').search(name_value): return failure("Invalid layer name.")
					var path_value := "." if nodes.is_empty() else (name_value if parent == "." else parent.path_join(name_value))
					if paths.has(path_value): return failure("Duplicate layer path.")
					if nodes.is_empty():
						if type != "CanvasGroup" or not parent.is_empty(): return failure("Layered root must be CanvasGroup.")
					elif not type in ["Node2D", "Sprite2D"] or not paths.has(parent): return failure("Layers must be Sprite2D or Node2D with an existing parent.")
					paths[path_value] = nodes.size()
					nodes.append({"name": name_value, "type": type, "parent": parent, "path": path_value, "properties": {}, "image": ""})
					current = nodes.size() - 1
					if attrs.has("unique_id"):
						var native_id: String = attrs.unique_id
						if not native_id.is_valid_int() or native_id.to_int() <= 0 or unique_ids.has(native_id.to_int()):
							return failure("Invalid or duplicate native node unique_id.")
						nodes[current]["unique_id"] = native_id.to_int()
						unique_ids[native_id.to_int()] = true
				_: return failure("Subresources, connections and other scene sections remain read-only.")
			continue
		if current < 0 or not line.contains(" = "): return failure("Unexpected scene content remains read-only.")
		var split := line.find(" = ")
		var key := line.left(split)
		var raw := line.substr(split + 3)
		var node: Dictionary = nodes[current]
		if key in ["script", "texture"]:
			var reference := RegEx.create_from_string('^ExtResource\\("([^"\\r\\n]+)"\\)$').search(raw)
			if reference == null or not resources.has(reference.get_string(1)): return failure("Unknown external resource reference.")
			var resource: Dictionary = resources[reference.get_string(1)]
			if key == "script":
				if current != 0 or root_script or resource.type != "Script": return failure("Only the root may have the fixed layered script.")
				root_script = true
				if resource.path != SCRIPT: metadata["script_path"] = resource.path
				if resource.has("uid"): metadata["script_uid"] = resource.uid
			else:
				if node.type != "Sprite2D" or not node.image.is_empty() or resource.type != "Texture2D": return failure("Invalid sprite texture.")
				node.image = resource.path
				if resource.has("uid"):
					if not metadata.has("image_uids"): metadata["image_uids"] = {}
					metadata.image_uids[resource.path] = resource.uid
			continue
		if not key in PROPERTIES or node.properties.has(key): return failure("Unknown or duplicate layer property: " + key)
		if key in ["fix_offset"] and current != 0: return failure("fix_offset belongs to the root.")
		if key in ["offset", "centered", "flip_h", "flip_v"] and node.type != "Sprite2D": return failure("Sprite property on a non-sprite node.")
		if not RegEx.create_from_string('^(?:true|false|-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|(?:Vector2|Color)\\([0-9., eE+\\-]+\\))$').search(raw): return failure("Only finite inert scene values are supported.")
		var value: Variant = str_to_var(raw)
		if not valid_property(key, value): return failure("Invalid layer property: " + key)
		node.properties[key] = value
	if nodes.is_empty() or not root_script: return failure("Scene requires a CanvasGroup root and the fixed native layered script.")
	metadata["nodes"] = nodes
	return {"supported": true, "diagnostics": [], "model": metadata}

static func valid_property(key: String, value: Variant) -> bool:
	if key in ["position", "scale", "offset"]: return value is Vector2 and is_finite(value.x) and is_finite(value.y)
	if key == "rotation": return (value is int or value is float) and is_finite(value)
	if key == "z_index": return value is int and value >= -4096 and value <= 4096
	if key == "modulate": return value is Color and is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	return value is bool

static func serialize(value: Dictionary) -> String:
	var images: Dictionary = {}
	for node: Dictionary in value.get("nodes", []):
		if not node.get("image", "").is_empty(): images[node.image] = "T%d" % images.size()
	var scene_uid := ' uid=' + var_to_str(value.scene_uid) if value.has("scene_uid") else ""
	var script_uid := ' uid=' + var_to_str(value.script_uid) if value.has("script_uid") else ""
	var text := '[gd_scene load_steps=%d format=3%s]\n\n[ext_resource type="Script" path=%s%s id="S"]\n' % [images.size() + 2, scene_uid, var_to_str(value.get("script_path", SCRIPT)), script_uid]
	for path: String in images:
		var uid := ' uid=' + var_to_str(value.image_uids[path]) if value.get("image_uids", {}).has(path) else ""
		text += '[ext_resource type="Texture2D" path=%s%s id="%s"]\n' % [var_to_str(path), uid, images[path]]
	for node: Dictionary in value.get("nodes", []):
		text += '\n[node name=%s type=%s%s%s]\n' % [var_to_str(node.name), var_to_str(node.type), ' parent=' + var_to_str(node.parent) if not node.parent.is_empty() else "", ' unique_id=' + str(node.unique_id) if node.has("unique_id") else ""]
		if node.parent.is_empty(): text += 'script = ExtResource("S")\n'
		for key: String in node.get("properties", {}): text += key + " = " + var_to_str(node.properties[key]) + "\n"
		if not node.get("image", "").is_empty(): text += 'texture = ExtResource("%s")\n' % images[node.image]
	return text

static func runtime_scene(value: Dictionary, source_workspace: RefCounted) -> PackedScene:
	var nodes: Dictionary = {}
	var root: CanvasGroup
	for info: Dictionary in value.nodes:
		var node: Node2D
		match info.type:
			"CanvasGroup":
				root = CanvasGroup.new()
				root.set_script(preload(SCRIPT))
				node = root
			"Node2D": node = Node2D.new()
			_: node = Sprite2D.new()
		node.name = info.name
		if node != root:
			nodes[info.parent].add_child(node)
			node.owner = root
		for key: String in info.properties: node.set(key, info.properties[key])
		if not info.image.is_empty():
			var image := Image.load_from_file(source_workspace.resolve_content_path(info.image))
			if image == null or image.is_empty():
				root.free()
				return null
			node.texture = ImageTexture.create_from_image(image)
		nodes[info.path] = node
	var scene := PackedScene.new()
	var result := scene.pack(root)
	root.free()
	return scene if result == OK else null

static func commands_error(extra: String, model_value: Dictionary) -> String:
	if extra.is_empty(): return ""
	var layers: Dictionary = {}
	for node: Dictionary in model_value.nodes: layers[node.path] = node.type
	for item: String in extra.split(","):
		var parts := item.strip_edges().split(" ", false, 1)
		if parts.size() != 2 or not parts[0] in ["show", "hide", "set"] or not layers.has(parts[1]) or parts[1] == ".": return "Use show, hide or set with an existing layer path."
		if parts[0] == "set" and layers[parts[1]] != "Sprite2D": return "The set command requires a Sprite2D layer."
	return ""

static func failure(message: String) -> Dictionary:
	return {"supported": false, "diagnostics": [message], "model": {}}
