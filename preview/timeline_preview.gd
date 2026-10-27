class_name TimelinePreview
extends Window
## An isolated preview window backed by the upstream Dialogic runtime and VN layout.
## References: https://docs.dialogic.pro/creating-timelines-in-code
## https://docs.dialogic.pro/styles-and-layouts.html
## https://docs.godotengine.org/en/stable/classes/class_window.html

signal preview_closed
signal preview_ready
signal preview_finished
signal event_observed(info: Dictionary)
signal text_observed(text: String)
signal question_observed(info: Dictionary)
signal _reset_completed

const Codec = preload("res://application/timeline_codec.gd")
const Identity = preload("res://application/app_identity.gd")
const DEFAULT_STYLE := "res://addons/dialogic/Modules/DefaultLayoutParts/Style_VN_Default/default_vn_style.tres"
const PREVIEW_FONT := "res://preview/preview_font.tres"

var running := false
var last_error := ""
var trace: Array[Dictionary] = []
var displayed_texts: Array[String] = []
var displayed_characters: Array[Dictionary] = []
var _handler: DialogicGameHandler
var _layout: Node
var _source := ""
var _source_path := ""
var _runtime_root: DialogicTimeline
var _timeline_directory: Dictionary = {}
var _had_timeline_directory := false
var _choice_default := 0
var _steps_without_input := 0
var _input_surface: Control
var _choice_canvas: CanvasLayer
var _workspace: RefCounted
var _runtime_characters: Dictionary = {}
var _runtime_textures: Array[Resource] = []
var _previous_directory: Dictionary = {}
var _directory_active := false
var _generation := 0
var _resetting := false
var _starting := false
var _status: Label
var _advance_button: Button
var _restart_button: Button
var _auto_button: CheckButton
var _skip_button: CheckButton
var _media: RefCounted
var _state_panel: Window
var _presentation: RefCounted
var _layout_generation := 0


func _init() -> void:
	name = "TimelinePreview"
	title = Identity.preview_title()
	size = Vector2i(1000, 600)
	min_size = Vector2i(640, 400)
	transient = true
	exclusive = true
	visible = false


func _ready() -> void:
	_handler = get_node_or_null("/root/Dialogic") as DialogicGameHandler
	_build_chrome()
	close_requested.connect(stop_preview)
	window_input.connect(_on_window_input)
	if _handler == null:
		last_error = "The Dialogic runtime autoload is unavailable."
		_status.text = last_error
		return
	# The preview window owns keyboard input. Root-viewport input must not advance
	# a timeline while the user edits a document or a modal dialog is open.
	_handler.Inputs.set_process_input(false)
	_handler.Inputs.set_process_unhandled_input(false)
	_handler.event_handled.connect(_on_event_handled)
	_handler.Text.text_started.connect(_on_text_started)
	_handler.timeline_ended.connect(_on_timeline_ended)
	_handler.Choices.question_shown.connect(_on_question_shown)
	_handler.TextInput.input_shown.connect(_on_text_input_shown)
	_handler.Styles.style_changed.connect(_on_style_changed)
	_handler.Inputs.auto_skip.toggled.connect(func(value: bool): _skip_button.set_pressed_no_signal(value))
	_handler.Inputs.auto_advance.toggled.connect(func(value: bool): _auto_button.set_pressed_no_signal(value))


func start_preview(source: String, workspace: RefCounted = null, source_path: String = "") -> Error:
	last_error = ""
	if not is_inside_tree() or _handler == null:
		last_error = "The preview window is not attached to a Dialogic project."
		return ERR_UNCONFIGURED
	if workspace != null and workspace.variable_document != null:
		var variable_problem: String = workspace.variable_document.preview_error()
		if not variable_problem.is_empty():
			last_error = variable_problem
			return ERR_UNAVAILABLE
	if workspace != null and workspace.text_settings != null:
		var settings_problem: String = workspace.text_settings.preview_error()
		if not settings_problem.is_empty():
			last_error = settings_problem
			return ERR_UNAVAILABLE
	var validation: Dictionary = Codec.validate_content(source, workspace, source_path)
	if not validation.get("supported", false):
		last_error = "\n".join(validation.get("diagnostics", []))
		return ERR_UNAVAILABLE
	if int(validation.get("event_count", 0)) == 0 and not _has_interaction_source(source):
		last_error = "Add at least one dialogue or narration event before starting preview."
		return ERR_INVALID_DATA
	var timeline: DialogicTimeline = Codec.parse_supported(source, workspace, source_path)
	if timeline == null:
		last_error = "Dialogic could not parse the supported timeline."
		return ERR_PARSE_ERROR
	var textures: Array[Resource] = []
	if not _prepare_portraits(timeline, workspace, _generation + 1, textures):
		Codec.GRAPH.release(timeline)
		return ERR_CANT_OPEN
	_source = source
	_source_path = source_path
	_workspace = workspace
	_generation += 1
	_starting = true
	running = false
	trace.clear()
	displayed_texts.clear()
	displayed_characters.clear()
	_status.text = "Preparing Dialogic preview…"
	_advance_button.disabled = true
	_restart_button.disabled = true
	popup_centered(size)
	_begin.call_deferred(timeline, _generation, textures)
	return OK


