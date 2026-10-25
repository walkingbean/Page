class_name CharacterDocument
extends "res://application/timeline_document.gd"

## Alpha 20's native .dch representation, with the document's verified-save path.
## Unrecognized properties remain read-only; the original source is never reduced
## to the supported subset on save. External script references are never loaded.
const CHARACTER_SCRIPT_PATH: String = "res://addons/dialogic/Resources/character.gd"
const DEFAULT_PORTRAIT: String = "default"
const SAFE_TOKENS: Array[String] = ["Color", "Vector2", "NodePath", "true", "false", "null", "inf", "nan", "e", "E"]

var character: DialogicCharacter = DialogicCharacter.new()
var portrait_path: String = ""


func _init() -> void:
	new_document()


func new_document() -> void:
	super.new_document()
	character = DialogicCharacter.new()
	portrait_path = ""
	content = var_to_str(inst_to_dict(character))
	_original_content = content


func get_file_extension() -> String:
	return "dch"


func open_file(file_path: String, source_workspace: RefCounted = null) -> Error:
	var previous_workspace: RefCounted = workspace
	if source_workspace != null:
		workspace = source_workspace
	var error: Error = super.open_file(file_path)
	if error != OK:
		workspace = previous_workspace
		return error
	var result: Dictionary = validate_content(content)
	character = result.get("character", null)
	portrait_path = result.get("portrait_path", "")
	return OK


func update_fields(display_name: String, color: Color, image_path: String = "", details: Dictionary = {}) -> Error:
	if read_only:
		return _fail(ERR_UNAVAILABLE, "This character contains unsupported properties and remains read-only.")
	var candidate: DialogicCharacter = character.duplicate(true) if character != null else DialogicCharacter.new()
	candidate.display_name = display_name
	candidate.color = color
	if details.has("portraits"):
		for key: String in ["nicknames", "description", "custom_info", "scale", "offset", "mirror", "portraits", "default_portrait"]:
			if details.has(key):
				var value: Variant = details[key]
				candidate.set(key, value.duplicate(true) if value is Dictionary or value is Array else value)
	else:
		# Legacy single-image API: preserve the remaining portraits when replacing.
		if image_path.is_empty():
			candidate.default_portrait = ""
			candidate.portraits = {}
		else:
			var selected: String = candidate.default_portrait if not candidate.default_portrait.is_empty() else DEFAULT_PORTRAIT
			candidate.default_portrait = selected
			if not candidate.portraits.has(selected):
				candidate.portraits[selected] = {"scene": "", "export_overrides": {}, "scale": 1.0, "offset": Vector2(), "mirror": false}
			candidate.portraits[selected]["export_overrides"]["image"] = var_to_str(image_path)
	var next_content: String = var_to_str(inst_to_dict(candidate))
	var result: Dictionary = validate_content(next_content)
	if not result["supported"]:
		return _fail(ERR_INVALID_DATA, "\n".join(result["diagnostics"]))
	if character != null and inst_to_dict(candidate) == inst_to_dict(character):
		last_error = ""
		return OK
	character = candidate
	portrait_path = result.portrait_path
	set_content(next_content)
	return OK


func save_file(file_path: String = "") -> Error:
	var target: String = _absolute_path(file_path) if not file_path.is_empty() else path
	if workspace != null and (target.is_empty() or workspace.content_path(target).is_empty()):
		return _fail(ERR_FILE_BAD_PATH, "Save the character inside the selected content folder, without symbolic links.")
	return super.save_file(file_path)


