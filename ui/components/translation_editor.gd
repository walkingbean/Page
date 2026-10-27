extends Window

signal saved
const Project = preload("res://application/localization_project.gd")
var workspace: RefCounted
var project: RefCounted
var enabled: CheckBox
var original: LineEdit
var file_mode: OptionButton
var location: OptionButton
var folder: LineEdit
var browser: OptionButton
var csv_path: LineEdit
var csv_text: CodeEdit
var new_locale: LineEdit
var message: Label
var csv_document: RefCounted
var initial_settings: Array = []
var initial_csv := ""
var dialog: FileDialog
var unsaved: ConfirmationDialog
var pending: Callable
var dialog_action := ""

func _ready() -> void:
	title = "Translations"; size = Vector2i(1080, 760); min_size = Vector2i(790, 560); transient = true; exclusive = true; visible = false
	var layout := VBoxContainer.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(layout)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; layout.add_child(scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.add_child(box)
	var options := HBoxContainer.new(); box.add_child(options)
	enabled = CheckBox.new(); enabled.text = "Enable translation"; enabled.name = "TranslationEnabled"; options.add_child(enabled)
	original = LineEdit.new(); original.name = "OriginalLocale"; original.placeholder_text = "Original locale, e.g. en"; original.custom_minimum_size.x = 180; options.add_child(original)
	file_mode = OptionButton.new(); file_mode.name = "TranslationFileMode"; file_mode.add_item("Per project"); file_mode.add_item("Per timeline / glossary"); options.add_child(file_mode)
	location = OptionButton.new(); location.name = "TranslationSaveMode"; location.add_item("Translation folder"); location.add_item("Next to source"); options.add_child(location)
	folder = line(box, "Translation folder in content project", "TranslationFolder")
	var tools := HBoxContainer.new(); box.add_child(tools)
	button(tools, "Save settings", save_settings)
	button(tools, "Update CSV files", update_csv)
	button(tools, "Collect translations", collect)
	button(tools, "Import CSV", func(): choose_file("import"))
	button(tools, "Export CSV", func(): choose_file("export"))
	browser = OptionButton.new(); browser.name = "TranslationCsvBrowser"; browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_child(browser)
	for picker: OptionButton in [file_mode, location, browser]: preload("res://ui/components/native_popup.gd").configure(picker)
	browser.item_selected.connect(func(i: int): transition(func(): open_csv(browser.get_item_metadata(i))))
	csv_path = line(box, "CSV file in content project", "TranslationCsvPath")
	var languages := HBoxContainer.new(); box.add_child(languages)
	new_locale = LineEdit.new(); new_locale.name = "AddLocale"; new_locale.placeholder_text = "New locale, e.g. ja"; new_locale.size_flags_horizontal = Control.SIZE_EXPAND_FILL; languages.add_child(new_locale)
	button(languages, "Add language", add_language)
	var label := Label.new(); label.text = "Edit native CSV below. Keep keys unchanged; quote values containing commas, quotes or line breaks."; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(label)
	csv_text = CodeEdit.new(); csv_text.name = "TranslationCsvText"; csv_text.size_flags_vertical = Control.SIZE_EXPAND_FILL; csv_text.custom_minimum_size.y = 210; box.add_child(csv_text)
	message = Label.new(); message.name = "TranslationMessage"; message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; message.custom_minimum_size.y = 64; box.add_child(message)
	var footer := HBoxContainer.new(); layout.add_child(footer)
	button(footer, "Save CSV", save_csv); button(footer, "Close", func(): transition(hide))
	dialog = FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.filters = PackedStringArray(["*.csv ; Translation CSV"]); dialog.file_selected.connect(file_selected); add_child(dialog)
	unsaved = ConfirmationDialog.new(); unsaved.title = "Unsaved translations"; unsaved.dialog_text = "Save edited settings and CSV before continuing?"; unsaved.ok_button_text = "Save"; unsaved.add_button("Discard", false, "discard"); add_child(unsaved)
	unsaved.confirmed.connect(func():
		if save_all() and pending.is_valid(): pending.call())
	unsaved.custom_action.connect(func(action: String):
		if action == "discard" and pending.is_valid(): pending.call())
	close_requested.connect(func(): transition(hide))

func button(parent: Node, caption: String, action: Callable) -> Button:
	var node := Button.new(); node.name = caption.replace(" ", ""); node.text = caption; node.pressed.connect(action); parent.add_child(node); return node

func line(parent: Node, caption: String, id: String) -> LineEdit:
	var label := Label.new(); label.text = caption; parent.add_child(label)
	var node := LineEdit.new(); node.name = id; parent.add_child(node); return node

func settings_fields() -> Array:
	return [enabled.button_pressed, original.text.strip_edges(), file_mode.selected, location.selected, folder.text.strip_edges()]

func open_translations(source_workspace: RefCounted) -> void:
	workspace = source_workspace; project = Project.new()
	var initial_error: String = "" if project.open_root(workspace) == OK else project.last_error
	var values: Dictionary = project.config.values
	enabled.button_pressed = values.get("dialogic/translation/enabled", false)
	original.text = values.get("dialogic/translation/original_locale", "en")
	file_mode.select(values.get("dialogic/translation/file_mode", 0)); location.select(values.get("dialogic/translation/save_mode", 0)); folder.text = values.get("dialogic/translation/translation_folder", "res://translations")
	initial_settings = settings_fields()
	refresh_browser()
	if browser.item_count: open_csv(browser.get_item_metadata(0))
	else:
		csv_document = null; csv_text.text = ""; initial_csv = ""; csv_path.text = ""
		message.text = "Choose the original language, save settings, then Update CSV files. Existing translations are retained."
	if not initial_error.is_empty(): message.text = initial_error
	var available := Vector2i(get_parent().get_viewport().get_visible_rect().size)
	popup_centered(Vector2i(mini(1080, available.x - 40), mini(760, available.y - 60)))
	if is_embedded(): position = (available - size) / 2

func refresh_browser() -> void:
	browser.clear()
	var paths: Dictionary = project.csv_paths()
	if paths.has("error"): message.text = paths.error; return
	var seen := {}
	for path: String in paths.paths.values():
		if seen.has(path) or not FileAccess.file_exists(path): continue
		seen[path] = true; browser.add_item(workspace.content_path(path)); browser.set_item_metadata(browser.item_count - 1, path)

func open_csv(path: String) -> void:
	var doc := Project.Csv.new()
	if doc.open_file(path) != OK: message.text = doc.last_error; return
	csv_document = doc; csv_text.text = doc.content; initial_csv = doc.content; csv_path.text = workspace.content_path(path)
	csv_text.editable = not doc.read_only
	message.text = "\n".join(doc.diagnostics) if doc.read_only else "CSV loaded. Save edits and Collect translations before transferring to a target Godot project."

func dirty() -> bool:
	return settings_fields() != initial_settings or csv_text.text != initial_csv or (csv_document != null and workspace.content_path(csv_document.path) != csv_path.text)

func transition(action: Callable) -> void:
	if dirty(): pending = action; unsaved.popup_centered(Vector2i(480, 180))
	else: action.call()

func save_settings() -> bool:
	if project == null: return false
	var fields := settings_fields()
	var keys := ["enabled", "original_locale", "file_mode", "save_mode", "translation_folder"]
	var candidate: RefCounted = Project.Config.new()
	# Preserve the snapshot read when the window opened, including conflict checks.
	for key: String in ["workspace", "target_path", "path", "content", "_original_content", "_original_bytes", "_expected_hash", "_newline", "_had_bom", "read_only"]: candidate.set(key, project.config.get(key))
	candidate.values = project.config.values.duplicate(true)
	for i: int in keys.size():
		if candidate.set_value("dialogic/translation/" + keys[i], fields[i]) != OK: message.text = candidate.last_error; return false
	var logical: String = fields[4]
	if logical != "res://" and workspace.resolve_content_path(logical.trim_suffix("/")).is_empty(): message.text = "Translation folder must stay inside the content root without symbolic links."; return false
	if candidate.save_file() != OK: message.text = candidate.last_error; return false
	project.open_root(workspace); initial_settings = fields; saved.emit(); message.text = "Native translation settings saved."
	return true

func save_csv() -> bool:
	if csv_text.text.is_empty(): return true
	var target: String = workspace.resolve_content_path(csv_path.text.strip_edges())
	if target.is_empty() or target.get_extension() != "csv": message.text = "Choose a content res:// CSV path."; return false
	var checked := Project.Csv.parse(csv_text.text)
	if checked.has("error"): message.text = checked.error; return false
	if csv_document == null: csv_document = Project.Csv.new()
	csv_document.set_content(csv_text.text)
	if csv_document.save_file(target) != OK: message.text = csv_document.last_error; return false
	initial_csv = csv_text.text; refresh_browser(); saved.emit(); message.text = "CSV saved. Collect translations to update native .translation files."
	return true

func save_all() -> bool:
	if csv_text.text != initial_csv and not save_csv(): return false
	if settings_fields() != initial_settings and not save_settings(): return false
	return true

func update_csv() -> void:
	if not save_all(): return
	var result: Dictionary = project.update_csv()
	if result.has("error"): message.text = result.error; return
	saved.emit(); refresh_browser()
	if browser.item_count: open_csv(browser.get_item_metadata(0))
	message.text = "CSV files and stable native IDs updated. " + str(result.written) + " files written."
	if not result.get("warnings", []).is_empty(): message.text += " Preserved " + str(result.warnings.size()) + " rows without current source; review before deleting them."

func collect() -> void:
	if not save_all(): return
	var result: Dictionary = project.collect_translations()
	if result.has("error"): message.text = result.error; return
	saved.emit(); message.text = "Native .translation resources and project registration saved. Preview can now use the CSV languages."

func add_language() -> void:
	var locale := new_locale.text.strip_edges()
	if not Project.Config.locale_valid(locale): message.text = "Enter a valid locale, such as ja or zh_CN."; return
	var table := Project.Csv.parse(csv_text.text)
	if table.has("error"): message.text = table.error; return
	for existing: String in table.locales:
		if TranslationServer.standardize_locale(existing) == TranslationServer.standardize_locale(locale): message.text = "This locale already exists."; return
	table.locales.append(locale)
	for key: String in table.rows: table.rows[key].append("")
	csv_text.text = Project.Csv.serialize(table); message.text = "Language column added. Enter translations and Save CSV."

func choose_file(action: String) -> void:
	if not save_all(): return
	dialog_action = action
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action == "import" else FileDialog.FILE_MODE_SAVE_FILE
	dialog.current_dir = workspace.root_path
	dialog.popup_centered_ratio(0.7)

func file_selected(path: String) -> void:
	if dialog_action == "export":
		if csv_document == null: message.text = "Open or generate a CSV first."; return
		if FileAccess.file_exists(path): message.text = "Export will not overwrite an existing file. Choose a new name."; return
		var copy := Project.Csv.new(); copy.set_content(csv_text.text)
		if copy.save_file(path) != OK: message.text = copy.last_error; return
		message.text = "CSV exported to " + path
	else:
		var destination: String = workspace.resolve_content_path(csv_path.text.strip_edges())
		if destination.is_empty(): message.text = "Choose or enter the destination CSV path in the content root first."; return
		var result: Dictionary = project.import_csv(path, destination)
		if result.has("error"): message.text = result.error; return
		open_csv(destination); refresh_browser(); saved.emit(); message.text = "CSV imported by key and locale. Other rows and languages were retained."
