extends Control
## Main screen for M0 step 4: board + HUD + order cards + presentation layer,
## driven by the shared event evaluator (no private timeline parsing here).
##
##   godot --path . --script res://tools/shot_game_screen.gd -- --t=6.2
##   godot --path . -- --autoplay               (real-time playback)
##   godot --path . -- --theme=themes/pet_shop  (data-only re-skin)
##
## The screen owns three things and nothing else:
##   1. wiring views to the evaluator's single resolved event stream
##   2. mirroring sim snapshots into the views (board / hud / order progress)
##   3. presentation time (clock -> FlyAnim), which never feeds back into the sim

const BoardScene := preload("res://src/view/board_view.tscn")
const HudView := preload("res://src/view/hud_view.gd")
const OrderPanel := preload("res://src/view/order_panel.gd")
const FlyAnim := preload("res://src/view/fly_anim.gd")
const ProjectModel := preload("res://src/core/project_model.gd")
const EventEvaluator := preload("res://src/core/event_evaluator.gd")
const AssetGuardScript := preload("res://src/assets/asset_guard.gd")
const ThemeLoader := preload("res://src/theme/theme_loader.gd")

const SAMPLE_PROJECT := "res://data/sample_project.json"
const MANIFEST_INDEX := "res://data/manifest_index.json"
const PAGE := Vector2(1080.0, 1920.0)
const BOARD_RECT := Rect2(50.0, 450.0, 980.0, 1260.0)
const HUD_RECT := Rect2(0.0, 0.0, 1080.0, 185.0)
const ORDER_RECT := Rect2(0.0, 182.0, 1080.0, 250.0)
const DEFAULT_SEED := 7

var board
var hud
var orders
var fly
var model
var evaluator
var guard
var theme_loader

var allow_placeholders: bool = false
var theme_name: String = ""
var theme_ok: bool = false
var sim_rejected: int = 0
var view_events: Dictionary = {}

var _clock: float = 0.0
var _seed: int = DEFAULT_SEED
var _autoplay: bool = true
var _freeze: bool = false
var _t_target: float = -1.0
var _selected := Vector2i(-1, -1)
var _level_index: int = 0
var _level_static: Dictionary = {}
var _end_time: float = 0.0
var _event_count: int = 0
var _last_code: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size.x <= 0.0 or size.y <= 0.0:
		size = PAGE
	_parse_args()

	model = ProjectModel.new()
	if not model.load_file(SAMPLE_PROJECT):
		push_error("[game] cannot load " + SAMPLE_PROJECT + ": " + String(model.load_error))
		return

	guard = AssetGuardScript.new()
	if not guard.load_from(MANIFEST_INDEX, allow_placeholders):
		push_warning("[game] asset index: " + String(guard.load_error))

	theme_loader = ThemeLoader.new()
	theme_loader.setup(guard, allow_placeholders)
	if theme_name.is_empty():
		theme_name = String(model.project.get("theme", "themes/default"))
	var theme_result: Dictionary = theme_loader.load_theme(theme_name, model.project)
	theme_ok = bool(theme_result.get("ok", false))
	var colors: Dictionary = theme_loader.colors()
	var metrics: Dictionary = theme_loader.metrics

	board = BoardScene.instantiate()
	board.position = Vector2.ZERO
	add_child(board)

	hud = HudView.new()
	hud.position = HUD_RECT.position
	hud.size = HUD_RECT.size
	add_child(hud)
	hud.set_palette(colors)

	orders = OrderPanel.new()
	orders.position = ORDER_RECT.position
	orders.size = ORDER_RECT.size
	orders.set_palette(colors)
	orders.set_metrics(metrics)
	orders.set_project(model.project)
	add_child(orders)

	fly = FlyAnim.new()
	fly.position = Vector2.ZERO
	fly.size = PAGE
	fly.set_palette(colors)
	fly.set_metrics(metrics)
	add_child(fly)

	_apply_static_level(0)
	evaluator = EventEvaluator.new()
	evaluator.setup(model, _seed, Callable(self, "_on_event"))
	var loaded: Dictionary = evaluator.load_timeline(_as_array(model.project.get("timeline", [])))
	_event_count = int(loaded.get("count", 0))
	_end_time = float(loaded.get("end_time", 0.0))
	if not bool(loaded.get("ok", false)):
		push_warning("[game] timeline rejected: " + str(loaded.get("errors", [])))

	_sync_from_sim()

	if _t_target >= 0.0:
		while evaluator.cursor < evaluator.events.size():
			var ev: Dictionary = evaluator.events[evaluator.cursor]
			if float(ev.get("at", 0.0)) > _t_target:
				break
			var report: Dictionary = evaluator.step()
			if not bool(report.get("ok", true)):
				sim_rejected += 1
				_last_code = String(report.get("code", ""))
		_clock = _t_target
		fly.set_clock(_clock)
	else:
		fly.set_clock(0.0)

	print("[game] project=%s levels=%d events=%d end=%.2f theme=%s ok=%s" % [
		SAMPLE_PROJECT.get_file(), model.level_count(), _event_count, _end_time,
		theme_name, str(theme_ok),
	])
	print("[game] " + String(theme_loader.summary()))
	print("[game] " + String(hud.debug_summary()))
	print("[game] " + String(orders.debug_summary()))
	print("[game] freeze=%s autoplay=%s clock=%.2f t=%.2f" % [
		str(_freeze), str(_autoplay), _clock, _t_target,
	])


