extends VBoxContainer

signal new_requested
signal open_requested
signal save_requested
signal save_as_requested
signal portrait_requested
signal fields_changed(fields: Dictionary)

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
	portrait_column.add_child(_label("Default portrait · PNG"))
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
	portrait_button = _button(portrait_actions, "Choose PNG", "Choose one static PNG portrait", func() -> void: _request(portrait_requested, true))
	clear_portrait_button = _button(portrait_actions, "Clear", "Remove the portrait reference", _clear_portrait)
	portrait_path_label = _label("No portrait selected", 11)
	portrait_path_label.name = "PortraitPath"
	portrait_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	portrait_path_label.add_theme_color_override("font_color", Color(0.58, 0.61, 0.66))
	column.add_child(portrait_path_label)
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
	set_portrait_preview(null, _character_portrait_path(character))
	_updating_fields = false
	set_document_state(title, read_only, message)


func get_fields() -> Dictionary:
	# Read controls directly: a save click can precede a deferred text_changed.
	return {
		"identifier": identifier_field.text,
		"display_name": display_name_field.text,
		"color": color_button.color,
		"portrait_path": _portrait_path,
	}


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
	clear_portrait_button.disabled = not editable or _portrait_path.is_empty()


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
	if not _enabled or not document_opened or document_read_only or _portrait_path.is_empty():
		return
	set_portrait_preview(null, "")
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
