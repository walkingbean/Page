class_name FlowSource
extends RefCounted

const Scalar = preload("res://application/scalar_expression.gd")
const Inline = preload("res://application/conditional_text.gd")
const Variables = preload("res://application/text_variables.gd")


static func is_flow(event: DialogicEvent) -> bool:
	return event is DialogicChoiceEvent or event is DialogicLabelEvent or event is DialogicJumpEvent or event is DialogicReturnEvent or event is DialogicEndTimelineEvent


static func inspect(raw: String, event: DialogicEvent, workspace: RefCounted = null, values: Variant = null, evaluate: bool = false) -> Dictionary:
	if event is DialogicChoiceEvent:
		return choice(raw, workspace, values, evaluate)
	if event is DialogicReturnEvent:
		return {"kind": "return"} if raw.strip_edges() == "return" else {"error": "Use return without arguments."}
	if event is DialogicEndTimelineEvent:
		return {"kind": "finish"} if raw.strip_edges() == "[end_timeline]" else {"error": "End uses [end_timeline] without arguments."}
	if event is DialogicLabelEvent:
		var matched := RegEx.create_from_string(r"\Alabel +(?<name>[^()\r\n]+?)(?: *\((?<display>[^()\r\n]+)\))? *\z").search(raw)
		if matched == null or matched.get_string("name").strip_edges().is_empty():
			return {"error": "Use label Identifier or label Identifier (Display Name)."}
		var parsed := DialogicLabelEvent.new()
		parsed.from_text(raw)
		return {"kind": "label", "name": parsed.name, "display_name": parsed.display_name}
	if event is DialogicJumpEvent:
		if raw != "jump" and not raw.begins_with("jump "):
			return {"error": "Use jump, jump Label, jump Timeline/ or jump Timeline/Label."}
		var target := raw.trim_prefix("jump").strip_edges()
		if target.contains("\n") or target.contains("\t"):
			return {"error": "A Jump target must occupy one line."}
		var slash := target.rfind("/")
		var timeline := target.left(slash) if slash >= 0 else ""
		var label := target.substr(slash + 1)
		if slash >= 0 and timeline.is_empty():
			return {"error": "A cross-timeline Jump requires a timeline identifier before /."}
		if timeline.contains("{") or timeline.contains("}"):
			return {"error": "Alpha 20 resolves a fixed timeline identifier; variables may be used in the label."}
		var checked := Variables.inspect(label, workspace, values, evaluate)
		if checked.has("error"):
			checked.offset += raw.find(label)
			return checked
		return {"kind": "jump", "timeline_identifier": timeline, "label_name": label, "expanded_label": checked.expanded}
	return {"error": "Unsupported flow event."}


static func choice(raw: String, workspace: RefCounted = null, values: Variant = null, evaluate: bool = false) -> Dictionary:
	var native := DialogicChoiceEvent.new()
	var found := native.regex.search(raw)
	if not raw.begins_with("- ") or found == null or found.get_start() != 0 or found.get_end() != raw.length():
		return {"error": "Use - Choice text | [if expression] [else=\"hide\"]. The native parser must consume the complete line."}
	var shortcode := found.get_string("shortcode")
	var parameter_regex := RegEx.create_from_string(r'(?<parameter>[^\s=]+)\s*=\s*"(?<value>(\{[^}]*\}|\[[^]]*\]|([^"\\]|\\.)*))"')
	var consumed := 0
	var keys := {}
	for pair: RegExMatch in parameter_regex.search_all(shortcode):
		if not shortcode.substr(consumed, pair.get_start() - consumed).strip_edges().is_empty():
			return {"error": "Choice parameters must be complete key=\"value\" pairs."}
		var key := pair.get_string("parameter")
		if keys.has(key):
			return {"error": "Duplicate Choice parameter: " + key}
		keys[key] = pair.get_string("value")
		consumed = pair.get_end()
	if not shortcode.substr(consumed).strip_edges().is_empty():
		return {"error": "Incomplete Choice parameter or unsupported native quoting."}
	if keys.has("else") and not keys.else in ["hide", "disable", "default", "0", "1", "2"]:
		return {"error": "Choice else must be hide, disable or default."}
	native.from_text(raw)
	if native.text.is_empty():
		return {"error": "A Choice needs nonempty button text."}
	var condition := {"value": true}
	if not native.condition.is_empty():
		condition = Scalar.inspect(native.condition, values, evaluate, false)
		if condition.has("error"):
			condition.offset += maxi(0, raw.find(native.condition))
			return condition
	elif raw.contains("[if") and found.get_string("text").find("[if") < 0:
		return {"error": "The Choice condition cannot be empty."}
	for text: String in [native.text, native.disabled_text]:
		var check := Inline.inspect(text.replace("\\|", "|"), workspace, values, false)
		if check.has("error"):
			check.offset += maxi(0, raw.find(text))
			return check
	if evaluate:
		var shown := native.text if condition.value or native.disabled_text.is_empty() else native.disabled_text
		var check := Inline.inspect(shown.replace("\\|", "|"), workspace, values, true)
		if check.has("error"):
			check.offset += maxi(0, raw.find(shown))
			return check
	return {"kind": "choice", "text": native.text, "expression": native.condition,
		"else_action": native.else_action, "disabled_text": native.disabled_text, "extra_data": native.extra_data}


static func mismatch(parsed: DialogicEvent, expected: Dictionary) -> String:
	match expected.kind:
		"choice":
			if not parsed is DialogicChoiceEvent or parsed.text != expected.text or parsed.condition != expected.expression or parsed.else_action != expected.else_action or parsed.disabled_text != expected.disabled_text or parsed.extra_data != expected.extra_data:
				return "The native parser did not preserve all Choice properties."
		"label":
			if not parsed is DialogicLabelEvent or parsed.name != expected.name or parsed.display_name != expected.display_name:
				return "The native parser did not preserve the Label properties."
		"jump":
			if not parsed is DialogicJumpEvent or parsed.timeline != DialogicResourceUtil.get_timeline_resource(expected.timeline_identifier) or parsed.label_name != expected.label_name:
				return "The native parser did not preserve the Jump target."
		"return":
			if not parsed is DialogicReturnEvent: return "Expected native Return."
		"finish":
			if not parsed is DialogicEndTimelineEvent: return "Expected native End."
	return ""
