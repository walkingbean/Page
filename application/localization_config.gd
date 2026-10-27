extends "res://application/timeline_document.gd"

## Source-preserving access to native localization settings in the content root.
const Data = preload("res://application/variable_document.gd")
const Native = preload("res://application/native_resource.gd")
const DEFAULTS := {
	"dialogic/translation/enabled": false,
	"dialogic/translation/original_locale": "en",
	"dialogic/translation/file_mode": 0,
	"dialogic/translation/save_mode": 0,
	"dialogic/translation/translation_folder": "res://translations",
	"dialogic/translation/add_separator": false,
	"dialogic/translation/id_counter": 16,
	"dialogic/translation/locales": [],
	"dialogic/glossary/glossary_files": [],
	"dialogic/glossary/default_case_sensitive": true,
	"dialogic/glossary/default_color": Color.POWDER_BLUE,
	"internationalization/locale/translations": [],
	"internationalization/locale/fallback": "en"
}
var values: Dictionary = {}
var target_path := ""

func get_file_extension() -> String:
	return "godot"

func open_root(source_workspace: RefCounted) -> Error:
	workspace = source_workspace
	target_path = workspace.root_path.path_join("project.godot")
	if workspace.content_path(target_path).is_empty(): return _fail(ERR_FILE_BAD_PATH, "Invalid content configuration path.")
	if FileAccess.file_exists(target_path):
		var error := super.open_file(target_path)
		if error != OK: return error
	else:
		new_document()
		content = "config_version=5\n"
		_original_content = content
	var inspected := inspect(content)
	values = inspected.get("values", {})
	return OK

func validate_content(text: String) -> Dictionary:
	var checked := inspect(text)
	return {"supported": not checked.has("error"), "diagnostics": [checked.error] if checked.has("error") else []}

static func spans(text: String) -> Dictionary:
	var valid := Data._scan_config(text)
	if valid.has("error"): return valid
	var result := {"keys": {}, "ends": {}}
	var section := ""
	var i := 0
	while i < text.length():
		if text[i] in [" ", "\t", "\r", "\n"]: i += 1; continue
		if text[i] == ";": i = Data._after_line(text, i); continue
		if text[i] == "[":
			result.ends[section] = i
			var end := text.find("]", i)
			section = text.substr(i + 1, end - i - 1).strip_edges()
			i = Data._after_line(text, end)
			continue
		var eq := text.find("=", i)
		var key := text.substr(i, eq - i).strip_edges().trim_prefix('"').trim_suffix('"')
		i = eq + 1
		while i < text.length() and text[i] in [" ", "\t", "\r", "\n"]: i += 1
		var span := Data._value_span(text, i)
		if span.has("error"): return span
		result.keys[section + "/" + key] = {"start": i, "end": span.end}
		i = span.next
	result.ends[section] = text.length()
	return result

static func inspect(text: String) -> Dictionary:
	var parsed := spans(text)
	if parsed.has("error"): return parsed
	var result := DEFAULTS.duplicate(true)
	for key: String in DEFAULTS:
		if not parsed.keys.has(key): continue
		var span: Dictionary = parsed.keys[key]
		var value := Native.decode(text.substr(span.start, span.end - span.start))
		if value.has("error"): return value
		var problem := value_error(key, value.value)
		if not problem.is_empty(): return {"error": problem}
		result[key] = value.value
	return {"values": result}

static func locale_valid(locale: String) -> bool:
	var normalized := TranslationServer.standardize_locale(locale)
	return RegEx.create_from_string("^[a-z]{2,3}([_-][A-Za-z0-9]{2,8})*$").search(locale) != null and normalized.get_slice("_", 0) in TranslationServer.get_all_languages()

static func value_error(key: String, value: Variant) -> String:
	if not DEFAULTS.has(key): return "Unsupported localization setting: " + key
	var expected: Variant = DEFAULTS[key]
	if expected is Array or expected is PackedStringArray:
		if not value is Array and not value is PackedStringArray: return "Expected an array: " + key
		for item: Variant in value:
			if not item is String: return "Expected string entries: " + key
	elif typeof(value) != typeof(expected): return "Invalid setting type: " + key
	if key.ends_with("original_locale") or key.ends_with("locale/fallback"):
		if not locale_valid(value): return "Enter a valid Godot locale such as en, ja or zh_CN."
	if key.ends_with("file_mode") or key.ends_with("save_mode"):
		if not value in [0, 1]: return "Choose project/timeline mode and folder/adjacent storage."
	if key.ends_with("id_counter") and (value < 16 or value > 0x7ffffffe): return "Translation id_counter is outside the supported native range."
	if key.ends_with("translation_folder") and not value.begins_with("res://"): return "Translation folder must use a content res:// path."
	return ""

func set_value(key: String, value: Variant) -> Error:
	if read_only: return _fail(ERR_UNAVAILABLE, "Invalid configuration remains read-only.")
	var problem := value_error(key, value)
	if not problem.is_empty(): return _fail(ERR_INVALID_DATA, problem)
	var parsed := spans(content)
	if parsed.has("error"): return _fail(ERR_INVALID_DATA, parsed.error)
	var encoded := var_to_str(value)
	var next := content
	if parsed.keys.has(key):
		var span: Dictionary = parsed.keys[key]
		next = content.left(span.start) + encoded + content.substr(span.end)
	else:
		var section := key.get_slice("/", 0)
		var name := key.substr(section.length() + 1)
		var statement := name + "=" + encoded + "\n"
		if not parsed.ends.has(section): next += "\n[" + section + "]\n" + statement
		else:
			var at: int = parsed.ends[section]
			next = content.left(at) + ("\n" if at > 0 and content[at - 1] != "\n" else "") + statement + content.substr(at)
	set_content(next)
	values[key] = value
	return OK

func save_file(_destination: String = "") -> Error:
	return super.save_file(target_path)
