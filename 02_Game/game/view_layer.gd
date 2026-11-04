extends Control

## M0 第 1 周第 5 步：View 通道事件层。
## 统一消费时间轴上 channel=="view" 的事件：横幅文字（text / cta / levelup）、
## 棋盘选中（select / highlight）、停留提示（hint）、角色与奖励动画（character_leave /
## character_next / star_fly / coin_popup），以及棋盘已满 toast（show_board_full）。
## 供 main 实时播放与编辑器预览共用。
## 只依赖注入的 project_data / board_view / order_view；空引用与空 payload 全部安全忽略。

const AssetLoader := preload("res://game/asset_loader.gd")

const MAIN_RECT := Rect2(0.0, 560.0, 1080.0, 120.0)
const CTA_RECT := Rect2(0.0, 1560.0, 1080.0, 120.0)
const BOARD_FULL_RECT := Rect2(284.0, 1000.0, 512.0, 128.0)
const MAIN_FONT_SIZE := 64
const CTA_FONT_SIZE := 56
const BOARD_FULL_FONT_SIZE := 48
const DEFAULT_TEXT_SECONDS := 2.0
const DEFAULT_LEVELUP_SECONDS := 1.5
const DEFAULT_HINT_SECONDS := 2.0
const BOARD_FULL_SECONDS := 1.5
const BOARD_FULL_TEXT_KEY := "board.full"
const BOARD_FULL_FALLBACK := "棋盘已满"
const LEVELUP_FALLBACK := "LEVEL UP"
const LEVELUP_TEXT_KEY := "levelup"

var project_data: Dictionary = {}
var board_view = null
var order_view = null
var loader = null
var theme_doc = null

var _main_label: Label = null
var _cta_label: Label = null
var _board_full: Control = null
var _main_hide_at := -1.0
var _cta_hide_at := -1.0
var _board_full_until := -1.0
var _hint_until := -1.0
var _now := 0.0
var _main_text_key := ""
var _cta_text_key := ""
var _show_seq := 0
var _main_show_seq := 0
var _cta_show_seq := 0


func setup(project_data_arg: Dictionary, board_view_arg, order_view_arg, theme_arg = null) -> void:
	project_data = project_data_arg
	board_view = board_view_arg
	order_view = order_view_arg
	theme_doc = theme_arg
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	loader = AssetLoader.new()
	loader.setup("res://assets/assets.json", true)

	_main_label = _ensure_label(_main_label, MAIN_RECT, MAIN_FONT_SIZE)
	_cta_label = _ensure_label(_cta_label, CTA_RECT, CTA_FONT_SIZE)
	var font := _ui_font()
	if font != null:
		_main_label.add_theme_font_override("font", font)
		_cta_label.add_theme_font_override("font", font)
	_board_full = _ensure_board_full_toast(_board_full)
	clear()


@warning_ignore("unused_parameter")
func on_event(event: Dictionary, snapshot: Dictionary, now: float) -> void:
	if event.is_empty():
		return
	var payload_v: Variant = event.get("payload")
	var payload: Dictionary = {}
	if typeof(payload_v) == TYPE_DICTIONARY:
		payload = payload_v
	match _string_field(event, "type"):
		"text":
			_handle_text(event, payload, now)
		"cta":
			_handle_cta(event, payload, now)
		"levelup":
			_handle_levelup(event, now)
		"select":
			_handle_select(payload_v, payload)
		"highlight":
			_handle_highlight(payload_v, payload)
		"hint":
			_handle_hint(payload_v, payload, event, now)
		"star_fly", "coin_popup":
			_handle_reward(payload)
		"character_leave":
			if _valid_object(order_view) and order_view.has_method("play_character_leave"):
				order_view.play_character_leave()
		"character_next":
			if _valid_object(order_view) and order_view.has_method("play_character_next"):
				order_view.play_character_next()


