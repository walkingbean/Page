extends Window

signal saved
signal resource_renamed(source: String, destination: String)
const Project = preload("res://application/project_document.gd")
const Source = preload("res://application/project_source_document.gd")
const Index = preload("res://application/project_index.gd")
const Rename = preload("res://application/project_rename.gd")
const Extensions = preload("res://application/project_extensions.gd")
const Runtime = preload("res://application/project_runtime.gd")
const Identity = preload("res://application/app_identity.gd")
var workspace: RefCounted
var project: RefCounted
var document: RefCounted
var index: RefCounted
var runtime := Runtime.new()
var resource_list: ItemList
var setting_list: ItemList
var key_field: LineEdit
var value_field: TextEdit
var source_editor: CodeEdit
var source_find: LineEdit
var source_label: Label
var references: TextEdit
var reference_list: ItemList
var message: Label
var logs: TextEdit
var rename_path: LineEdit
var extension_name: LineEdit
var filter: LineEdit
var tabs: TabContainer
var confirm_rename: ConfirmationDialog
var transfer_dialog: FileDialog
var unsaved: ConfirmationDialog
var pending: Callable
var rename_plan := {}
var selected_resource := ""
var selected_setting := ""
var _setting_original_key := ""
var _setting_original_value := ""
var _updating := false
var _last_log_size := -1
var _last_run_state := ""