func stop_preview() -> void:
	_generation += 1
	_starting = false
	running = false
	if is_instance_valid(_state_panel): _state_panel.hide()
	hide()
	if is_instance_valid(_advance_button):
		_advance_button.disabled = true
	_clear_runtime()
	preview_closed.emit()


func advance() -> void:
	if running and is_instance_valid(_handler) and not _text_input_visible() and _handler.current_state != _handler.States.AWAITING_CHOICE:
		_handler.Inputs.handle_input()


func restart() -> void:
	if not _source.is_empty() and not _starting:
		start_preview(_source, _workspace, _source_path)


func _begin(timeline: DialogicTimeline, generation: int, textures: Array[Resource]) -> void:
	await _clear_runtime()
	if generation != _generation or not is_inside_tree():
		Codec.GRAPH.release(timeline)
		for texture: Resource in textures:
			texture.resource_path = ""
		return
	# Register the exact instances referenced by the native parsed events. A
	# second clone here would break Dialogic's identity-based identifier lookup.
	_previous_directory = DialogicResourceUtil.get_directory("dch")
	_runtime_characters = timeline.get_meta("preview_characters", {})
	_runtime_textures = textures
	_runtime_root = timeline
	_had_timeline_directory = Engine.has_meta("dtl_directory")
	_timeline_directory = Engine.get_meta("dtl_directory", {})
	_choice_default = _handler.Choices.default_false_behaviour
	if timeline.has_meta("flow_preview"):
		var resources: Dictionary = timeline.get_meta("preview_timelines", {}).duplicate()
		resources[timeline.get_meta("source_path")] = timeline
		var directory := {}
		for alias: String in timeline.get_meta("preview_timeline_aliases", {}):
			directory[alias] = resources[timeline.get_meta("preview_timeline_aliases")[alias]]
		Engine.set_meta("dtl_directory", directory)
		_handler.Choices.default_false_behaviour = timeline.get_meta("preview_choice_default", 0)
	DialogicResourceUtil.set_directory("dch", _runtime_characters)
	_directory_active = true
	_presentation = preload("res://preview/presentation_session.gd").new()
	var presentation_error: Error = _presentation.begin(self, _handler, _workspace, generation)
	if presentation_error != OK:
		last_error = _presentation.last_error
		_status.text = last_error
		_starting = false
		_restart_button.disabled = false
		_restore_resources()
		return
	for character: DialogicCharacter in _runtime_characters.values():
		if character.custom_info.get("style", "") is String:
			character.custom_info["style"] = _presentation.remap_style_reference(character.custom_info.get("style", ""))
	var all_timelines: Array = timeline.get_meta("preview_timelines", {}).values()
	all_timelines.append(timeline)
	for item: DialogicTimeline in all_timelines:
		for event: DialogicEvent in item.events:
			if event is DialogicStyleEvent: event.style_name = _presentation.remap_style_reference(event.style_name)
	_localization = preload("res://preview/localization_session.gd").new()
	if _localization.begin(_handler, _workspace, preview_locale, self) != OK:
		last_error = _localization.last_error; _status.text = last_error; _starting = false; _restart_button.disabled = false; _restore_resources(); return
	_locale_picker.clear()
	for locale: String in _localization.locales:
		_locale_picker.add_item(locale)
		if locale == TranslationServer.get_locale(): _locale_picker.select(_locale_picker.item_count - 1)
	_media = preload("res://preview/media_session.gd").new()
	if _media.begin(self, _handler, _workspace, timeline, _presentation) != OK:
		last_error = _media.last_error; _status.text = last_error; _starting = false; _restart_button.disabled = false; _restore_resources(); return
	# Loading under this Window keeps the upstream CanvasLayer in its viewport.
	# No editor singleton or EditorInterface is involved in the preview path.
	_layout = _handler.Styles.load_style("", self)
	if _layout == null:
		_starting = false
		last_error = "The original Dialogic VN layout could not be loaded."
		_status.text = last_error
		_restart_button.disabled = false
		_restore_resources()
		return
	if not _layout.is_node_ready():
		await _layout.ready
	if generation != _generation or not is_inside_tree():
		return
	# Keep the upstream layout and Latin face, adding a bundled CJK fallback.
	_apply_layout_font()
	_prepare_native_choices()
	if timeline.has_meta("flow_preview") and (_workspace == null or _workspace.style_catalog.styles.is_empty()):
		_prepare_choice_controls(int(timeline.get_meta("preview_max_choices", 1)))
	_starting = false
	running = true
	_advance_button.disabled = false
	_restart_button.disabled = false
	_status.text = "Enter / Space or click the dialogue to advance. Esc / F6 closes preview."
	# Full clear restores the application's defaults; replace them only in this
	# runtime instance with an independent copy of the selected content root.
	_handler.VAR.var_storage = timeline.get_meta("preview_variables", {}).duplicate(true)
	_steps_without_input = 0
	_input_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	_handler.set("preview_guard", _guard_event)
	_handler.start_timeline(timeline)
	preview_ready.emit()


