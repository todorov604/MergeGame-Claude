extends RefCounted

## validator 验收测试：真 manifest、合法样例、broken 夹具、逐条变异用例。

const ManifestDoc = preload("res://core/manifest_doc.gd")
const ProjectDoc = preload("res://core/project_doc.gd")
const Validator = preload("res://core/validator.gd")


func run(r) -> void:
	var manifest_path := "res://data/manifest_index.json"
	var manifest = ManifestDoc.new()
	r.check(manifest.load_file(manifest_path), "manifest 应能加载")
	r.eq(manifest.resources.size(), 180, "manifest 资源数应为 180")

	# 1) 真 manifest 通过
	var vm = Validator.new()
	vm.validate_manifest(manifest)
	r.check(vm.errors.is_empty(), "真实 manifest 应 0 错误: " + _join(vm.errors))

	# 2) 合法样例通过
	var sample = ProjectDoc.new()
	r.check(sample.load_file("res://data/projects/sample_30s.json"), "样例 project.json 应能加载")
	var vs = Validator.new()
	vs.validate_manifest(manifest)
	vs.validate_project(sample, manifest, true)
	r.check(vs.errors.is_empty(), "样例 project.json 应通过: " + _join(vs.errors))

	# 3) assets 记录通过（由 sync_assets.gd 生成）
	var va = Validator.new()
	va.validate_assets_record("res://assets/assets.json", manifest)
	r.check(va.errors.is_empty(), "assets.json 应通过: " + _join(va.errors))

	# 4) broken 夹具应报出全部预期错误
	var broken = ProjectDoc.new()
	r.check(broken.load_file("res://tests/fixtures/broken_project.json"), "broken 夹具应能加载")
	var vb = Validator.new()
	vb.validate_manifest(manifest)
	vb.validate_project(broken, manifest, true)
	_check(r, vb.errors, "entities.CleanSet_Cb.maxLevel", "等级上限", "maxLevel=11 应报等级上限")
	_check(r, vb.errors, "levels[0].board.slots[0].entity", "未定义", "未定义实体应报错")
	_check(r, vb.errors, "levels[0].board.slots[1]", "", "越界 slot 应报错")
	_check(r, vb.errors, "hud", "gem", "缺少 hud.gem 应报错")
	_check(r, vb.errors, "levels[0]", "next", "残留 next 应报错")
	_check(r, vb.errors, "timeline", "重复", "重复事件 id 应报错")
	_check(r, vb.errors, "timeline", "wait", "wait 事件应报错")
	_check(r, vb.errors, "timeline", "payload", "缺少 payload 应报错")
	_check(r, vb.errors, "timeline", "锚点", "缺失锚点应报错")
	r.check(vb.errors.size() >= 9, "broken 夹具应至少报 9 条错误，实际 %d: %s" % [vb.errors.size(), _join(vb.errors)])

	# 5) 逐条变异：在合法样例副本上制造单一错误，断言被捕获
	var base := _sample_dict()
	_expect_error(r, manifest, base, "board.slots[0].entity", "未定义", func(d): d["levels"][0]["board"]["slots"][0]["entity"] = "Ghost")
	_expect_error(r, manifest, base, "entities.CleanSet_Ca.maxLevel", "10", func(d): d["entities"]["CleanSet_Ca"]["maxLevel"] = 11)
	_expect_error(r, manifest, base, "hud", "star", func(d): d["hud"].erase("star"))
	_expect_error(r, manifest, base, "levels[0].orders[0].mission", "", func(d):
		d["levels"][0]["orders"][0]["mission"].append({"entity": "CleanSet_Ca", "level": 1})
		d["levels"][0]["orders"][0]["mission"].append({"entity": "CleanSet_Ca", "level": 1}))
	_expect_error(r, manifest, base, "levels[0].orders[0].character", "", func(d): d["levels"][0]["orders"][0]["character"] = "char_missing")
	_expect_error(r, manifest, base, "generators.CleanBox_C.outputs[0].entity", "", func(d): d["generators"]["CleanBox_C"]["outputs"][0]["entity"] = "Ghost")
	_expect_error(r, manifest, base, "timeline", "重复", func(d): d["timeline"].append({"id": "e1", "channel": "sim", "type": "tap", "at": 1.0, "payload": {}}))
	_expect_error(r, manifest, base, "timeline", "未注册", func(d): d["timeline"].append({"id": "eX", "channel": "sim", "type": "explode", "at": 1.0, "payload": {}}))
	_expect_error(r, manifest, base, "timeline", "", func(d): d["timeline"].append({"id": "eY", "channel": "sim", "type": "tap", "at": 22.0, "payload": {"target": {"slot": [1, 1]}}, "duration": -1.0}))
	_expect_error(r, manifest, base, "timeline", "锚点", func(d): d["timeline"].append({"id": "eZ", "channel": "view", "type": "text", "at": {"after": "nope", "offset": 1.0}, "payload": {"text_key": "cta.play"}}))
	_expect_error(r, manifest, base, "timeline", "锚点循环", func(d): d["timeline"].append({"id": "c1", "channel": "view", "type": "text", "at": {"after": "c2", "offset": 0.0}, "payload": {"text_key": "cta.play"}}); d["timeline"].append({"id": "c2", "channel": "view", "type": "text", "at": {"after": "c1", "offset": 0.0}, "payload": {"text_key": "cta.play"}}))
	_expect_error(r, manifest, base, "timeline", "订单", func(d): d["timeline"][3]["payload"]["order"] = "order_missing")

	# 5b) chips.<entity>.icons 映射：未知资源 / 非法等级 / 未定义实体
	_expect_error(r, manifest, base, "chips.CleanSet_Ca.icons.1", "未定义", func(d): d["chips"] = {"CleanSet_Ca": {"icons": {"1": "no_such_asset"}}})
	_expect_error(r, manifest, base, "chips.CleanSet_Ca.icons.11", "1-10", func(d): d["chips"] = {"CleanSet_Ca": {"icons": {"11": "chip_clean_ca_lv01"}}})
	_expect_error(r, manifest, base, "chips.Ghost", "未定义", func(d): d["chips"] = {"Ghost": {"icons": {"1": "chip_clean_ca_lv01"}}})

	# 警告项（不阻断）
	var w1 = _validate_with(manifest, base, func(d): d["meta"]["duration"] = 30)
	r.check(_has_warning(w1.warnings, "duration"), "meta.duration 应产生警告")
	var w2 = _validate_with(manifest, base, func(d): d["timeline"][2]["payload"]["text_key"] = "nope.key")
	r.check(_has_warning(w2.warnings, "nope.key"), "缺失文案键应产生警告")

	# 6) manifest 变异（快照中只有 PLACEHOLDER/PRODUCTION 校验文件存在性）
	var frame_index := _resource_index_by_id(_fresh_manifest(), "board_frame")
	r.check(frame_index >= 0, "manifest 应包含 PLACEHOLDER 条目 board_frame")
	var m2 = _fresh_manifest()
	if frame_index >= 0:
		m2.resources[frame_index]["file"] = "res://assets/no_such_board_frame.png"
	var vmm = Validator.new()
	vmm.validate_manifest(m2)
	_check(r, vmm.errors, "resources[%d].file" % frame_index, "缺图", "manifest 缺图应报错")

	var m3 = _fresh_manifest()
	m3.resources[0]["usage"] = "REFERENCE_ONLY"
	var vm3 = Validator.new()
	vm3.validate_manifest(m3)
	_check(r, vm3.errors, "resources[0]", "status", "status/usage 不一致应报错")

	var m4 = _fresh_manifest()
	m4.resources.append(m4.resources[0].duplicate(true))
	var vm4 = Validator.new()
	vm4.validate_manifest(m4)
	_check(r, vm4.errors, "resources", "", "重复 manifest id 应报错")

	# 7) assets 记录变异：REFERENCE_ONLY 条目必须报错
	var bad_record := "user://bad_assets_test.json"
	var bad_file := FileAccess.open(bad_record, FileAccess.WRITE)
	bad_file.store_string(JSON.stringify({
		"version": 1,
		"assets": [{
			"id": "chip_clean_ca_lv01",
			"usage": "REFERENCE_ONLY",
			"license": "x",
			"source": "x",
			"file": "res://data/projects/sample_30s.json",
		}],
	}, "\t"))
	bad_file.close()
	var vb2 = Validator.new()
	vb2.validate_assets_record(bad_record, manifest)
	_check(r, vb2.errors, "assets", "REFERENCE_ONLY", "assets.json 出现 REFERENCE_ONLY 应报错")

	# 8) 不存在的 assets 记录只警告
	var vnone = Validator.new()
	vnone.validate_assets_record("user://no_such_assets.json", manifest)
	r.check(vnone.errors.is_empty(), "缺失 assets.json 不应是错误")
	r.check(not vnone.warnings.is_empty(), "缺失 assets.json 应产生警告")

	# 9) 主题映射：样例含 theme themes/pet_shop，真实 manifest + allow=true 仍 0 错误
	var theme_base := _sample_dict()
	r.eq(str(theme_base.get("theme", "")), "themes/pet_shop", "样例 project 应引用 themes/pet_shop")
	var p_theme = ProjectDoc.new()
	p_theme.from_dict(theme_base.duplicate(true), "<theme_sample>")
	var v_theme = Validator.new()
	v_theme.validate_manifest(manifest)
	v_theme.validate_project(p_theme, manifest, true)
	r.check(v_theme.errors.is_empty(), "含 pet_shop 主题的样例应 0 错误: " + _join(v_theme.errors))

	# 10) 主题目录不存在应报错
	_expect_error(r, manifest, theme_base, "theme", "主题文件不存在", func(d): d["theme"] = "themes/does_not_exist")

	# 11) 主题 chip_icons 引用 REFERENCE_ONLY 资源应报错。
	# 新 manifest 已无 REFERENCE_ONLY 条目，用内存变异把 pet_shop 引用的 chip_clean_ca_lv01 改为 REFERENCE_ONLY。
	var ref_manifest = _fresh_manifest()
	ref_manifest.by_id["chip_clean_ca_lv01"]["usage"] = "REFERENCE_ONLY"
	var p_ref = ProjectDoc.new()
	p_ref.from_dict(theme_base.duplicate(true), "<theme_ref>")
	var v_ref = Validator.new()
	v_ref.validate_project(p_ref, ref_manifest, true)
	r.check(
		_has(v_ref.errors, "theme.chip_icons", "REFERENCE_ONLY"),
		"主题 chip_icons 引用 REFERENCE_ONLY 应报错: " + _join(v_ref.errors)
	)

	# 11b) 主题 chip_icons 引用未定义资源应报错
	_expect_error(r, manifest, theme_base, "theme.chip_icons", "未定义", func(d): d["theme"] = "tests/fixtures/themes/chip_unknown")

	# 11c) manifest 为 PRODUCTION 但未打包（不在 assets.json）的主题引用必须被门禁拦下
	_expect_error(r, manifest, theme_base, "theme.chip_icons", "未打包", func(d): d["theme"] = "tests/fixtures/themes/chip_unpackaged")

	# 12) allow=false：主题的 PLACEHOLDER 资源应被守卫拒绝
	var p_theme_blocked = ProjectDoc.new()
	p_theme_blocked.from_dict(theme_base.duplicate(true), "<theme_blocked>")
	var v_theme_blocked = Validator.new()
	v_theme_blocked.validate_project(p_theme_blocked, manifest, false)
	r.check(
		_has(v_theme_blocked.errors, "", "allow_placeholders"),
		"allow=false 时 PLACEHOLDER 主题应报 allow_placeholders: " + _join(v_theme_blocked.errors)
	)


