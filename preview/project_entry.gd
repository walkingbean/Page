extends Node

## This file runs only in the target's independent native process.
func _ready() -> void:
	call_deferred("_start")

func _start() -> void:
	var arguments := OS.get_cmdline_user_args()
	var mode := "project"
	var entry := ""
	for index: int in arguments.size():
		if arguments[index] == "--page-mode" and index + 1 < arguments.size(): mode = arguments[index + 1]
		if arguments[index] == "--page-entry" and index + 1 < arguments.size(): entry = arguments[index + 1]
	print("PAGE_TARGET_READY ", JSON.stringify({"mode":mode, "entry":entry, "pid":OS.get_process_id()}))
	if mode == "project" or mode == "scene" or mode == "editor":
		if entry.is_empty(): _failure("No target scene selected."); return
		var resource := load(entry)
		if not resource is PackedScene: _failure("Target is not a valid PackedScene: " + entry); return
		var instance: Node = resource.instantiate()
		if instance == null: _failure("Cannot instantiate target scene: " + entry); return
		get_tree().root.add_child(instance)
		get_tree().current_scene = instance
		if mode == "editor":
			if not instance is DialogicEditor: _failure("Select a runtime-compatible DialogicEditor scene."); return
			var layer := CanvasLayer.new(); add_child(layer)
			var save := Button.new(); save.text = "Save editor"; save.position = Vector2(12, 8); layer.add_child(save)
			save.pressed.connect(instance._save)
			instance.position.y = 48
			instance._open(null); instance.opened.emit()
			print("PAGE_TARGET_EDITOR_OPENED ", instance._get_title())
		print("PAGE_TARGET_SCENE_LOADED ", entry)
		return
	var dialogic := get_node_or_null("/root/Dialogic")
	if dialogic == null: _failure("Native Dialogic autoload is missing."); return
	dialogic.signal_event.connect(func(argument: Variant): print("PAGE_TARGET_SIGNAL ", var_to_str(argument)))
	dialogic.timeline_ended.connect(func(): print("PAGE_TARGET_TIMELINE_ENDED"))
	var timeline := DialogicTimeline.new()
	if not FileAccess.file_exists(entry): _failure("Timeline is missing: " + entry); return
	timeline.from_text(FileAccess.get_file_as_string(entry))
	timeline.resource_path = entry
	timeline.process()
	if timeline.events.is_empty(): _failure("The target timeline has no native events."); return
	var text_commands := ["br", "b", "i", "u", "s", "code", "center", "right", "fill", "indent", "url", "img", "font", "font_size", "color", "bgcolor", "fgcolor", "outline_size", "outline_color", "table", "cell", "wave", "tornado", "shake", "fade", "rainbow", "pulse"]
	for indexer: DialogicIndexer in DialogicUtil.get_indexers():
		for effect: Dictionary in indexer._get_text_effects() + indexer._get_text_modifiers():
			if effect.has("command"): text_commands.append(str(effect.command))
	for event: DialogicEvent in timeline.events:
		if event is DialogicTextEvent:
			var shortcode := RegEx.create_from_string('^\\[([A-Za-z_][A-Za-z0-9_]*)(?:\\s[^\\n]*|=[^\\n]*)?\\]$').search(event.text.strip_edges())
			if shortcode != null and not shortcode.get_string(1) in text_commands:
				push_warning("Unregistered shortcode in target timeline; native parser treats it as text: " + event.text)
	dialogic.start(timeline)
	print("PAGE_TARGET_TIMELINE_STARTED ", entry)

func _failure(message: String) -> void:
	push_error("PAGE_TARGET_FAILED " + message)
	get_tree().quit(1)
