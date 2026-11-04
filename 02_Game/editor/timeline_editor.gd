extends Control

## M0 第 1 周第 5 步：时间轴编辑器（冻结规格 §5.1 时间轴页）。
## 轨道分组 / 绝对与相对锚点编辑 / 预览 / 单步 / 撤销重做 / 保存草稿。
## 事件模型与播放器来自 editor/timeline_model.gd、game/timeline_player.gd（纯逻辑契约）。

const ProjectDoc := preload("res://core/project_doc.gd")
const EventEvaluator := preload("res://core/event_evaluator.gd")
const AssetLoader := preload("res://game/asset_loader.gd")
const BoardView := preload("res://game/board_view.gd")
const OrderView := preload("res://game/order_view.gd")
const TimelineModel := preload("res://editor/timeline_model.gd")
const TimelinePlayer := preload("res://game/timeline_player.gd")
const ViewLayer := preload("res://game/view_layer.gd")

const PROJECT_PATH := "res://data/projects/sample_30s.json"
const DRAFT_URL := "user://timeline_draft.json"
const CHANNELS := ["sim", "view", "audio"]
const TOOLBAR_HEIGHT := 64.0
const LIST_WIDTH := 500.0
const LIST_BOTTOM := 1300.0
const PANEL_TOP := 1300.0
const DESIGN_WIDTH := 1080.0
const DESIGN_HEIGHT := 1920.0
const SELECTED_COLOR := Color(1.0, 0.847, 0.239)
const ERROR_COLOR := Color(1.0, 0.42, 0.42)
const IDLE_TEXT := "播放"
const PLAYING_TEXT := "暂停"

var _model = null
var _player = null
var _project_data: Dictionary = {}
var _selected_index := -1
var _playing := false
var _elapsed := 0.0
var _collapsed: Dictionary = {}
var _row_buttons: Dictionary = {}
var _capture_path := ""

var _board_view = null
var _order_view = null
var _view_layer = null
var _view_cursor := 0           # 下一个待应用的 view 事件在 _player.events 中的下标
var _scroll: ScrollContainer = null
var _list_vbox: VBoxContainer = null
var _time_label: Label = null
var _play_button: Button = null

var _id_edit: LineEdit = null
var _channel_option: OptionButton = null
var _type_option: OptionButton = null
var _at_mode_option: OptionButton = null
var _at_abs_spin: SpinBox = null
var _after_label: Label = null
var _after_edit: LineEdit = null
var _offset_label: Label = null
var _offset_spin: SpinBox = null
var _duration_spin: SpinBox = null
var _track_spin: SpinBox = null
var _order_spin: SpinBox = null
var _payload_edit: TextEdit = null
var _apply_button: Button = null
var _delete_button: Button = null
var _status_label: Label = null
var _error_label: Label = null


func _ready() -> void:
	_apply_ui_font()
	_build_preview()
	_build_toolbar()
	_build_event_list()
	_build_properties()
	_capture_path = _capture_path_from_args()
	if not _load_project():
		if not _capture_path.is_empty():
			get_tree().quit(1)
		return
	if not _capture_path.is_empty():
		await _run_capture(_capture_path)


# ---------------------------------------------------------------------------
# UI 构建
# ---------------------------------------------------------------------------

func _build_preview() -> void:
	_board_view = BoardView.new()
	add_child(_board_view)
	_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_order_view = OrderView.new()
	add_child(_order_view)
	_order_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# view 事件层：全屏叠加在棋盘/订单之上，不拦截编辑器输入。
	_view_layer = ViewLayer.new()
	add_child(_view_layer)
	if _view_layer is Control:
		var view_control := _view_layer as Control
		view_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		view_control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_toolbar() -> void:
	var panel := Panel.new()
	panel.position = Vector2.ZERO
	panel.size = Vector2(DESIGN_WIDTH, TOOLBAR_HEIGHT)
	panel.add_theme_stylebox_override("panel", _make_panel_style(0.95))
	add_child(panel)

	var margin := _make_margin(8, 6, 8, 6)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	margin.add_child(hbox)

	_play_button = _make_button("播放", _on_play_pressed)
	hbox.add_child(_play_button)
	hbox.add_child(_make_button("单步", _on_step_pressed))
	hbox.add_child(_make_button("重置", _on_reset_pressed))
	hbox.add_child(_make_button("撤销", _on_undo_pressed))
	hbox.add_child(_make_button("重做", _on_redo_pressed))
	hbox.add_child(_make_button("保存草稿", _on_save_pressed))

	_time_label = Label.new()
	_time_label.text = "t=0.0 · 0/0 事件"
	_time_label.add_theme_font_size_override("font_size", 20)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.clip_text = true
	hbox.add_child(_time_label)


