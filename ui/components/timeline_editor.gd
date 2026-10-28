extends Control

signal new_requested
signal open_requested
signal save_requested
signal save_as_requested
signal preview_from_line(line: int)
signal preview_requested
signal stop_requested
signal content_changed(text: String)

# Keep the supplied scene shell and add the working editor inside it.
# APIs: https://docs.godotengine.org/en/stable/classes/class_codeedit.html
# https://docs.godotengine.org/en/stable/classes/class_textedit.html

@onready var event_palette: Node = %EventPalette
@onready var header: Control = $Header
@onready var workspace: Control = $Workspace
@onready var no_timeline_screen: Control = %NoTimelineScreen
@onready var create_timeline_button: Button = %CreateTimelineButton
@onready var title_label: Label = $Header/HeaderMargin/HeaderRow/TimelineName

var authoring: VBoxContainer
var content_workspace: RefCounted
var interaction_form: ConfirmationDialog
var character_form: ConfirmationDialog
var choice_form: ConfirmationDialog
var flow_form: ConfirmationDialog
var inline_form: ConfirmationDialog
var condition_form: ConfirmationDialog
var variable_form: ConfirmationDialog
var source_editor: CodeEdit
var status_label: Label
var position_label: Label
var save_button: Button
var save_as_button: Button
var preview_button: Button
var stop_button: Button
var find_button: Button
var find_bar: HBoxContainer
var find_field: LineEdit
var find_previous_button: Button
var find_next_button: Button
var find_result: Label
var diagnostic_row: HBoxContainer
var diagnostic_count: Label
var diagnostic_selector: OptionButton
var diagnostic_jump_button: Button
var _issues: Array = []
var _diagnostic_source := ""
var timeline_opened := false
var document_read_only := false
var preview_running := false
var preview_available := false
var _updating_text := false


func _ready() -> void:
	_build_toolbar()
	_build_source_editor()
	_build_empty_screen()
	create_timeline_button.pressed.connect(func() -> void: new_requested.emit())
	event_palette.connect(&"text_requested", _insert_narration)
	event_palette.connect(&"host_requested", func(kind: String): _insert_branch_event('[signal arg="Signal"]' if kind == "Signal" else "do Host.method()"))
	event_palette.connect(&"comment_requested", _insert_comment)
	event_palette.connect(&"character_event_requested", _insert_character_source)
	character_form = preload("res://ui/components/character_event_editor.gd").new()
	character_form.name = "CharacterEventEditor"
	add_child(character_form)
	event_palette.connect(&"character_properties_requested", func(kind: String): character_form.open_for_editor(source_editor, content_workspace, kind))
	variable_form = preload("res://ui/components/variable_event_editor.gd").new()
	variable_form.name = "VariableEventEditor"
	add_child(variable_form)
	event_palette.connect(&"variable_requested", func(): variable_form.open_for_editor(source_editor))
	condition_form = preload("res://ui/components/condition_event_editor.gd").new()
	condition_form.name = "ConditionEventEditor"
	add_child(condition_form)
	event_palette.connect(&"condition_requested", func(): condition_form.open_for_editor(source_editor))
	choice_form = preload("res://ui/components/choice_event_editor.gd").new()
	choice_form.name = "ChoiceEventEditor"
	add_child(choice_form)
	event_palette.connect(&"choice_requested", func(): choice_form.open_for_editor(source_editor))
	flow_form = preload("res://ui/components/flow_event_editor.gd").new()
	flow_form.name = "FlowEventEditor"
	add_child(flow_form)
	event_palette.connect(&"flow_requested", func(kind: String): flow_form.open_for_editor(source_editor, kind))
	inline_form = preload("res://ui/components/conditional_text_editor.gd").new()
	inline_form.name = "ConditionalTextEditor"
	add_child(inline_form)
	event_palette.connect(&"inline_requested", func(): inline_form.open_for_editor(source_editor))
	interaction_form = preload("res://ui/components/text_interaction_editor.gd").new()
	interaction_form.name = "TextInteractionEditor"
	add_child(interaction_form)
	event_palette.connect(&"interaction_requested", func(kind: String): interaction_form.open_for_editor(source_editor, content_workspace, kind))
	authoring = preload("res://ui/components/authoring_tools.gd").new()
	var source_column := source_editor.get_parent()
	source_column.add_child(authoring)
	source_column.move_child(authoring, source_editor.get_index())
	authoring.setup(self)
	authoring.play_from_line.connect(func(line: int): preview_from_line.emit(line))
	_refresh_view_state()


