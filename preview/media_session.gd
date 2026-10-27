extends RefCounted

const Assets = preload("res://application/media_assets.gd")
var workspace: RefCounted
var window: Window
var handler: DialogicGameHandler
var resources: Array[Resource] = []
var paths: Dictionary = {}
var reverse_paths: Dictionary = {}
var timelines: Dictionary = {}
var characters: Dictionary = {}
var old_history: Dictionary = {}
var old_bus_layout: AudioBusLayout
var save_node: Node
var original_audio: Node
var audio_node: Node
var prefix := ""
var last_error := ""
var content_fingerprint := ""
var active := false
var saved_content := false

func begin(owner_window: Window, runtime: DialogicGameHandler, content: RefCounted, root: DialogicTimeline, presentation: RefCounted) -> Error:
	window = owner_window; handler = runtime; workspace = content
	prefix = "res://__page_media_%d_%d" % [window.get_instance_id(), window.get("_generation")]
	var layout := Assets.buses(workspace)
	if layout.has("error"): last_error = layout.error; return ERR_INVALID_DATA
	var configured_buses: Array = [ProjectSettings.get_setting("dialogic/audio/type_sound_bus", "Master")]
	for channel: Dictionary in ProjectSettings.get_setting("dialogic/audio/channel_defaults", {}).values(): configured_buses.append(channel.get("audio_bus", ""))
	for bus: String in configured_buses:
		if not bus.is_empty() and not layout.buses.has(bus): last_error = "Audio settings reference a missing content bus: " + bus; return ERR_INVALID_DATA
	old_bus_layout = AudioServer.generate_bus_layout()
	active = true
	original_audio = handler.get_node("Audio")
	handler.remove_child(original_audio)
	audio_node = preload("res://preview/preview_audio.gd").new()
	audio_node.name = "Audio"; audio_node.dialogic = handler
	handler.add_child(audio_node)
	AudioServer.bus_count = layout.buses.size()
	var i := 0
	for name: String in layout.buses:
		var bus: Dictionary = layout.buses[name]
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_volume_db(i, bus.volume_db)
		AudioServer.set_bus_mute(i, bus.mute)
		AudioServer.set_bus_solo(i, bus.solo)
		AudioServer.set_bus_bypass_effects(i, bus.bypass_fx)
		if i > 0: AudioServer.set_bus_send(i, bus.send)
		i += 1
	var all: Array = root.get_meta("preview_timelines", {}).values(); all.append(root)
	for timeline: DialogicTimeline in all:
		var source_path: String = timeline.get_meta("source_path", "")
		var logical: String = workspace.content_path(source_path) if workspace != null and source_path != "@current" else ""
		if logical.is_empty(): logical = "res://__unsaved_preview.dtl"
		var virtual := prefix.path_join("timeline_" + str(timelines.size()) + ".dtl")
		timeline.take_over_path(virtual)
		paths[logical] = virtual; reverse_paths[virtual] = logical; timelines[logical] = timeline
		resources.append(timeline)
		for event: DialogicEvent in timeline.events:
			if event is DialogicBackgroundEvent and event.argument.begins_with("res://"): event.argument = register_asset(event.argument, "image")
			elif event is DialogicAudioEvent or event is DialogicVoiceEvent:
				if not event.file_path.is_empty(): event.file_path = register_asset(event.file_path, "audio")
			if not last_error.is_empty(): restore(); return ERR_CANT_OPEN
	for key: String in presentation.directory:
		if key.begins_with("res://"):
			paths[key] = presentation.directory[key]; reverse_paths[presentation.directory[key]] = key
	for identifier: String in root.get_meta("preview_characters", {}):
		var character: DialogicCharacter = root.get_meta("preview_characters")[identifier]
		var logical: String = workspace.content_path(workspace.characters[identifier].path)
		characters[logical] = character
		character.set_meta("page_content_character", logical)
		var problem := Assets.mood_error(character.custom_info, workspace)
		if not problem.is_empty(): last_error = problem; restore(); return ERR_INVALID_DATA
		for name: String in character.custom_info.get("sound_moods", {}):
			var mood: Dictionary = character.custom_info.sound_moods[name]
			var files := Assets.sound_files(mood.get("sound_path", ""), workspace)
			var sounds: Array[AudioStream] = []
			for logical_sound: String in files.paths:
				var mapped := register_asset(logical_sound, "audio")
				if mapped.is_empty(): restore(); return ERR_CANT_OPEN
				sounds.append(load(mapped))
			# Runtime clones use the native sounds array; source keeps sound_path.
			mood.erase("sound_path"); mood["sounds"] = sounds
	var fields := {"simple_history_enabled":"simple_history_enabled", "simple_history_save":"simple_history_save", "full_event_history_enabled":"full_history_enabled", "full_event_history_save":"full_history_save", "visited_event_history_enabled":"visited_event_history_enabled", "save_visited_history_on_save":"save_on_save", "save_visited_history_on_autosave":"save_on_autosave"}
	for field: String in fields: old_history[field] = handler.History.get(field)
	for field: String in ["simple_history_content", "full_event_history_content", "visited_event_history_content"]: old_history[field] = handler.History.get(field).duplicate(true)
	# The preview owns a fresh history; restore the application snapshot on exit.
	handler.History.simple_history_content = []
	handler.History.full_event_history_content = []
	save_node = preload("res://preview/preview_save.gd").new()
	save_node.name = "Save"; save_node.dialogic = handler; save_node.session = self
	var root_name: String = workspace.root_path if workspace != null else "unsaved"
	save_node.save_root = "user://preview_saves/" + root_name.sha256_text() + "/"
	saved_content = workspace != null and not window.get("_source_path").is_empty() and FileAccess.file_exists(window.get("_source_path")) and normalize(FileAccess.get_file_as_string(window.get("_source_path"))) == normalize(window.get("_source"))
	content_fingerprint = fingerprint()
	handler.add_child(save_node)
	for field: String in fields: handler.History.set(field, ProjectSettings.get_setting("dialogic/history/" + fields[field], false))
	# Native setters share one signal connection; preserve the logical OR.
	if handler.History.save_visited_history_on_save or handler.History.save_visited_history_on_autosave: handler.History._update_saved_connection(true)
	handler.History.visited_event_history_content = {}
	if handler.History.visited_event_history_enabled: handler.History.load_visited_history()
	return OK