func _build_event_list() -> void:
	var panel := Panel.new()
	panel.position = Vector2(0.0, TOOLBAR_HEIGHT)
	panel.size = Vector2(LIST_WIDTH, LIST_BOTTOM - TOOLBAR_HEIGHT)
	panel.add_theme_stylebox_override("panel", _make_panel_style(0.86))
	add_child(panel)

	var margin := _make_margin(8, 8, 8, 8)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(margin)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list_vbox)


func _build_properties() -> void:
	var panel := Panel.new()
	panel.position = Vector2(0.0, PANEL_TOP)
	panel.size = Vector2(DESIGN_WIDTH, DESIGN_HEIGHT - PANEL_TOP)
	panel.add_theme_stylebox_override("panel", _make_panel_style(0.93))
	add_child(panel)

	var margin := _make_margin(16, 12, 16, 12)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	vbox.add_child(row1)
	row1.add_child(_make_label("ID"))
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "事件 id"
	_id_edit.custom_minimum_size = Vector2(150.0, 0.0)
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_id_edit)
	row1.add_child(_make_label("通道"))
	_channel_option = OptionButton.new()
	for channel_v in CHANNELS:
		_channel_option.add_item(String(channel_v))
	_channel_option.item_selected.connect(_on_channel_selected)
	row1.add_child(_channel_option)
	row1.add_child(_make_label("类型"))
	_type_option = OptionButton.new()
	_type_option.custom_minimum_size = Vector2(170.0, 0.0)
	_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_type_option)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	vbox.add_child(row2)
	row2.add_child(_make_label("时间"))
	_at_mode_option = OptionButton.new()
	_at_mode_option.add_item("绝对")
	_at_mode_option.add_item("相对 anchor")
	_at_mode_option.item_selected.connect(_on_at_mode_selected)
	row2.add_child(_at_mode_option)

	_at_abs_spin = SpinBox.new()
	_at_abs_spin.min_value = 0.0
	_at_abs_spin.max_value = 86400.0
	_at_abs_spin.step = 0.1
	_at_abs_spin.custom_minimum_size = Vector2(150.0, 0.0)
	_at_abs_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_at_abs_spin)

	_after_label = _make_label("after")
	row2.add_child(_after_label)
	_after_edit = LineEdit.new()
	_after_edit.placeholder_text = "锚点事件 id"
	_after_edit.custom_minimum_size = Vector2(150.0, 0.0)
	_after_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_after_edit)

	_offset_label = _make_label("offset")
	row2.add_child(_offset_label)
	_offset_spin = SpinBox.new()
	_offset_spin.min_value = -86400.0
	_offset_spin.max_value = 86400.0
	_offset_spin.step = 0.1
	_offset_spin.custom_minimum_size = Vector2(120.0, 0.0)
	_offset_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_offset_spin)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	vbox.add_child(row3)
	row3.add_child(_make_label("duration"))
	_duration_spin = SpinBox.new()
	_duration_spin.min_value = 0.0
	_duration_spin.max_value = 86400.0
	_duration_spin.step = 0.1
	_duration_spin.custom_minimum_size = Vector2(120.0, 0.0)
	_duration_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_duration_spin)
	row3.add_child(_make_label("track"))
	_track_spin = SpinBox.new()
	_track_spin.min_value = -100000.0
	_track_spin.max_value = 100000.0
	_track_spin.step = 1.0
	_track_spin.custom_minimum_size = Vector2(120.0, 0.0)
	_track_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_track_spin)
	row3.add_child(_make_label("order"))
	_order_spin = SpinBox.new()
	_order_spin.min_value = -100000.0
	_order_spin.max_value = 100000.0
	_order_spin.step = 1.0
	_order_spin.custom_minimum_size = Vector2(120.0, 0.0)
	_order_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_order_spin)

	vbox.add_child(_make_label("payload (JSON)"))
	_payload_edit = TextEdit.new()
	_payload_edit.custom_minimum_size = Vector2(0.0, 110.0)
	_payload_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_payload_edit.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_payload_edit)

	var row5 := HBoxContainer.new()
	row5.add_theme_constant_override("separation", 12)
	vbox.add_child(row5)
	_apply_button = _make_button("应用修改", _on_apply_pressed)
	_apply_button.disabled = true
	row5.add_child(_apply_button)
	row5.add_child(_make_button("新增事件", _on_add_pressed))
	_delete_button = _make_button("删除事件", _on_delete_pressed)
	_delete_button.disabled = true
	row5.add_child(_delete_button)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.clip_text = true
	row5.add_child(_status_label)

	_error_label = Label.new()
	_error_label.add_theme_font_size_override("font_size", 18)
	_error_label.add_theme_color_override("font_color", ERROR_COLOR)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.custom_minimum_size = Vector2(0.0, 24.0)
	vbox.add_child(_error_label)

	_update_at_mode_visibility()
	_set_properties_enabled(false)


