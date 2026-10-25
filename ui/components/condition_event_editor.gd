extends ConfirmationDialog

const Condition = preload("res://application/condition_source.gd")
var kind: OptionButton
var expression: TextEdit
var expression_label: Label
var message: Label
var source_editor: CodeEdit
var original_source := ""
var source_line := 0
var editing := false
var prefix := ""


func _ready() -> void:
	title = "Condition · nested branch"
	size = Vector2i(520, 430)
	min_size = size
	dialog_hide_on_ok = false
	get_ok_button().text = "Apply"
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 10)
	add_child(fields)
	kind = OptionButton.new()
	kind.name = "ConditionType"
	for caption: String in ["if", "elif", "else"]:
		kind.add_item(caption)
	fields.add_child(kind)
	expression_label = Label.new()
	expression_label.text = "Condition expression · variables use {name}"
	fields.add_child(expression_label)
	expression = TextEdit.new()
	expression.name = "ConditionExpression"
	expression.custom_minimum_size = Vector2(460, 200)
	expression.size_flags_vertical = Control.SIZE_EXPAND_FILL
	expression.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	fields.add_child(expression)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 64)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fields.add_child(scroll)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 42
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(message)
	kind.item_selected.connect(func(_index: int): _show_expression())
	confirmed.connect(_apply)


func _show_expression() -> void:
	expression.visible = kind.selected != 2
	expression_label.visible = expression.visible


func open_for_editor(editor: CodeEdit) -> void:
	if not editor.editable:
		return
	source_editor = editor
	original_source = editor.text
	source_line = editor.get_caret_line()
	var line := editor.get_line(source_line)
	var stripped := line.strip_edges(true, false)
	prefix = line.left(line.length() - stripped.length())
	editing = DialogicConditionEvent.new().is_valid_event(stripped)
	kind.select(0)
	expression.text = "true"
	get_ok_button().disabled = false
	message.text = "Insert a condition and a body before this line. elif/else must follow an if branch."
	if editing:
		var model := Condition.inspect_event(stripped)
		if model.has("error"):
			get_ok_button().disabled = true
			expression.text = line
			message.text = model.error + " Correct this line in the text editor first."
		else:
			kind.select(model.condition_type)
			expression.text = model.expression
			message.text = "Edit the header on line %d; its branch content is preserved." % (source_line + 1)
	_show_expression()
	popup_centered(Vector2i(520, 430))
	if expression.visible:
		expression.grab_focus()
	else:
		kind.grab_focus()


func _apply() -> void:
	if get_ok_button().disabled:
		return
	if not is_instance_valid(source_editor) or not source_editor.editable or source_editor.text != original_source:
		message.text = "The document changed or became read-only. Close and reopen the Condition form."
		return
	var header := "else:" if kind.selected == 2 else kind.get_item_text(kind.selected) + " " + expression.text.strip_edges() + ":"
	var checked := Condition.inspect_event(header)
	if checked.has("error"):
		message.text = checked.error
		return
	var lines := original_source.split("\n", true)
	header = prefix + header
	var insertion := header
	if editing:
		lines[source_line] = header
	else:
		var structure := Condition.scan(original_source, DialogicResourceUtil.get_event_cache())
		var indent: String = structure.indent if not structure.indent.is_empty() else "\t"
		insertion += "\n" + prefix + indent + "New narration.\n"
		lines[source_line] = insertion + lines[source_line]
	var structure := Condition.scan("\n".join(lines), DialogicResourceUtil.get_event_cache())
	if not structure.issues.is_empty():
		var issue: Dictionary = structure.issues[0]
		message.text = "Line %d: %s" % [issue.line, issue.message]
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
