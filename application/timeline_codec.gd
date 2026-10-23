class_name TimelineCodec
extends RefCounted

## Scope validation delegates event recognition and parsing to Dialogic Alpha 20.
## Character references must resolve to validated workspace .dch resources before
## parsing: Alpha 20's implicit temporary-character fallback is never accepted.
## References: https://docs.dialogic.pro/timeline-text-syntax.html
##             https://docs.dialogic.pro/event-character.html
##             https://docs.dialogic.pro/reference-manager.html

const MAX_SOURCE_BYTES: int = 4 * 1024 * 1024


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
	var lines: PackedStringArray = normalized.split("\n", true)
	var random_text_regex := RegEx.create_from_string(r"(?<!\\)<[^>]+/[^>]*>")
	var index: int = 0
	var narration_count: int = 0
	var comment_count: int = 0
	var character_text_count: int = 0
	var character_event_count: int = 0
	var expected_events: Array[Dictionary] = []
	while index < lines.size():
		var first_line: int = index + 1
		var line: String = lines[index]
		index += 1
		var stripped: String = line.strip_edges(true, false)
		if stripped.is_empty():
			continue
		var event: DialogicEvent = DialogicTimeline.event_from_string(stripped, cache)
		var raw_event: String = stripped
		# Mirror the original parser's event boundaries. A '#' on a continued
		# Text line belongs to that Text, rather than to a new Comment event.
		var source_lines: Array[int] = [first_line]
		var source_columns: Array[int] = [line.length() - stripped.length() + 1]
		while not event.is_string_full_event(raw_event) and index < lines.size():
			var following: String = lines[index].strip_edges(true, false)
			var following_column: int = lines[index].length() - following.length() + 1
			index += 1
			if following.is_empty():
				break
			raw_event += "\n" + following
			source_lines.append(index)
			source_columns.append(following_column)
		if line != stripped:
			_add_issue(issues, first_line, 1, "indented timelines require a later version.")
			continue
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
		if not event is DialogicTextEvent:
			_add_issue(issues, first_line, 1, "%s is outside this version's Text, Comment and basic Character scope." % event.event_name)
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
		# Conservative scope, not a replacement for Dialogic's grammar. Report
		# the actual physical source position without evaluating expressions.
		var position: int = _first_of(body, "{}")
		if position >= 0:
			_add_raw_issue(issues, source_lines, source_columns, raw_event, body_offset + position,
				"variables and expressions require a later version.")
			continue
		position = _first_of(body, "[]")
		if position >= 0:
			_add_raw_issue(issues, source_lines, source_columns, raw_event, body_offset + position,
				"BBCode, inline effects and text modifiers require a later version.")
			continue
		var random_match: RegExMatch = random_text_regex.search(body)
		if random_match != null:
			_add_raw_issue(issues, source_lines, source_columns, raw_event, body_offset + random_match.get_start(),
				"random text selection requires a later version.")
			continue
		position = raw_event.find("#id:")
		if position >= 0:
			_add_raw_issue(issues, source_lines, source_columns, raw_event, position,
				"translation metadata requires a later version.")
			continue
		if speaker.is_empty():
			narration_count += 1
		else:
			character_text_count += 1
		expected_events.append({"kind": "text", "line": first_line, "identifier": speaker, "portrait": portrait})

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
		timeline.set_meta("preview_characters", characters)
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
	if expected["kind"] == "comment":
		return "" if parsed is DialogicCommentEvent else "The official parser did not preserve the Comment event."
	if expected["kind"] == "text" and not parsed is DialogicTextEvent:
		return "The official parser did not preserve the Text event."
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