func _build_toolbar() -> void:
	var row: HBoxContainer = $Header/HeaderMargin/HeaderRow
	title_label.text = "Untitled"
	title_label.custom_minimum_size.x = 70
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	$Header/HeaderMargin/HeaderRow/Info.tooltip_text = "Native Dialogic .dtl: narration, comments, character dialogue and Character events."
	$Header/HeaderMargin/HeaderRow/Spacer.hide()
	$Header/HeaderMargin/HeaderRow/TextEditor.hide()
	$Header/HeaderMargin/HeaderRow/Utility.hide()
	_add_toolbar_button(row, "New", "New timeline (Ctrl+N)", func() -> void: new_requested.emit())
	_add_toolbar_button(row, "Open", "Open a .dtl file (Ctrl+O)", func() -> void: open_requested.emit())
	save_button = _add_toolbar_button(row, "Save", "Save (Ctrl+S)", func() -> void: save_requested.emit())
	save_as_button = _add_toolbar_button(row, "Save As", "Save as (Ctrl+Shift+S)", func() -> void: save_as_requested.emit())
	preview_button = _add_toolbar_button(row, "Play", "Preview with the Dialogic runtime", func() -> void: preview_requested.emit())
	preview_button.icon = preload("res://asset/dialogic_ui/icons/play.svg")
	stop_button = _add_toolbar_button(row, "Stop", "Stop preview", func() -> void: stop_requested.emit())
	stop_button.disabled = true


func _add_toolbar_button(row: HBoxContainer, caption: String, hint: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = caption.replace(" ", "") + "Button"
	button.text = caption
	button.tooltip_text = hint
	button.custom_minimum_size.y = 32
	button.pressed.connect(callback)
	row.add_child(button)
	return button


func _build_source_editor() -> void:
	var panel: PanelContainer = $Workspace/TimelinePanel
	$Workspace/TimelinePanel/TimelineScroll.hide()
	var margin := MarginContainer.new()
	margin.name = "SourceMargin"
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "SourceColumn"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var mode_row := HBoxContainer.new()
	column.add_child(mode_row)
	var hint := Label.new()
	hint.name = "ModeLabel"
	hint.text = "TEXT EDITOR  /  Native .dtl"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.64, 0.67, 0.72))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(hint)
	find_button = Button.new()
	find_button.name = "FindButton"
	find_button.text = "Find"
	find_button.tooltip_text = "Find text (Ctrl+F)"
	find_button.pressed.connect(show_find)
	mode_row.add_child(find_button)
	_build_find_bar(column)
	source_editor = CodeEdit.new()
	source_editor.name = "SourceEditor"
	source_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	source_editor.custom_minimum_size = Vector2(240, 160)
	source_editor.placeholder_text = "Write one narration event per line.\nEscape a literal colon as \\:"
	source_editor.gutters_draw_line_numbers = true
	source_editor.gutters_line_numbers_min_digits = 2
	source_editor.highlight_current_line = true
	source_editor.caret_blink = true
	source_editor.caret_draw_when_editable_disabled = true
	source_editor.deselect_on_focus_loss_enabled = false
	source_editor.scroll_past_end_of_file = false
	source_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	source_editor.auto_brace_completion_enabled = false
	source_editor.indent_automatic = false
	source_editor.indent_use_spaces = false
	source_editor.draw_tabs = true
	source_editor.draw_spaces = true
	source_editor.add_theme_font_size_override("font_size", 16)
	var source_font := SystemFont.new()
	source_font.font_names = PackedStringArray(["Cascadia Mono", "Noto Sans Mono", "DejaVu Sans Mono", "Microsoft YaHei", "Noto Sans CJK SC", "Yu Gothic"])
	source_font.fallbacks = [preload("res://asset/fonts/NotoSansCJKsc-Regular.otf")]
	source_editor.add_theme_font_override("font", source_font)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.09, 0.09, 0.10)
	input_style.content_margin_left = 8
	input_style.content_margin_top = 8
	input_style.content_margin_right = 8
	input_style.content_margin_bottom = 8
	input_style.set_corner_radius_all(4)
	source_editor.add_theme_stylebox_override("normal", input_style)
	source_editor.add_theme_stylebox_override("read_only", input_style)
	source_editor.add_theme_color_override("font_color", Color(0.86, 0.86, 0.89))
	source_editor.add_theme_color_override("font_readonly_color", Color(0.72, 0.72, 0.76))
	source_editor.add_theme_color_override("current_line_color", Color(0.20, 0.22, 0.26, 0.45))
	source_editor.add_theme_color_override("selection_color", Color(0.25, 0.46, 0.67, 0.6))
	source_editor.text_changed.connect(_on_source_changed)
	source_editor.caret_changed.connect(_update_position)
	column.add_child(source_editor)
	_build_diagnostic_row(column)
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.max_lines_visible = 2
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.custom_minimum_size.y = 18
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.69, 0.72, 0.77))
	column.add_child(status_label)
	position_label = Label.new()
	position_label.name = "PositionLabel"
	position_label.add_theme_font_size_override("font_size", 11)
	position_label.add_theme_color_override("font_color", Color(0.52, 0.55, 0.61))
	column.add_child(position_label)
	_update_position()


