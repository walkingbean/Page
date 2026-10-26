extends Control

const Document = preload("res://application/timeline_document.gd")
const CharacterDocumentType = preload("res://application/character_document.gd")
const VariableDocumentType = preload("res://application/variable_document.gd")
const VariableEditor = preload("res://ui/components/variable_editor.gd")
const ContentWorkspaceType = preload("res://application/content_workspace.gd")
const CharacterEditor = preload("res://ui/components/character_editor.gd")
const Preview = preload("res://preview/timeline_preview.gd")
const Identity = preload("res://application/app_identity.gd")

@onready var editor: Control = $MainLayout/PageContent/TimelineEditor
@onready var sidebar: Control = $MainLayout/ResourceSidebar
@onready var tabs: HBoxContainer = $MainLayout/PageContent/TopNavigation/Margin/Tabs

var document := Document.new()
var character_document := CharacterDocumentType.new()
var variable_document := VariableDocumentType.new()
var workspace: RefCounted = null
var has_document := false
var has_character := false
var active_mode := "timeline"
var styles_editor: Window
var settings_editor: Window
var character_editor: Control
var variable_editor: Control
var create_variables_dialog: ConfirmationDialog
var _pending_save_mode := ""
var _variable_selected: Variant = ""
var _variable_new_item := false
var _variable_initial_fields: Dictionary = {}
var _variable_form_dirty := false
var _variable_form_error := ""
var content_label: Label
var preview_window: Window
var open_dialog: FileDialog
var save_dialog: FileDialog
var workspace_dialog: FileDialog
var portrait_dialog: FileDialog
var unsaved_dialog: ConfirmationDialog
var error_dialog: AcceptDialog
var validation_timer: Timer
var pending_action := Callable()
var pending_workspace_action := Callable()
var _character_fields: Dictionary = {}
var _character_identifier_dirty := false
var _character_original_identifier := "character"
var _character_form_error := ""


func _ready() -> void:
	# Preserve the supplied theme's primary typeface while making content names
	# and configurable branding readable in languages covered by the bundled font.
	var interface_font := FontVariation.new()
	interface_font.base_font = ThemeDB.fallback_font
	interface_font.fallbacks = [preload("res://asset/fonts/NotoSansCJKsc-Regular.otf")]
	theme = theme.duplicate()
	theme.default_font = interface_font
	get_tree().auto_accept_quit = false
	get_window().title = Identity.window_title()
	tabs.get_node("Home").icon = Identity.app_icon_texture()
	editor.new_requested.connect(_request_new)
	editor.open_requested.connect(_request_open)
	editor.save_requested.connect(_save_document)
	editor.save_as_requested.connect(_save_as)
	editor.preview_requested.connect(_start_preview)
	editor.stop_requested.connect(_stop_preview)
	editor.content_changed.connect(_on_content_changed)
	sidebar.new_requested.connect(func(): _request_transition(_new_document))
	sidebar.new_character_requested.connect(_request_new_character)
	sidebar.open_requested.connect(_request_open)
	sidebar.document_activated.connect(_focus_active_editor)
	sidebar.resource_selected.connect(_request_resource)
	tabs.get_node("PlayTimeline").pressed.connect(_start_preview)
	tabs.get_node("Timeline").pressed.connect(func(): _request_switch_mode("timeline"))
	var character_tab: Button = tabs.get_node("Character")
	character_tab.disabled = false
	character_tab.add_theme_stylebox_override("normal", tabs.get_node("Timeline").get_theme_stylebox("normal"))
	character_tab.tooltip_text = "Edit native Dialogic characters"
	character_tab.pressed.connect(func(): _request_switch_mode("character"))
	var variable_tab: Button = tabs.get_node("Variables")
	variable_tab.disabled = false
	variable_tab.add_theme_stylebox_override("normal", tabs.get_node("Timeline").get_theme_stylebox("normal"))
	variable_tab.tooltip_text = "Edit native variable defaults"
	variable_tab.pressed.connect(func(): _request_switch_mode("variables"))
	styles_editor = preload("res://ui/components/style_editor.gd").new()
	styles_editor.name = "StyleEditor"
	add_child(styles_editor)
	styles_editor.saved.connect(func(): _refresh_workspace())
	settings_editor = preload("res://ui/components/text_settings_editor.gd").new()
	settings_editor.name = "TextSettingsEditor"
	add_child(settings_editor)
	settings_editor.saved.connect(func(): _refresh_workspace())
	for item: String in ["Layouts", "Settings"]:
		var button: Button = tabs.get_node(item)
		button.disabled = false
		button.add_theme_stylebox_override("normal", tabs.get_node("Timeline").get_theme_stylebox("normal"))
		button.pressed.connect(func(): _request_transition(func(): _with_workspace(func():
			if item == "Layouts": styles_editor.open_styles(workspace)
			else: settings_editor.open_settings(workspace))))
	_build_content_bar()
	character_editor = CharacterEditor.new()
	character_editor.name = "CharacterEditor"
	$MainLayout/PageContent.add_child(character_editor)
	character_editor.hide()
	character_editor.new_requested.connect(_request_new_character)
	character_editor.open_requested.connect(_request_open)
	character_editor.save_requested.connect(_save_document)
	character_editor.save_as_requested.connect(_save_as)
	character_editor.portrait_requested.connect(_request_portrait)
	character_editor.fields_changed.connect(_on_character_fields_changed)
	character_editor.portrait_selected.connect(_update_portrait_preview)
	var layer_editor := preload("res://ui/components/layered_portrait_editor.gd").new()
	layer_editor.name = "LayeredPortraitEditor"
	add_child(layer_editor)
	character_editor.layered_requested.connect(func(path: String): layer_editor.open_scene(workspace, path))
	layer_editor.saved.connect(func(path: String): character_editor.use_layered_scene(path))
	variable_editor = VariableEditor.new()
	variable_editor.name = "VariableEditor"
	$MainLayout/PageContent.add_child(variable_editor)
	variable_editor.hide()
	variable_editor.new_requested.connect(_request_new_variable)
	variable_editor.choose_folder_requested.connect(func(): _request_transition(_choose_workspace))
	variable_editor.save_requested.connect(_save_variables)
	variable_editor.apply_requested.connect(func(): _apply_variable_form())
	variable_editor.delete_requested.connect(_delete_variable)
	variable_editor.selection_requested.connect(_request_variable_selection)
	variable_editor.fields_changed.connect(_on_variable_fields_changed)
	_show_variables()
	_create_dialogs()
	validation_timer = Timer.new()
	validation_timer.one_shot = true
	validation_timer.wait_time = 0.25
	validation_timer.timeout.connect(_refresh_chrome)
	add_child(validation_timer)
	preview_window = Preview.new()
	preview_window.preview_closed.connect(_on_preview_closed)
	add_child(preview_window)
	tabs.get_node("PlayTimeline").disabled = true
	_refresh_workspace_chrome()
	if not Identity.last_error().is_empty():
		_show_error(Identity.last_error())
	# Resolve the content root first, regardless of command-line argument order.
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == "--content-root":
			_open_workspace(arguments[index + 1])
			break
	for argument: String in arguments:
		if argument.to_lower().ends_with(".dtl") or argument.to_lower().ends_with(".dch"):
			_open_selected(argument)
			break


