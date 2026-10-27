extends RefCounted

const Project = preload("res://application/localization_project.gd")
var active := false
var old_locale := ""
var old_translations: Array[Translation] = []
var translations: Array[Translation] = []
var old_settings: Dictionary = {}
var old_glossaries: Array = []
var glossaries: Array = []
var old_callback: Callable
var original_glossary: Node
var preview_glossary: Node
var glossary_index := -1
var old_parse_stack: Array = []
var handler: DialogicGameHandler
var last_error := ""
var locales: Array[String] = []

func begin(runtime: DialogicGameHandler, workspace: RefCounted, selected_locale: String, owner_window: Window = null) -> Error:
	handler = runtime
	var settings: Dictionary = Project.Config.DEFAULTS.duplicate(true)
	glossaries.clear()
	if workspace != null:
		var project := Project.new()
		if project.open_root(workspace) != OK: last_error = project.last_error; return ERR_INVALID_DATA
		var data := project.preview_data()
		if data.has("error"): last_error = data.error; return ERR_INVALID_DATA
		settings = data.settings; glossaries = data.glossaries; translations = data.translations
	old_locale = TranslationServer.get_locale()
	old_translations.assign(TranslationServer.get_translations())
	old_glossaries = handler.Glossary.glossaries.duplicate()
	old_parse_stack = handler.Text.parse_stack.duplicate()
	old_callback = handler.get("preview_localization")
	for key: String in settings:
		if not key.begins_with("dialogic/"): continue
		old_settings[key] = {"exists":ProjectSettings.has_setting(key), "value":ProjectSettings.get_setting(key)}
		ProjectSettings.set_setting(key, settings[key])
	# Native clear() must never try to resolve target res:// paths in the app.
	ProjectSettings.set_setting("dialogic/glossary/glossary_files", [])
	for resource: Translation in old_translations: TranslationServer.remove_translation(resource)
	# The native fallback setter is not script-bound in Godot 4.7.1. Merge the
	# original-language messages into session-only translations instead of
	# changing the host application's global fallback setting.
	var original: String = TranslationServer.standardize_locale(settings["dialogic/translation/original_locale"])
	var grouped := {}
	for resource: Translation in translations:
		if not grouped.has(resource.locale): grouped[resource.locale] = {}
		for key: String in resource.get_message_list(): grouped[resource.locale][key] = resource.get_message(key)
	if not grouped.has(original): grouped[original] = {}
	translations.clear()
	for locale: String in grouped:
		var resource := Translation.new(); resource.locale = locale
		var messages: Dictionary = grouped[original].duplicate()
		messages.merge(grouped[locale], true)
		for key: String in messages: resource.add_message(key, messages[key])
		translations.append(resource)
	for resource: Translation in translations:
		TranslationServer.add_translation(resource)
		if not resource.locale in locales: locales.append(resource.locale)
	if not original in locales: locales.push_front(original)
	var selected := TranslationServer.standardize_locale(selected_locale)
	TranslationServer.set_locale(selected if selected in locales else original)
	original_glossary = handler.get_node("Glossary"); glossary_index = original_glossary.get_index()
	handler.remove_child(original_glossary)
	preview_glossary = preload("res://preview/preview_glossary.gd").new()
	preview_glossary.name = "Glossary"; preview_glossary.dialogic = handler; preview_glossary.workspace = workspace
	preview_glossary.enabled = original_glossary.enabled; preview_glossary.color_overrides = original_glossary.color_overrides.duplicate(true)
	preview_glossary.prefix = "res://__page_glossary_" + str(Time.get_ticks_usec())
	preview_glossary.report_error = func(message: String):
		last_error = message
		if is_instance_valid(owner_window): owner_window.call("report_localization_error", message)
	handler.add_child(preview_glossary); handler.move_child(preview_glossary, glossary_index)
	preview_glossary.glossaries = glossaries
	handler.Text.load_parse_stack()
	handler.set("preview_localization", restore_glossaries)
	active = true
	return OK

func restore_glossaries() -> void:
	if active: handler.Glossary.glossaries = glossaries

func restore() -> void:
	if not active: return
	for resource: Translation in translations: TranslationServer.remove_translation(resource)
	for resource: Translation in old_translations: TranslationServer.add_translation(resource)
	TranslationServer.set_locale(old_locale)
	for key: String in old_settings: ProjectSettings.set_setting(key, old_settings[key].value if old_settings[key].exists else null)
	handler.set("preview_localization", old_callback)
	if is_instance_valid(preview_glossary):
		preview_glossary.release(); handler.remove_child(preview_glossary); preview_glossary.queue_free()
	if is_instance_valid(original_glossary):
		handler.add_child(original_glossary); handler.move_child(original_glossary, glossary_index)
		original_glossary.glossaries = old_glossaries
	handler.Text.parse_stack = old_parse_stack
	translations.clear(); old_translations.clear(); locales.clear()
	active = false
