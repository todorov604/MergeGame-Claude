extends RefCounted
## resource_manifest.json 读取结果。原始数据保持 JSON 解析值，不做类型转换。

var ok := false
var parse_error := ""
var version := 0
var resources: Array = []
var by_id: Dictionary = {}
var source_path := ""


func load_file(path: String) -> bool:
	ok = false
	parse_error = ""
	version = 0
	resources = []
	by_id = {}
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
	version = int(root.get("version", 0))

	var resources_value = root.get("resources", [])
	if resources_value is Array:
		resources = resources_value
	else:
		resources = []

	by_id = {}
	for resource in resources:
		if not resource is Dictionary:
			continue
		var resource_id = resource.get("id", "")
		if not resource_id is String or resource_id.is_empty():
			continue
		if not by_id.has(resource_id):
			by_id[resource_id] = resource

	return true


func get_resource(id: String) -> Dictionary:
	var resource: Dictionary = by_id.get(id, {})
	return resource


func has_resource(id: String) -> bool:
	return by_id.has(id)