func _apply_ui_font() -> void:
	# 默认主题不一定带中文字形；优先用资源守卫内的 font_zh（PRODUCTION）。
	var loader = AssetLoader.new()
	if not loader.setup("res://assets/assets.json", false):
		return
	var result: Dictionary = loader.load_font("font_zh")
	var font_v: Variant = result.get("font")
	if bool(result.get("ok", false)) and font_v is Font:
		var ui_theme := Theme.new()
		ui_theme.default_font = font_v
		theme = ui_theme


func _make_panel_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.14, alpha)
	style.border_color = Color(1.0, 1.0, 1.0, 0.12)
	style.set_border_width_all(1)
	return style


func _make_margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


func _make_label(text: String, font_size: int = 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, callback: Callable, font_size: int = 20) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(callback)
	return button


# ---------------------------------------------------------------------------
# 加载 / 模型 / 播放器
# ---------------------------------------------------------------------------

func _load_project() -> bool:
	_clear_error()
	_set_status("")
	_model = TimelineModel.new()
	var loaded := false
	var load_v: Variant = _model.load_file(PROJECT_PATH)
	if typeof(load_v) == TYPE_BOOL:
		loaded = bool(load_v)
	if not loaded:
		_set_error(_model_error_text("项目加载失败: %s" % PROJECT_PATH))
		return false

	var data_v: Variant = _model.project_data
	if typeof(data_v) == TYPE_DICTIONARY:
		_project_data = data_v
	if _project_data.is_empty():
		_set_error("项目数据为空: %s" % PROJECT_PATH)
		return false

	if not _rebuild_player():
		return false
	_setup_views()
	_rebuild_event_list()
	_populate_properties()
	_refresh_to_player()
	_update_time_label()
	return true


func _rebuild_player() -> bool:
	_player = null
	_playing = false
	_elapsed = 0.0
	_reset_view_layer()
	if _play_button != null:
		_play_button.text = IDLE_TEXT
	if _model == null:
		return false

	var doc = ProjectDoc.new()
	doc.from_dict(_copy_project_data())
	var player = TimelinePlayer.new()
	_player = player
	var setup_v: Variant = player.setup(doc)
	var ok := typeof(setup_v) == TYPE_BOOL and bool(setup_v)
	if not ok:
		_set_error(_player_error_text("播放器初始化失败"))
		return false
	return true


func _copy_project_data() -> Dictionary:
	if _model == null:
		return {}
	var data_v: Variant = _model.project_data
	if typeof(data_v) == TYPE_DICTIONARY:
		return (data_v as Dictionary).duplicate(true)
	return {}


func _setup_views() -> void:
	if _board_view == null or _order_view == null:
		return
	var snapshot := _player_current_snapshot()
	_board_view.setup(_project_data, snapshot, [], [], true)
	_order_view.setup(_project_data, snapshot, true)
	_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _view_layer != null:
		_view_layer.setup(_project_data, _board_view, _order_view)


func _refresh_to_player() -> void:
	_refresh_views(_player_current_snapshot())


func _refresh_views(snapshot: Dictionary) -> void:
	if _board_view == null or _order_view == null:
		return
	_board_view.refresh(snapshot)
	_order_view.refresh(snapshot)


func _after_model_change() -> void:
	if _model == null:
		return
	_clear_error()
	_set_status("")
	# 模型提交后可能已替换 project_data（撤销/重做/编辑），views 必须用新数据重建。
	var data_v: Variant = _model.project_data
	if typeof(data_v) == TYPE_DICTIONARY:
		_project_data = data_v
	if _selected_index >= 0 and _selected_index >= _event_count():
		_selected_index = -1
	_rebuild_player()
	_setup_views()
	_rebuild_event_list()
	_populate_properties()
	_refresh_to_player()
	_sync_view_events(maxf(_last_applied_time(), 0.0))
	_update_time_label()


func _update_time_label() -> void:
	if _time_label == null:
		return
	# player.last_applied_time() 在未应用任何事件时返回 -1.0（哨兵值），显示时按 0 处理。
	var t := maxf(_last_applied_time(), 0.0)
	var applied := _applied_count()
	var total := _sim_event_count()
	_time_label.text = "t=%.1f · %d/%d 事件" % [t, applied, total]


# ---------------------------------------------------------------------------
# 事件列表（channel -> track 分组，可折叠）
# ---------------------------------------------------------------------------

