extends RefCounted

## Defaults traced to the fixed Alpha 20 settings pages and subsystem readers.
## Dynamic locale defaults are resolved when opening the settings panel.
const EXTRA := {
	"animations/join_default": "Fade In Up", "animations/join_default_length": 0.5, "animations/join_default_wait": true,
	"animations/leave_default": "Fade Out Down", "animations/leave_default_length": 0.5, "animations/leave_default_wait": true,
	"animations/cross_fade_default": "Fade Cross", "animations/cross_fade_default_length": 0.5,
	"choices/autofocus_first": true, "choices/def_false_behaviour": 0, "choices/delay": 0.2,
	"choices/hotkey_behaviour": 0, "choices/reveal_by_input": false, "choices/reveal_delay": 0.0,
	"event_default_overrides": {}, "extensions_folder": "res://addons/dialogic_additions",
	"glossary/default_case_sensitive": true, "glossary/default_color": Color.POWDER_BLUE, "glossary/glossary_files": [],
	"layout/end_behaviour": 0, "portraits/default_portrait": "", "portraits/position_suggestion_names": "leftmost, left, center, right, rightmost",
	"text/custom_bbcode_effects": "", "timer/process_in_physics": false,
	"translation/add_separator": false, "translation/enabled": false, "translation/file_mode": 1, "translation/id_counter": 16,
	"translation/save_mode": 1, "translation/translation_folder": "", "translation/intern/file_mode": 1,
	"translation/intern/save_mode": 1, "translation/intern/translation_folder": "", "variables": {}
}
const ENUMS := {"choices/def_false_behaviour": "Hide,Disable", "choices/hotkey_behaviour": "None,Numbers", "layout/end_behaviour": "Free,Hide,Keep", "save/autosave_mode": "Timeline,Timer,Text", "text/split_at_new_lines_as": "New event,New line", "translation/file_mode": "Per project,Per timeline,None", "translation/save_mode": "Translation folder,Next to timeline,None"}

static func defaults() -> Dictionary:
	var result: Dictionary = preload("res://application/text_settings_document.gd").DEFAULTS.duplicate(true)
	result.merge(EXTRA, true)
	result["translation/original_locale"] = TranslationServer.get_tool_locale()
	result["translation/locales"] = TranslationServer.get_all_languages()
	return result

static func error(key: String, value: Variant) -> String:
	var known := defaults()
	var Native = preload("res://application/native_resource.gd")
	if not Native.finite_data(value): return "Settings must contain finite native values."
	if known.has(key) and not Native.compatible_type(typeof(known[key]), value): return "Incorrect native type for " + key
	if ENUMS.has(key) and (value < 0 or value >= str(ENUMS[key]).split(",").size()): return "Enum value is out of range: " + key
	if value is float and (key.contains("delay") or key.contains("length")) and value < 0: return "Delay and duration must be nonnegative."
	if key == "translation/id_counter" and value < 0: return "Translation ID counter must be nonnegative."
	var legacy = preload("res://application/text_settings_document.gd")
	if legacy.DEFAULTS.has(key) or key.begins_with("settings/"): return legacy.value_error(key, value)
	return ""
