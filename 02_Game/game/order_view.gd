extends Control

## M0 第 1 周第 4 步：订单/角色 View（订单卡、绿药丸、交单飞行动画、角色切换）。
## 角色、绿药丸、金币全部自绘；星星优先使用 ui_icon_star（PLACEHOLDER，需允许），
## 失败时自绘五角星。唯一贴图/字体入口：AssetLoader；绝不引用 REFERENCE_ONLY。

const AssetLoader := preload("res://game/asset_loader.gd")

const CARD_RECT := Rect2(40.0, 150.0, 580.0, 240.0)
const CHARACTER_CENTER := Vector2(860.0, 360.0)
const COMPLETE_HEX := "#3ddc6a"
const STATE_CLAIMED := "claimed"
const STATE_READY := "ready"

var project_data: Dictionary = {}
var snapshot: Dictionary = {}
var active_order: Dictionary = {}
var active_mission: Array = []
var character_id := ""
var order_state := ""
var allow_placeholders := true
var loader = null

var _palette: Array[Color] = [
	Color("#ff8a5c"),
	Color("#5cc8ff"),
	Color("#a07cff"),
	Color("#6be585"),
	Color("#ffd83d"),
	Color("#ff6fa5"),
	Color("#4fd1c5"),
	Color("#c0d3e8"),
]
var _font_cache: Font = null
var _star_texture: Texture2D = null
var _star_checked := false
var _character_alpha := 1.0
var _character_done := false
var _level_complete_text := ""
var _active_level_index := -1
var _claim_tween: Tween = null
var _claim_token: Control = null
var _reward_labels: Array = []


func setup(project_data_arg: Dictionary, snapshot_arg: Dictionary, allow_placeholders_flag := true) -> void:
	project_data = project_data_arg
	allow_placeholders = bool(allow_placeholders_flag)
	_font_cache = null
	_star_texture = null
	_star_checked = false
	_level_complete_text = ""
	_active_level_index = -1
	_character_alpha = 1.0
	_character_done = false
	_cancel_claim_animation()
	loader = AssetLoader.new()
	loader.setup("res://assets/assets.json", bool(allow_placeholders_flag))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resolve_snapshot(snapshot_arg)
	queue_redraw()


func refresh(snapshot_arg: Dictionary) -> void:
	_resolve_snapshot(snapshot_arg)
	queue_redraw()


func active_order_id() -> String:
	var id_v: Variant = active_order.get("id", "")
	if typeof(id_v) == TYPE_STRING:
		return String(id_v)
	return ""


func get_character_id() -> String:
	return character_id


func mission_count() -> int:
	return active_mission.size()


func is_ready() -> bool:
	return order_state == STATE_READY


func get_order_state() -> String:
	return order_state


## OrderView 本地坐标（角色头/身的整体中心）。
func character_center() -> Vector2:
	return CHARACTER_CENTER


