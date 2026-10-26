extends RefCounted

const Scalar = preload("res://application/scalar_expression.gd")
const Native = preload("res://application/native_resource.gd")
const Media = preload("res://application/media_source.gd")
const KINDS := ["Wait", "WaitInput", "Clear", "TextInput", "Style", "Setting", "Background", "Audio", "Voice", "History", "Save"]

static func create(kind: String) -> DialogicEvent:
	match kind:
		"Wait": return DialogicWaitEvent.new()
		"WaitInput": return DialogicWaitInputEvent.new()
		"Clear": return load("res://addons/dialogic/Modules/Clear/event_clear.gd").new()
		"TextInput": return DialogicTextInputEvent.new()
		"Style": return DialogicStyleEvent.new()
		"Setting": return DialogicSettingEvent.new()
	return Media.create(kind)

static func kind_of(event: DialogicEvent) -> String:
	for kind: String in KINDS:
		if event.get_script() == create(kind).get_script(): return kind
	return ""

static func setting_name_error(value: String) -> String:
	if value.is_empty() or RegEx.create_from_string('["=+*/\\\\\\-\\r\\n]').search(value): return "Setting names must be nonempty and compatible with the native parser."
	var host := Node.new()
	var reserved := ["settings", "_connections", "dialogic", "name", "script"]
	for prop: Dictionary in host.get_property_list(): reserved.append(prop.name)
	host.free()
	return "This name collides with a subsystem property." if value in reserved else ""

static func inspect(raw: String, event: DialogicEvent, workspace: RefCounted = null, values: Dictionary = {}, evaluate := false) -> Dictionary:
	var kind := kind_of(event)
	if kind.is_empty(): return {"error": "Unknown interaction event."}
	if kind in Media.KINDS: return Media.inspect(raw, event, workspace)
	if kind == "Setting": return inspect_setting(raw, workspace, values, evaluate)
	var clone := create(kind)
	var code := clone.get_shortcode()
	var outer := RegEx.create_from_string('^\\[' + code + '(?:[ \\t]+(.*))?\\]$').search(raw)
	if outer == null: return {"error": "Use the native [" + code + " key=\"value\"] syntax."}
	var tail := outer.get_string(1)
	var fields: Dictionary = clone.get_shortcode_parameters()
	var input := {}
	var at := 0
	var pattern := RegEx.create_from_string('[ \\t]*([a-z_]+)[ \\t]*=[ \\t]*"((?:[^"\\\\]|\\\\.)*)"')
	while at < tail.length():
		if tail.substr(at).strip_edges().is_empty(): break
		var pair := pattern.search(tail, at)
		if pair == null or pair.get_start() != at: return {"error": "Each argument must use key=\"value\"; unexpected trailing content is protected."}
		var key := pair.get_string(1)
		if not fields.has(key) or input.has(key): return {"error": "Unknown or duplicate argument: " + key, "offset": raw.find(key)}
		var property: String = fields[key].property
		var value: String = pair.get_string(2).replace('\\"', '"')
		var type := typeof(clone.get(property))
		if type == TYPE_BOOL and not value in ["true", "false"]: return {"error": key + " requires true or false."}
		if type in [TYPE_FLOAT, TYPE_INT] and (not value.is_valid_float() or not is_finite(value.to_float()) or value.to_float() < 0): return {"error": key + " requires a finite nonnegative number."}
		input[key] = value if type == TYPE_STRING else (value == "true" if type == TYPE_BOOL else value.to_float())
		at = pair.get_end()
	clone.from_text(raw)
	for key: String in input:
		if clone.get(fields[key].property) != input[key]: return {"error": "The fixed native parser cannot preserve the supplied value for " + key + "."}
	if kind == "TextInput":
		var name: String = clone.variable.trim_prefix("{").trim_suffix("}")
		if not name.is_valid_identifier() or not values.has(name) or not values[name] is String: return {"error": "TextInput requires an existing string variable in the selected content root."}
		if clone.variable != name and clone.variable != "{" + name + "}": return {"error": "Use a string variable name or {name}."}
	if kind == "Style" and workspace != null:
		var problem: String = workspace.style_error(clone.style_name)
		if not problem.is_empty(): return {"error": problem}
	elif kind == "Style" and not clone.style_name.is_empty(): return {"error": "Choose a content folder with this style."}
	var properties := {}
	for key: String in fields: properties[fields[key].property] = clone.get(fields[key].property)
	return {"kind": "interaction", "interaction": kind, "properties": properties, "event": clone, "raw": raw}

