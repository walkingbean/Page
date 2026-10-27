@tool
extends DialogicEvent

func _init() -> void:
	event_name = "DemoExtension"
	event_category = "Custom"

func get_shortcode() -> String:
	return "demoextension"

func _execute() -> void:
	dialogic.get_subsystem("DemoExtension").count += 1
	print("CUSTOM_EVENT_EXECUTED")
	finish()
