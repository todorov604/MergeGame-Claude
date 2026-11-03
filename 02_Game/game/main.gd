extends Control

## M0 第 1 周第 4 步：订单/角色自动演示入口。
## ProjectDoc -> EventEvaluator -> SimRunner -> 按事件时间实时播放 BoardView / OrderView。
## 截图模式：--capture <path> [--capture-at <seconds>]（capture-at 缺省 0）。
## 无参数时正常自动演示（循环播放）；R 重播，Space 暂停/继续。

const ProjectDoc := preload("res://core/project_doc.gd")
const EventEvaluator := preload("res://core/event_evaluator.gd")
const SimRunner := preload("res://core/sim/sim_runner.gd")
const BoardView := preload("res://game/board_view.gd")
const OrderView := preload("res://game/order_view.gd")

const PROJECT_PATH := "res://data/projects/sample_30s.json"
const CHANNEL_SIM := "sim"
const LOOP_TAIL_SECONDS := 2.0

var _project_data: Dictionary = {}
var _initial_snapshot: Dictionary = {}
var _sim_events: Array = []
var _snapshots: Array = []
var _elapsed := 0.0
var _event_index := 0
var _paused := false
var _running := false
var _capture_mode := false
var _board_view = null
var _order_view = null
var _label: Label = null
var _order_refresh_generation := 0


func _ready() -> void:
	var doc = ProjectDoc.new()
	if not doc.load_file(PROJECT_PATH):
		_show_error("项目加载失败: %s" % doc.parse_error)
		return

	_project_data = doc.data
	var seed_value := _seed_from(_project_data)

	var evaluator = EventEvaluator.new()
	var timeline: Array = []
	var timeline_v: Variant = _project_data.get("timeline", [])
	if typeof(timeline_v) == TYPE_ARRAY:
		timeline = timeline_v
	if not evaluator.evaluate(timeline):
		_show_error("时间轴求值失败: %s" % _first_error(evaluator.errors))
		return

	var sim_events: Array = []
	for event_v in evaluator.events:
		if typeof(event_v) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_v
		if _string_field(event, "channel") == CHANNEL_SIM:
			sim_events.append(event)

	var runner = SimRunner.new()
	var result: Dictionary = runner.run(doc, seed_value)
	var run_events: Array = []
	var run_events_v: Variant = result.get("events", [])
	if typeof(run_events_v) == TYPE_ARRAY:
		run_events = run_events_v
	var snapshots: Array = []
	var snapshots_v: Variant = result.get("snapshots", [])
	if typeof(snapshots_v) == TYPE_ARRAY:
		snapshots = snapshots_v
	if sim_events.size() != run_events.size() or sim_events.size() != snapshots.size():
		_show_error("sim 事件数量不一致: timeline=%d, runner=%d, snapshots=%d" % [sim_events.size(), run_events.size(), snapshots.size()])
		return

	_sim_events = sim_events
	_snapshots = snapshots
	var initial_v: Variant = result.get("initial_snapshot", {})
	if typeof(initial_v) == TYPE_DICTIONARY:
		_initial_snapshot = initial_v

	_board_view = BoardView.new()
	add_child(_board_view)
	_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_view.setup(_project_data, _initial_snapshot, [], [], true)

	_order_view = OrderView.new()
	add_child(_order_view)
	_order_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_order_view.setup(_project_data, _initial_snapshot, true)

	_label = Label.new()
	_label.position = Vector2(24.0, 18.0)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_label)
	_update_label(0.0)

	_running = true

	var capture_path := _capture_path_from_args()
	if not capture_path.is_empty():
		_capture_mode = true
		await _run_capture(capture_path, _capture_at_from_args())


func _process(delta: float) -> void:
	if not _running or _paused or _capture_mode:
		return
	if _sim_events.is_empty():
		return
	_elapsed += delta
	while _event_index < _sim_events.size():
		var event: Dictionary = _sim_events[_event_index]
		var at := _event_at(event)
		if at > _elapsed:
			break
		_apply_event(_event_index)
		_event_index += 1
		_update_label(at)
	if _event_index >= _sim_events.size() and _elapsed >= _last_event_time() + LOOP_TAIL_SECONDS:
		_restart_demo()


