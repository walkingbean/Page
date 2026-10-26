extends "res://addons/dialogic/Core/DialogicGameHandler.gd"

## The original event implementations remain unchanged. Preview checks happen
## before their deferred execution, using the current branch's runtime values.
var preview_guard: Callable


func handle_event(event_index: int) -> void:
	if preview_guard.is_valid() and current_timeline != null and event_index < current_timeline_events.size():
		if not preview_guard.call(current_timeline, event_index):
			return
	super.handle_event(event_index)


func get_full_state() -> DialogicSaveState:
	# Native Variables exposes user keys through _get. A key such as "name"
	# shadows Node.name during the upstream subsystem inventory. Isolate only
	# that metadata traversal, then put the exact runtime values in native state.
	var storage: Dictionary = VAR.var_storage
	VAR.var_storage = {}
	var state: DialogicSaveState = super.get_full_state()
	VAR.var_storage = storage
	if state.subsystems.has("VAR"):
		state.subsystems["VAR"]["var_storage"] = storage.duplicate(true)
	else:
		state.subsystems["VAR"] = {"var_storage":storage.duplicate(true)}
	return state


func load_full_state(state: DialogicSaveState) -> void:
	# Alpha 20 reads subsystem.name during restoration. Variables._get can
	# shadow that built-in property with a user variable named "name". Keep the
	# native state APIs and restoration order, using Node.get_name for metadata.
	var restore_guard := preview_guard
	await clear()
	if state == null or preview_guard != restore_guard: return
	for subsystem: DialogicSubsystem in get_children():
		var subsystem_name: StringName = subsystem.get_name()
		if state.subsystems.has(subsystem_name):
			subsystem.unpack_state(state.subsystems[subsystem_name])
	var scene: Node
	if has_subsystem("Styles"):
		Styles.load_state()
		scene = Styles.get_layout_node()
	if is_instance_valid(scene) and not scene.is_node_ready():
		await scene.ready
	else:
		await get_tree().process_frame
	if preview_guard != restore_guard: return
	for subsystem: DialogicSubsystem in get_children():
		if subsystem.get_name() != &"Styles": subsystem.load_state()
	if not state.timeline.is_empty():
		start_timeline(state.timeline, state.event_index)
	else:
		end_timeline.call_deferred(true)
