extends VBoxContainer

signal play_from_line(line: int)
const Source = preload("res://application/authoring_source.gd")
const Interaction = preload("res://application/interaction_source.gd")
var host: Control
var editor: CodeEdit
var tree: Tree
var mode_button: Button
var message: Label
var visual := false
var blocks: Array = []
var snapshot := ""
var rebuilding := false
var queued := false
var buttons: Array[Button] = []
var search_dialog: AcceptDialog
var query: LineEdit
var replace_text: LineEdit
var match_case: CheckBox
var whole_word: CheckBox
var use_regex: CheckBox
var in_selection: CheckBox
var search_message: Label
var search_range := Vector2i(-1, -1)
var host_form: ConfirmationDialog
var raw_dialog: ConfirmationDialog
var raw_editor: CodeEdit
var raw_snapshot := ""
var raw_index := -1
var raw_message: Label
var preferences: ConfigFile = ConfigFile.new()
const WRAP_LINE_LIMIT := 16384
var long_line := false
var blank_completion: PopupMenu
var blank_candidates: Array[String] = []
var completion_snapshot := ""
var completion_caret := Vector2i.ZERO

func setup(owner_control: Control) -> void:
	host = owner_control
	editor = host.source_editor
	name = "AuthoringTools"
	preferences.load("user://authoring.cfg")
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 4)
	add_child(bar)
	mode_button = button(bar, "Visual", func(): set_visual(not visual), false)
	button(bar, "Properties", properties)
	button(bar, "Source…", open_raw)
	button(bar, "Copy", func(): operation("copy"), false)
	button(bar, "Cut", func(): operation("cut"))
	button(bar, "Paste", func(): operation("paste"))
	button(bar, "Duplicate", func(): operation("duplicate"))
	button(bar, "Delete", func(): operation("delete"))
	button(bar, "Up", func(): operation("up"))
	button(bar, "Down", func(): operation("down"))
	button(bar, "Indent", func(): operation("indent"))
	button(bar, "Outdent", func(): operation("outdent"))
	button(bar, "Undo", func(): editor.undo())
	button(bar, "Redo", func(): editor.redo())
	button(bar, "Replace…", show_search, false)
	button(bar, "Complete", func(): editor.grab_focus(); editor.request_code_completion(true))
	button(bar, "Play here", play_here, false)
	button(bar, "Preferences…", show_preferences, false)
	tree = Tree.new()
	tree.name = "VisualEvents"
	tree.columns = 3
	tree.set_column_title(0, "Event")
	tree.set_column_title(1, "Source")
	tree.set_column_title(2, "Line")
	tree.set_column_expand(0, false); tree.set_column_custom_minimum_width(0, 130)
	tree.set_column_expand(2, false); tree.set_column_custom_minimum_width(2, 48)
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 160
	tree.item_activated.connect(properties)
	tree.multi_selected.connect(func(item: TreeItem, _column: int, selected: bool):
		if selected and not rebuilding:
			var index := int(item.get_metadata(0))
			if index >= 0 and index < blocks.size(): editor.set_caret_line(blocks[index].line); editor.set_caret_column(0))
	tree.gui_input.connect(_tree_input)
	tree.set_drag_forwarding(_tree_drag, _tree_can_drop, _tree_drop)
	add_child(tree)
	message = Label.new(); message.name = "AuthoringMessage"; message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; message.max_lines_visible = 2; add_child(message)
	editor.set_meta("page_prepare_source", prepare_source)
	editor.gui_input.connect(_prepare_input)
	editor.text_changed.connect(queue_refresh)
	editor.code_completion_enabled = true
	editor.code_completion_prefixes = PackedStringArray(["[", "{", ":", '"', "/", "\t", " ", "-", "#"])
	editor.code_completion_requested.connect(complete)
	blank_completion = PopupMenu.new(); blank_completion.name = "BlankLineCompletion"
	blank_completion.force_native = true # Same fixed-release embedded Popup cleanup workaround.
	blank_completion.max_size = Vector2i(520, 420); add_child(blank_completion)
	blank_completion.index_pressed.connect(accept_blank_completion)
	editor.set_drag_forwarding(Callable(), _source_can_drop, _source_drop)
	var syntax := CodeHighlighter.new()
	syntax.number_color = Color("b5cea8"); syntax.symbol_color = Color("d4d4d4")
	for word: String in ["if", "elif", "else", "set", "setting", "join", "leave", "update", "jump", "return", "end", "do", "label"]: syntax.add_keyword_color(word, Color("8bb7ed"))
	syntax.add_color_region('"', '"', Color("ce9178")); syntax.add_color_region("#", "", Color("8da87c"), true)
	editor.syntax_highlighter = syntax
	build_search()
	build_raw()
	host_form = preload("res://ui/components/host_event_editor.gd").new(); host_form.name = "HostEventProperties"; add_child(host_form)
	apply_preferences()
	set_visual(bool(preferences.get_value("editor", "visual", false)))

