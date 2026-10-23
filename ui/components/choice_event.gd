extends MarginContainer

signal selected(choice_event: Control)
signal branch_visibility_changed(expanded: bool)

const EVENT_NORMAL: StyleBox = preload("res://asset/dialogic_ui/theme/event_normal.tres")
const EVENT_SELECTED: StyleBox = preload("res://asset/dialogic_ui/theme/event_selected.tres")
const FOLD_RIGHT: Texture2D = preload("res://asset/dialogic_ui/icons/fold-right.svg")
const FOLD_DOWN: Texture2D = preload("res://asset/dialogic_ui/icons/fold-down.svg")
const TREE_EXPANDED: Texture2D = preload("res://asset/dialogic_ui/icons/tree-expanded.svg")
const TREE_COLLAPSED: Texture2D = preload("res://asset/dialogic_ui/icons/tree-collapsed.svg")

@export var choice_text := ""
@export_range(0, 8, 1) var indent_level := 1
@export var settings_expanded := false
@export var children_expanded := true
@export var branch_target_path: NodePath

@onready var event_panel: PanelContainer = %EventPanel
@onready var header: HBoxContainer = %Header
@onready var choice_input: LineEdit = %ChoiceText
@onready var settings_toggle: Button = %SettingsToggle
@onready var children_toggle: Button = %ChildrenToggle
@onready var settings_body: PanelContainer = %SettingsBody


func _ready() -> void:
	add_theme_constant_override(&"margin_left", indent_level * 22)
	choice_input.text = choice_text
	header.gui_input.connect(_on_header_gui_input)
	choice_input.focus_entered.connect(_request_selection)
	choice_input.text_changed.connect(_on_choice_text_changed)
	settings_toggle.pressed.connect(_on_settings_toggled)
	children_toggle.pressed.connect(_on_children_toggled)
	_apply_settings_state()
	_apply_children_state()
	set_selected(false)


func set_selected(is_selected: bool) -> void:
	event_panel.add_theme_stylebox_override(
		&"panel", EVENT_SELECTED if is_selected else EVENT_NORMAL
	)


func _request_selection() -> void:
	selected.emit(self)


func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_request_selection()
			grab_focus()


func _on_choice_text_changed(new_text: String) -> void:
	choice_text = new_text


func _on_settings_toggled() -> void:
	settings_expanded = not settings_expanded
	_apply_settings_state()
	_request_selection()


func _apply_settings_state() -> void:
	settings_body.visible = settings_expanded
	settings_toggle.icon = FOLD_DOWN if settings_expanded else FOLD_RIGHT
	settings_toggle.tooltip_text = "Hide Settings" if settings_expanded else "Show Settings"


func _on_children_toggled() -> void:
	children_expanded = not children_expanded
	_apply_children_state()
	_request_selection()


func _apply_children_state() -> void:
	var target: CanvasItem = null
	if not branch_target_path.is_empty():
		target = get_node_or_null(branch_target_path) as CanvasItem
	if target != null:
		target.visible = children_expanded
	children_toggle.visible = target != null
	children_toggle.icon = TREE_EXPANDED if children_expanded else TREE_COLLAPSED
	children_toggle.tooltip_text = (
		"Collapse Contained Events" if children_expanded else "Expand Contained Events"
	)
	branch_visibility_changed.emit(children_expanded)
