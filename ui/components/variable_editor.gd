extends VBoxContainer

signal new_requested
signal choose_folder_requested
signal save_requested
signal apply_requested
signal delete_requested
signal selection_requested(variable_name: Variant)
signal fields_changed

## Typed-variable form inside the supplied PageContent shell.
## https://docs.godotengine.org/en/4.7/classes/class_itemlist.html
## https://docs.godotengine.org/en/4.7/classes/class_textedit.html

var title_label: Label
var path_label: Label
var diagnostics_label: Label
var item_list: ItemList
var name_field: LineEdit
var value_field: TextEdit
const Literal = preload("res://application/variable_literal.gd")
var type_selector: OptionButton
var type_label: Label
var new_button: Button
var save_button: Button
var apply_button: Button
var delete_button: Button
var folder_button: Button
var _values: Dictionary = {}
var _selected_name: Variant = ""
var _has_root := false
var _document_read_only := false
var _field_editable := false
var _new_item := false
var _updating := false
var _enabled := true


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	var header := PanelContainer.new()
	header.name = "Header"
	header.custom_minimum_size.y = 46
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.109804, 0.109804, 0.117647)
	style.border_width_bottom = 1
	style.border_color = Color(0.07, 0.07, 0.08)
	header.add_theme_stylebox_override("panel", style)
	add_child(header)
	var header_margin := _margin(13, 6)
	header.add_child(header_margin)
	var header_row := HBoxContainer.new()
	header_margin.add_child(header_row)
	title_label = _label("Variables", 16)
	title_label.name = "VariableTitle"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_color_override("font_color", Color(0.843137, 0.772549, 0.552941))
	header_row.add_child(title_label)
	new_button = _button(header_row, "New", "New variable (Ctrl+N)", func(): new_requested.emit())
	save_button = _button(header_row, "Save", "Save variable defaults (Ctrl+S)", func(): save_requested.emit())
	var scroll := ScrollContainer.new()
	scroll.name = "VariableScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var margin := _margin(12, 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	path_label = _label("Choose a content folder to manage variables.", 11)
	path_label.name = "VariableConfigPath"
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(path_label)
	var folder_row := HBoxContainer.new()
	column.add_child(folder_row)
	folder_button = _button(folder_row, "Choose Content Folder", "Select the folder whose variable defaults will be edited", func(): choose_folder_requested.emit())
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(split)
	item_list = ItemList.new()
	item_list.name = "VariableList"
	item_list.custom_minimum_size = Vector2(190, 220)
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.size_flags_stretch_ratio = 0.75
	item_list.item_selected.connect(_on_item_selected)
	split.add_child(item_list)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fields.custom_minimum_size.x = 220
	fields.add_theme_constant_override("separation", 8)
	split.add_child(fields)
	fields.add_child(_label("Name"))
	name_field = LineEdit.new()
	name_field.name = "VariableName"
	name_field.placeholder_text = "e.g. player_name"
	name_field.custom_minimum_size.y = 32
	name_field.text_changed.connect(func(_text: String): _emit_fields_changed())
	fields.add_child(name_field)
	var hint := _label("Letters, digits and underscores; cannot start with a digit. Names are case-sensitive.", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(hint)
	type_selector = OptionButton.new()
	type_selector.name = "VariableTypeSelector"
	for kind: int in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
		type_selector.add_item(type_string(kind), kind)
	type_selector.item_selected.connect(func(_index: int): _emit_fields_changed())
	fields.add_child(type_selector)
	type_label = _label("Default value", 12)
	type_label.name = "VariableType"
	fields.add_child(type_label)
	value_field = TextEdit.new()
	value_field.name = "VariableValue"
	value_field.placeholder_text = "String: any text; Int/Float: number; Bool: true or false"
	value_field.custom_minimum_size.y = 140
	value_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	value_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	value_field.text_changed.connect(_emit_fields_changed)
	fields.add_child(value_field)
	var actions := HBoxContainer.new()
	fields.add_child(actions)
	apply_button = _button(actions, "Apply", "Apply fields to the unsaved variable list", func(): apply_requested.emit())
	delete_button = _button(actions, "Delete", "Delete this definition; timeline references are not changed", func(): delete_requested.emit())
	var reference_hint := _label("Use {variable_name} in narration or character dialogue. Renaming or deleting a definition does not rewrite timeline files.", 11)
	reference_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(reference_hint)
	column.add_child(HSeparator.new())
	diagnostics_label = _label("Choose a content folder to begin.", 12)
	diagnostics_label.name = "Diagnostics"
	diagnostics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(diagnostics_label)
	_refresh_state()


func show_document(values: Dictionary, selected_name: Variant, has_root: bool, read_only: bool) -> void:
	_values = values.duplicate(true)
	_has_root = has_root
	_document_read_only = read_only
	_updating = true
	item_list.clear()
	var keys: Array = values.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for key: Variant in keys:
		var supported: bool = key is String and Literal.supported(values[key]) and _valid_identifier(key)
		var caption: String = str(key) if key is String else "[" + type_string(typeof(key)) + "] " + str(key)
		var index: int = item_list.add_item(caption + ("" if supported else "  [read-only]"))
		item_list.set_item_metadata(index, key)
		item_list.set_item_tooltip(index, caption + (" · " + type_string(typeof(values[key])) if supported else " · Preserved read-only: " + var_to_str(values[key])))
	_updating = false
	show_selection(selected_name)


func show_selection(variable_name: Variant, new_item: bool = false) -> void:
	_updating = true
	_selected_name = variable_name
	_new_item = new_item
	item_list.deselect_all()
	for index: int in item_list.item_count:
		if not new_item and item_list.get_item_metadata(index) == variable_name:
			item_list.select(index)
			item_list.ensure_current_is_visible()
	var exists := not new_item and _values.has(variable_name)
	_field_editable = new_item or (exists and variable_name is String and Literal.supported(_values[variable_name]) and _valid_identifier(variable_name))
	name_field.text = str(variable_name) if exists else ""
	value_field.text = str(_values[variable_name]) if exists and _values[variable_name] is String else (var_to_str(_values[variable_name]) if exists else "")
	type_label.text = "Default value" if _field_editable else ("Read-only · " + type_string(typeof(_values[variable_name])) if exists else "Select a variable or choose New")
	var kind: int = typeof(_values[variable_name]) if exists and _field_editable else TYPE_STRING
	type_selector.select(maxi(0, type_selector.get_item_index(kind)))
	type_label.text = "Default value (Bool: true / false)" if _field_editable else type_label.text
	_updating = false
	_refresh_state()


func get_fields() -> Dictionary:
	var parsed: Dictionary = Literal.parse_field(value_field.text, type_selector.get_selected_id())
	return {"name": name_field.text, "value": value_field.text, "type": type_selector.get_selected_id(), "parsed_value": parsed.get("value"), "error": parsed.get("error", "")}


func select_list_item(variable_name: Variant) -> void:
	# Restore the selection after a rejected form change without losing its text.
	item_list.deselect_all()
	for index: int in item_list.item_count:
		if item_list.get_item_metadata(index) == variable_name:
			item_list.select(index)
			item_list.ensure_current_is_visible()


func set_document_state(title: String, path: String, message: String, read_only: bool) -> void:
	title_label.text = title
	title_label.tooltip_text = title
	path_label.text = path if not path.is_empty() else "Choose a content folder to manage variables."
	path_label.tooltip_text = path_label.text
	diagnostics_label.text = message
	_document_read_only = read_only
	_refresh_state()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_refresh_state()


func focus_editor() -> void:
	if name_field.editable:
		name_field.grab_focus()
	else:
		item_list.grab_focus()


func _refresh_state() -> void:
	var editable := _enabled and _has_root and not _document_read_only
	new_button.disabled = not _enabled or (_has_root and _document_read_only)
	save_button.disabled = not editable
	folder_button.disabled = not _enabled
	item_list.mouse_filter = Control.MOUSE_FILTER_STOP if _enabled else Control.MOUSE_FILTER_IGNORE
	name_field.editable = editable and _field_editable
	value_field.editable = editable and _field_editable
	type_selector.disabled = not editable or not _field_editable
	apply_button.disabled = not editable or not _field_editable
	delete_button.disabled = not editable or not _field_editable or _new_item or _selected_name.is_empty()


func _on_item_selected(index: int) -> void:
	if not _updating and _enabled:
		selection_requested.emit(item_list.get_item_metadata(index))


func _emit_fields_changed() -> void:
	if not _updating and _enabled and _field_editable and not _document_read_only:
		fields_changed.emit()


func _valid_identifier(value: String) -> bool:
	return RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*$").search(value) != null


func _label(caption: String, font_size: int = 13) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _margin(horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	return margin


func _button(row: HBoxContainer, caption: String, hint: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = caption.replace(" ", "") + "Button"
	button.text = caption
	button.tooltip_text = hint
	button.custom_minimum_size.y = 32
	button.pressed.connect(callback)
	row.add_child(button)
	return button
