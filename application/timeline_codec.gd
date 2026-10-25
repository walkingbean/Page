class_name TimelineCodec
extends RefCounted

## Scope validation delegates event recognition and parsing to Dialogic Alpha 20.
## Character references must resolve to validated workspace .dch resources before
## parsing: Alpha 20's implicit temporary-character fallback is never accepted.
## References: https://docs.dialogic.pro/timeline-text-syntax.html
##             https://docs.dialogic.pro/event-character.html
##             https://docs.dialogic.pro/reference-manager.html

const MAX_SOURCE_BYTES: int = 4 * 1024 * 1024
const ASSIGNMENT = preload("res://application/variable_assignment.gd")
const CONDITIONS = preload("res://application/condition_source.gd")
const INLINE = preload("res://application/conditional_text.gd")
const VARIABLES = preload("res://application/text_variables.gd")


static func normalize_source(source: String) -> String:
	return source.trim_prefix(String.chr(0xFEFF)).replace("\r\n", "\n").replace("\r", "\n")


static func validate_content(source: String, workspace: RefCounted = null) -> Dictionary:
	var result: Dictionary = _validate(source, workspace)
	result.erase("_timeline")
	return result


static func parse_supported(source: String, workspace: RefCounted = null) -> DialogicTimeline:
	var result: Dictionary = _validate(source, workspace)
	return result.get("_timeline") if result["supported"] else null


