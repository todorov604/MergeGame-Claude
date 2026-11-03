extends RefCounted

## 资源守卫矩阵测试（验收：REFERENCE_ONLY 禁止、PLACEHOLDER 需显式允许、TODO 阻断）。

const ManifestDoc = preload("res://core/manifest_doc.gd")
const ResourceGuard = preload("res://core/resource_guard.gd")


func run(r) -> void:
	var manifest_path := (ProjectSettings.globalize_path("res://") + "/../00_design/resource_manifest.json").simplify_path()
	var manifest = ManifestDoc.new()
	r.check(manifest.load_file(manifest_path), "manifest 应能加载: " + manifest_path)
	r.eq(manifest.resources.size(), 74, "manifest 资源数应为 74")
	r.check(manifest.has_resource("chip_clean_ca_lv01"), "manifest 应包含 chip_clean_ca_lv01")
	r.check(manifest.has_resource("font_zh"), "manifest 应包含 font_zh")

	var guard = ResourceGuard.new()
	var unloaded = guard.check("font_zh")
	r.check(not unloaded.ok, "未 setup 的守卫应拒绝加载")
	r.contains(unloaded.error, "manifest 未加载", "未 setup 错误文案")

	guard.setup(manifest, false)
	var reference = guard.check("chip_clean_ca_lv01")
	r.check(not reference.ok, "REFERENCE_ONLY 必须被拒绝")
	r.eq(reference.usage, "REFERENCE_ONLY", "REFERENCE_ONLY usage 回传")
	r.contains(reference.error, "REFERENCE_ONLY 资源禁止打包/出片", "REFERENCE_ONLY 错误文案")

	var placeholder_blocked = guard.check("board_frame")
	r.check(not placeholder_blocked.ok, "PLACEHOLDER 默认必须被拒绝")
	r.contains(placeholder_blocked.error, "allow_placeholders=true", "PLACEHOLDER 错误文案")

	var todo = guard.check("audio_bgm")
	r.check(not todo.ok, "TODO 必须被拒绝")
	r.contains(todo.error, "TODO 资源未补齐", "TODO 错误文案")

	var production = guard.check("font_zh")
	r.check(production.ok, "PRODUCTION 应允许")
	r.eq(production.usage, "PRODUCTION", "PRODUCTION usage 回传")
	r.eq(production.license, "Noto Sans OFL 1.1", "PRODUCTION license 回传")

	var unknown = guard.check("no_such_resource")
	r.check(not unknown.ok, "未知资源必须被拒绝")
	r.contains(unknown.error, "资源未在 manifest 中定义", "未知资源错误文案")

	guard.setup(manifest, true)
	var placeholder_allowed = guard.check("board_frame")
	r.check(placeholder_allowed.ok, "allow_placeholders=true 时 PLACEHOLDER 应允许")
	var reference_still_blocked = guard.check("chip_clean_ca_lv01")
	r.check(not reference_still_blocked.ok, "allow_placeholders=true 不能放行 REFERENCE_ONLY")
