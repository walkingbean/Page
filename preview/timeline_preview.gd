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
var _workspace: RefCounted
var _runtime_characters: Dictionary = {}
var _runtime_textures: Array[ImageTexture] = []
var _previous_directory: Dictionary = {}
var _directory_active := false
var _generation := 0
var _resetting := false
var _starting := false
var _status: Label
var _advance_button: Button
var _restart_button: Button


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


func start_preview(source: String, workspace: RefCounted = null) -> Error:
	last_error = ""
	if not is_inside_tree() or _handler == null:
		last_error = "The preview window is not attached to a Dialogic project."
		return ERR_UNCONFIGURED
	if workspace != null and workspace.variable_document != null:
		var variable_problem: String = workspace.variable_document.preview_error()
		if not variable_problem.is_empty():
			last_error = variable_problem
			return ERR_UNAVAILABLE
	var validation: Dictionary = Codec.validate_content(source, workspace)
	if not validation.get("supported", false):
		last_error = "\n".join(validation.get("diagnostics", []))
		return ERR_UNAVAILABLE
	if int(validation.get("event_count", 0)) == 0:
		last_error = "Add at least one dialogue or narration event before starting preview."
		return ERR_INVALID_DATA
	var timeline: DialogicTimeline = Codec.parse_supported(source, workspace)
	if timeline == null:
		last_error = "Dialogic could not parse the supported timeline."
		return ERR_PARSE_ERROR
	var textures: Array[ImageTexture] = []
	if not _prepare_portraits(timeline, workspace, _generation + 1, textures):
		return ERR_CANT_OPEN
	_source = source
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
	hide()
	if is_instance_valid(_advance_button):
		_advance_button.disabled = true
	_clear_runtime()
	preview_closed.emit()


func advance() -> void:
	if running and is_instance_valid(_handler):
		_handler.Inputs.handle_input()


func restart() -> void:
	if not _source.is_empty() and not _starting:
		start_preview(_source, _workspace)


func _begin(timeline: DialogicTimeline, generation: int, textures: Array[ImageTexture]) -> void:
	await _clear_runtime()
	if generation != _generation or not is_inside_tree():
		return
	# Register the exact instances referenced by the native parsed events. A
	# second clone here would break Dialogic's identity-based identifier lookup.
	_previous_directory = DialogicResourceUtil.get_directory("dch")
	_runtime_characters = timeline.get_meta("preview_characters", {})
	_runtime_textures = textures
	DialogicResourceUtil.set_directory("dch", _runtime_characters)
	_directory_active = true
	# Loading under this Window keeps the upstream CanvasLayer in its viewport.
	# No editor singleton or EditorInterface is involved in the preview path.
	_layout = _handler.Styles.load_style(DEFAULT_STYLE, self)
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
	_layout.set("global_font", PREVIEW_FONT)
	_layout.apply_export_overrides()
	_starting = false
	running = true
	_advance_button.disabled = false
	_restart_button.disabled = false
	_status.text = "Enter / Space or click the dialogue to advance. Esc / F6 closes preview."
	# Full clear restores the application's defaults; replace them only in this
	# runtime instance with an independent copy of the selected content root.
	_handler.VAR.var_storage = timeline.get_meta("preview_variables", {}).duplicate(true)
	_handler.start_timeline(timeline)
	preview_ready.emit()


func _clear_runtime() -> void:
	if _resetting:
		await _reset_completed
		return
	if not is_instance_valid(_handler):
		return
	_resetting = true
	# Native timeline cleanup yields one frame before disconnecting suspended
	# event signals. Detach the old text nodes first so a finishing reveal cannot
	# resume an old event after clear() has reset its timeline index to -1.
	_discard_layout()
	_handler.paused = false
	_handler.Inputs.stop_timers()
	_handler.Inputs.auto_skip.enabled = false
	_handler.Inputs.auto_advance.enabled_forced = false
	_handler.Inputs.auto_advance.enabled_until_user_input = false
	_handler.Inputs.auto_advance.enabled_until_next_event = false
	# DialogicTimeline.clean() waits one frame; awaiting it prevents an older
	# cleanup coroutine from wiping the next preview's timeline.
	await _handler.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	_restore_resources()
	_resetting = false
	_reset_completed.emit()


func _prepare_portraits(timeline: DialogicTimeline, workspace: RefCounted, generation: int, textures: Array[ImageTexture]) -> bool:
	var characters: Dictionary = timeline.get_meta("preview_characters", {})
	for identifier: String in characters:
		var character: DialogicCharacter = characters[identifier]
		for portrait_name: String in character.portraits:
			var portrait: Dictionary = character.portraits[portrait_name]
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
	if _directory_active:
		DialogicResourceUtil.set_directory("dch", _previous_directory)
	_directory_active = false
	_previous_directory = {}
	_runtime_characters = {}
	# Clear cache ownership immediately, even if a queued layout still retains a
	# texture for the remainder of this frame. No virtual path survives a stop.
	for texture: ImageTexture in _runtime_textures:
		texture.resource_path = ""
	_runtime_textures.clear()


func _discard_layout() -> void:
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
	if key.keycode in [KEY_ESCAPE, KEY_F6]:
		set_input_as_handled()
		stop_preview()
	elif key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
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
	trace.append(info)
	event_observed.emit(info)


func _on_text_started(info: Dictionary) -> void:
	if not running:
		return
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


func _on_timeline_ended() -> void:
	if not running:
		return
	running = false
	_starting = false
	_advance_button.disabled = true
	_status.text = "Timeline finished. Restart to play again, or close this window."
	preview_finished.emit()


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
	# The supported linear preview does not need the underlying choice/history UI.
	var input_surface := Control.new()
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
	_advance_button = Button.new()
	_advance_button.text = "Advance"
	_advance_button.focus_mode = Control.FOCUS_NONE
	_advance_button.pressed.connect(advance)
	row.add_child(_advance_button)
	_restart_button = Button.new()
	_restart_button.text = "Restart"
	_restart_button.focus_mode = Control.FOCUS_NONE
	_restart_button.pressed.connect(restart)
	row.add_child(_restart_button)
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