func _build_find_bar(column: VBoxContainer) -> void:
	find_bar = HBoxContainer.new()
	find_bar.name = "FindBar"
	find_bar.add_theme_constant_override("separation", 4)
	column.add_child(find_bar)
	find_field = LineEdit.new()
	find_field.name = "FindField"
	find_field.placeholder_text = "Find text"
	find_field.tooltip_text = "Literal, case-insensitive search. Enter: next; Shift+Enter: previous."
	find_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	find_field.custom_minimum_size.x = 120
	find_field.text_changed.connect(_on_find_text_changed)
	find_field.gui_input.connect(_on_find_input)
	find_bar.add_child(find_field)
	find_result = Label.new()
	find_result.name = "FindResult"
	find_result.add_theme_font_size_override("font_size", 11)
	find_result.custom_minimum_size.x = 68
	find_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	find_bar.add_child(find_result)
	find_previous_button = _add_toolbar_button(find_bar, "Prev", "Previous match (Shift+F3)", func() -> void: find_next(true))
	find_next_button = _add_toolbar_button(find_bar, "Next", "Next match (F3)", func() -> void: find_next(false))
	_add_toolbar_button(find_bar, "×", "Close find (Esc)", close_find)
	find_bar.hide()


func show_find() -> void:
	if not timeline_opened or preview_running:
		return
	var selection: String = source_editor.get_selected_text()
	if not selection.is_empty() and not selection.contains("\n"):
		find_field.text = selection
	find_bar.show()
	_on_find_text_changed(find_field.text)
	find_field.grab_focus()
	find_field.select_all()


func close_find() -> void:
	find_bar.hide()
	source_editor.set_search_text("")
	focus_editor()


func _on_find_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		find_next(event.shift_pressed)
		find_field.accept_event()
	elif event.keycode == KEY_ESCAPE:
		close_find()
		find_field.accept_event()


func _on_find_text_changed(query: String) -> void:
	source_editor.set_search_flags(0)
	source_editor.set_search_text(query)
	if query.is_empty():
		find_result.text = ""
		return
	_perform_find(false, false)


func find_next(backwards: bool = false) -> void:
	if not timeline_opened or preview_running:
		return
	if find_field.text.is_empty():
		show_find()
		return
	find_bar.show()
	source_editor.set_search_flags(0)
	source_editor.set_search_text(find_field.text)
	_perform_find(backwards, true)


func _perform_find(backwards: bool, advance: bool) -> void:
	var query: String = find_field.text
	var line: int = source_editor.get_caret_line()
	var column: int = source_editor.get_caret_column()
	var selected: String = source_editor.get_selected_text()
	# Starting one codepoint beyond the selected match also finds overlapping
	# literal matches. TextEdit.search handles Unicode and document wrapping.
	if advance and source_editor.has_selection() and selected.nocasecmp_to(query) == 0:
		line = source_editor.get_selection_from_line()
		column = source_editor.get_selection_from_column() + (-1 if backwards else 1)
	elif backwards and advance:
		column -= 1
	if column < 0:
		line = (line - 1 + source_editor.get_line_count()) % source_editor.get_line_count()
		column = source_editor.get_line(line).length()
	elif column > source_editor.get_line(line).length():
		line = (line + 1) % source_editor.get_line_count()
		column = 0
	var flags: int = TextEdit.SEARCH_BACKWARDS if backwards else 0
	var result: Vector2i = source_editor.search(query, flags, line, column)
	if result.x < 0:
		find_result.text = "Not found"
		find_result.tooltip_text = "No matching text in this document."
		source_editor.deselect()
		return
	source_editor.remove_secondary_carets()
	source_editor.select(result.y, result.x, result.y, result.x + query.length())
	source_editor.center_viewport_to_caret()
	find_result.text = "%d:%d" % [result.y + 1, result.x + 1]
	find_result.tooltip_text = "Match at line %d, column %d. Search wraps at the document ends." % [result.y + 1, result.x + 1]