func _clear_runtime() -> void:
	if _resetting:
		await _reset_completed
		return
	if not is_instance_valid(_handler):
		return
	_resetting = true
	# An idle clear also runs before the first preview and after it has closed.
	# Preserve application history until the media session can snapshot it.
	# Active sessions restore their own snapshot in _restore_resources().
	var idle_history := {}
	var idle_glossaries: Array = _handler.Glossary.glossaries.duplicate() if _localization == null else []
	if _media == null:
		for field: String in ["simple_history_content", "full_event_history_content"]:
			idle_history[field] = _handler.History.get(field).duplicate(true)
	# Alpha 20 keeps animation nodes under Portraits, separately from the
	# layout. Stop their completion signals before removing their target nodes.
	# This also releases repeating animations on close and restart.
	for animation: Node in _handler.Portraits.get_children():
		if animation is DialogicAnimation:
			animation.set_block_signals(true)
			animation.queue_free()
	# Background transitions also outlive their layout in Alpha 20. Cancel
	# their callbacks before removing the viewports they animate.
	for transition: Node in _handler.Backgrounds.get_children():
		if transition is DialogicBackgroundTransition:
			transition.set_block_signals(true)
			transition.queue_free()
	# Native timeline cleanup yields one frame before disconnecting suspended
	# event signals. Detach the old text nodes first so a finishing reveal cannot
	# resume an old event after clear() has reset its timeline index to -1.
	_discard_layout()
	if _media != null and is_instance_valid(_media.save_node): _media.save_node.autosave_enabled = false
	if _presentation != null: _presentation.disconnect_waits()
	_handler.Inputs.stop_timers()
	_handler.Inputs.auto_skip.enabled = false
	_handler.Inputs.auto_advance.enabled_forced = false
	_handler.Inputs.auto_advance.enabled_until_user_input = false
	_handler.Inputs.auto_advance.enabled_until_next_event = false
	# DialogicTimeline.clean() waits one frame; awaiting it prevents an older
	# cleanup coroutine from wiping the next preview's timeline.
	await _handler.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	if _localization == null: _handler.Glossary.glossaries = idle_glossaries
	# Native Backgrounds.clear() returns early when no holder remains. Reset
	# its identity explicitly so a new preview using the same color creates
	# a real background instead of taking the native unchanged-value shortcut.
	_handler.Backgrounds.scene = ""
	_handler.Backgrounds.argument = ""
	# Resume only after native portrait state is empty. The native paused
	# setter invokes _resume even when already false; stale animation metadata
	# must never be resumed during teardown.
	if _handler.paused:
		_handler.paused = false
	_restore_resources()
	for field: String in idle_history:
		_handler.History.set(field, idle_history[field])
	_resetting = false
	_reset_completed.emit()


