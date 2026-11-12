extends RefCounted
## M0 step 4 headless checks: order cards, character portrait, HUD fields, and
## the hard rule that the presentation layer never mutates sim state.
##
## Nothing here renders: no tree, no textures, no window.

const OrderPanel = preload("res://src/view/order_panel.gd")
const HudView = preload("res://src/view/hud_view.gd")
const FlyAnim = preload("res://src/view/fly_anim.gd")
const ProjectModel = preload("res://src/core/project_model.gd")
const Sim = preload("res://src/core/sim.gd")
const EventEvaluator = preload("res://src/core/event_evaluator.gd")

const SAMPLE := "res://data/sample_project.json"
const HANDLED := [
	"deliver", "order_claim", "coin_popup",
	"character_leave", "character_next", "levelup", "transition",
]


func run(t) -> void:
	_cards(t)
	_done_state(t)
	_hud(t)
	_presentation_only(t)
	_full_timeline_parity(t)


# ------------------------------------------------------------------ order card

func _cards(t) -> void:
	var project := _project()
	var level := _level(0)
	var panel = OrderPanel.new()
	panel.set_project(project)
	var built: Dictionary = panel.build_from_level(level)
	t.ok(bool(built.get("ok", false)), "level_1 builds into order cards")
	t.eq(int(built.get("cards", 0)), 1, "level_1 has exactly one order card")
	t.eq(int(built.get("missions", 0)), 2, "level_1 order needs two mission rows")
	t.eq(String(built.get("level_id", "")), String(_first_level_id()), "card build reports the level id")
	t.eq(panel.cards.size(), 1, "panel keeps one card")

	var card: Dictionary = panel.cards[0]
	t.eq(String(card.get("id", "")), "order_1", "card uses the order id")
	t.eq(String(card.get("character", "")), String(_l1_order_char()), "card points at the 1st order character")
	var mission: Array = card.get("mission", [])
	t.eq(mission.size(), 2, "mission has two entries")
	var item: Dictionary = mission[0]
	t.eq(String(item.get("entity", "")), "CleanSet_Ca", "mission entity matches the data")
	t.eq(int(item.get("level", 0)), 2, "mission level matches the data")
	t.eq(int(item.get("need", 0)), 1, "first mission needs 1")
	t.eq(int(item.get("have", -1)), 0, "mission starts with have=0")
	# 2026-11-11：第二行要几枚以数据为准（操作者会在内容编辑器里改，测试不写死）。
	var second: Dictionary = mission[1]
	t.eq(int(second.get("level", 0)), 1, "second mission is the lv1 row")
	t.eq(int(second.get("need", 0)), _l1_second_need(), "second mission need matches the data")
	t.eq(int(card.get("coin", -1)), 5, "card shows the coin reward")

	var summary: String = panel.debug_summary()
	t.ok(summary.contains("cards=1"), "summary reports one card", summary)
	t.ok(summary.contains("CleanSet_Ca@2 0/1"), "summary reports the mission need", summary)
	t.ok(_is_ascii(summary), "summary is ASCII", summary)
	t.ok(panel.portrait_center("order_1").x > 0.0, "portrait anchor is on screen",
			str(panel.portrait_center("order_1")))
	t.ok(panel.card_rect("order_1").size.x > 100.0, "card rect has a usable width",
			str(panel.card_rect("order_1")))

	var level2 := _level(1)
	var built2: Dictionary = panel.build_from_level(level2)
	t.eq(int(built2.get("cards", 0)), 5, "level_2 builds a five-card queue")
	t.eq(int(built2.get("missions", 0)), 11, "level_2 queue totals eleven mission rows")
	var summary2: String = panel.debug_summary()
	t.ok(summary2.contains("CleanSet_Cb@2 0/1"), "level_2 mission list is complete", summary2)

	# 1-2 cards per level: two orders must split the row, a third one is capped.
	var two := _level(1).duplicate(true)
	two["orders"] = [
		{"id": "order_a", "character": "char_01",
			"mission": [{"entity": "CleanSet_Ca", "level": 2}], "star": 1, "coin": 3},
		{"id": "order_b", "character": "char_02",
			"mission": [{"entity": "CleanSet_Cb", "level": 1}], "star": 2, "coin": 4},
		{"id": "order_c", "character": "char_01",
			"mission": [{"entity": "CleanSet_Ca", "level": 1}], "star": 0, "coin": 0},
	]
	panel.set_project(_project())
	var built3: Dictionary = panel.build_from_level(two)
	t.eq(int(built3.get("cards", 0)), 3, "a level with three orders builds three queue cards")
	t.eq(int(built3.get("missions", 0)), 3, "every mission row of the three cards is counted")
	var rect_a: Rect2 = panel.card_rect("order_a")
	var rect_b: Rect2 = panel.card_rect("order_b")
	t.ok(rect_b.position.x > rect_a.position.x + rect_a.size.x - 1.0,
			"the two cards do not overlap", str(rect_a) + " " + str(rect_b))
	t.ok(rect_a.size.x > 200.0, "each card keeps a usable width", str(rect_a.size.x))
	t.ok(panel.portrait_center("order_b").x > panel.portrait_center("order_a").x,
			"portraits follow their cards")
	t.eq(panel.debug_summary().split("|").size(), 3, "summary lists every card")

	panel.free()


