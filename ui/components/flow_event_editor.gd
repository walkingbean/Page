extends ConfirmationDialog

const Flow = preload("res://application/flow_source.gd")
const Structure = preload("res://application/condition_source.gd")
var kind: OptionButton
var timeline: LineEdit
var target: LineEdit
var display_name: LineEdit
var message: Label
var source_editor: CodeEdit
var original_source := ""
var source_line := 0
var editing := false
var prefix := ""


func _ready() -> void:
	title = "Flow event"
	size = Vector2i(560, 420)
	min_size = size
	dialog_hide_on_ok = false
	get_ok_button().text = "Apply"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 10)
	scroll.add_child(fields)
	kind = OptionButton.new()
	kind.name = "FlowKind"
	for value: String in ["Label", "Jump", "Return", "End"]:
		kind.add_item(value)
	fields.add_child(kind)
	timeline = _field(fields, "Target timeline · empty means this timeline", "FlowTimeline")
	target = _field(fields, "Label identifier · empty Jump target means the beginning", "FlowTarget")
	display_name = _field(fields, "Label display name · optional", "FlowDisplayName")
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 75
	fields.add_child(message)
	kind.item_selected.connect(func(_index: int): _show_fields())
	confirmed.connect(_apply)


func _field(parent: Control, caption: String, node_name: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.name = node_name
	edit.set_meta("caption", label)
	parent.add_child(edit)
	return edit


func _show_fields() -> void:
	for field: LineEdit in [timeline, target, display_name]:
		field.visible = (field == timeline and kind.selected == 1) or (field == target and kind.selected < 2) or (field == display_name and kind.selected == 0)
		field.get_meta("caption").visible = field.visible


func open_for_editor(editor: CodeEdit, requested: String = "Label") -> void:
	if not editor.editable:
		return
	source_editor = editor
	original_source = editor.text
	source_line = editor.get_caret_line()
	var line := editor.get_line(source_line)
	var raw := line.strip_edges(true, false)
	prefix = line.left(line.length() - raw.length())
	kind.select(["Label", "Jump", "Return", "End"].find(requested))
	timeline.text = ""
	target.text = "NewLabel" if requested == "Label" else ""
	display_name.text = ""
	var event := DialogicTimeline.event_from_string(raw, DialogicResourceUtil.get_event_cache())
	editing = (requested == "Label" and event is DialogicLabelEvent) or (requested == "Jump" and event is DialogicJumpEvent) or (requested == "Return" and event is DialogicReturnEvent) or (requested == "End" and event is DialogicEndTimelineEvent)
	get_ok_button().disabled = false
	message.text = "Insert a native flow event before this line. Timeline aliases belong to the content project."
	if editing:
		# The property form checks spelling; workspace references are checked by
		# the document validator after editing, including dynamic labels.
		if event is DialogicJumpEvent:
			var value := raw.trim_prefix("jump").strip_edges()
			var slash := value.rfind("/")
			timeline.text = value.left(slash) if slash >= 0 else ""
			target.text = value.substr(slash + 1)
		elif event is DialogicLabelEvent:
			var model := Flow.inspect(raw, event)
			if model.has("error"):
				get_ok_button().disabled = true
				message.text = model.error
			else:
				target.text = model.name
				display_name.text = model.display_name
		if not get_ok_button().disabled:
			message.text = "Edit line %d. Other lines remain unchanged." % (source_line + 1)
	_show_fields()
	popup_centered(size)
	(target if target.visible else kind).grab_focus()


func _apply() -> void:
	if get_ok_button().disabled:
		return
	if not is_instance_valid(source_editor) or not source_editor.editable or source_editor.text != original_source:
		message.text = "The document changed or became read-only. Reopen this form."
		return
	var raw := ""
	match kind.selected:
		0: raw = "label " + target.text.strip_edges() + (" (" + display_name.text.strip_edges() + ")" if not display_name.text.strip_edges().is_empty() else "")
		1: raw = "jump " + (timeline.text.strip_edges() + "/" if not timeline.text.strip_edges().is_empty() else "") + target.text.strip_edges()
		2: raw = "return"
		3: raw = "[end_timeline]"
	raw = raw.strip_edges()
	var event := DialogicTimeline.event_from_string(raw, DialogicResourceUtil.get_event_cache())
	var check := Flow.inspect(raw, event)
	if check.has("error") and not (kind.selected == 1 and target.text.contains("{") and not timeline.text.contains("{")):
		message.text = check.error
		return
	_replace(prefix + raw)


func _replace(raw: String) -> void:
	source_editor.remove_secondary_carets()
	source_editor.begin_complex_operation()
	source_editor.deselect()
	source_editor.set_caret_line(source_line)
	source_editor.set_caret_column(0)
	if editing:
		source_editor.select(source_line, 0, source_line, source_editor.get_line(source_line).length())
	else:
		raw += "\n"
	source_editor.insert_text_at_caret(raw)
	source_editor.end_complex_operation()
	hide()
	source_editor.grab_focus()