func _ready() -> void:
	hide()
	title = "Project & Extensions · " + Identity.project_name()
	min_size = Vector2i(840, 500); size = Vector2i(1120, 760)
	transient = true; exclusive = true
	var box := VBoxContainer.new(); box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(box)
	var tools := HFlowContainer.new(); box.add_child(tools)
	button(tools, "Refresh", func(): transition(refresh))
	button(tools, "Save all", save_all)
	button(tools, "Run project", func(): transition(func(): run_target("project", "")))
	button(tools, "Run selected", func(): transition(run_selected))
	button(tools, "Export native project", func(): transition(func(): transfer_dialog.popup_centered_ratio(0.75)))
	button(tools, "Stop", func(): runtime.stop(); show_message("Target process stopped. Log retained."))
	button(tools, "Project folder", func(): OS.shell_open(workspace.root_path) if workspace != null else OK)
	tabs = TabContainer.new(); tabs.name = "ProjectTabs"; tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL; box.add_child(tabs)
	var settings := HSplitContainer.new(); settings.name = "Settings"; tabs.add_child(settings)
	setting_list = ItemList.new(); setting_list.name = "ProjectSettings"; setting_list.custom_minimum_size.x = 340; settings.add_child(setting_list)
	setting_list.item_selected.connect(func(position: int):
		var next_key := setting_list.get_item_text(position)
		transition(func(): select_setting_key(next_key)))
	var fields := VBoxContainer.new(); fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL; settings.add_child(fields)
	key_field = line(fields, "Native section/key", "ProjectKey")
	value_field = TextEdit.new(); value_field.name = "ProjectValue"; value_field.size_flags_vertical = Control.SIZE_EXPAND_FILL; fields.add_child(value_field)
	key_field.text_changed.connect(func(_text: String): update_dirty())
	value_field.text_changed.connect(update_dirty)
	var edit_tools := HFlowContainer.new(); fields.add_child(edit_tools)
	button(edit_tools, "Apply value", apply_setting)
	button(edit_tools, "Remove key", remove_setting)
	button(edit_tools, "Autoload earlier", func(): move_autoload(-1))
	button(edit_tools, "Autoload later", func(): move_autoload(1))
	var hint := Label.new(); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; hint.text = 'Use native Variant values: "text", true, 1280, arrays or dictionaries. Autoload: key autoload/Host, value "*res://host.gd". Source constructors stay opaque here.'; fields.add_child(hint)
	var resources := HSplitContainer.new(); resources.name = "Resources"; tabs.add_child(resources)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 300; resources.add_child(left)
	filter = line(left, "Filter path", "ProjectFilter"); filter.text_changed.connect(func(_value: String): populate_resources())
	resource_list = ItemList.new(); resource_list.name = "ProjectResources"; resource_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; left.add_child(resource_list)
	resource_list.item_selected.connect(func(i: int):
		var path := str(resource_list.get_item_metadata(i))
		transition(func(): select_resource(path)))
	var right := VBoxContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; resources.add_child(right)
	references = TextEdit.new(); references.name = "ProjectReferences"; references.editable = false; references.size_flags_vertical = Control.SIZE_EXPAND_FILL; right.add_child(references)
	reference_list = ItemList.new(); reference_list.name = "ReferenceLocations"; reference_list.custom_minimum_size.y = 110; right.add_child(reference_list)
	reference_list.item_activated.connect(func(position: int):
		var location: Dictionary = reference_list.get_item_metadata(position)
		transition(func():
			selected_resource = location.source; open_selected()
			if document != null: source_editor.set_caret_line(maxi(0, location.line - 1))))
	rename_path = line(right, "Rename to res://…", "RenamePath")
	button(right, "Preview rename", preview_rename)
	button(right, "Edit selected source", func(): transition(open_selected))
	button(right, "Open selected editor", func(): transition(func(): run_target("editor", selected_resource)))
	var source := VBoxContainer.new(); source.name = "Source"; tabs.add_child(source)
	source_label = Label.new(); source_label.name = "SourcePath"; source_label.text = "Select a target text resource in Resources."; source.add_child(source_label)
	source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var search_tools := HBoxContainer.new(); source.add_child(search_tools)
	source_find = LineEdit.new(); source_find.name = "SourceFind"; source_find.placeholder_text = "Find in source"; source_find.size_flags_horizontal = Control.SIZE_EXPAND_FILL; search_tools.add_child(source_find)
	button(search_tools, "Previous match", func(): find_source(true))
	button(search_tools, "Next match", func(): find_source(false))
	source_find.text_submitted.connect(func(_text: String): find_source(false))
	source_editor = create_source_editor(); source.add_child(source_editor)
	button(source, "Save native source", save_source)
	var extensions := VBoxContainer.new(); extensions.name = "Extensions"; tabs.add_child(extensions)
	extension_name = line(extensions, "New example module name", "ExtensionName"); extension_name.text = "MyExtension"
	button(extensions, "Create native extension examples", func(): transition(create_examples))
	var explanation := Label.new(); explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; explanation.text = "Creates a native index, event, subsystem, editor, portrait, animation and layout layer. Edit these files in Source. In Resources, use Run selected for scenes or Open selected editor for runtime-compatible DialogicEditor scenes. Custom editors choose their own output files. EditorPlugin / EditorInterface tools require the Godot editor."; extensions.add_child(explanation)
	var extension_catalog := TextEdit.new(); extension_catalog.name = "ExtensionCatalog"; extension_catalog.editable = false; extension_catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL; extensions.add_child(extension_catalog)
	var output := VBoxContainer.new(); output.name = "Run log"; tabs.add_child(output)
	logs = TextEdit.new(); logs.name = "TargetLog"; logs.editable = false; logs.size_flags_vertical = Control.SIZE_EXPAND_FILL; output.add_child(logs)
	message = Label.new(); message.name = "ProjectMessage"; message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; message.custom_minimum_size.y = 48; box.add_child(message)
	button(box, "Close", func(): transition(hide))
	unsaved = ConfirmationDialog.new(); unsaved.title = "Unsaved target project changes"; unsaved.dialog_text = "Save all target project changes before continuing?"; unsaved.ok_button_text = "Save"; unsaved.add_button("Discard", false, "discard"); add_child(unsaved)
	unsaved.confirmed.connect(func():
		if save_all(): finish_pending())
	unsaved.canceled.connect(func(): pending = Callable())
	unsaved.custom_action.connect(func(action: String):
		if action == "discard":
			unsaved.hide()
			refresh()
			finish_pending())
	confirm_rename = ConfirmationDialog.new(); confirm_rename.title = "Review native resource rename"; confirm_rename.ok_button_text = "Apply rename"; add_child(confirm_rename); confirm_rename.confirmed.connect(commit_rename)
	transfer_dialog = FileDialog.new(); transfer_dialog.access = FileDialog.ACCESS_FILESYSTEM; transfer_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE; transfer_dialog.title = "New destination folder name"; transfer_dialog.current_file = "Dialogic_Project"; add_child(transfer_dialog)
	transfer_dialog.file_selected.connect(func(destination: String):
		var result := preload("res://application/project_transfer.gd").export_native(workspace, destination)
		show_message(result.error if result.has("error") else "Native project exported: " + result.destination))
	close_requested.connect(func(): transition(hide))

