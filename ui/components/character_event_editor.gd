extends ConfirmationDialog

const Source = preload("res://application/character_event_source.gd")
var kind: OptionButton
var identifier: LineEdit
var portrait: LineEdit
var transform: LineEdit
var parameter_fields: Dictionary = {}
var message: Label
var source_editor: CodeEdit
var workspace: RefCounted
var original_source := ""
var source_line := 0
var editing := false
var prefix := ""

func _ready() -> void:
	title = "Character event properties"
	size = Vector2i(650, 620)
	min_size = Vector2i(500, 390)
	dialog_hide_on_ok = false
	get_ok_button().text = "Apply"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 8)
	scroll.add_child(fields)
	kind = OptionButton.new()
	kind.name = "CharacterAction"
	for action: String in ["join", "leave", "update"]: kind.add_item(action)
	fields.add_child(kind)
	identifier = field(fields, "Character identifier · --All-- for Leave All", "CharacterIdentifier")
	portrait = field(fields, "Portrait · blank keeps native default/current behavior", "EventPortrait")
	transform = field(fields, "Position · leftmost / left / center / right / rightmost, or pos/size/rot", "EventTransform")
	for key: String in Source.PARAMS:
		var caption: String = {"animation": "Animation · native name, e.g. Fade In / Shake X", "length": "Animation length · seconds", "wait": "Wait · true / false", "repeat": "Repeat count · Update", "repeat_forever": "Repeat forever · true / false", "z_index": "Z index · explicit 0 resets Update", "mirrored": "Mirror · explicit false resets Update", "fade": "Portrait crossfade · native name", "fade_length": "Fade length · seconds", "move_time": "Movement time · seconds", "move_ease": "Ease · in / out / in_out / out_in", "move_trans": "Transition · linear / sine / cubic / …", "extra_data": "Layer commands · show path, hide path, set path"}[key]
		parameter_fields[key] = field(fields, caption + " · blank omits", key)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(message)
	confirmed.connect(_apply)

func field(parent: Control, caption: String, node_name: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.name = node_name
	parent.add_child(edit)
	return edit

func open_for_editor(editor: CodeEdit, content_workspace: RefCounted = null, requested: String = "join") -> void:
	if not editor.editable: return
	source_editor = editor
	workspace = content_workspace
	original_source = editor.text
	source_line = editor.get_caret_line()
	var line := editor.get_line(source_line)
	var raw := line.strip_edges(true, false)
	prefix = line.left(line.length() - raw.length())
	editing = raw.begins_with("join") or raw.begins_with("update") or raw.begins_with("leave")
	get_ok_button().disabled = false
	kind.select(["join", "leave", "update"].find(requested))
	identifier.text = ""
	portrait.text = ""
	transform.text = ""
	for field_value: LineEdit in parameter_fields.values(): field_value.text = ""
	message.text = "Insert a Character event at line %d. Values are stored in native .dtl syntax." % (source_line + 1)
	if editing:
		var model := Source.inspect(raw, workspace, false)
		if model.has("error"):
			get_ok_button().disabled = true
			message.text = model.error
		else:
			kind.select(model.action)
			identifier.text = model.identifier
			portrait.text = model.portrait
			transform.text = model.position if model.properties.set_transform else ""
			for key: String in model.parameters: parameter_fields[key].text = model.parameters[key]
			message.text = "Edit line %d; Apply is one undo operation." % (source_line + 1)
	popup_centered(size)
	identifier.grab_focus()

func _apply() -> void:
	if get_ok_button().disabled: return
	if not is_instance_valid(source_editor) or not source_editor.editable or source_editor.text != original_source:
		message.text = "The document changed or became read-only. Reopen this form."
		return
	var id := identifier.text.strip_edges()
	if id.is_empty() or id.contains('"') or id.contains("\n"):
		message.text = "Enter a valid character identifier."
		return
	var raw := kind.get_item_text(kind.selected) + ' "' + id + '"'
	if not portrait.text.strip_edges().is_empty(): raw += " (" + portrait.text.strip_edges() + ")"
	if not transform.text.strip_edges().is_empty(): raw += " " + transform.text.strip_edges()
	var params: Array[String] = []
	for key: String in parameter_fields:
		var value: String = parameter_fields[key].text.strip_edges()
		if key in ["move_ease", "move_trans"]: value = value.to_lower()
		if not value.is_empty(): params.append(key + '="' + value + '"')
	if not params.is_empty(): raw += " [" + " ".join(params) + "]"
	var check := Source.inspect(raw, workspace)
	if check.has("error"):
		message.text = check.error
		return
	if editing and prefix + raw == source_editor.get_line(source_line): hide(); return
	source_editor.remove_secondary_carets()
	source_editor.begin_complex_operation()
	source_editor.deselect()
	source_editor.set_caret_line(source_line)
	source_editor.set_caret_column(0)
	if editing: source_editor.select(source_line, 0, source_line, source_editor.get_line(source_line).length())
	else: raw += "\n"
	source_editor.insert_text_at_caret(prefix + raw)
	source_editor.end_complex_operation()
	hide()
	source_editor.grab_focus()
