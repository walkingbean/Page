extends RefCounted

const Config = preload("res://application/localization_config.gd")
const Glossary = preload("res://application/glossary_document.gd")
const Csv = preload("res://application/translation_csv.gd")
const Transaction = preload("res://application/localization_transaction.gd")
const Document = preload("res://application/timeline_document.gd")
const Character = preload("res://application/character_document.gd")
const Structure = preload("res://application/condition_source.gd")
var workspace: RefCounted
var config: RefCounted
var glossaries: Dictionary = {}
var diagnostics: Array[String] = []
var last_error := ""
var counter := 16
var used_ids: Dictionary = {}
var preview_locale := ""

func open_root(source_workspace: RefCounted) -> Error:
	workspace = source_workspace
	diagnostics.clear(); glossaries.clear(); last_error = ""
	config = Config.new()
	if config.open_root(workspace) != OK or config.read_only: return fail(config.last_error if not config.last_error.is_empty() else "\n".join(config.diagnostics))
	var words := {}
	for logical: String in config.values["dialogic/glossary/glossary_files"]:
		var path: String = workspace.resolve_content_path(logical)
		var doc := Glossary.new()
		if path.is_empty() or doc.open_file(path, workspace) != OK or doc.read_only:
			diagnostics.append("Cannot use glossary " + logical + ": " + doc.last_error + "\n" + "\n".join(doc.diagnostics)); continue
		glossaries[logical] = doc
		for word: String in doc.glossary.entries:
			if words.has(word): diagnostics.append("Ambiguous glossary word across resources: " + word)
			words[word] = logical
	return OK

func fail(message: String) -> Error:
	last_error = message
	return ERR_INVALID_DATA

func register_glossary(logical: String, enabled: bool = true) -> Error:
	if workspace.resolve_content_path(logical).is_empty(): return fail("Choose a glossary in the selected content root.")
	var paths: Array = Array(config.values["dialogic/glossary/glossary_files"])
	if enabled and not logical in paths: paths.append(logical)
	if not enabled: paths.erase(logical)
	if config.set_value("dialogic/glossary/glossary_files", paths) != OK or config.save_file() != OK: return fail(config.last_error)
	return open_root(workspace)

func folder() -> String:
	var logical: String = config.values["dialogic/translation/translation_folder"]
	if logical == "res://": return workspace.root_path
	return workspace.resolve_content_path(logical.trim_suffix("/"))

func output_path(kind: String, source: String = "") -> String:
	var directory := folder()
	if directory.is_empty(): return ""
	if kind == "character": return directory.path_join("dialogic_character_translations.csv")
	if config.values["dialogic/translation/file_mode"] == 0:
		return directory.path_join("dialogic_" + ("timeline" if kind == "timeline" else "glossary") + "_translations.csv")
	if config.values["dialogic/translation/save_mode"] == 1:
		if kind == "timeline": return source.get_basename() + "_translation.csv"
		return source.get_base_dir().path_join("dialogic_" + source.get_file().get_basename() + "_translation.csv")
	return directory.path_join("dialogic_" + source.get_file().get_basename() + "_translation.csv")

func csv_paths() -> Dictionary:
	var result := {}
	var groups := {}
	for path: String in workspace.timelines:
		var output := output_path("timeline", path)
		if output.is_empty(): return {"error":"Translation folder leaves the content root."}
		var identity: String = path if config.values["dialogic/translation/file_mode"] == 1 else "timeline"
		if groups.has(output) and groups[output] != identity: return {"error":"CSV output collision. Use adjacent storage or rename files: " + output}
		groups[output] = identity; result[path] = output
	for logical: String in glossaries:
		var path: String = workspace.resolve_content_path(logical)
		var output := output_path("glossary", path)
		var identity: String = logical if config.values["dialogic/translation/file_mode"] == 1 else "glossary"
		if groups.has(output) and groups[output] != identity: return {"error":"CSV output collision: " + output}
		groups[output] = identity; result[path] = output
	var character_path := output_path("character")
	if character_path.is_empty() or groups.has(character_path): return {"error":"Invalid or conflicting character CSV path."}
	result["@characters"] = character_path
	return {"paths":result}

func reserve(id: String, owner: String) -> bool:
	if id.is_empty(): return true
	if RegEx.create_from_string("^[0-9a-fA-F]+$").search(id) == null or id.length() > 8:
		last_error = "Invalid native hexadecimal translation ID in " + owner; return false
	if used_ids.has(id.to_lower()): last_error = "Duplicate translation ID " + id + " in " + owner + " and " + used_ids[id.to_lower()]; return false
	used_ids[id.to_lower()] = owner
	counter = maxi(counter, id.hex_to_int())
	return true

