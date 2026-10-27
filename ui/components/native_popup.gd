extends RefCounted
## Fixed Godot 4.7.1 release templates require native PopupMenus here.
## Position them in desktop coordinates when their owning Window is embedded.

static func configure(picker: OptionButton) -> void:
	var popup := picker.get_popup()
	popup.force_native = true
	popup.visibility_changed.connect(_place.bind(picker, popup))

static func _place(picker: OptionButton, popup: PopupMenu) -> void:
	if not is_instance_valid(picker) or not is_instance_valid(popup) or not popup.visible or popup.is_embedded(): return
	var host: Window = picker.get_window()
	while host.is_embedded(): host = host.get_parent().get_window()
	var transform := picker.get_screen_transform()
	var anchor: Vector2 = Vector2(host.position) + transform * Vector2(0, picker.size.y)
	var available := DisplayServer.screen_get_usable_rect(host.current_screen)
	if anchor.y + popup.size.y > available.end.y:
		anchor.y -= transform.get_scale().y * picker.size.y + popup.size.y
	popup.position = Vector2i(clampi(roundi(anchor.x), available.position.x, maxi(available.position.x, available.end.x - popup.size.x)), clampi(roundi(anchor.y), available.position.y, maxi(available.position.y, available.end.y - popup.size.y)))