func register_asset(logical: String, kind: String) -> String:
	if paths.has(logical): return paths[logical]
	last_error = Assets.path_error(logical, workspace, kind)
	if not last_error.is_empty(): return ""
	var absolute: String = workspace.resolve_content_path(logical)
	var resource: Resource = Assets.audio(absolute) if kind == "audio" else ImageTexture.create_from_image(Image.load_from_file(absolute))
	var virtual := prefix.path_join("asset_" + str(resources.size()) + "." + logical.get_extension())
	resource.take_over_path(virtual); resources.append(resource)
	paths[logical] = virtual; reverse_paths[virtual] = logical
	return virtual

func normalize(text: String) -> String:
	return text.trim_prefix(String.chr(0xFEFF)).replace("\r\n", "\n").replace("\r", "\n")

func fingerprint() -> String:
	if workspace == null: return ""
	var items := PackedStringArray()
	if ProjectSettings.get_setting("dialogic/translation/enabled", false): items.append("@preview_locale:" + TranslationServer.get_locale())
	var queue: Array[String] = [workspace.root_path]
	var count := 0
	while not queue.is_empty():
		var directory: String = queue.pop_front()
		for name: String in DirAccess.get_directories_at(directory):
			if name.begins_with(".") or name == "addons": continue
			var child := directory.path_join(name)
			if not workspace.content_path(child).is_empty(): queue.append(child)
		for name: String in DirAccess.get_files_at(directory):
			if name.ends_with(".import") or name.ends_with(".uid"): continue
			var file := directory.path_join(name)
			if workspace.content_path(file).is_empty(): continue
			count += 1
			if count > 20000: return ""
			items.append(workspace.content_path(file) + ":" + FileAccess.get_sha256(file))
	items.sort(); return "\n".join(items).sha256_text()

func map_value(value: Variant, outward: bool) -> Variant:
	if value is DialogicTimeline:
		var logical: String = reverse_paths.get(value.resource_path, value.resource_name)
		if not outward: return timelines.get(logical)
		var native := DialogicTimeline.new(); native.resource_name = logical
		return native
	if value is DialogicCharacter:
		var logical: String = value.get_meta("page_content_character", value.resource_name)
		if not outward: return characters.get(logical)
		var native := DialogicCharacter.new(); native.resource_name = logical
		return native
	if value is DialogicSaveState:
		var state := DialogicSaveState.new(); state.timeline = map_value(value.timeline, outward); state.event_index = value.event_index
		state.subsystems.assign(map_value(value.subsystems, outward)); return state
	if value is Dictionary:
		var copy: Dictionary = value.duplicate(); copy.clear()
		for key: Variant in value: copy[map_value(key, outward)] = map_value(value[key], outward)
		return copy
	if value is Array:
		var copy: Array = value.duplicate()
		for i: int in copy.size(): copy[i] = map_value(copy[i], outward)
		return copy
	if value is String:
		var mapping: Dictionary = reverse_paths if outward else paths
		if mapping.has(value): return mapping[value]
		# Visited-event keys append an event index to the timeline path.
		for path: String in mapping:
			if value.begins_with(path) and value.substr(path.length()).is_valid_int(): return mapping[path] + value.substr(path.length())
		# Full history stores native event text with quoted resource arguments.
		var mapped: String = value
		for path: String in mapping: mapped = mapped.replace('"' + path + '"', '"' + mapping[path] + '"')
		return mapped
	return value

func restore() -> void:
	if not active: return
	if is_instance_valid(save_node):
		save_node.autosave_enabled = false
		handler.History._update_saved_connection(false)
		if save_node.get_parent() != null: handler.remove_child(save_node)
		save_node.session = null; save_node.queue_free(); save_node = null
	handler.Voice.stop_audio(); handler.Voice.voice_player.stream = null; handler.Voice.current_audio_file = ""
	handler.Audio.stop_all_channels(); handler.Audio.stop_all_one_shot_sounds()
	if is_instance_valid(audio_node):
		audio_node.cancel_preview_tweens()
		handler.remove_child(audio_node); audio_node.queue_free(); audio_node = null
	if is_instance_valid(original_audio) and original_audio.get_parent() == null: handler.add_child(original_audio)
	for field: String in old_history:
		if not field.begins_with("save_visited"): handler.History.set(field, old_history[field])
	# Reconnect to the original Save after the presentation session restores it.
	AudioServer.set_bus_layout(old_bus_layout)
	for resource: Resource in resources: resource.resource_path = ""
	resources.clear(); paths.clear(); reverse_paths.clear(); timelines.clear(); characters.clear()
	active = false

func restore_history_connections() -> void:
	for field: String in ["save_visited_history_on_save", "save_visited_history_on_autosave"]:
		if old_history.has(field): handler.History.set(field, old_history[field])
	if old_history.get("save_visited_history_on_save", false) or old_history.get("save_visited_history_on_autosave", false): handler.History._update_saved_connection(true)
