extends SceneTree

## 校验入口（M0 第 1 周第 1 步）：
## godot --headless --script res://tools/validate.gd -- [选项]
##   --project X            项目 JSON（默认 res://data/projects/sample_30s.json）
##   --manifest Y           资源 manifest（默认 <项目根>/../00_design/resource_manifest.json）
##   --assets Z             assets.json（默认 res://assets/assets.json）
##   --allow-placeholders   允许 PLACEHOLDER 资源
##   --json                 只输出 JSON 汇总
## 退出码：无 error -> 0，否则 1。

const Validator := preload("res://core/validator.gd")
const ManifestDoc := preload("res://core/manifest_doc.gd")
const ProjectDoc := preload("res://core/project_doc.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var project_path := "res://data/projects/sample_30s.json"
	var manifest_path := _default_manifest_path()
	var assets_path := "res://assets/assets.json"
	var allow_placeholders := false
	var json_output := false

	var i := 0
	while i < args.size():
		var arg := String(args[i])
		if arg == "--project" and i + 1 < args.size():
			i += 1
			project_path = String(args[i])
		elif arg == "--manifest" and i + 1 < args.size():
			i += 1
			manifest_path = String(args[i])
		elif arg == "--assets" and i + 1 < args.size():
			i += 1
			assets_path = String(args[i])
		elif arg == "--allow-placeholders":
			allow_placeholders = true
		elif arg == "--json":
			json_output = true
		i += 1

	var resolved_project := _resolve_path(project_path)
	var resolved_manifest := _resolve_path(manifest_path)
	var resolved_assets := _resolve_path(assets_path)

	var manifest = ManifestDoc.new()
	var project = ProjectDoc.new()
	manifest.load_file(resolved_manifest)
	project.load_file(resolved_project)

	var validator = Validator.new()
	validator.validate_manifest(manifest)
	validator.validate_project(project, manifest, allow_placeholders)
	validator.validate_assets_record(resolved_assets, manifest)

	var result: Dictionary = validator.summary()
	if json_output:
		var payload: Dictionary = result.duplicate(true)
		payload["project"] = resolved_project
		payload["manifest"] = resolved_manifest
		print(JSON.stringify(payload, "\t"))
	else:
		for err_v in validator.errors:
			var err: Dictionary = err_v
			print("ERROR %s: %s" % [err["path"], err["message"]])
		for warn_v in validator.warnings:
			var warn: Dictionary = warn_v
			print("WARN %s: %s" % [warn["path"], warn["message"]])
		var status := "PASS" if bool(result["ok"]) else "FAIL"
		print("结果: %s (%d errors, %d warnings)" % [status, int(result["error_count"]), int(result["warning_count"])])

	quit(0 if bool(result["ok"]) else 1)


func _default_manifest_path() -> String:
	var root := ProjectSettings.globalize_path("res://")
	return (root + "../00_design/resource_manifest.json").simplify_path()


func _resolve_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