func _apply_event(index: int) -> void:
	if _board_view == null or _order_view == null:
		return
	if index < 0 or index >= _sim_events.size() or index >= _snapshots.size():
		return
	var event: Dictionary = _sim_events[index]
	var snapshot_after: Dictionary = {}
	var snapshot_v: Variant = _snapshots[index]
	if typeof(snapshot_v) == TYPE_DICTIONARY:
		snapshot_after = snapshot_v
	_board_view.refresh(snapshot_after)
	if _string_field(event, "type") == "order_claim":
		_play_claim(index, event, snapshot_after)
	else:
		_order_refresh_generation += 1
		_order_view.refresh(snapshot_after)


## order_claim：棋盘先刷新；物品 token 从事件前快照中 mission 第一件的格子飞向角色；
## 动画结束后再刷新 OrderView（已被更新快照覆盖时跳过，避免旧回调回写）。
func _play_claim(index: int, event: Dictionary, snapshot_after: Dictionary) -> void:
	if _board_view == null or _order_view == null:
		return
	var order_id := ""
	var payload_v: Variant = event.get("payload")
	if typeof(payload_v) == TYPE_DICTIONARY:
		order_id = _string_field(payload_v as Dictionary, "order")

	var prev_snapshot: Dictionary = _initial_snapshot
	if index > 0 and (index - 1) < _snapshots.size():
		var prev_v: Variant = _snapshots[index - 1]
		if typeof(prev_v) == TYPE_DICTIONARY:
			prev_snapshot = prev_v

	var order_def := _find_order_definition(prev_snapshot, order_id)
	var target := _first_mission_cell(prev_snapshot, order_def)
	if target.x < 0 or target.y < 0:
		_order_refresh_generation += 1
		_order_view.refresh(snapshot_after)
		return

	var origin: Vector2 = _board_view.cell_center_global(target.x, target.y)
	var coin := _int_field(order_def, "coin")
	var star := _int_field(order_def, "star")
	var generation := _order_refresh_generation
	_order_view.play_claim_sequence(origin, coin, star, func() -> void:
		if generation == _order_refresh_generation:
			_order_refresh_generation += 1
			_order_view.refresh(snapshot_after)
	)


