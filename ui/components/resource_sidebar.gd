extends PanelContainer

signal new_requested
signal new_character_requested
signal open_requested
signal document_activated
signal resource_selected(path: String, kind: String)

const FOLDER_ICON: Texture2D = preload("res://asset/dialogic_ui/icons/folder.svg")
const TIMELINE_ICON: Texture2D = preload("res://asset/dialogic_ui/timeline.svg")
const CHARACTER_ICON: Texture2D = preload("res://asset/dialogic_ui/character.svg")
const Identity = preload("res://application/app_identity.gd")

@onready var resource_tree: Tree = %ResourceTree
@onready var filter_field: LineEdit = $Layout/ContentMargin/Content/Tools/Search

var _document_path := ""
var _document_title := ""
var _document_dirty := false
var _document_kind := "timeline"
var _root_path := ""
var _characters: Dictionary = {}
var _timelines: Array = []
var _media: Array = []


func _ready() -> void:
	$Layout/LogoMargin/Logo.texture = Identity.logo_texture()
	$Layout/ContentMargin/Content/Tools/NewTimeline.pressed.connect(func() -> void: new_requested.emit())
	$Layout/ContentMargin/Content/Tools/NewCharacter.pressed.connect(func() -> void: new_character_requested.emit())
	$Layout/ContentMargin/Content/Tools/NewCharacter.tooltip_text = "Create a Dialogic character"
	var open_button: Button = $Layout/ContentMargin/Content/Tools/Options
	open_button.icon = FOLDER_ICON
	open_button.tooltip_text = "Open Dialogic content (Ctrl+O)"
	open_button.pressed.connect(func() -> void: open_requested.emit())
	for path: String in ["Layout/ContentMargin/Content/Tools/ReferenceManager", "Layout/Footer/Collapse"]:
		var button := get_node(path) as Button
		button.disabled = true
		button.tooltip_text = "This operation is planned for a future version."
	var version_button: Button = $Layout/Footer/Version
	version_button.text = Identity.footer_text()
	version_button.clip_text = true
	version_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	version_button.disabled = true
	version_button.tooltip_text = Identity.window_title() + "\nDialogic 2.0 Alpha 20 compatible content editor"
	filter_field.placeholder_text = "Filter content"
	filter_field.text_changed.connect(func(_text: String) -> void: _rebuild_tree())
	resource_tree.item_activated.connect(_on_item_activated)
	resource_tree.set_drag_forwarding(_drag_resource, Callable(), Callable())
	_rebuild_tree()


func set_document(path: String, title: String, dirty: bool, kind: String = "timeline") -> void:
	if [_document_path, _document_title, _document_dirty, _document_kind] == [path, title, dirty, kind]: return
	_document_path = path
	_document_title = title
	_document_dirty = dirty
	_document_kind = kind
	_rebuild_tree()


func set_workspace(root_path: String, characters: Dictionary, timelines: Array) -> void:
	if _root_path == root_path and _characters == characters and _timelines == timelines: return
	_root_path = root_path
	_characters = characters.duplicate()
	_timelines = timelines.duplicate()
	_rebuild_tree()


func _rebuild_tree() -> void:
	resource_tree.clear()
	var root := resource_tree.create_item()
	for kind: String in ["timeline", "character"]:
		var group := resource_tree.create_item(root)
		group.set_text(0, "Timelines" if kind == "timeline" else "Characters")
		group.set_icon(0, FOLDER_ICON)
		group.set_selectable(0, false)
		group.collapsed = false
		if _document_kind == kind and not _document_title.is_empty():
			_add_item(group, _document_path, _document_title, kind, true)
		if kind == "timeline":
			for path: String in _timelines:
				if path != _document_path or kind != _document_kind:
					_add_item(group, path, path.get_file(), kind)
		else:
			var identifiers: Array = _characters.keys()
			identifiers.sort()
			for identifier: String in identifiers:
				var entry: Dictionary = _characters[identifier]
				var path: String = str(entry.get("path", ""))
				if path != _document_path or kind != _document_kind:
					_add_item(group, path, identifier + ".dch", kind, false, "\n".join(entry.get("diagnostics", [])))

	var media_group := resource_tree.create_item(root)
	media_group.set_text(0, "Media"); media_group.set_selectable(0, false)
	for path: String in _media: _add_item(media_group, path, path.get_file(), "media")

func set_media(paths: Array) -> void:
	if _media == paths: return
	_media = paths.duplicate(); _rebuild_tree()

func _drag_resource(position: Vector2) -> Variant:
	var item := resource_tree.get_item_at_position(position)
	if item == null: return null
	var data: Variant = item.get_metadata(0)
	if not data is Dictionary or str(data.get("path", "")).is_empty(): return null
	var label := Label.new(); label.text = str(data.path).get_file(); resource_tree.set_drag_preview(label)
	return {"files": PackedStringArray([str(data.path)])}

func _add_item(group: TreeItem, path: String, title: String, kind: String, current: bool = false, diagnostics: String = "") -> void:
	if not filter_field.text.is_empty() and not title.to_lower().contains(filter_field.text.to_lower()):
		return
	var item := resource_tree.create_item(group)
	item.set_text(0, title + (" *" if current and _document_dirty else ""))
	item.set_icon(0, TIMELINE_ICON if kind == "timeline" else (CHARACTER_ICON if kind == "character" else FOLDER_ICON))
	item.set_tooltip_text(0, (path if not path.is_empty() else "Unsaved document") + ("\n" + diagnostics if not diagnostics.is_empty() else ""))
	item.set_metadata(0, {"path": path, "kind": kind, "current": current})
	if not diagnostics.is_empty():
		item.set_custom_color(0, Color(0.93, 0.72, 0.43))
	if current:
		item.select(0)


func _on_item_activated() -> void:
	var item := resource_tree.get_selected()
	if item == null:
		return
	var metadata: Variant = item.get_metadata(0)
	if not metadata is Dictionary or metadata.get("kind") == "media":
		return
	if metadata.get("current", false):
		document_activated.emit()
	else:
		resource_selected.emit(metadata.get("path", ""), metadata.get("kind", "timeline"))
