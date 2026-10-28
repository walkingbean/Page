extends ConfirmationDialog

const Source = preload("res://application/authoring_source.gd")
const Field = preload("res://ui/components/native_value_field.gd")
var editor: CodeEdit
var original := ""
var block: Dictionary
var kind := ""
var fields: Dictionary = {}
var column: VBoxContainer
var message: Label

func _ready() -> void:
	title = "Event properties"; dialog_hide_on_ok = false
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(580, 220); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	column = VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(column)
	confirmed.connect(apply)

func open_event(target: CodeEdit, record: Dictionary) -> void:
	editor = target; original = target.text; block = record; kind = record.kind
	for child: Node in column.get_children(): column.remove_child(child); child.queue_free()
	fields.clear()
	var event: DialogicEvent = record.event.get_script().new()
	event.from_text(record.raw)
	var properties := ["text"] if event is DialogicCommentEvent else (["argument_type", "argument"] if event is DialogicSignalEvent else ["autoload_name", "method", "arguments"])
	for key: String in properties:
		var metadata := {"type": typeof(event.get(key))}
		if key == "argument_type": metadata = {"type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": "String,Dictionary"}
		var field := Field.new(); field.name = key; field.setup(key.replace("_", " ").capitalize(), event.get(key), metadata); column.add_child(field); fields[key] = field
	message = Label.new(); message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; message.custom_minimum_size.x = 550; column.add_child(message)
	message.text = "Arguments use a native Array; prefix an expression String with @. Signal Dictionary uses JSON text."
	popup_centered(Vector2i(680, 300))

func apply() -> void:
	if not editor.editable: return
	if original != editor.text: message.text = "The timeline changed. Reopen this event."; return
	var event: DialogicEvent = block.event.get_script().new()
	event.from_text(block.raw)
	var changed := false
	for key: String in fields:
		var value: Variant = fields[key].value()
		if not fields[key].last_error.is_empty(): message.text = fields[key].last_error; return
		if key == "arguments" and not value is Array: message.text = "Arguments must be a native Array."; return
		if value is String and (value.contains("\n") or value.contains("\r")): message.text = "This event property requires a single physical line."; return
		if fields[key].is_changed(): event.set(key, value); changed = true
	if not changed: hide(); return
	var raw := event.to_text()
	if event is DialogicSignalEvent:
		var error := preload("res://application/host_source.gd").signal_syntax(raw)
		if not error.is_empty(): message.text = error; return
		if event.argument_type == 1 and not JSON.parse_string(str(event.argument)) is Dictionary: message.text = "Dictionary Signal requires a JSON object."; return
	if event is DialogicCallEvent and (event.autoload_name.is_empty() or event.method.is_empty()): message.text = "Specify the target autoload and method."; return
	var check: DialogicEvent = event.get_script().new(); check.from_text(raw)
	for key: String in fields:
		if check.get(key) != event.get(key): message.text = "The native parser cannot preserve " + key + ". Use native source to inspect the limitation."; return
	var end := Source.offset(editor, block.last_line, editor.get_line(block.last_line).length())
	Source.apply(editor, original.left(block.start) + block.indent + raw + original.substr(end))
	hide()
