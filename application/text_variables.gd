class_name TextVariables
extends RefCounted

## Validate the supported subset before the upstream expression fallback runs.
## Replacement order intentionally matches Alpha 20's parse_variables: matches
## come from the original text; each replacement acts on the entire result.
## https://docs.dialogic.pro/variables.html
const Scalar = preload("res://application/scalar_expression.gd")
const MAX_EXPANDED_BYTES: int = 4 * 1024 * 1024


static func inspect(text: String, workspace: RefCounted = null, runtime: Variant = null, evaluate: bool = true) -> Dictionary:
	var regex := RegEx.create_from_string(r"(?<!\\)\{(?<variable>([^{}]|\{[^}]*\})*)\}")
	var matches: Array[RegExMatch] = regex.search_all(text)
	var by_start: Dictionary = {}
	for found: RegExMatch in matches:
		by_start[found.get_start()] = found
	var index: int = 0
	var escaped_depth: int = 0
	while index < text.length():
		var character: String = text[index]
		if character == "{" and index > 0 and text[index - 1] == "\\":
			escaped_depth += 1
		elif character == "{" and by_start.has(index):
			var found: RegExMatch = by_start[index]
			index = found.get_end()
			continue
		elif character == "{":
			return _issue(index, "Unclosed or nested variable reference. Use {variable_name}, or escape a literal opening brace with \\{.")
		elif character == "}":
			if escaped_depth > 0:
				escaped_depth -= 1
			elif index == 0 or text[index - 1] != "\\":
				return _issue(index, "Unexpected closing brace outside a variable reference.")
		index += 1
	var defaults: Dictionary = {}
	if not matches.is_empty() and workspace != null and workspace.variable_document != null:
		var model: RefCounted = workspace.variable_document
		var problem: String = model.preview_error()
		if not problem.is_empty():
			return _issue(matches[0].get_start(), problem)
		defaults = model.runtime_values() if runtime == null else runtime
	var expanded: String = text.replace("\\{", "{")
	for found: RegExMatch in matches:
		var key: String = found.get_string("variable")
		var evaluated: Dictionary = Scalar.inspect(key, defaults, evaluate)
		if evaluated.has("error"):
			var offset: int = found.get_start() if valid_name(key) else found.get_start() + 1 + evaluated.get("offset", 0)
			return _issue(offset, evaluated.error)
		if not evaluate:
			continue
		var token: String = "{" + key + "}"
		var value: String = str(evaluated.value)
		# Bound replacement allocation before constructing the expanded text.
		var projected: int = expanded.to_utf8_buffer().size() + expanded.count(token) * (value.to_utf8_buffer().size() - token.to_utf8_buffer().size())
		if projected > MAX_EXPANDED_BYTES:
			return _issue(found.get_start(), "Expanded dialogue exceeds the 4 MiB preview text limit.")
		expanded = expanded.replace(token, value)
	var scope: Dictionary = text_scope(expanded)
	if not scope.is_empty():
		# Effects introduced by values belong to the reference in the source.
		var offset: int = int(scope["offset"])
		if not matches.is_empty():
			offset = matches[0].get_start()
		return _issue(offset, "Expanded text: " + str(scope["error"]))
	return {"expanded": expanded, "variables": defaults, "references": matches.size()}


static func valid_name(value: String) -> bool:
	return RegEx.create_from_string(r"\A[A-Za-z_][A-Za-z0-9_]*\z").search(value) != null


static func mask_expressions(text: String) -> String:
	# Preserve source offsets while checking literal text around expressions.
	# Native variable expansion runs before random-text modifiers, so a comparison
	# and division inside one expression must not be read as <random/selection>.
	var regex := RegEx.create_from_string(r"(?<!\\)\{(?<variable>([^{}]|\{[^}]*\})*)\}")
	var pieces := PackedStringArray()
	var start := 0
	for found: RegExMatch in regex.search_all(text):
		pieces.append(text.substr(start, found.get_start() - start))
		pieces.append(" ".repeat(found.get_end() - found.get_start()))
		start = found.get_end()
	pieces.append(text.substr(start))
	return "".join(pieces)


static func text_scope(text: String) -> Dictionary:
	var first: int = -1
	for character: String in "[]":
		var at: int = text.find(character)
		while at > 0 and text[at - 1] == "\\":
			at = text.find(character, at + 1)
		if at >= 0 and (first < 0 or at < first):
			first = at
	if first >= 0:
		return _issue(first, "BBCode, inline effects and text modifiers require a later version.")
	var random_match: RegExMatch = RegEx.create_from_string(r"(?<!\\)<[^>]+/[^>]*>").search(text)
	if random_match != null:
		return _issue(random_match.get_start(), "Random text selection requires a later version.")
	return {}


static func _issue(offset: int, message: String) -> Dictionary:
	return {"offset": offset, "error": message}
