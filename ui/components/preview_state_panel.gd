extends Window

var preview: Window
var slots: ItemList
var slot_name: LineEdit
var history: TextEdit
var message: Label
var confirm: ConfirmationDialog
var pending: Callable

func _ready() -> void:
	title = "History & saves"; size = Vector2i(620, 540); min_size = Vector2i(440, 320); transient = true; exclusive = true; visible = false
	var column := VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(column)
	message = Label.new(); message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(message)
	history = TextEdit.new(); history.name = "HistoryText"; history.editable = false; history.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; history.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(history)
	slots = ItemList.new(); slots.name = "SaveSlots"; slots.custom_minimum_size.y = 100; column.add_child(slots)
	slot_name = LineEdit.new(); slot_name.name = "SaveSlotName"; slot_name.placeholder_text = "Slot name · blank uses native default"; column.add_child(slot_name)
	slots.item_selected.connect(func(index: int): slot_name.text = slots.get_item_text(index))
	var options := HBoxContainer.new(); column.add_child(options)
	for setting: String in ["Wait for voice", "Skip voice"]:
		var check := CheckBox.new(); check.text = setting; check.button_pressed = true; options.add_child(check)
		check.toggled.connect(func(value: bool):
			if preview == null: return
			if setting == "Wait for voice": preview.get("_handler").Inputs.auto_advance.await_playing_voice = value
			else: preview.get("_handler").Inputs.auto_skip.skip_voice = value)
	var row := HBoxContainer.new(); column.add_child(row)
	for label: String in ["Save", "Load", "Delete", "Refresh", "Close"]:
		var button := Button.new(); button.name = label + "PreviewSlot"; button.text = label; row.add_child(button)
		button.pressed.connect(func(): action(label))
	confirm = ConfirmationDialog.new(); add_child(confirm); confirm.confirmed.connect(func(): if pending.is_valid(): pending.call())
	close_requested.connect(close_panel)

func close_panel() -> void:
	hide()
	if is_instance_valid(preview): preview.grab_focus()

func open_panel(owner_preview: Window) -> void:
	preview = owner_preview; refresh()
	var desired := Vector2i(620, 540)
	if is_embedded(): desired = Vector2i(mini(desired.x, preview.size.x - 24), mini(desired.y, preview.size.y - 48))
	popup_centered(desired)

func refresh() -> void:
	if preview.get("_media") == null or not is_instance_valid(preview.get("_media").save_node): message.text = "Start a preview first."; return
	var handler: DialogicGameHandler = preview.get("_handler")
	var lines := PackedStringArray()
	for item: Dictionary in handler.History.get_simple_history():
		var character: Variant = item.get("character", item.get("character_name", ""))
		var display_name: String = character.display_name if character is DialogicCharacter else str(character)
		lines.append(display_name + (": " if not display_name.is_empty() else "") + str(item.get("text", "")))
	lines.append("\nFull event history:")
	lines.append_array(preview.get("_media").map_value(handler.History.full_event_history_content, true))
	history.text = "\n".join(lines)
	slots.clear()
	for name: String in handler.Save.get_slot_names(): slots.add_item(name)
	message.text = "Preview saves belong to this content folder. Enable history in Settings to collect entries."

func action(kind: String) -> void:
	if kind == "Close": close_panel(); return
	if kind == "Refresh": refresh(); return
	if preview.get("_media") == null: message.text = "Start a preview first."; return
	var save: Node = preview.get("_media").save_node
	var name: String = slot_name.text if not slot_name.text.is_empty() else save.get_default_slot()
	if kind == "Delete" or (kind == "Save" and save.has_slot(name)):
		pending = execute.bind(kind, name); confirm.dialog_text = ("Delete" if kind == "Delete" else "Overwrite") + " preview slot '" + name + "'?"; confirm.popup_centered(); return
	execute(kind, name)

func execute(kind: String, name: String) -> void:
	if preview.get("_media") == null: return
	var save: Node = preview.get("_media").save_node
	var error: Error
	match kind:
		"Save": error = save.save(name)
		"Load":
			error = save.load(name)
			if error == OK:
				message.text = "Loading preview state…"
				error = await save.load_completed
		"Delete": error = save.delete_slot(name)
	refresh()
	message.text = kind + " completed: " + name if error == OK else (save.last_error if not save.last_error.is_empty() else error_string(error))
	if error == OK and kind == "Load": close_panel()
