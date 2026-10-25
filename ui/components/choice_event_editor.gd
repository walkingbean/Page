extends ConfirmationDialog

const Flow = preload("res://application/flow_source.gd")
const Structure = preload("res://application/condition_source.gd")
var text_field: TextEdit
var condition: LineEdit
var else_action: OptionButton
var disabled_text: TextEdit
var extra_data: TextEdit
var message: Label
var source_editor: CodeEdit
var original_source := ""
var source_line := 0
var editing := false
var prefix := ""


func _ready() -> void:
	title = "Choice properties"
	size = Vector2i(600, 490)
	min_size = Vector2i(480, 400)
	dialog_hide_on_ok = false
	get_ok_button().text = "Apply"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 330)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 8)
	scroll.add_child(fields)
	text_field = _text_field(fields, "Choice text · native escapes, variables and conditional text", "ChoiceText", 60)
	_caption(fields, "Optional condition expression")
	condition = LineEdit.new()
	condition.name = "ChoiceCondition"
	fields.add_child(condition)
	_caption(fields, "When the condition is false")
	else_action = OptionButton.new()
	else_action.name = "ChoiceElse"
	for label: String in ["Hide", "Disable", "Default (content project setting)"]:
		else_action.add_item(label)
	fields.add_child(else_action)
	disabled_text = _text_field(fields, "Disabled text · empty uses the normal text", "ChoiceDisabledText", 55)
	extra_data = _text_field(fields, "Extra data · JSON object of native parameter strings", "ChoiceExtraData", 70)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 65
	fields.add_child(message)
	confirmed.connect(_apply)


func _caption(parent: Control, caption: String) -> void:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)


func _text_field(parent: Control, caption: String, node_name: String, height: int) -> TextEdit:
	_caption(parent, caption)
	var edit := TextEdit.new()
	edit.name = node_name
	edit.custom_minimum_size.y = height
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(edit)
	return edit


func open_for_editor(editor: CodeEdit) -> void:
	if not editor.editable:
		return
	source_editor = editor
	original_source = editor.text
	source_line = editor.get_caret_line()
	var line := editor.get_line(source_line)
	var raw := line.strip_edges(true, false)
	prefix = line.left(line.length() - raw.length())
	editing = raw.begins_with("-")
	text_field.text = "New choice"
	condition.text = ""
	else_action.select(2)
	disabled_text.text = ""
	extra_data.text = "{}"
	get_ok_button().disabled = false
	message.text = "Insert a choice with a branch. Use \\| for a literal pipe. Existing neighboring branches are preserved."
	if editing:
		var native := DialogicChoiceEvent.new()
		var found := native.regex.search(raw)
		if found == null or found.get_end() != raw.length():
			get_ok_button().disabled = true
			message.text = "Correct this malformed Choice in the text editor first."
		else:
			native.from_text(raw)
			text_field.text = native.text
			condition.text = native.condition
			else_action.select(native.else_action)
			disabled_text.text = native.disabled_text
			extra_data.text = JSON.stringify(native.extra_data, "  ")
			message.text = "Edit line %d. Branch content is preserved; Apply is one undo operation." % (source_line + 1)
	popup_centered(size)
	text_field.grab_focus()


func _apply() -> void:
	if get_ok_button().disabled:
		return
	if not is_instance_valid(source_editor) or not source_editor.editable or source_editor.text != original_source:
		message.text = "The document changed or became read-only. Reopen this form."
		return
	var data: Variant = JSON.parse_string(extra_data.text)
	if not data is Dictionary:
		message.text = "Extra data must be a JSON object with string keys and native parameter string values."
		return
	for key: Variant in data:
		if not key is String or not data[key] is String or key in ["else", "alt_text"] or RegEx.create_from_string(r'\A[^\s=\[\]"]+\z').search(key) == null:
			message.text = "Extra-data keys must be distinct parameter names; values must be strings. else/alt_text have dedicated fields."
			return
	var native := DialogicChoiceEvent.new()
	native.text = text_field.text.strip_edges()
	native.condition = condition.text.strip_edges()
	native._has_condition = not native.condition.is_empty()
	native.else_action = else_action.selected
	native.disabled_text = disabled_text.text
	native.extra_data = data
	var raw := native.to_text()
	if raw.contains("\n") or raw.contains("\r"):
		message.text = "Choice properties must serialize to a single native line."
		return
	# Syntax-only form validation cannot assume a workspace variable value.
	var parsed := DialogicChoiceEvent.new()
	var found := parsed.regex.search(raw)
	if found == null or found.get_end() != raw.length():
		message.text = "These delimiters cannot be preserved by Alpha 20's native Choice parser. Use native escaping or edit the source."
		return
	parsed.from_text(raw)
	if parsed.text != native.text or parsed.condition != native.condition or parsed.else_action != native.else_action or parsed.disabled_text != native.disabled_text or parsed.extra_data != native.extra_data:
		message.text = "The native parser would change a property. Correct its quoting or escaping before applying."
		return
	var insertion := prefix + raw
	if not editing:
		var structure := Structure.scan(original_source, DialogicResourceUtil.get_event_cache())
		var indent: String = structure.indent if not structure.indent.is_empty() else "\t"
		insertion += "\n" + prefix + indent + "New narration.\n"
	var lines := original_source.split("\n", true)
	lines[source_line] = insertion if editing else insertion + lines[source_line]
	var structure := Structure.scan("\n".join(lines), DialogicResourceUtil.get_event_cache())
	if not structure.issues.is_empty():
		message.text = structure.issues[0].message
		return
	source_editor.remove_secondary_carets()
	source_editor.begin_complex_operation()
	source_editor.deselect()
	source_editor.set_caret_line(source_line)
	source_editor.set_caret_column(0)
	if editing:
		source_editor.select(source_line, 0, source_line, source_editor.get_line(source_line).length())
	source_editor.insert_text_at_caret(insertion)
	source_editor.end_complex_operation()
	hide()
	source_editor.grab_focus()
