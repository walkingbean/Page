extends RefCounted

const LAYER_PATH := "res://application/layered_portrait_document.gd"
const PARAMS := {"animation": "animation_name", "length": "animation_length", "wait": "animation_wait", "repeat": "animation_repeats", "repeat_forever": "repeat_forever", "z_index": "z_index", "mirrored": "mirrored", "fade": "fade_animation", "fade_length": "fade_length", "move_time": "transform_time", "move_ease": "transform_ease", "move_trans": "transform_trans", "extra_data": "extra_data"}

static func inspect(raw: String, workspace: RefCounted = null, check_references: bool = true) -> Dictionary:
	var pattern := RegEx.create_from_string('^(join|update|leave)[ \\t]+(?:"([^"\\r\\n]+)"|([^ \\t"():\\r\\n]+))(?:[ \\t]*\\(([^()\\r\\n]+)\\))?(?:[ \\t]+([^\\[\\]\\r\\n]*?))?(?:[ \\t]*\\[([^\\[\\]\\r\\n]*)\\])?[ \\t]*$')
	var found := pattern.search(raw)
	if found == null: return {"error": "Use join/update/leave Identifier (Portrait) Position [key=\"value\"]."}
	var action := found.get_string(1)
	var identifier := found.get_string(2) if not found.get_string(2).is_empty() else found.get_string(3)
	var portrait := found.get_string(4).strip_edges()
	var transform := found.get_string(5).strip_edges()
	if RegEx.create_from_string('[{}\\[\\]\\\\]').search(identifier + portrait): return {"error": "Character and portrait references must be static names in this version."}
	if identifier == "--All--" and action != "leave": return {"error": "--All-- is supported only by Leave."}
	if action == "leave" and (not portrait.is_empty() or not transform.is_empty()): return {"error": "Leave does not use a portrait or position."}
	if not transform.is_empty() and not valid_transform(transform): return {"error": "Use leftmost, left, center, right, rightmost or native pos/size/rot values."}
	var params: Dictionary = {}
	var tail := found.get_string(6)
	var offset := 0
	var pairs := RegEx.create_from_string('[ \\t]*([a-z_]+)[ \\t]*=[ \\t]*"([^"\\\\]*)"')
	while offset < tail.length():
		if tail.substr(offset).strip_edges().is_empty(): break
		var pair := pairs.search(tail, offset)
		if pair == null or pair.get_start() != offset: return {"error": "Every Character argument must use key=\"value\"; quotes, escapes and leftover text are not supported."}
		var key := pair.get_string(1)
		var value := pair.get_string(2)
		if not PARAMS.has(key) or params.has(key): return {"error": "Unknown or duplicate Character argument: " + key}
		var problem := parameter_error(key, value, action)
		if not problem.is_empty(): return {"error": problem, "offset": raw.find(key)}
		params[key] = value
		offset = pair.get_end()
	if params.get("repeat_forever", "false") == "true" and params.get("wait", "false") == "true": return {"error": "A repeating animation cannot wait forever."}
	var character: DialogicCharacter
	if check_references and identifier != "--All--":
		if workspace == null: return {"error": "Choose a content folder containing this character."}
		character = workspace.get_character(identifier)
		if character == null: return {"error": workspace.get_character_error(identifier)}
		if not portrait.is_empty() and not character.portraits.has(portrait): return {"error": "Character '%s' has no portrait '%s'." % [identifier, portrait]}
		var extra: String = params.get("extra_data", "")
		if not extra.is_empty():
			# UPDATE without a portrait depends on current runtime state. Validate all
			# possible layered portraits rather than silently target a wrong scene.
			var candidates: Array = [portrait] if not portrait.is_empty() else ([character.default_portrait] if action == "join" else character.portraits.keys())
			if candidates.is_empty(): return {"error": "Extra data requires a layered portrait."}
			for selected: String in candidates:
				var info: Dictionary = character.portraits.get(selected, {})
				var scene: Dictionary = load(LAYER_PATH).inspect_path(info.get("scene", ""), workspace)
				if not scene.supported: return {"error": "show/hide/set extra data requires an explicit layered portrait."}
				var error: String = load(LAYER_PATH).commands_error(extra, scene.model)
				if not error.is_empty(): return {"error": error}
	var expected: Dictionary = {}
	var event := DialogicCharacterEvent.new()
	# Load only prevalidated inert arguments, never untrusted Variant expressions.
	event.load_from_shortcode_parameters(tail)
	for key: String in PARAMS: expected[PARAMS[key]] = event.get(PARAMS[key])
	expected["set_z_index"] = params.has("z_index")
	expected["set_mirrored"] = params.has("mirrored")
	expected["set_portrait"] = not portrait.is_empty()
	expected["set_transform"] = not transform.is_empty()
	return {"kind": "character", "identifier": identifier, "portrait": portrait, "action": {"join": 0, "leave": 1, "update": 2}[action], "position": transform if not transform.is_empty() else "center", "parameters": params, "properties": expected, "raw": raw}

