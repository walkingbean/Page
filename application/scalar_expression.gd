class_name ScalarExpression
extends RefCounted

## A closed scalar grammar checked before the unchanged Dialogic runtime runs.
## Operations themselves use Godot Expression, including its eager boolean rules.
const Literal = preload("res://application/variable_literal.gd")
const MAX_SOURCE_BYTES := 65536
const MAX_TOKENS := 1024
const MAX_DEPTH := 64
const MAX_VALUE_BYTES := 4 * 1024 * 1024
const PRIORITY := {"or": 10, "||": 10, "and": 20, "&&": 20,
	"==": 40, "!=": 40, "<": 40, ">": 40, "<=": 40, ">=": 40,
	"+": 50, "-": 50, "*": 60, "/": 60, "%": 60, "**": 90}

var tokens: Array[Dictionary] = []
var cursor := 0
var issue: Dictionary = {}
var syntax_only := false


static func inspect(source: String, values: Variant = null) -> Dictionary:
	if source.to_utf8_buffer().size() > MAX_SOURCE_BYTES:
		return _error(0, "Expression exceeds the 65536-byte source limit.")
	if source.is_empty():
		return _error(0, "Enter an expression.")
	var worker := ScalarExpression.new()
	worker.syntax_only = values == null
	var scanned := worker._scan(source, true)
	if scanned.has("error"):
		return scanned
	# VAR.get_variable performs a direct lookup before expression evaluation.
	var key := source
	if key.begins_with("{") and key.ends_with("}") and key.count("{") == 1:
		key = key.trim_prefix("{").trim_suffix("}")
	if values != null and values.has(key):
		return _value(values[key], 0)
	var compiled := source
	var references := RegEx.create_from_string(r"\{([A-Za-z_][A-Za-z0-9_]*)\}").search_all(source)
	for found: RegExMatch in references:
		var name := found.get_string(1)
		if values != null and not values.has(name):
			return _error(found.get_start(), "Variable '%s' is missing or has an unsupported type. Names are case-sensitive." % name)
		var replacement := "1" if values == null else var_to_str(values[name])
		if values != null:
			var checked := _value(values[name], found.get_start())
			if checked.has("error"):
				return checked
		var projected := compiled.to_utf8_buffer().size() + compiled.count(found.get_string()) * (replacement.to_utf8_buffer().size() - found.get_string().to_utf8_buffer().size())
		if projected > MAX_VALUE_BYTES:
			return _error(found.get_start(), "Expanded expression exceeds the 4 MiB limit.")
		# Match Alpha 20: original match list, global replacement on current text.
		compiled = compiled.replace(found.get_string(), replacement)
	if RegEx.create_from_string(r"\A[A-Za-z_][A-Za-z0-9_]*\z").search(source) != null and source not in ["true", "false"]:
		if values != null:
			return _error(0, "Variable '%s' is missing or has an unsupported type. Names are case-sensitive." % source)
		compiled = "1"
	# Native rewrites these sequences before reference replacement. Reject literal
	# spellings that would silently change user text; the literal form encodes them.
	for marker: String in ["range(", "len(", "regex("]:
		if source.contains(marker):
			return _error(source.find(marker), "This spelling invokes native expression preprocessing. Encode '(' as \\u0028 inside a string.")
	worker.tokens.clear()
	var checked := worker._scan(compiled, false)
	if checked.has("error"):
		checked.offset = 0 if not references.is_empty() else checked.offset
		return checked
	var native := Expression.new()
	if native.parse(compiled) != OK:
		return _error(0, "Native expression syntax: " + native.get_error_text())
	var result: Variant = worker._parse(0)
	if not worker.issue.is_empty():
		if not references.is_empty():
			worker.issue.offset = 0
		return worker.issue
	if worker.cursor != worker.tokens.size():
		return _error(worker.tokens[worker.cursor].at, "Unexpected expression token.")
	if values == null:
		return {"expression": source}
	# The bounded walk has checked every eager operation; now obtain the exact
	# whole-expression value from the same engine parser used by Dialogic.
	var actual: Variant = native.execute([], null, false)
	if native.has_execute_failed():
		return _error(0, "Native expression evaluation: " + native.get_error_text())
	if typeof(actual) != typeof(result) or actual != result:
		return _error(0, "Expression grouping differs from the native parser. Add explicit parentheses.")
	return _value(actual, 0)