func _done_state(t) -> void:
	var panel = OrderPanel.new()
	panel.set_project(_project())
	panel.build_from_level(_level(0))
	t.eq(int(panel.build_from_level(_level(0)).get("cards", 0)), 1, "rebuild keeps one card")
	t.ok(panel.debug_summary().contains("done=0"), "fresh card is not done",
			panel.debug_summary())

	t.ok(panel.set_order_done("order_1", true), "set_order_done accepts a known order")
	var summary: String = panel.debug_summary()
	t.ok(summary.contains("done=1"), "summary carries the done mark", summary)
	t.ok(summary.contains("order_1:" + _l1_order_char() + ":CleanSet_Ca@2"), "summary keeps the mission row",
			summary)
	t.ok(panel.set_mission_have("order_1", 0, 1), "set_mission_have accepts a known slot")
	t.ok(panel.debug_summary().contains("1/1"), "mission progress is readable",
			panel.debug_summary())
	t.ok(not panel.set_order_done("order_missing", true), "unknown order is rejected")
	t.ok(not panel.set_mission_have("order_1", 9, 1), "unknown mission index is rejected")
	t.ok(panel.set_order_done("order_1", false), "done state can be cleared")
	t.ok(panel.debug_summary().contains("done=0"), "cleared card reports done=0",
			panel.debug_summary())
	panel.free()


# ------------------------------------------------------------------------- HUD

func _hud(t) -> void:
	var project := _project()
	var hud = HudView.new()
	var resolved: Dictionary = hud.build_from_hud(_dict(project.get("hud", {})))
	var fields := ["level", "energy", "energyTickSeconds", "energyTickMode", "coin",
			"gem", "exp"]
	for key in fields:
		t.ok(resolved.has(String(key)), "hud exposes field " + String(key))
	t.eq(int(resolved.get("level", 0)), 2, "hud level")
	t.eq(int(resolved.get("energy", 0)), 88, "hud energy")
	t.eq(int(resolved.get("energyTickSeconds", 0)), 120, "hud energyTickSeconds")
	t.eq(String(resolved.get("energyTickMode", "")), "decrement", "hud energyTickMode")
	t.eq(int(resolved.get("coin", 0)), 9, "hud coin")
	t.eq(int(resolved.get("gem", 0)), 99, "hud gem")
	t.eq(int(resolved.get("exp", 0)), 0, "hud exp")
	t.eq(int(hud.get_value("energy")), 88, "hud keeps the last value readable")

	var summary: String = hud.debug_summary()
	t.ok(summary.contains("level=2"), "hud summary reports the level", summary)
	t.ok(summary.contains("tick=120s/decrement"), "hud summary reports the tick rule", summary)
	t.ok(_is_ascii(summary), "hud summary is ASCII", summary)
	t.ok(hud.counter_center("coin").x > hud.counter_center("level").x,
			"coin counter sits right of the level badge",
			str(hud.counter_center("coin")))

	var empty: Dictionary = hud.build_from_hud({})
	t.eq(int(empty.get("energyTickSeconds", 0)), 120, "missing hud falls back to defaults")
	hud.free()


