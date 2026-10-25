class_name FlowGraph
extends RefCounted

const Structure = preload("res://application/condition_source.gd")
const Flow = preload("res://application/flow_source.gd")
const MAX_TIMELINES := 128
const MAX_GRAPH_BYTES := 32 * 1024 * 1024


static func catalog(workspace: RefCounted) -> Dictionary:
	var aliases := {}
	var explicit_aliases := {}
	var ambiguous := {}
	var mapped := {}
	if workspace == null or workspace.root_path.is_empty():
		return {"aliases": aliases, "ambiguous": ambiguous}
	if not workspace._scan_complete:
		return {"error": "The content scan is incomplete; timeline references cannot be resolved."}
	var config := ConfigFile.new()
	var project: String = workspace.root_path.path_join("project.godot")
	if FileAccess.file_exists(project):
		if config.load(project) != OK:
			return {"error": "Cannot read the content project's native timeline directory."}
		var directory: Variant = config.get_value("dialogic", "directories/dtl_directory", {})
		if not directory is Dictionary:
			return {"error": "dialogic/directories/dtl_directory must be a dictionary."}
		for key: Variant in directory:
			if not key is String or key.is_empty() or not directory[key] is String:
				return {"error": "Native timeline aliases and resource paths must be nonempty strings."}
			var absolute: String = workspace.resolve_content_path(directory[key])
			# Preserve invalid entries as explicit errors when referenced.
			aliases[key] = absolute if absolute in workspace.timelines else ""
			explicit_aliases[key] = true
			mapped[absolute] = true
	for absolute: String in workspace.timelines:
		if mapped.has(absolute):
			continue
		var name := absolute.get_file().get_basename()
		# An explicit native mapping is authoritative over inferred filenames.
		if explicit_aliases.has(name):
			continue
		if aliases.has(name):
			ambiguous[name] = true
		else:
			aliases[name] = absolute
	var folded := {}
	for name: String in aliases:
		var lower := name.to_lower()
		if folded.has(lower) and folded[lower] != name:
			ambiguous[name] = true
			ambiguous[folded[lower]] = true
		folded[lower] = name
	return {"aliases": aliases, "ambiguous": ambiguous}


