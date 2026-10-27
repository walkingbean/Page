extends DialogicAnimation

func animate() -> void:
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 0.5, time / 2.0)
	tween.tween_property(node, "modulate:a", 1.0, time / 2.0)
	await tween.finished
	finished_once.emit()

func _get_named_variations() -> Dictionary:
	return {"DemoExtension pulse":{"type":AnimationType.ACTION}}
