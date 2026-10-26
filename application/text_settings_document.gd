extends "res://application/timeline_document.gd"

const Data = preload("res://application/variable_document.gd")
const Native = preload("res://application/native_resource.gd")
const DEFAULTS := {
	"audio/type_sound_bus":"Master", "audio/channel_defaults":{"":{"volume":0.0,"audio_bus":"","fade_length":0.0,"loop":false}, "music":{"volume":0.0,"audio_bus":"","fade_length":0.0,"loop":true}},
	"history/simple_history_enabled":false, "history/simple_history_save":false, "history/full_history_enabled":false, "history/full_history_save":false, "history/visited_event_history_enabled":false, "history/save_on_save":false, "history/save_on_autosave":false,
	"save/autosave":false, "save/autosave_mode":0, "save/autosave_delay":60, "save/default_slot":"Default", "save/encryption_password":"", "save/encryption_on_exports_only":true,
	"text/letter_speed": 0.01, "text/input_action": "dialogic_default_action",
	"text/initial_text_reveal_skippable": true, "text/text_reveal_skip_delay": 0.1,
	"text/advance_delay": 0.1, "text/autocolor_names": false, "text/dialog_text_prefix": "",
	"text/split_at_new_lines": false, "text/split_at_new_lines_as": 0,
	"text/autoskip_time_per_event": 0.1, "text/autoadvance_enabled": false,
	"text/autoadvance_fixed_delay": 1.0, "text/autoadvance_per_word_delay": 0.0,
	"text/autoadvance_per_character_delay": 0.1, "text/autoadvance_ignored_characters_enabled": true,
	"text/autoadvance_ignored_characters": {}, "text/absolute_autopauses": false, "text/autopauses": {},
	"layout/style_list": [], "layout/default_style": "", "layout/style_directory": {}, "settings/text_speed": 1.0, "settings/autoadvance_delay_modifier": 1.0
}
var _workspace_ref: WeakRef
var settings_workspace: RefCounted:
	get: return _workspace_ref.get_ref() if _workspace_ref != null else null
	set(value): _workspace_ref = weakref(value) if value != null else null
var values: Dictionary = {}
var target_path := ""

func get_file_extension() -> String:
	return "godot"

func open_root(source_workspace: RefCounted) -> Error:
	settings_workspace = source_workspace
	target_path = settings_workspace.root_path.path_join("project.godot")
	if settings_workspace.content_path(target_path).is_empty(): return _fail(ERR_FILE_BAD_PATH, "project.godot must belong to the selected content folder.")
	if FileAccess.file_exists(target_path):
		var error := super.open_file(target_path)
		if error != OK: return error
	else:
		new_document()
		content = "config_version=5\n\n[dialogic]\n"
		_original_content = content
	var parsed := inspect(content)
	values = parsed.get("values", {})
	return OK

func validate_content(text: String) -> Dictionary:
	var result := inspect(text)
	return {"supported": not result.has("error"), "diagnostics": [result.error] if result.has("error") else []}

func save_file(file_path: String = "") -> Error:
	if settings_workspace == null or target_path != settings_workspace.root_path.path_join("project.godot") or settings_workspace.content_path(target_path).is_empty(): return _fail(ERR_FILE_BAD_PATH, "Settings require the current content root.")
	return super.save_file(target_path)

func preview_error() -> String:
	if read_only: return "\n".join(diagnostics)
	if dirty: return "Save or discard text/style settings before preview."
	if FileAccess.file_exists(settings_workspace.root_path.path_join("override.cfg")): return "Target override.cfg requires the project-extension stage; it cannot be silently ignored."
	if not path.is_empty():
		var current := Data._read_bytes(target_path)
		if current.error != OK or Data._digest(current.bytes) != _expected_hash: return "project.godot changed externally. Refresh the content folder before preview."
	elif FileAccess.file_exists(target_path): return "project.godot appeared externally. Refresh the content folder."
	return ""

func set_value(key: String, value: Variant) -> Error:
	if read_only: return _fail(ERR_UNAVAILABLE, "Invalid project configuration remains read-only.")
	var problem := value_error(key, value)
	if not problem.is_empty(): return _fail(ERR_INVALID_DATA, problem)
	var parsed := entries(content)
	if parsed.has("error"): return _fail(ERR_INVALID_DATA, parsed.error)
	var next := content
	if parsed.keys.has(key):
		var span: Dictionary = parsed.keys[key]
		next = content.left(span.start) + var_to_str(value) + content.substr(span.end)
	else:
		var at: int = parsed.dialogic_end
		if at < 0: next += "\n[dialogic]\n" + key + "=" + var_to_str(value) + "\n"
		else: next = content.left(at) + ("\n" if at > 0 and content[at - 1] != "\n" else "") + key + "=" + var_to_str(value) + "\n" + content.substr(at)
	set_content(next)
	values[key] = value
	return OK

func remove_value(key: String) -> Error:
	if read_only: return _fail(ERR_UNAVAILABLE, "Configuration is read-only.")
	var parsed := entries(content)
	if parsed.has("error"): return _fail(ERR_INVALID_DATA, parsed.error)
	if parsed.keys.has(key):
		var span: Dictionary = parsed.keys[key]
		set_content(content.left(span.statement) + content.substr(span.next))
		values.erase(key)
	return OK