func _prepare_portraits(timeline: DialogicTimeline, workspace: RefCounted, generation: int, textures: Array[Resource]) -> bool:
	var characters: Dictionary = timeline.get_meta("preview_characters", {})
	for identifier: String in characters:
		var character: DialogicCharacter = characters[identifier]
		for portrait_name: String in character.portraits:
			var portrait: Dictionary = character.portraits[portrait_name]
			var scene_path: String = portrait.get("scene", "")
			if not scene_path.is_empty() and not scene_path.begins_with("res://addons/"):
				var layers = preload("res://application/layered_portrait_document.gd")
				var checked: Dictionary = layers.inspect_path(scene_path, workspace)
				if not checked.supported:
					last_error = " ".join(checked.diagnostics)
					return false
				var packed: PackedScene = layers.runtime_scene(checked.model, workspace)
				if packed == null:
					last_error = "A layered portrait dependency changed during preview preparation."
					return false
				var virtual_scene := "res://__preview_cache_%d/%d/%d.tscn" % [get_instance_id(), generation, textures.size()]
				packed.take_over_path(virtual_scene)
				textures.append(packed)
				portrait["scene"] = virtual_scene
				continue
			var overrides: Dictionary = portrait.get("export_overrides", {})
			var logical_path: String = overrides.get("image", "")
			# Alpha 20's editor stores exported strings using var_to_str; its
			# programmatic add_portrait API also accepts a plain string path.
			if logical_path.begins_with('"'):
				var decoded: Variant = str_to_var(logical_path)
				logical_path = decoded if decoded is String else ""
			if logical_path.is_empty():
				continue
			var absolute_path: String = workspace.resolve_content_path(logical_path) if workspace != null else ""
			if absolute_path.is_empty() or not FileAccess.file_exists(absolute_path):
				last_error = "Cannot resolve the portrait for character %s: %s" % [identifier, logical_path]
				return false
			var image := Image.load_from_file(absolute_path)
			if image == null or image.is_empty():
				last_error = "Cannot load the portrait PNG for character %s: %s" % [identifier, logical_path]
				return false
			var texture := ImageTexture.create_from_image(image)
			# The unchanged upstream default portrait uses ResourceLoader.exists/load.
			# A scoped cache path lets it consume an external, unimported PNG in an
			# exported application. Only runtime clones receive this temporary path.
			var cache_path := "res://__preview_cache_%d/%d/%d.png" % [get_instance_id(), generation, textures.size()]
			texture.take_over_path(cache_path)
			textures.append(texture)
			overrides["image"] = var_to_str(cache_path)
			portrait["export_overrides"] = overrides
			character.portraits[portrait_name] = portrait
	return true


func _restore_resources() -> void:
	if _localization != null: _localization.restore(); _localization = null
	if _media != null: _media.restore()
	if _presentation != null:
		_presentation.restore()
		_presentation = null
	if _media != null:
		_media.restore_history_connections(); _media = null
	if _runtime_root != null:
		if _had_timeline_directory:
			Engine.set_meta("dtl_directory", _timeline_directory)
		else:
			Engine.remove_meta("dtl_directory")
		_handler.Choices.default_false_behaviour = _choice_default
		_handler.set("preview_guard", Callable())
		Codec.GRAPH.release(_runtime_root)
		_runtime_root = null
		_timeline_directory = {}
	if _directory_active:
		DialogicResourceUtil.set_directory("dch", _previous_directory)
	_directory_active = false
	_previous_directory = {}
	_runtime_characters = {}
	# Clear cache ownership immediately, even if a queued layout still retains a
	# texture for the remainder of this frame. No virtual path survives a stop.
	for texture: Resource in _runtime_textures:
		texture.resource_path = ""
	_runtime_textures.clear()


func _discard_layout() -> void:
	if is_instance_valid(_choice_canvas):
		_choice_canvas.get_parent().remove_child(_choice_canvas)
		_choice_canvas.queue_free()
	_choice_canvas = null
	var current_layout: Node = _handler.Styles.get_layout_node() if is_instance_valid(_handler) else null
	if is_instance_valid(current_layout): _layout = current_layout
	if is_instance_valid(_layout):
		# Text reveal sounds can still be playing when a preview is closed.
		# Release their audio-server playback before freeing the layout.
		for player: Node in _layout.find_children("*", "AudioStreamPlayer", true, false):
			(player as AudioStreamPlayer).stop()
			(player as AudioStreamPlayer).stream = null
		if _layout.get_parent() != null:
			_layout.get_parent().remove_child(_layout)
		_layout.queue_free()
	_layout = null
	if get_tree() != null and get_tree().has_meta("dialogic_layout_node"):
		get_tree().remove_meta("dialogic_layout_node")
	if Engine.has_meta("dialogic_persistent_style_info"):
		Engine.remove_meta("dialogic_persistent_style_info")


func _on_window_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if is_instance_valid(_locale_picker) and _locale_picker.get_popup().visible: return
	if key.keycode in [KEY_ESCAPE, KEY_F6]:
		set_input_as_handled()
		stop_preview()
	elif (is_instance_valid(_state_panel) and _state_panel.visible) or _text_input_visible():
		return
	elif is_instance_valid(_locale_picker) and _locale_picker.has_focus() and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		return
	elif key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _handler.current_state != _handler.States.AWAITING_CHOICE:
		set_input_as_handled()
		advance()