func validate_content(text: String) -> Dictionary:
	var issues: Array[String] = []
	var lexical_error: String = _check_data_tokens(text)
	if not lexical_error.is_empty():
		return {"supported": false, "diagnostics": [lexical_error], "character": null, "portrait_path": ""}
	var parsed: Variant = str_to_var(text)
	if not parsed is Dictionary:
		return {"supported": false, "diagnostics": ["The .dch source must be an Alpha 20 character dictionary."], "character": null, "portrait_path": ""}
	var values: Dictionary = parsed
	if values.get("@path", "") != CHARACTER_SCRIPT_PATH or not values.get("@subpath", NodePath("")) is NodePath or not String(values.get("@subpath", NodePath(""))).is_empty():
		return {"supported": false, "diagnostics": ["Only the bundled Alpha 20 DialogicCharacter script is accepted; external scripts are not loaded."], "character": null, "portrait_path": ""}
	var defaults: Dictionary = inst_to_dict(DialogicCharacter.new())
	for key: Variant in values:
		if not (key is String or key is StringName) or not defaults.has(key):
			issues.append("Unknown character property: " + str(key))
	if values.get("_translation_id", "") != "":
		issues.append("Character translation metadata requires a later version.")
	var name_value: Variant = values.get("display_name", "")
	var color_value: Variant = values.get("color", Color())
	if not name_value is String or not plain_name(name_value, true):
		issues.append("Display name must be plain single-line text, without expressions or formatting tags.")
	if not color_value is Color or not _valid_color(color_value):
		issues.append("Character color must have finite RGBA components between 0 and 1.")
	var aliases: Variant = values.get("nicknames", [])
	if not aliases is Array or aliases.size() > 1024:
		issues.append("Nicknames must be an array of at most 1024 plain names.")
	else:
		for alias: Variant in aliases:
			if not alias is String or not plain_name(alias):
				issues.append("Nicknames must be nonempty plain single-line names.")
	if not values.get("description", "") is String:
		issues.append("Description must be text.")
	if not values.get("custom_info", {}) is Dictionary or not inert_data(values.get("custom_info", {})):
		issues.append("Custom info must be a dictionary of finite inert values; objects and resources are not allowed.")
	if not valid_transform(values):
		issues.append("Character scale must be positive and finite, offset finite Vector2, mirror boolean.")
	var default_value: Variant = values.get("default_portrait", "")
	var portraits_value: Variant = values.get("portraits", {})
	var image_path := ""
	if not default_value is String or not portraits_value is Dictionary:
		issues.append("Portrait data has invalid types.")
	elif portraits_value.size() > 1024:
		issues.append("At most 1024 portraits are supported.")
	else:
		if not default_value.is_empty() and not portraits_value.has(default_value):
			issues.append("The default portrait does not exist.")
		if not portraits_value.is_empty() and default_value.is_empty():
			issues.append("Select an existing default portrait.")
		for key: Variant in portraits_value:
			if not (key is String or key is StringName) or not plain_name(str(key)) or String(key).contains("(") or String(key).contains(")"):
				issues.append("Portrait names must be nonempty plain names without parentheses.")
				continue
			var entry: Variant = portraits_value[key]
			if not entry is Dictionary or not _supported_portrait_keys(entry) or not valid_transform(entry):
				issues.append("Portrait '%s' has unknown properties or invalid transforms." % key)
				continue
			var scene: Variant = entry.get("scene", "")
			var overrides: Variant = entry.get("export_overrides", {})
			if not scene is String or not overrides is Dictionary:
				issues.append("Portrait '%s' scene or overrides have invalid types." % key)
				continue
			if scene in ["", "res://addons/dialogic/Modules/DefaultPortrait/default_portrait.tscn", HIGHLIGHT]:
				if overrides.size() != 1 or not overrides.get("image", null) is String:
					issues.append("Static and Highlight portraits require one image override.")
					continue
				var logical := decoded_image_path(overrides.image)
				var problem := validate_image(logical, workspace)
				if not problem.is_empty():
					issues.append("Portrait '%s': %s" % [key, problem])
				if key == default_value:
					image_path = logical
			else:
				if workspace == null:
					issues.append("Select the content folder to resolve the layered portrait.")
				elif not overrides.is_empty():
					issues.append("Layered portraits store properties in their native scene; unknown export overrides remain read-only.")
				else:
					var layer := preload("res://application/layered_portrait_document.gd").inspect_path(scene, workspace)
					if not layer.supported:
						issues.append("Portrait '%s': %s" % [key, " ".join(layer.diagnostics)])
	var result_character: DialogicCharacter = null
	if issues.is_empty():
		result_character = DialogicCharacter.new()
		for key: String in ["display_name", "color", "nicknames", "description", "custom_info", "scale", "offset", "mirror", "default_portrait", "portraits"]:
			result_character.set(key, values.get(key, defaults[key]))
	return {"supported": issues.is_empty(), "diagnostics": issues, "character": result_character, "portrait_path": image_path}

