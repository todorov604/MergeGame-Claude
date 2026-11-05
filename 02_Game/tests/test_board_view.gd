extends RefCounted

## 第 3 步验收：AssetLoader 资源加载规则 + BoardView 静态棋盘视图。

const AssetLoader = preload("res://game/asset_loader.gd")
const BoardView = preload("res://game/board_view.gd")
const ProjectDoc = preload("res://core/project_doc.gd")
const SimState = preload("res://core/sim/sim_state.gd")


func run(r) -> void:
	# ---------------------------------------------------------------- asset loader
	var loader = AssetLoader.new()
	var loader_ready: bool = loader.setup("res://assets/assets.json", false)
	r.check(loader_ready, "assets.json 应能加载: " + str(loader.setup_error))

	var frame_blocked: Dictionary = loader.load_texture("board_frame")
	r.check(not bool(frame_blocked["ok"]), "PLACEHOLDER 默认必须被拒绝")
	r.contains(str(frame_blocked["error"]), "allow_placeholders=true", "PLACEHOLDER 错误文案")

	var loader_allowed = AssetLoader.new()
	r.check(loader_allowed.setup("res://assets/assets.json", true), "allow_placeholders=true 的 loader 应能 setup")
	var frame: Dictionary = loader_allowed.load_texture("board_frame")
	r.check(bool(frame["ok"]), "allow_placeholders=true 时 PLACEHOLDER 应可加载: " + str(frame["error"]))
	r.check(frame["texture"] != null, "board_frame 纹理不应为 null")

	# PSD §20.5 布局常量与源图尺寸：回归时直接失败。
	r.eq(BoardView.BOARD_ORIGIN, Vector2(48.0, 466.0), "棋盘容器原点应为 (48,466)")
	r.eq(BoardView.BOARD_SIZE, Vector2(983.0, 1263.0), "棋盘容器尺寸应为 983×1263")
	r.eq(BoardView.BG_BOTTOM_RECT, Rect2(0.0, 384.0, 1080.0, 1536.0), "底部背景应为 1080×1536 @ y=384")
	r.eq(BoardView.BG_TOP_RECT, Rect2(0.0, 0.0, 1080.0, 400.0), "顶部背景应为 1080×400 @ (0,0)")
	r.eq(BoardView.ITEMS_RECT, Rect2(193.0, 1731.0, 693.0, 183.0), "底部信息条应为 693×183 @ (193,1731)")
	r.eq(BoardView.EXIT_RECT.size, Vector2(164.0, 174.0), "左下退出按钮应为 164×174")
	r.eq(BoardView.CABINET_RECT.size, Vector2(109.0, 147.0), "右下背包应为 109×147")
	r.eq(BoardView.CHIP_ICON_MAX, 140.0, "chip 图标最大绘制尺寸应为 140")

	var expected_sizes := {
		"board_frame": Vector2(983.0, 1263.0),
		"board_bg": Vector2(1080.0, 1536.0),
		"local_bg_top": Vector2(1080.0, 400.0),
		"local_items_bar": Vector2(693.0, 183.0),
		"ui_select_frame": Vector2(160.0, 164.0),
		"ui_order_card": Vector2(120.0, 180.0),
		"char_order_01_idle": Vector2(373.0, 370.0),
		"char_order_02_idle": Vector2(373.0, 524.0),
	}
	for asset_id in expected_sizes.keys():
		var asset_result: Dictionary = loader_allowed.load_texture(String(asset_id))
		r.check(bool(asset_result.get("ok", false)), "PSD 素材应可加载: %s (%s)" % [asset_id, str(asset_result.get("error", ""))])
		var texture_v: Variant = asset_result.get("texture")
		if texture_v is Texture2D:
			r.eq((texture_v as Texture2D).get_size(), expected_sizes[asset_id], "PSD 素材源尺寸: %s" % asset_id)

	var font: Dictionary = loader.load_font("font_en")
	r.check(bool(font["ok"]), "PRODUCTION 字体应可加载: " + str(font["error"]))
	r.check(font["font"] != null, "font_en 字体不应为 null")

	# 真实棋子图标在 M1 已登记为 PRODUCTION 并打包进 assets/。
	var chip_icon: Dictionary = loader.load_texture("chip_clean_ca_lv01")
	r.check(bool(chip_icon["ok"]), "PRODUCTION 棋子图标应可加载: " + str(chip_icon["error"]))
	r.check(chip_icon["texture"] != null, "棋子图标纹理不应为 null")

	var unknown: Dictionary = loader.load_texture("no_such_asset")
	r.check(not bool(unknown["ok"]), "未知资源必须被拒绝")
	r.contains(str(unknown["error"]), "未在 assets.json 中定义", "未知资源错误文案")

	# ---------------------------------------------------------------- board view
	var doc = ProjectDoc.new()
	r.check(doc.load_file("res://data/projects/sample_30s.json"), "样例项目应能加载: " + str(doc.parse_error))
	var data: Dictionary = doc.data.duplicate(true)
	var state = SimState.new()
	state.setup(data, 12345)
	var snapshot: Dictionary = state.snapshot()

	var view = BoardView.new()
	view.setup(data, snapshot, [[2, 3]], [[5, 5]], true)
	r.eq(view.slot_count(), 63, "level_1 棋盘槽位数应为 7×9=63")
	r.eq(view.cell_count(), 4, "level_1 格子数应为 4")
	r.eq(view.obstacle_count(), 3, "level_1 障碍数应为 3")
	r.eq(view.selection, [[2, 3]], "selection 应原样保留")
	r.eq(view.completed, [[5, 5]], "completed 应原样保留")
	view.free()

	var empty_view = BoardView.new()
	empty_view.setup({}, {}, [], [], true)
	r.eq(empty_view.slot_count(), 0, "空 snapshot 不应崩溃且槽位数为 0")
	empty_view.free()

	# ---------------------------------------------------------------- set_selection / set_completed 与 refresh
	var mark_view = BoardView.new()
	mark_view.setup(data, snapshot, [], [], true)
	r.eq(mark_view.selection, [], "初始 selection 应为空")
	r.eq(mark_view.completed, [], "初始 completed 应为空")
	mark_view.set_selection([[2, 3]])
	r.eq(mark_view.selection, [[2, 3]], "set_selection 应更新 selection")
	mark_view.set_completed([[5, 5]])
	r.eq(mark_view.completed, [[5, 5]], "set_completed 应更新 completed")
	mark_view.refresh(snapshot)
	r.eq(mark_view.selection, [[2, 3]], "refresh 后 selection 应保留")
	r.eq(mark_view.completed, [[5, 5]], "refresh 后 completed 应保留")
	mark_view.free()