func _build_content_bar() -> void:
	var row := HBoxContainer.new()
	row.name = "ContentBar"
	row.add_theme_constant_override("separation", 8)
	$MainLayout/PageContent.add_child(row)
	$MainLayout/PageContent.move_child(row, 1)
	var choose := Button.new()
	choose.name = "ContentFolder"
	choose.text = "Content Folder"
	choose.tooltip_text = "Choose the root containing timelines, characters and portraits."
	choose.pressed.connect(func(): _request_transition(_choose_workspace))
	row.add_child(choose)
	content_label = Label.new()
	content_label.name = "ContentRoot"
	content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content_label.custom_minimum_size.x = 80
	content_label.add_theme_font_size_override("font_size", 12)
	row.add_child(content_label)
	var refresh := Button.new()
	refresh.name = "Refresh"
	refresh.text = "Refresh"
	refresh.tooltip_text = "Rescan the content folder and validate character references."
	refresh.pressed.connect(_refresh_workspace)
	row.add_child(refresh)


func _create_dialogs() -> void:
	open_dialog = _file_dialog("Open Dialogic Content", FileDialog.FILE_MODE_OPEN_FILE)
	open_dialog.file_selected.connect(_open_selected)
	save_dialog = _file_dialog("Save As", FileDialog.FILE_MODE_SAVE_FILE)
	save_dialog.file_selected.connect(_save_selected)
	save_dialog.canceled.connect(func(): pending_action = Callable())
	workspace_dialog = _file_dialog("Choose Content Folder", FileDialog.FILE_MODE_OPEN_DIR)
	workspace_dialog.dir_selected.connect(_open_workspace)
	workspace_dialog.canceled.connect(func(): pending_workspace_action = Callable())
	portrait_dialog = _file_dialog("Choose Static PNG Portrait", FileDialog.FILE_MODE_OPEN_FILE)
	portrait_dialog.filters = PackedStringArray(["*.png ; PNG portrait"])
	portrait_dialog.file_selected.connect(_portrait_selected)
	unsaved_dialog = ConfirmationDialog.new()
	unsaved_dialog.title = "Unsaved Changes"
	unsaved_dialog.dialog_text = "Save your changes before continuing?"
	unsaved_dialog.ok_button_text = "Save"
	unsaved_dialog.add_button("Discard", false, "discard")
	unsaved_dialog.confirmed.connect(_save_pending_document)
	unsaved_dialog.custom_action.connect(_on_unsaved_action)
	unsaved_dialog.canceled.connect(_cancel_pending_action)
	add_child(unsaved_dialog)
	create_variables_dialog = ConfirmationDialog.new()
	create_variables_dialog.name = "CreateVariableConfig"
	create_variables_dialog.title = "Create Variable Configuration"
	create_variables_dialog.ok_button_text = "Create and Save"
	create_variables_dialog.confirmed.connect(func(): _save_variables(true))
	create_variables_dialog.canceled.connect(_cancel_pending_action)
	add_child(create_variables_dialog)
	error_dialog = AcceptDialog.new()
	error_dialog.title = Identity.project_name()
	add_child(error_dialog)


