extends ConfirmationDialog

signal applied(moods: Dictionary, default_mood: String)
const Field = preload("res://ui/components/native_value_field.gd")
const Assets = preload("res://application/media_assets.gd")
var moods: Dictionary = {}
var default_mood := ""
var selected := ""
var listing: ItemList
var name_field: LineEdit
var default_field: LineEdit
var fields: Dictionary = {}
var column: VBoxContainer
var message: Label
var syncing := false

func _ready() -> void:
	title = "Character typing sounds"; size = Vector2i(700, 630); min_size = Vector2i(550, 400); dialog_hide_on_ok = false
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(500, 330); add_child(scroll)
	column = VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(column)
	default_field = LineEdit.new(); default_field.name = "DefaultMood"; default_field.placeholder_text = "Default sound mood name"; column.add_child(default_field)
	listing = ItemList.new(); listing.name = "SoundMoods"; listing.custom_minimum_size.y = 100; column.add_child(listing)
	listing.item_selected.connect(func(index: int):
		var target := listing.get_item_text(index)
		if store_mood(): show_mood(target))
	var actions := HBoxContainer.new(); column.add_child(actions)
	for action: String in ["Add", "Remove"]:
		var button := Button.new(); button.text = action; actions.add_child(button)
		button.pressed.connect(func():
			if action == "Add":
				if not store_mood(): return
				var name := "mood"; var index := 1
				while moods.has(name): index += 1; name = "mood" + str(index)
				moods[name] = {}; refresh(); show_mood(name)
			else:
				moods.erase(selected); selected = ""; refresh(); show_mood(""))
	name_field = LineEdit.new(); name_field.name = "MoodName"; name_field.placeholder_text = "Mood name"; column.add_child(name_field)
	for key: String in ["sound_path", "mode", "pitch_base", "pitch_variance", "volume_base", "volume_variance", "skip_characters"]:
		var field := Field.new(); field.name = key; column.add_child(field); fields[key] = field
	message = Label.new(); message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(message)
	confirmed.connect(func():
		if not store_mood(): return
		var error := Assets.mood_error({"sound_moods":moods, "sound_mood_default":default_field.text})
		if not error.is_empty(): message.text = error; return
		applied.emit(moods.duplicate(true), default_field.text); hide())

func open_moods(info: Dictionary) -> void:
	moods = info.get("sound_moods", {}).duplicate(true); default_field.text = info.get("sound_mood_default", ""); selected = ""
	refresh(); show_mood(str(moods.keys()[0]) if not moods.is_empty() else ""); popup_fitted()

func popup_fitted() -> void:
	var host := get_parent().get_window()
	var desired := Vector2i(700, 630)
	if is_embedded(): desired = Vector2i(mini(desired.x, host.size.x - 40), mini(desired.y, host.size.y - 60))
	popup_centered(desired)

func refresh() -> void:
	listing.clear()
	for name: String in moods: listing.add_item(name)

func show_mood(name: String) -> void:
	selected = name; name_field.text = name
	var defaults := {"sound_path":"", "mode":0, "pitch_base":1.0, "pitch_variance":0.0, "volume_base":0.0, "volume_variance":0.0, "skip_characters":0}
	for key: String in fields:
		var field: Control = fields[key]
		for child: Node in field.get_children(): field.remove_child(child); child.queue_free()
		field.edited = false
		field.setup(key.replace("_", " ").capitalize(), moods.get(name, {}).get(key, defaults[key]))
	message.text = "Use a res:// audio file or folder. Modes: 0 Interrupt, 1 Overlap, 2 Await. Empty path disables this mood."

func store_mood() -> bool:
	if selected.is_empty(): return true
	var name := name_field.text.strip_edges()
	if name.is_empty() or (name != selected and moods.has(name)): message.text = "Use a unique, nonempty mood name."; return false
	var data: Dictionary = moods[selected].duplicate()
	for key: String in fields:
		data[key] = fields[key].value()
		if not fields[key].last_error.is_empty(): message.text = fields[key].last_error; return false
	data["name"] = name
	var error := Assets.mood_error({"sound_moods":{name:data}})
	if not error.is_empty(): message.text = error; return false
	moods.erase(selected); moods[name] = data; selected = name
	refresh(); return true
