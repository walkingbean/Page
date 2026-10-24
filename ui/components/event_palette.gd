extends PanelContainer

signal variable_requested
signal text_requested
signal comment_requested
signal character_event_requested(source: String)

const BUTTON_SCENE: PackedScene = preload("res://ui/components/event_palette_button.tscn")
var variable_button: Button
var text_button: Button
var comment_button: Button
var character_button: Button
var character_text_button: Button
var leave_button: Button
var character_selector: OptionButton
var position_selector: OptionButton
var _editable := false


func _ready() -> void:
	var sections: VBoxContainer = $Scroll/Margin/Sections
	for child in sections.get_children():
		if child is Button:
			child.disabled = true
			child.tooltip_text = "%s editing is planned for a future version." % child.text
	text_button = BUTTON_SCENE.instantiate() as Button
	text_button.name = "Text"
	text_button.text = "Text"
	text_button.icon = preload("res://asset/dialogic_ui/timeline.svg")
	text_button.set(&"accent_color", Color(0.35, 0.65, 0.91))
	text_button.tooltip_text = "Insert a narration line at the caret."
	text_button.pressed.connect(func() -> void: text_requested.emit())
	sections.add_child(text_button)
	sections.move_child(text_button, 1)
	comment_button = BUTTON_SCENE.instantiate() as Button
	comment_button.name = "Comment"
	comment_button.text = "Comment"
	comment_button.set(&"accent_color", Color(0.58, 0.64, 0.58))
	comment_button.tooltip_text = "Insert a # comment at the caret."
	comment_button.pressed.connect(func() -> void: comment_requested.emit())
	sections.add_child(comment_button)
	sections.move_child(comment_button, 2)
	character_button = sections.get_node("Character")
	character_button.tooltip_text = "Insert join for the selected character and position."
	character_button.pressed.connect(func(): _insert_character("join"))
	var controls := VBoxContainer.new()
	controls.name = "CharacterControls"
	sections.add_child(controls)
	sections.move_child(controls, character_button.get_index() + 1)
	character_selector = OptionButton.new()
	character_selector.name = "CharacterSelector"
	character_selector.fit_to_longest_item = false
	character_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	character_selector.tooltip_text = "Character identifier from the content folder"
	controls.add_child(character_selector)
	position_selector = OptionButton.new()
	position_selector.name = "JoinPosition"
	for position: String in ["left", "center", "right"]:
		position_selector.add_item(position)
	position_selector.select(1)
	position_selector.tooltip_text = "Position for the next join event"
	controls.add_child(position_selector)
	var actions := HBoxContainer.new()
	controls.add_child(actions)
	character_text_button = Button.new()
	character_text_button.text = "Dialogue"
	character_text_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_text_button.tooltip_text = "Insert dialogue spoken by the selected character"
	character_text_button.pressed.connect(func(): _insert_character("text"))
	actions.add_child(character_text_button)
	leave_button = Button.new()
	leave_button.text = "Leave"
	leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_button.pressed.connect(func(): _insert_character("leave"))
	actions.add_child(leave_button)
	variable_button = BUTTON_SCENE.instantiate() as Button
	variable_button.name = "Variable"
	variable_button.text = "Variable"
	variable_button.set(&"accent_color", Color(0.55, 0.7, 0.4))
	sections.add_child(variable_button)
	sections.move_child(variable_button, sections.get_node("LogicHeader").get_index() + 1)
	variable_button.tooltip_text = "Insert or edit the literal assignment at the caret"
	variable_button.pressed.connect(func(): variable_requested.emit())
	var note := Label.new()
	note.text = "Text, # comments and basic\ncharacter join / leave.\nChoose a content folder\nto use saved characters."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.55, 0.57, 0.63))
	sections.add_child(note)
	set_editable(false)


func set_characters(identifiers: Array[String]) -> void:
	var previous := character_selector.get_item_text(character_selector.selected) if character_selector.selected >= 0 else ""
	character_selector.clear()
	for identifier: String in identifiers:
		character_selector.add_item(identifier)
		if identifier == previous:
			character_selector.select(character_selector.item_count - 1)
	if identifiers.is_empty():
		character_selector.add_item("No supported characters")
		character_selector.set_item_metadata(0, false)
	else:
		for index: int in character_selector.item_count:
			character_selector.set_item_metadata(index, true)
	set_editable(_editable)


func set_editable(enabled: bool) -> void:
	_editable = enabled
	if is_instance_valid(variable_button):
		variable_button.disabled = not enabled
	if is_instance_valid(text_button):
		text_button.disabled = not enabled
	if is_instance_valid(comment_button):
		comment_button.disabled = not enabled
	if not is_instance_valid(character_selector):
		return
	var available: bool = enabled and character_selector.item_count > 0 and character_selector.get_item_metadata(0) == true
	character_button.disabled = not available
	character_selector.disabled = not available
	position_selector.disabled = not available
	character_text_button.disabled = not available
	leave_button.disabled = not available


func _insert_character(kind: String) -> void:
	if not _editable or character_selector.disabled or character_selector.selected < 0:
		return
	var identifier := '"' + character_selector.get_item_text(character_selector.selected) + '"'
	match kind:
		"join": character_event_requested.emit("join %s %s\n" % [identifier, position_selector.get_item_text(position_selector.selected)])
		"text": character_event_requested.emit("%s: New dialogue.\n" % identifier)
		"leave": character_event_requested.emit("leave %s\n" % identifier)