func _on_preview_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		advance()
		set_input_as_handled()


func _on_event_handled(event: DialogicEvent) -> void:
	if not running:
		return
	var info := {
		"index": _handler.current_event_idx,
		"event_name": event.event_name,
		"script": event.get_script().resource_path,
		"source": event.event_node_as_text,
	}
	info["timeline"] = _handler.current_timeline.get_meta("source_path", "") if _handler.current_timeline != null else ""
	trace.append(info)
	event_observed.emit(info)


func _on_text_started(info: Dictionary) -> void:
	if not running:
		return
	_steps_without_input = 0
	_input_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	_advance_button.disabled = false
	var text := str(info.get("text", ""))
	displayed_texts.append(text)
	var character: DialogicCharacter = info.get("character")
	displayed_characters.append({
		"identifier": character.get_identifier() if character != null else "",
		"display_name": character.display_name if character != null else "",
		"color": character.color.to_html() if character != null else "",
		"registered_instance": character != null and _runtime_characters.get(character.get_identifier()) == character,
	})
	text_observed.emit(text)


func _abort_presentation(problem: String) -> void:
	if not running: return
	last_error = problem
	_status.text = problem
	running = false
	_handler.Inputs.stop_timers()
	_handler.paused = true
	_advance_button.disabled = true
	_restart_button.disabled = false

func _on_timeline_ended() -> void:
	if not running:
		return
	running = false
	_starting = false
	_advance_button.disabled = true
	_status.text = "Timeline finished. Restart to play again, or close this window."
	preview_finished.emit()


var _localization: RefCounted
var _locale_picker: OptionButton
var preview_locale := ""

func _build_chrome() -> void:
	var background := ColorRect.new()
	background.color = Color("202126")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var chrome := CanvasLayer.new()
	chrome.layer = 100
	add_child(chrome)
	# Route clicks once, without relying on Input's root-viewport action state.
	# Native choice controls receive input while a question is active.
	var input_surface := Control.new()
	_input_surface = input_surface
	input_surface.name = "PreviewInputSurface"
	input_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_surface.offset_top = 58
	input_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	input_surface.gui_input.connect(_on_preview_click)
	chrome.add_child(input_surface)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 58
	chrome.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	_status = Label.new()
	_status.text = "Dialogic preview"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 14)
	row.add_child(_status)
	_locale_picker = OptionButton.new(); _locale_picker.name = "PreviewLocale"; _locale_picker.tooltip_text = "Change language and restart this preview"; row.add_child(_locale_picker)
	# Fixed 4.7.1 release templates mis-handle embedded Popup signal cleanup.
	preload("res://ui/components/native_popup.gd").configure(_locale_picker)
	_locale_picker.item_selected.connect(func(index: int): preview_locale = _locale_picker.get_item_text(index); restart())
	_advance_button = Button.new()
	_advance_button.text = "Advance"
	_advance_button.focus_mode = Control.FOCUS_NONE
	_advance_button.pressed.connect(advance)
	row.add_child(_advance_button)
	_auto_button = CheckButton.new()
	_auto_button.name = "AutoAdvance"
	_auto_button.text = "Auto"
	_auto_button.focus_mode = Control.FOCUS_NONE
	_auto_button.toggled.connect(func(value: bool):
		if running: _handler.Inputs.auto_advance.enabled_forced = value)
	row.add_child(_auto_button)
	_skip_button = CheckButton.new()
	_skip_button.name = "AutoSkip"
	_skip_button.text = "Skip"
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.toggled.connect(func(value: bool):
		if running: _handler.Inputs.auto_skip.enabled = value)
	row.add_child(_skip_button)
	_restart_button = Button.new()
	_restart_button.text = "Restart"
	_restart_button.focus_mode = Control.FOCUS_NONE
	_restart_button.pressed.connect(restart)
	row.add_child(_restart_button)
	var state_button := Button.new(); state_button.name = "HistoryAndSaves"; state_button.text = "History / Saves"; state_button.focus_mode = Control.FOCUS_NONE; row.add_child(state_button)
	_state_panel = preload("res://ui/components/preview_state_panel.gd").new(); add_child(_state_panel)
	state_button.pressed.connect(func(): _state_panel.open_panel(self))
	var stop_button := Button.new()
	stop_button.text = "Close"
	stop_button.focus_mode = Control.FOCUS_NONE
	stop_button.pressed.connect(stop_preview)
	row.add_child(stop_button)


