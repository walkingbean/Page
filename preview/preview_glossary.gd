extends "res://addons/dialogic/Modules/Glossary/subsystem_glossary.gd"

## Validate popup expressions before the native evaluator, then scope its assets.
const Variables = preload("res://application/text_variables.gd")
const Presentation = preload("res://application/text_presentation.gd")
var workspace: RefCounted
var report_error: Callable
var resources: Array[Resource] = []
var asset_cache := {}
var prefix := ""

func get_entry(entry_key: String) -> Dictionary:
	var glossary: DialogicGlossary = find_glossary(entry_key)
	if glossary == null: return {}
	var entry: Dictionary = glossary.get_entry(entry_key)
	var translated: bool = ProjectSettings.get_setting("dialogic/translation/enabled", false) and not glossary._translation_id.is_empty()
	var translation_key: String = glossary._translation_keys.get(entry_key, "")
	if translated and translation_key.is_empty(): return problem("Update the glossary CSV mapping before previewing: " + entry_key)
	for field: String in ["title", "text", "extra"]:
		var value: String = translate(translation_key.get_base_dir(), field, entry) if translated else entry.get(field, "")
		var checked := Variables.inspect(value, workspace, dialogic.VAR.var_storage, true)
		if checked.has("error"): return problem("Glossary " + entry_key + "/" + field + ": " + checked.error)
		var assets := Presentation.inspect(checked.expanded, workspace, null, true)
		if assets.has("error"): return problem("Glossary " + entry_key + "/" + field + ": " + assets.error)
	var result: Dictionary = super.get_entry(entry_key)
	for field: String in ["title", "text", "extra"]:
		var mapped := Presentation.remap(result[field], workspace, resources, prefix, asset_cache)
		if mapped.has("error"): return problem(mapped.error)
		result[field] = mapped.text
	return result

func problem(message: String) -> Dictionary:
	if report_error.is_valid(): report_error.call(message)
	return {}

func release() -> void:
	for resource: Resource in resources: resource.resource_path = ""
	resources.clear(); asset_cache.clear()
