class_name ConditionSource
extends RefCounted

## Nested structure preflight. Native Dialogic owns parsing and execution.
const MAX_INDENT_SPACES := 32
const MAX_DEPTH := 64
const Scalar = preload("res://application/scalar_expression.gd")


static func inspect_event(source: String, values: Variant = null, evaluate: bool = true) -> Dictionary:
	var found := RegEx.create_from_string(r"\A(?<type>if|elif) +(?<expression>[^\r\n]+?):[ \t]*\z").search(source)
	if source.strip_edges() == "else:":
		return {"kind": "condition", "condition_type": DialogicConditionEvent.ConditionTypes.ELSE, "expression": "", "value": true}
	if found == null or found.get_string("expression").strip_edges().is_empty():
		return {"error": "Use if expression:, elif expression: or else:. An if/elif condition cannot be empty.", "offset": 0}
	var expression := found.get_string("expression").strip_edges()
	var start := source.find(expression, found.get_start("expression"))
	# Conditions call Expressions.execute_string, not VAR.get_variable: bare
	# variable names and names shadowing true/false must not use direct lookup.
	var checked := Scalar.inspect(expression, values, evaluate, false)
	if checked.has("error"):
		checked.offset += start
		return checked
	var native := DialogicConditionEvent.new()
	native.from_text(source)
	if native.condition != expression:
		return {"error": "The native parser did not preserve this condition spelling.", "offset": start}
	var result := {"kind": "condition", "condition_type": native.condition_type, "expression": expression}
	if checked.has("value"):
		result["value"] = true if checked.value else false
	return result


static func scan(source: String, cache: Array) -> Dictionary:
	var records: Array[Dictionary] = []
	var issues: Array[Dictionary] = []
	var lines := source.split("\n", true)
	var index := 0
	var unit := ""
	var previous_indent := ""
	var previous_opener := false
	var chains: Dictionary = {}
	var previous_depth := 0
	while index < lines.size():
		var first_line := index + 1
		var line := lines[index]
		index += 1
		var stripped := line.strip_edges(true, false)
		if stripped.is_empty():
			continue
		var indent := line.left(line.length() - stripped.length())
		var event := DialogicTimeline.event_from_string(stripped, cache)
		var raw := stripped
		var source_lines: Array[int] = [first_line]
		var source_columns: Array[int] = [indent.length() + 1]
		while not event.is_string_full_event(raw) and index < lines.size():
			var following := lines[index].strip_edges(true, false)
			var prefix := lines[index].left(lines[index].length() - following.length())
			index += 1
			if following.is_empty():
				break
			if prefix != indent:
				issues.append({"line": index, "column": 1, "message": "A continued Text line must keep the event's indentation."})
			raw += "\n" + following
			source_lines.append(index)
			source_columns.append(prefix.length() + 1)
		var condition := event is DialogicConditionEvent
		var depth := 0
		if not indent.is_empty():
			if unit.is_empty():
				unit = "\t" if indent.begins_with("\t") else indent
			if (unit != "\t" and (unit.length() > MAX_INDENT_SPACES or unit.replace(" ", "") != "")) or indent != unit.repeat(indent.length() / maxi(1, unit.length())):
				issues.append({"line": first_line, "column": 1, "message": "Use Tab or a consistent unit of 1-32 spaces, without mixing or partial levels."})
			depth = indent.length() / maxi(1, unit.length())
			if depth > MAX_DEPTH:
				issues.append({"line": first_line, "column": 1, "message": "Condition nesting exceeds 64 levels."})
			if depth > previous_depth and (not previous_opener or depth != previous_depth + 1):
				issues.append({"line": first_line, "column": 1, "message": "Indent by exactly one level after a condition header."})
			if not chains.has(depth - 1):
				issues.append({"line": first_line, "column": 1, "message": "Indented content requires a preceding condition at the parent level."})
		for level: int in chains.keys():
			if level > depth:
				chains.erase(level)
		if condition:
			var header := inspect_event(raw)
			if header.has("error"):
				issues.append({"line": first_line, "column": indent.length() + 1 + int(header.get("offset", 0)), "message": header.error})
			elif header.condition_type == DialogicConditionEvent.ConditionTypes.IF:
				chains[depth] = false
			else:
				if not chains.has(depth) or chains.get(depth, false):
					issues.append({"line": first_line, "column": indent.length() + 1, "message": "elif/else must follow an if chain at the same level; else must be last."})
				if header.condition_type == DialogicConditionEvent.ConditionTypes.ELSE:
					chains[depth] = true
		else:
			chains.erase(depth)
		# Reproduce the upstream parser's implicit end events, including empty
		# branches. Explicit <<END BRANCH>> remains outside authored .dtl syntax.
		var ends := 0
		if indent.length() < previous_indent.length():
			ends += previous_depth - depth
		if previous_opener and indent.length() <= previous_indent.length():
			ends += 1
		records.append({"event": event, "raw": raw, "line": first_line, "indent": indent,
			"source_lines": source_lines, "source_columns": source_columns, "ends_before": ends, "depth": depth})
		previous_indent = indent
		previous_depth = depth
		previous_opener = event.can_contain_events
	# Alpha 20 closes EOF indentation by character count, even for spaces.
	# Keep this native quirk visible to comparison; never rewrite the plugin.
	return {"records": records, "issues": issues, "ends_after": previous_indent.length(), "indent": unit}
