extends RefCounted

## Owns preview-only settings/resource mappings. The native Save subsystem is
## temporarily detached so native Setting events cannot persist global values.
const SettingsDocument = preload("res://application/text_settings_document.gd")
const Presentation = preload("res://application/text_presentation.gd")
var owner_window: Window
var handler: DialogicGameHandler
var workspace: RefCounted
var resources: Array[Resource] = []
var asset_cache: Dictionary = {}
var directory: Dictionary = {}
var old_directory: Dictionary = {}
var old_settings: Dictionary = {}
var old_runtime_settings: Dictionary = {}
var old_modifiers: Array = []
var old_parse_stack: Array = []
var old_autopauses: Dictionary = {}
var old_auto: Dictionary = {}
var save_node: Node
var save_index := -1
var save_enabled := false
var prefix := ""
var active := false
var last_error := ""
var signal_baselines: Array[Dictionary] = []

func begin(window: Window, runtime: DialogicGameHandler, content_workspace: RefCounted, generation: int) -> Error:
	owner_window = window; handler = runtime; workspace = content_workspace
	prefix = "res://__preview_text_%d_%d" % [window.get_instance_id(), generation]
	if workspace != null and workspace.text_settings != null:
		last_error = workspace.text_settings.preview_error()
		if not last_error.is_empty(): return ERR_UNAVAILABLE
	var values: Dictionary = SettingsDocument.DEFAULTS.duplicate(true)
	if workspace != null and workspace.text_settings != null: values.merge(workspace.text_settings.values, true)
	for signal_value: Signal in [handler.Inputs.dialogic_action, handler.Inputs.dialogic_action_priority, handler.Wait.timeout, handler.TextInput.input_confirmed, handler.Inputs.auto_advance.autoadvance]:
		var callbacks: Array[Callable] = []
		for connection: Dictionary in signal_value.get_connections(): callbacks.append(connection.callable)
		signal_baselines.append({"signal": signal_value, "callbacks": callbacks})
	old_directory = DialogicStylesUtil.style_directory.duplicate()
	old_runtime_settings = handler.Settings.settings.duplicate(true)
	old_modifiers = handler.Text.text_modifiers.duplicate()
	old_parse_stack = handler.Text.parse_stack.duplicate()
	old_autopauses = handler.Text._autopauses.duplicate()
	var keys := values.keys()
	for prop: Dictionary in ProjectSettings.get_property_list():
		if prop.name.begins_with("dialogic/settings/"):
			var key: String = prop.name.trim_prefix("dialogic/")
			if not key in keys: keys.append(key)
	for key: String in keys:
		var full := "dialogic/" + key
		old_settings[full] = {"exists": ProjectSettings.has_setting(full), "value": ProjectSettings.get_setting(full)}
		ProjectSettings.set_setting(full, values.get(key))
	active = true
	if handler.has_subsystem("Save"):
		save_node = handler.Save
		save_index = save_node.get_index()
		save_enabled = save_node.autosave_enabled
		save_node.autosave_enabled = false
		handler.remove_child(save_node)
	if workspace != null and workspace.style_catalog != null:
		var mapped: Dictionary = workspace.style_catalog.runtime(resources, prefix, asset_cache)
		if mapped.has("error"): last_error = mapped.error; restore(); return ERR_INVALID_DATA
		directory = mapped.directory
	DialogicStylesUtil.style_directory = directory
	ProjectSettings.set_setting("dialogic/layout/default_style", directory.get("", ""))
	handler.Settings._reload_settings()
	handler.Text._clear_state()
	handler.Text._update_user_speed(handler.Settings.get_setting("text_speed", 1.0))

	handler.Text._autopauses.clear()
	for chars: String in values.get("text/autopauses", {}):
		handler.Text._autopauses[RegEx.create_from_string(r"(?<!(\[|\{))[" + chars + r"](?!([^{}\[\]]*[\]\}]|$))")] = values["text/autopauses"][chars]
	handler.Text.text_modifiers.append({"method": remap_text, "type": -1, "order": 45})
	handler.Text.load_parse_stack()
	var auto: RefCounted = handler.Inputs.auto_advance
	var mapping := {"fixed_delay":"autoadvance_fixed_delay", "per_word_delay":"autoadvance_per_word_delay", "per_character_delay":"autoadvance_per_character_delay", "ignored_characters_enabled":"autoadvance_ignored_characters_enabled", "ignored_characters":"autoadvance_ignored_characters"}
	for field: String in mapping:
		old_auto[field] = auto.get(field)
		auto.set(field, values["text/" + mapping[field]])
	for field: String in ["enabled_forced", "enabled_until_user_input", "enabled_until_next_event", "override_delay_for_current_event", "delay_modifier"]: old_auto[field] = auto.get(field)
	old_auto["skip_time"] = handler.Inputs.auto_skip.time_per_event
	# Alpha-20 initializes this field to 1.0 and only changes it on a
	# Settings change signal; _reload_settings does not emit that signal.
	auto.delay_modifier = 1.0
	auto.enabled_forced = values["text/autoadvance_enabled"]
	handler.Inputs.auto_skip.time_per_event = values["text/autoskip_time_per_event"]
	return OK

func remap_text(text: String) -> String:
	var mapped := Presentation.remap(text, workspace, resources, prefix, asset_cache)
	if mapped.has("error"):
		last_error = mapped.error
		owner_window.call_deferred("_abort_presentation", last_error)
		return ""
	return mapped.text

func remap_style_reference(value: String) -> String:
	return directory.get(value, value) if value.begins_with("res://") else value

func disconnect_waits() -> void:
	for baseline: Dictionary in signal_baselines:
		var native_signal: Signal = baseline.signal
		for connection: Dictionary in native_signal.get_connections():
			if not connection.callable in baseline.callbacks and native_signal.is_connected(connection.callable): native_signal.disconnect(connection.callable)
	signal_baselines.clear()

func restore() -> void:
	if not active: return
	disconnect_waits()
	handler.Inputs.stop_timers()
	for key: String in old_settings:
		ProjectSettings.set_setting(key, old_settings[key].value if old_settings[key].exists else null)
	DialogicStylesUtil.style_directory = old_directory
	handler.Text.text_modifiers.assign(old_modifiers)
	handler.Text.parse_stack.assign(old_parse_stack)
	handler.Text._autopauses = old_autopauses
	handler.Settings.settings = old_runtime_settings
	handler.Text._update_user_speed(handler.Settings.get_setting("text_speed", 1.0))
	for field: String in old_auto:
		if field == "skip_time": handler.Inputs.auto_skip.time_per_event = old_auto[field]
		else: handler.Inputs.auto_advance.set(field, old_auto[field])
	if is_instance_valid(save_node):
		handler.add_child(save_node)
		handler.move_child(save_node, mini(save_index, handler.get_child_count() - 1))
		save_node.autosave_enabled = save_enabled
	for resource: Resource in resources: resource.resource_path = ""
	resources.clear(); asset_cache.clear(); directory.clear()
	save_node = null
	active = false
