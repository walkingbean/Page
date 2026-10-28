extends RefCounted

## Editing uses source spans; unchanged events are never reserialized.
const Scan = preload("res://application/condition_source.gd")
const Codec = preload("res://application/timeline_codec.gd")

static func inspect(source: String) -> Dictionary:
	var parsed := Scan.scan(source, DialogicResourceUtil.get_event_cache())
	var offsets: Array[int] = [0]
	var lines := source.split("\n", true)
	for line: String in lines: offsets.append(offsets[-1] + line.length() + 1)
	var blocks: Array[Dictionary] = []
	for record: Dictionary in parsed.records:
		var first: int = record.source_lines[0] - 1
		var last: int = record.source_lines[-1] - 1
		var raw_line: String = lines[first]
		var indent := raw_line.left(raw_line.length() - raw_line.strip_edges(true, false).length())
		blocks.append({"start": offsets[first], "end": mini(source.length(), offsets[last + 1]), "line": first, "last_line": last, "indent": indent, "depth": record.depth, "kind": record.event.event_name, "event": record.event, "raw": record.raw})
	for index: int in blocks.size():
		blocks[index].end = blocks[index + 1].start if index + 1 < blocks.size() else source.length()
	return {"blocks": blocks, "issues": parsed.issues}

static func at_line(blocks: Array, line: int) -> int:
	for index: int in blocks.size():
		if line >= blocks[index].line and line <= blocks[index].last_line: return index
	return -1