func next_id() -> String:
	counter += 1
	return "%x" % counter

func update_csv() -> Dictionary:
	var result := _update_csv()
	# Discard staging mutations after validation/commit failure as well as success.
	open_root(workspace)
	return result

func _update_csv() -> Dictionary:
	last_error = ""
	if not workspace._scan_complete: return {"error":"Complete the content scan before generating translation IDs."}
	if not diagnostics.is_empty(): return {"error":"\n".join(diagnostics)}
	var targets := csv_paths()
	if targets.has("error"): return targets
	used_ids.clear(); counter = config.values["dialogic/translation/id_counter"]
	var timelines := {}
	var characters := {}
	var changes: Array[Dictionary] = []
	# Validate all existing IDs before allocating any new ID.
	for path: String in workspace.timelines:
		var doc := Document.new(); doc.workspace = workspace
		if doc.open_file(path) != OK or doc.read_only: return {"error":"Cannot translate " + path + ": " + doc.last_error + "\n" + "\n".join(doc.diagnostics)}
		var scanned := Structure.scan(doc.content, DialogicResourceUtil.get_event_cache())
		for record: Dictionary in scanned.records:
			if not record.event.can_be_translated(): continue
			var id: String = record.raw.get_slice("#id:", 1).strip_edges() if "#id:" in record.raw else ""
			if not reserve(id, path + ":" + str(record.line)): return {"error":last_error}
		timelines[path] = {"document":doc, "records":scanned.records}
	for identifier: String in workspace.characters:
		var info: Dictionary = workspace.characters[identifier]
		var doc := Character.new()
		if doc.open_file(info.path, workspace) != OK or doc.read_only: return {"error":"Unsupported character: " + identifier}
		if not reserve(doc.character._translation_id, info.path): return {"error":last_error}
		characters[identifier] = doc
	for logical: String in glossaries:
		var resource: DialogicGlossary = glossaries[logical].glossary
		if not reserve(resource._translation_id, logical): return {"error":last_error}
		for key: String in resource.entries:
			if resource.entries[key] is Dictionary and not reserve(resource.entries[key].get("_translation_id", ""), logical + ":" + key): return {"error":last_error}
	if counter > 0x7ffff000: return {"error":"Native translation ID range is exhausted."}
	var originals := {}
	var had_directory := Engine.has_meta("dch_directory")
	var previous: Variant = Engine.get_meta("dch_directory", {})
	Engine.set_meta("dch_directory", workspace.runtime_characters())
	for path: String in timelines:
		var doc: RefCounted = timelines[path].document
		var lines: PackedStringArray = doc.content.split("\n", true)
		var rows: Dictionary = originals.get(targets.paths[path], {})
		for record: Dictionary in timelines[path].records:
			if not record.event.can_be_translated(): continue
			var event: DialogicEvent = record.event.get_script().new()
			event._load_from_string(record.raw)
			if event._translation_id.is_empty():
				event._translation_id = next_id()
				var line: int = record.source_lines[-1] - 1
				var trailing: String = lines[line].substr(lines[line].strip_edges(false, true).length())
				lines[line] = lines[line].strip_edges(false, true) + " #id:" + event._translation_id + trailing
			for property: String in event._get_translatable_properties(): rows[event.get_property_translation_key(property)] = event._get_property_original_translation(property)
		originals[targets.paths[path]] = rows
		doc.set_content("\n".join(lines), false)
		changes.append({"path":path, "before":doc._original_bytes, "after":doc._encoded_content()})
	if had_directory: Engine.set_meta("dch_directory", previous)
	else: Engine.remove_meta("dch_directory")
	var character_rows := {}
	for identifier: String in characters:
		var doc: RefCounted = characters[identifier]
		if doc.character._translation_id.is_empty(): doc.character._translation_id = next_id()
		character_rows[doc.character.get_property_translation_key(DialogicCharacter.TranslatedProperties.NAME)] = doc.character.display_name
		if not doc.character.nicknames.is_empty(): character_rows[doc.character.get_property_translation_key(DialogicCharacter.TranslatedProperties.NICKNAMES)] = ", ".join(doc.character.nicknames)
		doc.set_content(var_to_str(inst_to_dict(doc.character)), false)
		changes.append({"path":doc.path, "before":doc._original_bytes, "after":doc._encoded_content()})
	if not character_rows.is_empty(): originals[targets.paths["@characters"]] = character_rows
	for logical: String in glossaries:
		var doc: RefCounted = glossaries[logical]
		var resource: DialogicGlossary = doc.glossary
		if resource._translation_id.is_empty(): resource._translation_id = next_id()
		var rows: Dictionary = originals.get(targets.paths[doc.path], {})
		for key: String in resource.entries:
			if not resource.entries[key] is Dictionary: continue
			var entry: Dictionary = resource.entries[key]
			if str(entry.get("_translation_id", "")).is_empty(): entry._translation_id = next_id()
			for property: String in entry:
				if property.begins_with("_"): continue
				if entry[property] is String: rows[resource.get_property_translation_key(key, property)] = entry[property]
				elif property == "alternatives": rows[resource.get_property_translation_key(key, property)] = ",".join(entry[property])
		originals[targets.paths[doc.path]] = rows
	var tables := {}
	var warnings: Array[String] = []
	for output: String in originals:
		var existing := read_csv(output, true)
		if existing.has("error"): return existing
		var merged := Csv.merge_source(existing.table, originals[output], config.values["dialogic/translation/original_locale"])
		if merged.has("error"): return merged
		for stale: String in merged.stale: warnings.append("Preserved row without current source: " + stale)
		tables[output] = merged
		changes.append({"path":output, "before":existing.before, "after":Csv.serialize(merged).to_utf8_buffer()})
	var mapped := update_glossary_mappings(tables, targets.paths)
	if mapped.has("error"): return mapped
	for logical: String in glossaries:
		var doc: RefCounted = glossaries[logical]
		if doc.sync_resource() != OK: return {"error":doc.last_error}
		changes.append({"path":doc.path, "before":doc._original_bytes, "after":doc._encoded_content()})
	config.set_value("dialogic/translation/id_counter", counter)
	changes.append(config_change())
	var result := Transaction.commit(workspace, changes)
	result["warnings"] = warnings
	open_root(workspace)
	return result