static func inspect_setting(raw: String, workspace: RefCounted, values: Dictionary, evaluate: bool) -> Dictionary:
	var match_value := RegEx.create_from_string('^setting +(?:(reset)(?: +"([^"\\r\\n]*)")? *|"([^"\\r\\n]+)" *= *(.*))$').search(raw)
	if match_value == null: return {"error": "Use setting \"name\" = value, setting reset \"name\", or setting reset."}
	var event := DialogicSettingEvent.new()
	var name := match_value.get_string(2) if not match_value.get_string(1).is_empty() else match_value.get_string(3)
	if not name.is_empty():
		var issue := setting_name_error(name)
		if not issue.is_empty(): return {"error": issue}
	var expected: Variant
	var literal := match_value.get_string(4).strip_edges()
	if match_value.get_string(1).is_empty():
		if literal.begins_with('"') and literal.ends_with('"'):
			var parsed := Native.decode(literal)
			if parsed.has("error") or not parsed.get("value") is String: return {"error": "Invalid native Setting string."}
			expected = parsed.value
			if expected.contains('"') or expected.contains("\\"): return {"error": "Alpha 20 Setting string parsing cannot preserve quotes/backslashes; use a string variable instead."}
		else:
			var checked := Scalar.inspect(literal, values, evaluate)
			if checked.has("error"): return checked
			expected = checked.get("value")
		if (evaluate or expected is String) and name in ["text_speed", "autoadvance_delay_modifier"] and (not typeof(expected) in [TYPE_INT, TYPE_FLOAT] or not is_finite(expected) or expected < 0): return {"error": "Text speed and auto-advance modifiers require finite nonnegative numbers."}
	event.from_text(raw)
	var properties := {"mode": event.mode, "name": event.name, "value": event.value, "_value_type": event._value_type}
	if event.name != name: return {"error": "Native Setting name did not survive parsing."}
	return {"kind": "interaction", "interaction": "Setting", "properties": properties, "event": event, "raw": raw, "evaluated_value": expected}

static func setting_transition_error(parsed: Dictionary, current: Dictionary) -> String:
	if parsed.has("error") or parsed.get("interaction") != "Setting" or parsed.properties.mode != 0: return ""
	var name: String = parsed.properties.name
	if not current.has(name): return ""
	var before := typeof(current[name])
	var after := typeof(parsed.evaluated_value)
	if before == after or (before in [TYPE_INT, TYPE_FLOAT] and after in [TYPE_INT, TYPE_FLOAT]): return ""
	return "Dialogic alpha-20 cannot compare the current and new types for setting '%s'. Use a matching type/default, or reset an undeclared setting before changing its type." % name

static func mismatch(event: DialogicEvent, expected: Dictionary) -> String:
	if kind_of(event) != expected.interaction: return "The native parser changed the interaction event type."
	for property: String in expected.properties:
		if event.get(property) != expected.properties[property]: return "The native parser changed interaction property: " + property
	return ""

static func serialize(kind: String, fields: Dictionary) -> Dictionary:
	if kind in Media.KINDS: return Media.serialize(kind, fields)
	var event := create(kind)
	if event == null: return {"error": "Unknown event kind."}
	if kind == "Setting":
		var mode: int = fields.get("mode", 0)
		if mode == 2: return {"source": "setting reset"}
		var name: String = fields.get("name", "")
		var issue := setting_name_error(name)
		if not issue.is_empty(): return {"error": issue}
		if mode == 1: return {"source": 'setting reset "' + name + '"'}
		var value: String = str(fields.get("value", ""))
		match int(fields.get("_value_type", 0)):
			0: value = var_to_str(value)
			2: value = "{" + value + "}"
		return {"source": 'setting "' + name + '" = ' + value}
	var parts := PackedStringArray()
	for key: String in event.get_shortcode_parameters():
		var property: String = event.get_shortcode_parameters()[key].property
		var value: Variant = fields.get(property, event.get(property))
		var text := (var_to_str(value) if value is float else str(value)).replace('"', '\\"')
		if text.contains("\n") or text.contains("\r"): return {"error": "Shortcode fields must be a single physical line."}
		parts.append(key + '="' + text + '"')
	return {"source": "[" + event.get_shortcode() + " " + " ".join(parts) + "]"}
