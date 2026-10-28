extends RefCounted

const AUDIO := ["wav", "ogg", "mp3"]
const IMAGES := ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "dds", "exr", "hdr"]
const Native = preload("res://application/native_resource.gd")

static func transitions() -> Dictionary:
	var result := {"": "res://addons/dialogic/Modules/Background/Transitions/Defaults/simple_fade.gd"}
	var native: Dictionary = DialogicResourceUtil.list_special_resources("BackgroundTransition")
	for name: String in native:
		var path: String = native[name].get("path", "")
		if path.begins_with("res://addons/dialogic/Modules/Background/Transitions/"):
			result[DialogicUtil.pretty_name(name)] = path
	return result

static func path_error(logical: String, workspace: RefCounted, kind: String) -> String:
	if workspace == null: return "Choose a content folder for media resources."
	var absolute: String = workspace.resolve_content_path(logical)
	if absolute.is_empty(): return "Media must be an unlinked res:// path inside the selected content root: " + logical
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null: return "Media file is missing or unreadable: " + logical
	var limit := 64 * 1024 * 1024 if kind == "audio" else 32 * 1024 * 1024
	if file.get_length() == 0 or file.get_length() > limit: return "Media file is empty or exceeds its byte limit: " + logical
	var extension := logical.get_extension().to_lower()
	if not extension in (AUDIO if kind == "audio" else IMAGES): return "Unsupported " + kind + " format: " + extension
	if kind == "image":
		if extension == "svg" and file.get_as_text().contains("href="): return "External SVG references are not supported in preview."
		var image := Image.load_from_file(absolute)
		if image == null or image.is_empty(): return "Image could not be decoded: " + logical
		if image.get_width() > 8192 or image.get_height() > 8192 or image.get_width() * image.get_height() > 16 * 1024 * 1024: return "Image exceeds 8192 pixels per side or 16 megapixels."
	else:
		var stream := audio(absolute)
		if stream == null or stream.get_length() <= 0: return "Audio could not be decoded: " + logical
	return ""