func _file_dialog(caption: String, mode: FileDialog.FileMode) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = caption
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	add_child(dialog)
	return dialog


func _request_transition(action: Callable) -> void:
	_sync_document_from_editor()
	if _active_dirty():
		pending_action = action
		_pending_save_mode = active_mode
		unsaved_dialog.dialog_text = "Save your changes before continuing?"
		unsaved_dialog.popup_centered(Vector2i(420, 150))
	else:
		action.call()


func _active_dirty() -> bool:
	if active_mode == "variables":
		return _variables_dirty()
	if active_mode == "character":
		return has_character and (character_document.dirty or _character_identifier_dirty or not _character_form_error.is_empty())
	return has_document and document.dirty


func _request_switch_mode(mode: String) -> void:
	if mode == active_mode:
		_focus_active_editor()
		return
	_request_transition(func(): _activate_mode(mode))


func _activate_mode(mode: String) -> void:
	_stop_preview()
	active_mode = mode
	editor.visible = mode == "timeline"
	character_editor.visible = mode == "character"
	variable_editor.visible = mode == "variables"
	tabs.get_node("Variables").flat = mode != "variables"
	tabs.get_node("Variables").modulate = Color.WHITE if mode == "variables" else Color(0.75, 0.75, 0.75)
	tabs.get_node("Timeline").flat = mode != "timeline"
	tabs.get_node("Character").flat = mode != "character"
	tabs.get_node("Timeline").modulate = Color.WHITE if mode == "timeline" else Color(0.75, 0.75, 0.75)
	tabs.get_node("Character").modulate = Color.WHITE if mode == "character" else Color(0.75, 0.75, 0.75)
	_refresh_chrome()
	_focus_active_editor()


func _focus_active_editor() -> void:
	if active_mode == "timeline":
		editor.focus_editor()
	elif active_mode == "variables":
		variable_editor.focus_editor()
	elif has_character:
		character_editor.display_name_field.grab_focus()


func _request_new() -> void:
	if active_mode == "variables":
		_request_new_variable()
	elif active_mode == "character":
		_request_new_character()
	else:
		_request_transition(_new_document)


func _new_document() -> void:
	_stop_preview()
	document.new_document()
	document.workspace = workspace
	has_document = true
	_activate_mode("timeline")
	_show_document()
	editor.focus_editor()


func _request_new_character() -> void:
	_request_transition(func(): _with_workspace(_new_character))


func _new_character() -> void:
	if workspace == null:
		_with_workspace(_new_character)
		return
	character_document.new_document()
	character_document.workspace = workspace
	has_character = true
	_character_identifier_dirty = false
	_activate_mode("character")
	_show_character()
	character_editor.identifier_field.grab_focus()
	character_editor.identifier_field.select_all()


func _request_open() -> void:
	_request_transition(_choose_workspace if active_mode == "variables" else _show_open_dialog)


func _show_open_dialog() -> void:
	open_dialog.filters = PackedStringArray(["*.dch ; Dialogic Character"]) if active_mode == "character" else PackedStringArray(["*.dtl ; Dialogic Timeline", "*.dch ; Dialogic Character"])
	if workspace != null:
		open_dialog.current_dir = workspace.root_path
	open_dialog.popup_centered_ratio(0.75)


func _request_resource(path: String, kind: String) -> void:
	if path.is_empty():
		_request_switch_mode(kind)
		return
	_request_transition(func(): _open_selected(path))


func _open_selected(path: String) -> void:
	if path.get_extension().to_lower() == "dch":
		_with_workspace(func(): _open_character(path))
		return
	_stop_preview()
	document.workspace = workspace
	var result: Error = document.open_file(path)
	if result != OK:
		_show_error(document.last_error)
		return
	has_document = true
	_activate_mode("timeline")
	_show_document()
	editor.focus_editor()


func _open_character(path: String) -> void:
	if workspace.content_path(path).is_empty():
		_show_error("Choose the content folder containing this character before opening it.")
		return
	var result: Error = character_document.open_file(path, workspace)
	if result != OK:
		_show_error(character_document.last_error)
		return
	has_character = true
	_character_identifier_dirty = false
	_activate_mode("character")
	_show_character()


