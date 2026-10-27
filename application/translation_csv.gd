extends "res://application/timeline_document.gd"

const Settings = preload("res://application/localization_config.gd")
var table: Dictionary = {}

func get_file_extension() -> String:
	return "csv"

func open_file(file_path: String) -> Error:
	var error := super.open_file(file_path)
	if error != OK: return error
	table = parse(content)
	return OK

func validate_content(text: String) -> Dictionary:
	var parsed := parse(text)
	return {"supported": not parsed.has("error"), "diagnostics": [parsed.error] if parsed.has("error") else []}

static func parse(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > 4194304 or text.to_utf8_buffer().has(0): return {"error":"CSV must be valid text up to 4 MiB without NUL."}
	text = text.trim_prefix(String.chr(0xFEFF))
	var records: Array = []
	var row: Array[String] = []
	var cell := ""
	var quoted := false
	var closed := false
	var i := 0
	while i < text.length():
		var c := text[i]
		if quoted:
			if c == '"':
				if i + 1 < text.length() and text[i + 1] == '"': cell += '"'; i += 1
				else: quoted = false; closed = true
			else: cell += c
		elif c == '"':
			if not cell.is_empty() or closed: return {"error":"A CSV quote must begin a field."}
			quoted = true
		elif c == ",":
			row.append(cell); cell = ""; closed = false
		elif c == "\n" or c == "\r":
			row.append(cell)
			if row.any(func(v: String): return not v.is_empty()): records.append(row.duplicate())
			row.clear(); cell = ""; closed = false
			if c == "\r" and i + 1 < text.length() and text[i + 1] == "\n": i += 1
		elif closed: return {"error":"Unexpected text after a quoted CSV field."}
		else: cell += c
		i += 1
	if quoted: return {"error":"Unclosed CSV quoted field."}
	row.append(cell)
	if row.any(func(v: String): return not v.is_empty()): records.append(row)
	if records.is_empty() or records[0].size() < 2 or records[0][0] != "keys": return {"error":"CSV requires a keys column followed by at least one locale."}
	var locales: Array[String] = []
	var normalized := {}
	for locale: String in records[0].slice(1):
		if not Settings.locale_valid(locale): return {"error":"Invalid CSV locale: " + locale}
		var key := TranslationServer.standardize_locale(locale)
		if normalized.has(key): return {"error":"Duplicate CSV locale: " + locale}
		normalized[key] = true; locales.append(locale)
	var rows := {}
	for record: Array in records.slice(1):
		if record.size() != locales.size() + 1: return {"error":"CSV row has the wrong number of columns: " + str(record[0])}
		var key: String = record[0]
		if key.is_empty() or rows.has(key): return {"error":"Empty or duplicate CSV key: " + key}
		rows[key] = record.slice(1)
	return {"locales":locales, "rows":rows}

static func quote(value: String) -> String:
	return '"' + value.replace('"', '""') + '"'

static func serialize(data: Dictionary) -> String:
	var result := "keys"
	for locale: String in data.locales: result += "," + quote(locale)
	result += "\n"
	for key: String in data.rows:
		result += quote(key)
		for value: String in data.rows[key]: result += "," + quote(value)
		result += "\n"
	return result

static func merge_source(existing: Dictionary, originals: Dictionary, original_locale: String) -> Dictionary:
	var locales: Array = existing.get("locales", [original_locale]).duplicate()
	var index := locale_index(locales, original_locale)
	if index < 0: return {"error":"Existing CSV does not contain the configured original locale: " + original_locale}
	var rows: Dictionary = existing.get("rows", {}).duplicate(true)
	var stale: Array[String] = []
	for key: String in rows:
		if not originals.has(key): stale.append(key)
	for key: String in originals:
		if not rows.has(key):
			var values: Array[String] = []
			values.resize(locales.size()); values.fill("")
			rows[key] = values
		rows[key][index] = originals[key]
	return {"locales":locales, "rows":rows, "stale":stale}

static func merge_import(existing: Dictionary, imported: Dictionary, original_locale: String) -> Dictionary:
	if locale_index(imported.locales, original_locale) < 0: return {"error":"Imported CSV must include the configured original locale."}
	var result: Dictionary = existing.duplicate(true)
	for locale: String in imported.locales:
		if locale_index(result.locales, locale) < 0:
			result.locales.append(locale)
			for key: String in result.rows: result.rows[key].append("")
	for key: String in imported.rows:
		if not result.rows.has(key):
			var values: Array[String] = []; values.resize(result.locales.size()); values.fill("")
			result.rows[key] = values
		for i: int in imported.locales.size(): result.rows[key][locale_index(result.locales, imported.locales[i])] = imported.rows[key][i]
	return result

static func locale_index(locales: Array, locale: String) -> int:
	var normalized := TranslationServer.standardize_locale(locale)
	for i: int in locales.size():
		if TranslationServer.standardize_locale(locales[i]) == normalized: return i
	return -1

static func translations(data: Dictionary) -> Array[Translation]:
	var result: Array[Translation] = []
	for i: int in data.locales.size():
		var resource := Translation.new()
		resource.locale = data.locales[i]
		for key: String in data.rows:
			var value: String = data.rows[key][i]
			if not value.is_empty(): resource.add_message(key, value)
		result.append(resource)
	return result