# ------------------------------------------------------------------- arguments

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text == "--autoplay":
			_autoplay = true
		elif text == "--no-autoplay":
			_autoplay = false
		elif text.begins_with("--t="):
			_freeze = true
			_t_target = maxf(0.0, float(text.substr(4)))
		elif text.begins_with("--theme="):
			theme_name = text.substr(8)
		elif text.begins_with("--seed="):
			_seed = int(text.substr(7))
		elif text == "--allow-placeholders":
			allow_placeholders = true


# ------------------------------------------------------------------- view sync

func _apply_static_level(index: int) -> void:
	_level_index = index
	_level_static = _as_dict(model.level(index))
	_selected = Vector2i(-1, -1)
	orders.build_from_level(_level_static)
	fly.set_backdrop({
		"board": BOARD_RECT,
		"level": index + 1,
		"level_id": String(_level_static.get("id", "")),
		"title": String(_as_dict(model.project.get("meta", {})).get("title", "")),
		"order": _first_order_id(_level_static),
	})


func _first_order_id(level: Dictionary) -> String:
	for raw in _as_array(level.get("orders", [])):
		if typeof(raw) == TYPE_DICTIONARY:
			return String((raw as Dictionary).get("id", ""))
	return ""


func _sync_from_sim() -> void:
	if evaluator == null or evaluator.sim == null:
		return
	var snap: Dictionary = evaluator.sim.snapshot()
	var index := int(snap.get("level_index", 0))
	if index != _level_index:
		_apply_static_level(index)
	var level := _level_from_snapshot(snap)
	board.build_from_level_data(level, _as_dict(model.project.get("entities", {})),
			_generators_live(snap))
	board.apply_state({"selected": _to_array(_selected), "completed": _completed_cells(snap)})
	hud.build_from_hud(_as_dict(snap.get("hud", {})))
	orders.sync_orders(_as_array(snap.get("orders", [])))
	_refresh_anchors()


func _level_from_snapshot(snap: Dictionary) -> Dictionary:
	var board_snap := _as_dict(snap.get("board", {}))
	var slots: Array = []
	for row in _as_array(board_snap.get("cells", [])):
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 4:
			continue
		slots.append({
			"x": int((row as Array)[0]),
			"y": int((row as Array)[1]),
			"entity": String((row as Array)[2]),
			"level": int((row as Array)[3]),
		})
	var obstacles: Array = []
	for row in _as_array(board_snap.get("obstacles", [])):
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 3:
			continue
		for kind in _as_array((row as Array)[2]):
			obstacles.append({
				"slot": [int((row as Array)[0]), int((row as Array)[1])],
				"type": String(kind),
			})
	return {
		"id": String(snap.get("level_id", "")),
		"board": {
			"width": int(board_snap.get("width", 7)),
			"height": int(board_snap.get("height", 9)),
			"slots": slots,
		},
		"obstacles": obstacles,
		"orders": _as_array(_level_static.get("orders", [])),
	}


## View-only derivation: a cell that satisfies an open mission item is marked as
## ready (green) so the delivery beat reads without extra art.
func _completed_cells(snap: Dictionary) -> Array:
	var wanted := {}
	for raw in _as_array(snap.get("orders", [])):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = raw
		if bool(order.get("done", false)):
			continue
		var mission := _as_array(order.get("mission", []))
		for i in range(mission.size()):
			var item = mission[i]
			if typeof(item) != TYPE_ARRAY or (item as Array).size() < 3:
				continue
			if int((item as Array)[2]) >= 1:
				continue
			var key := "%s@%d" % [String((item as Array)[0]), int((item as Array)[1])]
			wanted[key] = true
	var out: Array = []
	for row in _as_array(_as_dict(snap.get("board", {})).get("cells", [])):
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 4:
			continue
		var key := "%s@%d" % [String((row as Array)[2]), int((row as Array)[3])]
		if wanted.has(key):
			out.append([int((row as Array)[0]), int((row as Array)[1])])
	return out