func _save_document() -> void:
	if active_mode == "variables":
		_save_variables()
		return
	_sync_document_from_editor()
	if not _can_save_character_form():
		return
	var active: RefCounted = character_document if active_mode == "character" else document
	if not (has_character if active_mode == "character" else has_document):
		return
	if active.path.is_empty():
		_save_as()
		return
	_save_selected(active.path)


func _save_as() -> void:
	if active_mode == "variables":
		_save_variables()
		return
	_sync_document_from_editor()
	if not _can_save_character_form():
		return
	var is_character := active_mode == "character"
	if not (has_character if is_character else has_document):
		return
	var active: RefCounted = character_document if is_character else document
	if active.read_only:
		_show_error("This file uses features outside the supported scope and remains read-only.")
		pending_action = Callable()
		return
	save_dialog.title = "Save Character As" if is_character else "Save Timeline As"
	save_dialog.filters = PackedStringArray(["*.dch ; Dialogic Character"]) if is_character else PackedStringArray(["*.dtl ; Dialogic Timeline"])
	if not active.path.is_empty():
		save_dialog.current_dir = active.path.get_base_dir()
	elif workspace != null:
		save_dialog.current_dir = workspace.root_path
	var filename: String = active.path.get_file()
	if filename.is_empty():
		filename = character_editor.get_fields().get("identifier", "character") + ".dch" if is_character else "timeline.dtl"
	save_dialog.current_file = filename
	save_dialog.popup_centered_ratio(0.75)


func _save_selected(path: String) -> void:
	_sync_document_from_editor()
	if not _can_save_character_form():
		return
	var is_character := active_mode == "character"
	var active: RefCounted = character_document if is_character else document
	# Dependencies can change outside this application after the last scan.
	# Validate the synchronized buffer against fresh resources before any write.
	if workspace != null:
		var refresh_result: Error = workspace.refresh()
		_refresh_workspace_chrome()
		if refresh_result != OK:
			pending_action = Callable()
			_show_error("Could not refresh the content folder before saving. " + workspace.last_error)
			return
	if is_character:
		if workspace == null or workspace.content_path(path).is_empty():
			pending_action = Callable()
			_show_error("Save characters inside the selected content folder so their references remain portable.")
			return
		var identifier := path.get_file().get_basename()
		if not ContentWorkspaceType.valid_identifier(identifier):
			pending_action = Callable()
			_show_error("Choose a character filename without control characters, quotes, path separators or Dialogic syntax punctuation. The identifiers _ and --All-- are reserved.")
			return
		for existing: String in workspace.characters:
			var entry: Dictionary = workspace.characters[existing]
			if existing.to_lower() == identifier.to_lower() and str(entry.get("path", "")) != path:
				pending_action = Callable()
				_show_error("A character with this identifier already exists in the content folder: " + existing)
				return
	var result: Error = active.save_file(path)
	if result != OK:
		pending_action = Callable()
		_show_error(active.last_error)
		_refresh_chrome()
		return
	if is_character:
		_character_identifier_dirty = false
		character_editor.set_identifier(active.path.get_file().get_basename())
		_character_original_identifier = active.path.get_file().get_basename()
		_character_fields = character_editor.get_fields().duplicate(true)
	_refresh_workspace(false)
	_refresh_chrome("Saved: " + active.path)
	_finish_pending_action()


func _on_unsaved_action(action: StringName) -> void:
	if action != &"discard":
		return
	unsaved_dialog.hide()
	if not pending_action.is_valid():
		return
	var next := pending_action
	pending_action = Callable()
	# Inactive sessions stay available after a tab switch. Discard must really
	# restore the saved session, not leave hidden dirty content behind.
	var discard_variables: bool = _pending_save_mode == "variables"
	_pending_save_mode = ""
	if not (_discard_variable_changes() if discard_variables else _discard_active_changes()):
		return
	next.call()


func _discard_active_changes() -> bool:
	if active_mode == "variables":
		return _discard_variable_changes()
	var active: RefCounted = character_document if active_mode == "character" else document
	if active.path.is_empty():
		active.new_document()
	else:
		var result: Error = active.open_file(active.path, workspace) if active_mode == "character" else active.open_file(active.path)
		if result != OK:
			_show_error("Could not restore the saved document. Your edited buffer is still open. " + active.last_error)
			return false
	if active_mode == "character":
		_character_identifier_dirty = false
		_show_character()
	else:
		_show_document()
	return true


func _sync_document_from_editor() -> void:
	# Save and transitions consume controls directly, before deferred change signals.
	if active_mode == "variables":
		_on_variable_fields_changed()
	elif active_mode == "character":
		if has_character and not character_document.read_only:
			_on_character_fields_changed(character_editor.get_fields())
	elif has_document and not document.read_only:
		var text: String = editor.current_text()
		if text != document.content:
			_on_content_changed(text)


