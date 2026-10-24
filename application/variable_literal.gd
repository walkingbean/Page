class_name VariableLiteral
extends RefCounted

## Only primitive literals reach Expression. No host or user code is evaluated.
## Alpha 20 rewrites braces and several function names even inside strings.
## Encode those characters before the native event parser sees the source.
static func supported(value: Variant) -> bool:
	return value is String or value is int or value is bool or (value is float and is_finite(value))


static func parse_field(text: String, kind: int) -> Dictionary:
	if kind == TYPE_STRING:
		if text.to_utf8_buffer().has(0):
			return {"error": "NUL is not supported in variable values."}
		return {"value": text}
	if kind == TYPE_BOOL:
		if text in ["true", "false"]:
			return {"value": text == "true"}
		return {"error": "Enter true or false for a Bool value."}
	if kind == TYPE_INT:
		if RegEx.create_from_string(r"\A[+-]?[0-9]+\z").search(text) == null:
			return {"error": "Enter an integer literal without spaces or expressions."}
		var digits := text.trim_prefix("-").trim_prefix("+")
		while digits.length() > 1 and digits.begins_with("0"):
			digits = digits.substr(1)
		var limit := "9223372036854775808" if text.begins_with("-") else "9223372036854775807"
		if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit):
			return {"error": "Integer exceeds the signed 64-bit range."}
		return {"value": text.to_int()}
	if kind == TYPE_FLOAT:
		if RegEx.create_from_string(r"\A[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\z").search(text) == null or not is_finite(text.to_float()):
			return {"error": "Enter a finite decimal Float literal; expressions, NaN and infinity are not supported."}
		return {"value": text.to_float()}
	return {"error": "Only String, Int, Float and Bool values are editable."}


static func parse_token(token: String) -> Dictionary:
	if token in ["true", "false"]:
		return {"value": token == "true"}
	if token.begins_with('"'):
		# This closed string grammar permits escapes but no executable suffix.
		if RegEx.create_from_string(r'\A"(?:[^"\\\r\n]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"\z').search(token) == null:
			return {"error": "Use one closed quoted string with valid escapes."}
		var expression := Expression.new()
		if expression.parse(token) != OK:
			return {"error": expression.get_error_text()}
		var value: Variant = expression.execute([], null, false)
		if expression.has_execute_failed() or not value is String or value.to_utf8_buffer().has(0):
			return {"error": "The string literal cannot be represented by the native parser."}
		return {"value": value}
	var kind := TYPE_FLOAT if token.contains(".") or token.to_lower().contains("e") else TYPE_INT
	return parse_field(token, kind)


static func encode(value: Variant) -> String:
	if value is String:
		return JSON.stringify(value).replace('\\"', '\\u0022').replace("{", "\\u007b").replace("}", "\\u007d").replace("(", "\\u0028")
	return var_to_str(value)


static func inspect_event(source: String, values: Variant = null) -> Dictionary:
	var found := RegEx.create_from_string(r"\Aset[ \t]+\{(?<name>[A-Za-z_][A-Za-z0-9_]*)\}[ \t]*=[ \t]*(?<literal>[^\r\n]+?)[ \t]*\z").search(source)
	if found == null:
		return {"error": "Use set {variable_name} = literal. Only direct literal assignment is supported.", "offset": 0}
	var name: String = found.get_string("name")
	var token: String = found.get_string("literal")
	var result: Dictionary = parse_token(token)
	if result.has("error"):
		result["offset"] = found.get_start("literal")
		return result
	if values != null and not values.has(name):
		return {"error": "Assignment target '%s' is missing or has an unsupported type." % name, "offset": found.get_start("name")}
	# Compare with the upstream parser and its expression preprocessing, without
	# evaluating any unvalidated input. A quoted string must stay a single literal.
	var native := DialogicVariableEvent.new()
	native.from_text(source)
	var expression_text := '"' + str(native.value) + '"' if native._value_type == DialogicVariableEvent.VarValueType.STRING else str(native.value)
	if expression_text.contains("{") or expression_text.contains("range(") or expression_text.contains("len(") or expression_text.contains("regex("):
		return {"error": "This spelling invokes native expression preprocessing. Use the Variable form to encode a literal string.", "offset": found.get_start("literal")}
	if values != null and values.has(expression_text):
		return {"error": "A variable named '%s' shadows this native literal; rename that variable before previewing." % expression_text, "offset": found.get_start("literal")}
	var interpreted: Dictionary = parse_token(expression_text)
	if interpreted.has("error") or typeof(interpreted.get("value")) != typeof(result.value) or interpreted.get("value") != result.value:
		return {"error": "Alpha 20 does not preserve this literal spelling. Use the Variable form to encode it.", "offset": found.get_start("literal")}
	# Numeric evaluation must also match the engine used by the native runtime.
	var evaluator := Expression.new()
	if evaluator.parse(expression_text) != OK:
		return {"error": "Native expression parser rejected this literal.", "offset": found.get_start("literal")}
	var actual: Variant = evaluator.execute([], null, false)
	if evaluator.has_execute_failed() or typeof(actual) != typeof(result.value) or actual != result.value:
		return {"error": "Native runtime cannot represent this literal exactly.", "offset": found.get_start("literal")}
	return {"kind": "variable", "name": name, "value": result.value, "native_value": native.value, "value_type": native._value_type}
