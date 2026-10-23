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


func update_fields(display_name: String, color: Color, image_path: String = "") -> Error:
	if read_only:
		return _fail(ERR_UNAVAILABLE, "This character contains unsupported properties and remains read-only.")
	var candidate: DialogicCharacter = character.duplicate(true) if character != null else DialogicCharacter.new()
	candidate.display_name = display_name
	candidate.color = color
	if image_path.is_empty():
		candidate.default_portrait = ""
		candidate.portraits = {}
	else:
		var portrait_name: String = candidate.default_portrait if not candidate.default_portrait.is_empty() else DEFAULT_PORTRAIT
		candidate.default_portrait = portrait_name
		if candidate.portraits.has(portrait_name):
			var existing: Dictionary = candidate.portraits[portrait_name]
			if decoded_image_path(existing.get("export_overrides", {}).get("image", "")) != image_path:
				existing["export_overrides"]["image"] = var_to_str(image_path)
		else:
			candidate.portraits = {portrait_name: {"scene": "", "export_overrides": {"image": var_to_str(image_path)}, "scale": 1, "offset": Vector2(), "mirror": false}}
	var next_content: String = var_to_str(inst_to_dict(candidate))
	var result: Dictionary = validate_content(next_content)
	if not result["supported"]:
		return _fail(ERR_INVALID_DATA, "\n".join(result["diagnostics"]))
	# Updating a form without changing values must retain original source bytes.
	if character != null and inst_to_dict(candidate) == inst_to_dict(character):
		last_error = ""
		return OK
	character = candidate
	portrait_path = image_path
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
	for key: Variant in defaults:
		if key in ["@path", "@subpath", "display_name", "color", "default_portrait", "portraits"]:
			continue
		if values.get(key, defaults[key]) != defaults[key]:
			issues.append("Property is outside the current editable scope: " + str(key))
	var name_value: Variant = values.get("display_name", "")
	var color_value: Variant = values.get("color", Color())
	var default_value: Variant = values.get("default_portrait", "")
	var portraits_value: Variant = values.get("portraits", {})
	if not name_value is String or String(name_value).contains("\n") or String(name_value).contains("\r") or String(name_value).contains("{") or String(name_value).contains("}") or String(name_value).contains("[") or String(name_value).contains("]"):
		issues.append("Display name must be plain single-line text, without expressions or formatting tags.")
	if not color_value is Color or not _valid_color(color_value):
		issues.append("Character color must have finite RGBA components between 0 and 1.")
	if not default_value is String or not portraits_value is Dictionary:
		issues.append("Portrait data has invalid types.")
	var image_path: String = ""
	if default_value is String and portraits_value is Dictionary:
		if portraits_value.is_empty():
			if not default_value.is_empty():
				issues.append("The default portrait does not exist.")
		elif portraits_value.size() != 1 or not portraits_value.has(default_value) or String(default_value).is_empty():
			issues.append("This editor supports at most one portrait, selected as the default portrait.")
		else:
			var portrait: Variant = portraits_value[default_value]
			if not portrait is Dictionary or not _supported_portrait_keys(portrait) or portrait.get("scene", null) != "" or not portrait.get("export_overrides", null) is Dictionary:
				issues.append("Only Dialogic's default static-image portrait scene is supported.")
			else:
				var overrides: Dictionary = portrait["export_overrides"]
				if overrides.size() != 1 or not overrides.get("image", null) is String:
					issues.append("Only the default portrait's image property is supported.")
				else:
					image_path = decoded_image_path(overrides["image"])
					if not _logical_png_path(image_path):
						issues.append("Portrait image must use a portable res:// path to a PNG inside the content folder.")
					elif workspace == null:
						issues.append("Select the content folder to resolve this character's portrait.")
					else:
						var absolute: String = workspace.resolve_content_path(image_path)
						if absolute.is_empty():
							issues.append("Portrait image leaves the content folder or follows a symbolic link.")
						else:
							var png_error: String = workspace.validate_png(absolute)
							if not png_error.is_empty():
								issues.append(png_error)
	var result_character: DialogicCharacter = null
	# Do not use dict_to_inst on input: constructing the known class and assigning
	# only validated properties prevents nested or substituted script execution.
	if issues.is_empty():
		result_character = DialogicCharacter.new()
		result_character.display_name = name_value
		result_character.color = color_value
		result_character.default_portrait = default_value
		result_character.portraits = portraits_value.duplicate(true)
	return {"supported": issues.is_empty(), "diagnostics": issues, "character": result_character, "portrait_path": image_path}


static func decoded_image_path(value: String) -> String:
	if value.begins_with("res://"):
		return value
	if not value.begins_with("\"") or not value.ends_with("\"") or not _check_data_tokens(value).is_empty():
		return ""
	var decoded: Variant = str_to_var(value)
	return decoded if decoded is String else ""


static func _supported_portrait_keys(portrait: Dictionary) -> bool:
	for key: Variant in portrait:
		if not key in ["scene", "export_overrides", "scale", "offset", "mirror"]:
			return false
	return portrait.get("scale", 1) == 1 and portrait.get("offset", Vector2()) == Vector2() and portrait.get("mirror", false) == false


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