func config_change() -> Dictionary:
	return {"path":config.target_path, "before":config._original_bytes if not config.path.is_empty() else null, "after":config._encoded_content()}

func read_csv(path: String, allow_new := false) -> Dictionary:
	if not FileAccess.file_exists(path):
		if allow_new: return {"table":{"locales":[config.values["dialogic/translation/original_locale"]], "rows":{}}, "before":null}
		return {"error":"Missing CSV: " + path}
	var doc := Csv.new()
	if doc.open_file(path) != OK or doc.read_only: return {"error":"Cannot read CSV: " + path + "\n" + doc.last_error + "\n" + "\n".join(doc.diagnostics)}
	return {"table":doc.table, "before":doc._original_bytes}

func update_glossary_mappings(tables: Dictionary, paths: Dictionary) -> Dictionary:
	var all_words := {}
	for logical: String in glossaries:
		var doc: RefCounted = glossaries[logical]
		var resource: DialogicGlossary = doc.glossary
		resource._translation_keys.clear()
		var table: Dictionary = tables.get(paths[doc.path], {})
		for key: String in resource.entries:
			if not resource.entries[key] is Dictionary: continue
			resource.entries[key].erase("regex_options")
			var identity: String = logical + "/" + key
			for property: String in ["name", "alternatives"]:
				var csv_key := resource.get_property_translation_key(key, property)
				for value: String in table.get("rows", {}).get(csv_key, []):
					var words: Array = [value] if property == "name" else Array(value.split(",", false))
					for word: String in words:
						word = word.strip_edges()
						if word.is_empty(): continue
						if all_words.has(word) and all_words[word] != identity: return {"error":"Translated glossary name/alias is ambiguous: " + word}
						all_words[word] = identity
						resource._translation_keys[word] = csv_key
			# The native popup asks by the original entry name, including in translated text.
			resource._translation_keys[key] = resource.get_property_translation_key(key, "name")
	return {}

func tables() -> Dictionary:
	var target := csv_paths()
	if target.has("error"): return target
	var result := {}
	for path: String in target.paths.values():
		if result.has(path) or not FileAccess.file_exists(path): continue
		var read := read_csv(path)
		if read.has("error"): return read
		result[path] = read.table
	return {"tables":result, "paths":target.paths}