static func parameter_error(key: String, value: String, action: String) -> String:
	if action == "leave" and not key in ["animation", "length", "wait"]: return "Leave supports animation, length and wait only."
	if key in ["wait", "mirrored", "repeat_forever"]:
		return "" if value in ["true", "false"] else key + " requires true or false."
	if key in ["length", "fade_length", "move_time"]:
		return "" if value.is_valid_float() and is_finite(value.to_float()) and value.to_float() >= 0 and value.to_float() <= 3600 else key + " requires a finite duration from 0 to 3600 seconds."
	if key in ["repeat", "z_index"]:
		return "" if value.is_valid_int() and (value.to_int() >= 1 and value.to_int() <= 10000 if key == "repeat" else value.to_int() >= -4096 and value.to_int() <= 4096) else key + " has an invalid integer range."
	if key in ["move_ease", "move_trans"]:
		var options: Array = DialogicCharacterEvent.new().ease_options if key == "move_ease" else DialogicCharacterEvent.new().trans_options
		for option: Dictionary in options:
			if value == option.label.to_lower() or (value.is_valid_int() and value.to_int() == option.value): return ""
		return "Use lowercase native easing/transition names (for example out, in_out, cubic) or the exact enum number."
	if key in ["animation", "fade"]:
		if value.is_empty(): return ""
		var type: int = 4 if key == "fade" else {"join": 1, "leave": 2, "update": 3}[action]
		for name: String in DialogicPortraitAnimationUtil.get_portrait_animations_filtered(type):
			if value.to_lower().replace(" ", "_") == name.to_lower().replace(" ", "_"): return ""
		return "Choose a bundled native animation for this action; custom animation scripts require a later version."
	if key == "extra_data" and (value.contains("{") or value.contains("}")): return "Extra data must be static layered commands."
	return ""

static func valid_transform(value: String) -> bool:
	if value in ["leftmost", "left", "center", "right", "rightmost"]: return true
	var fields := value.split(" ", false)
	var seen: Dictionary = {}
	for field: String in fields:
		var split := field.split("=", true)
		if split.size() != 2 or not split[0] in ["pos", "position", "size", "siz", "rot", "rotation"]: return false
		var key := String(split[0]).left(3)
		if seen.has(key): return false
		seen[key] = true
		if key == "rot":
			if not split[1].is_valid_float() or not is_finite(split[1].to_float()): return false
		else:
			if not RegEx.create_from_string('^(?:x[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:px|%)?)?(?:y[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:px|%)?)$').search(split[1]) or split[1].is_empty(): return false
	return not seen.is_empty()

static func mismatch(parsed: DialogicCharacterEvent, model: Dictionary) -> String:
	if parsed.action != model.action or parsed.transform != model.position: return "The native parser did not preserve Character action or transform."
	for key: String in model.properties:
		if parsed.get(key) != model.properties[key]: return "The native parser did not preserve Character property: " + key
	return ""
