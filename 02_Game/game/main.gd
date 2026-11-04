extends Control

## M0 第 1 周第 5 步：时间轴实时播放入口。
## ProjectDoc -> TimelinePlayer（Validator + 求值 + SimRunner）-> BoardView / OrderView / ViewLayer。
## 截图模式：--capture <path> [--capture-at <seconds>]（capture-at 缺省 0）。
## 无参数时循环自动演示；R 重播，Space 暂停/继续。

const ProjectDoc := preload("res://core/project_doc.gd")
const TimelinePlayer := preload("res://game/timeline_player.gd")
const BoardView := preload("res://game/board_view.gd")
const OrderView := preload("res://game/order_view.gd")
const ViewLayer := preload("res://game/view_layer.gd")
const HUDView := preload("res://game/hud_view.gd")
const ThemeDoc := preload("res://game/theme_doc.gd")

const PROJECT_PATH := "res://data/projects/sample_30s.json"
const CHANNEL_SIM := "sim"
const CHANNEL_VIEW := "view"
const LOOP_TAIL_SECONDS := 2.0
const HINT_DELAY := 3.0

var _project_data: Dictionary = {}
var _player = null
var _board_view = null
var _order_view = null
var _view_layer = null
var _hud = null
var _theme = null
var _label: Label = null
var _error_label: Label = null
var _elapsed := 0.0
var _view_cursor := 0
var _paused := false
var _running := false
var _capture_mode := false
var _capture_path := ""
var _capture_at := 0.0
var _claim_generation := 0
var _project_path := PROJECT_PATH
var _render_mode := false
var _selection_slots: Array = []
var _selection_at := -1.0
var _hint_shown := false


func _ready() -> void:
	# 参数必须先解析：之后任何启动失败都能按截图/渲染约定退出，而不是挂起。
	_capture_path = _capture_path_from_args()
	_capture_at = _capture_at_from_args()
	_project_path = _arg_value("--project", PROJECT_PATH)
	_render_mode = _has_arg("--render")

	var doc = ProjectDoc.new()
	if not doc.load_file(_resolve_project_path(_project_path)):
		_fail_start("项目加载失败: %s" % doc.parse_error)
		return

	_project_data = doc.data
	_player = TimelinePlayer.new()
	# setup 内部先跑 Validator：非法项目（wait/未注册类型等）不得进入 main 与出片。
	var setup_v: Variant = _player.setup(doc)
	var setup_ok := typeof(setup_v) == TYPE_BOOL and bool(setup_v)
	if not setup_ok:
		_fail_start(_first_player_error())
		return

	var theme_dir := String(_project_data.get("theme", "themes/pet_shop"))
	_theme = ThemeDoc.new()
	if not _theme.load_theme(theme_dir, _project_data, true):
		_fail_start("主题加载失败: %s" % _theme.error)
		return

	_build_views()
	_running = true

	if not _capture_path.is_empty():
		_capture_mode = true
		await _run_capture(_capture_path, _capture_at)


func _process(delta: float) -> void:
	if not _running or _paused or _capture_mode or _player == null:
		return

	_elapsed += delta

	# 1) 推进 sim：应用所有已到点的 sim 事件，并把视图刷新到对应快照。
	_advance_sim()

	# 2) 推进 view：player.events 已按 at_resolved 排序，含 sim/view/audio。
	_advance_view()

	if _view_layer != null:
		_view_layer.tick(_elapsed)
	# 3) 选中停留超过 HINT_DELAY 后提示所有可合并格（在 tick 清理过期提示之后）。
	_maybe_show_hint()
	_update_label(_elapsed)

	# 4) 循环：duration 已含 view 事件的 duration（sample=30s），尾部再留 2s。
	var duration := 0.0
	var duration_v: Variant = _player.duration
	if typeof(duration_v) == TYPE_INT or typeof(duration_v) == TYPE_FLOAT:
		duration = float(duration_v)
	if _elapsed >= duration + LOOP_TAIL_SECONDS:
		_restart_demo()


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
		_refresh_hud()


# ---------------------------------------------------------------------------
# 视图构建
# ---------------------------------------------------------------------------