func _build_diagnostic_row(column: VBoxContainer) -> void:
	diagnostic_row = HBoxContainer.new()
	diagnostic_row.name = "DiagnosticRow"
	column.add_child(diagnostic_row)
	diagnostic_count = Label.new()
	diagnostic_count.add_theme_font_size_override("font_size", 12)
	diagnostic_row.add_child(diagnostic_count)
	diagnostic_selector = OptionButton.new()
	diagnostic_selector.name = "Diagnostics"
	diagnostic_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagnostic_selector.custom_minimum_size.x = 100
	diagnostic_selector.fit_to_longest_item = false
	diagnostic_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	diagnostic_selector.item_selected.connect(_on_diagnostic_selected)
	diagnostic_row.add_child(diagnostic_selector)
	diagnostic_jump_button = _add_toolbar_button(diagnostic_row, "Go to line", "Jump to the selected diagnostic", func() -> void: jump_to_diagnostic(diagnostic_selector.selected))
	diagnostic_row.hide()


func set_diagnostics(issues: Array) -> void:
	_issues = issues.duplicate(true)
	_diagnostic_source = source_editor.text
	diagnostic_selector.clear()
	diagnostic_count.text = "%d issue(s)" % _issues.size()
	for issue: Dictionary in _issues:
		var line: int = int(issue.get("line", 0))
		var caption: String = ("Line %d: " % line if line > 0 else "") + str(issue.get("message", ""))
		diagnostic_selector.add_item(caption)
		diagnostic_selector.get_popup().set_item_tooltip(diagnostic_selector.item_count - 1, caption)
	diagnostic_row.visible = not _issues.is_empty()
	if not _issues.is_empty():
		diagnostic_selector.select(0)
		diagnostic_selector.tooltip_text = diagnostic_selector.get_item_text(0)
	diagnostic_jump_button.disabled = preview_running or _issues.is_empty() or int(_issues[0].get("line", 0)) <= 0


func _on_diagnostic_selected(index: int) -> void:
	diagnostic_selector.tooltip_text = diagnostic_selector.get_item_text(index)
	diagnostic_jump_button.disabled = preview_running or int(_issues[index].get("line", 0)) <= 0
	jump_to_diagnostic(index)


func jump_to_diagnostic(index: int) -> void:
	# A click can arrive before TextEdit's deferred text_changed signal.
	# Never navigate using locations belonging to an earlier buffer.
	if source_editor.text != _diagnostic_source:
		set_diagnostics([])
		return
	if preview_running or index < 0 or index >= _issues.size():
		return
	var issue: Dictionary = _issues[index]
	var source_line: int = int(issue.get("line", 0))
	if source_line <= 0 or source_line > source_editor.get_line_count():
		return
	var line: int = source_line - 1
	var column: int = clampi(int(issue.get("column", 1)) - 1, 0, source_editor.get_line(line).length())
	source_editor.remove_secondary_carets()
	source_editor.deselect()
	source_editor.set_caret_line(line)
	source_editor.set_caret_column(column)
	source_editor.center_viewport_to_caret()
	source_editor.grab_focus()


func _build_empty_screen() -> void:
	var content: VBoxContainer = $NoTimelineScreen/CenterContainer/EmptyContent
	var message: Label = $NoTimelineScreen/CenterContainer/EmptyContent/Message
	message.text = "No timeline opened.\nCreate a timeline\nor open a .dtl file."
	var open_button := Button.new()
	open_button.name = "OpenTimelineButton"
	open_button.text = "Open Timeline"
	open_button.custom_minimum_size.y = 34
	open_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	open_button.pressed.connect(func() -> void: open_requested.emit())
	content.add_child(open_button)
	var scope := Label.new()
	scope.text = "Narration · Comments · Characters"
	scope.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scope.add_theme_font_size_override("font_size", 12)
	scope.add_theme_color_override("font_color", Color(0.55, 0.57, 0.63))
	content.add_child(scope)