func tick(now: float) -> void:
	_now = now
	if _valid_object(_board_full) and _board_full.visible and _board_full_until >= 0.0 and now >= _board_full_until:
		_board_full.visible = false
		_board_full_until = -1.0
	if _hint_until >= 0.0 and now >= _hint_until:
		_hint_until = -1.0
		_clear_board_hint()
	if _valid_object(_main_label) and _main_label.visible and _main_hide_at >= 0.0 and now >= _main_hide_at:
		_main_label.visible = false
		_main_label.text = ""
		_main_text_key = ""
		_main_hide_at = -1.0
	if _valid_object(_cta_label) and _cta_label.visible and _cta_hide_at >= 0.0 and now >= _cta_hide_at:
		_cta_label.visible = false
		_cta_label.text = ""
		_cta_text_key = ""
		_cta_hide_at = -1.0


## 棋盘已满 toast：显示约 1.5 秒，由 tick 到期隐藏。
func show_board_full() -> void:
	_board_full_until = _now + BOARD_FULL_SECONDS
	if not _valid_object(_board_full):
		return
	_board_full.visible = true


func board_full_visible() -> bool:
	return _valid_object(_board_full) and _board_full.visible


func clear() -> void:
	if _valid_object(_main_label):
		_main_label.text = ""
		_main_label.visible = false
	if _valid_object(_cta_label):
		_cta_label.text = ""
		_cta_label.visible = false
	if _valid_object(_board_full):
		_board_full.visible = false
	_main_hide_at = -1.0
	_cta_hide_at = -1.0
	_board_full_until = -1.0
	_hint_until = -1.0
	_main_text_key = ""
	_cta_text_key = ""
	_clear_board_hint()


func current_text() -> String:
	var label := _top_visible_label()
	if label == null:
		return ""
	return label.text


func active_text_key() -> String:
	var label := _top_visible_label()
	if label == null:
		return ""
	if label == _main_label:
		return _main_text_key
	return _cta_text_key


## 仍在显示的两个横幅中，取最近一次事件显示的那个。
func _top_visible_label() -> Label:
	var main_visible := _valid_object(_main_label) and _main_label.visible
	var cta_visible := _valid_object(_cta_label) and _cta_label.visible
	if main_visible and (not cta_visible or _main_show_seq >= _cta_show_seq):
		return _main_label
	if cta_visible:
		return _cta_label
	return null


# ---------------------------------------------------------------------------
# 事件处理
# ---------------------------------------------------------------------------

func _handle_text(event: Dictionary, payload: Dictionary, now: float) -> void:
	var text_key := _string_field(payload, "text_key")
	if text_key.is_empty():
		return
	_show_main(_resolve_text(text_key), text_key, now + _event_duration(event, DEFAULT_TEXT_SECONDS))


func _handle_cta(event: Dictionary, payload: Dictionary, now: float) -> void:
	var text_key := _string_field(payload, "text_key")
	if text_key.is_empty():
		return
	_show_cta(_resolve_text(text_key), text_key, now + _event_duration(event, DEFAULT_TEXT_SECONDS))


func _handle_levelup(event: Dictionary, now: float) -> void:
	var text := _localized_text(LEVELUP_TEXT_KEY)
	if text.is_empty():
		text = LEVELUP_FALLBACK
	_show_main(text, LEVELUP_TEXT_KEY, now + _event_duration(event, DEFAULT_LEVELUP_SECONDS))


func _handle_select(payload_raw: Variant, payload: Dictionary) -> void:
	var slot: Array = []
	var slot_v: Variant = payload.get("slot")
	if slot_v != null:
		slot = _normalize_slot(slot_v)
	if slot.is_empty():
		slot = _normalize_slot(payload_raw)
	if slot.is_empty():
		return
	_set_board_selection([slot])