func _exit_tree() -> void:
	_generation += 1
	running = false
	if is_instance_valid(_handler):
		if _handler.event_handled.is_connected(_on_event_handled):
			_handler.event_handled.disconnect(_on_event_handled)
		if _handler.Text.text_started.is_connected(_on_text_started):
			_handler.Text.text_started.disconnect(_on_text_started)
		if _handler.timeline_ended.is_connected(_on_timeline_ended):
			_handler.timeline_ended.disconnect(_on_timeline_ended)
		_handler.Inputs.stop_timers()
		_handler.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	_restore_resources()


func _on_question_shown(info: Dictionary) -> void:
	if not running:
		return
	_input_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_advance_button.disabled = true
	_status.text = "Choose an available option. Esc / F6 closes preview."
	if not info.get("invalid", false):
		_steps_without_input = 0
	question_observed.emit(info)


func _guard_event(timeline: DialogicTimeline, index: int) -> bool:
	if not running:
		return false
	_steps_without_input += 1
	var problem := ""
	if _steps_without_input > 10000:
		problem = "Preview stopped after 10000 events without user interaction. Check for a jump loop."
	elif _handler.Jump.jump_stack.size() >= 1024 and timeline.events[index] is DialogicJumpEvent:
		problem = "Preview jump stack exceeds 1024 calls. Check for recursion without Return."
	else:
		problem = _runtime_problem(timeline, index)
	if problem.is_empty():
		return true
	var lines: Array = timeline.get_meta("source_lines", [])
	var source_line: int = lines[index] if index < lines.size() else 0
	last_error = "%s · line %d: %s" % [timeline.get_meta("source_path", "Current timeline"), source_line, problem]
	_status.text = last_error
	running = false
	_starting = false
	_advance_button.disabled = true
	_restart_button.disabled = false
	_input_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	_handler.Choices.hide_all_choices()
	return false


func _layout_dependency_error(event: DialogicEvent, needs_choice := false) -> String:
	if not (event is DialogicTextEvent or event is DialogicChoiceEvent or event is DialogicTextInputEvent): return ""
	var name: String = _handler.Styles.style
	if event is DialogicTextEvent:
		name = _handler.Styles.base_style
		if event.character != null and not str(event.character.custom_info.get("style", "")).is_empty(): name = event.character.custom_info.style
	var style: DialogicStyle = DialogicStylesUtil.get_style(name)
	var available: Dictionary = load("res://application/style_catalog.gd").presentation_capabilities(style)
	if event is DialogicTextEvent and not available.text: return "This style has no usable text layer. Add a native textbox layer, or pair the Text Bubble base with its Textbubble layer."
	if (event is DialogicChoiceEvent or needs_choice) and not available.choice: return "This style has no choice layer. Add a native choices layer before previewing choices."
	if event is DialogicTextInputEvent and not available.input: return "This style has no TextInput layer. Add the native TextInput layer before previewing this event."
	return ""

