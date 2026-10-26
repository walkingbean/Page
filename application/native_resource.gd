extends RefCounted

## Inert Godot text-resource reader. Only bundled Dialogic classes/scenes and
## data resources are instantiated; target scripts are never loaded.
const Data = preload("res://application/variable_document.gd")
const STYLE_SCRIPT := "res://addons/dialogic/Resources/dialogic_style.gd"
const LAYER_SCRIPT := "res://addons/dialogic/Resources/dialogic_style_layer.gd"
const PARTS := "res://addons/dialogic/Modules/DefaultLayoutParts/"
const BUILTINS := ["FontFile", "FontVariation", "StyleBoxFlat", "StyleBoxTexture", "StyleBoxEmpty", "StyleBoxLine", "Theme", "Gradient", "GradientTexture1D", "GradientTexture2D"]
const TOKENS := ["true", "false", "null", "inf", "nan", "e", "E", "Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Rect2", "Rect2i", "Color", "Transform2D", "NodePath", "PackedStringArray", "PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array", "PackedVector2Array", "PackedVector3Array", "PackedVector4Array", "PackedColorArray", "Array", "String", "StringName", "int", "float", "bool"]
const REF_KEY := "__page_native_reference__"
static var scene_schemas: Dictionary = {}
static var scene_kinds: Dictionary = {}

static func failure(message: String) -> Dictionary:
	return {"error": message, "supported": false, "diagnostics": [message]}

static func decode(raw: String) -> Dictionary:
	# Keep unchanged spans intact. Appending every numeric character repeatedly
	# copies the growing String and makes ordinary embedded font data quadratic.
	var parts := PackedStringArray()
	var literal_start := 0
	var i := 0
	while i < raw.length():
		var ch := raw[i]
		if ch == '"':
			i += 1
			while i < raw.length():
				if raw[i] == "\\": i += 2
				elif raw[i] == '"': i += 1; break
				else: i += 1
			continue
		if ch == ";":
			parts.append(raw.substr(literal_start, i - literal_start))
			i = Data._after_line(raw, i)
			parts.append("\n")
			literal_start = i
			continue
		var code := ch.unicode_at(0)
		if ch == "_" or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			var start := i
			i += 1
			while i < raw.length() and (raw[i] == "_" or raw[i].is_valid_identifier() or raw[i].is_valid_int()): i += 1
			var word := raw.substr(start, i - start)
			if word in ["ExtResource", "SubResource"]:
				var found := RegEx.create_from_string('^\\s*\\(\\s*"([^"\\r\\n]+)"\\s*\\)').search(raw.substr(i))
				if found == null: return failure("Invalid native resource reference.")
				parts.append(raw.substr(literal_start, start - literal_start))
				parts.append(var_to_str({REF_KEY: word, "id": found.get_string(1)}))
				i += found.get_end()
				literal_start = i
			elif word == "Array" and i < raw.length() and raw[i] == "[":
				# Typed arrays retain values; the owning property re-applies its type.
				var end := raw.find("]", i)
				if end < 0: return failure("Unclosed typed array.")
				var type_name := raw.substr(i + 1, end - i - 1)
				if not type_name in TOKENS + BUILTINS + ["Font", "Texture2D", "Resource", "DialogicStyleLayer"] and not RegEx.create_from_string('^ExtResource\\("[^"\\n]+"\\)$').search(type_name): return failure("Unsupported typed array element class.")
				i = end + 1
				while i < raw.length() and raw[i] in [" ", "\t"]: i += 1
				if i >= raw.length() or raw[i] != "(": return failure("Invalid typed array.")
				# Locate this wrapper's closing parenthesis, respecting nested values.
				var depth := 1
				var j := i + 1
				var quoted := false
				while j < raw.length() and depth > 0:
					if quoted:
						if raw[j] == "\\": j += 1
						elif raw[j] == '"': quoted = false
					elif raw[j] == '"': quoted = true
					elif raw[j] == "(": depth += 1
					elif raw[j] == ")": depth -= 1
					j += 1
				if depth != 0: return failure("Unclosed typed array wrapper.")
				# Validate only this wrapper. A typed array can be nested inside a
				# dictionary/array whose later closing delimiters belong to its parent.
				var span := Data._value_span(raw.substr(i, j - i), 0)
				if span.has("error"): return span
				var nested := decode(raw.substr(i + 1, j - i - 2))
				if nested.has("error"): return nested
				parts.append(raw.substr(literal_start, start - literal_start))
				parts.append(var_to_str(nested.value))
				i = j
				literal_start = i
			elif word in TOKENS: pass
			else: return failure("Unsupported native value constructor: " + word)
		else:
			i += 1
	parts.append(raw.substr(literal_start))
	var out := "".join(parts)
	var checked := Data._value_span(out, 0)
	if checked.has("error"): return checked
	return Data._parse_value(out)

