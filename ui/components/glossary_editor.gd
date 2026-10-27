extends Window

signal saved
const Document = preload("res://application/glossary_document.gd")
const Project = preload("res://application/localization_project.gd")
var workspace: RefCounted
var project: RefCounted
var document: RefCounted
var browser: OptionButton
var entries: ItemList
var path_field: LineEdit
var name_field: LineEdit
var aliases_field: LineEdit
var title_field: LineEdit
var text_field: TextEdit
var extra_field: TextEdit
var enabled_field: CheckBox
var entry_enabled: CheckBox
var case_field: CheckBox
var color_field: ColorPickerButton
var registered_field: CheckBox
var message: Label
var file_dialog: FileDialog
var unsaved: ConfirmationDialog
var pending: Callable
var selected_name := ""
var initial_fields: Dictionary = {}
var initial_header: Array = []
var loading := false

func _ready() -> void:
	title = "Glossary"; size = Vector2i(1050, 730); min_size = Vector2i(760, 550); transient = true; exclusive = true; visible = false
	var box := VBoxContainer.new(); box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(box)
	var tools := HBoxContainer.new(); box.add_child(tools)
	browser = OptionButton.new(); browser.name = "GlossaryBrowser"; browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tools.add_child(browser)
	preload("res://ui/components/native_popup.gd").configure(browser)
	browser.item_selected.connect(func(i: int): transition(func(): open_path(browser.get_item_metadata(i))))
	button(tools, "New", func(): transition(new_glossary)); button(tools, "Open", func(): file_dialog.popup_centered_ratio(0.7))
	button(tools, "Move earlier", func(): move_registration(-1)); button(tools, "Move later", func(): move_registration(1))
	path_field = line(box, "File in content root", "GlossaryPath")
	var options := HBoxContainer.new(); box.add_child(options)
	enabled_field = check(options, "Glossary enabled", "GlossaryEnabled")
	registered_field = check(options, "Registered in content project", "GlossaryRegistered")
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; split.split_offset = 230; box.add_child(split)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 180; split.add_child(left)
	entries = ItemList.new(); entries.name = "GlossaryEntries"; entries.size_flags_vertical = Control.SIZE_EXPAND_FILL; left.add_child(entries)
	entries.item_selected.connect(func(i: int):
		if apply_entry(): show_entry(entries.get_item_text(i)))
	var entry_tools := HBoxContainer.new(); left.add_child(entry_tools)
	button(entry_tools, "Add entry", add_entry); button(entry_tools, "Delete entry", delete_entry)
	var scroll := ScrollContainer.new(); scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; split.add_child(scroll)
	var fields := VBoxContainer.new(); fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(fields)
	name_field = line(fields, "Name", "GlossaryName")
	aliases_field = line(fields, "Aliases · comma separated", "GlossaryAliases")
	title_field = line(fields, "Popup title", "GlossaryTitle")
	text_field = area(fields, "Definition · native rich text", "GlossaryText", 180)
	extra_field = area(fields, "Extra", "GlossaryExtra", 90)
	entry_enabled = check(fields, "Entry enabled", "EntryEnabled")
	case_field = check(fields, "Case sensitive", "GlossaryCase")
	color_field = ColorPickerButton.new(); color_field.name = "GlossaryColor"; color_field.custom_minimum_size = Vector2(120, 30); fields.add_child(color_field)
	button(fields, "Apply entry", apply_entry)
	message = Label.new(); message.name = "GlossaryMessage"; message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; message.custom_minimum_size.y = 54; box.add_child(message)
	var footer := HBoxContainer.new(); box.add_child(footer)
	button(footer, "Save glossary", save_glossary); button(footer, "Close", func(): transition(hide))
	file_dialog = FileDialog.new(); file_dialog.access = FileDialog.ACCESS_FILESYSTEM; file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; file_dialog.filters = PackedStringArray(["*.tres ; Native glossary"]); add_child(file_dialog)
	file_dialog.file_selected.connect(func(path: String): transition(func(): open_path(path)))
	unsaved = ConfirmationDialog.new(); unsaved.title = "Unsaved glossary changes"; unsaved.dialog_text = "Save changes before continuing?"; unsaved.ok_button_text = "Save"; unsaved.add_button("Discard", false, "discard"); add_child(unsaved)
	unsaved.confirmed.connect(func():
		if save_glossary() and pending.is_valid(): pending.call())
	unsaved.custom_action.connect(func(action: String):
		if action == "discard" and pending.is_valid(): pending.call())
	close_requested.connect(func(): transition(hide))

