extends RefCounted
## 柜子（safebox）：2026-11-12 改成 JSON 指定坐标后的规则测试。
##   * `parse()` 产出 `{size,x,y,w,h,charges,level}`（board_view / 成片直接吃这套字段）
##   * `validate_entries()` 拦越界 / 重叠 / 压棋子 / 旧字符串写法
##   * sim 里柜子格照样阻挡，且不会被合并爆炸破坏

const Safeboxes = preload("res://src/core/safeboxes.gd")
const ProjectModel = preload("res://src/core/project_model.gd")
const Sim = preload("res://src/core/sim.gd")


func run(t) -> void:
	_spans(t)
	_parse(t)
	_validation(t)
	_sim_blocks_the_cells(t)


func _spans(t) -> void:
	t.eq(Safeboxes.span_of("1x7"), Vector2i(7, 1), "1x7 占 7 宽 1 高")
	t.eq(Safeboxes.span_of("2x2"), Vector2i(2, 2), "2x2 占 2x2")
	t.eq(Safeboxes.span_of("2x3"), Vector2i(3, 2), "2x3 占 3 宽 2 高")
	t.eq(Safeboxes.span_of("2x4"), Vector2i(4, 2), "2x4 占 4 宽 2 高")
	t.eq(Safeboxes.cells_of("2x2", 3, 4).size(), 4, "2x2 覆盖 4 格")


func _parse(t) -> void:
	var boxes: Array = Safeboxes.parse([
		{"size": "2x4", "slot": [0, 5]},
		{"size": "1x7", "slot": [0, 8], "charges": 3, "level": 12},
	], 7, 9)
	t.eq(boxes.size(), 2, "两个合法柜子都解析出来")
	var a: Dictionary = boxes[0]
	t.eq(String(a.get("size", "")), "2x4", "size 保留")
	t.eq(Vector2i(int(a.get("x", -1)), int(a.get("y", -1))), Vector2i(0, 5), "锚点按左上角解析")
	t.eq(Vector2i(int(a.get("w", 0)), int(a.get("h", 0))), Vector2i(4, 2), "宽高由 size 推出")
	t.eq(int(a.get("charges", -1)), Safeboxes.DEFAULT_CHARGES, "charges 默认 10")
	t.eq(int(a.get("level", -1)), Safeboxes.DEFAULT_LEVEL, "level 默认 22")
	var b: Dictionary = boxes[1]
	t.eq(int(b.get("charges", -1)), 3, "charges 读 JSON")
	t.eq(int(b.get("level", -1)), 12, "level 读 JSON")

	# 越界的、旧写法的、重叠的都要被丢弃（sim 不能半信半疑地摆）
	var dropped: Array = Safeboxes.parse([
		{"size": "2x4", "slot": [0, 8]},          # y+2 = 10 > 9
		"2x4",                                     # 旧字符串写法
		{"size": "2x4", "slot": [0, 5]},
		{"size": "2x4", "slot": [1, 5]},          # 与上一条重叠
	], 7, 9)
	t.eq(dropped.size(), 1, "越界 / 旧写法 / 重叠的条目都被丢弃")


func _validation(t) -> void:
	var occupied := {Vector2i(2, 6): "a chip"}
	var errs: Array = Safeboxes.validate_entries([
		"2x4",
		{"size": "9x9", "slot": [0, 0]},
		{"size": "2x4", "slot": [0, 8]},
		{"size": "2x4", "slot": [0, 5]},
		{"size": "2x4", "slot": [1, 5]},
		{"size": "2x2", "slot": [2, 6]},
		{"size": "2x2", "slot": [5, 0], "charges": 0},
	], 7, 9, occupied)
	var codes: Array = []
	for e in errs:
		codes.append(String((e as Dictionary).get("code", "")))
	t.ok(codes.has("SAFE_LEGACY_STRING"), "旧字符串写法报 SAFE_LEGACY_STRING", str(codes))
	t.ok(codes.has("SAFE_SIZE"), "非法尺寸报 SAFE_SIZE", str(codes))
	t.ok(codes.has("SAFE_OOB"), "越界报 SAFE_OOB（(0,8) 放 2x4）", str(codes))
	t.ok(codes.has("SAFE_OVERLAP"), "柜子互相重叠 / 压到棋子报 SAFE_OVERLAP", str(codes))
	t.ok(codes.has("SAFE_NUMBER"), "charges=0 报 SAFE_NUMBER", str(codes))

	var clean: Array = Safeboxes.validate_entries([{"size": "2x2", "slot": [0, 0]}], 7, 9, {})
	t.eq(clean, [], "合法配置零错误")


func _sim_blocks_the_cells(t) -> void:
	var model = ProjectModel.new()
	var project := {
		"version": 2,
		"hud": {"energy": 3, "coin": 0, "gem": 0},
		"entities": {"A": {"kind": "chip", "family": "F", "chain": "a", "maxLevel": 5}},
		"characters": {},
		"generators": {},
		"levels": [{
			"id": "s1",
			"board": {"width": 7, "height": 9, "slots": [
				{"x": 0, "y": 0, "entity": "A", "level": 1},
				{"x": 2, "y": 0, "entity": "A", "level": 1},
			]},
			"obstacles": [],
			"safes": [{"size": "2x3", "slot": [1, 4], "charges": 4, "level": 15}],
		}],
	}
	t.ok(model.load_data(project), "自造工程能加载", model.load_error)
	var sim = Sim.new()
	sim.setup(model, 7)
	t.eq(sim.safeboxes.size(), 1, "sim 解析出一个柜子")
	t.eq(int((sim.safeboxes[0] as Dictionary).get("charges", -1)), 4, "sim 带上了 charges")
	for cell in Safeboxes.cells_of("2x3", 1, 4):
		t.ok(sim.board.obstacle_types(cell).has("safe"), "柜子格被标成 safe 障碍 " + str(cell))

	# 柜子格不能落子（合并会被拒）
	var moved: Dictionary = sim.apply({"type": "move", "payload": {"from": [0, 0], "to": [1, 4]}})
	t.ok(not bool(moved.get("ok", true)), "棋子不能落进柜子格", str(moved))