static func _validate(source: String, workspace: RefCounted) -> Dictionary:
	var issues: Array[Dictionary] = []
	var normalized: String = normalize_source(source)
	var encoded: PackedByteArray = normalized.to_utf8_buffer()
	if encoded.size() > MAX_SOURCE_BYTES:
		_add_issue(issues, 0, 1, "This preview supports timelines up to 4 MiB.")
		return _result(issues, 0, 0)
	var nul_position: int = encoded.find(0)
	if nul_position >= 0:
		var prefix: String = encoded.slice(0, nul_position).get_string_from_utf8()
		_add_issue(issues, prefix.count("\n") + 1, prefix.length() - prefix.rfind("\n"), "NUL characters are not supported in timeline text.")
		return _result(issues, 0, 0)

	var cache: Array = DialogicResourceUtil.get_event_cache()
	if cache.size() < 2:
		_add_issue(issues, 0, 1, "The Dialogic event catalog could not be initialized.")
		return _result(issues, 0, 0)
	var structure := CONDITIONS.scan(normalized, cache)
	issues.assign(structure.issues)
	if not issues.is_empty():
		return _result(issues, 0, 0)
	var narration_count: int = 0
	var comment_count: int = 0
	var character_text_count: int = 0
	var character_event_count: int = 0
	var expected_events: Array[Dictionary] = []
	var runtime: Dictionary = workspace.variable_document.runtime_values() if workspace != null and workspace.variable_document != null else {}
	var active := true
	var chains: Dictionary = {}
	for record: Dictionary in structure.records:
		var first_line: int = record.line
		var event: DialogicEvent = record.event
		var raw_event: String = record.raw
		var source_lines: Array[int] = record.source_lines
		var source_columns: Array[int] = record.source_columns
		for ending: int in record.ends_before:
			expected_events.append({"kind": "end", "line": first_line})
		var depth: int = record.depth
		for level: int in chains.keys():
			if level > depth:
				chains.erase(level)
		var parent_active: bool = true if depth == 0 else chains.get(depth - 1, {}).get("active", false)
		if event is DialogicConditionEvent:
			if raw_event.begins_with("if "):
				chains[depth] = {"matched": false, "active": false}
			var state: Dictionary = chains.get(depth, {"matched": false, "active": false})
			var condition: Dictionary = CONDITIONS.inspect_event(raw_event, runtime, parent_active and not state.matched)
			if condition.has("error"):
				_add_raw_issue(issues, source_lines, source_columns, raw_event, condition.get("offset", 0), condition.error)
				state.active = false
				chains[depth] = state
				continue
			state.active = parent_active and not state.matched and condition.get("value", false)
			state.matched = state.matched or state.active
			chains[depth] = state
			condition["line"] = first_line
			expected_events.append(condition)
			continue
		active = parent_active
		chains.erase(depth)
		if event is DialogicCommentEvent:
			comment_count += 1
			expected_events.append({"kind": "comment", "line": first_line})
			continue
		if event is DialogicCharacterEvent:
			var model: Dictionary = _character_model(raw_event, workspace)
			if model.has("error"):
				_add_raw_issue(issues, source_lines, source_columns, raw_event, model.get("offset", 0), model["error"])
				continue
			model["line"] = first_line
			expected_events.append(model)
			character_event_count += 1
			continue
		if event is DialogicVariableEvent:
			var problem: String = "Choose a content folder with saved variables." if workspace == null or workspace.variable_document == null else workspace.variable_document.preview_error()
			if not problem.is_empty():
				_add_issue(issues, first_line, 1, problem)
				continue
			var assignment: Dictionary = ASSIGNMENT.inspect_event(raw_event, runtime, active)
			if assignment.has("error"):
				_add_raw_issue(issues, source_lines, source_columns, raw_event, assignment.get("offset", 0), assignment.error)
				continue
			assignment["line"] = first_line
			expected_events.append(assignment)
			if active:
				runtime[assignment.name] = assignment.value
			continue
		if not event is DialogicTextEvent:
			_add_issue(issues, first_line, 1, "%s is outside this version's Text, Comment, scalar Variable, nested Condition and basic Character scope." % event.event_name)
			continue
		var text_event: DialogicTextEvent = event as DialogicTextEvent
		var escape_offset: int = 1 if raw_event.begins_with("\\") else 0
		var match_result: RegExMatch = text_event.regex.search(raw_event.trim_prefix("\\"))
		if match_result == null:
			_add_issue(issues, first_line, 1, "Dialogic could not parse the text event.")
			continue
		var speaker: String = match_result.get_string("name").strip_edges()
		var portrait: String = match_result.get_string("portrait").trim_prefix("(").trim_suffix(")").strip_edges()
		if speaker == "_":
			speaker = ""
		var reference_error: String = _reference_error(speaker, portrait, workspace)
		if not reference_error.is_empty():
			var reference_offset: int = match_result.get_start("name") if not speaker.is_empty() else match_result.get_start("portrait")
			_add_raw_issue(issues, source_lines, source_columns, raw_event, maxi(0, reference_offset) + escape_offset, reference_error)
			continue
		var body: String = match_result.get_string("text")
		var body_offset: int = match_result.get_start("text") + escape_offset
		# Alpha 20 first removes a raw event prefix above, then decodes and
		# removes a second prefix from the trimmed Text body. Validate exactly
		# what its variable parser receives, not an earlier escaped form.
		var native_body: String = _native_text_body(body)
		var variable_result: Dictionary = INLINE.inspect(native_body, workspace, runtime, active)
		if variable_result.has("error"):
			var raw_offset: int = _native_body_source_offset(body, int(variable_result.get("offset", 0)))
			_add_raw_issue(issues, source_lines, source_columns, raw_event, body_offset + raw_offset, variable_result["error"])
			continue
		var position: int = raw_event.find("#id:")
		if position >= 0:
			_add_raw_issue(issues, source_lines, source_columns, raw_event, position,
				"translation metadata requires a later version.")
			continue
		if speaker.is_empty():
			narration_count += 1
		else:
			character_text_count += 1
		expected_events.append({"kind": "text", "line": first_line, "identifier": speaker, "portrait": portrait, "text": native_body})

	for ending: int in structure.ends_after:
		expected_events.append({"kind": "end", "line": normalized.count("\n") + 1})
	if not issues.is_empty():
		return _result(issues, narration_count, comment_count, character_text_count, character_event_count)
	# Keep the actual objects together with the timeline for the runtime host.
	# Engine metadata is the official resource directory's runtime cache. Set it
	# directly here so validation never writes the editor's ProjectSettings.
	var characters: Dictionary = workspace.runtime_characters() if workspace != null else {}
	for expected: Dictionary in expected_events:
		var identifier: String = expected.get("identifier", "")
		if not identifier.is_empty() and not characters.get(identifier) is DialogicCharacter:
			_add_issue(issues, expected["line"], 1, "Character '%s' has no validated runtime .dch resource; temporary character fallback is not supported." % identifier)
	if not issues.is_empty():
		return _result(issues, narration_count, comment_count, character_text_count, character_event_count)
	var had_directory: bool = Engine.has_meta("dch_directory")
	var previous_directory: Variant = Engine.get_meta("dch_directory") if had_directory else null
	Engine.set_meta("dch_directory", characters)
	var timeline: DialogicTimeline = DialogicTimeline.new()
	timeline.from_text(normalized)
	timeline.process()
	if timeline.events.size() != expected_events.size():
		_add_issue(issues, 0, 1, "The official parser's event boundaries do not match the supported source.")
	else:
		for parsed_index: int in timeline.events.size():
			var parsed: DialogicEvent = timeline.events[parsed_index]
			var expected: Dictionary = expected_events[parsed_index]
			var mismatch: String = _parsed_mismatch(parsed, expected, characters)
			if not mismatch.is_empty():
				_add_issue(issues, expected["line"], 1, mismatch)
	if had_directory:
		Engine.set_meta("dch_directory", previous_directory)
	else:
		Engine.remove_meta("dch_directory")
	var result: Dictionary = _result(issues, narration_count, comment_count, character_text_count, character_event_count)
	if issues.is_empty():
		var source_map: Array[int] = []
		for expected: Dictionary in expected_events:
			source_map.append(expected.line)
		timeline.set_meta("source_lines", source_map)
		timeline.set_meta("preview_characters", characters)
		var defaults: Dictionary = {}
		if workspace != null and workspace.variable_document != null:
			defaults = workspace.variable_document.runtime_values()
		timeline.set_meta("preview_variables", defaults.duplicate(true))
		result["_timeline"] = timeline
	return result


