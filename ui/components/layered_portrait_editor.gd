extends ConfirmationDialog

signal saved(path: String)
const Document = preload("res://application/layered_portrait_document.gd")
var document: RefCounted
var workspace: RefCounted
var draft: Dictionary = {}
var path_field: LineEdit
var layers: ItemList
var node_name_field: LineEdit
var parent_field: LineEdit
var image_field: LineEdit
var x_field: SpinBox
var y_field: SpinBox
var sx_field: SpinBox
var sy_field: SpinBox
var visible_field: CheckBox
var fix_field: CheckBox
var image_preview: TextureRect
var message: Label
var png_dialog: FileDialog
var selected := 0
var changing := false
var controls: Array[Control] = []

func _ready() -> void:
	title = "Native layered portrait"
	size = Vector2i(710, 640)
	min_size = Vector2i(600, 420)
	dialog_hide_on_ok = false
	get_ok_button().text = "Save scene and use"
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(550, 370)
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	path_field = field(column, "Scene path · res:// inside the content folder", "ScenePath")
	fix_field = CheckBox.new()
	fix_field.text = "Fix offset · native bottom alignment"
	column.add_child(fix_field)
	controls.append(fix_field)
	fix_field.toggled.connect(func(value: bool):
		if not changing and not draft.is_empty(): draft.nodes[0].properties["fix_offset"] = value)
	layers = ItemList.new()
	layers.name = "Layers"
	layers.custom_minimum_size.y = 100
	column.add_child(layers)
	layers.item_selected.connect(show_layer)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	for action: String in ["Add sprite", "Add group", "Delete layer"]:
		var button := Button.new()
		button.text = action
		button.pressed.connect(change_layers.bind(action))
		actions.add_child(button)
		controls.append(button)
	node_name_field = field(column, "Name · Apply layer after editing", "LayerName")
	parent_field = field(column, "Parent path · . means root", "LayerParent")
	image_field = field(column, "Sprite image · res://…png", "LayerImage")
	var image_actions := HBoxContainer.new()
	column.add_child(image_actions)
	var choose := Button.new()
	choose.text = "Import PNG"
	choose.pressed.connect(func(): png_dialog.popup_centered_ratio(0.65))
	image_actions.add_child(choose)
	controls.append(choose)
	image_preview = TextureRect.new()
	image_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_preview.custom_minimum_size = Vector2(100, 72)
	image_actions.add_child(image_preview)
	var transform := HBoxContainer.new()
	column.add_child(transform)
	x_field = number(transform, "Position X")
	y_field = number(transform, "Position Y")
	sx_field = number(transform, "Scale X")
	sy_field = number(transform, "Scale Y")
	visible_field = CheckBox.new()
	visible_field.text = "Visible"
	column.add_child(visible_field)
	controls.append(visible_field)
	var apply := Button.new()
	apply.text = "Apply layer"
	apply.pressed.connect(apply_layer)
	column.add_child(apply)
	controls.append(apply)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	png_dialog = FileDialog.new()
	png_dialog.access = FileDialog.ACCESS_FILESYSTEM
	png_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	png_dialog.filters = PackedStringArray(["*.png ; PNG image"])
	add_child(png_dialog)
	png_dialog.file_selected.connect(func(path: String):
		var logical: String = workspace.import_portrait(path)
		if logical.is_empty(): message.text = workspace.last_error
		else: image_field.text = logical; update_image())
	confirmed.connect(save_scene)

