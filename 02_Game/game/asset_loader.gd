extends RefCounted

## 资源加载器（M0 第 1 周第 3 步）：运行时唯一资源入口。
## 只允许加载 assets.json 中 usage 为 PLACEHOLDER（需显式允许）或 PRODUCTION 的资源；
## REFERENCE_ONLY / TODO 一律拒绝，绝不引用原游戏图片。

var allow_placeholders := false
var record_path := "res://assets/assets.json"
var by_id: Dictionary = {}
var setup_error := ""


func setup(record_path_arg = "res://assets/assets.json", allow_placeholders_flag = false) -> bool:
	record_path = String(record_path_arg)
	allow_placeholders = bool(allow_placeholders_flag)
	by_id = {}
	setup_error = ""

	if not FileAccess.file_exists(record_path):
		setup_error = "assets.json 不存在: %s" % record_path
		return false

	var text := FileAccess.get_file_as_string(record_path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		setup_error = "读取 assets.json 失败(%s): %s" % [error_string(FileAccess.get_open_error()), record_path]
		return false

	var root: Variant = JSON.parse_string(text)
	if root == null:
		setup_error = "JSON 解析失败: %s" % record_path
		return false
	if typeof(root) != TYPE_DICTIONARY:
		setup_error = "JSON 根节点不是 Dictionary: %s" % record_path
		return false

	var assets_v: Variant = (root as Dictionary).get("assets", [])
	if typeof(assets_v) != TYPE_ARRAY:
		setup_error = "assets 字段不是 Array: %s" % record_path
		return false

	var assets: Array = assets_v
	for item_v in assets:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var id_v: Variant = item.get("id", "")
		if typeof(id_v) != TYPE_STRING:
			continue
		var id := String(id_v)
		if id.is_empty():
			continue
		by_id[id] = item

	return true


func has(id: String) -> bool:
	return by_id.has(id)


func load_texture(id: String) -> Dictionary:
	return _load_asset(id, "texture")


func load_font(id: String) -> Dictionary:
	return _load_asset(id, "font")


func _load_asset(id: String, kind: String) -> Dictionary:
	if not by_id.has(id):
		return _result(false, kind, "", "", "资源未在 assets.json 中定义: %s" % id)

	var record: Dictionary = by_id[id]
	var usage := _string_field(record, "usage")
	var license := _string_field(record, "license")

	if usage == "PLACEHOLDER" and not allow_placeholders:
		return _result(false, kind, usage, license, "PLACEHOLDER 资源需 allow_placeholders=true: %s" % id)

	if usage == "REFERENCE_ONLY" or usage == "TODO":
		return _result(false, kind, usage, license, "REFERENCE_ONLY/TODO 资源禁止加载: %s" % id)

	# 硬约束：除 PLACEHOLDER / PRODUCTION 外的 usage 一律拒绝。
	if usage != "PLACEHOLDER" and usage != "PRODUCTION":
		return _result(false, kind, usage, license, "资源 usage 不允许加载: %s" % id)

	var file := _string_field(record, "file")
	if file.is_empty() or not FileAccess.file_exists(file):
		return _result(false, kind, usage, license, "缺图: %s" % file)

	# 混合策略：有导入缓存（.godot）时优先用 ResourceLoader，保持出片纹理/字体与既有基线一致；
	# 干净副本无导入缓存时回退到原始文件读取（纹理 Image.load_from_file，字体 FontFile.load_dynamic_font）。
	var loaded: Resource = null
	if kind == "texture":
		loaded = _load_texture(file)
	elif kind == "font":
		loaded = _load_font(file)
	if kind == "texture" and loaded is Texture2D:
		return _result(true, kind, usage, license, "", loaded)
	if kind == "font" and loaded is Font:
		return _result(true, kind, usage, license, "", loaded)
	return _result(false, kind, usage, license, "资源类型不符: %s" % file)


## 纹理：导入缓存真实存在时优先 ResourceLoader；否则从原始 PNG 解码为 ImageTexture。
func _load_texture(file: String) -> Texture2D:
	if _has_import_cache(file):
		var cached: Resource = ResourceLoader.load(file)
		if cached is Texture2D:
			return cached
		push_warning("导入缓存存在但纹理加载失败，回退运行时解码: %s" % file)
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(file))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## 字体：导入缓存真实存在时优先 ResourceLoader；否则用 FontFile 直接加载动态字体文件。
func _load_font(file: String) -> Font:
	if _has_import_cache(file):
		var cached: Resource = ResourceLoader.load(file)
		if cached is Font:
			return cached
		push_warning("导入缓存存在但字体加载失败，回退运行时加载: %s" % file)
	var font := FontFile.new()
	var font_error: Error = font.load_dynamic_font(ProjectSettings.globalize_path(file))
	if font_error == OK:
		return font
	return null


## 读取 <file>.import 的 path= 行，确认导入缓存文件真实存在。
## 干净副本（无 .godot）里 ResourceLoader.exists 仍会返回 true，直接 load 会打印错误；
## 必须先看 .import 指向的缓存文件是否存在，再决定是否走 ResourceLoader。
func _has_import_cache(file: String) -> bool:
	var import_path := file + ".import"
	if not FileAccess.file_exists(import_path):
		return false
	var text := FileAccess.get_file_as_string(import_path)
	if text.is_empty():
		return false
	var cache_path := ""
	for line_v in text.split("\n"):
		var line := String(line_v).strip_edges()
		if line.begins_with("path="):
			cache_path = line.substr("path=".length()).strip_edges()
			break
	if cache_path.length() >= 2 and cache_path.begins_with("\"") and cache_path.ends_with("\""):
		cache_path = cache_path.substr(1, cache_path.length() - 2)
	if cache_path.is_empty():
		return false
	return FileAccess.file_exists(cache_path)


func _result(ok_flag: bool, kind: String, usage: String, license: String, error: String, payload: Resource = null) -> Dictionary:
	var result := {
		"ok": ok_flag,
		"usage": usage,
		"license": license,
		"error": error,
	}
	if kind == "texture":
		result["texture"] = payload
	else:
		result["font"] = payload
	return result


func _string_field(source: Dictionary, key: String) -> String:
	var value: Variant = source.get(key, "")
	if typeof(value) == TYPE_STRING:
		return String(value)
	return ""