func _runtime_problem(timeline: DialogicTimeline, index: int) -> String:
	var event: DialogicEvent = timeline.events[index]
	var values: Dictionary = _handler.VAR.var_storage
	var needs_choice := event is DialogicTextEvent and index + 1 < timeline.events.size() and timeline.events[index + 1] is DialogicChoiceEvent
	var presentation_error := _layout_dependency_error(event, needs_choice)
	if not presentation_error.is_empty(): return presentation_error
	var check := {}
	if event is DialogicVariableEvent:
		check = Codec.ASSIGNMENT.inspect_event(event.event_node_as_text, values, true)
	elif event is DialogicConditionEvent:
		check = Codec.CONDITIONS.inspect_event(event.event_node_as_text, values, true)
	elif event is DialogicTextEvent:
		var prefix: String = ProjectSettings.get_setting("dialogic/text/dialog_text_prefix", "")
		var suffix := ""
		if event.character != null:
			var name_check := preload("res://application/text_variables.gd").inspect(event.character.get_display_name_translated(), _workspace, values, true)
			if name_check.has("error"): return "Translated character name: " + name_check.error
			prefix += str(event.character.custom_info.get("prefix", ""))
			suffix = str(event.character.custom_info.get("suffix", ""))
		check = Codec.INLINE.inspect(prefix + event.get_property_translated("text") + suffix, _workspace, values, true)
		if not check.has("error"):
			# Native playback clones point to scoped cache scenes. Validate the
			# content resource that produced this exact registered clone instead.
			var content_character: DialogicCharacter = null
			if event.character != null:
				for identifier: String in _runtime_characters:
					if _runtime_characters[identifier] == event.character:
						content_character = _workspace.get_character(identifier) if _workspace != null else null
						break
				if content_character == null: return "The preview speaker no longer matches a validated content character."
			var active_portrait: String = event.portrait
			if content_character != null and active_portrait.is_empty():
				active_portrait = _handler.Portraits.portraits.get(event.character.get_identifier(), {}).get("portrait", content_character.default_portrait)
			check = Codec.PRESENTATION.inspect(check.get("expanded", event.text), _workspace, content_character, true, active_portrait)
	elif not Codec.INTERACTION.kind_of(event).is_empty():
		check = Codec.INTERACTION.inspect(event.event_node_as_text, event, _workspace, values, true)
		if not check.has("error"):
			var transition_error: String = Codec.INTERACTION.setting_transition_error(check, _handler.Settings.settings)
			if not transition_error.is_empty(): check = {"error": transition_error}
	elif event is DialogicJumpEvent:
		check = Codec.FLOW.inspect(event.event_node_as_text, event, _workspace, values, true)
		if not check.has("error") and not check.expanded_label.is_empty():
			var destination: DialogicTimeline = event.timeline if event.timeline != null else timeline
			if not destination.get_meta("labels", {}).has(check.expanded_label):
				check = {"error": "Label '%s' was not found in %s." % [check.expanded_label, destination.get_meta("source_path")]}
	if check.has("error"):
		return check.error
	# A Text event can reveal its following question before the Choice event
	# executes. Check every sibling option before either native entry point.
	var first := index + 1 if event is DialogicTextEvent else index
	if first < timeline.events.size() and timeline.events[first] is DialogicChoiceEvent:
		var previous := _handler.current_event_idx
		_handler.current_event_idx = first
		var choices: Array = _handler.Choices.get_current_choice_indexes()
		_handler.current_event_idx = previous
		for choice_index: int in choices:
			var option: DialogicEvent = timeline.events[choice_index]
			check = Codec.FLOW.inspect(option.event_node_as_text, option, _workspace, values, true)
			if check.has("error"):
				return "Choice at line %d: %s" % [timeline.get_meta("source_lines")[choice_index], check.error]
			for property: String in ["text", "disabled_text"]:
				var translated: String = option.get_property_translated(property)
				check = Codec.INLINE.inspect(translated.replace("\\|", "|"), _workspace, values, false)
				if check.has("error"): return "Translated choice at line %d: %s" % [timeline.get_meta("source_lines")[choice_index], check.error]
			var condition := {"value": true} if option.condition.is_empty() else preload("res://application/scalar_expression.gd").inspect(option.condition, values, true, false)
			var shown := "text" if condition.get("value", false) or option.disabled_text.is_empty() else "disabled_text"
			check = Codec.INLINE.inspect(option.get_property_translated(shown).replace("\\|", "|"), _workspace, values, true)
			if check.has("error"): return "Translated choice at line %d: %s" % [timeline.get_meta("source_lines")[choice_index], check.error]
	return ""


func _prepare_choice_controls(count: int) -> void:
	var choice_theme: Theme
	for node: Node in _layout.find_children("*", "Control", true, false):
		if node.has_method("get_choices"):
			choice_theme = node.theme
			node.get_choices().hide()
	_choice_canvas = CanvasLayer.new()
	_choice_canvas.layer = 50
	add_child(_choice_canvas)
	var scroll := ScrollContainer.new()
	scroll.name = "PreviewChoices"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 70
	scroll.offset_right = -70
	scroll.offset_top = 90
	scroll.offset_bottom = -160
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_choice_canvas.add_child(scroll)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 10)
	choices.theme = choice_theme
	scroll.add_child(choices)
	for index: int in count:
		var button := DialogicNode_ChoiceButton.new()
		button.name = "PreviewChoice%d" % (index + 1)
		button.custom_minimum_size.y = 40
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices.add_child(button)


static func _has_interaction_source(source: String) -> bool:
	return RegEx.create_from_string("(?m)^\\s*(?:\\[(?:wait|wait_input|text_input|style|clear|background|voice|history|save)\\b|setting\\b|audio\\b|\\[end)").search(source) != null

func _text_input_visible() -> bool:
	if not is_instance_valid(_handler): return false
	for node: Node in get_tree().get_nodes_in_group("dialogic_text_input"):
		if node is CanvasItem and node.is_visible_in_tree(): return true
	return false