func button(parent: Node, caption: String, callback: Callable, mutation := true) -> Button:
	var control := Button.new(); control.text = caption; control.name = caption.replace("…", "").replace(" ", "")
	control.pressed.connect(callback); parent.add_child(control)
	if mutation: buttons.append(control)
	return control

func set_visual(value: bool) -> void:
	visual = value
	tree.visible = visual
	editor.visible = not visual
	size_flags_vertical = Control.SIZE_EXPAND_FILL if visual else Control.SIZE_SHRINK_BEGIN
	mode_button.text = "Text" if visual else "Visual"
	host.get_node("Workspace/TimelinePanel/SourceMargin/SourceColumn").get_child(0).get_node("ModeLabel").text = "VISUAL EDITOR / Native .dtl" if visual else "TEXT EDITOR / Native .dtl"
	refresh()
	preferences.set_value("editor", "visual", visual); save_preferences()
	if visual: tree.grab_focus()
	else: editor.grab_focus()

func queue_refresh() -> void:
	if queued: return
	queued = true
	refresh.call_deferred()

func refresh() -> void:
	queued = false
	if editor == null: return
	prepare_source(editor.text)
	for control: Button in buttons: control.disabled = not editor.editable
	if not visual:
		message.text = "Long lines are shown without wrapping. The complete source is retained." if long_line else ""
		return
	var line := editor.get_caret_line()
	if snapshot == editor.text and tree.get_root() != null: return
	rebuilding = true
	snapshot = editor.text
	var parsed := Source.inspect(snapshot)
	blocks = parsed.blocks
	tree.clear()
	var root := tree.create_item()
	for index: int in blocks.size():
		var block: Dictionary = blocks[index]
		var item := tree.create_item(root)
		item.set_text(0, "  ".repeat(mini(block.depth, 12)) + block.kind)
		item.set_text(1, block.raw.left(2048).replace("\n", " ↵ ") + (" …" if block.raw.length() > 2048 else ""))
		item.set_text(2, str(block.line + 1))
		item.set_metadata(0, index)
		item.set_tooltip_text(1, block.raw.left(8192) + ("\n… Open Source… to view the complete event." if block.raw.length() > 8192 else ""))
		item.set_custom_color(0, block.event.event_color.lightened(0.25))
		if block.line <= line and block.last_line >= line: item.select(0)
	message.text = str(parsed.issues[0].message) if not parsed.issues.is_empty() else "%d events · Ctrl / Shift: multi-select · Parent selection includes its branch." % blocks.size()
	rebuilding = false

func selected() -> Array:
	if not visual:
		blocks = Source.inspect(editor.text).blocks
		var index := Source.at_line(blocks, editor.get_caret_line())
		return [index] if index >= 0 else []
	if snapshot != editor.text: refresh()
	var result := []
	var item := tree.get_next_selected(null)
	while item != null:
		result.append(int(item.get_metadata(0))); item = tree.get_next_selected(item)
	return result

func commit(next: Dictionary) -> bool:
	if not editor.editable: return false
	if next.has("error"): message.text = str(next.error); return false
	Source.apply(editor, str(next.source))
	host.content_changed.emit(editor.text)
	queue_refresh()
	return true

