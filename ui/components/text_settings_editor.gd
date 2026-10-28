extends Window

signal all_settings_requested
signal saved
const Document = preload("res://application/text_settings_document.gd")
const Field = preload("res://ui/components/native_value_field.gd")
const Native = preload("res://application/native_resource.gd")
var document: RefCounted
var workspace: RefCounted
var fields: Dictionary = {}
var column: VBoxContainer
var message: Label
var custom: CodeEdit
var initial_custom := ""
var save_button: Button
var discard_dialog: ConfirmationDialog
var creation_dialog: ConfirmationDialog
var channel_editor: ConfirmationDialog

func _ready() -> void:
	title = "Text, media & state settings"; size = Vector2i(880, 680); min_size = Vector2i(600, 400); transient = true; exclusive = true; visible = false
	var layout := VBoxContainer.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(layout)
	var message_scroll := ScrollContainer.new(); message_scroll.custom_minimum_size.y = 72; message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; layout.add_child(message_scroll)
	message = Label.new(); message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; message.size_flags_horizontal = Control.SIZE_EXPAND_FILL; message_scroll.add_child(message)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; layout.add_child(scroll)
	column = VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation", 8); scroll.add_child(column)
	var all_settings := Button.new(); all_settings.name = "AllNativeSettings"; all_settings.text = "All native settings…"; layout.add_child(all_settings)
	all_settings.pressed.connect(func():
		if dirty(): message.text = "Save or close and discard these changes before opening all native settings."
		else: all_settings_requested.emit())
	var row := HBoxContainer.new(); layout.add_child(row)
	save_button = Button.new(); save_button.name = "SaveSettings"; save_button.text = "Save settings"; save_button.pressed.connect(save_settings); row.add_child(save_button)
	var close := Button.new(); close.text = "Close"; close.pressed.connect(_request_close); row.add_child(close)
	discard_dialog = ConfirmationDialog.new(); discard_dialog.dialog_text = "Discard unsaved setting changes?"; discard_dialog.confirmed.connect(hide); add_child(discard_dialog)
	creation_dialog = ConfirmationDialog.new(); creation_dialog.dialog_text = "Create a native project.godot in this content folder to store text, media and state settings?"; creation_dialog.confirmed.connect(func(): save_settings(true)); add_child(creation_dialog)
	channel_editor = preload("res://ui/components/audio_channels_editor.gd").new(); add_child(channel_editor)
	channel_editor.channels_applied.connect(func(channels: Dictionary):
		var field: Control = fields["audio/channel_defaults"]
		field.control.text = var_to_str(channels); field.edited = true)
	close_requested.connect(_request_close)

func open_settings(source_workspace: RefCounted) -> void:
	workspace = source_workspace
	document = Document.new()
	var error: Error = document.open_root(workspace)
	for child: Node in column.get_children(): column.remove_child(child); child.queue_free()
	fields.clear()
	if error != OK:
		message.text = document.last_error; save_button.disabled = true; _popup_fitted(); return
	for key: String in Document.DEFAULTS:
		if key.begins_with("layout/") or key.begins_with("settings/"): continue
		var field := Field.new(); field.name = key.replace("/", "_")
		field.setup(key.replace("/", " · ").replace("_", " ").capitalize(), document.values.get(key, Document.DEFAULTS[key]), {"type": typeof(Document.DEFAULTS[key])})
		column.add_child(field); fields[key] = field
		if key == "audio/channel_defaults":
			var button := Button.new(); button.name = "EditAudioChannels"; button.text = "Edit audio channels"; column.add_child(button)
			button.pressed.connect(func():
				var values: Variant = fields["audio/channel_defaults"].value()
				if values is Dictionary: channel_editor.open_channels(values))
	var label := Label.new(); label.text = "Runtime setting defaults · scalar values (including text_speed)"; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(label)
	custom = CodeEdit.new(); custom.name = "RuntimeSettings"; custom.custom_minimum_size.y = 130; column.add_child(custom)
	var dictionary := {}
	for key: String in document.values:
		if key.begins_with("settings/"): dictionary[key.trim_prefix("settings/")] = document.values[key]
	if not dictionary.has("text_speed"): dictionary["text_speed"] = 1.0
	initial_custom = var_to_str(dictionary); custom.text = initial_custom
	message.text = "Native settings for: " + workspace.root_path + "\nAudio channels: volume (dB), audio_bus, fade_length, loop. Autosave modes: 0 jumps, 1 timer, 2 text. Preview uses its own Advance controls."
	save_button.disabled = document.read_only
	if document.read_only: message.text = "\n".join(document.diagnostics)
	_popup_fitted()

func dirty() -> bool:
	if custom != null and custom.text != initial_custom: return true
	for field: Control in fields.values():
		if field.is_changed(): return true
	return document != null and document.dirty

func _request_close() -> void:
	if dirty(): discard_dialog.popup_centered()
	else: hide()

func save_settings(creation_confirmed := false) -> void:
	if document == null or document.read_only: return
	var changes := {}
	for key: String in fields:
		var field: Control = fields[key]
		var value: Variant = field.value()
		if not field.last_error.is_empty(): message.text = key + ": " + field.last_error; return
		var problem := Document.value_error(key, value)
		if not problem.is_empty(): message.text = problem; return
		if field.is_changed(): changes[key] = value
	var runtime := Native.decode(custom.text)
	if runtime.has("error") or not runtime.get("value") is Dictionary: message.text = runtime.get("error", "Runtime defaults must be a native dictionary."); return
	for key: Variant in runtime.value:
		if not key is String: message.text = "Setting names must be strings."; return
		var problem := Document.value_error("settings/" + key, runtime.value[key])
		if problem.is_empty(): problem = preload("res://application/interaction_source.gd").setting_name_error(key)
		if not problem.is_empty(): message.text = problem; return
	if document.path.is_empty() and not creation_confirmed: creation_dialog.popup_centered(); return
	var previous: String = document.content
	var previous_values: Dictionary = document.values.duplicate(true)
	for key: String in changes:
		if document.set_value(key, changes[key]) != OK: message.text = document.last_error; document.set_content(previous); document.values = previous_values; return
	if custom.text != initial_custom:
		for key: String in document.values.keys():
			if key.begins_with("settings/") and not runtime.value.has(key.trim_prefix("settings/")): document.remove_value(key)
		for key: String in runtime.value:
			if document.set_value("settings/" + key, runtime.value[key]) != OK: message.text = document.last_error; document.set_content(previous); document.values = previous_values; return
	if document.save_file() != OK: message.text = document.last_error; return
	workspace.refresh()
	saved.emit()
	open_settings(workspace)
	message.text = "Saved native settings. " + workspace.root_path

func _popup_fitted() -> void:
	var desired := Vector2i(880, 680)
	if is_embedded():
		var host := get_parent().get_window()
		desired.x = mini(desired.x, maxi(min_size.x, host.size.x - 40))
		desired.y = mini(desired.y, maxi(min_size.y, host.size.y - 60))
	popup_centered(desired)
