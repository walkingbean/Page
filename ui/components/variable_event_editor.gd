extends ConfirmationDialog

const Literal = preload("res://application/variable_literal.gd")
const Assignment = preload("res://application/variable_assignment.gd")
const EXPRESSION_MODE := 1000
var target: LineEdit
var kind: OptionButton
var value: TextEdit
var message: Label
var source_editor: CodeEdit
var original_source := ""
var source_line := 0
var editing := false
var indentation := ""


func _ready() -> void:
	title = "Variable · assignment"
	size = Vector2i(520, 430)
	min_size = size
	get_ok_button().text = "Apply"
	dialog_hide_on_ok = false
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 10)
	add_child(fields)
	var label := Label.new()
	label.text = "Target variable (saved in the content folder)"
	fields.add_child(label)
	target = LineEdit.new()
	target.name = "AssignmentTarget"
	fields.add_child(target)
	kind = OptionButton.new()
	kind.name = "AssignmentType"
	for type: int in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
		kind.add_item(type_string(type), type)
	kind.add_item("Expression", EXPRESSION_MODE)
	fields.add_child(kind)
	value = TextEdit.new()
	value.name = "AssignmentValue"
	value.custom_minimum_size = Vector2(460, 200)
	value.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	value.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fields.add_child(value)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Bound diagnostics independently of their text length. Long messages remain
	# scrollable and cannot move Apply/Cancel outside the minimum-size window.
	var diagnostics := ScrollContainer.new()
	diagnostics.custom_minimum_size = Vector2(460, 64)
	diagnostics.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fields.add_child(diagnostics)
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.custom_minimum_size.y = 42
	message.size.x = 460
	diagnostics.add_child(message)
	confirmed.connect(_apply)


func open_for_editor(editor: CodeEdit) -> void:
	if not editor.editable:
		return
	source_editor = editor
	original_source = editor.text
	source_line = editor.get_caret_line()
	var line := editor.get_line(source_line)
	indentation = line.left(line.length() - line.strip_edges(true, false).length())
	line = line.strip_edges(true, false)
	editing = line.begins_with("set")
	var model: Dictionary = Assignment.inspect_event(line) if editing else {}
	if model.has("error"):
		message.text = model.error + " Correct this line in the text editor first."
		get_ok_button().disabled = true
		target.text = ""
		value.text = line
	else:
		get_ok_button().disabled = false
		target.text = model.get("name", "")
		var initial: Variant = model.get("value", "")
		if model.has("expression"):
			kind.select(kind.get_item_index(EXPRESSION_MODE))
			value.text = model.expression
		else:
			kind.select(kind.get_item_index(typeof(initial)))
			value.text = initial if initial is String else var_to_str(initial)
		message.text = "Edit assignment on line %d." % (source_line + 1) if editing else "Insert before the current line. Expression example: {score} + 1. Bool accepts true or false."
	popup_centered(Vector2i(520, 430))
	target.grab_focus()


func _apply() -> void:
	if not is_instance_valid(source_editor) or not source_editor.editable or source_editor.text != original_source:
		message.text = "The document changed or became read-only. Close and reopen the Variable form."
		return
	var expression: String = value.text
	if kind.get_selected_id() != EXPRESSION_MODE:
		var parsed: Dictionary = Literal.parse_field(value.text, kind.get_selected_id())
		if parsed.has("error"):
			message.text = parsed.error
			return
		expression = Literal.encode(parsed.value)
	var line: String = "set {%s} = %s" % [target.text, expression]
	var check: Dictionary = Assignment.inspect_event(line)
	if check.has("error"):
		message.text = check.error
		return
	line = indentation + line
	# This form edits one explicit event; secondary carets must not duplicate it.
	source_editor.remove_secondary_carets()
	source_editor.begin_complex_operation()
	source_editor.deselect()
	source_editor.set_caret_line(source_line)
	source_editor.set_caret_column(0)
	if editing:
		source_editor.select(source_line, 0, source_line, source_editor.get_line(source_line).length())
		source_editor.insert_text_at_caret(line)
	elif source_editor.get_line(source_line).is_empty():
		source_editor.insert_text_at_caret(line + "\n")
	else:
		source_editor.insert_text_at_caret(line + "\n")
	source_editor.end_complex_operation()
	hide()
	source_editor.grab_focus()
