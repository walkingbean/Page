extends "res://application/timeline_document.gd"

const Native = preload("res://application/native_resource.gd")
const PRESETS := {
	"Visual Novel": Native.PARTS + "Style_VN_Default/default_vn_style.tres",
	"Text Bubbles": Native.PARTS + "Style_TextBubbles/textbubble_style.tres",
	"Speaker Textbox": Native.PARTS + "Style_SpeakerTextbox/speaker_textbox_style.tres"
}
var model: Dictionary = {}
var style: DialogicStyle

func get_file_extension() -> String:
	return "tres"

func create_preset(name_value: String, preset: String, source_workspace: RefCounted) -> Error:
	workspace = source_workspace
	new_document()
	if not PRESETS.has(preset): return _fail(ERR_INVALID_PARAMETER, "Choose a native style preset.")
	var parsed := Native.scan(FileAccess.get_file_as_string(PRESETS[preset]))
	if parsed.has("error"): return _fail(ERR_INVALID_DATA, parsed.error)
	model = parsed.model
	model.sections[0].attrs.erase("uid")
	root_properties()["name"] = name_value
	return update_model(model)

func open_file(file_path: String, source_workspace: RefCounted = null) -> Error:
	workspace = source_workspace
	if workspace == null or workspace.content_path(file_path).is_empty(): return _fail(ERR_FILE_BAD_PATH, "Open a style inside the selected content folder.")
	var error := super.open_file(file_path)
	if error == OK:
		var checked := inspect(content)
		model = checked.get("model", {})
		style = checked.get("resource")
	return error

func validate_content(text: String) -> Dictionary:
	var checked := inspect(text)
	return {"supported": not checked.has("error"), "diagnostics": [checked.error] if checked.has("error") else []}

func inspect(text: String) -> Dictionary:
	var parsed := Native.scan(text)
	if parsed.has("error"): return parsed
	var chain: Array[String] = []
	var check_path := _validation_path if not _validation_path.is_empty() else path
	if workspace != null and not check_path.is_empty(): chain.append(workspace.content_path(check_path))
	var built := Native.build(parsed.model, workspace, chain, {})
	if built.has("error"): return built
	if not built.resource is DialogicStyle: return Native.failure("Select a native DialogicStyle .tres resource.")
	built["model"] = parsed.model
	return built

func update_model(next: Dictionary) -> Error:
	if read_only: return _fail(ERR_UNAVAILABLE, "Unsupported styles remain read-only.")
	var text := Native.serialize(next)
	var checked := inspect(text)
	if checked.has("error"): return _fail(ERR_INVALID_DATA, checked.error)
	model = checked.model
	style = checked.resource
	set_content(text)
	return OK

func save_file(file_path: String = "") -> Error:
	var target := _absolute_path(file_path) if not file_path.is_empty() else path
	if workspace == null or workspace.content_path(target).is_empty(): return _fail(ERR_FILE_BAD_PATH, "Save the style inside the selected content folder.")
	return super.save_file(target)

func root_properties() -> Dictionary:
	for section: Dictionary in model.get("sections", []):
		if section.kind == "resource": return section.props
	return {}

func layer_properties(id: String, create := false) -> Dictionary:
	var root := root_properties()
	var info: Dictionary = root.get("layer_info", {})
	if not info.has(id) and create:
		var resource_id := new_id("Layer")
		model.sections.insert(model.sections.size() - 1, {"kind": "sub_resource", "attrs": {"type": "Resource", "id": resource_id}, "props": {"script": external(Native.LAYER_SCRIPT, "Script"), "overrides": {}}})
		info[id] = Native.make_reference("SubResource", resource_id)
		root["layer_info"] = info
	if not info.has(id): return {}
	var ref: Dictionary = info[id]
	for section: Dictionary in model.sections:
		if section.kind == "sub_resource" and section.attrs.id == ref.id: return section.props
	return {}

func new_id(prefix: String) -> String:
	var ids := []
	for section: Dictionary in model.sections: ids.append(str(section.attrs.get("id", "")))
	var i := 1
	while prefix + str(i) in ids: i += 1
	return prefix + str(i)

func external(logical: String, type: String) -> Dictionary:
	for section: Dictionary in model.sections:
		if section.kind == "ext_resource" and section.attrs.path == logical and section.attrs.type == type: return Native.make_reference("ExtResource", section.attrs.id)
	var id := new_id("External")
	model.sections.insert(1, {"kind": "ext_resource", "attrs": {"type": type, "path": logical, "id": id}, "props": {}})
	return Native.make_reference("ExtResource", id)

func add_layer(scene_path: String) -> Error:
	if style != null and style.inherits != null: return _fail(ERR_UNAVAILABLE, "Inherited styles use the root style's layer order; edit the parent to add or reorder layers.")
	var id := "10"
	var index := 16
	while root_properties().get("layer_info", {}).has(id): index += 1; id = String.num_int64(index, 16)
	var snapshot := model.duplicate(true)
	layer_properties(id, true)["scene"] = external(scene_path, "PackedScene")
	root_properties().get("layer_list", []).append(id)
	var error := update_model(model)
	if error != OK: model = snapshot
	return error

func remove_layer(id: String) -> Error:
	if id.is_empty() or (style != null and style.inherits != null): return _fail(ERR_UNAVAILABLE, "The base and inherited layer order cannot be removed here.")
	var snapshot := model.duplicate(true)
	root_properties().layer_list.erase(id)
	root_properties().layer_info.erase(id)
	var error := update_model(model)
	if error != OK: model = snapshot
	return error

func move_layer(id: String, delta: int) -> Error:
	if style != null and style.inherits != null: return _fail(ERR_UNAVAILABLE, "Reorder layers in the parent style.")
	var order: Array = root_properties().get("layer_list", [])
	var index := order.find(id)
	if index < 0 or index + delta < 0 or index + delta >= order.size(): return OK
	var snapshot := model.duplicate(true)
	order.remove_at(index); order.insert(index + delta, id)
	var error := update_model(model)
	if error != OK: model = snapshot
	return error

func set_override(id: String, key: String, value: Variant, remove := false) -> Error:
	var snapshot := model.duplicate(true)
	var info := layer_properties(id, true)
	var overrides: Dictionary = info.get("overrides", {})
	if remove: overrides.erase(key)
	else: overrides[key] = var_to_str(value)
	info["overrides"] = overrides
	var error := update_model(model)
	if error != OK: model = snapshot
	return error

func set_inheritance(logical: String) -> Error:
	var snapshot := model.duplicate(true)
	if logical.is_empty():
		root_properties().erase("inherits")
	else:
		root_properties()["inherits"] = external(logical, "Resource")
	var error := update_model(model)
	if error != OK: model = snapshot
	return error