func button(parent: Node, caption: String, action: Callable) -> Button:
	var node := Button.new(); node.text = caption; node.name = caption.replace(" ", ""); node.pressed.connect(action); parent.add_child(node); return node

func line(parent: Node, caption: String, id: String) -> LineEdit:
	var label := Label.new(); label.text = caption; parent.add_child(label)
	var node := LineEdit.new(); node.name = id; parent.add_child(node); return node

func area(parent: Node, caption: String, id: String, height: int) -> TextEdit:
	var label := Label.new(); label.text = caption; parent.add_child(label)
	var node := TextEdit.new(); node.name = id; node.custom_minimum_size.y = height; node.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; parent.add_child(node); return node

func check(parent: Node, caption: String, id: String) -> CheckBox:
	var node := CheckBox.new(); node.name = id; node.text = caption; parent.add_child(node); return node

func open_glossaries(source_workspace: RefCounted) -> void:
	workspace = source_workspace; project = Project.new()
	var initial_error: String = "" if project.open_root(workspace) == OK else project.last_error
	browser.clear()
	for logical: String in project.glossaries:
		browser.add_item(logical); browser.set_item_metadata(browser.item_count - 1, workspace.resolve_content_path(logical))
	file_dialog.current_dir = workspace.root_path
	if browser.item_count: open_path(browser.get_item_metadata(0))
	else: new_glossary()
	if not initial_error.is_empty(): message.text = initial_error
	var available := Vector2i(get_parent().get_viewport().get_visible_rect().size)
	popup_centered(Vector2i(mini(1050, available.x - 40), mini(730, available.y - 60)))
	if is_embedded(): position = (available - size) / 2

func new_glossary() -> void:
	document = Document.new(); document.workspace = workspace
	path_field.text = "res://new_glossary.tres"; registered_field.button_pressed = true; enabled_field.button_pressed = true
	selected_name = ""; refresh_entries(); show_entry(""); remember_header()
	message.text = "Add entries, choose a file path, then save the native glossary and registration."

func open_path(path: String) -> void:
	var next := Document.new()
	if next.open_file(path, workspace) != OK: message.text = next.last_error; return
	document = next; selected_name = ""; path_field.text = workspace.content_path(path)
	registered_field.button_pressed = path_field.text in project.config.values["dialogic/glossary/glossary_files"]
	enabled_field.button_pressed = document.glossary.enabled if document.glossary != null else false
	refresh_entries(); show_entry(entries.get_item_text(0) if entries.item_count else ""); remember_header()
	message.text = "\n".join(document.diagnostics) if document.read_only else "Native glossary loaded. Existing translation IDs and extension fields are preserved."

func refresh_entries() -> void:
	entries.clear()
	if document == null or document.glossary == null: return
	for name: String in document.glossary.entries:
		if document.glossary.entries[name] is Dictionary:
			entries.add_item(name)
			if name == selected_name: entries.select(entries.item_count - 1)

func fields() -> Dictionary:
	var aliases: Array[String] = []
	for word: String in aliases_field.text.split(",", false): aliases.append(word.strip_edges())
	return {"name":name_field.text, "alternatives":aliases, "title":title_field.text, "text":text_field.text, "extra":extra_field.text, "enabled":entry_enabled.button_pressed, "case_sensitive":case_field.button_pressed, "color":color_field.color}

