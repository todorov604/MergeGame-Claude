extends RefCounted

## 第 7 步验收：主题映射（ThemeDoc）。
## 契约：load_theme(theme_dir, project_data, allow_placeholders) -> bool；
## 字段 ok/error/theme_name/background_top/background_bottom/palette/
##      board_frame_id/font_ui_id/star_id；方法 board_frame_texture()/star_texture()/ui_font()。

const ThemeDoc = preload("res://game/theme_doc.gd")
const BoardView = preload("res://game/board_view.gd")
const ProjectDoc = preload("res://core/project_doc.gd")


func run(r) -> void:
	# 1) pet_shop：正常加载，字段与取图接口齐全
	var pet = ThemeDoc.new()
	r.check(pet.load_theme("res://themes/pet_shop", {}, true), "pet_shop 应能加载: " + str(pet.error))
	r.eq(pet.theme_name, "pet_shop", "theme_name 应为 pet_shop")
	r.check(pet.palette.size() >= 8, "pet_shop palette 至少 8 色（实际 %d）" % pet.palette.size())
	r.check(pet.board_frame_texture() != null, "board_frame_texture() 不应为 null")
	r.check(pet.star_texture() != null, "star_texture() 不应为 null")
	r.check(pet.ui_font() != null, "ui_font() 不应为 null")

	# 1b) chip_icons：level 1..10 → 资源 id；纹理可加载，未配置的实体/等级回退为空。
	r.eq(pet.chip_icon_id("CleanSet_Ca", 1), "chip_clean_ca_lv01", "Ca lv01 应映射 chip_clean_ca_lv01")
	r.eq(pet.chip_icon_id("CleanSet_Ca", 6), "chip_clean_ca_lv06", "Ca lv06 应映射 chip_clean_ca_lv06")
	r.eq(pet.chip_icon_id("CleanSet_Ca", 7), "icon_10002107", "Ca lv07 应映射 icon_10002107")
	r.eq(pet.chip_icon_id("CleanSet_Ca", 10), "icon_10002110", "Ca lv10 应映射 icon_10002110")
	r.eq(pet.chip_icon_id("CleanSet_Cb", 1), "chip_clean_cb_lv01", "Cb lv01 应映射 chip_clean_cb_lv01")
	r.eq(pet.chip_icon_id("CleanSet_Cb", 10), "icon_10002210", "Cb lv10 应映射 icon_10002210")
	var ca_texture = pet.chip_texture("CleanSet_Ca", 1)
	r.check(ca_texture != null, "Ca lv01 chip 纹理不应为 null")
	if ca_texture != null:
		r.check(ca_texture.get_width() > 0, "Ca lv01 chip 纹理宽度应大于 0")
	r.check(pet.chip_icon_id("CleanSet_Ca", 11) == "", "未配置的等级应返回空 id")
	r.check(pet.chip_texture("CleanSet_Ca", 11) == null, "未配置的等级应回退为空纹理")
	r.check(pet.chip_texture("NoSuchEntity", 1) == null, "未配置的实体应回退为空纹理")

	# 1c) 两套主题 1..10 全量映射：单级映射错误必须被抓住。
	var ca_ids := _expected_chain_ids("ca", 1)
	var cb_ids := _expected_chain_ids("cb", 2)
	for level in range(1, 11):
		r.eq(pet.chip_icon_id("CleanSet_Ca", level), ca_ids[level - 1], "pet_shop Ca lv%02d 映射" % level)
		r.eq(pet.chip_icon_id("CleanSet_Cb", level), cb_ids[level - 1], "pet_shop Cb lv%02d 映射" % level)

	# 2) candy：背景与调色板必须和 pet_shop 不同
	var candy = ThemeDoc.new()
	r.check(candy.load_theme("res://themes/candy", {}, true), "candy 应能加载: " + str(candy.error))
	r.check(
		str(candy.background_bottom) != str(pet.background_bottom),
		"candy background_bottom 应与 pet_shop 不同"
	)
	r.check(candy.palette.size() > 0 and pet.palette.size() > 0, "两套主题 palette 都不应为空")
	if candy.palette.size() > 0 and pet.palette.size() > 0:
		r.check(str(candy.palette[0]) != str(pet.palette[0]), "candy palette[0] 应与 pet_shop 不同")

	# 2b) candy 换一套图标：Ca 映射 cb 链，证明图标集由主题驱动
	r.eq(candy.chip_icon_id("CleanSet_Ca", 1), "chip_clean_cb_lv01", "candy 的 Ca lv01 应映射 cb 链图标")
	r.check(
		candy.chip_icon_id("CleanSet_Ca", 1) != pet.chip_icon_id("CleanSet_Ca", 1),
		"两套主题的 chip 图标映射应不同"
	)
	r.check(candy.chip_texture("CleanSet_Ca", 1) != null, "candy 的 chip 纹理不应为 null")
	for level in range(1, 11):
		r.eq(candy.chip_icon_id("CleanSet_Ca", level), cb_ids[level - 1], "candy Ca lv%02d 应映射 cb 链" % level)
		r.eq(candy.chip_icon_id("CleanSet_Cb", level), ca_ids[level - 1], "candy Cb lv%02d 应映射 ca 链" % level)

	# 2c) 主题引用的 chip 图标必须全部在 assets.json（未打包资源运行时会回退）
	var asset_ids := _asset_ids()
	var unregistered: Array = []
	for theme_doc in [pet, candy]:
		for entity in ["CleanSet_Ca", "CleanSet_Cb"]:
			for level in range(1, 11):
				var icon_id: String = theme_doc.chip_icon_id(entity, level)
				if icon_id.is_empty() or not asset_ids.has(icon_id):
					unregistered.append(icon_id)
	r.check(unregistered.is_empty(), "主题 chip_icons 应全部在 assets.json: %s" % ", ".join(unregistered))

	# 3) allow=false：PLACEHOLDER 主题必须被资源守卫拒绝
	var blocked = ThemeDoc.new()
	r.check(not blocked.load_theme("res://themes/pet_shop", {}, false), "allow=false 时 pet_shop 应加载失败")
	r.contains(str(blocked.error), "allow_placeholders", "PLACEHOLDER 守卫错误文案")

	# 4) 不存在的主题目录：失败且 error 非空
	var missing = ThemeDoc.new()
	r.check(not missing.load_theme("themes/does_not_exist", {}, true), "不存在的主题目录应加载失败")
	r.check(not str(missing.error).is_empty(), "不存在的主题目录应给出错误信息")

	# 5) 优先级：theme 的 board_frame 覆盖 project_data.icons.board_frame
	var overridden = ThemeDoc.new()
	var project_with_icon := {"icons": {"board_frame": "box_safe_x"}}
	r.check(
		overridden.load_theme("res://themes/pet_shop", project_with_icon, true),
		"theme 覆盖 project 的 board_frame 后仍应加载成功: " + str(overridden.error)
	)
	r.eq(overridden.board_frame_id, "board_frame", "theme 指定的 board_frame 应优先于 project_data")

	# 5b) chip 图标优先级：theme > project > default
	var project_chips := {
		"chips": {
			"CleanSet_Ca": {"icons": {"1": "ui_icon_star"}},
			"OnlyInProject": {"icons": {"1": "ui_icon_star"}},
		}
	}
	var priority = ThemeDoc.new()
	r.check(
		priority.load_theme("res://themes/pet_shop", project_chips, true),
		"带 project chips 的主题应能加载: " + str(priority.error)
	)
	r.eq(priority.chip_icon_id("CleanSet_Ca", 1), "chip_clean_ca_lv01", "theme 应覆盖 project 的 chip 图标")
	r.eq(priority.chip_icon_id("OnlyInProject", 1), "ui_icon_star", "theme 未定义的实体应回落到 project")
	r.check(priority.chip_texture("OnlyInProject", 1) != null, "project 回落的 chip 纹理不应为 null")

	# 5c) 未知 chip 图标：主题仍可加载，取图回退为空并产生 warning
	var fallback = ThemeDoc.new()
	var bad_project := {"chips": {"BrokenEntity": {"icons": {"1": "no_such_asset"}}}}
	r.check(
		fallback.load_theme("res://themes/pet_shop", bad_project, true),
		"未知 chip 图标不应导致主题加载失败: " + str(fallback.error)
	)
	r.check(fallback.chip_texture("BrokenEntity", 1) == null, "未知 chip 图标应回退为空纹理")
	r.check(not fallback.warnings.is_empty(), "未知 chip 图标应产生 warning")

	# 6) BoardView.setup 可选 theme 参数不应崩溃
	var doc = ProjectDoc.new()
	r.check(doc.load_file("res://data/projects/sample_30s.json"), "样例项目应能加载: " + str(doc.parse_error))
	var data: Dictionary = doc.data.duplicate(true)
	var view_theme = ThemeDoc.new()
	r.check(
		view_theme.load_theme("res://themes/pet_shop", data, true),
		"样例数据下 pet_shop 应能加载: " + str(view_theme.error)
	)
	var view = BoardView.new()
	view.setup(data, {}, [], [], true, view_theme)
	r.check(view.slot_count() >= 0, "BoardView.setup 带 theme 参数不应崩溃")
	r.check(view.chip_icon_texture("CleanSet_Ca", 1) != null, "BoardView 应能取到主题 chip 图标")
	var view_no_theme = BoardView.new()
	view_no_theme.setup(data, {}, [], [], true)
	r.check(view_no_theme.chip_icon_texture("CleanSet_Ca", 1) == null, "无主题时 chip 图标应为空")
	view_no_theme.free()
	view.free()


## lv01–06 登记为 chip_clean_<chain>_lvNN；lv07–10 登记为 icon_10002<chain><level>。
func _expected_chain_ids(chain: String, chain_digit: int) -> Array:
	var ids: Array = []
	for level in range(1, 11):
		if level <= 6:
			ids.append("chip_clean_%s_lv%02d" % [chain, level])
		else:
			ids.append("icon_10002%d%02d" % [chain_digit, level])
	return ids


func _asset_ids() -> Dictionary:
	var ids: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/assets.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ids
	var assets_v: Variant = (parsed as Dictionary).get("assets", [])
	if typeof(assets_v) != TYPE_ARRAY:
		return ids
	for item_v in (assets_v as Array):
		if typeof(item_v) == TYPE_DICTIONARY:
			var id_v: Variant = (item_v as Dictionary).get("id", "")
			if typeof(id_v) == TYPE_STRING:
				ids[String(id_v)] = true
	return ids
