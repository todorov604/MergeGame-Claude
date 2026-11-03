extends RefCounted

## 模拟状态（M0 第 1 周第 2 步）：
## 汇总项目数据、HUD、棋盘、订单、生成器与关卡流程；持有唯一 RNG。
## 不依赖 Node / SceneTree。确定性约束：随机只来自本状态的 RandomNumberGenerator，
## 禁止 randf()/randomize()/时间 API。

const BoardState := preload("res://core/sim/board_state.gd")
const GeneratorEngine := preload("res://core/sim/generator_engine.gd")
const OrderEngine := preload("res://core/sim/order_engine.gd")
const LevelFlow := preload("res://core/sim/level_flow.gd")

var project_data: Dictionary = {}
var seed_value := 0
var rng: RandomNumberGenerator = null
var hud: Dictionary = {}
var board
var orders
var generators
var flow
var level_complete := false
var event_log: Array = []


func setup(data: Dictionary, seed_in: int) -> void:
	project_data = data
	seed_value = seed_in
	rng = RandomNumberGenerator.new()
	rng.seed = seed_in

	hud = {}
	var hud_v: Variant = data.get("hud", {})
	if typeof(hud_v) == TYPE_DICTIONARY:
		hud = (hud_v as Dictionary).duplicate(true)

	board = BoardState.new()
	orders = OrderEngine.new()
	generators = GeneratorEngine.new()
	flow = LevelFlow.new()

	var generators_v: Variant = data.get("generators", {})
	var generators_config: Dictionary = {}
	if typeof(generators_v) == TYPE_DICTIONARY:
		generators_config = generators_v
	generators.setup(generators_config)

	var levels_v: Variant = data.get("levels", [])
	var levels: Array = []
	if typeof(levels_v) == TYPE_ARRAY:
		levels = levels_v
	flow.setup(levels)

	event_log = []
	load_current_level()


func load_current_level() -> void:
	var level: Dictionary = flow.current_level()
	board.load_from_level(level)
	orders.setup(level)
	generators.reset()
	level_complete = false


func advance_level() -> bool:
	if not flow.has_next():
		return false
	flow.next()
	load_current_level()
	return true


func snapshot() -> Dictionary:
	return {
		"seed": int(seed_value),
		"hud": hud.duplicate(true),
		"level": flow.snapshot(),
		"board": board.snapshot(),
		"orders": orders.snapshot(),
		"level_complete": bool(level_complete),
	}


func state_hash() -> String:
	return JSON.stringify(snapshot(), "", true).sha256_text()