func button(parent: Node, caption: String, action: Callable) -> Button:
	var node := Button.new(); node.text = caption; node.name = caption.replace(" ", ""); node.pressed.connect(action); parent.add_child(node); return node

func line(parent: Node, caption: String, id: String) -> LineEdit:
	var label := Label.new(); label.text = caption; parent.add_child(label)
	var field := LineEdit.new(); field.name = id; parent.add_child(field); return field

func open_project(target_workspace: RefCounted) -> void:
	workspace = target_workspace
	refresh()
	var available := Vector2i(get_parent().get_viewport().get_visible_rect().size)
	popup_centered(Vector2i(mini(1120, available.x - 40), mini(760, available.y - 70)))
	if is_embedded(): position = (available - size) / 2

func refresh() -> void:
	project = Project.new()
	if project.open_project(workspace) != OK: show_message(project.last_error); return
	index = Index.new(); index.scan(workspace)
	document = null; replace_source_text("")
	_updating = true; key_field.text = ""; value_field.text = ""; _setting_original_key = ""; _setting_original_value = ""; _updating = false
	populate_settings(); populate_resources(); update_dirty()
	var report: Array[String] = []
	for extension: Dictionary in Extensions.catalog(index): report.append(extension.path + "\n  " + ", ".join(extension.categories))
	(tabs.get_node("Extensions/ExtensionCatalog") as TextEdit).text = "\n\n".join(report)
	show_message("%d target resources · %d references · %d diagnostic(s)." % [index.resources.size(), index.references.size(), index.diagnostics.size()])
	if not project.diagnostics.is_empty(): show_message("\n".join(project.diagnostics))

func populate_settings() -> void:
	setting_list.clear()
	var parsed := Project.inspect(project.content)
	for key: String in parsed.get("entries", {}):
		if key.contains("/"): setting_list.add_item(key)

func select_setting_key(key: String) -> void:
	selected_setting = key
	var parsed := Project.inspect(project.content)
	if not parsed.get("entries", {}).has(selected_setting): return
	_updating = true
	key_field.text = selected_setting
	value_field.text = parsed.entries[selected_setting].literal
	remember_setting(); _updating = false; update_dirty()

func apply_setting() -> bool:
	var key := key_field.text.strip_edges()
	var literal := value_field.text.strip_edges()
	if Project.Data._has_constructor(literal): show_message("Object/resource constructors remain opaque. Edit their original source if needed."); return false
	var parsed := Project.Data._parse_value(literal)
	if parsed.has("error"): show_message(parsed.error); return false
	var error: Error
	if key.begins_with("autoload/") and key != "autoload/Dialogic":
		if not parsed.value is String: show_message("Autoload value must be a native path string."); return false
		error = project.set_autoload(key.trim_prefix("autoload/"), parsed.value.trim_prefix("*"), parsed.value.begins_with("*"))
	else: error = project.set_value(key, parsed.value)
	if error != OK: show_message(project.last_error); return false
	remember_setting(); populate_settings(); update_dirty(); show_message("Value applied to draft. Save all writes the target project.")

	return true

func remove_setting() -> void:
	if project.remove_value(key_field.text.strip_edges()) != OK: show_message(project.last_error); return
	_updating = true; key_field.text = ""; value_field.text = ""; remember_setting(); _updating = false
	populate_settings(); update_dirty()

func move_autoload(offset: int) -> void:
	if not key_field.text.begins_with("autoload/"): show_message("Select an autoload first."); return
	if project.reorder_autoload(key_field.text.trim_prefix("autoload/"), offset) != OK: show_message("Cannot move this autoload in that direction."); return
	populate_settings(); update_dirty()

