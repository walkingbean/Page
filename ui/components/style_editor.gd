extends Window

signal saved
const Document = preload("res://application/style_document.gd")
const Native = preload("res://application/native_resource.gd")
const Field = preload("res://ui/components/native_value_field.gd")
var workspace: RefCounted
var document: RefCounted
var browser: OptionButton
var preset: OptionButton
var name_field: LineEdit
var parent_field: LineEdit
var path_field: LineEdit
var default_field: CheckBox
var layer_list: ItemList
var scene_picker: OptionButton
var fields_column: VBoxContainer
var fields: Dictionary = {}
var selected_layer := ""
var message: Label
var save_button: Button
var file_dialog: FileDialog
var import_dialog: FileDialog
var discard_dialog: ConfirmationDialog
var creation_dialog: ConfirmationDialog
var pending: Callable
var initial_name := ""
var initial_parent := ""
var initial_default := false
var active_asset_field: LineEdit
var _loading := false
var initial_path := ""

func _ready() -> void:
	title = "Styles & layouts"; size = Vector2i(1100, 740); min_size = Vector2i(800, 480); transient = true; exclusive = true; visible = false
	var layout := VBoxContainer.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(layout)
	var toolbar := HBoxContainer.new(); layout.add_child(toolbar)
	browser = OptionButton.new(); browser.name = "Styles"; browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL; browser.fit_to_longest_item = false; toolbar.add_child(browser)
	browser.item_selected.connect(func(index: int): _transition(func(): _open_path(browser.get_item_metadata(index))))
	button(toolbar, "Open", func(): file_dialog.popup_centered_ratio(0.75))
	preset = OptionButton.new()
	for key: String in Document.PRESETS: preset.add_item(key)
	toolbar.add_child(preset)
	button(toolbar, "New", func(): _transition(_new_style))
	var header_scroll := ScrollContainer.new(); header_scroll.custom_minimum_size.y = 125; header_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; layout.add_child(header_scroll)
	var headers := VBoxContainer.new(); headers.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header_scroll.add_child(headers)
	name_field = line(headers, "Style name", "StyleName")
	path_field = line(headers, "File in content folder", "StylePath")
	parent_field = line(headers, "Inherit from · blank for none", "ParentStyle")
	default_field = CheckBox.new(); default_field.text = "Default style for this content project"; headers.add_child(default_field)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; split.split_offset = 220; layout.add_child(split)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 180; split.add_child(left)
	layer_list = ItemList.new(); layer_list.name = "LayoutLayers"; layer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; layer_list.custom_minimum_size.y = 130; left.add_child(layer_list)
	layer_list.item_selected.connect(_select_layer)
	scene_picker = OptionButton.new(); scene_picker.fit_to_longest_item = false; scene_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; left.add_child(scene_picker)
	for folder: String in DirAccess.get_directories_at(Native.PARTS):
		if folder.begins_with("Layer_"):
			for file: String in DirAccess.get_files_at(Native.PARTS.path_join(folder)):
				if file.ends_with(".tscn") and not file in ["text_bubble.tscn", "example_history_item.tscn"]:
					scene_picker.add_item(folder.trim_prefix("Layer_")); scene_picker.set_item_metadata(scene_picker.item_count - 1, Native.PARTS.path_join(folder).path_join(file))
	var layer_tools := HBoxContainer.new(); left.add_child(layer_tools)
	button(layer_tools, "+", _add_layer); button(layer_tools, "−", _remove_layer); button(layer_tools, "↑", func(): _move_layer(-1)); button(layer_tools, "↓", func(): _move_layer(1))
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; split.add_child(scroll)
	fields_column = VBoxContainer.new(); fields_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; fields_column.add_theme_constant_override("separation", 6); scroll.add_child(fields_column)
	var message_scroll := ScrollContainer.new(); message_scroll.custom_minimum_size.y = 56; message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; layout.add_child(message_scroll)
	message = Label.new(); message.name = "StyleMessage"; message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; message.size_flags_horizontal = Control.SIZE_EXPAND_FILL; message_scroll.add_child(message)
	var footer := HBoxContainer.new(); layout.add_child(footer)
	button(footer, "Apply layer", _apply_fields)
	button(footer, "Import font / image", func(): import_dialog.popup_centered_ratio(0.7))
	save_button = button(footer, "Save style & register", save_style)
	button(footer, "Close", _request_close)
	file_dialog = FileDialog.new(); file_dialog.access = FileDialog.ACCESS_FILESYSTEM; file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; file_dialog.filters = PackedStringArray(["*.tres ; Dialogic style"]); add_child(file_dialog)
	file_dialog.file_selected.connect(func(path: String): _transition(func(): _open_path(path)))
	import_dialog = FileDialog.new(); import_dialog.access = FileDialog.ACCESS_FILESYSTEM; import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; import_dialog.filters = PackedStringArray(["*.ttf,*.otf,*.png ; Font or image"]); import_dialog.file_selected.connect(_import_asset); add_child(import_dialog)
	discard_dialog = ConfirmationDialog.new(); discard_dialog.dialog_text = "Discard unsaved style changes?"; discard_dialog.confirmed.connect(func():
		if pending.is_valid(): pending.call()); add_child(discard_dialog)
	creation_dialog = ConfirmationDialog.new(); creation_dialog.dialog_text = "Saving this style will create a native project.godot to register it in the content project. Continue?"; creation_dialog.confirmed.connect(func(): save_style(true)); add_child(creation_dialog)
	close_requested.connect(_request_close)