func _rebuild_event_list() -> void:
	if _list_vbox == null:
		return
	var saved_scroll := 0
	if _scroll != null:
		saved_scroll = _scroll.scroll_vertical
	_row_buttons.clear()
	_clear_children(_list_vbox)

	var timeline := _timeline()
	if timeline.is_empty():
		var empty_label := _make_label("（无事件）", 18)
		empty_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
		_list_vbox.add_child(empty_label)
		return

	var resolved_by_id := _resolved_times_by_id(timeline)
	var groups: Array = []
	var group_by_key: Dictionary = {}
	for i in range(timeline.size()):
		var event: Dictionary = {}
		var entry_v: Variant = timeline[i]
		if typeof(entry_v) == TYPE_DICTIONARY:
			event = entry_v
		var channel := _string_field(event, "channel")
		if channel.is_empty():
			channel = "?"
		var track := _int_field(event, "track")
		var key := "%s|%d" % [channel, track]
		if not group_by_key.has(key):
			var group := {"key": key, "channel": channel, "track": track, "indices": []}
			group_by_key[key] = group
			groups.append(group)
		var group_v: Variant = group_by_key[key]
		if typeof(group_v) == TYPE_DICTIONARY:
			var indices_v: Variant = (group_v as Dictionary).get("indices")
			if typeof(indices_v) == TYPE_ARRAY:
				(indices_v as Array).append(i)
	groups.sort_custom(_group_sort)

	for group_v in groups:
		if typeof(group_v) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = group_v
		var key := String(group.get("key", ""))
		var channel := String(group.get("channel", "?"))
		var track := int(group.get("track", 0))
		var indices: Array = []
		var indices_v: Variant = group.get("indices", [])
		if typeof(indices_v) == TYPE_ARRAY:
			indices = indices_v
		var collapsed := bool(_collapsed.get(key, false))
		var header := _make_button(
			"%s · track %d (%d)" % [channel, track, indices.size()],
			_on_group_toggled.bind(key)
		)
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_list_vbox.add_child(header)
		if collapsed:
			continue

		for index_v in indices:
			var index := int(index_v)
			var event: Dictionary = {}
			var entry_v: Variant = timeline[index]
			if typeof(entry_v) == TYPE_DICTIONARY:
				event = entry_v
			var event_id := _string_field(event, "id")
			var type_text := _string_field(event, "type")
			var resolved_text := "?"
			if resolved_by_id.has(event_id):
				resolved_text = "%.1f" % float(resolved_by_id[event_id])
			var id_text := "?" if event_id.is_empty() else event_id
			var type_show := "?" if type_text.is_empty() else type_text
			var row_text := "%s · %s · t=%s" % [id_text, type_show, resolved_text]
			var row := _make_button(row_text, _on_event_row_pressed.bind(index), 18)
			row.flat = true
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.custom_minimum_size = Vector2(0.0, 32.0)
			_apply_row_selected(row, index == _selected_index)
			_list_vbox.add_child(row)
			_row_buttons[index] = row

	if _scroll != null:
		_scroll.set_deferred("scroll_vertical", saved_scroll)


func _group_sort(a: Dictionary, b: Dictionary) -> bool:
	var priority_a := _channel_order(String(a.get("channel", "")))
	var priority_b := _channel_order(String(b.get("channel", "")))
	if priority_a != priority_b:
		return priority_a < priority_b
	var track_a := int(a.get("track", 0))
	var track_b := int(b.get("track", 0))
	if track_a != track_b:
		return track_a < track_b
	return String(a.get("channel", "")) < String(b.get("channel", ""))


func _channel_order(channel: String) -> int:
	var index := CHANNELS.find(channel)
	return index if index >= 0 else 99


func _resolved_times_by_id(timeline: Array) -> Dictionary:
	var evaluator = EventEvaluator.new()
	evaluator.evaluate(timeline)
	var resolved := {}
	for event_v in evaluator.events:
		if typeof(event_v) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_v
		var event_id := _string_field(event, "id")
		if event_id.is_empty():
			continue
		resolved[event_id] = _number_value(event.get("at_resolved"), 0.0)
	return resolved


func _on_group_toggled(key: String) -> void:
	_collapsed[key] = not bool(_collapsed.get(key, false))
	_rebuild_event_list()


func _on_event_row_pressed(index: int) -> void:
	if _model == null:
		return
	if index < 0 or index >= _event_count():
		return
	_selected_index = index
	for index_v in _row_buttons.keys():
		var row_v: Variant = _row_buttons[index_v]
		if row_v is Button and is_instance_valid(row_v):
			_apply_row_selected(row_v, int(index_v) == index)
	_populate_properties()
	_clear_error()


func _apply_row_selected(row: Button, selected: bool) -> void:
	if selected:
		row.add_theme_color_override("font_color", SELECTED_COLOR)
		row.add_theme_color_override("font_hover_color", SELECTED_COLOR.lightened(0.15))
		row.add_theme_color_override("font_pressed_color", SELECTED_COLOR)
	else:
		row.remove_theme_color_override("font_color")
		row.remove_theme_color_override("font_hover_color")
		row.remove_theme_color_override("font_pressed_color")