func _scan(source: String, original: bool) -> Dictionary:
	var i := 0
	var depth := 0
	while i < source.length():
		var at := i
		var c := source[i]
		if c in [" ", "\t", "\r", "\n"]:
			i += 1
			continue
		if tokens.size() >= MAX_TOKENS:
			return _error(i, "Expression exceeds the 1024-token limit.")
		if c == '"':
			i += 1
			while i < source.length():
				if source[i] == "\\":
					i += 2
				elif source[i] == '"':
					i += 1
					break
				else:
					i += 1
			var spelling := source.substr(at, i - at)
			if original and (spelling.contains("{") or spelling.contains("}")):
				return _error(at, "Encode braces inside expression strings as \\u007b and \\u007d to preserve native preprocessing.")
			var parsed := Literal.parse_token(spelling)
			if parsed.has("error"):
				return _error(at, parsed.error)
			tokens.append({"kind": "value", "value": parsed.value, "at": at})
			continue
		if c == "{" and original:
			var end := source.find("}", i + 1)
			if end < 0 or RegEx.create_from_string(r"\A[A-Za-z_][A-Za-z0-9_]*\z").search(source.substr(i + 1, end - i - 1)) == null:
				return _error(i, "Use a flat variable reference such as {score}.")
			tokens.append({"kind": "value", "value": 1, "at": at})
			i = end + 1
			continue
		var number := RegEx.create_from_string(r"\A(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?").search(source.substr(i))
		if number != null:
			var token := number.get_string()
			var parsed := Literal.parse_token(token)
			if parsed.has("error"):
				# The signed minimum is representable only with its unary minus.
				if token == "9223372036854775808" and not tokens.is_empty() and tokens[-1].kind == "-":
					parsed = {"value": -9223372036854775807 - 1}
				else:
					return _error(i, parsed.error)
			tokens.append({"kind": "value", "value": parsed.value, "at": at})
			i += token.length()
			continue
		var word := RegEx.create_from_string(r"\A[A-Za-z_][A-Za-z0-9_]*").search(source.substr(i))
		if word != null:
			var token := word.get_string()
			if token in ["true", "false"]:
				tokens.append({"kind": "value", "value": token == "true", "at": at})
			elif token in ["and", "or", "not"]:
				tokens.append({"kind": token, "at": at})
			elif original and token == source:
				tokens.append({"kind": "value", "value": 1, "at": at})
			else:
				return _error(i, "Use {name} for a variable inside an expression. Functions and host access require a later version.")
			i += token.length()
			continue
		var op := source.substr(i, 2)
		if not op in ["**", "==", "!=", "<=", ">=", "&&", "||"]:
			op = c
		if not PRIORITY.has(op) and not op in ["(", ")", "!"]:
			return _error(i, "Unsupported expression token. Use scalar arithmetic, comparison and logic only.")
		if op == "(":
			depth += 1
			if depth > MAX_DEPTH:
				return _error(i, "Expression exceeds the 64-level parentheses limit.")
		elif op == ")":
			depth -= 1
			if depth < 0:
				return _error(i, "Unexpected closing parenthesis.")
		tokens.append({"kind": op, "at": at})
		i += op.length()
	if depth != 0:
		return _error(source.length(), "Unclosed parenthesis.")
	return {}


func _parse(minimum: int, depth: int = 0) -> Variant:
	if depth > 128:
		issue = _error(tokens[mini(cursor, tokens.size() - 1)].at, "Expression exceeds the 128-level operand nesting limit.")
		return null
	if cursor >= tokens.size():
		issue = _error(0, "Missing expression operand.")
		return null
	var token: Dictionary = tokens[cursor]
	cursor += 1
	var left: Variant
	if token.kind == "value":
		left = token.value
	elif token.kind in ["-", "not", "!"]:
		left = _parse(80 if token.kind == "-" else 30, depth + 1)
		if not syntax_only and issue.is_empty():
			left = _operation(token.kind, left, null, token.at)
	elif token.kind == "(":
		left = _parse(0, depth + 1)
		if cursor >= tokens.size() or tokens[cursor].kind != ")":
			issue = _error(token.at, "Unclosed parenthesis.")
			return null
		cursor += 1
	else:
		issue = _error(token.at, "Expected an expression operand.")
		return null
	while issue.is_empty() and cursor < tokens.size():
		token = tokens[cursor]
		if not PRIORITY.has(token.kind) or PRIORITY[token.kind] < minimum:
			break
		cursor += 1
		var right: Variant = _parse(PRIORITY[token.kind] + 1, depth + 1)
		if not syntax_only and issue.is_empty():
			left = _operation(token.kind, left, right, token.at)
	return left


func _operation(op: String, left: Variant, right: Variant, at: int) -> Variant:
	if right != null and op in ["/", "%"] and (right is int or right is float) and right == 0:
		issue = _error(at, "Division or modulo by zero.")
		return null
	if op == "%" and left is String:
		issue = _error(at, "String formatting requires a later version; % currently supports numeric modulo.")
		return null
	if op == "+" and left is String and right is String and left.to_utf8_buffer().size() + right.to_utf8_buffer().size() > MAX_VALUE_BYTES:
		issue = _error(at, "Expression string exceeds the 4 MiB limit.")
		return null
	if op == "*" and ((left is String and right is int) or (right is String and left is int)):
		issue = _error(at, "String repetition is outside the scalar arithmetic scope.")
		return null
	if op in ["/", "%"] and left is int and right is int and left == (-9223372036854775807 - 1) and right == -1:
		issue = _error(at, "Integer division exceeds the signed 64-bit range.")
		return null
	var evaluator := Expression.new()
	var expression := op + " a" if right == null else "a " + op + " b"
	if evaluator.parse(expression, PackedStringArray(["a", "b"])) != OK:
		issue = _error(at, evaluator.get_error_text())
		return null
	var actual: Variant = evaluator.execute([left, right], null, false)
	if evaluator.has_execute_failed():
		issue = _error(at, "Expression type error: " + evaluator.get_error_text())
		return null
	var checked := _value(actual, at)
	if checked.has("error"):
		issue = checked
	return actual


static func _value(value: Variant, at: int) -> Dictionary:
	if not Literal.supported(value):
		return _error(at, "Expression must produce a finite String, Int, Float or Bool value.")
	if value is String and (value.to_utf8_buffer().size() > MAX_VALUE_BYTES or value.to_utf8_buffer().has(0)):
		return _error(at, "Expression string contains NUL or exceeds the 4 MiB limit.")
	return {"value": value}


static func _error(at: int, message: String) -> Dictionary:
	return {"offset": at, "error": message}