func operation(action: String) -> void:
	if not editor.editable and action != "copy": return
	var selection := selected()
	var expanded := Source.expanded(blocks, selection)
	if action == "paste":
		var position: int = blocks[expanded[0]].start if not expanded.is_empty() else editor.text.length()
		var indent: String = blocks[expanded[0]].indent if not expanded.is_empty() else ""
		var clipboard := DisplayServer.clipboard_get()
		if not clipboard.is_empty(): commit(Source.checked(Source.insert(editor.text, position, clipboard, indent)))
		return
	if expanded.is_empty(): message.text = "Select an event first."; return
	match action:
		"copy", "cut":
			DisplayServer.clipboard_set(Source.copy(editor.text, blocks, selection))
			if action == "cut": commit(Source.checked(Source.remove(editor.text, blocks, selection)))
		"duplicate": commit(Source.checked(Source.insert(editor.text, blocks[expanded[-1]].end, Source.copy(editor.text, blocks, selection), blocks[expanded[0]].indent)))
		"delete": commit(Source.checked(Source.remove(editor.text, blocks, selection)))
		"up":
			if expanded[0] == 0: return
			var target: int = expanded[0] - 1
			while target > 0 and blocks[target].depth > blocks[expanded[0]].depth: target -= 1
			# A preceding elif/else belongs to the preceding if unit.
			for candidate: int in range(target, -1, -1):
				if blocks[candidate].depth == blocks[target].depth and blocks[candidate].raw.begins_with("if ") and target in Source.expanded(blocks, [candidate]):
					target = candidate; break
			commit(Source.move(editor.text, blocks, selection, target))
		"down":
			var target: int = expanded[-1] + 1
			if target >= blocks.size(): return
			var next_group := Source.expanded(blocks, [target])
			commit(Source.move(editor.text, blocks, selection, next_group[-1] + 1))
		"indent", "outdent":
			var lines := editor.text.split("\n", true)
			var unit := "\t"
			for block: Dictionary in blocks:
				if not block.indent.is_empty(): unit = block.indent if block.depth == 1 else unit; break
			for index: int in expanded:
				for line: int in range(blocks[index].line, blocks[index].last_line + 1):
					lines[line] = unit + lines[line] if action == "indent" else lines[line].trim_prefix(unit)
			commit(Source.checked("\n".join(lines)))

func _tree_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var action := ""
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_C: action = "copy"
			KEY_X: action = "cut"
			KEY_V: action = "paste"
			KEY_D: action = "duplicate"
			KEY_Z:
				if editor.editable:
					if event.shift_pressed: editor.redo()
					else: editor.undo()
			KEY_Y:
				if editor.editable: editor.redo()
			KEY_A:
				var item := tree.get_root().get_first_child() if tree.get_root() else null
				while item != null: item.select(0); item = item.get_next()
			KEY_H: show_search()
			_: return
	elif event.keycode == KEY_DELETE: action = "delete"
	elif event.alt_pressed and event.keycode in [KEY_UP, KEY_DOWN]: action = "up" if event.keycode == KEY_UP else "down"
	else: return
	if not action.is_empty(): operation(action)
	tree.accept_event()

func properties() -> void:
	var selection := selected()
	if selection.is_empty() or not editor.editable: return
	var block: Dictionary = blocks[selection[0]]
	editor.set_caret_line(block.line); editor.set_caret_column(block.indent.length())
	var event: DialogicEvent = block.event
	if event is DialogicTextEvent: host.interaction_form.open_for_editor(editor, host.content_workspace, "Text")
	elif event is DialogicCharacterEvent: host.character_form.open_for_editor(editor, host.content_workspace, block.raw.get_slice(" ", 0))
	elif event is DialogicVariableEvent: host.variable_form.open_for_editor(editor)
	elif event is DialogicConditionEvent: host.condition_form.open_for_editor(editor)
	elif event is DialogicChoiceEvent: host.choice_form.open_for_editor(editor)
	elif event is DialogicJumpEvent: host.flow_form.open_for_editor(editor, "Jump")
	elif event is DialogicLabelEvent: host.flow_form.open_for_editor(editor, "Label")
	elif event is DialogicReturnEvent: host.flow_form.open_for_editor(editor, "Return")
	elif event is DialogicEndTimelineEvent: host.flow_form.open_for_editor(editor, "End")
	elif not Interaction.kind_of(event).is_empty(): host.interaction_form.open_for_editor(editor, host.content_workspace, Interaction.kind_of(event))
	elif event is DialogicCommentEvent or event is DialogicSignalEvent or event is DialogicCallEvent: host_form.open_event(editor, block)
	else: open_raw()

func play_here() -> void:
	if host.preview_running or not editor.editable: message.text = "Preview is unavailable for this document or is already running."; return
	var selection := selected()
	if selection.is_empty(): message.text = "Select an event to play from."; return
	message.text = "Starts with project defaults; earlier events are skipped."
	play_from_line.emit(int(blocks[selection[0]].line) + 1)