func _build_views() -> void:
	_board_view = BoardView.new()
	add_child(_board_view)
	_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_view.setup(_project_data, _initial_snapshot(), [], [], true, _theme)

	_order_view = OrderView.new()
	add_child(_order_view)
	_order_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_order_view.setup(_project_data, _initial_snapshot(), true, _theme)

	_view_layer = ViewLayer.new()
	add_child(_view_layer)
	_view_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view_layer.setup(_project_data, _board_view, _order_view, _theme)

	# HUD 最后加入，保证位于 view_layer 之上、调试标签之下。
	_hud = HUDView.new()
	add_child(_hud)
	if _hud is Control:
		var hud_control := _hud as Control
		hud_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hud_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.setup(_project_data, _theme, true)
	_hud.refresh(_initial_snapshot(), 0.0)

	_label = Label.new()
	_label.position = Vector2(24.0, 128.0)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_label)
	# 出片模式不显示调试时间标签。
	_label.visible = not _render_mode
	_update_label(0.0)

	_error_label = Label.new()
	_error_label.position = Vector2(24.0, 62.0)
	_error_label.size = Vector2(1032.0, 88.0)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_font_size_override("font_size", 28)
	_error_label.add_theme_color_override("font_color", Color("#ff6b6b"))
	add_child(_error_label)
	# 出片模式不显示运行期错误标签，避免错误文字入镜；错误仍经 push_error 写入日志/终端。
	_error_label.visible = not _render_mode


# ---------------------------------------------------------------------------
# 播放调度
# ---------------------------------------------------------------------------

func _advance_sim() -> void:
	if _player == null:
		return
	var guard := 0
	while _player.has_next() and _player.next_event_time() <= _elapsed:
		guard += 1
		if guard > 4096:
			_show_runtime_error("播放步进异常：事件未推进")
			return
		# 动画与 completed 计算都需要事件前的快照。
		var before_snapshot: Dictionary = _player.current_snapshot()
		var result_v: Variant = _player.step()
		if typeof(result_v) != TYPE_DICTIONARY:
			_show_runtime_error("播放步进失败")
			return
		_apply_sim_result(result_v as Dictionary, before_snapshot, true)


## 应用一条 sim 结果：刷新视图、驱动选中/完成状态；失败时只显示错误，不播成功动画。
## animate=false 用于截图 seek（不创建 Tween）。
func _apply_sim_result(result: Dictionary, before_snapshot: Dictionary, animate: bool) -> void:
	var snapshot := _snapshot_from(result)
	var event := _event_from(result)
	if _board_view != null:
		_board_view.refresh(snapshot)
	if _hud != null:
		_hud.refresh(snapshot, _elapsed)

	var log_entry := _sim_log_entry(result)
	var ok := bool(result.get("ok", false))
	# 兼容未修复的 step：即使 result.ok 误报成功，也以 sim_log 的实际结果为准。
	if not log_entry.is_empty():
		ok = ok and bool(log_entry.get("ok", false))
	var event_type := _string_field(event, "type")
	var message := _string_field(log_entry, "message")
	if message.is_empty():
		message = _string_field(result, "message")

	# 棋盘已满：显式 board_full 事件，或 tap 失败且消息为“棋盘已满”。
	if _view_layer != null and _view_layer.has_method("show_board_full"):
		if event_type == "board_full" or (event_type == "tap" and not ok and message.contains("棋盘已满")):
			_view_layer.show_board_full()

	if not ok:
		var event_id := _string_field(event, "id")
		if event_id.is_empty():
			event_id = "?"
		if message.is_empty():
			message = "模拟失败"
		_show_runtime_error("事件 %s 失败: %s" % [event_id, message])
		# 失败事件状态未变化，订单视图照常刷新；绝不播放成功动画。
		_refresh_order_view(snapshot)
		return

	# 普通事件立即刷新订单视图；成功 order_claim 交给飞行动画回调刷新，
	# 这样角色在动画期间保持可见（与 OrderView.play_claim_sequence 的语义一致）。
	if not (animate and event_type == "order_claim"):
		_refresh_order_view(snapshot)

	_drive_visual_state(event, before_snapshot)

	if animate and event_type == "order_claim":
		_play_claim(event, before_snapshot, snapshot)


## 选中/完成驱动：tap 选目标格；merge/drag 选目标格；deliver 标记 mission 全部格子；
## order_claim / level_next 清空。选中变化同时重置停留提示。
func _drive_visual_state(event: Dictionary, before_snapshot: Dictionary) -> void:
	if _board_view == null:
		return
	var payload := _payload(event)
	match _string_field(event, "type"):
		"tap":
			var target := _dict_field(payload, "target")
			var slot := _xy_from(target.get("slot"))
			if _is_xy(slot):
				_board_view.set_selection([slot])
				_track_selection([slot])
		"merge", "drag":
			var to := _xy_from(payload.get("to"))
			if _is_xy(to):
				_board_view.set_selection([to])
				_track_selection([to])
		"deliver":
			var order_id := _string_field(payload, "order")
			var order_def := _find_order_definition(before_snapshot, order_id)
			_board_view.set_completed(_mission_cells(before_snapshot, order_def))
			_board_view.set_selection([])
			_clear_selection_hint()
		"order_claim", "level_next":
			_board_view.set_completed([])
			_board_view.set_selection([])
			_clear_selection_hint()