func _on_content_changed(text: String) -> void:
	if active_mode != "timeline" or not has_document or text == document.content:
		return
	document.set_content(text, false)
	editor.set_preview_available(false)
	editor.set_diagnostics([])
	tabs.get_node("PlayTimeline").disabled = true
	validation_timer.start()


func _on_character_fields_changed(fields: Dictionary) -> void:
	if not has_character or character_document.read_only or fields == _character_fields:
		return
	if character_document.path.is_empty():
		_character_identifier_dirty = fields.get("identifier", "") != _character_original_identifier
	if not fields.get("form_error", "").is_empty():
		_character_fields = fields.duplicate(true)
		_character_form_error = fields.form_error
		_refresh_chrome(_character_form_error)
		return
	var result: Error = character_document.update_fields(fields.get("display_name", ""), fields.get("color", Color.WHITE), fields.get("portrait_path", ""), fields)
	_character_fields = fields.duplicate(true)
	_character_form_error = character_document.last_error if result != OK else ""
	_refresh_chrome(_character_form_error)


func _can_save_character_form() -> bool:
	if active_mode == "character" and not _character_form_error.is_empty():
		pending_action = Callable()
		_show_error("Correct the character fields before saving. " + _character_form_error)
		return false
	return true


func _document_title() -> String:
	var title: String = document.path.get_file() if not document.path.is_empty() else "Untitled.dtl"
	return title + (" *" if document.dirty else "")


func _character_title() -> String:
	var title: String = character_document.path.get_file() if not character_document.path.is_empty() else "Untitled.dch"
	return title + (" *" if character_document.dirty or _character_identifier_dirty or not _character_form_error.is_empty() else "")


func _show_document() -> void:
	editor.show_document(_document_title(), document.content, document.read_only, "")
	_refresh_chrome()


func _show_character() -> void:
	_character_form_error = ""
	var identifier: String = character_document.path.get_file().get_basename() if not character_document.path.is_empty() else "character"
	_character_original_identifier = identifier
	character_editor.show_document(_character_title(), identifier, character_document.character, character_document.read_only, "", character_document.path.is_empty())
	_character_fields = character_editor.get_fields().duplicate(true)
	_update_portrait_preview(str(_character_fields.get("portrait_path", "")))
	_refresh_chrome()


func _refresh_chrome(message: String = "", validation: Dictionary = {}) -> void:
	if is_instance_valid(validation_timer):
		validation_timer.stop()
	if active_mode == "variables":
		if message.is_empty():
			message = _variable_status()
		variable_editor.set_document_state("Variables" + (" *" if _variables_dirty() else ""), variable_document.file_path, message, variable_document.read_only)
		sidebar.set_document("", "", false, "variables")
		tabs.get_node("PlayTimeline").disabled = not has_document
		get_window().title = Identity.window_title("Variables" + (" *" if _variables_dirty() else ""))
		return
	if active_mode == "character":
		tabs.get_node("PlayTimeline").disabled = true
		if has_character:
			if message.is_empty() and not _character_form_error.is_empty():
				message = "Cannot save: " + _character_form_error
			if message.is_empty():
				message = "Read-only: " + " ".join(character_document.diagnostics) if character_document.read_only else "Native .dch · Characters and portraits · " + ("Unsaved" if _active_dirty() else "Ready")
			character_editor.set_document_state(_character_title(), character_document.read_only, message)
			sidebar.set_document(character_document.path, character_document.path.get_file() if not character_document.path.is_empty() else "Untitled.dch", _active_dirty(), "character")
			get_window().title = Identity.window_title(_character_title())
		else:
			sidebar.set_document("", "", false, "character")
			get_window().title = Identity.window_title()
		return
	if not has_document:
		sidebar.set_document("", "", false, "timeline")
		tabs.get_node("PlayTimeline").disabled = true
		get_window().title = Identity.window_title()
		return
	if validation.is_empty():
		validation = document.validate_content(document.content)
	var diagnostics: Array = validation.get("diagnostics", [])
	if message.is_empty():
		if not diagnostics.is_empty():
			message = "Read-only: " if document.read_only else "Cannot save or preview: "
			message += str(diagnostics[0])
		else:
			var counts: Dictionary = validation.get("document_counts", validation)
			message = "%d text · %d comment(s) · %d character event(s) | %s" % [counts.get("event_count", 0), counts.get("comment_count", 0), counts.get("character_event_count", 0), "Unsaved" if document.dirty else "Ready"]
	editor.set_document_state(_document_title(), document.read_only, message)
	editor.set_diagnostics(validation.get("issues", []))
	sidebar.set_document(document.path, document.path.get_file() if not document.path.is_empty() else "Untitled.dtl", document.dirty, "timeline")
	var available := not document.read_only and bool(validation.get("supported", false)) and int(validation.get("event_count", 0)) > 0
	editor.set_preview_available(available)
	tabs.get_node("PlayTimeline").disabled = not available
	get_window().title = Identity.window_title(_document_title())


