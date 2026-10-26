extends VBoxContainer

signal new_requested
signal open_requested
signal save_requested
signal save_as_requested
signal portrait_requested
signal fields_changed(fields: Dictionary)
signal portrait_selected(path: String)
signal layered_requested(path: String)

# A form inside the supplied PageContent shell. File ownership and validation
# remain in the application controller, including native .dch preservation.
# https://docs.godotengine.org/en/stable/classes/class_colorpickerbutton.html

var title_label: Label
var identifier_field: LineEdit
var display_name_field: LineEdit
var color_button: ColorPickerButton
var portrait_preview: TextureRect
var portrait_empty_label: Label
var portrait_path_label: Label
var diagnostics_label: Label
var new_button: Button
var open_button: Button
var save_button: Button
var save_as_button: Button
var portrait_button: Button
var clear_portrait_button: Button
var form_scroll: ScrollContainer

var document_opened := false
var document_read_only := false
var _enabled := true
var _identifier_editable := false
var _updating_fields := false
var _portrait_path := ""
var nicknames_field: TextEdit
var description_field: TextEdit
var custom_info_field: CodeEdit
var style_field: LineEdit
var text_prefix_field: LineEdit
var text_suffix_field: LineEdit
var style_picker: MenuButton
var character_scale: SpinBox
var character_x: SpinBox
var character_y: SpinBox
var character_mirror: CheckBox
var portrait_list: ItemList
var portrait_name_field: LineEdit
var default_selector: OptionButton
var preset_selector: OptionButton
var scene_path_field: LineEdit
var portrait_scale: SpinBox
var portrait_x: SpinBox
var portrait_y: SpinBox
var portrait_mirror: CheckBox
var ignore_scale: CheckBox
var _extra_controls: Array[Control] = []
var _portraits: Dictionary = {}
var _default := ""
var _selected := ""



func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	_build_header()
	_build_form()
	_refresh_state()


func _build_header() -> void:
	var panel := PanelContainer.new()
	panel.name = "Header"
	panel.custom_minimum_size.y = 46
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.109804, 0.109804, 0.117647)
	style.border_width_bottom = 1
	style.border_color = Color(0.07, 0.07, 0.08)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := _margin(13, 6)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	margin.add_child(row)
	title_label = Label.new()
	title_label.name = "CharacterName"
	title_label.text = "Characters"
	title_label.custom_minimum_size.x = 70
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0.843137, 0.772549, 0.552941))
	row.add_child(title_label)
	new_button = _button(row, "New", "Create a character", func() -> void: _request(new_requested))
	open_button = _button(row, "Open", "Open a Dialogic .dch character", func() -> void: _request(open_requested))
	save_button = _button(row, "Save", "Save character (Ctrl+S)", func() -> void: _request(save_requested, true))
	save_as_button = _button(row, "Save As", "Save character as (Ctrl+Shift+S)", func() -> void: _request(save_as_requested, true))