func build_raw() -> void:
	raw_dialog = ConfirmationDialog.new(); raw_dialog.name = "NativeEventSource"; raw_dialog.title = "Native event source"; raw_dialog.dialog_hide_on_ok = false; add_child(raw_dialog)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(560, 300); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; raw_dialog.add_child(scroll)
	var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(column)
	var hint := Label.new(); hint.text = "Edit this complete native event. Unselected events remain unchanged."; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(hint)
	raw_editor = CodeEdit.new(); raw_editor.custom_minimum_size = Vector2(520, 240); raw_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(raw_editor)
	raw_message = Label.new(); raw_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; raw_message.custom_minimum_size.x = 500; column.add_child(raw_message)
	raw_dialog.confirmed.connect(func():
		if editor.text != raw_snapshot: raw_message.text = "The timeline changed. Reopen the event before applying."; return
		if not editor.editable or raw_index < 0: return
		var block: Dictionary = blocks[raw_index]
		var lines := raw_editor.text.split("\n", true)
		for index: int in lines.size(): lines[index] = block.indent + lines[index]
		var end := Source.offset(editor, block.last_line, editor.get_line(block.last_line).length())
		var next := raw_snapshot.left(block.start) + "\n".join(lines) + raw_snapshot.substr(end)
		var result := Source.checked(next)
		if result.has("error"): raw_message.text = result.error; return
		if commit(result): raw_dialog.hide())

func open_raw() -> void:
	var selection := selected()
	if selection.is_empty() or not editor.editable: return
	raw_index = selection[0]; raw_snapshot = editor.text
	raw_editor.text = blocks[raw_index].raw; raw_editor.clear_undo_history()
	raw_message.text = "Native syntax is preserved. Apply changes as one undo operation."
	raw_dialog.popup_centered(Vector2i(680, 420))

func build_search() -> void:
	search_dialog = AcceptDialog.new(); search_dialog.name = "FindReplace"; search_dialog.title = "Find and replace"; search_dialog.dialog_hide_on_ok = true; add_child(search_dialog)
	search_dialog.get_ok_button().text = "Close"
	var column := VBoxContainer.new(); search_dialog.add_child(column)
	query = LineEdit.new(); query.name = "Query"; query.placeholder_text = "Find"; column.add_child(query)
	replace_text = LineEdit.new(); replace_text.name = "Replacement"; replace_text.placeholder_text = "Replace with · regex capture: $1"; column.add_child(replace_text)
	var flags := HFlowContainer.new(); column.add_child(flags)
	for label: String in ["Match case", "Whole word", "Regex", "Selection only"]:
		var check := CheckBox.new(); check.text = label; flags.add_child(check)
		match label:
			"Match case": match_case = check
			"Whole word": whole_word = check
			"Regex": use_regex = check
			"Selection only": in_selection = check
	var actions := HFlowContainer.new(); column.add_child(actions)
	button(actions, "Previous", func(): search(false, false, true), false)
	button(actions, "Next", func(): search(false, false), false)
	button(actions, "Replace", func(): search(true, false))
	button(actions, "Replace all", func(): search(true, true))
	search_message = Label.new(); search_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; search_message.custom_minimum_size.x = 500; column.add_child(search_message)
	query.text_submitted.connect(func(_text: String): search(false, false))

func show_search() -> void:
	if not host.timeline_opened: return
	search_range = Vector2i(-1, -1)
	if editor.has_selection():
		search_range = Vector2i(Source.offset(editor, editor.get_selection_from_line(), editor.get_selection_from_column()), Source.offset(editor, editor.get_selection_to_line(), editor.get_selection_to_column()))
		if not editor.get_selected_text().contains("\n"): query.text = editor.get_selected_text()
	in_selection.disabled = search_range.x < 0
	if in_selection.disabled: in_selection.button_pressed = false
	search_message.text = "Literal replacement by default. Regex uses $1, $2 for captured groups."
	search_dialog.popup_centered(Vector2i(650, 245)); query.grab_focus()