func _choose_workspace() -> void:
	if workspace != null:
		workspace_dialog.current_dir = workspace.root_path
	workspace_dialog.popup_centered_ratio(0.75)


func _with_workspace(action: Callable) -> void:
	if workspace != null:
		action.call()
	else:
		pending_workspace_action = action
		_choose_workspace()


func _open_workspace(path: String) -> void:
	var candidate := ContentWorkspaceType.new()
	var result: Error = candidate.open_root(path)
	if result != OK:
		pending_workspace_action = Callable()
		_show_error(candidate.last_error)
		return
	var candidate_variables := VariableDocumentType.new()
	result = candidate_variables.open_root(candidate.root_path)
	if result != OK:
		pending_workspace_action = Callable()
		_show_error(candidate_variables.last_error)
		return
	candidate.variable_document = candidate_variables
	_stop_preview()
	var changed: bool = workspace != null and workspace.root_path != candidate.root_path
	workspace = candidate
	variable_document = candidate_variables
	_show_variables()
	document.workspace = workspace
	character_document.workspace = workspace
	# A character form belongs to its original content root; do not reinterpret
	# its portrait paths in a different folder. Timeline buffers stay inspectable.
	if changed:
		has_character = false
		character_document.new_document()
		_character_fields.clear()
		_character_form_error = ""
		_character_identifier_dirty = false
		character_editor.show_document("Characters", "", null)
	_refresh_workspace_chrome()
	_revalidate_timeline_context()
	_refresh_chrome()
	if pending_workspace_action.is_valid():
		var action := pending_workspace_action
		pending_workspace_action = Callable()
		action.call()


func _refresh_workspace(show_errors: bool = true, reload_variables: bool = true) -> void:
	_sync_document_from_editor()
	if workspace != null:
		var result: Error = workspace.refresh()
		if result != OK and show_errors:
			_show_error(workspace.last_error)
		if reload_variables:
			_refresh_variables(show_errors)
	_refresh_workspace_chrome()
	_revalidate_timeline_context()
	_refresh_chrome()


func _refresh_workspace_chrome() -> void:
	var style_names: Array[String] = []
	if workspace != null and workspace.style_catalog != null:
		for value: String in workspace.style_catalog.styles:
			if not value.is_empty() and not value.begins_with("res://"): style_names.append(value)
	character_editor.set_styles(style_names)
	var ids: Array[String] = []
	if workspace == null:
		content_label.text = "No content folder · Narration files can still open"
		content_label.tooltip_text = "Choose a content folder to work with characters and portraits."
		sidebar.set_workspace("", {}, [])
	else:
		var issues: Array = workspace.diagnostics
		content_label.text = workspace.root_path + (" · %d issue(s)" % issues.size() if not issues.is_empty() else "")
		content_label.tooltip_text = workspace.root_path + ("\n" + "\n".join(issues) if not issues.is_empty() else "")
		sidebar.set_workspace(workspace.root_path, workspace.characters, workspace.timelines)
		for identifier: String in workspace.characters:
			if workspace.has_character(identifier) and workspace.get_character_error(identifier).is_empty():
				ids.append(identifier)
	ids.sort()
	editor.set_characters(ids)
	editor.content_workspace = workspace


func _revalidate_timeline_context() -> void:
	if has_document and not document.dirty:
		var validation: Dictionary = document.validate_content(document.content)
		document.read_only = not validation.get("supported", false)
		document.diagnostics.assign(validation.get("diagnostics", []))


func _request_portrait() -> void:
	if has_character and not character_document.read_only:
		portrait_dialog.popup_centered_ratio(0.75)


func _portrait_selected(path: String) -> void:
	if workspace == null or not has_character or character_document.read_only:
		return
	var logical: String = workspace.import_portrait(path)
	if logical.is_empty():
		_show_error(workspace.last_error)
		return
	_update_portrait_preview(logical)
	_on_character_fields_changed(character_editor.get_fields())


func _update_portrait_preview(logical: String) -> void:
	var texture: Texture2D = null
	if workspace != null and not logical.is_empty():
		var absolute: String = workspace.resolve_content_path(logical)
		if not absolute.is_empty():
			var image := Image.load_from_file(absolute)
			if image != null and not image.is_empty():
				texture = ImageTexture.create_from_image(image)
	character_editor.set_portrait_preview(texture, logical)