func show_entry(name: String) -> void:
	selected_name = name
	var entry: Dictionary = document.glossary.get_entry(name) if document != null and document.glossary != null else {}
	name_field.text = entry.get("name", ""); aliases_field.text = ", ".join(entry.get("alternatives", [])); title_field.text = entry.get("title", "")
	text_field.text = entry.get("text", ""); extra_field.text = entry.get("extra", "")
	entry_enabled.button_pressed = entry.get("enabled", true); case_field.button_pressed = entry.get("case_sensitive", true); color_field.color = entry.get("color", Color.POWDER_BLUE)
	initial_fields = fields()
	for node: Control in [name_field, aliases_field, title_field, text_field, extra_field]: node.set("editable", document != null and not document.read_only)

func apply_entry() -> bool:
	if document == null or document.read_only: return false
	if fields() == initial_fields: return true
	if document.set_entry(selected_name, fields()) != OK: message.text = document.last_error; return false
	selected_name = name_field.text.strip_edges(); initial_fields = fields(); refresh_entries()
	message.text = "Entry applied. Save to write the resource."
	return true

func add_entry() -> void:
	if not apply_entry(): return
	var name := "New entry"; var index := 2
	while document.glossary.entries.has(name): name = "New entry " + str(index); index += 1
	if document.set_entry("", {"name":name, "alternatives":[], "title":name, "text":"", "extra":""}) != OK: message.text = document.last_error; return
	refresh_entries(); show_entry(name)

func delete_entry() -> void:
	if document == null or selected_name.is_empty(): return
	if document.remove_entry(selected_name) != OK: message.text = document.last_error; return
	selected_name = ""; refresh_entries(); show_entry("")

func remember_header() -> void:
	initial_header = [path_field.text, enabled_field.button_pressed, registered_field.button_pressed]

func dirty() -> bool:
	return document != null and (document.dirty or fields() != initial_fields or initial_header != [path_field.text, enabled_field.button_pressed, registered_field.button_pressed])

func transition(action: Callable) -> void:
	if dirty(): pending = action; unsaved.popup_centered(Vector2i(460, 170))
	else: action.call()

func save_glossary() -> bool:
	if not apply_entry(): return false
	var target: String = workspace.resolve_content_path(path_field.text.strip_edges())
	if target.is_empty() or target.get_extension() != "tres": message.text = "Choose a content res:// path ending in .tres."; return false
	if target != document.path and FileAccess.file_exists(target): message.text = "Save As will not overwrite another resource."; return false
	if document.glossary.enabled != enabled_field.button_pressed:
		document.glossary.enabled = enabled_field.button_pressed
		if document.sync_resource() != OK: message.text = document.last_error; return false
	var paths: Array = Array(project.config.values["dialogic/glossary/glossary_files"])
	var logical: String = workspace.content_path(target)
	if registered_field.button_pressed and not logical in paths: paths.append(logical)
	if not registered_field.button_pressed: paths.erase(logical)
	if project.config.set_value("dialogic/glossary/glossary_files", paths) != OK: message.text = project.config.last_error; return false
	var before: Variant = document._original_bytes if target == document.path else null
	var result := Project.Transaction.commit(workspace, [{"path":target, "before":before, "after":document._encoded_content()}, project.config_change()])
	if result.has("error"): message.text = result.error; return false
	project.open_root(workspace); open_path(target); saved.emit()
	message.text = "Glossary and native project registration saved. Update CSV files after changing translatable content."
	return true

func move_registration(delta: int) -> void:
	if dirty(): message.text = "Save or discard glossary edits before changing registration order."; return
	var paths: Array = Array(project.config.values["dialogic/glossary/glossary_files"])
	var index := paths.find(path_field.text)
	if index < 0 or index + delta < 0 or index + delta >= paths.size(): return
	var value: Variant = paths[index]; paths.remove_at(index); paths.insert(index + delta, value)
	if project.config.set_value("dialogic/glossary/glossary_files", paths) != OK or project.config.save_file() != OK: message.text = project.config.last_error; return
	saved.emit(); message.text = "Glossary registration order saved."
