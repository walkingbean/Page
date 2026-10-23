extends Button

@export var accent_color := Color("#3b8bf2")


func _ready() -> void:
	_apply_accent_style(&"normal", Color(0.16, 0.16, 0.17, 1.0))
	_apply_accent_style(&"hover", Color(0.24, 0.24, 0.26, 1.0))
	_apply_accent_style(&"pressed", Color(0.09, 0.09, 0.10, 1.0))


func _apply_accent_style(state: StringName, background: Color) -> void:
	var inherited_style := get_theme_stylebox(state, &"Button") as StyleBoxFlat
	if inherited_style == null:
		return
	var style := inherited_style.duplicate() as StyleBoxFlat
	style.bg_color = background
	style.border_width_left = 3
	style.border_color = accent_color
	add_theme_stylebox_override(state, style)
