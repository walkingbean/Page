class_name ConditionalText
extends RefCounted

## Alpha 20 Core modifier (order 20), followed by variables (order 30).
## Keep the upstream regex and original-match/global-replacement semantics.
const PATTERN := r"(?(DEFINE)(?<nobraces>([^{}]|\{(?P>nobraces)\})*))\[if *(?<condition>(\{(?P>nobraces)\}|true\b|false\b))(?<truetext>(\\\]|\\\/|[^\]\/])*)(\/(?<falsetext>(\\\]|[^\]])*))?\]"
const Scalar = preload("res://application/scalar_expression.gd")
const Variables = preload("res://application/text_variables.gd")


static func expression_model(condition: String, values: Variant = null, evaluate := false) -> Dictionary:
	# {name} is a native reference; {expression} is the modifier's expression
	# wrapper, removed by native execute_string after inner references expand.
	var expression := condition
	var shift := 0
	var inner := condition.substr(1, condition.length() - 2) if condition.begins_with("{") else ""
	if condition.begins_with("{") and (not Variables.valid_name(inner) or (inner in ["true", "false"] and (values == null or not values.has(inner)))):
		expression = condition.substr(1, condition.length() - 2)
		shift = 1
	var checked := Scalar.inspect(expression, values, evaluate, false)
	if checked.has("error"):
		checked.offset += shift
	return checked


static func inspect(text: String, workspace: RefCounted = null, runtime: Variant = null, evaluate := true) -> Dictionary:
	var matches := RegEx.create_from_string(PATTERN).search_all(text)
	if matches.is_empty():
		var malformed := _malformed(Variables.mask_expressions(text))
		if not malformed.is_empty():
			return malformed
		return Variables.inspect(text, workspace, runtime, evaluate)
	var values: Dictionary = runtime if runtime != null else (workspace.variable_document.runtime_values() if workspace != null and workspace.variable_document != null else {})
	var outside := text
	for found: RegExMatch in matches:
		outside = outside.replace(found.get_string(), " ".repeat(found.get_string().length()))
	var malformed := _malformed(Variables.mask_expressions(outside))
	if not malformed.is_empty():
		return malformed
	var literal := Variables.text_scope(Variables.mask_expressions(outside))
	if not literal.is_empty():
		return literal
	var expanded := text
	var positions := PackedInt32Array()
	positions.resize(text.length())
	for i: int in text.length():
		positions[i] = i
	for found: RegExMatch in matches:
		var checked := expression_model(found.get_string("condition"), values, evaluate)
		if checked.has("error"):
			checked.offset += found.get_start("condition")
			return checked
		# Validate both alternatives without executing inactive arithmetic.
		for group: String in ["truetext", "falsetext"]:
			var branch := found.get_string(group)
			if branch.contains("[if"):
				return {"offset": found.get_start(group) + branch.find("[if"), "error": "Nested inline condition modifiers are not supported by this native syntax. Use nested timeline conditions."}
			var syntax := Variables.inspect(branch, workspace, values, false)
			if syntax.has("error"):
				syntax.offset += maxi(found.get_start(group), 0)
				return syntax
		var group := "truetext" if checked.get("value", false) else "falsetext"
		var insert := found.get_string(group)
		var origin := maxi(found.get_start(group), found.get_start()) + insert.length() - insert.strip_edges(true, false).length()
		var token := found.get_string()
		if insert.strip_edges().is_empty() and " " + token + " " in expanded:
			token += " "
		insert = insert.strip_edges()
		var start := 0
		var at := expanded.find(token)
		var pieces := PackedStringArray()
		var mapped := PackedInt32Array()
		while at >= 0:
			pieces.append(expanded.substr(start, at - start))
			mapped.append_array(positions.slice(start, at))
			pieces.append(insert)
			for i: int in insert.length():
				mapped.append(origin + i)
			start = at + token.length()
			at = expanded.find(token, start)
		pieces.append(expanded.substr(start))
		mapped.append_array(positions.slice(start))
		expanded = "".join(pieces)
		positions = mapped
	var result := Variables.inspect(expanded, workspace, values, evaluate)
	if result.has("error"):
		result.offset = positions[mini(int(result.offset), positions.size() - 1)] if not positions.is_empty() else 0
	return result


static func _malformed(text: String) -> Dictionary:
	var at := text.find("[if")
	if at >= 0:
		return {"offset": at, "error": "Malformed conditional text. Use [if true yes/no], [if {flag} yes/no], or [if {{score} > 1} yes/no], with a closing ]."}
	return {}