static func _character_model(raw: String, workspace: RefCounted) -> Dictionary:
	# Alpha 20 recognizes any line beginning with 'join', 'leave' or 'update'.
	# Its regex also accepts trailing text and incomplete names. Restrict those
	# cases before calling from_text, which assumes a successful regex match.
	if raw.begins_with("update"):
		return {"error": "Character Update requires a later version."}
	var dynamic_offset: int = _first_of(raw, "{}[]")
	if dynamic_offset >= 0:
		return {"error": "Character expressions and optional shortcode arguments require a later version.", "offset": dynamic_offset}
	var regex := RegEx.create_from_string(r'^(?<type>join|leave)[ \t]+(?:"(?<quoted>[^"\r\n]+)"|(?<bare>[^ \t"():\r\n]+))(?:[ \t]*\((?<portrait>[^()\r\n]*)\))?(?:[ \t]+(?<position>left|center|right))?[ \t]*$')
	var matched: RegExMatch = regex.search(raw)
	if matched == null:
		return {"error": "Use join Identifier [left|center|right] or leave Identifier; only the default portrait is supported."}
	var identifier: String = matched.get_string("quoted") if not matched.get_string("quoted").is_empty() else matched.get_string("bare")
	identifier = identifier.strip_edges()
	if identifier.is_empty():
		return {"error": "A Character event requires a nonempty workspace character identifier."}
	if identifier == "--All--":
		return {"error": "Leave All requires a later version.", "offset": raw.find(identifier)}
	var portrait: String = matched.get_string("portrait").strip_edges()
	var position: String = matched.get_string("position")
	var action: String = matched.get_string("type")
	if action == "leave" and (not portrait.is_empty() or not position.is_empty() or raw.contains("(")):
		return {"error": "Leave supports only a character identifier in this version."}
	var reference_error: String = _reference_error(identifier, portrait, workspace)
	if not reference_error.is_empty():
		return {"error": reference_error, "offset": maxi(0, raw.find(identifier))}
	return {"kind": "character", "identifier": identifier, "portrait": portrait,
		"action": DialogicCharacterEvent.Actions.JOIN if action == "join" else DialogicCharacterEvent.Actions.LEAVE,
		"position": "center" if position.is_empty() else position}


static func _reference_error(identifier: String, portrait: String, workspace: RefCounted) -> String:
	if _first_of(identifier + portrait, "{}[]") >= 0:
		return "Dynamic character names, portrait expressions and text modifiers require a later version."
	if identifier.is_empty():
		return "A portrait requires a workspace character." if not portrait.is_empty() else ""
	if workspace == null:
		return "Character '%s' requires an open content workspace containing its .dch file; escape a literal colon with \\: ." % identifier
	var character: DialogicCharacter = workspace.get_character(identifier)
	if character == null:
		var details: String = workspace.get_character_error(identifier)
		return details if not details.is_empty() else "Character '%s' has no supported .dch file in this workspace." % identifier
	if not portrait.is_empty() and (portrait != character.default_portrait or not character.portraits.has(portrait)):
		return "Only character '%s' default portrait is supported in this version." % identifier
	return ""