# ---------------------------------------------------------------------------
# 选中停留提示
# ---------------------------------------------------------------------------

## 每帧检查：选中格停留满 HINT_DELAY 秒后，把同 entity+level 的全部格子交给棋盘提示。
func _maybe_show_hint() -> void:
	if _board_view == null or _selection_slots.is_empty() or _hint_shown:
		return
	if _selection_at < 0.0 or _elapsed - _selection_at < HINT_DELAY:
		return
	var origin := _slot_xy(_selection_slots[0])
	var slots := _matching_entity_slots(_current_snapshot(), origin)
	if slots.size() >= 2:
		if _board_view.has_method("set_hint_slots"):
			_board_view.set_hint_slots(slots)
		_hint_shown = true


## 新选中/切换选中：记录停留起点并清掉旧提示。
func _track_selection(slots: Array) -> void:
	_selection_slots = slots.duplicate()
	_selection_at = _elapsed
	_hint_shown = false
	if _board_view != null and _board_view.has_method("clear_hint"):
		_board_view.clear_hint()


## 选中清空（deliver/order_claim/level_next/重播）：清状态并撤掉提示。
func _clear_selection_hint() -> void:
	_selection_slots = []
	_selection_at = -1.0
	_hint_shown = false
	if _board_view != null and _board_view.has_method("clear_hint"):
		_board_view.clear_hint()


## 与 origin 同 entity+level 的全部格子坐标（含 origin 自身）。
func _matching_entity_slots(snapshot: Dictionary, origin: Vector2i) -> Array:
	var slots: Array = []
	var board_v: Variant = snapshot.get("board")
	if typeof(board_v) != TYPE_DICTIONARY:
		return slots
	var cells_v: Variant = (board_v as Dictionary).get("cells")
	if typeof(cells_v) != TYPE_ARRAY:
		return slots
	var cells: Array = cells_v
	var entity := ""
	var level := 0
	var found := false
	for cell_v in cells:
		if typeof(cell_v) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = cell_v
		if _int_field(cell, "x") == origin.x and _int_field(cell, "y") == origin.y:
			entity = _string_field(cell, "entity")
			level = _int_field(cell, "level")
			found = true
			break
	if not found or entity.is_empty():
		return slots
	for cell_v in cells:
		if typeof(cell_v) != TYPE_DICTIONARY:
			continue
		var match_cell: Dictionary = cell_v
		if _string_field(match_cell, "entity") != entity:
			continue
		if _int_field(match_cell, "level") != level:
			continue
		slots.append(Vector2i(_int_field(match_cell, "x"), _int_field(match_cell, "y")))
	return slots


func _current_snapshot() -> Dictionary:
	if _player == null:
		return {}
	var snapshot_v: Variant = _player.current_snapshot()
	if typeof(snapshot_v) == TYPE_DICTIONARY:
		return snapshot_v as Dictionary
	return {}


func _refresh_hud() -> void:
	if _hud == null:
		return
	_hud.refresh(_current_snapshot(), _elapsed)


## order_claim：token 从事件前快照中 mission 首件的格子飞向角色；动画结束后刷新 OrderView。
func _play_claim(event: Dictionary, before_snapshot: Dictionary, after_snapshot: Dictionary) -> void:
	if _board_view == null or _order_view == null:
		return
	var order_id := _string_field(_payload(event), "order")
	var order_def := _find_order_definition(before_snapshot, order_id)
	var target := _first_mission_cell(before_snapshot, order_def)
	if not _is_xy(target):
		_refresh_order_view(after_snapshot)
		return

	var origin: Vector2 = _board_view.cell_center_global(target.x, target.y)
	var coin := _int_field(order_def, "coin")
	var star := _int_field(order_def, "star")
	var generation := _claim_generation
	_order_view.play_claim_sequence(origin, coin, star, func() -> void:
		if generation != _claim_generation:
			return
		_claim_generation += 1
		if _order_view != null:
			_order_view.refresh(after_snapshot)
	)


## 每次外部驱动 OrderView 都递增 generation，旧 claim 回调不会回写过期快照。
func _refresh_order_view(snapshot: Dictionary) -> void:
	if _order_view == null:
		return
	_claim_generation += 1
	_order_view.refresh(snapshot)