func search(replace: bool, all_matches: bool, backwards := false) -> void:
	if replace and not editor.editable: search_message.text = "This document cannot be edited now."; return
	var first := search_range.x if in_selection.button_pressed else 0
	var last := search_range.y if in_selection.button_pressed else -1
	var result := Source.matches(editor.text, query.text, match_case.button_pressed, whole_word.button_pressed, use_regex.button_pressed, first, last)
	if result.has("error"): search_message.text = result.error; return
	var found: Array = result.matches
	if found.is_empty(): search_message.text = "No matches."; return
	var at := Source.offset(editor, editor.get_caret_line(), editor.get_caret_column())
	if editor.has_selection(): at = Source.offset(editor, editor.get_selection_from_line(), editor.get_selection_from_column())
	var selected_index := -1
	if replace:
		for index: int in found.size():
			if found[index].start == at: selected_index = index; break
	if selected_index < 0:
		if backwards:
			for index: int in found.size():
				if found[index].start < at: selected_index = index
			if selected_index < 0: selected_index = found.size() - 1
		else:
			for index: int in found.size():
				if found[index].start > at or (not editor.has_selection() and found[index].start == at): selected_index = index; break
			if selected_index < 0: selected_index = 0
	if not replace:
		var start := Source.location(editor.text, found[selected_index].start)
		var end := Source.location(editor.text, found[selected_index].end)
		editor.select(start.y, start.x, end.y, end.x)
		editor.center_viewport_to_caret()
		if visual:
			rebuilding = true
			var item := tree.get_root().get_first_child()
			while item != null:
				item.deselect(0)
				var block: Dictionary = blocks[int(item.get_metadata(0))]
				if start.y >= block.line and start.y <= block.last_line: item.select(0); tree.scroll_to_item(item)
				item = item.get_next()
			rebuilding = false
		search_message.text = "%d / %d · line %d" % [selected_index + 1, found.size(), start.y + 1]
		return
	var changes: Array = found if all_matches else [found[selected_index]]
	var next := editor.text
	var delta := 0
	for index: int in range(changes.size() - 1, -1, -1):
		var hit: Dictionary = changes[index]
		var value := Source.replacement(hit, replace_text.text, use_regex.button_pressed)
		next = next.left(hit.start) + value + next.substr(hit.end)
		delta += value.length() - (hit.end - hit.start)
	if next.to_utf8_buffer().size() > Source.Codec.MAX_SOURCE_BYTES or next.to_utf8_buffer().has(0): search_message.text = "The replacement exceeds the supported text limit."; return
	Source.apply(editor, next)
	if in_selection.button_pressed: search_range.y += delta
	search_message.text = "%d replacement(s). Undo restores this operation." % changes.size()
	queue_refresh()

