extends RefCounted
## 资源渲染守卫：按 manifest 中的 usage 决定资源能否打包/出片。

var manifest = null
var allow_placeholders := false


func setup(manifest_doc, allow_placeholders_flag: bool) -> void:
	manifest = manifest_doc
	allow_placeholders = allow_placeholders_flag


func check(resource_id: String) -> Dictionary:
	if manifest == null or not manifest.ok:
		return _result(false, "", "", "manifest 未加载")

	if not manifest.has_resource(resource_id):
		return _result(false, "", "", "资源未在 manifest 中定义: %s" % resource_id)

	var resource: Dictionary = manifest.get_resource(resource_id)
	var usage := _get_string(resource, "usage")
	var license := _get_string(resource, "license")

	if usage == "REFERENCE_ONLY":
		return _result(false, usage, license, "REFERENCE_ONLY 资源禁止打包/出片: %s" % resource_id)
	if usage == "TODO":
		return _result(false, usage, license, "TODO 资源未补齐，禁止出片: %s" % resource_id)
	if usage == "PLACEHOLDER" and not allow_placeholders:
		return _result(false, usage, license, "PLACEHOLDER 资源需 allow_placeholders=true: %s" % resource_id)

	return _result(true, usage, license, "")


func _result(ok_flag: bool, usage: String, license: String, error: String) -> Dictionary:
	return {"ok": ok_flag, "usage": usage, "license": license, "error": error}


func _get_string(source: Dictionary, key: String) -> String:
	var value = source.get(key, "")
	if value is String:
		return value
	return ""
