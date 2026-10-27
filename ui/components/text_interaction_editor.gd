extends ConfirmationDialog

const Source = preload("res://application/interaction_source.gd")
const Field = preload("res://ui/components/native_value_field.gd")
const Scan = preload("res://application/condition_source.gd")
var source_editor: CodeEdit
var workspace: RefCounted
var original_source := ""
var first_line := 0
var last_line := 0
var prefix := ""
var editing := false
var current_kind := "Text"
var translation_id := ""
var column: VBoxContainer
var fields: Dictionary = {}
var text_body: TextEdit
var speaker: LineEdit
var portrait: LineEdit
var message: Label
var setting_mode: OptionButton
var value_type: OptionButton

func _ready() -> void:
	title = "Event properties"; size = Vector2i(730, 650); min_size = Vector2i(530, 400); dialog_hide_on_ok = false
	get_ok_button().text = "Apply"
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(480, 330); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	column = VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation", 10); scroll.add_child(column)
	confirmed.connect(_apply)

func open_for_editor(editor: CodeEdit, content_workspace: RefCounted = null, requested := "Text") -> void:
	if not editor.editable: return
	source_editor = editor; workspace = content_workspace; original_source = editor.text
	first_line = editor.get_caret_line(); last_line = first_line
	var source_line := editor.get_line(first_line)
	prefix = source_line.left(source_line.length() - source_line.strip_edges(true, false).length())
	current_kind = requested; editing = false
	var selected: DialogicEvent
	var selected_raw := ""
	for record: Dictionary in Scan.scan(original_source, DialogicResourceUtil.get_event_cache()).records:
		if first_line + 1 in record.source_lines:
			if (requested == "Text" and record.event is DialogicTextEvent) or Source.kind_of(record.event) == requested:
				selected = record.event; selected_raw = record.raw; first_line = record.source_lines[0] - 1; last_line = record.source_lines[-1] - 1; editing = true
			break
	for child: Node in column.get_children(): column.remove_child(child); child.queue_free()
	fields.clear(); text_body = null; speaker = null; portrait = null; setting_mode = null; value_type = null
	get_ok_button().disabled = false
	var problem := ""
	translation_id = ""
	if selected != null and selected.can_be_translated() and "#id:" in selected_raw:
		translation_id = selected_raw.get_slice("#id:", 1).strip_edges()
		selected_raw = selected_raw.get_slice("#id:", 0)
	if requested == "Text":
		speaker = line("Character · blank for narration", "TextCharacter")
		portrait = line("Portrait · blank uses current/default", "TextPortrait")
		text_body = CodeEdit.new(); text_body.name = "TextBody"; text_body.custom_minimum_size.y = 220; text_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; text_body.text = "Narration text."; column.add_child(text_body)
		_build_insert_tools(text_body)
		if selected != null:
			var parsed: RegExMatch = selected.regex.search(selected_raw.trim_prefix("\\"))
			if parsed != null:
				speaker.text = parsed.get_string("name"); portrait.text = parsed.get_string("portrait").trim_prefix("(").trim_suffix(")")
				text_body.text = preload("res://application/timeline_codec.gd")._native_text_body(parsed.get_string("text"))
	else:
		var event := Source.create(requested)
		if selected != null:
			var values: Dictionary = workspace.variable_document.runtime_values() if workspace != null and workspace.variable_document != null else {}
			var checked := Source.inspect(selected_raw, selected, workspace, values, false)
			if checked.has("error"): problem = checked.error
			else: event = checked.event
		if requested == "Setting":
			setting_mode = OptionButton.new(); setting_mode.name = "SettingMode"
			for caption: String in ["Set", "Reset", "Reset all"]: setting_mode.add_item(caption)
			setting_mode.select(event.mode); column.add_child(setting_mode)
			_add_field("name", "Setting name", event.name)
			value_type = OptionButton.new(); value_type.name = "SettingValueType"
			for caption: String in ["String", "Number", "Variable", "Expression"]: value_type.add_item(caption)
			value_type.select(event._value_type); column.add_child(value_type)
			_add_field("value", "Value", str(event.value))
		else:
			for key: String in event.get_shortcode_parameters():
				var property: String = event.get_shortcode_parameters()[key].property
				_add_field(property, property.replace("_", " ").capitalize(), event.get(property))
				if requested == "Audio" and Source.Media.FLAGS.has(property):
					var flag: String = Source.Media.FLAGS[property]
					_add_field(flag, "Override channel " + property.replace("_", " "), event.get(flag))
	message = Label.new(); message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(message)
	message.text = problem if not problem.is_empty() else (("Edit" if editing else "Insert") + " " + requested + " at line " + str(first_line + 1) + ". Apply is one undo operation.")
	get_ok_button().disabled = not problem.is_empty()
	_popup_fitted()

