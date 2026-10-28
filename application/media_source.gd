extends RefCounted

const Assets = preload("res://application/media_assets.gd")
const KINDS := ["Background", "Audio", "Voice", "History", "Save"]
const FLAGS := {"fade_length":"set_fade_length", "volume":"set_volume", "audio_bus":"set_audio_bus", "loop":"set_loop", "sync_channel":"set_sync_channel"}

static func create(kind: String) -> DialogicEvent:
	match kind:
		"Background": return DialogicBackgroundEvent.new()
		"Audio": return DialogicAudioEvent.new()
		"Voice": return DialogicVoiceEvent.new()
		"History": return DialogicHistoryEvent.new()
		"Save": return DialogicSaveEvent.new()
	return null

static func kind_of(event: DialogicEvent) -> String:
	for kind: String in KINDS:
		if event.get_script() == create(kind).get_script(): return kind
	return ""

static func slot_error(value: String) -> String:
	if value.is_empty(): return ""
	if value.length() > 128 or RegEx.create_from_string("^[\\p{L}\\p{N}_-]+$").search(value) == null or value in [".", ".."]: return "Slot names require 1–128 letters, numbers, underscores or hyphens."
	if value.to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]: return "This slot name is reserved on Windows."
	return ""

static func inspect(raw: String, original: DialogicEvent, workspace: RefCounted = null, check_references := true) -> Dictionary:
	var kind := kind_of(original)
	var event := create(kind)
	if event == null: return {"error":"Unknown media event."}
	var tail := ""
	var expected := {}
	if kind == "Audio":
		var parsed := RegEx.create_from_string('^audio[ \\t]+(?:(?<channel>[\\w-]+)[ \\t]+)?(?<file>"[^"\\r\\n]*"|-)(?:[ \\t]+\\[(?<options>.*)\\])?[ \\t]*$').search(raw)
		if parsed == null: return {"error":"Use audio [channel] \"res://file.wav\" [volume=\"-6\"] or audio channel -."}
		var channel := parsed.get_string("channel")
		if channel == "-": return {"error":"A dash cannot be an audio channel name."}
		expected["channel_name"] = channel
		expected["file_path"] = "" if parsed.get_string("file") == "-" else parsed.get_string("file").trim_prefix('"').trim_suffix('"')
		tail = parsed.get_string("options")
	else:
		var parsed := RegEx.create_from_string('^\\[' + event.get_shortcode() + '(?:[ \\t]+(.*))?\\]$').search(raw)
		if parsed == null: return {"error":"Use the complete native shortcode for " + kind + "."}
		tail = parsed.get_string(1)
	var schema: Dictionary = event.get_shortcode_parameters()
	var seen := {}
	var at := 0
	var regex := RegEx.create_from_string('[ \\t]*([a-z_]+)[ \\t]*=[ \\t]*"((?:[^"\\\\]|\\\\.)*)"')
	while at < tail.length():
		if tail.substr(at).strip_edges().is_empty(): break
		var pair := regex.search(tail, at)
		if pair == null or pair.get_start() != at: return {"error":"Each media argument must use key=\"value\" with no trailing content."}
		var key := pair.get_string(1)
		if not schema.has(key) or seen.has(key) or (kind == "Audio" and key in ["channel", "path"]): return {"error":"Unknown or duplicate media argument: " + key}
		seen[key] = true
		var property: String = schema[key].property
		var value: String = pair.get_string(2).replace('\\"', '"')
		var type := typeof(event.get(property))
		if type == TYPE_BOOL:
			if not value in ["true", "false"]: return {"error":key + " requires true or false."}
			expected[property] = value == "true"
		elif type in [TYPE_INT, TYPE_FLOAT]:
			if kind == "History":
				var actions := {"Clear":0, "clear":0, "Pause":1, "pause":1, "Resume":2, "resume":2, "start":2, "0":0, "1":1, "2":2}
				if not actions.has(value): return {"error":"History action must be Clear, Pause or Resume."}
				expected[property] = actions[value]
			else:
				if not value.is_valid_float() or not is_finite(value.to_float()): return {"error":key + " requires a finite number."}
				if key == "fade" and value.to_float() < 0: return {"error":"Fade duration must be nonnegative."}
				expected[property] = value.to_float()
		else: expected[property] = value
		at = pair.get_end()
	event.from_text(raw)
	for property: String in expected:
		if event.get(property) != expected[property]: return {"error":"The fixed native parser cannot preserve media property: " + property}
	var properties := {}
	for key: String in schema:
		var property: String = schema[key].property
		if kind != "Audio" or not FLAGS.has(property) or event.get(FLAGS[property]): properties[property] = event.get(property)
	if kind == "Audio":
		for flag: String in FLAGS.values(): properties[flag] = event.get(flag)
	if not check_references: return {"kind":"interaction", "interaction":kind, "properties":properties, "event":event, "raw":raw}
	var error := ""
	match kind:
		"Background":
			if not event.scene.is_empty():
				# The fixed native subsystem accepts .tscn scenes. Inspect the path
				# without loading target scripts in the authoring process.
				var absolute: String = workspace.resolve_content_path(event.scene) if workspace != null else ""
				if absolute.is_empty() or event.scene.get_extension() != "tscn" or not FileAccess.file_exists(absolute): error = "Choose an existing unlinked res:// .tscn background scene in the content folder."
			elif not event.argument.is_empty() and not (event.argument.begins_with("#") and event.argument.is_valid_html_color()): error = Assets.path_error(event.argument, workspace, "image")
			if error.is_empty() and not event.transition.is_empty() and not Assets.transitions().has(event.transition): error = "Unknown or custom background transition: " + event.transition
		"Audio", "Voice":
			if kind == "Voice" or not event.file_path.is_empty(): error = Assets.path_error(event.file_path, workspace, "audio")
			if error.is_empty(): error = Assets.bus_error(event.audio_bus, workspace)
			if kind == "Audio" and error.is_empty() and not event.sync_channel.is_empty() and RegEx.create_from_string("^[\\w-]+$").search(event.sync_channel) == null: error = "Invalid synchronization channel."
		"Save": error = slot_error(event.slot_name)
	if not error.is_empty(): return {"error":error}
	return {"kind":"interaction", "interaction":kind, "properties":properties, "event":event, "raw":raw}

static func serialize(kind: String, fields: Dictionary) -> Dictionary:
	var event := create(kind)
	if event == null: return {"error":"Unknown media kind."}
	var pieces := PackedStringArray()
	for key: String in event.get_shortcode_parameters():
		var property: String = event.get_shortcode_parameters()[key].property
		if kind == "Audio" and (key in ["path", "channel"] or (FLAGS.has(property) and not fields.get(FLAGS[property], false))): continue
		var value: Variant = fields.get(property, event.get(property))
		var literal := var_to_str(value) if value is float else str(value)
		if literal.contains("\n") or literal.contains("\r"): return {"error":"Media arguments must be single-line values."}
		pieces.append(key + '="' + literal.replace('"', '\\"') + '"')
	if kind == "Audio":
		var file: String = fields.get("file_path", "")
		if file.contains('"') or file.contains("\n") or file.contains("\r"): return {"error":"Audio paths cannot contain quotes or newlines."}
		var channel: String = fields.get("channel_name", "")
		return {"source":"audio " + (channel + " " if not channel.is_empty() else "") + ('"' + file + '"' if not file.is_empty() else "-") + (" [" + " ".join(pieces) + "]" if not pieces.is_empty() else "")}
	return {"source":"[" + event.get_shortcode() + " " + " ".join(pieces) + "]"}