## Generator charges live in the sim, not in project.json; hand the board a copy
## with the current counts so its x<charges> badge matches the simulation.
func _generators_live(snap: Dictionary) -> Dictionary:
	var out := _as_dict(model.project.get("generators", {})).duplicate(true)
	var live := _as_dict(snap.get("generators", {}))
	for gid in live.keys():
		if not out.has(gid):
			continue
		var cfg := _as_dict(out[gid])
		cfg["charges"] = int(_as_dict(live[gid]).get("charges", cfg.get("charges", 0)))
		out[String(gid)] = cfg
	return out


func _refresh_anchors() -> void:
	var table := {}
	var width := 7
	var height := 9
	if evaluator != null and evaluator.sim != null and evaluator.sim.board != null:
		width = int(evaluator.sim.board.width)
		height = int(evaluator.sim.board.height)
	for y in height:
		for x in width:
			table["cell:%d,%d" % [x, y]] = board.cell_rect(x, y).get_center()
	for card in orders.cards:
		var id := String(card.get("id", ""))
		table["order:" + id] = orders.portrait_center(id) + orders.position
		table["card:" + id] = orders.card_rect(id).get_center() + orders.position
	table["order:default"] = table.get("order:default", Vector2(540.0, 300.0))
	if not orders.cards.is_empty():
		var first := String((orders.cards[0] as Dictionary).get("id", ""))
		table["order:default"] = table.get("order:" + first, Vector2(540.0, 300.0))
	var coin_local: Vector2 = hud.counter_center("coin")
	var star_local: Vector2 = hud.counter_center("star")
	var gem_local: Vector2 = hud.counter_center("gem")
	table["hud:coin"] = coin_local + hud.position
	table["hud:star"] = star_local + hud.position
	table["hud:gem"] = gem_local + hud.position
	fly.set_anchors(table)
	fly.set_clock(_clock)


# --------------------------------------------------------------------- events

func _on_event(ev: Dictionary) -> void:
	var type := String(ev.get("type", ""))
	var channel := String(ev.get("channel", ""))
	view_events[channel + ":" + type] = int(view_events.get(channel + ":" + type, 0)) + 1
	if channel == "sim":
		_sync_from_sim()
	elif type == "select":
		var payload := _as_dict(ev.get("payload", {}))
		var cell := _to_cell(payload.get("slot", null))
		if cell.x >= 0:
			_selected = cell
			board.apply_state({"selected": _to_array(_selected),
					"completed": _completed_cells(evaluator.sim.snapshot())})
	fly.play_event(_with_hue(ev))


## Item flights borrow the mission item's hue, so the thing flying to the card
## looks like the chip that was consumed. Presentation only: the event the sim
## received is untouched (the evaluator copied nothing).
func _with_hue(ev: Dictionary) -> Dictionary:
	var type := String(ev.get("type", ""))
	if type != "deliver" and type != "order_claim":
		return ev
	var out := ev.duplicate(true)
	var payload := _as_dict(out.get("payload", {}))
	payload["hue"] = _mission_hue(String(payload.get("order", "")))
	out["payload"] = payload
	return out


func _mission_hue(order_id: String) -> String:
	for card in orders.cards:
		if String(card.get("id", "")) != order_id:
			continue
		var items: Array = card.get("mission", [])
		if not items.is_empty():
			var hue: Color = items[0].get("hue", Color.WHITE)
			return hue.to_html(false)
	return ""


func _process(delta: float) -> void:
	if _freeze or evaluator == null:
		return
	if not _autoplay:
		fly.set_clock(_clock)
		return
	_clock += delta
	while evaluator.cursor < evaluator.events.size():
		var ev: Dictionary = evaluator.events[evaluator.cursor]
		if float(ev.get("at", 0.0)) > _clock:
			break
		var report: Dictionary = evaluator.step()
		if not bool(report.get("ok", true)):
			sim_rejected += 1
			_last_code = String(report.get("code", ""))
	fly.set_clock(_clock)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_tree().quit(0)


func debug_summary() -> String:
	return "game level=%d/%s events=%d clock=%.2f selected=%s sim_rejected=%d view=%d" % [
		_level_index + 1, String(_level_static.get("id", "")), _event_count, _clock,
		str(_selected), sim_rejected, view_events.size(),
	]


# -------------------------------------------------------------------- helpers

func _to_array(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


func _to_cell(raw) -> Vector2i:
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
		return Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
	return Vector2i(-1, -1)


func _as_dict(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _as_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
