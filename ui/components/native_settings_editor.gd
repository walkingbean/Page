extends Window

signal saved
const Document = preload("res://application/project_document.gd")
const Catalog = preload("res://application/settings_catalog.gd")
const Field = preload("res://ui/components/native_value_field.gd")
const Native = preload("res://application/native_resource.gd")
var workspace: RefCounted
var document: RefCounted
var fields: Dictionary = {}
var rows: Dictionary = {}
var opaque: Dictionary = {}
var resets: Dictionary = {}
var reset_edits: Dictionary = {}
var defaults: Dictionary = {}
var column: VBoxContainer
var filter: LineEdit
var category: OptionButton
var message: Label
var save_button: Button
var transition_dialog: ConfirmationDialog
var creation_dialog: ConfirmationDialog
var pending_action: Callable

func _init() -> void:
	title = "All native Dialogic settings"; visible = false; transient = true; exclusive = true; min_size = Vector2i(640, 420)

func _ready() -> void:
	var layout := VBoxContainer.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(layout)
	var top := HBoxContainer.new(); layout.add_child(top)
	filter = LineEdit.new(); filter.name = "SettingSearch"; filter.placeholder_text = "Search setting name"; filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(filter)
	category = OptionButton.new(); category.name = "SettingCategory"; top.add_child(category)
	filter.text_changed.connect(func(_value: String): apply_filter())
	category.item_selected.connect(func(_index: int): apply_filter())
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; layout.add_child(scroll)
	column = VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(column)
	message = Label.new(); message.name = "SettingsStatus"; message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; message.max_lines_visible = 3; layout.add_child(message)
	var actions := HBoxContainer.new(); layout.add_child(actions)
	save_button = Button.new(); save_button.name = "SaveNativeSettings"; save_button.text = "Save"; save_button.pressed.connect(func(): save_settings()); actions.add_child(save_button)
	var close := Button.new(); close.text = "Close"; close.pressed.connect(func(): transition(hide)); actions.add_child(close)
	transition_dialog = ConfirmationDialog.new(); transition_dialog.title = "Unsaved settings"; transition_dialog.dialog_text = "Save native setting changes before continuing?"; transition_dialog.get_ok_button().text = "Save"; transition_dialog.add_button("Discard", false, "discard"); transition_dialog.dialog_hide_on_ok = false; add_child(transition_dialog)
	transition_dialog.confirmed.connect(func():
		if save_settings(): finish_transition())
	transition_dialog.custom_action.connect(func(action: StringName):
		if action == &"discard": fields.clear(); resets.clear(); reset_edits.clear(); document = null; finish_transition())
	transition_dialog.canceled.connect(func(): pending_action = Callable())
	creation_dialog = ConfirmationDialog.new(); creation_dialog.dialog_text = "Create project.godot in this content folder?"; add_child(creation_dialog)
	creation_dialog.confirmed.connect(func():
		if save_settings(true) and pending_action.is_valid(): finish_transition())
	close_requested.connect(func(): transition(hide))

func open_settings(content: RefCounted) -> void:
	workspace = content; document = Document.new()
	var error: Error = document.open_project(workspace)
	for child: Node in column.get_children(): column.remove_child(child); child.queue_free()
	fields.clear(); rows.clear(); resets.clear(); reset_edits.clear(); opaque.clear()
	if error != OK: message.text = document.last_error; save_button.disabled = true; popup_fitted(); return
	defaults = Catalog.defaults()
	var keys := defaults.keys()
	for full: String in document.entries:
		if full.begins_with("dialogic/") and not keys.has(full.trim_prefix("dialogic/")): keys.append(full.trim_prefix("dialogic/"))
	keys.sort()
	category.clear(); category.add_item("All")
	var categories: Array[String] = []
	for key: String in keys:
		var group := key.get_slice("/", 0)
		if not group in categories: categories.append(group); category.add_item(group)
		var row := HBoxContainer.new(); column.add_child(row); rows[key] = row
		var entry: Dictionary = document.entries.get("dialogic/" + key, {})
		if entry.get("opaque", false):
			var label := Label.new(); label.text = key; row.add_child(label)
			var literal := LineEdit.new(); literal.text = entry.literal; literal.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(literal); fields[key] = literal; opaque[key] = entry.literal
		else:
			var value: Variant = entry.get("value", defaults.get(key))
			var info := {"type": typeof(value)}
			if Catalog.ENUMS.has(key): info["hint"] = PROPERTY_HINT_ENUM; info["hint_string"] = Catalog.ENUMS[key]
			var field := Field.new(); field.name = key.replace("/", "_"); field.setup(key.replace("/", " · "), value, info); row.add_child(field); fields[key] = field
		var reset := Button.new(); reset.text = "Reset"; reset.tooltip_text = "Remove this project's override and use the native default."; row.add_child(reset)
		track_field(key, row)
		reset.pressed.connect(func(): reset_field(key, row))
	message.text = "%d native settings · Only changed fields are written. Reset removes an override.\nUnknown fields remain native text. Extension scripts run only in the separate target preview." % keys.size()
	save_button.disabled = document.read_only
	apply_filter(); popup_fitted()