func button(parent: Node, caption: String, action: Callable) -> Button:
	var b := Button.new(); b.text = caption; b.name = caption.replace(" ", "").replace("/", ""); b.pressed.connect(action); parent.add_child(b); return b

func line(parent: Node, caption: String, node_name: String) -> LineEdit:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := Label.new(); label.text = caption; label.custom_minimum_size.x = 220; row.add_child(label)
	var field := LineEdit.new(); field.name = node_name; field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(field); return field

func open_styles(source_workspace: RefCounted) -> void:
	workspace = source_workspace
	browser.clear()
	if workspace.style_catalog != null:
		for key: String in workspace.style_catalog.styles:
			if key.is_empty() or key.begins_with("res://"): continue
			browser.add_item(key); browser.set_item_metadata(browser.item_count - 1, workspace.resolve_content_path(workspace.style_catalog.paths[key]))
	file_dialog.current_dir = workspace.root_path
	if browser.item_count > 0: _open_path(browser.get_item_metadata(0))
	else: _new_style()
	_popup_fitted()

func _new_style() -> void:
	document = Document.new()
	var error: Error = document.create_preset("New Style", preset.get_item_text(preset.selected), workspace)
	if error != OK: message.text = document.last_error; return
	path_field.text = "res://new_style.tres"
	_refresh_form()

func _open_path(path: String) -> void:
	var candidate = Document.new()
	var error: Error = candidate.open_file(path, workspace)
	if error != OK: message.text = candidate.last_error; return
	document = candidate; path_field.text = workspace.content_path(path)
	_refresh_form()

func _refresh_form(preserve_header := false) -> void:
	var header: Array = [name_field.text, parent_field.text, default_field.button_pressed] if preserve_header else []
	_loading = true
	layer_list.clear(); fields.clear()
	for child: Node in fields_column.get_children(): fields_column.remove_child(child); child.queue_free()
	save_button.disabled = document.read_only or document.style == null
	if document.style == null:
		message.text = "\n".join(document.diagnostics); _loading = false; return
	name_field.text = document.style.name
	initial_name = name_field.text
	var parent: Variant = document.root_properties().get("inherits")
	parent_field.text = ""
	if parent is Dictionary:
		for section: Dictionary in document.model.sections:
			if section.kind == "ext_resource" and section.attrs.id == parent.id: parent_field.text = section.attrs.path
	initial_parent = parent_field.text
	default_field.button_pressed = not document.path.is_empty() and workspace.text_settings.values.get("layout/default_style", "") == workspace.content_path(document.path)
	initial_default = default_field.button_pressed
	if not preserve_header: initial_path = path_field.text
	if preserve_header:
		name_field.text = header[0]; parent_field.text = header[1]; default_field.button_pressed = header[2]
	layer_list.add_item("Base layout"); layer_list.set_item_metadata(0, "")
	for id: String in document.style.get_layer_inherited_list():
		var info: Dictionary = document.style.get_layer_inherited_info(id)
		layer_list.add_item(id + " · " + info.path.get_base_dir().get_file().trim_prefix("Layer_")); layer_list.set_item_metadata(layer_list.item_count - 1, id)
	message.text = "Native style and layout overrides. Inherited layer order is edited in the parent."
	_loading = false
	layer_list.select(0); _select_layer(0)

func _select_layer(index: int) -> void:
	if _loading or document == null or document.style == null: return
	if not _apply_fields(): return
	selected_layer = layer_list.get_item_metadata(index)
	_show_fields()