static func audio(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"wav": return AudioStreamWAV.load_from_file(path)
		"ogg": return AudioStreamOggVorbis.load_from_file(path)
		"mp3": return AudioStreamMP3.load_from_file(path)
	return null

static func mood_error(info: Dictionary, workspace: RefCounted = null) -> String:
	var moods: Variant = info.get("sound_moods", {})
	var default_mood: Variant = info.get("sound_mood_default", "")
	if not moods is Dictionary or moods.size() > 256 or not default_mood is String: return "Sound moods require a dictionary (at most 256 entries) and a default name."
	if not default_mood.is_empty() and not moods.has(default_mood): return "Default sound mood does not exist."
	var defaults := {"name":"", "sound_path":"", "volume_base":0.0, "volume_variance":0.0, "pitch_base":1.0, "pitch_variance":0.0, "skip_characters":0, "mode":0}
	for name: Variant in moods:
		if not name is String or name.is_empty() or not moods[name] is Dictionary: return "Each sound mood needs a name and native properties."
		for key: Variant in moods[name]:
			var value: Variant = moods[name][key]
			if not defaults.has(key) or not Native.compatible_type(typeof(defaults[key]), value) or not Native.finite_data(value): return "Invalid sound mood field: " + str(key)
			if key in ["volume_variance", "pitch_variance", "skip_characters"] and value < 0: return "Sound variation and skipped characters must be nonnegative."
			if key == "pitch_base" and value <= 0: return "Base pitch must be positive."
			if key == "mode" and not value in [0, 1, 2]: return "Typing mode must be Interrupt (0), Overlap (1) or Await (2)."
		if workspace != null:
			var files := sound_files(str(moods[name].get("sound_path", "")), workspace)
			if files.has("error"): return files.error
	return ""

static func sound_files(logical: String, workspace: RefCounted) -> Dictionary:
	if logical.is_empty(): return {"paths":[]}
	var absolute: String = workspace.resolve_content_path(logical.trim_suffix("/"))
	if absolute.is_empty(): return {"error":"Sound mood paths must belong to the selected content root."}
	var paths: Array[String] = []
	if FileAccess.file_exists(absolute): paths.append(logical)
	elif DirAccess.dir_exists_absolute(absolute):
		for name: String in DirAccess.get_files_at(absolute):
			if name.get_extension().to_lower() in AUDIO: paths.append(logical.trim_suffix("/").path_join(name))
	else: return {"error":"Sound mood file or folder is missing: " + logical}
	if paths.is_empty() or paths.size() > 256: return {"error":"A sound mood folder needs 1–256 supported audio files."}
	paths.sort()
	for path: String in paths:
		var error := path_error(path, workspace, "audio")
		if not error.is_empty(): return {"error":error}
	return {"paths":paths}

static func buses(workspace: RefCounted) -> Dictionary:
	var result := {"Master":{"name":"Master", "volume_db":0.0, "send":"", "mute":false, "solo":false, "bypass_fx":false}}
	if workspace == null: return {"buses":result}
	var logical := "res://default_bus_layout.tres"
	var config := ConfigFile.new()
	if config.load(workspace.root_path.path_join("project.godot")) == OK: logical = str(config.get_value("audio", "buses/default_bus_layout", logical))
	var absolute: String = workspace.resolve_content_path(logical)
	if absolute.is_empty(): return {"error":"Audio bus layout must belong to the selected content root."}
	if not FileAccess.file_exists(absolute):
		return {"buses":result} if logical == "res://default_bus_layout.tres" else {"error":"Configured audio bus layout is missing."}
	if FileAccess.get_file_as_bytes(absolute).size() > 1024 * 1024: return {"error":"Audio bus layout exceeds 1 MiB."}
	var text := FileAccess.get_file_as_string(absolute)
	if not text.begins_with('[gd_resource type="AudioBusLayout"') or text.contains("[ext_resource") or text.contains("[sub_resource"): return {"error":"Custom audio bus effects/resources require the project-extension stage; the layout is not executed."}
	var indexed := {}
	for line: String in text.split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("["): continue
		var parsed := RegEx.create_from_string('^bus/([0-9]+)/([a-z_]+)\\s*=\\s*(.*)$').search(line)
		if parsed == null: return {"error":"Unknown audio bus layout field."}
		var index := parsed.get_string(1).to_int()
		var key := parsed.get_string(2)
		if index >= 64 or not result.Master.has(key): return {"error":"Unsupported bus field or more than 64 buses."}
		var literal := parsed.get_string(3)
		if key in ["name", "send"] and literal.begins_with('&"'): literal = literal.substr(1)
		var value := Native.decode(literal)
		if value.has("error") or not Native.compatible_type(typeof(result.Master[key]), value.get("value")) or not Native.finite_data(value.get("value")): return {"error":"Invalid audio bus property."}
		if not indexed.has(index): indexed[index] = result.Master.duplicate()
		if indexed[index].has("__" + key): return {"error":"Duplicate audio bus property."}
		indexed[index]["__" + key] = true
		indexed[index][key] = value.value
	result.clear()
	for index: int in indexed.size():
		if not indexed.has(index): return {"error":"Audio bus indices must be contiguous."}
		var bus: Dictionary = indexed[index]
		if bus.name.is_empty() or result.has(bus.name) or (index == 0 and bus.name != "Master"): return {"error":"Audio buses require unique names and Master at index zero."}
		if index > 0 and not result.has(bus.send): return {"error":"Audio bus sends must target an earlier bus."}
		result[bus.name] = bus
	return {"buses":result}

static func bus_error(name: String, workspace: RefCounted) -> String:
	var layout := buses(workspace)
	if layout.has("error"): return layout.error
	return "" if name.is_empty() or layout.buses.has(name) else "Audio bus is missing from the content project: " + name