static func expanded(blocks: Array, selection: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in selection:
		var index := int(value)
		if index < 0 or index >= blocks.size(): continue
		var block: Dictionary = blocks[index]
		if not index in result: result.append(index)
		if block.event.can_contain_events:
			for following: int in range(index + 1, blocks.size()):
				var other: Dictionary = blocks[following]
				var chain: bool = block.raw.begins_with("if ") and other.depth == block.depth and (other.raw.begins_with("elif ") or other.raw.strip_edges() == "else:")
				if other.depth < block.depth or (other.depth == block.depth and not chain): break
				if not following in result: result.append(following)
	result.sort()
	return result

static func copy(source: String, blocks: Array, selection: Array, fresh_ids := false) -> String:
	var result := ""
	for index: int in expanded(blocks, selection):
		result += source.substr(blocks[index].start, blocks[index].end - blocks[index].start)
	if fresh_ids:
		result = RegEx.create_from_string("(?m)[ \\t]*#id:[0-9a-fA-F]+[ \\t]*$").sub(result, "", true)
	return result

static func remove(source: String, blocks: Array, selection: Array) -> String:
	var selected := expanded(blocks, selection)
	selected.reverse()
	for index: int in selected: source = source.left(blocks[index].start) + source.substr(blocks[index].end)
	return source

static func insert(source: String, position: int, text: String, indent := "", fresh_ids := true) -> String:
	text = Codec.normalize_source(text)
	if fresh_ids: text = RegEx.create_from_string("(?m)[ \\t]*#id:[0-9a-fA-F]+[ \\t]*$").sub(text, "", true)
	var lines := text.split("\n", true)
	var common := ""
	var found := false
	for line: String in lines:
		if line.strip_edges().is_empty(): continue
		var prefix := line.left(line.length() - line.strip_edges(true, false).length())
		if not found: common = prefix; found = true
		else:
			while not prefix.begins_with(common): common = common.left(common.length() - 1)
	for index: int in lines.size():
		if not lines[index].is_empty(): lines[index] = indent + lines[index].trim_prefix(common)
	text = "\n".join(lines)
	position = clampi(position, 0, source.length())
	if position > 0 and source[position - 1] != "\n": text = "\n" + text
	if not text.ends_with("\n"): text += "\n"
	return source.left(position) + text + source.substr(position)

static func move(source: String, blocks: Array, selection: Array, target: int) -> Dictionary:
	var selected := expanded(blocks, selection)
	if selected.is_empty(): return {"error": "Select an event first."}
	if target in selected or target < 0 or target > blocks.size(): return {"error": "Cannot move a block into itself."}
	var at: int = blocks[target].start if target < blocks.size() else source.length()
	var indent: String = blocks[target].indent if target < blocks.size() else blocks[selected[0]].indent
	var text := copy(source, blocks, selected)
	var removed := 0
	for index: int in selected:
		if blocks[index].start < at: removed += blocks[index].end - blocks[index].start
	var next := insert(remove(source, blocks, selected), at - removed, text, indent, false)
	return checked(next)

static func checked(source: String) -> Dictionary:
	if source.to_utf8_buffer().size() > Codec.MAX_SOURCE_BYTES or source.to_utf8_buffer().has(0): return {"error": "The result must be UTF-8 text without NUL and at most 4 MiB."}
	var parsed := inspect(source)
	if not parsed.issues.is_empty(): return {"error": str(parsed.issues[0].message)}
	for block: Dictionary in parsed.blocks:
		if block.event is DialogicTextEvent:
			var unknown := Codec.unknown_shortcode(block.raw)
			if not unknown.is_empty(): return {"error": "Unregistered event-like shortcode: " + unknown + ". Keep the original source or escape the opening bracket for literal text."}
	return {"source": source}

static func offset(editor: TextEdit, line: int, column: int) -> int:
	var result := column
	for i: int in line: result += editor.get_line(i).length() + 1
	return result

static func location(source: String, position: int) -> Vector2i:
	var prefix := source.left(position)
	return Vector2i(prefix.length() - prefix.rfind("\n") - 1, prefix.count("\n"))

static func apply(editor: CodeEdit, source: String, caret := -1) -> void:
	if not editor.editable or source == editor.text: return
	if editor.has_meta("page_prepare_source"): editor.get_meta("page_prepare_source").call(source)
	var at := offset(editor, editor.get_caret_line(), editor.get_caret_column()) if caret < 0 else caret
	editor.remove_secondary_carets()
	editor.begin_complex_operation()
	editor.select_all()
	editor.insert_text_at_caret(source)
	editor.end_complex_operation()
	var point := location(source, mini(at, source.length()))
	editor.deselect()
	editor.set_caret_line(point.y)
	editor.set_caret_column(point.x)

static func matches(source: String, query: String, case_sensitive: bool, whole_word: bool, regex_mode: bool, first := 0, last := -1) -> Dictionary:
	if query.is_empty(): return {"matches": []}
	var pattern := query
	if not regex_mode:
		pattern = ""
		for character: String in query:
			pattern += "\\" + character if character in "\\.^$|?*+()[]{}" else character
	if whole_word: pattern = "\\b(?:" + pattern + ")\\b"
	if not case_sensitive: pattern = "(?i)" + pattern
	var regex := RegEx.new()
	if regex.compile(pattern, false) != OK: return {"error": "Invalid regular expression."}
	var found: Array[Dictionary] = []
	var end := source.length() if last < 0 else mini(last, source.length())
	for hit: RegExMatch in regex.search_all(source, first, end):
		if hit.get_start() == hit.get_end(): return {"error": "A zero-length match cannot be replaced. Use a pattern that consumes text."}
		found.append({"start": hit.get_start(), "end": hit.get_end(), "text": hit.get_string(), "groups": hit.strings})
	return {"matches": found, "regex": regex}

static func replacement(match_info: Dictionary, replacement_text: String, regex_mode: bool) -> String:
	if not regex_mode: return replacement_text
	var reference := RegEx.create_from_string("\\$(\\d+)")
	var result := replacement_text
	var hits := reference.search_all(replacement_text)
	hits.reverse()
	for hit: RegExMatch in hits:
		var index := hit.get_string(1).to_int()
		var value: String = match_info.groups[index] if index < match_info.groups.size() else ""
		result = result.left(hit.get_start()) + value + result.substr(hit.get_end())
	return result