# ---------------------------------------------------------------------------
# 属性面板
# ---------------------------------------------------------------------------

func _populate_properties() -> void:
	var has_selection := _model != null and _selected_index >= 0 and _selected_index < _event_count()
	var event: Dictionary = {}
	if has_selection:
		var event_v: Variant = _model.get_event(_selected_index)
		if typeof(event_v) == TYPE_DICTIONARY:
			event = event_v
		if event.is_empty():
			has_selection = false
	_set_properties_enabled(has_selection)
	if not has_selection:
		_clear_properties()
		return

	_id_edit.text = _string_field(event, "id")
	var channel := _string_field(event, "channel")
	_select_option_text(_channel_option, channel, false)
	_rebuild_type_options(channel, _string_field(event, "type"))

	var at_v: Variant = event.get("at")
	if typeof(at_v) == TYPE_DICTIONARY:
		_at_mode_option.select(1)
		var anchor: Dictionary = at_v
		_after_edit.text = _string_field(anchor, "after")
		_offset_spin.value = _float_field(anchor, "offset", 0.0)
		_at_abs_spin.value = 0.0
	else:
		_at_mode_option.select(0)
		_at_abs_spin.value = _number_value(at_v, 0.0)
		_after_edit.text = ""
		_offset_spin.value = 0.0
	_update_at_mode_visibility()

	_duration_spin.value = _float_field(event, "duration", 0.0)
	_track_spin.value = float(_int_field(event, "track"))
	_order_spin.value = float(_int_field(event, "order"))

	var payload_v: Variant = event.get("payload")
	if typeof(payload_v) == TYPE_DICTIONARY:
		_payload_edit.text = JSON.stringify(payload_v, "  ")
	elif payload_v == null:
		_payload_edit.text = "{}"
	else:
		_payload_edit.text = JSON.stringify(payload_v, "  ")


func _clear_properties() -> void:
	_id_edit.text = ""
	_channel_option.select(0)
	_type_option.clear()
	_at_mode_option.select(0)
	_at_abs_spin.value = 0.0
	_after_edit.text = ""
	_offset_spin.value = 0.0
	_duration_spin.value = 0.0
	_track_spin.value = 0.0
	_order_spin.value = 0.0
	_payload_edit.text = ""
	_update_at_mode_visibility()


func _set_properties_enabled(enabled: bool) -> void:
	_id_edit.editable = enabled
	_channel_option.disabled = not enabled
	_type_option.disabled = not enabled
	_at_mode_option.disabled = not enabled
	_at_abs_spin.editable = enabled
	_after_edit.editable = enabled
	_offset_spin.editable = enabled
	_duration_spin.editable = enabled
	_track_spin.editable = enabled
	_order_spin.editable = enabled
	_payload_edit.editable = enabled
	_apply_button.disabled = not enabled
	_delete_button.disabled = not enabled


func _update_at_mode_visibility() -> void:
	if _at_mode_option == null:
		return
	var absolute := _at_mode_option.selected != 1
	if _at_abs_spin != null:
		_at_abs_spin.visible = absolute
	if _after_label != null:
		_after_label.visible = not absolute
	if _after_edit != null:
		_after_edit.visible = not absolute
	if _offset_label != null:
		_offset_label.visible = not absolute
	if _offset_spin != null:
		_offset_spin.visible = not absolute


func _on_at_mode_selected(_index: int) -> void:
	_update_at_mode_visibility()


func _on_channel_selected(index: int) -> void:
	if _channel_option == null:
		return
	if index < 0 or index >= _channel_option.item_count:
		return
	_rebuild_type_options(_channel_option.get_item_text(index), "")


func _rebuild_type_options(channel: String, current_type: String) -> void:
	if _type_option == null:
		return
	_type_option.clear()
	for type_v in _types_for_channel(channel):
		_type_option.add_item(String(type_v))
	if not current_type.is_empty():
		var found := false
		for i in range(_type_option.item_count):
			if _type_option.get_item_text(i) == current_type:
				found = true
				break
		if not found:
			_type_option.add_item(current_type)
	if _type_option.item_count == 0:
		return
	for i in range(_type_option.item_count):
		if _type_option.get_item_text(i) == current_type:
			_type_option.select(i)
			return
	_type_option.select(0)


func _types_for_channel(channel: String) -> Array:
	match channel:
		"sim":
			return EventEvaluator.SIM_TYPES
		"view":
			return EventEvaluator.VIEW_TYPES
		"audio":
			return EventEvaluator.AUDIO_TYPES
	return []


