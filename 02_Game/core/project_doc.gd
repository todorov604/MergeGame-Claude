extends RefCounted
## project.json 读取结果。原始数据保持 JSON 解析值，不做类型转换。

var ok := false
var parse_error := ""
var source_path := ""
var data: Dictionary = {}


func load_file(path: String) -> bool:
	ok = false
	parse_error = ""
	data = {}
	source_path = path

	if not FileAccess.file_exists(path):
		parse_error = "文件不存在: %s" % path
		return false

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		parse_error = "读取文件失败(%s): %s" % [error_string(FileAccess.get_open_error()), path]
		return false

	var root = JSON.parse_string(text)
	if root == null:
		parse_error = "JSON 解析失败: %s" % path
		return false
	if not root is Dictionary:
		parse_error = "JSON 根节点不是 Dictionary: %s" % path
		return false

	ok = true
	data = root
	return true


func from_dict(d: Dictionary, source_path_arg: String = "<memory>") -> void:
	ok = true
	parse_error = ""
	data = d
	source_path = source_path_arg


func get_dict(key: String) -> Dictionary:
	var value = data.get(key, {})
	if value is Dictionary:
		return value
	return {}


func get_array(key: String) -> Array:
	var value = data.get(key, [])
	if value is Array:
		return value
	return []


func timeline() -> Array:
	return get_array("timeline")