func complete() -> void:
	if not editor.editable: return
	var candidates: Dictionary = {}
	var prefix := editor.get_line(editor.get_caret_line()).left(editor.get_caret_column())
	var suffix := editor.get_line(editor.get_caret_line()).substr(editor.get_caret_column())
	var stripped := prefix.strip_edges(true, false)
	var content: RefCounted = host.content_workspace
	var variable_context := prefix.rfind("{") > prefix.rfind("}")
	var shortcode_context := prefix.rfind("[") > prefix.rfind("]")
	var quote_context := prefix.count('"') % 2 == 1
	editor.clear_string_delimiters()
	if quote_context and not variable_context: editor.add_string_delimiter('"', '"')
	if variable_context:
		if content != null and content.variable_document != null:
			for key: String in completion_variables(content.variable_document._saved):
				var fragment := prefix.substr(prefix.rfind("{") + 1)
				var scope := fragment.left(fragment.rfind(".") + 1) if fragment.contains(".") else ""
				if not scope.is_empty() and not key.begins_with(scope): continue
				candidates[key.trim_prefix(scope)] = key.trim_prefix(scope) + ("" if suffix.begins_with("}") else "}")
	elif shortcode_context and not quote_context:
		var tail := prefix.substr(prefix.rfind("[") + 1)
		for event: DialogicEvent in DialogicResourceUtil.get_event_cache():
			var code := event.get_shortcode()
			if code.is_empty(): continue
			if not tail.contains(" ") and not tail.contains("\t"): candidates[code] = code + ("" if suffix.begins_with("]") else "]")
			elif tail.replace("\t", " ").get_slice(" ", 0) == code:
				for key: String in event.get_shortcode_parameters(): candidates[key] = key + '=\"\"'
	elif quote_context:
		if content != null:
			var command_subject := stripped.begins_with("join ") or stripped.begins_with("update ") or stripped.begins_with("leave ")
			if command_subject and stripped.count('"') == 1:
				for identifier: String in content.characters:
					if content.has_character(identifier): candidates[identifier] = identifier
			else:
				var property := ""
				var event_code := "audio" if stripped.begins_with("audio ") else ""
				if event_code == "audio": property = "file_path"
				if shortcode_context:
					var tail := prefix.substr(prefix.rfind("[") + 1).replace("\t", " ")
					event_code = tail.get_slice(" ", 0)
					var before_quote := tail.left(tail.rfind('"')).strip_edges().trim_suffix("=").strip_edges()
					var parameter := before_quote.get_slice(" ", before_quote.get_slice_count(" ") - 1)
					for event: DialogicEvent in DialogicResourceUtil.get_event_cache():
						if event.get_shortcode() != event_code: continue
						var schema := event.get_shortcode_parameters()
						if schema.has(parameter): property = str(schema[parameter].property)
				var extensions: Array[String] = []
				if property == "file_path": extensions.assign(["wav", "ogg", "mp3"])
				elif event_code == "background" and property == "argument": extensions.assign(["png", "jpg", "jpeg", "svg", "webp"])
				elif property == "scene": extensions.assign(["tscn", "scn"])
				if not extensions.is_empty():
					for resource: String in resource_paths(content, extensions): candidates[content.content_path(resource)] = content.content_path(resource)
				elif property == "style_name" and content.style_catalog != null:
					for style: String in content.style_catalog.styles:
						if not style.is_empty(): candidates[style] = style
				elif event_code == "text_input" and property == "variable" and content.variable_document != null:
					for variable: String in content.variable_document.runtime_values():
						if content.variable_document.runtime_values()[variable] is String: candidates[variable] = variable
	elif prefix.rfind("(") > prefix.rfind(")"):
		var subject := stripped.left(stripped.rfind("(")).strip_edges()
		var character_command := subject.begins_with("join ") or subject.begins_with("update ") or subject.begins_with("leave ")
		if character_command: subject = subject.substr(subject.find(" ") + 1).strip_edges()
		subject = subject.trim_prefix('"').trim_suffix('"')
		if content != null and content.characters.has(subject):
			var character: Resource = content.characters[subject].get("resource")
			if character != null:
				for portrait: String in character.portraits:
					candidates[portrait] = portrait + ("" if suffix.begins_with(")") else (")" if character_command else "): "))
	elif stripped.begins_with("join ") or stripped.begins_with("update ") or stripped.begins_with("leave "):
		if content != null:
			for identifier: String in content.characters:
				if not content.has_character(identifier): continue
				candidates[identifier] = var_to_str(identifier) if identifier.contains(" ") or identifier.contains("\t") else identifier
	elif stripped.begins_with("jump "):
		for line: String in editor.text.split("\n"):
			if line.strip_edges().begins_with("label "):
				var label := line.strip_edges().trim_prefix("label ").get_slice("(", 0).strip_edges(); candidates[label] = label
		if content != null:
			var catalog := preload("res://application/flow_graph.gd").catalog(content)
			for alias: String in catalog.get("aliases", {}):
				if not catalog.get("ambiguous", {}).has(alias): candidates[alias] = alias + "/"
	else:
		for text: String in ["if true:", "elif true:", "else:", "- Choice", "label start", "jump start", "return", "[end_timeline]", 'setting "text_speed" = 1', "set {value} = 0", "# Comment", "do Host.method()", '[signal arg="Signal"]', '[wait time="1"]', '[wait_input]', '[clear]', '[text_input]', '[style]', 'audio ""', '[background]', '[voice]', '[history]', '[save]']: candidates[text] = text
		if content != null:
			for identifier: String in content.characters:
				if not content.has_character(identifier): continue
				candidates[identifier + ": "] = identifier + ": "
				for command: String in ["join", "update", "leave"]: candidates[command + " " + identifier] = command + " " + identifier
				var character: Resource = content.characters[identifier].get("resource")
				if character != null:
					for portrait: String in character.portraits: candidates[identifier + "(" + portrait + "): "] = identifier + "(" + portrait + "): "
		# Native CodeEdit replaces the current word, not all preceding commands.
		if stripped.contains(" "):
			var fixed := stripped.left(stripped.rfind(" ") + 1)
			var token_candidates := {}
			for caption: String in candidates:
				if caption.begins_with(fixed): token_candidates[caption.trim_prefix(fixed)] = str(candidates[caption]).trim_prefix(fixed)
			candidates = token_candidates
		elif stripped == "#": candidates = {"Comment":" Comment"}
		elif stripped == "-": candidates = {"Choice":" Choice"}
	if prefix.is_empty() and not candidates.is_empty():
		editor.cancel_code_completion(); blank_completion.clear(); blank_candidates.clear()
		completion_snapshot = editor.text
		completion_caret = Vector2i(editor.get_caret_line(), editor.get_caret_column())
		for key: String in candidates:
			blank_completion.add_item(key); blank_candidates.append(candidates[key])
		blank_completion.position = Vector2i(editor.get_screen_position() + editor.get_caret_draw_pos() + Vector2(0, editor.get_line_height()))
		blank_completion.popup(); blank_completion.set_focused_item(0)
		return
	for key: String in candidates: editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, key, candidates[key])
	editor.update_code_completion_options(true)