func _select_option_text(option: OptionButton, text: String, add_if_missing: bool) -> void:
	for i in range(option.item_count):
		if option.get_item_text(i) == text:
			option.select(i)
			return
	if add_if_missing and not text.is_empty():
		option.add_item(text)
		option.select(option.item_count - 1)
		return
	if option.item_count > 0:
		option.select(0)


# ---------------------------------------------------------------------------
# 工具栏行为
# ---------------------------------------------------------------------------

func _on_play_pressed() -> void:
	if _player == null:
		return
	if _playing:
		_stop_playing()
		return
	if not _has_next():
		_set_status("已到末尾")
		return
	# 继续播放时保留已走过的时钟（只前进不回拨），避免暂停后播放跳回上一事件时间。
	_elapsed = maxf(_elapsed, maxf(_last_applied_time(), 0.0))
	_playing = true
	_play_button.text = PLAYING_TEXT
	_clear_error()


func _on_step_pressed() -> void:
	if _player == null:
		return
	_stop_playing()
	var result := _step_player()
	if result.is_empty():
		_set_error("单步失败")
		return
	var snapshot: Dictionary = {}
	var snapshot_v: Variant = result.get("snapshot", {})
	if typeof(snapshot_v) == TYPE_DICTIONARY:
		snapshot = snapshot_v
	if not snapshot.is_empty():
		_refresh_views(snapshot)
	var ok := bool(result.get("ok", false))
	var done := bool(result.get("done", false))
	# 失败事件同样推进到预计算快照；view 事件与选中仍按已到时间同步。
	if not done:
		_apply_selection_for_event(_event_from_result(result))
		_sync_view_events(maxf(_last_applied_time(), 0.0))
	if ok:
		_clear_error()
	elif done:
		_set_status("已到末尾")
	else:
		_set_error(_step_failure_text(result))
	_update_time_label()


func _on_reset_pressed() -> void:
	if _player == null:
		return
	_stop_playing()
	_player.reset()
	_elapsed = 0.0
	_reset_view_layer()
	_set_board_selection([])
	_refresh_to_player()
	_sync_view_events(maxf(_last_applied_time(), 0.0))
	_update_time_label()
	_clear_error()
	_set_status("已重置")


func _on_undo_pressed() -> void:
	if _model == null:
		return
	if not _bool_result(_model.can_undo()):
		_set_status("没有可撤销的操作")
		return
	if not _bool_result(_model.undo()):
		_set_error(_model_error_text("撤销失败"))
		return
	_after_model_change()
	_set_status("已撤销")


func _on_redo_pressed() -> void:
	if _model == null:
		return
	if not _bool_result(_model.can_redo()):
		_set_status("没有可重做的操作")
		return
	if not _bool_result(_model.redo()):
		_set_error(_model_error_text("重做失败"))
		return
	_after_model_change()
	_set_status("已重做")


func _on_save_pressed() -> void:
	if _model == null:
		return
	if not _bool_result(_model.save_draft()):
		_set_error(_model_error_text("草稿保存失败"))
		return
	_clear_error()
	_set_status("草稿已保存 %s" % DRAFT_URL)


func _on_apply_pressed() -> void:
	if _model == null or _selected_index < 0:
		return
	if _selected_index >= _event_count():
		return

	var json := JSON.new()
	var parse_error := json.parse(_payload_edit.text)
	if parse_error != OK:
		_set_error("payload JSON 解析失败（第 %d 行）: %s" % [json.get_error_line(), json.get_error_message()])
		return
	var payload: Variant = json.data
	if typeof(payload) != TYPE_DICTIONARY:
		_set_error("payload 必须是 JSON 对象（Dictionary）")
		return

	var channel := ""
	var channel_index := _channel_option.selected
	if channel_index >= 0 and channel_index < _channel_option.item_count:
		channel = _channel_option.get_item_text(channel_index)
	var type_text := ""
	var type_index := _type_option.selected
	if type_index >= 0 and type_index < _type_option.item_count:
		type_text = _type_option.get_item_text(type_index)

	var at_value: Variant = 0.0
	if _at_mode_option.selected == 1:
		var anchor := _after_edit.text.strip_edges()
		if anchor.is_empty():
			_set_error("相对锚点必须填写 after 事件 id")
			return
		at_value = {"after": anchor, "offset": _offset_spin.value}
	else:
		at_value = _at_abs_spin.value

	var event := {
		"id": _id_edit.text.strip_edges(),
		"channel": channel,
		"type": type_text,
		"at": at_value,
		"payload": payload,
	}
	if _duration_spin.value > 0.0:
		event["duration"] = _duration_spin.value
	var track := int(round(_track_spin.value))
	if track != 0:
		event["track"] = track
	var order := int(round(_order_spin.value))
	if order != 0:
		event["order"] = order

	if not _bool_result(_model.update_event(_selected_index, event)):
		_set_error(_model_error_text("更新事件失败"))
		return
	_after_model_change()
	_set_status("已应用修改")


