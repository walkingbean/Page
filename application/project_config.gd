extends RefCounted
const Data = preload("res://application/variable_document.gd")

static func valid_key(key: String) -> bool:
	return RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_./-]*$").search(key) != null and not key.contains("..")

static func inspect(text: String) -> Dictionary:
	var valid := Data._scan_config(text)
	if valid.has("error"): return valid
	var result := {"entries":{}, "sections":{}}
	var section := ""
	var index := 0
	while index < text.length():
		if text[index] in [" ", "\t", "\r", "\n"]: index += 1; continue
		if text[index] == ";": index = Data._after_line(text, index); continue
		if text[index] == "[":
			result.sections[section] = index
			var end := text.find("]", index)
			section = text.substr(index + 1, end - index - 1).strip_edges()
			index = Data._after_line(text, end)
			continue
		var statement := index
		var quoted := false
		var escaped := false
		while index < text.length():
			if escaped: escaped = false
			elif text[index] == "\\" and quoted: escaped = true
			elif text[index] == '"': quoted = not quoted
			elif text[index] == "=" and not quoted: break
			index += 1
		var raw_key := text.substr(statement, index - statement).strip_edges()
		var key_config := ConfigFile.new()
		if key_config.parse("[key]\n" + raw_key + "=0\n") != OK: return {"error":"Invalid configuration key."}
		var key: String = key_config.get_section_keys("key")[0]
		index += 1
		while index < text.length() and text[index] in [" ", "\t", "\r", "\n"]: index += 1
		var span := Data._value_span(text, index)
		if span.has("error"): return span
		var literal := text.substr(index, span.end - index)
		var item := {"start":index, "end":span.end, "statement":statement, "next":span.next, "literal":literal, "opaque":Data._has_constructor(literal)}
		if not item.opaque:
			var decoded := Data._parse_value(literal)
			if decoded.has("error"): return decoded
			item["value"] = decoded.value
		result.entries[(section + "/" if not section.is_empty() else "") + key] = item
		index = span.next
	result.sections[section] = text.length()
	return result
