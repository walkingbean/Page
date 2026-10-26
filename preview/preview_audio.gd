extends "res://addons/dialogic/Modules/Audio/subsystem_audio.gd"

## Keep native playback rules; cancel native volume tweens before freeing players.
var preview_tweens: Array[Tween] = []

func update_audio(channel_name := "", path := "", settings_overrides := {}) -> void:
	var before := get_tree().get_processed_tweens()
	super.update_audio(channel_name, path, settings_overrides)
	for tween: Tween in get_tree().get_processed_tweens():
		if tween not in before: preview_tweens.append(tween)
	preview_tweens = preview_tweens.filter(func(tween: Tween): return tween.is_valid())

func cancel_preview_tweens() -> void:
	for tween: Tween in preview_tweens:
		if tween.is_valid(): tween.kill()
	preview_tweens.clear()

func _clear_state(clear_flag := DialogicGameHandler.ClearFlags.FULL_CLEAR) -> void:
	cancel_preview_tweens()
	super._clear_state(clear_flag)