func _on_add_pressed() -> void:
	if _model == null:
		return
	var new_event := {
		"id": _model.next_event_id(),
		"channel": "sim",
		"type": "tap",
		"at": 0.0,
		"payload": {},
	}
	if not _bool_result(_model.add_event(new_event)):
		_set_error(_model_error_text("新增事件失败"))
		return
	_selected_index = _event_count() - 1
	_after_model_change()
	_set_status("已新增事件")


func _on_delete_pressed() -> void:
	if _model == null or _selected_index < 0:
		return
	if not _bool_result(_model.delete_event(_selected_index)):
		_set_error(_model_error_text("删除事件失败"))
		return
	_selected_index = -1
	_after_model_change()
	_set_status("已删除事件")


# ---------------------------------------------------------------------------
# 播放 / 单步驱动
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _playing or _player == null:
		return
	_elapsed += delta
	var stepped := false
	var guard := 0
	while _has_next() and _next_event_time() <= _elapsed + 0.000001:
		guard += 1
		if guard > 4096:
			_stop_playing()
			_set_error("播放步进异常：事件未推进")
			return
		var result := _step_player()
		if result.is_empty():
			_stop_playing()
			_set_error("播放步进失败")
			return
		if not bool(result.get("ok", false)):
			_stop_playing()
			if bool(result.get("done", false)):
				_set_status("已到末尾")
			else:
				_set_error(_step_failure_text(result))
			_update_time_label()
			return
		var snapshot: Dictionary = {}
		var snapshot_v: Variant = result.get("snapshot", {})
		if typeof(snapshot_v) == TYPE_DICTIONARY:
			snapshot = snapshot_v
		_refresh_views(snapshot)
		_apply_selection_for_event(_event_from_result(result))
		stepped = true
		if bool(result.get("done", false)):
			break
	# view 事件按时间推进（每帧 tick 以驱动层内动画）。
	_sync_view_events(_elapsed)
	if stepped:
		_update_time_label()
	if not _has_next():
		_stop_playing()
		_update_time_label()


func _stop_playing() -> void:
	_playing = false
	if _play_button != null:
		_play_button.text = IDLE_TEXT


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if not key_event.ctrl_pressed:
		return
	if key_event.keycode == KEY_Z:
		if key_event.shift_pressed:
			_on_redo_pressed()
		else:
			_on_undo_pressed()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_Y:
		_on_redo_pressed()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 截图模式
# ---------------------------------------------------------------------------

func _capture_path_from_args() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if String(args[i]) == "--capture" and i + 1 < args.size():
			return String(args[i + 1])
	return ""


func _run_capture(path: String) -> void:
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


# ---------------------------------------------------------------------------
# 模型 / 播放器访问与通用工具
# ---------------------------------------------------------------------------

func _timeline() -> Array:
	if _model == null:
		return []
	var timeline_v: Variant = _model.timeline()
	if typeof(timeline_v) == TYPE_ARRAY:
		return timeline_v
	return []


func _event_count() -> int:
	if _model == null:
		return 0
	return int(_number_value(_model.event_count(), 0.0))


func _has_next() -> bool:
	if _player == null:
		return false
	var value: Variant = _player.has_next()
	return bool(value) if typeof(value) == TYPE_BOOL else false


func _next_event_time() -> float:
	if _player == null:
		return 0.0
	return _number_value(_player.next_event_time(), 0.0)


func _last_applied_time() -> float:
	if _player == null:
		return 0.0
	return _number_value(_player.last_applied_time(), 0.0)


func _applied_count() -> int:
	if _player == null:
		return 0
	return int(_number_value(_player.applied_count(), 0.0))


func _sim_event_count() -> int:
	if _player == null:
		return 0
	return int(_number_value(_player.sim_event_count(), 0.0))


func _player_current_snapshot() -> Dictionary:
	if _player == null:
		return {}
	var snapshot_v: Variant = _player.current_snapshot()
	if typeof(snapshot_v) == TYPE_DICTIONARY:
		return snapshot_v
	return {}


func _step_player() -> Dictionary:
	if _player == null:
		return {}
	var result_v: Variant = _player.step()
	if typeof(result_v) == TYPE_DICTIONARY:
		return result_v
	return {}


## 把 at_resolved <= now 的 view 事件依次交给 view_layer，并把 view 层 tick 到 now。
## 游标只前进；重置/重建播放器时由 _reset_view_layer() 归零。
func _sync_view_events(now: float) -> void:
	if _view_layer == null or _player == null:
		return
	var events_v: Variant = _player.events
	if typeof(events_v) != TYPE_ARRAY:
		return
	var events: Array = events_v
	var snapshot := _player_current_snapshot()
	while _view_cursor < events.size():
		var event_v: Variant = events[_view_cursor]
		if typeof(event_v) != TYPE_DICTIONARY:
			_view_cursor += 1
			continue
		var event: Dictionary = event_v
		if _event_at(event) > now:
			break
		_view_cursor += 1
		if _string_field(event, "channel") != "view":
			continue
		_view_layer.on_event(event, snapshot, now)
	_view_layer.tick(now)


