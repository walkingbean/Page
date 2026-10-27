@tool
extends DialogicEditor
var field: TextEdit
var picker: FileDialog
var status: Label
var loaded_path := ""
var loaded_hash := ""

func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var label := Label.new()
	label.text = "Native extension editor — DemoExtension"
	box.add_child(label)
	field = TextEdit.new()
	field.custom_minimum_size = Vector2(600, 260)
	field.text = "Edit this message, then Save editor to a native .cfg file."
	box.add_child(field)
	field.text_changed.connect(func(): current_resource_state = ResourceStates.UNSAVED)
	var open_button := Button.new()
	open_button.text = "Open native config"
	box.add_child(open_button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.add_filter("*.cfg", "Godot configuration")
	add_child(picker)
	picker.file_selected.connect(_selected)
	open_button.pressed.connect(func():
		picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		picker.popup_centered_ratio(0.8))

func _get_title() -> String:
	return "DemoExtension"

func _open(_extra: Variant = null) -> void:
	status.text = "Choose an output file explicitly. Preview source files remain unchanged."
	print("CUSTOM_EDITOR_OPENED")

func _save() -> void:
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.current_file = "extension_settings.cfg"
	picker.popup_centered_ratio(0.8)

func _selected(path: String) -> void:
	var config := ConfigFile.new()
	if picker.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		if config.load(path) != OK:
			status.text = "Cannot open config: " + path
			return
		field.text = str(config.get_value("custom", "message", ""))
	else:
		if FileAccess.file_exists(path) and (path != loaded_path or FileAccess.get_sha256(path) != loaded_hash):
			status.text = "Output already exists or changed externally. Open it first or choose a new file."
			return
		if path == loaded_path and config.load(path) != OK:
			status.text = "Cannot reload the original config."
			return
		config.set_value("custom", "message", field.text)
		if config.save(path) != OK:
			status.text = "Cannot save config: " + path
			return
		print("CUSTOM_EDITOR_SAVED ", path)
	loaded_path = path
	loaded_hash = FileAccess.get_sha256(path)
	current_resource_state = ResourceStates.SAVED
	status.text = "Native config: " + path