static func encode(value: Variant) -> String:
	if value is Dictionary:
		if value.has(REF_KEY): return '%s(%s)' % [value[REF_KEY], var_to_str(value.id)]
		var pairs := PackedStringArray()
		for key: Variant in value: pairs.append(encode(key) + ": " + encode(value[key]))
		return "{\n" + ",\n".join(pairs) + "\n}"
	if value is Array:
		var items := PackedStringArray()
		for item: Variant in value: items.append(encode(item))
		return "[" + ", ".join(items) + "]"
	return var_to_str(value)

static func make_reference(kind: String, id: String) -> Dictionary:
	return {REF_KEY: kind, "id": id}

static func scan(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > 4 * 1024 * 1024 or text.to_utf8_buffer().has(0): return failure("Native resource must be at most 4 MiB without NUL.")
	var sections: Array[Dictionary] = []
	var i := 0
	text = text.trim_prefix(String.chr(0xFEFF))
	while i < text.length():
		if text[i] in [" ", "\t", "\n", "\r"]: i += 1; continue
		if text[i] == ";": i = Data._after_line(text, i); continue
		if text[i] == "[":
			var end := text.find("\n", i)
			if end < 0: end = text.length()
			var line := text.substr(i, end - i).strip_edges()
			var header := RegEx.create_from_string('^\\[(gd_resource|ext_resource|sub_resource|resource)(.*?)\\]$').search(line)
			if header == null: return failure("Invalid native resource section.")
			var attrs := {}
			var rest := header.get_string(2)
			for found: RegExMatch in RegEx.create_from_string('([a-z_]+)=("(?:[^"\\\\]|\\\\.)*"|[0-9]+)').search_all(rest):
				if attrs.has(found.get_string(1)): return failure("Duplicate resource attribute.")
				attrs[found.get_string(1)] = str_to_var(found.get_string(2))
				rest = rest.replace(found.get_string(), "")
			if not rest.strip_edges().is_empty(): return failure("Unknown resource header data remains read-only.")
			var kind := header.get_string(1)
			var allowed: Array = {"gd_resource":["type", "script_class", "load_steps", "format", "uid"], "ext_resource":["type", "path", "id", "uid"], "sub_resource":["type", "id"], "resource":[]}[kind]
			for key: String in attrs:
				if not key in allowed: return failure("Unknown native header property: " + key)
			sections.append({"kind": kind, "attrs": attrs, "props": {}})
			i = end + 1
			continue
		if sections.is_empty() or not sections[-1].kind in ["sub_resource", "resource"]: return failure("Resource property is outside its section.")
		var eq := text.find("=", i)
		var nl := text.find("\n", i)
		if eq < 0 or (nl >= 0 and nl < eq): return failure("Missing resource property assignment.")
		var key := text.substr(i, eq - i).strip_edges()
		if key.is_empty() or sections[-1].props.has(key): return failure("Empty or duplicate native property.")
		i = eq + 1
		while i < text.length() and text[i] in [" ", "\t", "\r", "\n"]: i += 1
		var span := Data._value_span(text, i)
		if span.has("error"): return span
		var decoded := decode(text.substr(i, span.end - i))
		if decoded.has("error"): return decoded
		sections[-1].props[key] = decoded.value
		i = span.next
	if sections.is_empty() or sections[0].kind != "gd_resource" or sections[0].attrs.get("format") != 3: return failure("Expected Godot format 3 text resource.")
	var roots := 0
	var ids := {}
	for section: Dictionary in sections:
		if section.kind == "resource": roots += 1
		if section.kind in ["ext_resource", "sub_resource"]:
			var id: String = str(section.attrs.get("id", ""))
			var identity: String = section.kind + id
			if id.is_empty() or ids.has(identity): return failure("Missing or duplicate resource id.")
			ids[identity] = true
	if roots != 1: return failure("Expected exactly one root resource.")
	return {"model": {"sections": sections}}

static func serialize(model: Dictionary) -> String:
	var text := ""
	model.sections[0].attrs["load_steps"] = model.sections.size() - 1
	for section: Dictionary in model.sections:
		text += "[" + section.kind
		for key: String in section.attrs: text += " " + key + "=" + var_to_str(section.attrs[key])
		text += "]\n"
		for key: String in section.props:
			var value := encode(section.props[key])
			if key == "layer_list": value = "Array[String](" + value + ")"
			text += key + " = " + value + "\n"
		text += "\n"
	return text

static func inspect_path(logical: String, workspace: RefCounted, chain: Array[String] = [], cache: Dictionary = {}) -> Dictionary:
	if chain.size() >= 128 or logical in chain: return failure("Native resource dependency cycle or depth exceeds 128: " + logical)
	if cache.has(logical): return cache[logical]
	var absolute: String = logical if is_bundled(logical) else (workspace.resolve_content_path(logical) if workspace != null else "")
	if absolute.is_empty() or not FileAccess.file_exists(absolute): return failure("Missing resource or path outside the content folder: " + logical)
	var bytes := FileAccess.get_file_as_bytes(absolute)
	if bytes.size() > 32 * 1024 * 1024: return failure("Asset exceeds 32 MiB: " + logical)
	var resource: Resource
	match logical.get_extension().to_lower():
		"png":
			var issue: String = workspace.validate_png(absolute) if workspace != null and not is_bundled(logical) else ""
			if not issue.is_empty(): return failure(issue)
			var image := Image.load_from_file(absolute)
			if image == null or image.is_empty(): return failure("Cannot decode image: " + logical)
			resource = ImageTexture.create_from_image(image)
		"ttf", "otf":
			var font := FontFile.new()
			if font.load_dynamic_font(absolute) != OK: return failure("Cannot decode font: " + logical)
			resource = font
		"tres":
			if bytes.get_string_from_utf8().to_utf8_buffer() != bytes: return failure("Resource must be valid UTF-8: " + logical)
			var parsed := scan(bytes.get_string_from_utf8())
			if parsed.has("error"): return parsed
			var next_chain := chain.duplicate(); next_chain.append(logical)
			var built := build(parsed.model, workspace, next_chain, cache)
			if built.has("error"): return built
			built["model"] = parsed.model
			built["sha256"] = Data._digest(bytes)
			cache[logical] = built
			return built
		_: return failure("Only native .tres, TTF/OTF and PNG content assets are supported.")
	var result := {"resource": resource, "sha256": Data._digest(bytes)}
	cache[logical] = result
	return result

static func is_bundled(path: String) -> bool:
	return path.begins_with(PARTS) and not path.contains("..") and FileAccess.file_exists(path)

static func build(model: Dictionary, workspace: RefCounted, chain: Array[String] = [], cache: Dictionary = {}) -> Dictionary:
	var script_reference: Variant
	for section: Dictionary in model.sections:
		if section.kind == "resource": script_reference = section.props.get("script")
	var is_style := false
	if script_reference is Dictionary and script_reference.get(REF_KEY) == "ExtResource":
		for section: Dictionary in model.sections:
			if section.kind == "ext_resource" and str(section.attrs.id) == str(script_reference.id): is_style = section.attrs.get("path") == STYLE_SCRIPT
	var previous_depth: int = cache.get("__active_style_depth__", 0)
	if is_style and previous_depth >= 64: return failure("Style inheritance exceeds 64 styles including the root.")
	cache["__active_style_depth__"] = previous_depth + (1 if is_style else 0)
	var result := _build_model(model, workspace, chain, cache)
	cache["__active_style_depth__"] = previous_depth
	return result

static func _build_model(model: Dictionary, workspace: RefCounted, chain: Array[String], cache: Dictionary) -> Dictionary:
	var sections: Dictionary = {}
	for section: Dictionary in model.sections:
		if section.kind == "ext_resource": sections["ExtResource:" + str(section.attrs.id)] = section
		elif section.kind == "sub_resource": sections["SubResource:" + str(section.attrs.id)] = section
		elif section.kind == "resource": sections["root"] = section
	var made := {}
	# Validate unused dependencies as well; hidden executable resources stay protected.
	for id: String in sections:
		var checked := _build_section(id, model, sections, made, [], workspace, chain, cache)
		if checked.has("error"): return checked
	return {"resource": made["root"]}

static func _build_section(id: String, model: Dictionary, sections: Dictionary, made: Dictionary, active: Array[String], workspace: RefCounted, chain: Array[String], cache: Dictionary) -> Dictionary:
	if made.has(id): return {"resource": made[id]}
	if id in active or active.size() >= 64 or not sections.has(id): return failure("Invalid or cyclic native resource reference: " + id)
	var next := active.duplicate(); next.append(id)
	var section: Dictionary = sections[id]
	if section.kind == "ext_resource":
		var path: String = section.attrs.get("path", "")
		var type: String = section.attrs.get("type", "")
		if type == "Script":
			if not path in [STYLE_SCRIPT, LAYER_SCRIPT]: return failure("Custom scripts require the extension stage and are not executed.")
			made[id] = load(path)
		elif type == "PackedScene":
			if not is_bundled(path) or path.get_extension() != "tscn": return failure("Custom layout scenes remain read-only until the extension stage.")
			made[id] = load(path)
		else:
			if not type in BUILTINS + ["Resource", "Font", "Texture2D", "StyleBox"]: return failure("Unsupported external resource type: " + type)
			var resolved := inspect_path(path, workspace, chain, cache)
			if resolved.has("error"): return resolved
			made[id] = resolved.resource
		return {"resource": made[id]}
	var type: String = model.sections[0].attrs.get("type", "") if id == "root" else section.attrs.get("type", "")
	var resource: Resource
	if type == "Resource":
		var script_value: Variant = section.props.get("script")
		if not script_value is Dictionary or not script_value.has(REF_KEY): return failure("Only native Dialogic style resource scripts are supported.")
		var script := _resolve_value(script_value, model, sections, made, next, workspace, chain, cache)
		if script.has("error"): return script
		if script.value == load(STYLE_SCRIPT): resource = DialogicStyle.new()
		elif script.value == load(LAYER_SCRIPT): resource = DialogicStyleLayer.new()
		else: return failure("Unexpected script resource.")
	elif type in BUILTINS:
		if section.props.get("script") != null: return failure("Scripted font, theme and drawing resources require the project-extension stage.")
		resource = ClassDB.instantiate(type)
	else: return failure("Unsupported native resource class: " + type)
	var properties := {}
	for prop: Dictionary in resource.get_property_list(): properties[prop.name] = prop
	for key: String in section.props:
		if key == "script": continue
		if key == "resource_local_to_scene" or key == "resource_name" or key.begins_with("metadata/"): pass
		elif not properties.has(key) and not (resource is Theme and key.contains("/")): return failure("Unknown resource property remains read-only: " + key)
		var parsed := _resolve_value(section.props[key], model, sections, made, next, workspace, chain, cache)
		if parsed.has("error"): return parsed
		var value: Variant = parsed.value
		if properties.has(key) and not compatible_type(properties[key].type, value): return failure("Invalid type for resource property: " + key)
		if not finite_data(value): return failure("Non-finite native resource value: " + key)
		if resource is DialogicStyle:
			if key == "name" and (not value is String or value.strip_edges().is_empty()): return failure("Style name must be nonempty.")
			if key == "inherits" and value != null and not value is DialogicStyle: return failure("Style inheritance requires DialogicStyle.")
			if (key == "base_scene" and value != null) or (key in ["layers", "base_overrides"] and not value.is_empty()): return failure("Pre-alpha-16 style formats remain read-only; migrate them in the fixed native editor.")
		if resource is DialogicStyleLayer and key == "scene" and value != null and not value is PackedScene: return failure("A layout layer requires a bundled PackedScene.")
		if properties.has(key) and properties[key].type == TYPE_OBJECT and value != null:
			var expected_class: String = properties[key].get("class_name", "")
			if ClassDB.class_exists(expected_class) and not value.is_class(expected_class): return failure("Wrong native resource class for: " + key)
		if resource is DialogicStyle and key == "layer_list":
			var typed: Array[String] = []
			for item: Variant in value:
				if not item is String: return failure("Style layer ids must be strings.")
				typed.append(item)
			resource.layer_list = typed
		else:
			var previous: Variant = resource.get(key)
			if previous is Array and previous.is_typed() and value is Array:
				var typed_values: Array = previous.duplicate(); typed_values.assign(value); resource.set(key, typed_values)
			else: resource.set(key, value)
	if resource is DialogicStyle:
		var checked := validate_style(resource, workspace, chain, cache)
		if not checked.is_empty(): return failure(checked)
	made[id] = resource
	return {"resource": resource}

static func _resolve_value(value: Variant, model: Dictionary, sections: Dictionary, made: Dictionary, active: Array[String], workspace: RefCounted, chain: Array[String], cache: Dictionary) -> Dictionary:
	if value is Dictionary:
		if value.has(REF_KEY):
			var result := _build_section(str(value[REF_KEY]) + ":" + str(value.id), model, sections, made, active, workspace, chain, cache)
			return result if result.has("error") else {"value": result.resource}
		var result := {}
		for key: Variant in value:
			var item := _resolve_value(value[key], model, sections, made, active, workspace, chain, cache)
			if item.has("error"): return item
			result[key] = item.value
		return {"value": result}
	if value is Array:
		var result := []
		for element: Variant in value:
			var item := _resolve_value(element, model, sections, made, active, workspace, chain, cache)
			if item.has("error"): return item
			result.append(item.value)
		return {"value": result}
	return {"value": value}

static func compatible_type(type: int, value: Variant) -> bool:
	return type == TYPE_NIL or typeof(value) == type or (type == TYPE_FLOAT and value is int) or (type == TYPE_OBJECT and value == null)

static func finite_data(value: Variant, depth := 0) -> bool:
	if depth > 64: return false
	if value is float: return is_finite(value)
	if value is Vector2: return is_finite(value.x) and is_finite(value.y)
	if value is Vector3: return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
	if value is Vector4: return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) and is_finite(value.w)
	if value is Rect2: return finite_data(value.position, depth + 1) and finite_data(value.size, depth + 1)
	if value is Transform2D: return finite_data(value.x, depth + 1) and finite_data(value.y, depth + 1) and finite_data(value.origin, depth + 1)
	if typeof(value) in [TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY]:
		for item: Variant in value:
			if not finite_data(item, depth + 1): return false
	if value is Color: return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	if value is Array or value is Dictionary:
		for item: Variant in (value.values() if value is Dictionary else value):
			if not finite_data(item, depth + 1): return false
	return true