func _advance_view() -> void:
	if _player == null:
		return
	var events_v: Variant = _player.events
	if typeof(events_v) != TYPE_ARRAY:
		return
	var events: Array = events_v
	while _view_cursor < events.size():
		var event_v: Variant = events[_view_cursor]
		if typeof(event_v) != TYPE_DICTIONARY:
			_view_cursor += 1
			continue
		var event: Dictionary = event_v
		if _event_at(event) > _elapsed:
			break
		# sim 事件已由 _advance_sim 应用，这里只需跳过。
		if _string_field(event, "channel") == CHANNEL_VIEW and _view_layer != null:
			_view_layer.on_event(event, _player.current_snapshot(), _elapsed)
		_view_cursor += 1


func _restart_demo() -> void:
	if _player == null:
		return
	_claim_generation += 1
	_player.reset()
	_view_cursor = 0
	_elapsed = 0.0
	if _view_layer != null:
		_view_layer.clear()
	var initial := _initial_snapshot()
	if _board_view != null:
		_board_view.refresh(initial)
		_board_view.set_selection([])
		_board_view.set_completed([])
	_clear_selection_hint()
	_refresh_order_view(initial)
	if _hud != null:
		_hud.refresh(initial, 0.0)
	_clear_runtime_error()
	_update_label(0.0)


# ---------------------------------------------------------------------------
# 截图模式
# ---------------------------------------------------------------------------

func _run_capture(path: String, capture_at: float) -> void:
	if capture_at > 0.0:
		_seek_silent(capture_at)
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = null
	var viewport := get_viewport()
	if viewport != null:
		var viewport_texture := viewport.get_texture()
		if viewport_texture != null:
			image = viewport_texture.get_image()
	if image == null:
		push_error("capture 失败：无法获取视口图像 -> %s" % path)
		get_tree().quit(1)
		return
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("capture 保存失败(%s): %s" % [error_string(save_error), path])
		get_tree().quit(1)
		return
	print("capture: %dx%d -> %s" % [image.get_width(), image.get_height(), path])
	get_tree().quit(0)


## 静默 seek：按 player.events 顺序逐条应用 at <= capture_at 的 sim/view 事件。
## 不播 Tween；view_layer 仍收到 on_event/tick，保证截图包含文字等视图效果。
func _seek_silent(capture_at: float) -> void:
	if _player == null:
		return
	var events_v: Variant = _player.events
	if typeof(events_v) == TYPE_ARRAY:
		var events: Array = events_v
		while _view_cursor < events.size():
			var event_v: Variant = events[_view_cursor]
			if typeof(event_v) != TYPE_DICTIONARY:
				_view_cursor += 1
				continue
			var event: Dictionary = event_v
			var at := _event_at(event)
			if at > capture_at:
				break
			var channel := _string_field(event, "channel")
			if channel == CHANNEL_SIM:
				if _player.has_next():
					var before_snapshot: Dictionary = _player.current_snapshot()
					var result_v: Variant = _player.step()
					if typeof(result_v) == TYPE_DICTIONARY:
						_apply_sim_result(result_v as Dictionary, before_snapshot, false)
			elif channel == CHANNEL_VIEW and _view_layer != null:
				_view_layer.on_event(event, _player.current_snapshot(), at)
			_view_cursor += 1
	if _view_layer != null:
		_view_layer.tick(capture_at)
	_elapsed = capture_at
	_refresh_hud()
	_update_label(capture_at)


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
# 启动失败
# ---------------------------------------------------------------------------

## 启动期失败：显示错误 + push_error；截图模式必须退出，否则等待渲染会挂起。
func _fail_start(message: String) -> void:
	push_error(message)
	var label := Label.new()
	label.text = message
	label.position = Vector2(40.0, 40.0)
	label.size = Vector2(1000.0, 240.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color("#ff6b6b"))
	add_child(label)
	if not _capture_path.is_empty() or _render_mode:
		get_tree().quit(1)