func _sample_dict() -> Dictionary:
	var p = ProjectDoc.new()
	p.load_file("res://data/projects/sample_30s.json")
	return p.data.duplicate(true)


func _fresh_manifest():
	var m = ManifestDoc.new()
	var manifest_path := "res://data/manifest_index.json"
	m.load_file(manifest_path)
	return m


func _resource_index_by_id(manifest, resource_id: String) -> int:
	for i in range(manifest.resources.size()):
		var entry_v: Variant = manifest.resources[i]
		if typeof(entry_v) == TYPE_DICTIONARY and str((entry_v as Dictionary).get("id", "")) == resource_id:
			return i
	return -1


func _validate_with(manifest, base: Dictionary, mutate: Callable) -> RefCounted:
	var d := base.duplicate(true)
	mutate.call(d)
	var p = ProjectDoc.new()
	p.from_dict(d, "<mutant>")
	var v = Validator.new()
	v.validate_project(p, manifest, true)
	return v


func _expect_error(r, manifest, base: Dictionary, path_prefix: String, needle: String, mutate: Callable) -> void:
	var v = _validate_with(manifest, base, mutate)
	var ok := _has(v.errors, path_prefix, needle)
	if not ok and needle != "":
		# 路径格式可能不同时退化为按消息匹配；path-only 检查不允许退化
		ok = _has(v.errors, "", needle)
	r.check(ok, "变异应报错 [%s / %s]: %s" % [path_prefix, needle, _join(v.errors)])


func _has(errors: Array, path_prefix: String, needle: String) -> bool:
	for e in errors:
		var path := str(e.get("path", ""))
		var message := str(e.get("message", ""))
		if path_prefix != "" and not path.begins_with(path_prefix):
			continue
		if needle == "" or message.find(needle) != -1:
			return true
	return false


func _check(r, errors: Array, path_prefix: String, needle: String, label: String) -> void:
	var ok := _has(errors, path_prefix, needle)
	if not ok and needle != "":
		ok = _has(errors, "", needle)
	r.check(ok, label + ": " + _join(errors))


func _has_warning(warnings: Array, needle: String) -> bool:
	for w in warnings:
		if str(w.get("message", "")).find(needle) != -1:
			return true
	return false


func _join(errors: Array) -> String:
	var parts: Array = []
	for e in errors:
		parts.append("%s: %s" % [str(e.get("path", "")), str(e.get("message", ""))])
	return " | ".join(parts)