func _build_form() -> void:
	form_scroll = ScrollContainer.new()
	form_scroll.name = "CharacterScroll"
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form_scroll.follow_focus = true
	add_child(form_scroll)
	var margin := _margin(12, 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var mode := _label("CHARACTER  /  Native .dch", 12)
	mode.add_theme_color_override("font_color", Color(0.64, 0.67, 0.72))
	column.add_child(mode)
	var fields_row := HBoxContainer.new()
	fields_row.add_theme_constant_override("separation", 20)
	column.add_child(fields_row)
	var fields := VBoxContainer.new()
	fields.custom_minimum_size.x = 220
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 8)
	fields_row.add_child(fields)
	fields.add_child(_label("Identifier"))
	identifier_field = _field("IdentifierField", "e.g. Alice")
	identifier_field.tooltip_text = "Used by timelines. Existing characters use the .dch filename; choose a filename with Save As."
	identifier_field.text_changed.connect(_on_text_changed)
	fields.add_child(identifier_field)
	var identifier_hint := _label("The .dch filename is the timeline identifier.", 11)
	identifier_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identifier_hint.add_theme_color_override("font_color", Color(0.52, 0.55, 0.61))
	fields.add_child(identifier_hint)
	fields.add_child(_label("Display name"))
	display_name_field = _field("DisplayNameField", "Name shown during dialogue")
	display_name_field.text_changed.connect(_on_text_changed)
	fields.add_child(display_name_field)
	fields.add_child(_label("Name color"))
	color_button = ColorPickerButton.new()
	color_button.name = "NameColorButton"
	color_button.custom_minimum_size = Vector2(140, 32)
	color_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	color_button.tooltip_text = "Dialogic character name color"
	color_button.color = Color.WHITE
	color_button.color_changed.connect(func(_color: Color) -> void: _emit_fields_changed())
	fields.add_child(color_button)
	var portrait_column := VBoxContainer.new()
	portrait_column.custom_minimum_size.x = 220
	portrait_column.add_theme_constant_override("separation", 8)
	fields_row.add_child(portrait_column)
	portrait_column.add_child(_label("Selected portrait"))
	var preview_panel := PanelContainer.new()
	preview_panel.name = "PortraitPanel"
	preview_panel.custom_minimum_size = Vector2(220, 164)
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.09, 0.09, 0.10)
	preview_style.set_corner_radius_all(4)
	preview_panel.add_theme_stylebox_override("panel", preview_style)
	portrait_column.add_child(preview_panel)
	portrait_preview = TextureRect.new()
	portrait_preview.name = "PortraitPreview"
	portrait_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(portrait_preview)
	portrait_empty_label = _label("No portrait", 12)
	portrait_empty_label.name = "PortraitPlaceholder"
	portrait_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_empty_label.add_theme_color_override("font_color", Color(0.52, 0.55, 0.61))
	preview_panel.add_child(portrait_empty_label)
	var portrait_actions := HBoxContainer.new()
	portrait_column.add_child(portrait_actions)
	portrait_button = _button(portrait_actions, "Choose PNG", "Choose a PNG for the selected portrait", func() -> void: _request(portrait_requested, true))
	clear_portrait_button = _button(portrait_actions, "Clear", "Remove the portrait reference", _clear_portrait)
	portrait_path_label = _label("No portrait selected", 11)
	portrait_path_label.name = "PortraitPath"
	portrait_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	portrait_path_label.add_theme_color_override("font_color", Color(0.58, 0.61, 0.66))
	column.add_child(portrait_path_label)
	_build_extended_form(column)
	column.add_child(HSeparator.new())
	diagnostics_label = _label("Create or open a character to begin.", 12)
	diagnostics_label.name = "Diagnostics"
	diagnostics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnostics_label.add_theme_color_override("font_color", Color(0.69, 0.72, 0.77))
	column.add_child(diagnostics_label)