const HIGHLIGHT := "res://addons/dialogic/Modules/HighlightPortrait/simple_highlight_portrait.tscn"

static func plain_name(value: String, empty_ok: bool = false) -> bool:
	return (empty_ok or not value.strip_edges().is_empty()) and not RegEx.create_from_string("[\\x00-\\x1f{}\\[\\]]").search(value)

static func valid_transform(value: Dictionary) -> bool:
	var scale_value: Variant = value.get("scale", 1.0)
	var off: Variant = value.get("offset", Vector2())
	return (scale_value is float or scale_value is int) and is_finite(scale_value) and scale_value > 0 and scale_value <= 10000 and off is Vector2 and is_finite(off.x) and is_finite(off.y) and value.get("mirror", false) is bool and value.get("ignore_char_scale", false) is bool

static func inert_data(value: Variant, depth: int = 0) -> bool:
	if depth > 24:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_VECTOR2: return is_finite(value.x) and is_finite(value.y)
		TYPE_COLOR: return _valid_color(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not inert_data(item, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not (key is String or key is StringName) or not inert_data(value[key], depth + 1): return false
			return true
	return false

static func validate_image(logical: String, source_workspace: RefCounted) -> String:
	if not _logical_png_path(logical): return "Portrait image must use a portable res:// path to a PNG inside the content folder."
	if source_workspace == null: return "Select the content folder to resolve this character's portrait."
	var absolute: String = source_workspace.resolve_content_path(logical)
	if absolute.is_empty(): return "Portrait image leaves the content folder or follows a symbolic link."
	return source_workspace.validate_png(absolute)


static func decoded_image_path(value: String) -> String:
	if value.begins_with("res://"):
		return value
	if not value.begins_with("\"") or not value.ends_with("\"") or not _check_data_tokens(value).is_empty():
		return ""
	var decoded: Variant = str_to_var(value)
	return decoded if decoded is String else ""


static func _supported_portrait_keys(portrait: Dictionary) -> bool:
	for key: Variant in portrait:
		if not key in ["scene", "export_overrides", "scale", "offset", "mirror", "ignore_char_scale"]:
			return false
	return true


static func _valid_color(value: Color) -> bool:
	for component: float in [value.r, value.g, value.b, value.a]:
		if not is_finite(component) or component < 0.0 or component > 1.0:
			return false
	return true


static func _logical_png_path(value: String) -> bool:
	if not value.begins_with("res://") or value.get_extension().to_lower() != "png" or value.contains("\\") or value.to_utf8_buffer().has(0):
		return false
	var relative: String = value.trim_prefix("res://")
	return not relative.is_empty() and not relative.contains(":") and not ".." in relative.split("/") and not "." in relative.split("/")


static func _check_data_tokens(text: String) -> String:
	# Variant text may contain Object(...) constructors. Reject constructors and
	# identifiers other than inert value types BEFORE calling str_to_var.
	if text.to_utf8_buffer().size() > CODEC.MAX_SOURCE_BYTES or text.to_utf8_buffer().has(0):
		return "Character data exceeds 4 MiB or contains a NUL byte."
	var in_string: bool = false
	var escaped: bool = false
	var depth: int = 0
	var token: String = ""
	for index: int in text.length():
		var ch: String = text[index]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == "\"":
				in_string = false
			continue
		var code: int = ch.unicode_at(0)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or ch == "_" or (not token.is_empty() and code >= 48 and code <= 57):
			token += ch
			if token.length() > 32:
				return "Character data contains an unsupported value constructor."
			continue
		if not token.is_empty():
			if not token in SAFE_TOKENS:
				return "Character data contains an unsupported value constructor: " + token
			token = ""
		if ch == "\"":
			in_string = true
		elif ch in ["{", "[", "("]:
			depth += 1
		elif ch in ["}", "]", ")"]:
			depth -= 1
		if depth < 0 or depth > 32:
			return "Character data has invalid or excessively nested delimiters."
	if not token.is_empty() and not token in SAFE_TOKENS:
		return "Character data contains an unsupported value constructor: " + token
	if in_string or depth != 0:
		return "Character data contains an unterminated string or delimiter."
	return ""
