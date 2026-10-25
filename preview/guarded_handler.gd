extends "res://addons/dialogic/Core/DialogicGameHandler.gd"

## The original event implementations remain unchanged. Preview checks happen
## before their deferred execution, using the current branch's runtime values.
var preview_guard: Callable


func handle_event(event_index: int) -> void:
	if preview_guard.is_valid() and current_timeline != null and event_index < current_timeline_events.size():
		if not preview_guard.call(current_timeline, event_index):
			return
	super.handle_event(event_index)