func show_document(title: String, text: String, read_only: bool, message: String) -> void:
	timeline_opened = true
	find_bar.hide()
	find_field.text = ""
	find_result.text = ""
	source_editor.set_search_text("")
	set_diagnostics([])
	_updating_text = true
	if authoring != null: authoring.prepare_source(text)
	source_editor.text = text
	source_editor.clear_undo_history()
	_updating_text = false
	set_document_state(title, read_only, message)
	if authoring != null: authoring.snapshot = ""; authoring.refresh()


func set_document_state(title: String, read_only: bool, message: String) -> void:
	document_read_only = read_only
	title_label.text = title
	title_label.tooltip_text = title
	source_editor.tooltip_text = "Read-only: this file uses unsupported features or unresolved content." if read_only else "Dialogic .dtl source. Plain text: narration; # comment; identifier: dialogue; join / leave."
	set_status(message)
	_refresh_view_state()
	_update_position()


func set_status(message: String) -> void:
	status_label.text = message
	status_label.tooltip_text = message


func set_preview_state(running: bool) -> void:
	preview_running = running
	if running:
		find_bar.hide()
		source_editor.set_search_text("")
	_refresh_view_state()


func set_preview_available(available: bool) -> void:
	preview_available = available
	_refresh_view_state()


func current_text() -> String:
	return source_editor.text


func get_text_editor() -> CodeEdit:
	return source_editor


func focus_editor() -> void:
	if timeline_opened:
		if authoring != null and authoring.visual: authoring.tree.grab_focus()
		else: source_editor.grab_focus()


func _on_source_changed() -> void:
	if not _updating_text:
		# Save/Play can have already validated this exact buffer before the
		# deferred text_changed signal arrives. Keep that fresh result.
		if source_editor.text != _diagnostic_source:
			set_diagnostics([])
		if find_bar.visible and not find_field.text.is_empty():
			find_result.text = "Next / Prev"
		content_changed.emit(source_editor.text)
	_update_position()


func _insert_narration() -> void:
	_insert_branch_event("New narration.")


func _insert_comment() -> void:
	_insert_branch_event("# New comment.")


func set_characters(identifiers: Array[String]) -> void:
	event_palette.set_characters(identifiers)


func _insert_character_source(text: String) -> void:
	_insert_branch_event(text.trim_suffix("\n"))


func _insert_branch_event(text: String) -> void:
	if not timeline_opened or document_read_only or preview_running:
		return
	source_editor.grab_focus()
	var line := source_editor.get_line(source_editor.get_caret_line())
	var indent := line.left(line.length() - line.strip_edges(true, false).length())
	# Preserve the original insertion behavior outside a branch. Inside one,
	# insert an explicit event before the current line without splitting it.
	if indent.is_empty():
		var prefix := "" if source_editor.text.is_empty() or source_editor.get_caret_column() == 0 else "\n"
		source_editor.insert_text_at_caret(prefix + text + "\n")
	else:
		source_editor.remove_secondary_carets()
		source_editor.begin_complex_operation()
		source_editor.deselect()
		source_editor.set_caret_column(0)
		source_editor.insert_text_at_caret(indent + text + "\n")
		source_editor.end_complex_operation()


func _update_position() -> void:
	if is_instance_valid(position_label) and is_instance_valid(source_editor):
		position_label.text = "Ln %d, Col %d   ·   Dialogic .dtl   ·   %s" % [source_editor.get_caret_line() + 1, source_editor.get_caret_column() + 1, "Read-only" if document_read_only else "UTF-8"]


func _refresh_view_state() -> void:
	header.visible = timeline_opened
	workspace.visible = timeline_opened
	no_timeline_screen.visible = not timeline_opened
	save_button.disabled = not timeline_opened or document_read_only or preview_running
	save_as_button.disabled = not timeline_opened or document_read_only or preview_running
	preview_button.disabled = not timeline_opened or document_read_only or preview_running or not preview_available
	stop_button.disabled = not preview_running
	find_button.disabled = not timeline_opened or preview_running
	find_field.editable = not preview_running
	find_previous_button.disabled = preview_running
	find_next_button.disabled = preview_running
	diagnostic_selector.disabled = preview_running
	diagnostic_jump_button.disabled = preview_running or _issues.is_empty() or int(_issues[diagnostic_selector.selected].get("line", 0)) <= 0
	source_editor.editable = timeline_opened and not document_read_only and not preview_running
	event_palette.call(&"set_editable", timeline_opened and not document_read_only and not preview_running)
	if authoring != null: authoring.refresh()