func _margin(horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	return margin


func _label(caption: String, font_size: int = 13) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _field(node_name: String, placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.name = node_name
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = 32
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var input_font := SystemFont.new()
	input_font.font_names = PackedStringArray(["Noto Sans", "DejaVu Sans", "Microsoft YaHei", "Noto Sans CJK SC", "Yu Gothic"])
	input_font.fallbacks = [preload("res://asset/fonts/NotoSansCJKsc-Regular.otf")]
	field.add_theme_font_override("font", input_font)
	return field


func _button(row: HBoxContainer, caption: String, hint: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = caption.replace(" ", "") + "Button"
	button.text = caption
	button.tooltip_text = hint
	button.custom_minimum_size.y = 32
	button.pressed.connect(callback)
	row.add_child(button)
	return button


func show_document(title: String, identifier: String, character: DialogicCharacter, read_only: bool = false, message: String = "", identifier_editable: bool = false) -> void:
	_updating_fields = true
	document_opened = character != null
	_identifier_editable = identifier_editable
	identifier_field.text = identifier
	display_name_field.text = character.display_name if character else ""
	color_button.color = character.color if character else Color.WHITE
	_portraits = character.portraits.duplicate(true) if character else {}
	_default = character.default_portrait if character else ""
	_selected = _default
	nicknames_field.text = "\n".join(character.nicknames) if character else ""
	description_field.text = character.description if character else ""
	custom_info_field.text = var_to_str(character.custom_info) if character else "{}"
	style_field.text = str(character.custom_info.get("style", "")) if character else ""
	text_prefix_field.text = str(character.custom_info.get("prefix", "")) if character else ""
	text_suffix_field.text = str(character.custom_info.get("suffix", "")) if character else ""
	character_scale.value = character.scale if character else 1.0
	character_x.value = character.offset.x if character else 0.0
	character_y.value = character.offset.y if character else 0.0
	character_mirror.button_pressed = character.mirror if character else false
	_refresh_portrait_list()
	_show_selected()
	set_portrait_preview(null, _character_portrait_path(character))
	_updating_fields = false
	set_document_state(title, read_only, message)


func get_fields() -> Dictionary:
	var custom: Variant = {}
	var custom_error := preload("res://application/character_document.gd")._check_data_tokens(custom_info_field.text)
	if custom_error.is_empty():
		custom = str_to_var(custom_info_field.text)
		if not custom is Dictionary or not preload("res://application/character_document.gd").inert_data(custom):
			custom_error = "Custom info must be an inert native dictionary."
	var aliases: Array = []
	for value: String in nicknames_field.text.split("\n"):
		if not value.strip_edges().is_empty(): aliases.append(value.strip_edges())
	return {"identifier": identifier_field.text, "display_name": display_name_field.text, "color": color_button.color,
		"portrait_path": _portrait_path, "nicknames": aliases, "description": description_field.text,
		"custom_info": custom if custom is Dictionary else {}, "form_error": custom_error,
		"scale": character_scale.value, "offset": Vector2(character_x.value, character_y.value), "mirror": character_mirror.button_pressed,
		"portraits": _portraits.duplicate(true), "default_portrait": _default}


func set_document_state(title: String, read_only: bool, message: String) -> void:
	# Updating the title/dirty marker must not reset text, selection or undo.
	title_label.text = title
	title_label.tooltip_text = title
	document_read_only = read_only
	diagnostics_label.text = message
	diagnostics_label.add_theme_color_override("font_color", Color(0.93, 0.72, 0.43) if read_only else Color(0.69, 0.72, 0.77))
	_refresh_state()


func set_identifier(identifier: String, editable: bool = false) -> void:
	identifier_field.text = identifier
	_identifier_editable = editable
	_refresh_state()


func set_portrait_preview(texture: Texture2D, path: String) -> void:
	_portrait_path = path
	if not _updating_fields and not path.is_empty():
		if _selected.is_empty():
			_selected = "default"
			_default = _selected
			_portraits[_selected] = _new_portrait()
			_refresh_portrait_list()
		if _portraits.has(_selected) and _portraits[_selected].get("scene", "") in ["", preload("res://application/character_document.gd").HIGHLIGHT]:
			_portraits[_selected]["export_overrides"] = {"image": var_to_str(path)}
	portrait_preview.texture = texture
	portrait_empty_label.visible = texture == null
	portrait_empty_label.text = "No portrait" if path.is_empty() else "Preview unavailable"
	portrait_path_label.text = "No portrait selected" if path.is_empty() else path
	portrait_path_label.tooltip_text = path
	_refresh_state()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_refresh_state()


func _refresh_state() -> void:
	var editable := _enabled and document_opened and not document_read_only
	new_button.disabled = not _enabled
	open_button.disabled = not _enabled
	save_button.disabled = not editable
	save_as_button.disabled = not editable
	identifier_field.editable = editable and _identifier_editable
	display_name_field.editable = editable
	color_button.disabled = not editable
	portrait_button.disabled = not editable
	clear_portrait_button.disabled = not editable or _selected.is_empty()
	for control: Control in _extra_controls:
		if control is TextEdit or control is LineEdit: control.editable = editable
		elif control is BaseButton: control.disabled = not editable
		elif control is SpinBox: control.editable = editable
	portrait_list.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE


func _request(request: Signal, requires_editable: bool = false) -> void:
	if not _enabled or (requires_editable and (not document_opened or document_read_only)):
		return
	request.emit()


func _on_text_changed(_text: String) -> void:
	_emit_fields_changed()


func _emit_fields_changed() -> void:
	if _updating_fields or not _enabled or not document_opened or document_read_only:
		return
	fields_changed.emit(get_fields())


func _clear_portrait() -> void:
	if not _enabled or not document_opened or document_read_only or _selected.is_empty(): return
	_portraits.erase(_selected)
	if _default == _selected: _default = str(_portraits.keys()[0]) if not _portraits.is_empty() else ""
	_selected = _default
	_refresh_portrait_list()
	_show_selected()
	_emit_fields_changed()


func _character_portrait_path(character: DialogicCharacter) -> String:
	if character == null:
		return ""
	var portrait: Variant = character.portraits.get(character.default_portrait, {})
	if not portrait is Dictionary:
		return ""
	var overrides: Variant = portrait.get("export_overrides", {})
	if not overrides is Dictionary:
		return ""
	var image_path: Variant = overrides.get("image", "")
	if not image_path is String:
		return ""
	# Alpha 20 stores export override strings in native variant syntax.
	if image_path.begins_with('"') and image_path.ends_with('"'):
		var decoded: Variant = str_to_var(image_path)
		return decoded if decoded is String else ""
	return image_path


func _build_extended_form(column: VBoxContainer) -> void:
	column.add_child(HSeparator.new())
	nicknames_field = _text_field(column, "Nicknames · one per line", "Nicknames", 62)
	description_field = _text_field(column, "Description", "Description", 76)
	column.add_child(_label("Character style and text prefix / suffix"))
	var presentation_row := HBoxContainer.new()
	column.add_child(presentation_row)
	style_field = _field("CharacterStyle", "Style name · blank uses base style")
	presentation_row.add_child(style_field)
	style_picker = MenuButton.new(); style_picker.text = "Choose style"; presentation_row.add_child(style_picker)
	style_picker.get_popup().id_pressed.connect(func(id: int):
		style_field.text = str(style_picker.get_popup().get_item_metadata(id))
		_on_presentation_changed(""))
	text_prefix_field = _field("TextPrefix", "Text prefix")
	text_suffix_field = _field("TextSuffix", "Text suffix")
	column.add_child(text_prefix_field); column.add_child(text_suffix_field)
	for field: LineEdit in [style_field, text_prefix_field, text_suffix_field]:
		field.text_changed.connect(_on_presentation_changed)
		_extra_controls.append(field)
	_extra_controls.append(style_picker)
	column.add_child(_label("Custom info · native dictionary"))
	custom_info_field = CodeEdit.new()
	custom_info_field.name = "CustomInfo"
	custom_info_field.custom_minimum_size.y = 90
	custom_info_field.text = "{}"
	custom_info_field.text_changed.connect(_on_custom_info_changed)
	column.add_child(custom_info_field)
	_extra_controls.append(custom_info_field)
	column.add_child(_label("Character transform · scale / offset X / offset Y / mirror"))
	var global_row := HBoxContainer.new()
	column.add_child(global_row)
	character_scale = _number(global_row, "CharacterScale", 1, 0.001, 10000)
	character_x = _number(global_row, "CharacterOffsetX", 0)
	character_y = _number(global_row, "CharacterOffsetY", 0)
	character_mirror = _check(global_row, "Mirror", "CharacterMirror")
	column.add_child(HSeparator.new())
	column.add_child(_label("Portraits · select a portrait to edit; renaming does not rewrite timelines"))
	portrait_list = ItemList.new()
	portrait_list.name = "PortraitList"
	portrait_list.custom_minimum_size.y = 110
	portrait_list.item_selected.connect(func(index: int): _selected = portrait_list.get_item_text(index); _show_selected())
	column.add_child(portrait_list)
	var row := HBoxContainer.new()
	column.add_child(row)
	portrait_name_field = _field("PortraitName", "Portrait name")
	row.add_child(portrait_name_field)
	_extra_controls.append(portrait_name_field)
	for action: String in ["Add", "Rename", "Duplicate", "Delete"]:
		_extra_controls.append(_button(row, action, action + " selected portrait", _portrait_action.bind(action)))
	column.add_child(_label("Default portrait"))
	default_selector = OptionButton.new()
	default_selector.name = "DefaultPortrait"
	default_selector.item_selected.connect(func(index: int): _default = default_selector.get_item_text(index); _emit_fields_changed())
	column.add_child(default_selector)
	_extra_controls.append(default_selector)
	column.add_child(_label("Portrait preset"))
	preset_selector = OptionButton.new()
	preset_selector.name = "PortraitPreset"
	for preset: String in ["Static image", "HighlightPortrait", "LayeredPortrait scene"]: preset_selector.add_item(preset)
	preset_selector.item_selected.connect(_preset_changed)
	column.add_child(preset_selector)
	_extra_controls.append(preset_selector)
	var scene_row := HBoxContainer.new()
	column.add_child(scene_row)
	scene_path_field = _field("LayeredScenePath", "res://portraits/layered.tscn")
	scene_path_field.text_changed.connect(func(value: String):
		if not _updating_fields and _portraits.has(_selected) and preset_selector.selected == 2:
			_portraits[_selected]["scene"] = value
			_emit_fields_changed())
	scene_row.add_child(scene_path_field)
	_extra_controls.append(scene_path_field)
	_extra_controls.append(_button(scene_row, "Layer editor", "Create or edit a native layered scene", func(): layered_requested.emit(scene_path_field.text)))
	column.add_child(_label("Portrait transform · scale / offset X / offset Y / mirror"))
	var transform := HBoxContainer.new()
	column.add_child(transform)
	portrait_scale = _number(transform, "PortraitScale", 1, 0.001, 10000)
	portrait_x = _number(transform, "PortraitOffsetX", 0)
	portrait_y = _number(transform, "PortraitOffsetY", 0)
	portrait_mirror = _check(transform, "Mirror", "PortraitMirror")
	ignore_scale = _check(transform, "Ignore character scale", "IgnoreCharacterScale")
	for control: SpinBox in [portrait_scale, portrait_x, portrait_y]:
		control.value_changed.connect(func(_value: float): _store_transform())
	portrait_mirror.toggled.connect(func(_value: bool): _store_transform())
	ignore_scale.toggled.connect(func(_value: bool): _store_transform())

func _text_field(parent: Control, caption: String, node_name: String, height: int) -> TextEdit:
	parent.add_child(_label(caption))
	var field := TextEdit.new()
	field.name = node_name
	field.custom_minimum_size.y = height
	field.text_changed.connect(_emit_fields_changed)
	parent.add_child(field)
	_extra_controls.append(field)
	return field

func _number(parent: Control, node_name: String, initial: float, minimum: float = -1000000, maximum: float = 1000000) -> SpinBox:
	var field := SpinBox.new()
	field.name = node_name
	field.min_value = minimum
	field.max_value = maximum
	field.step = 0.01
	field.value = initial
	field.custom_minimum_size.x = 100
	field.value_changed.connect(func(_value: float): _emit_fields_changed())
	parent.add_child(field)
	_extra_controls.append(field)
	return field

func _check(parent: Control, caption: String, node_name: String) -> CheckBox:
	var field := CheckBox.new()
	field.name = node_name
	field.text = caption
	field.toggled.connect(func(_value: bool): _emit_fields_changed())
	parent.add_child(field)
	_extra_controls.append(field)
	return field

func _new_portrait() -> Dictionary:
	return {"scene": "", "export_overrides": {"image": ""}, "scale": 1.0, "offset": Vector2(), "mirror": false}

func _portrait_action(action: String) -> void:
	if not _enabled or document_read_only or not document_opened: return
	if action == "Delete": _clear_portrait(); return
	var next := portrait_name_field.text.strip_edges()
	if next.is_empty() or _portraits.has(next) or not preload("res://application/character_document.gd").plain_name(next) or next.contains("(") or next.contains(")"):
		diagnostics_label.text = "Choose a unique portrait name without Dialogic syntax punctuation."
		return
	if action != "Add" and not _portraits.has(_selected): return
	_portraits[next] = _new_portrait() if action == "Add" else _portraits[_selected].duplicate(true)
	if action == "Rename":
		_portraits.erase(_selected)
		if _default == _selected: _default = next
	if _default.is_empty(): _default = next
	_selected = next
	_refresh_portrait_list()
	_show_selected()
	_emit_fields_changed()

func _refresh_portrait_list() -> void:
	portrait_list.clear()
	default_selector.clear()
	for key: String in _portraits:
		portrait_list.add_item(key)
		default_selector.add_item(key)
		if key == _selected: portrait_list.select(portrait_list.item_count - 1)
		if key == _default: default_selector.select(default_selector.item_count - 1)

func _show_selected() -> void:
	var was_updating := _updating_fields
	_updating_fields = true
	var value: Dictionary = _portraits.get(_selected, _new_portrait())
	portrait_name_field.text = _selected
	var scene: String = value.get("scene", "")
	preset_selector.select(0 if scene.is_empty() or scene.ends_with("/default_portrait.tscn") else (1 if scene == preload("res://application/character_document.gd").HIGHLIGHT else 2))
	scene_path_field.text = scene if preset_selector.selected == 2 else ""
	scene_path_field.editable = preset_selector.selected == 2
	portrait_scale.value = value.get("scale", 1.0)
	portrait_x.value = value.get("offset", Vector2()).x
	portrait_y.value = value.get("offset", Vector2()).y
	portrait_mirror.button_pressed = value.get("mirror", false)
	ignore_scale.button_pressed = value.get("ignore_char_scale", false)
	var path := preload("res://application/character_document.gd").decoded_image_path(value.get("export_overrides", {}).get("image", ""))
	set_portrait_preview(null, path)
	_updating_fields = was_updating
	if not was_updating: portrait_selected.emit(path)

func _preset_changed(index: int) -> void:
	if _updating_fields or not _portraits.has(_selected): return
	var value: Dictionary = _portraits[_selected]
	value["scene"] = ["", preload("res://application/character_document.gd").HIGHLIGHT, scene_path_field.text][index]
	value["export_overrides"] = {} if index == 2 else {"image": var_to_str(_portrait_path)}
	scene_path_field.editable = index == 2
	_emit_fields_changed()

func _store_transform() -> void:
	if _updating_fields or not _portraits.has(_selected): return
	_portraits[_selected].merge({"scale": portrait_scale.value, "offset": Vector2(portrait_x.value, portrait_y.value), "mirror": portrait_mirror.button_pressed}, true)
	if ignore_scale.button_pressed or _portraits[_selected].has("ignore_char_scale"):
		_portraits[_selected]["ignore_char_scale"] = ignore_scale.button_pressed
	_emit_fields_changed()

func use_layered_scene(logical: String) -> void:
	if _selected.is_empty():
		_selected = "layered"
		_portraits[_selected] = _new_portrait()
		if _default.is_empty(): _default = _selected
	_portraits[_selected]["scene"] = logical
	_portraits[_selected]["export_overrides"] = {}
	_refresh_portrait_list()
	_show_selected()
	_emit_fields_changed()


func set_styles(names: Array[String]) -> void:
	style_picker.get_popup().clear()
	style_picker.get_popup().add_item("Use base style")
	style_picker.get_popup().set_item_metadata(0, "")
	for value: String in names:
		style_picker.get_popup().add_item(value)
		style_picker.get_popup().set_item_metadata(style_picker.get_popup().item_count - 1, value)

func _on_presentation_changed(_value: String) -> void:
	if _updating_fields: return
	var checked := preload("res://application/character_document.gd")._check_data_tokens(custom_info_field.text)
	if not checked.is_empty(): return
	var value: Variant = str_to_var(custom_info_field.text)
	if not value is Dictionary: return
	for key: String in {"style":style_field, "prefix":text_prefix_field, "suffix":text_suffix_field}:
		var text: String = {"style":style_field, "prefix":text_prefix_field, "suffix":text_suffix_field}[key].text
		if text.is_empty(): value.erase(key)
		else: value[key] = text
	_updating_fields = true
	custom_info_field.text = var_to_str(value)
	_updating_fields = false
	_emit_fields_changed()

func _on_custom_info_changed() -> void:
	if _updating_fields: return
	if preload("res://application/character_document.gd")._check_data_tokens(custom_info_field.text).is_empty():
		var value: Variant = str_to_var(custom_info_field.text)
		if value is Dictionary:
			_updating_fields = true
			style_field.text = str(value.get("style", ""))
			text_prefix_field.text = str(value.get("prefix", ""))
			text_suffix_field.text = str(value.get("suffix", ""))
			_updating_fields = false
	_emit_fields_changed()