func _start_preview() -> void:
	_sync_document_from_editor()
	if active_mode == "character" or not has_document:
		return
	if _variables_dirty():
		_pending_save_mode = "variables"
		pending_action = _begin_timeline_preview
		unsaved_dialog.dialog_text = "Save variable defaults before preview? The timeline buffer will not be saved automatically."
		unsaved_dialog.popup_centered(Vector2i(480, 170))
		return
	_begin_timeline_preview()


func _begin_timeline_preview() -> void:
	if workspace != null:
		var variable_error: String = variable_document.preview_error()
		if not variable_error.is_empty():
			_show_error(variable_error + " Use Refresh to reload saved defaults; unsaved changes are preserved.")
			return
	if active_mode != "timeline":
		_activate_mode("timeline")
	_refresh_workspace(false, false)
	var validation: Dictionary = document.validate_content(document.content)
	_refresh_chrome("", validation)
	if document.read_only or not bool(validation.get("supported", false)):
		_show_error("Preview requires supported content. " + " ".join(validation.get("diagnostics", [])))
		return
	if int(validation.get("event_count", 0)) == 0:
		_show_error("Add a text line before starting preview.")
		return
	var result: Error = await preview_window.start_preview(document.content, workspace, document.path)
	if result != OK:
		_show_error("Dialogic preview could not start (error %d)." % result)
		return
	editor.set_preview_state(true)
	character_editor.set_enabled(false)
	variable_editor.set_enabled(false)


func _stop_preview() -> void:
	if is_instance_valid(preview_window):
		preview_window.stop_preview()


func _on_preview_closed() -> void:
	editor.set_preview_state(false)
	character_editor.set_enabled(true)
	variable_editor.set_enabled(true)
	_focus_active_editor()


func _show_error(message: String) -> void:
	error_dialog.dialog_text = message
	error_dialog.popup_centered(Vector2i(540, 160))
	if active_mode == "timeline":
		editor.set_status(message)
	elif active_mode == "variables":
		variable_editor.set_document_state("Variables" + (" *" if _variables_dirty() else ""), variable_document.file_path, message, variable_document.read_only)
	elif has_character:
		character_editor.set_document_state(_character_title(), character_document.read_only, message)


func _shortcut_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	# No main-window shortcut may consume input belonging to a modal workflow.
	for dialog: Window in [open_dialog, save_dialog, workspace_dialog, portrait_dialog, unsaved_dialog, create_variables_dialog, error_dialog, preview_window]:
		if is_instance_valid(dialog) and dialog.visible:
			return
	var handled := true
	if event.is_command_or_control_pressed():
		match event.keycode:
			KEY_N: _request_new()
			KEY_O: _request_open()
			KEY_F:
				if active_mode == "timeline": editor.show_find()
				else: handled = false
			KEY_S:
				if event.shift_pressed: _save_as()
				else: _save_document()
			_: handled = false
	else:
		match event.keycode:
			KEY_F3:
				if active_mode == "timeline": editor.find_next(event.shift_pressed)
				else: handled = false
			KEY_ESCAPE:
				if active_mode == "timeline" and editor.find_bar.visible: editor.close_find()
				else: handled = false
			KEY_F5: _start_preview()
			KEY_F6: _stop_preview()
			_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready():
		_request_transition(func(): get_tree().quit())


func _variables_dirty() -> bool:
	return not variable_document.root_path.is_empty() and (variable_document.dirty or _variable_form_dirty)


func _variable_status() -> String:
	if workspace == null:
		return "Choose a content folder to edit variables. Narration files can still be edited without one."
	if not _variable_form_error.is_empty():
		return "Correct the variable fields: " + _variable_form_error
	if variable_document.read_only:
		return "Read-only: " + " ".join(variable_document.diagnostics)
	if not variable_document.override_warning.is_empty():
		return variable_document.override_warning
	var message := "Native variable defaults · " + ("Unsaved" if _variables_dirty() else "Ready")
	if not FileAccess.file_exists(variable_document.file_path):
		message += " · First Save creates project.godot in the selected content folder."
	return message


func _show_variables(selected_name: Variant = "") -> void:
	_variable_selected = selected_name
	if not variable_document.values.has(_variable_selected):
		_variable_selected = ""
	_variable_new_item = false
	_variable_form_dirty = false
	_variable_form_error = ""
	variable_editor.show_document(variable_document.values, _variable_selected, not variable_document.root_path.is_empty(), variable_document.read_only)
	_variable_initial_fields = variable_editor.get_fields().duplicate(true)


func _request_new_variable() -> void:
	if workspace == null:
		_with_workspace(_new_variable)
		return
	if active_mode != "variables":
		_request_transition(_new_variable)
		return
	if _apply_variable_form():
		_new_variable()


func _new_variable() -> void:
	if workspace == null or variable_document.read_only:
		return
	_activate_mode("variables")
	_variable_selected = ""
	_variable_new_item = true
	variable_editor.show_selection("", true)
	_variable_initial_fields = variable_editor.get_fields().duplicate(true)
	_variable_form_dirty = true
	_variable_form_error = "Enter a name for the new variable."
	_refresh_chrome()
	variable_editor.name_field.grab_focus()