func accept_blank_completion(index: int) -> void:
	if not editor.editable or editor.text != completion_snapshot or index < 0 or index >= blank_candidates.size(): return
	if Vector2i(editor.get_caret_line(), editor.get_caret_column()) != completion_caret: return
	editor.grab_focus(); editor.insert_text_at_caret(blank_candidates[index]); queue_refresh()

static func resource_paths(content: RefCounted, extensions: Array[String] = ["png", "jpg", "jpeg", "svg", "webp", "wav", "ogg", "mp3"]) -> Array[String]:
	var result: Array[String] = []
	var pending: Array[String] = [content.root_path]
	var count := 0
	while not pending.is_empty() and count < 20000:
		var path := pending.pop_back() as String
		for directory: String in DirAccess.get_directories_at(path):
			count += 1
			if directory.begins_with(".") or directory == "addons": continue
			var child := path.path_join(directory)
			if not content.content_path(child).is_empty(): pending.append(child)
		for file: String in DirAccess.get_files_at(path):
			count += 1
			if file.get_extension().to_lower() in extensions:
				var absolute := path.path_join(file)
				if not content.content_path(absolute).is_empty(): result.append(absolute)
	result.sort()
	return result

func _tree_drag(_position: Vector2) -> Variant:
	if not editor.editable or selected().is_empty(): return null
	var label := Label.new(); label.text = "Move selected event block(s)"; tree.set_drag_preview(label)
	return {"page_event_move": true, "source": editor.text, "selection": selected(), "owner": get_instance_id()}

func _tree_can_drop(_position: Vector2, data: Variant) -> bool:
	return editor.editable and data is Dictionary and ((data.has("page_event_move") and data.get("owner") == get_instance_id()) or data.has("files"))

func _tree_drop(position: Vector2, data: Variant) -> void:
	var item := tree.get_item_at_position(position)
	var target := int(item.get_metadata(0)) if item != null else blocks.size()
	if data.has("page_event_move"):
		if editor.text != data.source: message.text = "The document changed during the drag."; return
		commit(Source.move(editor.text, blocks, data.selection, target))
	else: drop_files(data.files, blocks[target].line if target < blocks.size() else editor.get_line_count())

func _source_can_drop(_position: Vector2, data: Variant) -> bool:
	return editor.editable and data is Dictionary and data.has("files")

func _source_drop(position: Vector2, data: Variant) -> void:
	var point := editor.get_line_column_at_pos(Vector2i(position))
	drop_files(data.files, point.y)