## 清空 view 层并回到事件游标起点（重置 / 播放器重建时调用）。
func _reset_view_layer() -> void:
	_view_cursor = 0
	if _view_layer != null:
		_view_layer.clear()


## 依据已应用的 sim 事件驱动棋盘选中：tap 选中 target.slot；merge/drag 选中 to；
## order_claim/level_next 清空；其余类型保持现状（deliver 暂不处理完成标记）。
func _apply_selection_for_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var payload := _payload_of(event)
	match _string_field(event, "type"):
		"tap":
			var target_v: Variant = payload.get("target")
			if typeof(target_v) == TYPE_DICTIONARY:
				var slot := _xy_or_empty((target_v as Dictionary).get("slot"))
				if not slot.is_empty():
					_set_board_selection([slot])
		"merge", "drag":
			var to := _xy_or_empty(payload.get("to"))
			if not to.is_empty():
				_set_board_selection([to])
		"order_claim", "level_next":
			_set_board_selection([])


func _set_board_selection(selection: Array) -> void:
	if _board_view == null:
		return
	if not _board_view.has_method("set_selection"):
		return
	_board_view.set_selection(selection)


func _step_failure_text(result: Dictionary) -> String:
	var event := _event_from_result(result)
	var event_id := _string_field(event, "id")
	if event_id.is_empty():
		event_id = "?"
	var message := _string_field(result, "message")
	if message.is_empty():
		message = "未知错误"
	return "事件 %s 失败: %s" % [event_id, message]


func _model_error_text(fallback: String) -> String:
	if _model != null:
		var errors_v: Variant = _model.last_errors
		if typeof(errors_v) == TYPE_ARRAY:
			var errors: Array = errors_v
			if not errors.is_empty():
				return _error_entry_text(errors[0], fallback)
	return fallback


func _player_error_text(fallback: String) -> String:
	if _player == null:
		return fallback
	var errors_v: Variant = _player.errors
	if typeof(errors_v) != TYPE_ARRAY:
		return fallback
	var errors: Array = errors_v
	if errors.is_empty():
		return fallback
	return _error_entry_text(errors[0], fallback)


func _error_entry_text(entry_v: Variant, fallback: String) -> String:
	if typeof(entry_v) == TYPE_DICTIONARY:
		var entry: Dictionary = entry_v
		var path := _string_field(entry, "path")
		var message := _string_field(entry, "message")
		if message.is_empty():
			return fallback
		if path.is_empty():
			return message
		return "%s: %s" % [path, message]
	var text := str(entry_v)
	return text if not text.is_empty() else fallback


func _set_error(text: String) -> void:
	if _error_label != null:
		_error_label.text = text


func _clear_error() -> void:
	if _error_label != null:
		_error_label.text = ""


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func _bool_result(value: Variant) -> bool:
	return bool(value) if typeof(value) == TYPE_BOOL else false


static func _number_value(value: Variant, fallback: float) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return fallback


static func _event_from_result(result: Dictionary) -> Dictionary:
	var event_v: Variant = result.get("event", {})
	if typeof(event_v) == TYPE_DICTIONARY:
		var event: Dictionary = event_v
		return event
	return {}


static func _event_at(event: Dictionary) -> float:
	return _number_value(event.get("at_resolved"), 0.0)


static func _payload_of(event: Dictionary) -> Dictionary:
	var payload_v: Variant = event.get("payload", {})
	if typeof(payload_v) == TYPE_DICTIONARY:
		var payload: Dictionary = payload_v
		return payload
	return {}


## [x, y] 且两元素均为 int-like 才返回数组；否则返回 []。
static func _xy_or_empty(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	var arr: Array = value
	if arr.size() != 2:
		return []
	if not _is_int_like(arr[0]) or not _is_int_like(arr[1]):
		return []
	return [int(arr[0]), int(arr[1])]


static func _is_int_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		return is_finite(f) and f == floor(f)
	return false


static func _float_field(source: Dictionary, key: String, fallback: float = 0.0) -> float:
	var value: Variant = source.get(key)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return fallback


static func _int_field(source: Dictionary, key: String) -> int:
	var value: Variant = source.get(key)
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f) and f == floor(f):
			return int(f)
	return 0


static func _string_field(source: Dictionary, key: String, fallback: String = "") -> String:
	var value: Variant = source.get(key)
	if typeof(value) == TYPE_STRING:
		return String(value)
	return fallback