# ------------------------------------------------------- presentation isolation

func _presentation_only(t) -> void:
	var model := ProjectModel.new()
	t.ok(model.load_data(_project()), "self-made project loads for the sim isolation check")
	var sim = Sim.new()
	sim.setup(model, 21)
	var before: String = sim.digest()

	var fly = FlyAnim.new()
	for type in HANDLED:
		t.ok(fly.play_event({
			"id": "probe_" + String(type),
			"channel": "view",
			"type": String(type),
			"at": 1.0,
			"duration": 0.5,
			"payload": {},
		}), "play_event handles " + String(type))
	t.eq(sim.digest(), before, "play_event never mutates sim state")
	t.ok(fly.active_count() >= HANDLED.size(), "every handled event queued a motion",
			str(fly.active_count()))
	var summary: String = fly.debug_summary()
	t.ok(summary.contains("levelup:1"), "fly summary counts levelup", summary)
	t.ok(summary.contains("order_claim:1"), "fly summary counts order_claim", summary)
	t.ok(_is_ascii(summary), "fly summary is ASCII", summary)

	t.ok(not fly.play_event({"type": "text", "payload": {}}),
			"text is not a presentation-owned event")
	t.ok(not fly.play_event({"type": "select", "payload": {}}),
			"select is not a presentation-owned event")
	t.eq(sim.digest(), before, "ignored events still leave the sim untouched")

	fly.set_clock(10.0)
	t.eq(fly.active_count(), 0, "motions retire once their time has passed")
	fly.free()


## Full-timeline proof: same seed, one run without a sink and one run with the
## presentation layer attached, digest-for-digest identical.
func _full_timeline_parity(t) -> void:
	# 这条只比"有没有挂表现层"的 digest，用真样例的时间轴（内容与断言无关）
	var model := ProjectModel.new()
	if not model.load_file(SAMPLE):
		t.ok(false, "sample project loads for the timeline parity check")
		return
	var timeline: Array = _as_array(model.project.get("timeline", []))

	var plain = EventEvaluator.new()
	plain.setup(model, 31, null)
	plain.load_timeline(timeline)
	var plain_result: Dictionary = plain.run_all()

	var fly = FlyAnim.new()
	var sink := func(ev: Dictionary) -> void:
		fly.play_event(ev)
	var watched = EventEvaluator.new()
	watched.setup(model, 31, sink)
	watched.load_timeline(timeline)
	var watched_result: Dictionary = watched.run_all()

	var plain_digests: Array = plain_result.get("digests", [])
	var watched_digests: Array = watched_result.get("digests", [])
	t.ok(plain_digests.size() > 0, "timeline produced sim digests", str(plain_digests.size()))
	t.eq(watched_digests, plain_digests, "presentation layer does not change any sim digest")
	t.eq(int(watched_result.get("dispatched", 0)), int(plain_result.get("dispatched", 0)),
			"both runs dispatch the same number of events")
	t.ok(fly.debug_summary().contains("handled="), "fly recorded the timeline beats",
			fly.debug_summary())
	t.eq(plain.sim.digest(), watched.sim.digest(), "final sim state is identical")
	fly.free()


# --------------------------------------------------------------------- helpers