func _restart_demo() -> void:
	if _board_view == null or _order_view == null:
		return
	_elapsed = 0.0
	_event_index = 0
	_board_view.refresh(_initial_snapshot)
	_order_refresh_generation += 1
	_order_view.refresh(_initial_snapshot)
	_update_label(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _capture_mode or not _running:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_R:
		_restart_demo()
	elif key_event.keycode == KEY_SPACE:
		_paused = not _paused


# ---------------------------------------------------------------------------
# 截图模式
# ---------------------------------------------------------------------------

func _run_capture(path: String, capture_at: float) -> void:
	if capture_at > 0.0:
		_silent_seek(capture_at)
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("capture 保存失败(%s): %s" % [error_string(save_error), path])
		get_tree().quit(1)
		return
	print("capture: %dx%d -> %s" % [image.get_width(), image.get_height(), path])
	get_tree().quit()


## 静默 seek：按时间顺序应用 at <= capture_at 的事件，不做动画，直接 refresh 到对应快照。
func _silent_seek(capture_at: float) -> void:
	if _board_view == null or _order_view == null:
		return
	var last_at := 0.0
	var applied := false
	for i in range(_sim_events.size()):
		var event: Dictionary = _sim_events[i]
		var at := _event_at(event)
		if at > capture_at:
			break
		if i >= _snapshots.size():
			break
		var snapshot_after: Dictionary = {}
		var snapshot_v: Variant = _snapshots[i]
		if typeof(snapshot_v) == TYPE_DICTIONARY:
			snapshot_after = snapshot_v
		_board_view.refresh(snapshot_after)
		_order_refresh_generation += 1
		_order_view.refresh(snapshot_after)
		last_at = at
		applied = true
	if applied:
		_update_label(last_at)


func _capture_path_from_args() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--capture" and i + 1 < args.size():
			return String(args[i + 1])
	return ""


func _capture_at_from_args() -> float:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--capture-at" and i + 1 < args.size():
			var text := String(args[i + 1])
			if text.is_valid_float():
				return text.to_float()
	return 0.0


# ---------------------------------------------------------------------------
# 数据辅助
# ---------------------------------------------------------------------------

func _update_label(time: float) -> void:
	if _label != null:
		_label.text = "M0 step 4 · t=%.1fs" % time


func _event_at(event: Dictionary) -> float:
	var value: Variant = event.get("at_resolved", 0.0)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return 0.0


func _last_event_time() -> float:
	if _sim_events.is_empty():
		return 0.0
	var last: Dictionary = _sim_events[_sim_events.size() - 1]
	return _event_at(last)


func _find_order_definition(prev_snapshot: Dictionary, order_id: String) -> Dictionary:
	if order_id.is_empty():
		return {}
	var level := _level_for_snapshot(prev_snapshot)
	var orders_v: Variant = level.get("orders")
	if typeof(orders_v) != TYPE_ARRAY:
		return {}
	for order_v in (orders_v as Array):
		if typeof(order_v) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = order_v
		if _string_field(order, "id") == order_id:
			return order
	return {}


## 行优先（y 外层、x 内层）找到第一个匹配 mission 第一件的格子；找不到返回 (-1,-1)。
func _first_mission_cell(prev_snapshot: Dictionary, order_def: Dictionary) -> Vector2i:
	var mission_v: Variant = order_def.get("mission")
	if typeof(mission_v) != TYPE_ARRAY:
		return Vector2i(-1, -1)
	var mission: Array = mission_v
	if mission.is_empty() or typeof(mission[0]) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	var item: Dictionary = mission[0]
	var entity := _string_field(item, "entity")
	var item_level := _int_field(item, "level")
	if entity.is_empty():
		return Vector2i(-1, -1)

	var board_v: Variant = prev_snapshot.get("board")
	if typeof(board_v) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	var cells_v: Variant = (board_v as Dictionary).get("cells")
	if typeof(cells_v) != TYPE_ARRAY:
		return Vector2i(-1, -1)

	var best := Vector2i(-1, -1)
	for cell_v in (cells_v as Array):
		if typeof(cell_v) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = cell_v
		if _string_field(cell, "entity") != entity:
			continue
		if _int_field(cell, "level") != item_level:
			continue
		var x := _int_field(cell, "x")
		var y := _int_field(cell, "y")
		if best.x < 0 or y < best.y or (y == best.y and x < best.x):
			best = Vector2i(x, y)
	return best


func _level_for_snapshot(snapshot_arg: Dictionary) -> Dictionary:
	var levels_v: Variant = _project_data.get("levels")
	if typeof(levels_v) != TYPE_ARRAY:
		return {}
	var levels: Array = levels_v
	if levels.is_empty():
		return {}
	var index := 0
	var level_snapshot_v: Variant = snapshot_arg.get("level")
	if typeof(level_snapshot_v) == TYPE_DICTIONARY:
		index = _int_field(level_snapshot_v as Dictionary, "index")
	index = clampi(index, 0, levels.size() - 1)
	var level_v: Variant = levels[index]
	if typeof(level_v) == TYPE_DICTIONARY:
		return level_v as Dictionary
	return {}


func _show_error(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.position = Vector2(40.0, 40.0)
	label.size = Vector2(1000.0, 240.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color("#ff6b6b"))
	add_child(label)
	push_error(message)


func _first_error(errors: Array) -> String:
	if errors.is_empty():
		return "未知错误"
	var first_v: Variant = errors[0]
	if typeof(first_v) == TYPE_DICTIONARY:
		return _string_field(first_v as Dictionary, "message")
	return "未知错误"


static func _seed_from(data: Dictionary) -> int:
	var meta_v: Variant = data.get("meta", {})
	if typeof(meta_v) != TYPE_DICTIONARY:
		return 0
	var seed_v: Variant = (meta_v as Dictionary).get("seed")
	if typeof(seed_v) == TYPE_INT or typeof(seed_v) == TYPE_FLOAT:
		return int(seed_v)
	return 0


static func _int_field(source: Dictionary, key: String) -> int:
	var value: Variant = source.get(key)
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f) and f == floor(f):
			return int(f)
	return 0


static func _string_field(source: Dictionary, key: String) -> String:
	var value: Variant = source.get(key, "")
	if typeof(value) == TYPE_STRING:
		return String(value)
	return ""