func populate_resources() -> void:
	resource_list.clear()
	if index == null: return
	var paths: Array = index.resources.keys(); paths.sort()
	for logical: String in paths:
		if filter.text.is_empty() or logical.to_lower().contains(filter.text.to_lower()):
			resource_list.add_item(logical.get_file() + " · " + logical.get_base_dir().trim_prefix("res://")); resource_list.set_item_metadata(resource_list.item_count - 1, logical); resource_list.set_item_tooltip(resource_list.item_count - 1, logical)

func select_resource(logical: String) -> void:
	selected_resource = logical
	if not index.resources.has(logical): return
	var item: Dictionary = index.resources[logical]
	var report: Array[String] = [logical, "Type: %s · %d bytes\nUID: %s" % [item.kind, item.bytes, item.uid], "\nDependencies:"]
	for reference: Dictionary in index.dependencies(logical): report.append("%d → %s" % [reference.line, reference.target])
	report.append("\nReferenced by:")
	for reference: Dictionary in index.incoming(logical): report.append("%s:%d (%s)" % [reference.source, reference.line, reference.kind])
	report.append("\nDiagnostics / analysis limits:")
	report.append_array(index.diagnostics); report.append_array(index.uncertain)
	references.text = "\n".join(report); rename_path.text = logical
	reference_list.clear()
	for reference: Dictionary in index.dependencies(logical) + index.incoming(logical):
		reference_list.add_item("%s:%d → %s" % [reference.source.get_file(), reference.line, reference.target.get_file()])
		reference_list.set_item_metadata(reference_list.item_count - 1, reference)
		reference_list.set_item_tooltip(reference_list.item_count - 1, "Double-click to open " + reference.source + ":" + str(reference.line))

func open_selected() -> void:
	var next := Source.new()
	if next.open_source(workspace, selected_resource) != OK: show_message(next.last_error); return
	document = next
	replace_source_text(document.content); source_editor.editable = not document.read_only
	source_label.text = selected_resource; source_label.tooltip_text = selected_resource; tabs.current_tab = 2; update_dirty()

func create_source_editor() -> CodeEdit:
	var control := CodeEdit.new()
	control.name = "ProjectSource"; control.size_flags_vertical = Control.SIZE_EXPAND_FILL; control.gutters_draw_line_numbers = true
	control.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_F and event.is_command_or_control_pressed():
				source_find.grab_focus(); source_find.select_all(); source_editor.accept_event()
			elif event.keycode == KEY_F3:
				find_source(event.shift_pressed); source_editor.accept_event())
	control.text_changed.connect(func():
		if not _updating and document != null: document.set_content(source_editor.text, false); update_dirty())
	return control

func replace_source_text(text: String) -> void:
	# A new native control avoids fixed-engine hidden-scroll and clear/gutter bugs,
	# and makes undo history belong only to the newly opened document.
	_updating = true
	var previous := source_editor
	var holder := previous.get_parent()
	var position_in_parent := previous.get_index()
	holder.remove_child(previous)
	source_editor = create_source_editor()
	source_editor.text = text
	source_editor.clear_undo_history()
	holder.add_child(source_editor); holder.move_child(source_editor, position_in_parent)
	previous.queue_free()
	_updating = false

func remember_setting() -> void:
	_setting_original_key = key_field.text; _setting_original_value = value_field.text

func setting_form_dirty() -> bool:
	return not _updating and key_field != null and (key_field.text != _setting_original_key or value_field.text != _setting_original_value)

func dirty() -> bool:
	return setting_form_dirty() or (project != null and project.dirty) or (document != null and document.dirty)

func transition(action: Callable) -> void:
	if dirty(): pending = action; unsaved.popup_centered(Vector2i(500, 180))
	else: action.call()

func finish_pending() -> void:
	var action := pending
	pending = Callable()
	if action.is_valid(): action.call()

func save_source() -> bool:
	if document == null or not document.dirty: return true
	if document.save_file() != OK: show_message(document.last_error); return false
	update_dirty(); saved.emit(); show_message("Native source saved. Use Run selected to compile it in the target process."); return true