func line(caption: String, node_name: String) -> LineEdit:
	var label := Label.new(); label.text = caption; column.add_child(label)
	var edit := LineEdit.new(); edit.name = node_name; column.add_child(edit); return edit

func _add_field(key: String, caption: String, value: Variant) -> void:
	var field := Field.new(); field.name = key; field.setup(caption, value); column.add_child(field); fields[key] = field

func _apply() -> void:
	if not is_instance_valid(source_editor) or not source_editor.editable or original_source != source_editor.text:
		message.text = "The document changed or became read-only. Reopen this form."; return
	var raw := ""
	if current_kind == "Text":
		var event := DialogicTextEvent.new(); event.text = text_body.text
		if not speaker.text.strip_edges().is_empty():
			if RegEx.create_from_string('["\\r\\n\\[\\]{}():]').search(speaker.text): message.text = "Choose a static character identifier."; return
			event.character_identifier = speaker.text.strip_edges(); event.character = null
		event.portrait = portrait.text.strip_edges()
		raw = event.to_text()
	else:
		var values := {}
		for key: String in fields:
			values[key] = fields[key].value()
			if not fields[key].last_error.is_empty(): message.text = fields[key].last_error; return
		if current_kind == "Setting": values["mode"] = setting_mode.selected; values["_value_type"] = value_type.selected
		var generated := Source.serialize(current_kind, values)
		if generated.has("error"): message.text = generated.error; return
		raw = generated.source
		var runtime: Dictionary = workspace.variable_document.runtime_values() if workspace != null and workspace.variable_document != null else {}
		var checked := Source.inspect(raw, Source.create(current_kind), workspace, runtime, false)
		if checked.has("error"): message.text = checked.error; return
	if current_kind == "Text" and not translation_id.is_empty(): raw += " #id:" + translation_id
	var inserted := prefix + raw.replace("\n", "\n" + prefix)
	var lines := original_source.split("\n")
	var candidate := PackedStringArray()
	for i: int in first_line: candidate.append(lines[i])
	candidate.append(inserted)
	for i: int in range(last_line + 1 if editing else first_line, lines.size()): candidate.append(lines[i])
	if current_kind == "Text":
		var validation := preload("res://application/timeline_codec.gd").validate_content("\n".join(candidate), workspace)
		if not validation.supported: message.text = "\n".join(validation.diagnostics); return
	source_editor.remove_secondary_carets(); source_editor.begin_complex_operation(); source_editor.deselect()
	source_editor.set_caret_line(first_line); source_editor.set_caret_column(0)
	if editing: source_editor.select(first_line, 0, last_line, source_editor.get_line(last_line).length())
	else: inserted += "\n"
	source_editor.insert_text_at_caret(inserted); source_editor.end_complex_operation(); hide()

func _build_insert_tools(target: TextEdit) -> void:
	var row := HBoxContainer.new(); column.add_child(row)
	var picker := OptionButton.new(); picker.name = "TextMarkup"
	var tags := ["b", "i", "u", "s", "color", "font_size", "font", "img", "wave", "shake", "rainbow", "random", "n", "n+", "br", "speed", "lspeed", "pause", "input", "signal", "aa", "ns", "portrait", "extra_data", "mood", "Custom BBCode"]
	for tag: String in tags: picker.add_item(tag)
	row.add_child(picker)
	var parameter := LineEdit.new(); parameter.name = "MarkupParameter"; parameter.placeholder_text = "Value / options"; parameter.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(parameter)
	var insert := Button.new(); insert.text = "Insert"; row.add_child(insert)
	insert.pressed.connect(func():
		var tag: String = tags[picker.selected]
		var value: String = parameter.text
		var selected: String = target.get_selected_text()
		var text := ""
		if tag == "random": text = "<" + (value if not value.is_empty() else "one/two") + ">"
		elif tag == "Custom BBCode": text = "[" + value + "]" + selected
		elif tag == "img": text = "[img]" + value + "[/img]"
		elif tag in ["n", "n+", "br", "speed", "lspeed", "pause", "input", "signal", "aa", "ns", "portrait", "extra_data", "mood"]: text = "[" + tag + ("=" + value if not value.is_empty() else "") + "]" + selected
		else: text = "[" + tag + ("=" + value if not value.is_empty() else "") + "]" + selected + "[/" + tag + "]"
		target.begin_complex_operation(); target.insert_text_at_caret(text); target.end_complex_operation(); target.grab_focus())

func _popup_fitted() -> void:
	var desired := Vector2i(730, 650)
	if is_embedded():
		var host := get_parent().get_window()
		desired.x = mini(desired.x, maxi(min_size.x, host.size.x - 40))
		desired.y = mini(desired.y, maxi(min_size.y, host.size.y - 60))
	popup_centered(desired)
