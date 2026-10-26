extends RefCounted

const Native = preload("res://application/native_resource.gd")
const NUMERIC_EFFECTS := ["speed", "lspeed", "pause", "aa", "ns"]

static func inspect(text: String, workspace: RefCounted = null, character: DialogicCharacter = null, check_resources := false, active_portrait: String = "") -> Dictionary:
	for match_value: RegExMatch in RegEx.create_from_string('(?<!\\\\)\\[(speed|lspeed|pause|aa|ns)(?:=([^\\]]*))?\\]').search_all(text):
		var key := match_value.get_string(1)
		var argument := match_value.get_string(2)
		if argument.is_empty(): continue
		if key in ["lspeed", "pause"]: argument = argument.trim_suffix("!")
		if key == "aa": argument = argument.trim_suffix("?")
		if not argument.is_valid_float() or not is_finite(argument.to_float()) or argument.to_float() < 0:
			return {"offset": match_value.get_start(), "error": key + " requires a finite nonnegative value."}
	if not check_resources: return {}
	var selected_portrait := active_portrait
	for effect: RegExMatch in RegEx.create_from_string('(?<!\\\\)\\[(portrait|extra_data)=([^\\]]*)\\]').search_all(text):
		if character == null: return {"offset": effect.get_start(), "error": "Portrait text effects require a workspace speaker."}
		if effect.get_string(1) == "portrait":
			if not character.portraits.has(effect.get_string(2)): return {"offset": effect.get_start(), "error": "The text effect references a missing portrait."}
			selected_portrait = effect.get_string(2)
		else:
			# An edit-time branch may not determine the active portrait yet.
			# Validate a possible layered target here, then check the actual
			# portrait immediately before native execution. Inline portrait tags
			# update that target in their original text order.
			var candidates: Array = [selected_portrait] if not selected_portrait.is_empty() else character.portraits.keys()
			var valid_target := false
			var problem := "extra_data text effects require a validated layered portrait as their active target."
			var layers = load("res://application/layered_portrait_document.gd")
			for name: String in candidates:
				var portrait: Dictionary = character.portraits.get(name, {})
				var checked: Dictionary = layers.inspect_path(portrait.get("scene", ""), workspace)
				if not checked.supported: continue
				var issue: String = layers.commands_error(effect.get_string(2), checked.model)
				if issue.is_empty(): valid_target = true; break
				problem = issue
			if not valid_target: return {"offset": effect.get_start(), "error": problem}
	for asset: Dictionary in asset_references(text):
		var checked := Native.inspect_path(asset.path, workspace, [], {})
		if checked.has("error"): return {"offset": asset.start, "error": checked.error}
		if asset.kind == "font" and not checked.resource is Font: return {"offset": asset.start, "error": "The font tag requires a native Font resource."}
		if asset.kind == "image" and not checked.resource is Texture2D: return {"offset": asset.start, "error": "The image tag requires a PNG/Texture2D resource."}
	return {}

static func asset_references(text: String) -> Array[Dictionary]:
	var refs: Array[Dictionary] = []
	for found: RegExMatch in RegEx.create_from_string('\\[img(?:=[^\\]]*| [^\\]]*)?\\]([^\\[]+)\\[/img\\]').search_all(text):
		refs.append({"kind": "image", "path": found.get_string(1), "start": found.get_start(1), "end": found.get_end(1)})
	for found: RegExMatch in RegEx.create_from_string('\\[font=([^\\]]+)\\]').search_all(text):
		refs.append({"kind": "font", "path": found.get_string(1).trim_prefix('"').trim_suffix('"'), "start": found.get_start(1), "end": found.get_end(1)})
	for tag: RegExMatch in RegEx.create_from_string('\\[font ([^\\]]+)\\]').search_all(text):
		for found: RegExMatch in RegEx.create_from_string('(?:^| )(?:n|b|i|bi|mono)=("[^"]+"|[^ ]+)').search_all(tag.get_string(1)):
			refs.append({"kind": "font", "path": found.get_string(1).trim_prefix('"').trim_suffix('"'), "start": tag.get_start(1) + found.get_start(1), "end": tag.get_start(1) + found.get_end(1)})
	refs.sort_custom(func(a: Dictionary, b: Dictionary): return a.start < b.start)
	return refs

static func remap(text: String, workspace: RefCounted, resources: Array[Resource], prefix: String, cache: Dictionary) -> Dictionary:
	var refs := asset_references(text)
	refs.reverse()
	for ref: Dictionary in refs:
		var key: String = ref.path
		if not cache.has(key):
			var loaded := Native.inspect_path(key, workspace, [], {})
			if loaded.has("error"): return loaded
			var virtual := prefix.path_join("asset_%d.%s" % [resources.size(), key.get_extension()])
			loaded.resource.take_over_path(virtual)
			resources.append(loaded.resource)
			cache[key] = virtual
		text = text.left(ref.start) + cache[key] + text.substr(ref.end)
	return {"text": text}