static func compile(source: String, workspace: RefCounted, source_path: String, local_validator: Callable) -> Dictionary:
	var inventory := catalog(workspace)
	if inventory.has("error"):
		return failure(inventory.error)
	var root_key := source_path if not source_path.is_empty() else "@current"
	var sources := {root_key: source}
	var resources := {root_key: DialogicTimeline.new()}
	var queue: Array[String] = [root_key]
	var dependencies := {}
	var total_bytes := source.to_utf8_buffer().size()
	var cache := DialogicResourceUtil.get_event_cache()
	var issues: Array[Dictionary] = []
	var cursor := 0
	while cursor < queue.size():
		var key := queue[cursor]
		cursor += 1
		var structure := Structure.scan(sources[key], cache)
		for record: Dictionary in structure.records:
			if not record.event is DialogicJumpEvent:
				continue
			var model := Flow.inspect(record.raw, record.event)
			# Variable references are checked by the local validator with defaults.
			if model.has("error") and record.raw.contains("{"):
				var slash: int = record.raw.rfind("/")
				model = {"timeline_identifier": record.raw.substr(5, slash - 5) if slash >= 5 else ""}
			if model.has("error") or model.timeline_identifier.is_empty():
				continue
			var identifier: String = model.timeline_identifier
			var target: String = inventory.aliases.get(identifier, "")
			var message := ""
			if inventory.ambiguous.has(identifier):
				message = "Ambiguous timeline '%s'; use a unique native alias in the content project's dtl_directory." % identifier
			elif target.is_empty():
				message = "Timeline '%s' is missing, outside the content root, linked or absent from the native directory." % identifier
			if not message.is_empty():
				issues.append(issue(key, root_key, record.line, message))
				continue
			dependencies[identifier] = target
			if sources.has(target):
				continue
			if sources.size() >= MAX_TIMELINES:
				issues.append(issue(key, root_key, record.line, "A preview graph supports at most 128 timelines."))
				continue
			var file := FileAccess.open(target, FileAccess.READ)
			if file == null or file.get_length() > 4 * 1024 * 1024:
				issues.append(issue(key, root_key, record.line, "Timeline dependency is unreadable or exceeds 4 MiB: " + identifier))
				continue
			var bytes := file.get_buffer(file.get_length())
			file.close()
			if bytes.has(0) or not load("res://application/timeline_document.gd")._is_utf8(bytes):
				issues.append(issue(key, root_key, record.line, "Timeline dependency must be valid UTF-8 without NUL: " + identifier))
				continue
			var decoded := bytes.get_string_from_utf8()
			total_bytes += bytes.size()
			if total_bytes > MAX_GRAPH_BYTES:
				issues.append(issue(key, root_key, record.line, "Timeline dependencies exceed the 32 MiB preview graph limit."))
				continue
			sources[target] = decoded.trim_prefix(String.chr(0xFEFF)).replace("\r\n", "\n").replace("\r", "\n")
			resources[target] = DialogicTimeline.new()
			queue.append(target)
	if not issues.is_empty():
		return failure("", issues)
	var directory := {}
	var alias_paths := {}
	for alias: String in inventory.aliases:
		var path: String = inventory.aliases[alias]
		if resources.has(path) and not inventory.ambiguous.has(alias):
			directory[alias] = resources[path]
			alias_paths[alias] = path
	var had_directory := Engine.has_meta("dtl_directory")
	var old_directory: Variant = Engine.get_meta("dtl_directory") if had_directory else null
	Engine.set_meta("dtl_directory", directory)
	var characters: Dictionary = workspace.runtime_characters() if workspace != null else {}
	var count := 0
	var document_counts := {"event_count": 0, "comment_count": 0, "character_event_count": 0}
	var max_choices := 1
	var defaults: Dictionary = workspace.variable_document.runtime_values() if workspace != null and workspace.variable_document != null else {}
	for key: String in queue:
		var checked: Dictionary = local_validator.call(sources[key], workspace, true, characters)
		if not checked.supported:
			for detail: Dictionary in checked.issues:
				var mapped_issue := issue(key, root_key, detail.line, detail.message)
				mapped_issue.column = detail.column
				issues.append(mapped_issue)
			continue
		var parsed: DialogicTimeline = checked._timeline
		if key == root_key:
			# Display only events in the open document, without dependencies or
			# the nonzero playback sentinel used for flow-only timelines.
			for event: DialogicEvent in parsed.events:
				if event is DialogicTextEvent:
					document_counts.event_count += 1
				elif event is DialogicCommentEvent:
					document_counts.comment_count += 1
				elif event is DialogicCharacterEvent:
					document_counts.character_event_count += 1
		var target: DialogicTimeline = resources[key]
		target.events = parsed.events
		target.events_processed = true
		target.indent_format = parsed.indent_format
		target.text_lines_indexed = parsed.text_lines_indexed.duplicate()
		target.set_meta("source_lines", parsed.get_meta("source_lines", []))
		target.set_meta("source_path", key)
		target.set_meta("flow_preview", true)
		count += checked.event_count
		var group_size := question_size(target)
		max_choices = maxi(max_choices, group_size)
		if group_size > 256:
			issues.append(issue(key, root_key, 0, "A preview question supports at most 256 options."))
	for key: String in queue:
		var timeline: DialogicTimeline = resources[key]
		var labels := {}
		for event: DialogicEvent in timeline.events:
			if event is DialogicLabelEvent and not labels.has(event.name):
				labels[event.name] = true
		timeline.set_meta("labels", labels)
	for key: String in queue:
		var timeline: DialogicTimeline = resources[key]
		for index: int in timeline.events.size():
			var event: DialogicEvent = timeline.events[index]
			if event is DialogicJumpEvent and not event.label_name.contains("{"):
				var destination: DialogicTimeline = event.timeline if event.timeline != null else timeline
				if not event.label_name.is_empty() and not destination.get_meta("labels", {}).has(event.label_name):
					issues.append(issue(key, root_key, timeline.get_meta("source_lines")[index], "Label '%s' was not found in %s." % [event.label_name, destination.get_meta("source_path")]))
	if had_directory:
		Engine.set_meta("dtl_directory", old_directory)
	else:
		Engine.remove_meta("dtl_directory")
	var root: DialogicTimeline = resources[root_key]
	var others := resources.duplicate()
	others.erase(root_key)
	root.set_meta("preview_timelines", others)
	root.set_meta("preview_timeline_aliases", alias_paths)
	root.set_meta("preview_characters", characters)
	root.set_meta("preview_variables", defaults.duplicate(true))
	root.set_meta("preview_max_choices", max_choices)
	var cfg := ConfigFile.new()
	var false_behaviour := 0
	if workspace != null and cfg.load(workspace.root_path.path_join("project.godot")) == OK:
		false_behaviour = int(cfg.get_value("dialogic", "choices/def_false_behaviour", 0))
	root.set_meta("preview_choice_default", false_behaviour if false_behaviour in [0, 1] else 0)
	if not issues.is_empty():
		release(root)
		return failure("", issues)
	return {"supported": true, "diagnostics": [], "issues": [], "event_count": maxi(1, count), "_timeline": root,
		"narration_count": count, "character_text_count": 0, "character_event_count": 0, "comment_count": 0,
		"document_counts": document_counts}


static func release(root: DialogicTimeline) -> void:
	if not root.has_meta("flow_preview") and not root.has_meta("preview_timelines"):
		return
	var timelines: Array = [root]
	timelines.append_array(root.get_meta("preview_timelines", {}).values())
	root.remove_meta("preview_timelines")
	root.remove_meta("preview_timeline_aliases")
	for timeline: DialogicTimeline in timelines:
		for event: DialogicEvent in timeline.events:
			if event is DialogicJumpEvent:
				event.timeline = null


static func issue(path: String, root_path: String, line: int, message: String) -> Dictionary:
	return {"line": line if path == root_path else 0, "column": 1, "path": path,
		"dependency_line": line, "message": message if path == root_path else "%s · line %d: %s" % [path, line, message]}


static func failure(message: String, issues: Array[Dictionary] = []) -> Dictionary:
	if not message.is_empty():
		issues.append({"line": 0, "column": 1, "message": message})
	var diagnostics: Array[String] = []
	for detail: Dictionary in issues:
		diagnostics.append(("Line %d: " % detail.line if detail.line > 0 else "") + detail.message)
	return {"supported": false, "issues": issues, "diagnostics": diagnostics, "event_count": 0}


static func question_size(timeline: DialogicTimeline) -> int:
	var endings := {}
	var stack: Array[int] = []
	for index: int in timeline.events.size():
		var event: DialogicEvent = timeline.events[index]
		if event.can_contain_events:
			stack.append(index)
		elif event is DialogicEndBranchEvent and not stack.is_empty():
			endings[stack.pop_back()] = index
	var maximum := 0
	for index: int in timeline.events.size():
		if not timeline.events[index] is DialogicChoiceEvent:
			continue
		var cursor := index
		var count := 0
		while cursor < timeline.events.size() and timeline.events[cursor] is DialogicChoiceEvent:
			count += 1
			cursor = int(endings.get(cursor, timeline.events.size())) + 1
		maximum = maxi(maximum, count)
	return maximum