func apply_filter() -> void:
	var group := category.get_item_text(category.selected) if category.selected >= 0 else "All"
	for key: String in rows: rows[key].visible = (group == "All" or key.get_slice("/", 0) == group) and (filter.text.is_empty() or key.to_lower().contains(filter.text.to_lower()))

func dirty() -> bool:
	if document == null: return false
	if document.dirty or not resets.is_empty() or not reset_edits.is_empty(): return true
	for key: String in fields:
		if opaque.has(key):
			if fields[key].text != opaque[key]: return true
		elif fields[key].is_changed(): return true
	return false

func transition(action: Callable) -> void:
	if dirty(): pending_action = action; transition_dialog.popup_centered(Vector2i(440, 160))
	else: hide(); action.call()

func finish_transition() -> void:
	transition_dialog.hide(); hide()
	var action := pending_action; pending_action = Callable()
	if action.is_valid(): action.call_deferred()

func save_settings(creation_confirmed := false) -> bool:
	if document == null or document.read_only: return false
	var changes := {}
	for key: String in fields:
		if resets.has(key): continue
		if opaque.has(key):
			if fields[key].text != opaque[key]: changes[key] = {"literal": fields[key].text}
			continue
		var field: Control = fields[key]
		if not field.is_changed() and not reset_edits.has(key): continue
		var value: Variant = field.value()
		var error: String = field.last_error if not field.last_error.is_empty() else Catalog.error(key, value)
		if not error.is_empty(): message.text = key + ": " + error; return false
		changes[key] = {"value": value}
	if document.path.is_empty() and not creation_confirmed: creation_dialog.popup_centered(); return false
	var previous: String = document.content
	for key: String in resets:
		if document.remove_value("dialogic/" + key) != OK: message.text = document.last_error; document.set_content(previous); return false
	for key: String in changes:
		var entry: Dictionary = changes[key]
		var result: Error = document.set_literal("dialogic/" + key, entry.literal) if entry.has("literal") else document.set_value("dialogic/" + key, entry.value)
		if result != OK: message.text = document.last_error; document.set_content(previous); return false
	if document.save_file() != OK: message.text = document.last_error; return false
	workspace.refresh(); saved.emit(); open_settings(workspace)
	message.text = "Saved native settings to " + document.target_path
	return true

func popup_fitted() -> void:
	var available: Vector2i = get_parent().get_window().size
	popup_centered(Vector2i(mini(900, available.x - 40), mini(660, available.y - 60)))

func track_field(key: String, row: Control) -> void:
	var edited := func(_value: String = ""):
		if resets.has(key): reset_edits[key] = true
		resets.erase(key); row.modulate = Color.WHITE
	if opaque.has(key): fields[key].text_changed.connect(edited)
	else: fields[key].value_changed.connect(edited)

func reset_field(key: String, row: Control) -> void:
	resets[key] = true; reset_edits.erase(key)
	if defaults.has(key):
		var old: Control = fields[key]; row.remove_child(old); old.queue_free()
		var value: Variant = defaults[key]
		var info := {"type": typeof(value)}
		if Catalog.ENUMS.has(key): info["hint"] = PROPERTY_HINT_ENUM; info["hint_string"] = Catalog.ENUMS[key]
		var field := Field.new(); field.setup(key.replace("/", " · "), value, info); row.add_child(field); row.move_child(field, 0); fields[key] = field; opaque.erase(key)
		track_field(key, row)
	row.modulate = Color(0.65, 0.65, 0.65); message.text = key + " will use its native default after saving. Editing it creates a new override."