## 2026-11-12（AGENTS §6.35）：改用自造工程，形状照原来的断言造
## （hud level=2 / energy=88 / coin=9 / gem=99；第 1 关 1 张单 2 行任务；第 2 关 5 张单）。
func _project() -> Dictionary:
	return {
		"version": 2,
		"hud": {"level": 2, "energy": 88, "energyTickSeconds": 120, "energyTickMode": "decrement",
			"coin": 9, "gem": 99, "exp": 0},
		"entities": {
			"CleanSet_Ca": {"kind": "chip", "family": "Clean", "chain": "Ca", "maxLevel": 10,
				"visual": {"hue": "#F2A65A", "label": "Ca"}},
			"CleanSet_Cb": {"kind": "chip", "family": "Clean", "chain": "Cb", "maxLevel": 10,
				"visual": {"hue": "#8FC7E8", "label": "Cb"}},
			"char_x": {"kind": "character"},
		},
		"characters": {"char_x": {"display": "X"}},
		"generators": {},
		"levels": [
			{
				"id": "mini_1",
				"board": {"width": 7, "height": 9, "slots": [
					{"x": 0, "y": 0, "entity": "CleanSet_Ca", "level": 1},
					{"x": 1, "y": 0, "entity": "CleanSet_Ca", "level": 1},
					{"x": 2, "y": 0, "entity": "CleanSet_Ca", "level": 1},
					{"x": 3, "y": 0, "entity": "CleanSet_Ca", "level": 1},
				]},
				"obstacles": [],
				"orders": [{
					"id": "order_1", "character": "char_x", "coin": 5, "gem": 0, "energy": 0,
					"mission": [
						{"entity": "CleanSet_Ca", "level": 2, "count": 1},
						{"entity": "CleanSet_Ca", "level": 1, "count": 2},
					],
				}],
			},
			{
				"id": "mini_2",
				"board": {"width": 7, "height": 9, "slots": []},
				"obstacles": [],
				"orders": [
					{"id": "o1", "character": "char_x", "coin": 5, "mission": [{"entity": "CleanSet_Ca", "level": 2, "count": 1}]},
					{"id": "o2", "character": "char_x", "coin": 5, "mission": [{"entity": "CleanSet_Cb", "level": 2, "count": 1}]},
					{"id": "o3", "character": "char_x", "coin": 5, "mission": [
						{"entity": "CleanSet_Ca", "level": 1, "count": 1},
						{"entity": "CleanSet_Cb", "level": 1, "count": 1},
						{"entity": "CleanSet_Ca", "level": 2, "count": 1}]},
					{"id": "o4", "character": "char_x", "coin": 5, "mission": [
						{"entity": "CleanSet_Ca", "level": 2, "count": 1},
						{"entity": "CleanSet_Cb", "level": 1, "count": 1},
						{"entity": "CleanSet_Cb", "level": 2, "count": 1}]},
					{"id": "o5", "character": "char_x", "coin": 5, "mission": [
						{"entity": "CleanSet_Cb", "level": 2, "count": 1},
						{"entity": "CleanSet_Ca", "level": 1, "count": 1},
						{"entity": "CleanSet_Ca", "level": 2, "count": 1}]},
				],
			},
		],
	}


func _level(index: int) -> Dictionary:
	var levels: Array = _as_array(_project().get("levels", []))
	if index >= 0 and index < levels.size() and typeof(levels[index]) == TYPE_DICTIONARY:
		return levels[index]
	return {}


func _dict(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _as_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _is_ascii(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) > 126:
			return false
	return true


## level_1 第一单的角色（从数据里读，不写死）。
func _l1_order_char() -> String:
	var model = ProjectModel.new()
	if not model.load_data(_project()):
		return ""
	var orders: Array = model.level(0).get("orders", [])
	if orders.is_empty():
		return ""
	return String((orders[0] as Dictionary).get("character", ""))


## level_1 第一单第二行要几枚（从数据读）。
func _l1_second_need() -> int:
	var model = ProjectModel.new()
	if not model.load_data(_project()):
		return 0
	var orders: Array = model.level(0).get("orders", [])
	if orders.is_empty():
		return 0
	var mission: Array = (orders[0] as Dictionary).get("mission", [])
	if mission.size() < 2:
		return 0
	return int((mission[1] as Dictionary).get("count", 1))


## 第一关的 id（从数据读）。
func _first_level_id() -> String:
	var model = ProjectModel.new()
	if not model.load_data(_project()):
		return ""
	return String(model.level(0).get("id", ""))