func _request_variable_selection(variable_name: Variant) -> void:
	if variable_name == _variable_selected and not _variable_new_item:
		return
	if not _apply_variable_form():
		variable_editor.select_list_item(_variable_selected)
		return
	_show_variables(variable_name)
	_refresh_chrome()


func _on_variable_fields_changed() -> void:
	if not is_instance_valid(variable_editor) or variable_document.read_only or variable_document.root_path.is_empty():
		return
	if not _variable_new_item and (not _variable_selected is String or not variable_document.is_editable(_variable_selected)):
		return
	var fields: Dictionary = variable_editor.get_fields()
	_variable_form_dirty = _variable_new_item or fields != _variable_initial_fields
	_variable_form_error = _variable_fields_error(fields) if _variable_form_dirty else ""
	if is_instance_valid(validation_timer):
		validation_timer.start()


func _variable_fields_error(fields: Dictionary) -> String:
	if not str(fields.get("error", "")).is_empty():
		return fields.error
	var variable_name: String = fields.get("name", "")
	if not VariableDocumentType.valid_identifier(variable_name):
		return "Use a nonempty ASCII identifier: letters, digits and underscores; do not start with a digit."
	if variable_document.values.has(variable_name) and (_variable_new_item or variable_name != _variable_selected):
		return "A variable or read-only item with this exact name already exists. Names are case-sensitive."
	return ""


func _apply_variable_form() -> bool:
	_on_variable_fields_changed()
	if not _variable_form_dirty:
		return true
	if not _variable_form_error.is_empty():
		_show_error(_variable_form_error)
		return false
	var fields: Dictionary = variable_editor.get_fields()
	var new_name: String = fields.get("name", "")
	var result: Error = variable_document.update_variable("" if _variable_new_item else _variable_selected, new_name, fields.get("parsed_value"))
	if result != OK:
		_variable_form_error = variable_document.last_error
		_show_error(_variable_form_error)
		return false
	_show_variables(new_name)
	_refresh_chrome()
	return true


func _delete_variable() -> void:
	if workspace == null or variable_document.read_only or not _variable_selected is String or _variable_selected.is_empty() or _variable_new_item:
		return
	var result: Error = variable_document.remove_variable(_variable_selected)
	if result != OK:
		_show_error(variable_document.last_error)
		return
	_show_variables()
	_refresh_chrome("Definition removed from the unsaved list. Existing timeline references have not been changed.")


func _save_variables(creation_confirmed: bool = false) -> void:
	if workspace == null:
		_cancel_pending_action()
		_show_error("Choose a content folder before saving variable defaults.")
		return
	if not _apply_variable_form():
		_cancel_pending_action()
		return
	if variable_document.read_only:
		_cancel_pending_action()
		_show_error("Variable configuration is read-only. " + " ".join(variable_document.diagnostics))
		return
	var result: Error = variable_document.check_current()
	if result != OK:
		_cancel_pending_action()
		_show_error(variable_document.last_error)
		return
	if not FileAccess.file_exists(variable_document.file_path) and not creation_confirmed:
		create_variables_dialog.dialog_text = "Save will create a native project.godot containing variable defaults in:\n" + workspace.root_path + "\nIt will not configure a game scene, plugins or autoloads."
		create_variables_dialog.popup_centered(Vector2i(560, 210))
		return
	result = variable_document.save()
	if result != OK:
		_cancel_pending_action()
		_show_error(variable_document.last_error)
		return
	_show_variables(_variable_selected)
	_revalidate_timeline_context()
	_refresh_chrome("Saved: " + variable_document.file_path)
	_finish_pending_action()


func _discard_variable_changes() -> bool:
	var result: Error = variable_document.discard_changes()
	if result != OK:
		_show_error("Could not reload saved variable defaults. Your draft is still available. " + variable_document.last_error)
		return false
	_show_variables(_variable_selected)
	_revalidate_timeline_context()
	_refresh_chrome()
	return true


func _refresh_variables(show_errors: bool) -> void:
	var result: Error
	if _variables_dirty():
		result = variable_document.check_current()
	else:
		result = variable_document.refresh()
		if result == OK:
			_show_variables(_variable_selected)
	if result != OK and show_errors:
		_show_error(variable_document.last_error)


func _save_pending_document() -> void:
	if _pending_save_mode == "variables":
		_save_variables()
	else:
		_save_document()


func _cancel_pending_action() -> void:
	pending_action = Callable()
	_pending_save_mode = ""


func _finish_pending_action() -> void:
	_pending_save_mode = ""
	if pending_action.is_valid():
		var action := pending_action
		pending_action = Callable()
		action.call()
