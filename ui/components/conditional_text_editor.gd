extends ConfirmationDialog

const Inline = preload("res://application/conditional_text.gd")
var expression: LineEdit
var true_text: TextEdit
var false_text: TextEdit
var message: Label
var source_editor: CodeEdit
var original_source := ""
var source_line := 0
var start := 0
var end := 0


func _ready() -> void:
	title = "Conditional Text"
	size = Vector2i(540, 440)
	min_size = size
	dialog_hide_on_ok = false
	get_ok_button().text = "Apply"
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 8)
	add_child(fields)
	var label := Label.new()
	label.text = "Expression · true, false, {name}, or {{name} > 1}"
	fields.add_child(label)
	expression = LineEdit.new()
	expression.name = "InlineExpression"
	fields.add_child(expression)
	for caption: String in ["When true · native text; escape / as \\/ and ] as \\]", "When false · optional; escape ] as \\]"]:
		label = Label.new()
		label.text = caption
		fields.add_child(label)
		var edit := TextEdit.new()
		edit.custom_minimum_size = Vector2(480, 100)
		edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		fields.add_child(edit)
		if true_text == null:
			true_text = edit
			edit.name = "TrueText"
		else:
			false_text = edit
			edit.name = "FalseText"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 50
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fields.add_child(scroll)
	message = Label.new()
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(message)
	confirmed.connect(_apply)


func open_for_editor(editor: CodeEdit) -> void:
	if not editor.editable:
		return
	source_editor = editor
	original_source = editor.text
	source_line = editor.get_caret_line()
	start = editor.get_caret_column()
	end = start
	expression.text = "true"
	true_text.text = "Text when true."
	false_text.text = "Text when false."
	message.text = "Insert at the caret, or edit the conditional text containing the caret."
	for found: RegExMatch in RegEx.create_from_string(Inline.PATTERN).search_all(editor.get_line(source_line)):
		if start >= found.get_start() and start < found.get_end():
			start = found.get_start()
			end = found.get_end()
			expression.text = found.get_string("condition")
			true_text.text = found.get_string("truetext").strip_edges()
			false_text.text = found.get_string("falsetext").strip_edges()
			message.text = "Edit this marker; surrounding source is preserved."
			break
	popup_centered(Vector2i(540, 440))
	expression.grab_focus()


func _apply() -> void:
	if not is_instance_valid(source_editor) or not source_editor.editable or source_editor.text != original_source:
		message.text = "The document changed or became read-only. Close and reopen the form."
		return
	var condition := expression.text.strip_edges()
	var yes := true_text.text.strip_edges()
	var no := false_text.text.strip_edges()
	var token := "[if " + condition + " " + yes + ("/" + no if not no.is_empty() else "") + "]"
	var found := RegEx.create_from_string(Inline.PATTERN).search(token)
	if token.contains("\n") or token.contains("\r") or found == null or found.get_string() != token or found.get_string("condition") != condition or found.get_string("truetext").strip_edges() != yes or found.get_string("falsetext").strip_edges() != no:
		message.text = "Use a single-line native condition; escape / in true text and ] in either text."
		return
	var checked := Inline.expression_model(condition)
	if checked.has("error"):
		message.text = checked.error
		return
	if yes.contains("[if") or no.contains("[if"):
		message.text = "Use timeline conditions for nesting; nested inline modifiers are unsupported."
		return
	source_editor.remove_secondary_carets()
	source_editor.begin_complex_operation()
	source_editor.deselect()
	source_editor.set_caret_line(source_line)
	source_editor.set_caret_column(start)
	if end > start:
		source_editor.select(source_line, start, source_line, end)
	source_editor.insert_text_at_caret(token)
	source_editor.end_complex_operation()
	hide()
	source_editor.grab_focus()
