@tool
extends DialogicIndexer

func _get_events() -> Array:
	return [this_folder.path_join("event.gd")]

func _get_subsystems() -> Array[Dictionary]:
	return [{"name":"DemoExtension", "script":this_folder.path_join("subsystem.gd")}]

func _get_editors() -> Array[String]:
	return [this_folder.path_join("editor.tscn")]

func _get_special_resources() -> Dictionary:
	return {"Animation":list_animations("animations")}

func _get_portrait_scene_presets() -> Array[Dictionary]:
	return [{"name":"DemoExtension portrait", "path":this_folder.path_join("portrait.tscn")}]

func _get_layout_parts() -> Array[Dictionary]:
	return [{"name":"DemoExtension layer", "type":"Layer", "path":this_folder.path_join("layout.tscn"), "description":"Native custom overlay"}]