func _arg_value(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if String(args[i]) == key and i + 1 < args.size():
			return String(args[i + 1])
	return fallback


func _has_arg(key: String) -> bool:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if String(arg) == key:
			return true
	return false


func _resolve_project_path(path: String) -> String:
	if path.begins_with("res://") or path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


func _first_player_error() -> String:
	if _player == null:
		return "未知错误"
	var errors_v: Variant = _player.errors
	if typeof(errors_v) != TYPE_ARRAY:
		return "未知错误"
	var errors: Array = errors_v
	if errors.is_empty():
		return "未知错误"
	var first_v: Variant = errors[0]
	if typeof(first_v) != TYPE_DICTIONARY:
		var text := str(first_v)
		return text if not text.is_empty() else "未知错误"
	var first: Dictionary = first_v
	var message := _string_field(first, "message")
	if message.is_empty():
		return "未知错误"
	var path := _string_field(first, "path")
	if path.is_empty():
		return message
	return "%s: %s" % [path, message]


# ---------------------------------------------------------------------------
# 运行期错误显示
# ---------------------------------------------------------------------------

func _show_runtime_error(message: String) -> void:
	push_error(message)
	if _error_label != null:
		_error_label.text = message


func _clear_runtime_error() -> void:
	if _error_label != null:
		_error_label.text = ""


# ---------------------------------------------------------------------------
# 数据辅助
# ---------------------------------------------------------------------------

func _update_label(time: float) -> void:
	if _label != null:
		_label.text = "M0 step 4 · t=%.1fs" % time


func _initial_snapshot() -> Dictionary:
	if _player == null:
		return {}
	var snapshot_v: Variant = _player.initial_snapshot
	if typeof(snapshot_v) == TYPE_DICTIONARY:
		return snapshot_v as Dictionary
	return {}


func _event_at(event: Dictionary) -> float:
	var value: Variant = event.get("at_resolved", 0.0)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return 0.0


func _sim_log_entry(result: Dictionary) -> Dictionary:
	if _player == null:
		return {}
	var next_index_v: Variant = result.get("index", 0)
	if not _is_int_like(next_index_v):
		return {}
	var index := int(next_index_v) - 1
	var sim_log_v: Variant = _player.sim_log
	if typeof(sim_log_v) != TYPE_ARRAY:
		return {}
	var sim_log: Array = sim_log_v
	if index < 0 or index >= sim_log.size():
		return {}
	var entry_v: Variant = sim_log[index]
	if typeof(entry_v) == TYPE_DICTIONARY:
		return entry_v as Dictionary
	return {}


func _snapshot_from(result: Dictionary) -> Dictionary:
	var snapshot_v: Variant = result.get("snapshot", {})
	if typeof(snapshot_v) == TYPE_DICTIONARY:
		return snapshot_v as Dictionary
	return {}


func _event_from(result: Dictionary) -> Dictionary:
	var event_v: Variant = result.get("event", {})
	if typeof(event_v) == TYPE_DICTIONARY:
		return event_v as Dictionary
	return {}


func _payload(event: Dictionary) -> Dictionary:
	return _dict_field(event, "payload")


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


## 行优先（y 外层、x 内层）找到 mission 第一件在事件前快照中的格子；找不到返回 (-1,-1)。
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


## mission 全部物品在事件前快照中的格子（multiset，行优先、每格只用一次）。
func _mission_cells(prev_snapshot: Dictionary, order_def: Dictionary) -> Array:
	var result: Array = []
	var mission_v: Variant = order_def.get("mission")
	if typeof(mission_v) != TYPE_ARRAY:
		return result
	var mission: Array = mission_v
	var board_v: Variant = prev_snapshot.get("board")
	if typeof(board_v) != TYPE_DICTIONARY:
		return result
	var cells_v: Variant = (board_v as Dictionary).get("cells")
	if typeof(cells_v) != TYPE_ARRAY:
		return result

	var cells: Array = cells_v
	var used: Dictionary = {}
	for item_v in mission:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var entity := _string_field(item, "entity")
		if entity.is_empty():
			continue
		var item_level := _int_field(item, "level")
		var best := Vector2i(-1, -1)
		for cell_v in cells:
			if typeof(cell_v) != TYPE_DICTIONARY:
				continue
			var cell: Dictionary = cell_v
			var x := _int_field(cell, "x")
			var y := _int_field(cell, "y")
			if used.has("%d,%d" % [x, y]):
				continue
			if _string_field(cell, "entity") != entity:
				continue
			if _int_field(cell, "level") != item_level:
				continue
			if best.x < 0 or y < best.y or (y == best.y and x < best.x):
				best = Vector2i(x, y)
		if _is_xy(best):
			used["%d,%d" % [best.x, best.y]] = true
			result.append(best)
	return result


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


static func _dict_field(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}


static func _xy_from(value: Variant) -> Vector2i:
	if typeof(value) != TYPE_ARRAY:
		return Vector2i(-1, -1)
	var arr: Array = value
	if arr.size() != 2:
		return Vector2i(-1, -1)
	if not _is_int_like(arr[0]) or not _is_int_like(arr[1]):
		return Vector2i(-1, -1)
	return Vector2i(int(arr[0]), int(arr[1]))


static func _is_xy(xy: Vector2i) -> bool:
	return xy.x >= 0 and xy.y >= 0


static func _slot_xy(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		var v: Vector2i = value
		return v
	return _xy_from(value)


static func _is_int_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var f := float(value)
	return is_finite(f) and f == floor(f)


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
