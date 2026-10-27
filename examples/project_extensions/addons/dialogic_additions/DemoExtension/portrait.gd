extends DialogicPortrait

func _ready() -> void:
	var shape := Polygon2D.new()
	shape.name = "Shape"
	shape.polygon = PackedVector2Array([Vector2(-60, 0), Vector2(60, 0), Vector2(0, -180)])
	shape.color = Color(0.4, 0.7, 1.0)
	add_child(shape)

func _get_covered_rect() -> Rect2:
	return Rect2(-60, -180, 120, 180)

func _update_portrait(_who: DialogicCharacter, _which: String) -> void:
	print("CUSTOM_PORTRAIT_UPDATED ", _which)

func _set_mirror(mirrored: bool) -> void:
	$Shape.scale.x = -1.0 if mirrored else 1.0

func _set_extra_data(data: String) -> void:
	print("CUSTOM_PORTRAIT_EXTRA ", data)
