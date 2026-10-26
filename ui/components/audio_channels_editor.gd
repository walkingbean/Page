extends "res://ui/components/sound_mood_editor.gd"

signal channels_applied(channels: Dictionary)

func _ready() -> void:
	super._ready()
	title = "Audio channel defaults"
	default_field.hide()
	for callback: Dictionary in confirmed.get_connections(): confirmed.disconnect(callback.callable)
	confirmed.connect(func():
		if store_mood(): channels_applied.emit(moods.duplicate(true)); hide())
	for control: Control in fields.values(): column.remove_child(control); control.queue_free()
	fields.clear()
	for key: String in ["volume", "audio_bus", "fade_length", "loop"]:
		var field := Field.new(); field.name = key; column.add_child(field); fields[key] = field
	column.move_child(message, column.get_child_count() - 1)

func open_channels(channels: Dictionary) -> void:
	moods = channels.duplicate(true); selected = ""; refresh()
	show_mood(str(moods.keys()[0]) if not moods.is_empty() else "")
	popup_fitted()

func show_mood(name: String) -> void:
	selected = name; name_field.text = name; name_field.placeholder_text = "Channel name · empty is one-shot SFX"
	var defaults := {"volume":0.0, "audio_bus":"", "fade_length":0.0, "loop":not name.is_empty()}
	for key: String in fields:
		var field: Control = fields[key]
		for child: Node in field.get_children(): field.remove_child(child); child.queue_free()
		field.edited = false; field.setup(key.replace("_", " ").capitalize(), moods.get(name, {}).get(key, defaults[key]))
	message.text = "Volume is in dB; negative values are valid. Empty channel is one-shot SFX: fade 0 and loop off."

func store_mood() -> bool:
	if not moods.has(selected): return true
	var name := name_field.text.strip_edges()
	if name != selected and moods.has(name): message.text = "Channel names must be unique."; return false
	var data := {}
	for key: String in fields:
		data[key] = fields[key].value()
		if not fields[key].last_error.is_empty(): message.text = fields[key].last_error; return false
	var error: String = preload("res://application/text_settings_document.gd").value_error("audio/channel_defaults", {name:data})
	if not error.is_empty(): message.text = error; return false
	moods.erase(selected); moods[name] = data; selected = name; refresh(); return true