func _show_fields() -> void:
	fields.clear(); active_asset_field = null
	for child: Node in fields_column.get_children(): fields_column.remove_child(child); child.queue_free()
	var info: Dictionary = document.style.get_layer_inherited_info(selected_layer)
	var schema := Native.schema(info.path)
	for key: String in schema:
		var value: Variant = schema[key].default
		if info.overrides.has(key):
			var parsed := Native.decode(info.overrides[key]); value = parsed.get("value", info.overrides[key])
		var row := HBoxContainer.new(); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; fields_column.add_child(row)
		var field := Field.new(); field.name = key; field.setup(key.replace("_", " ").capitalize(), value, schema[key]); row.add_child(field); fields[key] = field
		button(row, "Reset", func():
			if document.set_override(selected_layer, key, null, true) != OK: message.text = document.last_error
			else: _show_fields())
		if schema[key].hint == PROPERTY_HINT_FILE and field.control is LineEdit:
			field.control.focus_entered.connect(func(): active_asset_field = field.control)

func _apply_fields() -> bool:
	if _loading or document == null or document.style == null or document.read_only: return true
	for key: String in fields:
		var field: Control = fields[key]
		if not field.is_changed(): continue
		var value: Variant = field.value()
		if not field.last_error.is_empty(): message.text = field.last_error; return false
		if document.set_override(selected_layer, key, value) != OK: message.text = document.last_error; return false
		field.initial = value
	return true

func _add_layer() -> void:
	if document == null or not _apply_fields(): return
	if document.add_layer(scene_picker.get_item_metadata(scene_picker.selected)) != OK: message.text = document.last_error; return
	_refresh_form(true)

func _remove_layer() -> void:
	if document == null or not _apply_fields(): return
	if document.remove_layer(selected_layer) != OK: message.text = document.last_error; return
	_refresh_form(true)

func _move_layer(delta: int) -> void:
	if document == null or not _apply_fields(): return
	if document.move_layer(selected_layer, delta) != OK: message.text = document.last_error; return
	_refresh_form(true)

func dirty() -> bool:
	if document == null: return false
	if path_field.text != initial_path or document.dirty or name_field.text != initial_name or parent_field.text != initial_parent or default_field.button_pressed != initial_default: return true
	for field: Control in fields.values():
		if field.is_changed(): return true
	return false

func _transition(action: Callable) -> void:
	if dirty(): pending = action; discard_dialog.popup_centered()
	else: action.call()

func _request_close() -> void:
	_transition(hide)

func save_style(creation_confirmed := false) -> void:
	if document == null or document.read_only or not _apply_fields(): return
	if not FileAccess.file_exists(workspace.root_path.path_join("project.godot")) and not creation_confirmed: creation_dialog.popup_centered(); return
	var target: String = workspace.resolve_content_path(path_field.text.strip_edges())
	if target.is_empty() or target.get_extension() != "tres": message.text = "Choose a portable res://... .tres path inside the content folder."; return
	if name_field.text.strip_edges().is_empty(): message.text = "Enter a style name."; return
	var fresh_catalog = preload("res://application/style_catalog.gd").new()
	fresh_catalog.refresh(workspace)
	if not fresh_catalog.diagnostics.is_empty(): message.text = "\n".join(fresh_catalog.diagnostics); return
	if fresh_catalog.paths.has(name_field.text) and fresh_catalog.paths[name_field.text] != workspace.content_path(target): message.text = "Another style already uses this name."; return
	var snapshot: Dictionary = document.model.duplicate(true)
	document.root_properties()["name"] = name_field.text
	if document.update_model(document.model) != OK: document.model = snapshot; message.text = document.last_error; return
	if parent_field.text != initial_parent and document.set_inheritance(parent_field.text.strip_edges()) != OK: message.text = document.last_error; return
	if document.save_file(target) != OK: message.text = document.last_error; return
	var registered: Error = workspace.style_catalog.register(workspace.content_path(target), default_field.button_pressed, initial_default and not default_field.button_pressed)
	if registered != OK:
		message.text = "Style file saved; native index was not updated: " + "\n".join(workspace.style_catalog.diagnostics) + " Reopen settings or retry registration."
		return
	workspace.refresh(); saved.emit(); _open_path(target)
	message.text = "Saved style and native project index."

func _import_asset(path: String) -> void:
	var logical: String = workspace.import_text_asset(path)
	if logical.is_empty(): message.text = workspace.last_error; return
	if is_instance_valid(active_asset_field): active_asset_field.text = logical; active_asset_field.text_changed.emit(logical)
	message.text = "Imported: " + logical

func _popup_fitted() -> void:
	var desired := Vector2i(1100, 740)
	if is_embedded():
		var host := get_parent().get_window()
		desired.x = mini(desired.x, maxi(min_size.x, host.size.x - 40))
		desired.y = mini(desired.y, maxi(min_size.y, host.size.y - 60))
	popup_centered(desired)