## 交单动画：90×90 token 从棋盘格飞向角色 → 角色完成对号 → 奖励上浮 → 角色淡出。
## 不在场景树中时直接回调（供无渲染测试使用）。
func play_claim_sequence(from_global: Vector2, coin: int, star: int, on_finished := Callable()) -> void:
	if not is_inside_tree():
		if on_finished.is_valid():
			on_finished.call()
		return

	_cancel_claim_animation()
	_character_done = false
	_character_alpha = 1.0
	queue_redraw()

	var local_point: Vector2 = get_global_transform().affine_inverse() * from_global
	var token := _create_token()
	token.position = local_point - Vector2(45.0, 45.0)
	add_child(token)
	_claim_token = token

	var target := character_center() - Vector2(45.0, 45.0)
	var tween := create_tween()
	_claim_tween = tween
	tween.tween_property(token, "position", target, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(token, "scale", Vector2(0.3, 0.3), 0.5)
	tween.tween_callback(func() -> void:
		_free_claim_token()
		_character_done = true
		queue_redraw()
	)
	tween.tween_interval(0.25)
	tween.tween_callback(func() -> void:
		_spawn_reward_popups(coin, star)
	)
	tween.tween_interval(0.8)
	tween.tween_method(_set_character_alpha, 1.0, 0.0, 0.35)
	tween.tween_callback(func() -> void:
		_claim_tween = null
		if on_finished.is_valid():
			on_finished.call()
	)


func _set_character_alpha(value: float) -> void:
	_character_alpha = value
	queue_redraw()


func show_level_complete(text: String) -> void:
	_level_complete_text = text
	queue_redraw()


# ---------------------------------------------------------------------------
# 状态解析
# ---------------------------------------------------------------------------

func _resolve_snapshot(snapshot_arg: Dictionary) -> void:
	snapshot = snapshot_arg
	var level := _current_level()
	var level_index := _snapshot_level_index()

	var chosen_id := ""
	var chosen_state := ""
	var orders_v: Variant = snapshot.get("orders", [])
	if typeof(orders_v) == TYPE_ARRAY:
		for entry_v in (orders_v as Array):
			if typeof(entry_v) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_v
			var state := _string_field(entry, "state")
			if state == STATE_CLAIMED:
				continue
			chosen_id = _string_field(entry, "id")
			chosen_state = state
			break

	var new_active: Dictionary = {}
	var new_mission: Array = []
	var new_character := ""
	var new_state := ""
	if not chosen_id.is_empty():
		var order_def := _find_level_order(level, chosen_id)
		if not order_def.is_empty():
			new_active = order_def.duplicate(true)
			new_character = _string_field(new_active, "character")
			new_state = chosen_state
			var mission_v: Variant = new_active.get("mission")
			if typeof(mission_v) == TYPE_ARRAY:
				new_mission = (mission_v as Array).duplicate(true)

	var level_changed := level_index != _active_level_index
	if _claim_tween != null:
		# 外部 refresh 意味着视图状态被重新驱动（如重播/切关），终止未完成的交单动画。
		_cancel_claim_animation()
	if level_changed:
		_level_complete_text = ""
	_character_alpha = 1.0
	_character_done = false
	_active_level_index = level_index

	active_order = new_active
	active_mission = new_mission
	character_id = new_character
	order_state = new_state


func _snapshot_level_index() -> int:
	var index := 0
	var level_v: Variant = snapshot.get("level")
	if typeof(level_v) == TYPE_DICTIONARY:
		index = _int_field(level_v as Dictionary, "index")
	return index


func _current_level() -> Dictionary:
	var levels_v: Variant = project_data.get("levels")
	if typeof(levels_v) != TYPE_ARRAY:
		return {}
	var levels: Array = levels_v
	if levels.is_empty():
		return {}
	var index := clampi(_snapshot_level_index(), 0, levels.size() - 1)
	var level_v: Variant = levels[index]
	if typeof(level_v) == TYPE_DICTIONARY:
		return level_v as Dictionary
	return {}


func _find_level_order(level: Dictionary, order_id: String) -> Dictionary:
	if order_id.is_empty():
		return {}
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


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	_draw_order_card()
	_draw_character()
	_draw_level_complete()


func _draw_order_card() -> void:
	if active_order.is_empty():
		return
	var font := _ui_font()
	draw_style_box(_make_style(Color("#1d2c4d"), 28, Color("#5b7fae"), 5), CARD_RECT)

	var title := "订单 %s" % active_order_id()
	draw_string(font, CARD_RECT.position + Vector2(28.0, 56.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 34, Color("#eaf2ff"))

	var row_y := CARD_RECT.position.y + 100.0
	for item_v in active_mission:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var entity := _string_field(item, "entity")
		var item_level := _int_field(item, "level")
		var entity_color := _entity_color(entity)
		var block := Rect2(CARD_RECT.position.x + 32.0, row_y - 22.0, 44.0, 44.0)
		draw_style_box(_make_style(entity_color, 10, entity_color.lightened(0.3), 3), block)
		draw_string(
			font,
			Vector2(block.position.x + 58.0, row_y + 10.0),
			"%s Lv%d" % [entity, item_level],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			28,
			Color(1.0, 1.0, 1.0, 0.92)
		)
		row_y += 56.0

	var reward_y := CARD_RECT.end.y - 44.0
	_draw_coin(Vector2(CARD_RECT.position.x + 62.0, reward_y), _int_field(active_order, "coin"), font)
	_draw_star(Vector2(CARD_RECT.position.x + 250.0, reward_y), _int_field(active_order, "star"), font)

	if order_state == STATE_READY:
		_draw_ready_pill(Rect2(CARD_RECT.position.x + 360.0, CARD_RECT.end.y - 76.0, 200.0, 64.0))


func _draw_coin(center: Vector2, coin: int, font: Font) -> void:
	draw_circle(center, 22.0, Color("#f5b83d"))
	draw_circle(center, 17.0, Color("#ffd76a"))
	draw_arc(center, 22.0, 0.0, TAU, 32, Color("#b07a18"), 3.0, true)
	draw_string(font, center + Vector2(30.0, 10.0), "+%d" % coin, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color("#ffe9a8"))


func _draw_star(center: Vector2, star: int, font: Font) -> void:
	var texture := _star_texture_or_null()
	if texture != null:
		draw_texture_rect(texture, Rect2(center - Vector2(22.0, 22.0), Vector2(44.0, 44.0)), false)
	else:
		_draw_star_polygon(center, 22.0)
	draw_string(font, center + Vector2(30.0, 10.0), "+%d" % star, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color("#fff2a8"))


func _draw_star_polygon(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var point_radius := radius if (i % 2) == 0 else radius * 0.45
		var angle := -PI * 0.5 + PI / 5.0 * float(i)
		points.append(center + Vector2(cos(angle), sin(angle)) * point_radius)
	draw_colored_polygon(points, Color("#ffe066"))
	draw_polyline(points, Color("#d9a81f"), 2.0, true)


func _draw_ready_pill(rect: Rect2) -> void:
	draw_style_box(_make_style(Color(COMPLETE_HEX), 32, Color("#a9f7bd"), 4), rect)
	var center := rect.get_center()
	draw_line(center + Vector2(-30.0, 2.0), center + Vector2(-8.0, 22.0), Color.WHITE, 8.0, true)
	draw_line(center + Vector2(-8.0, 22.0), center + Vector2(32.0, -20.0), Color.WHITE, 8.0, true)


func _draw_character() -> void:
	if character_id.is_empty():
		return
	var alpha := clampf(_character_alpha, 0.0, 1.0)
	if alpha <= 0.001:
		return
	var dim := 0.45 if order_state == STATE_CLAIMED else 1.0
	var base := _entity_color(character_id)
	var skin := _with_alpha(base, alpha * dim)
	var body := _with_alpha(base.darkened(0.18), alpha * dim)
	var outline := _with_alpha(base.lightened(0.25), alpha * dim)

	var head_center := CHARACTER_CENTER + Vector2(0.0, -70.0)
	draw_style_box(
		_make_style(body, 40, outline, 4),
		Rect2(CHARACTER_CENTER + Vector2(-78.0, -30.0), Vector2(156.0, 160.0))
	)
	draw_circle(head_center, 54.0, skin)
	draw_arc(head_center, 54.0, 0.0, TAU, 48, _with_alpha(Color(1.0, 1.0, 1.0, 0.75), alpha * dim), 3.0, true)
	draw_circle(head_center + Vector2(-18.0, -6.0), 8.0, _with_alpha(Color("#243044"), alpha * dim))
	draw_circle(head_center + Vector2(18.0, -6.0), 8.0, _with_alpha(Color("#243044"), alpha * dim))

	var font := _ui_font()
	_draw_text_centered(font, character_id, CHARACTER_CENTER + Vector2(0.0, 170.0), 30, _with_alpha(Color(1.0, 1.0, 1.0, 0.92), alpha * dim))

	if order_state == STATE_READY or _character_done:
		_draw_check_badge(CHARACTER_CENTER + Vector2(82.0, -108.0), 26.0, alpha * dim)


func _draw_check_badge(center: Vector2, radius: float, alpha: float) -> void:
	draw_circle(center, radius, _with_alpha(Color(COMPLETE_HEX), alpha))
	draw_arc(center, radius, 0.0, TAU, 32, _with_alpha(Color(1.0, 1.0, 1.0, 0.9), alpha), 2.5, true)
	var scale := radius * 0.55
	draw_line(
		center + Vector2(-0.75 * scale, 0.0),
		center + Vector2(-0.1 * scale, 0.65 * scale),
		_with_alpha(Color.WHITE, alpha),
		5.0,
		true
	)
	draw_line(
		center + Vector2(-0.1 * scale, 0.65 * scale),
		center + Vector2(0.8 * scale, -0.6 * scale),
		_with_alpha(Color.WHITE, alpha),
		5.0,
		true
	)


func _draw_level_complete() -> void:
	if _level_complete_text.is_empty():
		return
	var center := Vector2(540.0, 900.0)
	var font := _ui_font()
	var text_size := font.get_string_size(_level_complete_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 72)
	var width := minf(text_size.x + 112.0, 1040.0)
	var rect := Rect2(center - Vector2(width * 0.5, 70.0), Vector2(width, 140.0))
	draw_style_box(_make_style(Color(0.03, 0.06, 0.12, 0.62), 30, Color(1.0, 1.0, 1.0, 0.18), 3), rect)
	_draw_text_centered(font, _level_complete_text, center, 72, Color.WHITE)


# ---------------------------------------------------------------------------
# 动画辅助
# ---------------------------------------------------------------------------

func _create_token() -> Control:
	var token := Control.new()
	token.size = Vector2(90.0, 90.0)
	token.pivot_offset = Vector2(45.0, 45.0)
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.z_index = 20

	var panel := Panel.new()
	panel.size = Vector2(90.0, 90.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_style(Color("#ffb347"), 18, Color("#ffe2a8"), 4))
	token.add_child(panel)

	var label := Label.new()
	label.text = "item"
	label.size = Vector2(90.0, 90.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color("#4a2d00"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.add_child(label)
	return token


func _free_claim_token() -> void:
	if _claim_token != null and is_instance_valid(_claim_token):
		_claim_token.queue_free()
	_claim_token = null


func _cancel_claim_animation() -> void:
	if _claim_tween != null:
		if _claim_tween.is_valid():
			_claim_tween.kill()
		_claim_tween = null
	_free_claim_token()
	for label_v in _reward_labels:
		if label_v is Node and is_instance_valid(label_v):
			(label_v as Node).queue_free()
	_reward_labels.clear()


func _spawn_reward_popups(coin: int, star: int) -> void:
	var center := character_center()
	_spawn_popup("+%d" % coin, Color("#ffd76a"), center + Vector2(-90.0, -30.0))
	_spawn_popup("+%d" % star, Color("#fff2a8"), center + Vector2(30.0, -30.0))


func _spawn_popup(text: String, color: Color, start: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _ui_font())
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", color)
	label.position = start
	label.z_index = 30
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_reward_labels.append(label)

	var tween := label.create_tween()
	tween.tween_property(label, "position", start + Vector2(0.0, -80.0), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.8)
	tween.tween_callback(func() -> void:
		if is_instance_valid(label):
			label.queue_free()
	)


# ---------------------------------------------------------------------------
# 通用工具
# ---------------------------------------------------------------------------

func _star_texture_or_null() -> Texture2D:
	if _star_checked:
		return _star_texture
	_star_checked = true
	if loader != null:
		var result: Dictionary = loader.load_texture("ui_icon_star")
		var texture_v: Variant = result.get("texture")
		if bool(result.get("ok", false)) and texture_v is Texture2D:
			_star_texture = texture_v
	return _star_texture


func _entity_color(entity: String) -> Color:
	if entity.is_empty():
		return Color("#8fa3bf")
	# djb2 稳定哈希：同一 entity 跨运行得到同一颜色。
	var hash_value := 5381
	for i in range(entity.length()):
		hash_value = (hash_value * 33 + entity.unicode_at(i)) % 2147483647
	return _palette[hash_value % _palette.size()]


func _ui_font() -> Font:
	if _font_cache != null:
		return _font_cache
	if loader != null:
		var zh: Dictionary = loader.load_font("font_zh")
		var zh_font: Variant = zh.get("font")
		if bool(zh.get("ok", false)) and zh_font is Font:
			_font_cache = zh_font
		else:
			var en: Dictionary = loader.load_font("font_en")
			var en_font: Variant = en.get("font")
			if bool(en.get("ok", false)) and en_font is Font:
				_font_cache = en_font
	if _font_cache == null:
		_font_cache = ThemeDB.fallback_font
	return _font_cache


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(alpha, 0.0, 1.0))


func _make_style(fill: Color, corner: int, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(corner)
	style.set_border_width_all(border_width)
	style.border_color = border
	return style


func _draw_text_centered(font: Font, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var pos := Vector2(center.x - text_size.x * 0.5, baseline)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


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