static func enum_items(hint: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var next_value := 0
	for raw: String in hint.split(","):
		var label := raw
		var colon := raw.rfind(":")
		if colon >= 0 and raw.substr(colon + 1).is_valid_int():
			next_value = int(raw.substr(colon + 1))
			label = raw.substr(0, colon)
		items.append({"label": label, "value": next_value})
		next_value += 1
	return items

static func schema(scene_path: String) -> Dictionary:
	if scene_path.is_empty(): scene_path = PARTS + "Base_Default/default_layout_base.tscn"
	if scene_schemas.has(scene_path): return scene_schemas[scene_path]
	if not is_bundled(scene_path) or scene_path.get_extension() != "tscn": return {}
	var scene: PackedScene = load(scene_path)
	var node := scene.instantiate()
	scene_kinds[scene_path] = "base" if node is DialogicLayoutBase else ("layer" if node is DialogicLayoutLayer else "")
	var result := {}
	if scene_kinds[scene_path].is_empty() or node.get_script() == null:
		node.free(); scene_schemas[scene_path] = result
		return result
	var group := ""
	for info: Dictionary in node.get_script().get_script_property_list():
		if info.usage & PROPERTY_USAGE_GROUP: group = str(info.name)
		if info.usage & PROPERTY_USAGE_EDITOR and info.type != TYPE_NIL and group != "Private":
			var item := info.duplicate()
			item["default"] = node.get(info.name)
			result[info.name] = item
	node.free()
	scene_schemas[scene_path] = result
	return result

static func validate_style(style: DialogicStyle, workspace: RefCounted, chain: Array[String] = [], cache: Dictionary = {}) -> String:
	if style.name.strip_edges().is_empty() or style.name.contains("\n"): return "Style name must be nonempty, single-line text."
	if style.layer_list.size() > 1024 or style.layer_info.size() > 1025: return "At most 1024 layout layers are supported."
	if not style.layer_info.has(""): return "Style is missing its base layout layer."
	for id: Variant in style.layer_info:
		if not id is String or not style.layer_info[id] is DialogicStyleLayer: return "Style layer_info must map ids to native DialogicStyleLayer resources."
	var seen := {}
	for id: String in style.layer_list:
		if id.is_empty() or seen.has(id) or not style.layer_info.has(id): return "Style layer order contains missing or duplicate ids."
		seen[id] = true
	for id: Variant in style.layer_info:
		if not id is String or not style.layer_info[id] is DialogicStyleLayer: return "Style layer_info must map ids to native DialogicStyleLayer resources."
		var info := style.get_layer_inherited_info(id)
		var fields := schema(info.path)
		var actual_path: String = info.path if not info.path.is_empty() else PARTS + "Base_Default/default_layout_base.tscn"
		if scene_kinds.get(actual_path, "") != ("base" if id.is_empty() else "layer"): return "Use a native layout base for the base slot and native layout layers for other slots: " + actual_path
		if fields.is_empty() and not info.overrides.is_empty(): return "Unknown layout export schema: " + info.path
		for key: Variant in info.overrides:
			if not key is String or not fields.has(key) or not info.overrides[key] is String: return "Unknown or invalid layout override: " + str(key)
			var parsed := decode(info.overrides[key])
			var value: Variant = parsed.get("value")
			if fields[key].type == TYPE_STRING and (parsed.has("error") or value == null): value = info.overrides[key]
			elif parsed.has("error"): return parsed.error
			if not compatible_type(fields[key].type, value) or not finite_data(value): return "Invalid layout override type: " + key
			if fields[key].hint == PROPERTY_HINT_ENUM and value is int:
				var valid := false
				for option: Dictionary in enum_items(str(fields[key].hint_string)):
					if option.value == value: valid = true
				if not valid: return "Layout enum is out of range: " + key
			if fields[key].hint == PROPERTY_HINT_RANGE and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				var limits: PackedStringArray = str(fields[key].hint_string).split(",")
				if limits.size() >= 2:
					if (value < float(limits[0]) and not "or_lesser" in limits) or (value > float(limits[1]) and not "or_greater" in limits): return "Layout value is outside the native editor range: " + key
			if fields[key].hint == PROPERTY_HINT_DIR and value is String and not value.is_empty():
				if value != "res://addons/dialogic/Example Assets/sound-effects/": return "Custom audio folders require the media stage: " + key
			if fields[key].hint == PROPERTY_HINT_FILE and value is String and not value.is_empty():
				if is_bundled(value): continue
				var asset := inspect_path(value, workspace, chain, cache)
				if asset.has("error"): return key + ": " + asset.error
				if key.contains("font") and not asset.resource is Font: return "A font resource is required: " + key
				if (key.contains("panel") or key.contains("stylebox")) and not asset.resource is StyleBox: return "A StyleBox resource is required: " + key
				if key.contains("texture") and not asset.resource is Texture2D: return "A Texture2D resource is required: " + key
	return ""