func _handle_highlight(payload_raw: Variant, payload: Dictionary) -> void:
	var slots: Array = []
	var slots_v: Variant = payload.get("slots")
	if typeof(slots_v) == TYPE_ARRAY:
		slots = _normalize_slots_array(slots_v as Array)
	if slots.is_empty():
		var slot_v: Variant = payload.get("slot")
		if slot_v != null:
			var single := _normalize_slot(slot_v)
			if not single.is_empty():
				slots = [single]
	if slots.is_empty() and typeof(payload_raw) == TYPE_ARRAY:
		var raw: Array = payload_raw
		if raw.size() >= 2 and _is_number(raw[0]) and _is_number(raw[1]):
			slots = [_normalize_slot(raw)]
		else:
			slots = _normalize_slots_array(raw)
	if slots.is_empty():
		return
	_set_board_selection(slots)


## hint：提取 slots（{slots:[[x,y],...]} / {slot:[x,y]} / 裸数组），交给棋盘视图停留提示。
func _handle_hint(payload_raw: Variant, payload: Dictionary, event: Dictionary, now: float) -> void:
	var slots: Array = []
	var slots_v: Variant = payload.get("slots")
	if typeof(slots_v) == TYPE_ARRAY:
		slots = _normalize_slots_array(slots_v as Array)
	if slots.is_empty():
		var slot_v: Variant = payload.get("slot")
		if slot_v != null:
			var single := _normalize_slot(slot_v)
			if not single.is_empty():
				slots = [single]
	if slots.is_empty() and typeof(payload_raw) == TYPE_ARRAY:
		var raw: Array = payload_raw
		if raw.size() >= 2 and _is_number(raw[0]) and _is_number(raw[1]):
			slots = [_normalize_slot(raw)]
		else:
			slots = _normalize_slots_array(raw)
	if slots.is_empty():
		return
	if _valid_object(board_view) and board_view.has_method("set_hint_slots"):
		board_view.set_hint_slots(slots)
	_hint_until = now + _event_duration(event, DEFAULT_HINT_SECONDS)


## star_fly / coin_popup：coin 优先取 payload.amount，其次 payload.coin；star 取 payload.star。
func _handle_reward(payload: Dictionary) -> void:
	if not _valid_object(order_view) or not order_view.has_method("play_reward_popup"):
		return
	var coin := 0
	if payload.has("amount"):
		coin = _int_value(payload.get("amount"))
	elif payload.has("coin"):
		coin = _int_value(payload.get("coin"))
	var star := _int_value(payload.get("star"))
	order_view.play_reward_popup(coin, star)


# ---------------------------------------------------------------------------
# 显示与数据辅助
# ---------------------------------------------------------------------------

func _show_main(text: String, text_key: String, hide_at: float) -> void:
	_main_text_key = text_key
	_main_hide_at = hide_at
	_show_seq += 1
	_main_show_seq = _show_seq
	if not _valid_object(_main_label):
		return
	_main_label.text = text
	_main_label.visible = true


func _show_cta(text: String, text_key: String, hide_at: float) -> void:
	_cta_text_key = text_key
	_cta_hide_at = hide_at
	_show_seq += 1
	_cta_show_seq = _show_seq
	if not _valid_object(_cta_label):
		return
	_cta_label.text = text
	_cta_label.visible = true


## text/cta 的文案：查 locales[meta.locale]，缺失时回退为键名本身。
func _resolve_text(text_key: String) -> String:
	var text := _localized_text(text_key)
	if text.is_empty():
		return text_key
	return text


func _localized_text(key: String) -> String:
	if key.is_empty():
		return ""
	var pack := _locale_pack()
	var value: Variant = pack.get(key)
	if typeof(value) == TYPE_STRING:
		return String(value)
	return ""


func _locale_pack() -> Dictionary:
	var meta_v: Variant = project_data.get("meta")
	var locale := ""
	if typeof(meta_v) == TYPE_DICTIONARY:
		locale = _string_field(meta_v as Dictionary, "locale")
	if locale.is_empty():
		return {}
	var locales_v: Variant = project_data.get("locales")
	if typeof(locales_v) != TYPE_DICTIONARY:
		return {}
	var pack_v: Variant = (locales_v as Dictionary).get(locale)
	if typeof(pack_v) == TYPE_DICTIONARY:
		return pack_v as Dictionary
	return {}