static func value_error(key: String, value: Variant) -> String:
	if not DEFAULTS.has(key) and not key.begins_with("settings/"): return "This setting belongs to a later project configuration stage: " + key
	if key.begins_with("settings/"):
		if not key.trim_prefix("settings/").is_valid_identifier() or not typeof(value) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL] or not Native.finite_data(value): return "Runtime setting defaults require a simple name and a finite scalar value."
		var runtime_name := key.trim_prefix("settings/")
		var host := Node.new()
		var reserved := ["settings", "_connections", "dialogic", "script"]
		for prop: Dictionary in host.get_property_list(): reserved.append(prop.name)
		host.free()
		if runtime_name in reserved: return "Runtime setting name collides with a subsystem property."
		if runtime_name in ["text_speed", "autoadvance_delay_modifier"] and (not typeof(value) in [TYPE_INT, TYPE_FLOAT] or value < 0): return "Text speed and auto-advance modifiers require finite nonnegative numbers."
		return ""
	if not Native.compatible_type(typeof(DEFAULTS[key]), value) or not Native.finite_data(value): return "Invalid native setting type: " + key
	if value is float and value < 0: return "Time and speed settings must be finite and nonnegative."
	if key == "save/autosave_mode" and not value in [0, 1, 2]: return "Autosave mode must be 0 (timeline), 1 (timer) or 2 (text)."
	if key == "save/autosave_delay" and value <= 0: return "Autosave delay must be positive."
	if key == "save/default_slot":
		if value.is_empty(): return "Default slot must not be empty."
		return preload("res://application/media_source.gd").slot_error(value)
	if key == "audio/channel_defaults":
		for channel: Variant in value:
			if not channel is String or (not channel.is_empty() and (channel == "-" or RegEx.create_from_string("^[\\w-]+$").search(channel) == null)): return "Invalid audio channel name."
			if not value[channel] is Dictionary: return "Audio channel defaults must be dictionaries."
			var defaults := {"volume":0.0, "audio_bus":"", "fade_length":0.0, "loop":true}
			for field: Variant in value[channel]:
				if not defaults.has(field) or not Native.compatible_type(typeof(defaults[field]), value[channel][field]): return "Unknown or invalid audio channel field."
			if value[channel].get("fade_length", 0.0) < 0: return "Channel fade must be nonnegative."
			if channel.is_empty() and (value[channel].get("loop", false) or value[channel].get("fade_length", 0.0) != 0): return "One-shot defaults require loop=false and fade_length=0."
	if key == "text/split_at_new_lines_as" and not value in [0, 1]: return "Newline mode must be 0 or 1."
	if key == "text/autopauses":
		for chars: Variant in value:
			if not chars is String or chars.is_empty() or RegEx.create_from_string('[\\[\\]\\\\^\\-]').search(chars) or not typeof(value[chars]) in [TYPE_FLOAT, TYPE_INT] or value[chars] < 0 or not is_finite(value[chars]): return "Autopause keys must be literal character sets and values finite, nonnegative seconds."
	if key == "text/autoadvance_ignored_characters":
		for ch: Variant in value:
			if not ch is String or ch.length() != 1: return "Ignored characters must be a dictionary keyed by single characters."
	if key == "layout/style_list":
		for item: Variant in value:
			if not item is String: return "Style list must contain native resource paths."
	return ""

static func inspect(text: String) -> Dictionary:
	var parsed := entries(text)
	if parsed.has("error"): return parsed
	var result := {}
	for key: String in parsed.keys:
		if not DEFAULTS.has(key) and not key.begins_with("settings/"): continue
		var span: Dictionary = parsed.keys[key]
		var value := Native.decode(text.substr(span.start, span.end - span.start))
		if value.has("error"): return value
		var problem := value_error(key, value.value)
		if not problem.is_empty(): return {"error": problem}
		result[key] = value.value
	if parsed.keys.has("text/custom_bbcode_effects"):
		var span: Dictionary = parsed.keys["text/custom_bbcode_effects"]
		var value := Native.decode(text.substr(span.start, span.end - span.start))
		if value.has("error") or value.get("value") != "": return {"error": "Custom RichTextEffect scripts require the extension stage; they are not loaded."}
	return {"values": result}

static func entries(text: String) -> Dictionary:
	var valid := Data._scan_config(text)
	if valid.has("error"): return valid
	var result := {"keys": {}, "dialogic_end": -1}
	var i := 0
	var section := ""
	while i < text.length():
		if text[i] in [" ", "\t", "\r", "\n"]: i += 1; continue
		if text[i] == ";": i = Data._after_line(text, i); continue
		if text[i] == "[":
			if section == "dialogic": result.dialogic_end = i
			var end := text.find("]", i)
			section = text.substr(i + 1, end - i - 1).strip_edges()
			i = Data._after_line(text, end)
			continue
		var start := i
		var eq := text.find("=", i)
		var raw_key := text.substr(start, eq - start).strip_edges()
		var key := raw_key.trim_prefix('"').trim_suffix('"')
		i = eq + 1
		while i < text.length() and text[i] in [" ", "\t", "\r", "\n"]: i += 1
		var span := Data._value_span(text, i)
		if span.has("error"): return span
		if section == "dialogic": result.keys[key] = {"start": i, "end": span.end, "statement": start, "next": span.next}
		i = span.next
	if section == "dialogic": result.dialogic_end = text.length()
	return result
