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
	view.free()