func _event_duration(event: Dictionary, fallback: float) -> float:
	var value: Variant = event.get("duration")
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var seconds := float(value)
		if is_finite(seconds) and seconds >= 0.0:
			return seconds
	# 兼容把 duration 写在 payload 里的数据。
	var payload_v: Variant = event.get("payload")
	if typeof(payload_v) == TYPE_DICTIONARY:
		var payload_seconds_v: Variant = (payload_v as Dictionary).get("duration")
		if typeof(payload_seconds_v) == TYPE_INT or typeof(payload_seconds_v) == TYPE_FLOAT:
			var payload_seconds := float(payload_seconds_v)
			if is_finite(payload_seconds) and payload_seconds >= 0.0:
				return payload_seconds
	return fallback


func _normalize_slot(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 2 and _is_number(arr[0]) and _is_number(arr[1]):
			return [int(arr[0]), int(arr[1])]
	elif typeof(value) == TYPE_VECTOR2I:
		var v: Vector2i = value
		return [v.x, v.y]
	elif typeof(value) == TYPE_VECTOR2:
		var v2: Vector2 = value
		return [int(v2.x), int(v2.y)]
	return []


func _normalize_slots_array(values: Array) -> Array:
	var slots: Array = []
	for value_v in values:
		var slot := _normalize_slot(value_v)
		if not slot.is_empty():
			slots.append(slot)
	return slots


func _set_board_selection(selection: Array) -> void:
	if not _valid_object(board_view) or not board_view.has_method("set_selection"):
		return
	board_view.set_selection(selection)


func _clear_board_hint() -> void:
	if not _valid_object(board_view) or not board_view.has_method("clear_hint"):
		return
	board_view.clear_hint()


## 棋盘已满 toast：优先 PLACEHOLDER 贴图，加载失败则用本地化文字 Label。
func _ensure_board_full_toast(existing: Control) -> Control:
	var node := existing
	if node == null or not is_instance_valid(node):
		node = _create_board_full_toast()
		add_child(node)
	node.position = BOARD_FULL_RECT.position
	node.size = BOARD_FULL_RECT.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.visible = false
	if node is Label:
		var label := node as Label
		label.text = _board_full_text()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", BOARD_FULL_FONT_SIZE)
		label.add_theme_color_override("font_color", Color.WHITE)
		var font := _ui_font()
		if font != null:
			label.add_theme_font_override("font", font)
	return node


func _create_board_full_toast() -> Control:
	if loader != null:
		var result: Dictionary = loader.load_texture("ui_board_full_toast")
		if bool(result.get("ok", false)):
			var texture_v: Variant = result.get("texture")
			if texture_v is Texture2D:
				var rect := TextureRect.new()
				rect.texture = texture_v as Texture2D
				rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				return rect
	var label := Label.new()
	label.text = _board_full_text()
	return label


func _board_full_text() -> String:
	var text := _localized_text(BOARD_FULL_TEXT_KEY)
	if text.is_empty():
		return BOARD_FULL_FALLBACK
	return text


func _ensure_label(existing: Label, rect: Rect2, font_size: int) -> Label:
	var label := existing
	if label == null or not is_instance_valid(label):
		label = Label.new()
		add_child(label)
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.text = ""
	label.visible = false
	return label


func _ui_font() -> Font:
	if theme_doc != null:
		var theme_font_v: Variant = theme_doc.ui_font()
		if theme_font_v is Font:
			return theme_font_v
	if loader != null:
		var result: Dictionary = loader.load_font("font_zh")
		var font_v: Variant = result.get("font")
		if bool(result.get("ok", false)) and font_v is Font:
			return font_v
	return ThemeDB.fallback_font


func _valid_object(obj) -> bool:
	if obj == null:
		return false
	if typeof(obj) != TYPE_OBJECT:
		return false
	return is_instance_valid(obj)


static func _int_value(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f):
			return int(f)
	return 0


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _string_field(source: Dictionary, key: String) -> String:
	var value: Variant = source.get(key, "")
	if typeof(value) == TYPE_STRING:
		return String(value)
	return ""
