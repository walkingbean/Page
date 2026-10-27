extends Node

func _ready() -> void:
	var timeline := DialogicTimeline.new()
	timeline.from_text(FileAccess.get_file_as_string("res://story.dtl"))
	timeline.resource_path = "res://story.dtl"
	Dialogic.start(timeline)
