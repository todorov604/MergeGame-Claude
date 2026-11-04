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

	var font: Dictionary = loader.load_font("font_en")
	r.check(bool(font["ok"]), "PRODUCTION 字体应可加载: " + str(font["error"]))
	r.check(font["font"] != null, "font_en 字体不应为 null")

	var reference: Dictionary = loader.load_texture("chip_clean_ca_lv01")
	r.check(not bool(reference["ok"]), "REFERENCE_ONLY 资源必须被拒绝")
	var reference_error := str(reference["error"])
	r.check(
		reference_error.find("未在 assets.json 中定义") != -1 or reference_error.find("禁止加载") != -1,
		"REFERENCE_ONLY 错误文案（实际=%s）" % reference_error
	)

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
