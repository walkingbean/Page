extends RefCounted
const Transaction = preload("res://application/project_transaction.gd")
const Config = preload("res://application/project_document.gd")

static func catalog(index: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var config := Config.new()
	config.open_project(index.workspace)
	var folder := str(config.value("dialogic/extensions_folder", "res://addons/dialogic_additions/")).trim_suffix("/")
	for logical: String in index.resources:
		if logical.begins_with(folder + "/") and logical.get_file() == "index.gd" and logical.trim_prefix(folder + "/").count("/") == 1:
			var text: String = index.resources[logical].get("text", "")
			var categories: Array[String] = []
			for method: String in ["events", "subsystems", "editors", "settings_pages", "character_editor_sections", "text_effects", "text_modifiers", "special_resources", "portrait_scene_presets", "style_presets", "layout_parts"]:
				if text.contains("func _get_" + method + "("): categories.append(method)
			result.append({"path":logical, "categories":categories})
	return result

static func create_example(workspace: RefCounted, identifier: String) -> Dictionary:
	if not identifier.is_valid_identifier() or identifier.begins_with("_"): return {"error":"Choose an extension identifier using letters, digits and underscores."}
	var tree := Engine.get_main_loop() as SceneTree
	var native := tree.root.get_node_or_null("Dialogic") if tree != null else null
	if native != null and native.has_node(NodePath(identifier)): return {"error":"Extension subsystem name is reserved by the native runtime: " + identifier}
	var config := Config.new()
	if config.open_project(workspace) != OK or config.read_only: return {"error":"Invalid target project configuration."}
	var folder := str(config.value("dialogic/extensions_folder", "res://addons/dialogic_additions/")).trim_suffix("/").path_join(identifier)
	var absolute: String = workspace.resolve_content_path(folder)
	if absolute.is_empty() or DirAccess.dir_exists_absolute(absolute) or folder.begins_with("res://addons/dialogic/"): return {"error":"Choose a new extension folder outside the fixed dependency."}
	if DirAccess.dir_exists_absolute(absolute.get_base_dir()):
		for existing: String in DirAccess.get_directories_at(absolute.get_base_dir()):
			if existing.to_lower() == identifier.to_lower(): return {"error":"Extension folder collides by case: " + existing}
	var files := example_files(identifier, folder)
	var changes: Array[Dictionary] = []
	for name: String in files:
		changes.append({"path":absolute.path_join(name), "before":null, "after":str(files[name]).to_utf8_buffer()})
	var result := Transaction.commit(workspace, changes)
	if not result.has("error"): result["folder"] = folder
	return result

static func example_files(identifier: String, folder: String) -> Dictionary:
	var files := {}
	files["index.gd"] = '@tool\nextends DialogicIndexer\n\nfunc _get_events() -> Array:\n\treturn [this_folder.path_join("event.gd")]\n\nfunc _get_subsystems() -> Array[Dictionary]:\n\treturn [{"name":"%s", "script":this_folder.path_join("subsystem.gd")}]\n\nfunc _get_editors() -> Array[String]:\n\treturn [this_folder.path_join("editor.tscn")]\n\nfunc _get_special_resources() -> Dictionary:\n\treturn {"Animation":list_animations("animations")}\n\nfunc _get_portrait_scene_presets() -> Array[Dictionary]:\n\treturn [{"name":"%s portrait", "path":this_folder.path_join("portrait.tscn")}]\n\nfunc _get_layout_parts() -> Array[Dictionary]:\n\treturn [{"name":"%s layer", "type":"Layer", "path":this_folder.path_join("layout.tscn"), "description":"Native custom overlay"}]\n' % [identifier, identifier, identifier]
	files["event.gd"] = '@tool\nextends DialogicEvent\n\nfunc _init() -> void:\n\tevent_name = "%s"\n\tevent_category = "Custom"\n\nfunc get_shortcode() -> String:\n\treturn "%s"\n\nfunc _execute() -> void:\n\tdialogic.get_subsystem("%s").count += 1\n\tprint("CUSTOM_EVENT_EXECUTED")\n\tfinish()\n' % [identifier, identifier.to_lower(), identifier]
	files["subsystem.gd"] = 'extends DialogicSubsystem\nvar count := 0\n\nfunc _post_install() -> void:\n\tprint("CUSTOM_SUBSYSTEM_INSTALLED")\n'
	files["editor.gd"] = "@tool\nextends DialogicEditor\nvar field: TextEdit\nvar picker: FileDialog\nvar status: Label\nvar loaded_path := \"\"\nvar loaded_hash := \"\"\n\nfunc _ready() -> void:\n\tvar box := VBoxContainer.new()\n\tbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)\n\tadd_child(box)\n\tvar label := Label.new()\n\tlabel.text = \"Native extension editor — %s\"\n\tbox.add_child(label)\n\tfield = TextEdit.new()\n\tfield.custom_minimum_size = Vector2(600, 260)\n\tfield.text = \"Edit this message, then Save editor to a native .cfg file.\"\n\tbox.add_child(field)\n\tfield.text_changed.connect(func(): current_resource_state = ResourceStates.UNSAVED)\n\tvar open_button := Button.new()\n\topen_button.text = \"Open native config\"\n\tbox.add_child(open_button)\n\tstatus = Label.new()\n\tstatus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART\n\tbox.add_child(status)\n\tpicker = FileDialog.new()\n\tpicker.access = FileDialog.ACCESS_FILESYSTEM\n\tpicker.add_filter(\"*.cfg\", \"Godot configuration\")\n\tadd_child(picker)\n\tpicker.file_selected.connect(_selected)\n\topen_button.pressed.connect(func():\n\t\tpicker.file_mode = FileDialog.FILE_MODE_OPEN_FILE\n\t\tpicker.popup_centered_ratio(0.8))\n\nfunc _get_title() -> String:\n\treturn \"%s\"\n\nfunc _open(_extra: Variant = null) -> void:\n\tstatus.text = \"Choose an output file explicitly. Preview source files remain unchanged.\"\n\tprint(\"CUSTOM_EDITOR_OPENED\")\n\nfunc _save() -> void:\n\tpicker.file_mode = FileDialog.FILE_MODE_SAVE_FILE\n\tpicker.current_file = \"extension_settings.cfg\"\n\tpicker.popup_centered_ratio(0.8)\n\nfunc _selected(path: String) -> void:\n\tvar config := ConfigFile.new()\n\tif picker.file_mode == FileDialog.FILE_MODE_OPEN_FILE:\n\t\tif config.load(path) != OK:\n\t\t\tstatus.text = \"Cannot open config: \" + path\n\t\t\treturn\n\t\tfield.text = str(config.get_value(\"custom\", \"message\", \"\"))\n\telse:\n\t\tif FileAccess.file_exists(path) and (path != loaded_path or FileAccess.get_sha256(path) != loaded_hash):\n\t\t\tstatus.text = \"Output already exists or changed externally. Open it first or choose a new file.\"\n\t\t\treturn\n\t\tif path == loaded_path and config.load(path) != OK:\n\t\t\tstatus.text = \"Cannot reload the original config.\"\n\t\t\treturn\n\t\tconfig.set_value(\"custom\", \"message\", field.text)\n\t\tif config.save(path) != OK:\n\t\t\tstatus.text = \"Cannot save config: \" + path\n\t\t\treturn\n\t\tprint(\"CUSTOM_EDITOR_SAVED \", path)\n\tloaded_path = path\n\tloaded_hash = FileAccess.get_sha256(path)\n\tcurrent_resource_state = ResourceStates.SAVED\n\tstatus.text = \"Native config: \" + path\n" % [identifier, identifier]
	files["editor.tscn"] = scene(folder.path_join("editor.gd"), "Control", "CustomEditor")
	files["portrait.gd"] = 'extends DialogicPortrait\n\nfunc _ready() -> void:\n\tvar shape := Polygon2D.new()\n\tshape.name = "Shape"\n\tshape.polygon = PackedVector2Array([Vector2(-60, 0), Vector2(60, 0), Vector2(0, -180)])\n\tshape.color = Color(0.4, 0.7, 1.0)\n\tadd_child(shape)\n\nfunc _get_covered_rect() -> Rect2:\n\treturn Rect2(-60, -180, 120, 180)\n\nfunc _update_portrait(_who: DialogicCharacter, _which: String) -> void:\n\tprint("CUSTOM_PORTRAIT_UPDATED ", _which)\n\nfunc _set_mirror(mirrored: bool) -> void:\n\t$Shape.scale.x = -1.0 if mirrored else 1.0\n\nfunc _set_extra_data(data: String) -> void:\n\tprint("CUSTOM_PORTRAIT_EXTRA ", data)\n'
	files["portrait.tscn"] = scene(folder.path_join("portrait.gd"), "Node2D", "CustomPortrait")
	files["animations/pulse.gd"] = 'extends DialogicAnimation\n\nfunc animate() -> void:\n\tvar tween := node.create_tween()\n\ttween.tween_property(node, "modulate:a", 0.5, time / 2.0)\n\ttween.tween_property(node, "modulate:a", 1.0, time / 2.0)\n\tawait tween.finished\n\tfinished_once.emit()\n\nfunc _get_named_variations() -> Dictionary:\n\treturn {"%s pulse":{"type":AnimationType.ACTION}}\n' % identifier
	files["layout.gd"] = '@tool\nextends DialogicLayoutLayer\n'
	files["layout.tscn"] = '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="%s/layout.gd" id="1"]\n[node name="CustomLayer" type="Control"]\nscript = ExtResource("1")\nlayout_mode = 3\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\nmouse_filter = 2\n[node name="Label" type="Label" parent="."]\noffset_left = 20.0\noffset_top = 20.0\ntext = "Custom Dialogic layout layer"\n' % folder
	files[identifier.to_lower() + "_example.dtl"] = '[' + identifier.to_lower() + ']\nNative extension event completed.\n'
	return files

static func scene(script: String, kind: String, node_name: String) -> String:
	return '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="%s" id="1"]\n[node name="%s" type="%s"]\nscript = ExtResource("1")\n' % [script, node_name, kind]
