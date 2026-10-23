class_name AppIdentity
extends RefCounted

## One source of truth for product branding. VERSION.txt owns the release number.
## ConfigFile: https://docs.godotengine.org/en/stable/classes/class_configfile.html

const CONFIG_PATH := "res://config/branding.cfg"
const VERSION_PATH := "res://VERSION.txt"
const MAX_SVG_BYTES := 2 * 1024 * 1024
const LOGO_SIZE := Vector2i(768, 195)

static var _loaded := false
static var _values: Dictionary = {}
static var _error := ""
static var _logo: Texture2D
static var _app_icon: Texture2D


static func validate_config(config_path: String = CONFIG_PATH) -> Dictionary:
	var errors: Array[String] = []
	var values: Dictionary = {}
	var configuration := ConfigFile.new()
	var result: Error = configuration.load(config_path)
	if result != OK:
		return {"valid": false, "errors": ["Cannot read branding configuration (error %d): %s" % [result, config_path]], "values": values}
	for key: String in ["project_name", "artifact_stem", "logo_svg", "app_icon_svg", "user_data_directory"]:
		var value: Variant = configuration.get_value("branding", key, null)
		if not value is String or str(value).strip_edges().is_empty():
			errors.append("branding/%s must be a nonempty string." % key)
		else:
			values[key] = str(value).strip_edges()
	if not errors.is_empty():
		return {"valid": false, "errors": errors, "values": values}
	var name: String = values["project_name"]
	if name.length() > 160 or name.contains("\n") or name.contains("\r") or name.contains("\t"):
		errors.append("branding/project_name must be one line of at most 160 characters.")
	var safe_name := RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$")
	for key: String in ["artifact_stem", "user_data_directory"]:
		if safe_name.search(values[key]) == null:
			errors.append("branding/%s must use 1-96 ASCII letters, digits, underscores or hyphens, starting with a letter or digit." % key)
	for key: String in ["logo_svg", "app_icon_svg"]:
		var image_result: Dictionary = _read_svg(values[key], key)
		if image_result.has("error"):
			errors.append(image_result["error"])
		else:
			values["logo_image" if key == "logo_svg" else "app_icon_image"] = image_result["image"]
	var release: String = FileAccess.get_file_as_string(VERSION_PATH).strip_edges()
	if RegEx.create_from_string("^[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][A-Za-z0-9.+-]+)?$").search(release) == null:
		errors.append("VERSION.txt must contain a valid release version.")
	else:
		values["version"] = release
	return {"valid": errors.is_empty(), "errors": errors, "values": values}


static func _read_svg(path: String, key: String) -> Dictionary:
	if not path.begins_with("res://") or path.get_extension().to_lower() != "svg" or path.simplify_path() != path:
		return {"error": "branding/%s must be a canonical res:// path to an SVG in this Source project." % key}
	for folder: String in ["tests", "docs", "builds", "tools", "examples"]:
		if path.begins_with("res://" + folder + "/"):
			return {"error": "branding/%s cannot reference an export-excluded folder." % key}
	if not FileAccess.file_exists(path):
		# Exported runtimes may resolve imported textures without source SVG bytes.
		# Source builds reject missing files even when stale imports still exist.
		if OS.has_feature("template") and ResourceLoader.exists(path, "Texture2D"):
			var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
			var imported_image: Image = texture.get_image() if texture != null else null
			if imported_image == null or imported_image.is_empty():
				return {"error": "The configured imported SVG cannot be rendered: " + path}
			if imported_image.is_compressed() and imported_image.decompress() != OK:
				return {"error": "The configured imported SVG cannot be decompressed: " + path}
			return {"image": imported_image}
		return {"error": "The configured SVG does not exist: " + path}
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null or source.get_length() > MAX_SVG_BYTES:
		return {"error": "The configured SVG cannot be read or exceeds 2 MiB: " + path}
	var bytes: PackedByteArray = source.get_buffer(source.get_length())
	source.close()
	if not _has_svg_root(bytes):
		return {"error": "The configured image is not an SVG XML document: " + path}
	var image := Image.new()
	var image_error: Error = image.load_svg_from_buffer(bytes)
	if image_error != OK or image.is_empty():
		return {"error": "The configured SVG cannot be rendered (error %d): %s" % [image_error, path]}
	return {"image": image}


static func _has_svg_root(bytes: PackedByteArray) -> bool:
	var parser := XMLParser.new()
	if parser.open_buffer(bytes) != OK:
		return false
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			return parser.get_node_name() == "svg"
	return false


static func reload_branding(config_path: String = CONFIG_PATH) -> Error:
	var validation := validate_config(config_path)
	_loaded = true
	_values = validation["values"]
	_logo = null
	_app_icon = null
	_error = "\n".join(validation["errors"])
	if not validation["valid"]:
		_values = {}
		return ERR_INVALID_DATA
	_logo = _fit_texture(_values["logo_image"], LOGO_SIZE)
	_app_icon = _fit_texture(_values["app_icon_image"], Vector2i(16, 16))
	_values.erase("logo_image")
	_values.erase("app_icon_image")
	return OK


static func _fit_texture(image: Image, size: Vector2i) -> Texture2D:
	var fitted: Image = image.duplicate()
	var scale_factor: float = minf(float(size.x) / image.get_width(), float(size.y) / image.get_height())
	var target := Vector2i(maxi(1, roundi(image.get_width() * scale_factor)), maxi(1, roundi(image.get_height() * scale_factor)))
	fitted.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
	fitted.convert(Image.FORMAT_RGBA8)
	var canvas := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	canvas.blit_rect(fitted, Rect2i(Vector2i.ZERO, target), (size - target) / 2)
	return ImageTexture.create_from_image(canvas)


static func _ensure_loaded() -> void:
	if not _loaded:
		reload_branding()


static func project_name() -> String:
	_ensure_loaded()
	return _values.get("project_name", "Branding configuration error")


static func version() -> String:
	_ensure_loaded()
	return _values.get("version", "")


static func artifact_stem() -> String:
	_ensure_loaded()
	return _values.get("artifact_stem", "editor")


static func window_title(document_title: String = "") -> String:
	var suffix: String = project_name() + (" " + version() if not version().is_empty() else "")
	return document_title + " — " + suffix if not document_title.is_empty() else suffix


static func preview_title() -> String:
	return "Preview — " + window_title()


static func footer_text() -> String:
	return window_title()


static func logo_texture() -> Texture2D:
	_ensure_loaded()
	return _logo


static func app_icon_texture() -> Texture2D:
	_ensure_loaded()
	return _app_icon


static func last_error() -> String:
	_ensure_loaded()
	return _error