static func _parsed_mismatch(parsed: DialogicEvent, expected: Dictionary, characters: Dictionary) -> String:
	if expected["kind"] == "end":
		return "" if parsed is DialogicEndBranchEvent else "The official parser did not preserve the branch boundary."
	if expected["kind"] == "condition":
		if not parsed is DialogicConditionEvent or parsed.condition_type != expected.condition_type or parsed.condition != expected.expression:
			return "The official parser did not preserve the Condition event."
		return ""
	if expected["kind"] == "variable":
		if not parsed is DialogicVariableEvent or parsed.operation != DialogicVariableEvent.Operations.SET or parsed.name != expected.name or parsed._value_type != expected.value_type or parsed.value != expected.native_value:
			return "The official parser did not preserve the Variable assignment event."
		return ""
	if expected["kind"] == "comment":
		return "" if parsed is DialogicCommentEvent else "The official parser did not preserve the Comment event."
	if expected["kind"] == "text" and not parsed is DialogicTextEvent:
		return "The official parser did not preserve the Text event."
	if expected["kind"] == "text" and parsed.text != expected["text"]:
		return "The official parser's decoded text does not match the validated Text body."
	if expected["kind"] == "character" and not parsed is DialogicCharacterEvent:
		return "The official parser did not preserve the Character event."
	var identifier: String = expected["identifier"]
	if identifier.is_empty():
		if parsed.character != null or not parsed.character_identifier.is_empty() or not parsed.portrait.is_empty():
			return "The official parser found an unexpected character or portrait dependency."
	else:
		if not characters.has(identifier) or parsed.character != characters[identifier] or parsed.character_identifier != identifier:
			return "The official parser could not resolve the exact workspace .dch character; temporary character fallback is not supported."
		if parsed.portrait != expected["portrait"]:
			return "The official parser found an unexpected portrait dependency."
	if expected["kind"] == "character":
		if parsed.action != expected["action"] or parsed.transform != expected["position"]:
			return "The official parser found an unsupported Character action or position."
	return ""


static func _native_text_body(body: String) -> String:
	# Keep this transformation identical to DialogicTextEvent.from_text.
	var decoded: String = body.replace("\\\n", "\n").replace("\\:", ":").strip_edges().trim_prefix("\\")
	return "" if decoded == "<Empty Text Event>" else decoded


static func _native_body_source_offset(body: String, decoded_offset: int) -> int:
	# Map only the reported offset rather than allocate a per-character map
	# for every valid line. Continuation and colon escapes remove one source
	# character each; trimming and the final body escape shift the start.
	var decoded: String = body.replace("\\\n", "\n").replace("\\:", ":")
	var left_trimmed: String = decoded.strip_edges(true, false)
	var target: int = maxi(0, decoded_offset) + decoded.length() - left_trimmed.length()
	if left_trimmed.strip_edges(false, true).begins_with("\\"):
		target += 1
	var source_index: int = 0
	var output_index: int = 0
	while source_index < body.length():
		var width: int = 1
		if body[source_index] == "\\" and source_index + 1 < body.length() and body[source_index + 1] in ["\n", ":"]:
			width = 2
		if output_index == target:
			return source_index
		source_index += width
		output_index += 1
	return body.length()


static func _first_of(text: String, characters: String) -> int:
	var first: int = -1
	for character: String in characters:
		var position: int = text.find(character)
		if position >= 0 and (first < 0 or position < first):
			first = position
	return first


static func _add_raw_issue(issues: Array[Dictionary], source_lines: Array[int], source_columns: Array[int], raw: String, offset: int, message: String) -> void:
	var prefix: String = raw.left(maxi(0, offset))
	var relative_line: int = prefix.count("\n")
	var relative_column: int = maxi(0, offset) - prefix.rfind("\n") - 1
	_add_issue(issues, source_lines[relative_line], source_columns[relative_line] + relative_column, message)


static func _add_issue(issues: Array[Dictionary], line: int, column: int, message: String) -> void:
	issues.append({"line": line, "column": column, "message": message})


static func _result(issues: Array[Dictionary], narration_count: int, comment_count: int, character_text_count: int = 0, character_event_count: int = 0) -> Dictionary:
	var diagnostics: Array[String] = []
	for issue: Dictionary in issues:
		diagnostics.append(("Line %d: " % issue["line"] if issue["line"] > 0 else "") + issue["message"])
	return {"supported": issues.is_empty(), "diagnostics": diagnostics, "issues": issues,
		"event_count": narration_count + character_text_count, "narration_count": narration_count,
		"character_text_count": character_text_count, "comment_count": comment_count,
		"character_event_count": character_event_count}