func save_all() -> bool:
	if setting_form_dirty() and not apply_setting(): return false
	if project != null and project.dirty and project.save_file() != OK: show_message(project.last_error); return false
	if not save_source(): return false
	update_dirty(); saved.emit(); show_message("Target project changes saved."); return true

func update_dirty() -> void:
	title = "Project & Extensions · " + Identity.project_name() + (" *" if dirty() else "")

func preview_rename() -> void:
	transition(func():
		rename_plan = Rename.plan(index, selected_resource, rename_path.text.strip_edges())
		if rename_plan.has("error"): show_message(rename_plan.error); return
		confirm_rename.dialog_text = rename_plan.source + "\n→ " + rename_plan.destination + "\nUID: " + rename_plan.uid + "\n\n" + "\n".join(rename_plan.summary) + "\n\nRecovery copies will be retained."
		confirm_rename.popup_centered(Vector2i(700, 360)))

func commit_rename() -> void:
	var result := Rename.commit(index, rename_plan)
	if result.has("error"): show_message(result.error); return
	resource_renamed.emit(rename_plan.source, rename_plan.destination); saved.emit(); refresh(); show_message("Rename committed. Recovery copies remain beside the changed files.")

func create_examples() -> void:
	var result := Extensions.create_example(workspace, extension_name.text.strip_edges())
	if result.has("error"): show_message(result.error); return
	refresh(); saved.emit(); show_message("Created native extension files in " + result.folder)

func run_selected() -> void:
	if selected_resource.get_extension() == "dtl": run_target("timeline", selected_resource)
	elif selected_resource.get_extension() in ["tscn", "scn"]: run_target("scene", selected_resource)
	else: show_message("Select a timeline or scene. Scripts run through their target scene or autoload.")

func run_target(mode: String, entry: String, buffer: String = "") -> void:
	show_message("Preparing target resources…")
	var result := runtime.start(workspace, mode, entry, buffer)
	if result.has("error"): show_message(result.error); return
	_last_log_size = -1; _last_run_state = "running"; tabs.current_tab = 4; show_message("Target process running. Log: " + runtime.log_path)

func _process(_delta: float) -> void:
	if runtime.log_path.is_empty() or not visible: return
	runtime.running()
	if FileAccess.file_exists(runtime.log_path):
		var text := FileAccess.get_file_as_string(runtime.log_path)
		if text.length() != _last_log_size:
			logs.text = text; _last_log_size = text.length()
			if Runtime.log_reports_failure(text): show_message("Target reported an error. Inspect Run log; the original project is unchanged.")
	if runtime.state != _last_run_state:
		_last_run_state = runtime.state
		if runtime.state in ["ended", "failed"]:
			show_message("Target process %s (exit %d). Inspect Run log: %s" % ["failed" if Runtime.log_reports_failure(logs.text) else runtime.state, runtime.exit_code, runtime.log_path])

func show_message(text: String) -> void:
	message.text = text; message.tooltip_text = text

func find_source(backwards: bool) -> void:
	if source_find.text.is_empty(): show_message("Enter a literal source search."); return
	var line_number := source_editor.get_caret_line()
	var column := source_editor.get_caret_column() + (-1 if backwards else 1)
	if column < 0:
		line_number = posmod(line_number - 1, source_editor.get_line_count())
		column = source_editor.get_line(line_number).length()
	elif column > source_editor.get_line(line_number).length():
		line_number = (line_number + 1) % source_editor.get_line_count(); column = 0
	var found := source_editor.search(source_find.text, TextEdit.SEARCH_MATCH_CASE | (TextEdit.SEARCH_BACKWARDS if backwards else 0), line_number, column)
	if found.x < 0: show_message("No source match."); return
	source_editor.set_caret_line(found.y); source_editor.set_caret_column(found.x)
	source_editor.select(found.y, found.x, found.y, found.x + source_find.text.length())
	source_editor.center_viewport_to_caret()
	show_message("Source match at line %d." % (found.y + 1))

func _exit_tree() -> void:
	runtime.stop()