func field(parent: Control, caption: String, node_name: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.name = node_name
	parent.add_child(edit)
	controls.append(edit)
	return edit

func number(parent: Control, caption: String) -> SpinBox:
	var column := VBoxContainer.new()
	parent.add_child(column)
	var label := Label.new()
	label.text = caption
	column.add_child(label)
	var box := SpinBox.new()
	box.min_value = -1000000
	box.max_value = 1000000
	box.step = 0.01
	column.add_child(box)
	controls.append(box)
	return box

func open_scene(source_workspace: RefCounted, logical: String = "") -> void:
	if source_workspace == null: return
	workspace = source_workspace
	document = Document.new()
	document.workspace = workspace
	path_field.text = logical if not logical.is_empty() else "res://portraits/layered.tscn"
	var absolute: String = workspace.resolve_content_path(path_field.text)
	if not absolute.is_empty() and FileAccess.file_exists(absolute):
		if document.open_file(absolute, workspace) != OK:
			message.text = document.last_error
		else: message.text = "\n".join(document.diagnostics)
		draft = document.model.duplicate(true)
	else:
		draft = {"nodes": [{"name": "LayeredPortrait", "type": "CanvasGroup", "parent": "", "path": ".", "image": "", "properties": {"fix_offset": true}}]}
		message.text = "Create a native scene. Add sprites or groups; each sprite uses a content-root PNG."
	var enabled: bool = not document.read_only and not draft.is_empty()
	for control: Control in controls:
		if control is LineEdit: control.editable = enabled
		elif control is SpinBox: control.editable = enabled
		elif control is BaseButton: control.disabled = not enabled
	get_ok_button().disabled = not enabled
	selected = 0
	refresh_layers()
	if enabled: show_layer(0)
	popup_centered(size)

func refresh_layers() -> void:
	layers.clear()
	for node: Dictionary in draft.get("nodes", []): layers.add_item(node.path + " · " + node.type)
	if layers.item_count: layers.select(clampi(selected, 0, layers.item_count - 1))

func show_layer(index: int) -> void:
	if draft.is_empty(): return
	changing = true
	selected = index
	var node: Dictionary = draft.nodes[index]
	node_name_field.text = node.name
	parent_field.text = node.parent
	image_field.text = node.image
	image_field.editable = node.type == "Sprite2D"
	x_field.value = node.properties.get("position", Vector2()).x
	y_field.value = node.properties.get("position", Vector2()).y
	sx_field.value = node.properties.get("scale", Vector2.ONE).x
	sy_field.value = node.properties.get("scale", Vector2.ONE).y
	visible_field.button_pressed = node.properties.get("visible", true)
	fix_field.button_pressed = draft.nodes[0].properties.get("fix_offset", true)
	changing = false
	update_image()

func update_image() -> void:
	image_preview.texture = null
	var absolute: String = workspace.resolve_content_path(image_field.text)
	if not absolute.is_empty() and workspace.validate_png(absolute).is_empty():
		image_preview.texture = ImageTexture.create_from_image(Image.load_from_file(absolute))

func apply_layer() -> bool:
	if document.read_only or draft.is_empty(): return false
	var next: Dictionary = draft.duplicate(true)
	var node: Dictionary = next.nodes[selected]
	var old: String = node.path
	node.name = node_name_field.text.strip_edges()
	node.parent = "" if selected == 0 else parent_field.text.strip_edges()
	node.path = "." if selected == 0 else (node.name if node.parent == "." else node.parent.path_join(node.name))
	node.image = image_field.text.strip_edges() if node.type == "Sprite2D" else ""
	node.properties.merge({"position": Vector2(x_field.value, y_field.value), "scale": Vector2(sx_field.value, sy_field.value), "visible": visible_field.button_pressed}, true)
	if old != node.path:
		for child: Dictionary in next.nodes:
			if child == node: continue
			if child.parent == old: child.parent = node.path
			elif child.parent.begins_with(old + "/"): child.parent = node.path + child.parent.substr(old.length())
			if child.path.begins_with(old + "/"): child.path = node.path + child.path.substr(old.length())
	var checked := Document.inspect(Document.serialize(next), workspace)
	if not checked.supported:
		message.text = " ".join(checked.diagnostics)
		return false
	draft = checked.model
	refresh_layers()
	message.text = "Layer updated in this form. Save scene to write the native .tscn."
	return true

func change_layers(action: String) -> void:
	if draft.is_empty() or document.read_only: return
	if action == "Delete layer":
		if selected == 0: message.text = "The root cannot be deleted."; return
		var path: String = draft.nodes[selected].path
		for index: int in range(draft.nodes.size() - 1, -1, -1):
			if draft.nodes[index].path == path or draft.nodes[index].path.begins_with(path + "/"): draft.nodes.remove_at(index)
		selected = 0
	else:
		var parent: String = draft.nodes[selected].path if draft.nodes[selected].type != "Sprite2D" else draft.nodes[selected].parent
		var name_value := "Layer%d" % draft.nodes.size()
		var names: Array = []
		for node: Dictionary in draft.nodes: names.append(node.path)
		while (name_value if parent == "." else parent.path_join(name_value)) in names: name_value += "_2"
		draft.nodes.append({"name": name_value, "type": "Sprite2D" if action == "Add sprite" else "Node2D", "parent": parent, "path": name_value if parent == "." else parent.path_join(name_value), "image": "", "properties": {}})
		selected = draft.nodes.size() - 1
	refresh_layers()
	show_layer(selected)

func save_scene() -> void:
	if not apply_layer(): return
	var logical := path_field.text.strip_edges()
	var absolute: String = workspace.resolve_content_path(logical)
	if absolute.is_empty() or logical.get_extension() != "tscn" or logical.begins_with("res://addons/"):
		message.text = "Choose a .tscn path in the content folder, outside addons."
		return
	if document.update_model(draft) != OK:
		message.text = document.last_error
		return
	if not DirAccess.dir_exists_absolute(absolute.get_base_dir()):
		if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK: message.text = "Cannot create scene folder."; return
	if document.save_file(absolute) != OK:
		message.text = document.last_error + " Reopen changed files before saving."
		return
	saved.emit(logical)
	hide()