func collect_translations() -> Dictionary:
	var result := _collect_translations()
	open_root(workspace)
	return result

func _collect_translations() -> Dictionary:
	var loaded := tables()
	if loaded.has("error"): return loaded
	if loaded.tables.is_empty(): return {"error":"Update or import CSV files before collecting translations."}
	var mapping := update_glossary_mappings(loaded.tables, loaded.paths)
	if mapping.has("error"): return mapping
	var changes: Array[Dictionary] = []
	var registered: PackedStringArray = PackedStringArray(config.values["internationalization/locale/translations"])
	var locales: Array[String] = []
	var seen := {}
	for path: String in loaded.tables:
		for resource: Translation in Csv.translations(loaded.tables[path]):
			if not resource.locale in locales: locales.append(resource.locale)
			for key: String in resource.get_message_list():
				var identity: String = resource.locale + "/" + key
				if seen.has(identity) and seen[identity] != resource.get_message(key): return {"error":"Conflicting translations in multiple CSVs: " + identity}
				seen[identity] = resource.get_message(key)
			var output: String = path.get_basename() + "." + resource.locale + ".translation"
			var temporary := "user://page_translation_" + str(Time.get_ticks_usec()) + ".translation"
			if ResourceSaver.save(resource, temporary) != OK: return {"error":"Could not serialize a native Translation resource."}
			var bytes := FileAccess.get_file_as_bytes(temporary)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
			changes.append(Transaction.change(output, bytes))
			var logical: String = workspace.content_path(output)
			if not logical in registered: registered.append(logical)
	for logical: String in glossaries:
		var doc: RefCounted = glossaries[logical]
		if doc.sync_resource() != OK: return {"error":doc.last_error}
		changes.append({"path":doc.path, "before":doc._original_bytes, "after":doc._encoded_content()})
	config.set_value("dialogic/translation/locales", locales)
	config.set_value("internationalization/locale/translations", registered)
	config.set_value("internationalization/locale/fallback", config.values["dialogic/translation/original_locale"])
	changes.append(config_change())
	var result := Transaction.commit(workspace, changes)
	open_root(workspace)
	return result

func import_csv(source: String, destination: String) -> Dictionary:
	if workspace.content_path(destination).is_empty(): return {"error":"Choose a CSV destination inside the content root."}
	var incoming := read_csv(source)
	if incoming.has("error"): return incoming
	var existing := read_csv(destination, true)
	if existing.has("error"): return existing
	var merged := Csv.merge_import(existing.table, incoming.table, config.values["dialogic/translation/original_locale"])
	if merged.has("error"): return merged
	return Transaction.commit(workspace, [{"path":destination, "before":existing.before, "after":Csv.serialize(merged).to_utf8_buffer()}])

func preview_data() -> Dictionary:
	if not diagnostics.is_empty(): return {"error":"\n".join(diagnostics)}
	for logical: String in config.values["internationalization/locale/translations"]:
		var path: String = workspace.resolve_content_path(logical)
		if path.is_empty() or not FileAccess.file_exists(path): return {"error":"Missing registered translation: " + logical}
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() < 4: return {"error":"Unreadable registered translation: " + logical}
		var signature := file.get_buffer(4).get_string_from_ascii(); file.close()
		if path.get_extension() != "translation" or not signature in ["RSRC", "RSCC"]: return {"error":"Invalid registered native translation: " + logical + ". Collect translations again from the source CSV."}
	var loaded := tables()
	if loaded.has("error"): return loaded
	if loaded.tables.is_empty() and not config.values["internationalization/locale/translations"].is_empty(): return {"error":"PAGE preview requires the source CSV files for registered translations. Import the CSV files before previewing."}
	var mapping := update_glossary_mappings(loaded.tables, loaded.paths)
	if mapping.has("error"): return mapping
	var translations: Array[Translation] = []
	var seen := {}
	for table: Dictionary in loaded.tables.values():
		for resource: Translation in Csv.translations(table):
			for key: String in resource.get_message_list():
				var identity := resource.locale + "/" + key
				if seen.has(identity) and seen[identity] != resource.get_message(key): return {"error":"Conflicting translations in multiple CSVs: " + identity}
				seen[identity] = resource.get_message(key)
			translations.append(resource)
	var resources: Array[DialogicGlossary] = []
	for doc: RefCounted in glossaries.values(): resources.append(doc.glossary.duplicate(true))
	return {"translations":translations, "glossaries":resources, "settings":config.values.duplicate(true)}