func drop_files(files: Variant, line: int) -> void:
	if not editor.editable or host.content_workspace == null: message.text = "Choose a writable content document first."; return
	var content: RefCounted = host.content_workspace
	var snippets: Array[String] = []
	for input: String in files:
		var logical: String = content.content_path(input)
		if logical.is_empty() or not FileAccess.file_exists(input): message.text = "Drop files already inside the selected content folder: " + input; return
		if logical.contains('"') or logical.contains("\n"): message.text = "This resource path cannot be represented by the native event syntax."; return
		match input.get_extension().to_lower():
			"dch":
				var identifier := ""
				for candidate: String in content.characters:
					if content.characters[candidate].path == input and content.has_character(candidate): identifier = candidate; break
				if identifier.is_empty(): message.text = "The character is unavailable or has unresolved dependencies."; return
				snippets.append((var_to_str(identifier) if identifier.contains(" ") or identifier.contains("\t") else identifier) + ": Dialogue")
			"dtl":
				var catalog := preload("res://application/flow_graph.gd").catalog(content)
				var aliases: Array = catalog.get("aliases", {}).keys(); aliases.sort()
				var selected_alias := ""
				for alias: String in aliases:
					if catalog.aliases[alias] == input and not catalog.ambiguous.has(alias): selected_alias = alias; break
				if selected_alias.is_empty(): message.text = "Assign a unique native timeline alias before dropping this timeline."; return
				snippets.append("jump " + selected_alias + "/")
			"png", "jpg", "jpeg", "svg", "webp": snippets.append(preload("res://application/media_source.gd").serialize("Background", {"argument": logical}).source)
			"wav", "ogg", "mp3": snippets.append(preload("res://application/media_source.gd").serialize("Audio", {"file_path": logical}).source)
			_: message.text = "This file type has no timeline drop action: " + input; return
	var at := Source.offset(editor, line, 0) if line < editor.get_line_count() else editor.text.length()
	var original := editor.get_line(line) if line < editor.get_line_count() else ""
	var indent := original.left(original.length() - original.strip_edges(true, false).length())
	commit(Source.checked(Source.insert(editor.text, at, "\n".join(snippets), indent)))

func show_preferences() -> void:
	var dialog := ConfirmationDialog.new(); dialog.title = "Editor preferences"; dialog.name = "EditorPreferences"; add_child(dialog)
	var column := VBoxContainer.new(); dialog.add_child(column)
	var label := Label.new(); label.text = "These preferences apply to this application on this device."; column.add_child(label)
	var font := SpinBox.new(); font.name = "FontSize"; font.min_value = 10; font.max_value = 40; font.value = preferences.get_value("editor", "font_size", 16); column.add_child(font)
	var wrap := CheckBox.new(); wrap.name = "Wrap"; wrap.text = "Wrap long lines"; wrap.button_pressed = preferences.get_value("editor", "wrap", true); column.add_child(wrap)
	var spaces := CheckBox.new(); spaces.name = "Whitespace"; spaces.text = "Show whitespace"; spaces.button_pressed = preferences.get_value("editor", "whitespace", true); column.add_child(spaces)
	dialog.confirmed.connect(func():
		preferences.set_value("editor", "font_size", int(font.value)); preferences.set_value("editor", "wrap", wrap.button_pressed); preferences.set_value("editor", "whitespace", spaces.button_pressed)
		save_preferences(); apply_preferences(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(530, 220))

func apply_preferences() -> void:
	editor.add_theme_font_size_override("font_size", clampi(int(preferences.get_value("editor", "font_size", 16)), 10, 40))
	prepare_source(editor.text)
	editor.draw_spaces = bool(preferences.get_value("editor", "whitespace", true)); editor.draw_tabs = editor.draw_spaces

func save_preferences() -> void:
	if preferences.save("user://authoring.cfg") != OK: message.text = "Editor preferences could not be saved."

# Boundaries on a multi-megabyte physical line cause quadratic layout work in
# the pinned engine. Keep every source byte; only suspend the wrap preference.
func prepare_source(value: String) -> void:
	long_line = false
	var start := 0
	while start < value.length():
		var end := value.find("\n", start)
		if end < 0: end = value.length()
		if end - start > WRAP_LINE_LIMIT:
			long_line = true
			break
		start = end + 1
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if preferences.get_value("editor", "wrap", true) and not long_line else TextEdit.LINE_WRAPPING_NONE

func _prepare_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (((event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_V) or (event.shift_pressed and event.keycode == KEY_INSERT)):
		prepare_source(editor.text + DisplayServer.clipboard_get())

static func completion_variables(values: Dictionary, prefix := "", depth := 0) -> Array[String]:
	var names: Array[String] = []
	if depth > 32: return names
	for key: Variant in values:
		if not key is String or not key.is_valid_identifier(): continue
		var path: String = prefix + String(key)
		if values[key] is Dictionary: names.append_array(completion_variables(values[key], path + ".", depth + 1))
		elif values[key] is String or values[key] is bool or values[key] is int or values[key] is float: names.append(path)
	names.sort()
	return names
