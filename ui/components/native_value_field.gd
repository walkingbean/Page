extends HBoxContainer

signal value_changed
const Native = preload("res://application/native_resource.gd")
var value_type := TYPE_NIL
var control: Control
var vector_y: SpinBox
var label: Label
var info: Dictionary = {}
var initial: Variant
var last_error := ""
var edited := false

func setup(caption: String, value: Variant, metadata: Dictionary = {}) -> void:
	info = metadata
	value_type = metadata.get("type", typeof(value))
	initial = value
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label = Label.new(); label.text = caption; label.custom_minimum_size.x = 220
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	match value_type:
		TYPE_BOOL:
			var box := CheckBox.new(); box.button_pressed = value
			box.toggled.connect(func(_v: bool): value_changed.emit()); control = box
		TYPE_COLOR:
			var picker := ColorPickerButton.new(); picker.color = value; picker.custom_minimum_size = Vector2(100, 30)
			picker.color_changed.connect(func(_v: Color): value_changed.emit()); control = picker
		TYPE_INT, TYPE_FLOAT:
			if metadata.get("hint") == PROPERTY_HINT_ENUM:
				var options := OptionButton.new()
				for option: Dictionary in Native.enum_items(str(metadata.get("hint_string", ""))):
					options.add_item(option.label)
					var index := options.item_count - 1
					options.set_item_metadata(index, option.value)
					if option.value == value: options.select(index)
				options.item_selected.connect(func(_i: int): value_changed.emit()); control = options
			else:
				var number := SpinBox.new(); number.allow_greater = true; number.allow_lesser = true
				number.step = 1.0 if value_type == TYPE_INT else 0.001
				if metadata.get("hint") == PROPERTY_HINT_RANGE:
					var parts: PackedStringArray = str(metadata.get("hint_string", "")).split(",")
					if parts.size() >= 2:
						number.min_value = float(parts[0]); number.max_value = float(parts[1])
						number.allow_greater = "or_greater" in parts; number.allow_lesser = "or_lesser" in parts
						if parts.size() > 2 and parts[2].is_valid_float(): number.step = float(parts[2])
				number.value = value; number.value_changed.connect(func(_v: float): value_changed.emit()); control = number
		TYPE_VECTOR2:
			var number := SpinBox.new(); number.allow_greater = true; number.allow_lesser = true; number.step = 0.01; number.value = value.x
			vector_y = SpinBox.new(); vector_y.allow_greater = true; vector_y.allow_lesser = true; vector_y.step = 0.01; vector_y.value = value.y
			number.value_changed.connect(func(_v: float): value_changed.emit()); vector_y.value_changed.connect(func(_v: float): value_changed.emit()); control = number
		_:
			var field := LineEdit.new(); field.text = str(value) if value_type == TYPE_STRING else var_to_str(value)
			field.text_changed.connect(func(_v: String): value_changed.emit()); control = field
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = 130
	control.name = "Value"
	add_child(control)
	if vector_y != null: add_child(vector_y)
	value_changed.connect(func(): edited = true)

func value() -> Variant:
	last_error = ""
	# A SpinBox may display fewer decimal places than the native file stores.
	# Keep the original Variant until the user actually changes this field.
	if not edited: return initial
	if control is CheckBox: return control.button_pressed
	if control is ColorPickerButton: return control.color
	if control is OptionButton: return control.get_item_metadata(control.selected)
	if vector_y != null: return Vector2(control.value, vector_y.value)
	if control is SpinBox: return int(control.value) if value_type == TYPE_INT else control.value
	if value_type == TYPE_STRING: return control.text
	var parsed := Native.decode(control.text)
	if parsed.has("error"): last_error = parsed.error; return null
	return parsed.value

func is_changed() -> bool:
	if not edited: return false
	var next: Variant = value()
	return not last_error.is_empty() or next != initial