func _on_text_input_shown(_info: Dictionary) -> void:
	if not running: return
	_steps_without_input = 0
	_input_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_advance_button.disabled = true
	_status.text = "Enter a value and confirm. Esc / F6 closes preview."

func _on_style_changed(_info: Dictionary) -> void:
	if not running and not _starting: return
	_layout_generation += 1
	_adopt_layout.call_deferred(_generation, _layout_generation)

func _adopt_layout(generation: int, layout_generation: int) -> void:
	var layout: Node = _handler.Styles.get_layout_node()
	if not is_instance_valid(layout): return
	if not layout.is_node_ready(): await layout.ready
	if generation != _generation or layout_generation != _layout_generation or not is_instance_valid(layout): return
	_layout = layout
	_apply_layout_font()
	_prepare_native_choices()
	if is_instance_valid(_choice_canvas):
		_choice_canvas.get_parent().remove_child(_choice_canvas)
		_choice_canvas.queue_free()
		_choice_canvas = null
	if _runtime_root != null and _runtime_root.has_meta("flow_preview") and (_workspace == null or _workspace.style_catalog.styles.is_empty()):
		_prepare_choice_controls(int(_runtime_root.get_meta("preview_max_choices", 1)))

func _apply_layout_font() -> void:
	if not is_instance_valid(_layout): return
	# Alpha 20 TextInput creates a Theme but does not assign a new one.
	# Supply a local Theme first so its native font-setting method can apply.
	for layer: Node in _layout.get_layers():
		if layer.get_script().resource_path == "res://addons/dialogic/Modules/DefaultLayoutParts/Layer_TextInput/text_input_layer.gd" and layer.get("theme") == null:
			layer.set("theme", Theme.new())
			layer.apply_export_overrides()
	if "global_font" in _layout and str(_layout.get("global_font")).is_empty():
		_layout.set("global_font", PREVIEW_FONT)
		_layout.apply_export_overrides()

func _prepare_native_choices() -> void:
	if _runtime_root == null or _workspace == null or _workspace.style_catalog.styles.is_empty(): return
	var count: int = _runtime_root.get_meta("preview_max_choices", 1)
	for layer: Node in _layout.get_layers():
		if not layer.has_method("get_choices"): continue
		var choices: VBoxContainer = layer.get_choices()
		if count <= int(layer.get("maximum_choices")): continue
		# Reuse the native layer/theme and native choice buttons. Add overflow
		# controls to a scroll container without changing saved style properties.
		var scroll := ScrollContainer.new(); scroll.name = "PAGEChoiceOverflow"
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.offset_top = 72; scroll.offset_bottom = -150
		scroll.offset_left = 50; scroll.offset_right = -50
		scroll.follow_focus = true; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		layer.add_child(scroll)
		choices.reparent(scroll); choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for index: int in range(choices.get_child_count(), count):
			var button := DialogicNode_ChoiceButton.new()
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size = layer.get("boxes_min_size")
			choices.add_child(button)


func report_save_error(message: String) -> void:
	_status.text = "Preview save: " + message

func report_localization_error(message: String) -> void:
	last_error = message
	_status.text = message

func restore_saved_state(state: DialogicSaveState) -> void:
	if _media == null: return
	var save: Node = _media.save_node
	if _starting:
		save.load_pending = false; save.last_error = "Preview is still starting."; save.load_completed.emit(ERR_BUSY); return
	var generation := _generation
	_starting = true
	running = false
	var enabled: bool = _media.save_node.autosave_enabled
	_media.save_node.autosave_enabled = false
	_discard_layout()
	await _handler.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	if _media == null or generation != _generation: return
	running = true
	var variable_defaults: Variant = ProjectSettings.get_setting("dialogic/variables", {})
	ProjectSettings.set_setting("dialogic/variables", {})
	await _handler.load_full_state(state)
	ProjectSettings.set_setting("dialogic/variables", variable_defaults)
	await get_tree().process_frame
	await get_tree().process_frame
	if _media == null or generation != _generation: return
	_layout = _handler.Styles.get_layout_node()
	if is_instance_valid(_layout) and _layout.get_parent() != self: _layout.reparent(self)
	if is_instance_valid(_layout): _apply_layout_font(); _prepare_native_choices()
	_media.save_node.autosave_enabled = enabled
	_starting = false
	if not running and not last_error.is_empty():
		save.load_pending = false
		save.last_error = last_error
		save.load_completed.emit(ERR_INVALID_DATA)
		return
	_advance_button.disabled = false
	_status.text = "Loaded preview state. Advance to continue."
	save.load_pending = false
	save.load_completed.emit(OK)
