extends RefCounted
## M0 core sim: board / merge / generator / order / level state.
##
## Driven only by sim events (tap, merge, deliver, order_claim, energy_tick,
## level_complete, level_next). Nothing ticks per frame and nothing reads the
## clock, so `seed + ordered event list` fully determines the final state.
##
## Every rule returns {"ok", "code", "note"}: a rejected command never mutates
## state, which is what makes "same digest before and after a failed claim" a
## meaningful test instead of a coincidence.

const BoardState = preload("res://src/core/board_state.gd")
const Safeboxes := preload("res://src/core/safeboxes.gd")
const IceCell := preload("res://src/core/ice_cell.gd")
const ProjectModel = preload("res://src/core/project_model.gd")
const Rng = preload("res://src/core/rng.gd")
const StateDigest = preload("res://src/core/state_digest.gd")
const SimHandlers = preload("res://src/core/sim_handlers.gd")

const MAX_LEVEL := 10
const INVALID_POS := Vector2i(-1000000, -1000000)

var model
var board
var rng
var level_index: int = 0
var time: float = 0.0
## Last accepted generator drop: {"from", "to", "entity", "level"}. The views use it
## to fly the chip in; empty on a rejected tap.
var last_spawn: Dictionary = {}
## Obstacles cleared by the last merge: [{"cell": [x, y], "kind": "ice"}].
var last_unlocks: Array = []
## 左侧库存剩余次数（-1 表示尚未从关卡配置里读取）。
var stockpile_count: int = -1
## 库存面板固定产出哪一种棋子：进关时定一次，之后交付/合成都不变。
var stockpile_chip: Dictionary = {}
## Multi-cell safeboxes for the current level (empty when the level declares none).
var safeboxes: Array = []
var hud: Dictionary = {}
var orders: Array = []
var generator_state: Dictionary = {}
var level_complete_pending: bool = false
## 2026-11-10：冰只按**自己的倒计时**融化（爆炸不再波及）。这里记每格冰出现的关卡时刻。
var ice_since: Dictionary = {}
## 2026-11-12：每台生成器自己的"指定顺序"游标（Vector2i -> 已吐出的条数）。
## 按格子存，所以同一实体摆多台可以各配各的队列。
var gen_seq_index: Dictionary = {}
## 库存面板"飞生成器"模式：只允许点一次。
var stockpile_used: bool = false
## 库存面板自己的顺序游标（飞棋子模式）。
var stockpile_seq_index: int = 0
## 2026-11-11：每格冰可以有自己的时长（关卡 JSON 的 `obstacle.seconds`）。
var ice_lengths: Dictionary = {}
## 2026-11-11：网 / 冰下面压着的那枚棋子可以由 JSON 指定（`obstacle.chip`）。
var trapped_chips: Dictionary = {}
var board_full_pending: bool = false
var log_events: Array = []
var seed_value: int = 0


func setup(model_in, seed_value_in: int) -> void:
	model = model_in
	seed_value = seed_value_in
	board = BoardState.new()
	rng = Rng.make(seed_value_in, 0)
	level_index = 0
	time = 0.0
	hud = model.hud_initial() if model != null else {}
	orders = []
	generator_state = {}
	stockpile_count = -1
	stockpile_chip = {}
	level_complete_pending = false
	board_full_pending = false
	log_events = []
	_load_level(0)


# ---------------------------------------------------------------- level state

## 2026-11-05: the badge number comes from the level data (`level_number`).
func _apply_level_number(lvl: Dictionary, index: int) -> void:
	hud["level"] = int(lvl.get("level_number", index + 1))


func _load_level(index: int) -> void:
	var lvl: Dictionary = {}
	if model != null:
		lvl = model.level(index)
	if hud.is_empty() and model != null:
		hud = model.hud_initial()
	# 2026-11-05: the badge number comes from the level data, not from its index.
	_apply_level_number(lvl, index)
	board.load_level(lvl)
	# 2026-11-11：障碍可以带自己的参数 —— `seconds`（这块冰多少秒）与
	# `chip`（网/冰下面压哪一枚棋子）。没写就沿用原来的确定性默认值。
	ice_lengths = {}
	trapped_chips = {}
	for entry in lvl.get("obstacles", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot = (entry as Dictionary).get("slot", [])
		if typeof(slot) != TYPE_ARRAY or (slot as Array).size() < 2:
			continue
		var ocell := Vector2i(int((slot as Array)[0]), int((slot as Array)[1]))
		var sec = (entry as Dictionary).get("seconds", null)
		if typeof(sec) == TYPE_INT or typeof(sec) == TYPE_FLOAT:
			if int(sec) > 0:
				ice_lengths[ocell] = int(sec)
		var chip = (entry as Dictionary).get("chip", null)
		if typeof(chip) == TYPE_DICTIONARY:
			var cident := String((chip as Dictionary).get("entity", ""))
			if not cident.is_empty():
				trapped_chips[ocell] = {"entity": cident,
						"level": int((chip as Dictionary).get("level", 1))}
	# 2026-11-11：蜘蛛网下面**压着一枚确定的棋子**（和视图 `IceCell.chip` 画的是同一枚）。
	# 这样"拖一枚同款棋子压上去"才有比较对象：解锁网 + 合成高一级。
	for cell in board.obstacles.keys():
		if not board.obstacle_types(cell).has("web"):
			continue
		if board.has_item(cell):
			continue
		var webbed := _trapped_chip(cell)
		if not webbed.is_empty():
			board.put(cell, String(webbed.get("entity", "")), int(webbed.get("level", 1)))
	# 2026-11-10：关卡自带的冰从关卡开始计时。
	# 2026-11-12（操作者报的 bug）：倒计时必须从**这一关开始的那一刻**算。
	# 以前记的是 0.0，而 `time` 是整个工程的全局时钟 —— 玩到第 2 关时冰已经
	# 倒数了第 1 关花掉的时间（设 30 秒、进关只剩 15 秒）。
	gen_seq_index = {}
	stockpile_used = false
	stockpile_seq_index = 0
	ice_since = {}
	for cell in board.obstacles.keys():
		var kinds0: Array = board.obstacle_types(cell)
		if kinds0.has("ice"):
			ice_since[cell] = time
	# Multi-cell safeboxes: the level declares the sizes it wants (e.g. ["1x7","2x4"]);
	# their cells are blocked for the whole level, so no spawn/drop/merge lands there.
	# 2026-11-12（操作者）：柜子改成 JSON 指定坐标，只在里占格，不参与规则。
	safeboxes = []
	var raw_safes = lvl.get("safes", [])
	if typeof(raw_safes) == TYPE_ARRAY and not (raw_safes as Array).is_empty():
		var occupied := {}
		for pos in board.cells.keys():
			occupied[pos] = "item"
		for pos in board.obstacles.keys():
			occupied[pos] = "obstacle"
		safeboxes = Safeboxes.parse(raw_safes, board.width, board.height, occupied)
		for cell in Safeboxes.cells(safeboxes):
			board.add_obstacle(cell, "safe")

	orders = []
	var raw_orders = lvl.get("orders", [])
	if typeof(raw_orders) == TYPE_ARRAY:
		for o in raw_orders:
			if typeof(o) == TYPE_DICTIONARY:
				orders.append(_make_order(o))

	generator_state = {}
	stockpile_count = -1
	stockpile_chip = {}
	var gen_table := {}
	if model != null and typeof(model.project) == TYPE_DICTIONARY:
		var table = model.project.get("generators", {})
		if typeof(table) == TYPE_DICTIONARY:
			gen_table = table
	var ids: Array = gen_table.keys()
	ids.sort()
	for gid in ids:
		var cfg = gen_table[gid]
		var charges := 0
		if typeof(cfg) == TYPE_DICTIONARY:
			charges = int(cfg.get("charges", 0))
		generator_state[String(gid)] = {"charges": charges, "ready_at": 0.0}

	# A level without orders is already cleared. Without this, no claim could ever
	# set the flag and level_next would be unreachable — and M0 §2.2 explicitly
	# allows `"orders": []` on a level.
	level_complete_pending = orders.is_empty()
	board_full_pending = false
	_sanitize_board_levels()


## M0 caps every level at 10 (and at the entity's own maxLevel). The validator
## blocks bad data before rendering, but the sim is also driven directly by
## previews/tests, so it must not carry an out-of-range item into its state.
func _sanitize_board_levels() -> void:
	if board == null:
		return
	for pos in board.cells.keys():
		var it = board.cells[pos]
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var cap := _level_cap(String(it.get("entity", "")))
		it["level"] = clampi(int(it.get("level", 1)), 1, cap)


func _make_order(raw: Dictionary) -> Dictionary:
	var mission: Array = []
	var src = raw.get("mission", [])
	if typeof(src) == TYPE_ARRAY:
		for it in src:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			mission.append({
				"entity": String(it.get("entity", "")),
				"level": int(it.get("level", 1)),
				# 2026-11-10：一个任务行可以要**多枚**同名同级棋子（JSON 里的 count，缺省 1）。
				# 角标读它当分母：count=2 就是 0/2、1/2、2/2。
				"need": maxi(int(it.get("count", 1)), 1),
				"have": 0,
			})
	return {
		"id": String(raw.get("id", "")),
		"character": String(raw.get("character", "")),
		"mission": mission,
		"coin": int(raw.get("coin", 0)),
		# 2026-11-09：订单的钻石奖励（订单卡底部那颗）。缺省 0 = 这单不给钻石，
		# 老数据/老 take 不加字段也能照旧跑。
		"gem": int(raw.get("gem", 0)),
		# 2026-11-09：订单卡的体力（闪电）奖励。缺省 0 = 这单不给体力。
		"energy": int(raw.get("energy", 0)),
		"done": false,
	}


func current_level_id() -> String:
	if model == null:
		return ""
	var lvl: Dictionary = model.level(level_index)
	return String(lvl.get("id", ""))


func set_time(t: float) -> void:
	time = t


func _refresh_board_full() -> void:
	if board == null:
		board_full_pending = false
		return
	board_full_pending = board.first_free_cell().x < 0


# ------------------------------------------------------------------ dispatch

func apply(event: Dictionary) -> Dictionary:
	var type := String(event.get("type", ""))
	var at = event.get("at", null)
	if typeof(at) == TYPE_INT or typeof(at) == TYPE_FLOAT:
		time = float(at)
	var res: Dictionary
	if not SimHandlers.is_registered(type):
		res = _err("SIM_UNKNOWN_TYPE", "unregistered sim type: " + type)
	else:
		res = SimHandlers.apply(self, event)
	if typeof(res) != TYPE_DICTIONARY:
		res = _err("SIM_UNKNOWN_TYPE", "handler returned no result")
	if not res.has("code"):
		res["code"] = ""
	if not res.has("note"):
		res["note"] = ""
	# `board_full_pending` is derived state: recompute it after every command so a
	# freed cell clears the flag instead of leaving a stale "board full" forever.
	_refresh_board_full()
	log_events.append({
		"id": String(event.get("id", "")),
		"type": type,
		"at": time,
		"ok": bool(res.get("ok", false)),
		"code": String(res.get("code", "")),
	})
	return res


# ---------------------------------------------------------------------- utils

func _err(code: String, note: String = "") -> Dictionary:
	return {"ok": false, "code": code, "note": note}


func _ok(note: String = "") -> Dictionary:
	return {"ok": true, "code": "", "note": note}


func _to_pos(v) -> Vector2i:
	if typeof(v) != TYPE_ARRAY:
		return INVALID_POS
	var arr: Array = v
	if arr.size() < 2:
		return INVALID_POS
	var x = arr[0]
	var y = arr[1]
	if not (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT):
		return INVALID_POS
	if not (typeof(y) == TYPE_INT or typeof(y) == TYPE_FLOAT):
		return INVALID_POS
	return Vector2i(int(x), int(y))


func _level_cap(entity_id: String) -> int:
	var cap := MAX_LEVEL
	if model != null:
		var ent: Dictionary = model.entity(entity_id)
		if ent.has("maxLevel"):
			var raw = ent["maxLevel"]
			if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
				cap = int(raw)
	if cap <= 0:
		cap = MAX_LEVEL
	return mini(MAX_LEVEL, cap)


func _find_order(order_id: String) -> int:
	for i in range(orders.size()):
		if String(orders[i].get("id", "")) == order_id:
			return i
	return -1


func _all_orders_done() -> bool:
	for o in orders:
		if not bool(o.get("done", false)):
			return false
	return true


func _generator_slot(entity_id: String, cfg: Dictionary) -> Dictionary:
	if generator_state.has(entity_id):
		return generator_state[entity_id]
	var gs := {"charges": int(cfg.get("charges", 0)), "ready_at": 0.0}
	generator_state[entity_id] = gs
	return gs


# ------------------------------------------------------------------------ tap

## Output pool for one generator. Rare entries only join the pool when an
## unfinished order in the CURRENT level asks for exactly that entity + level, so
## "rare direct-order drop" can never be a free bonus.
## 2026-11-12（操作者口径）：真随机池 = 本关**所有订单（含已完成）**的每个子任务，
## 该系列从 lv1 一直到子任务要求的等级，每个 (系列,等级) 只出现一次，等权。
## 例：Ca4 + Cb3 → Ca1/Ca2/Ca3/Ca4/Cb1/Cb2/Cb3，各 1/7。
func random_pool() -> Array:
	var pool: Array = []
	var seen := {}
	if model == null:
		return pool
	for order in orders:
		for m in (order as Dictionary).get("mission", []):
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var eid := String((m as Dictionary).get("entity", ""))
			if eid.is_empty():
				continue
			var ent: Dictionary = model.entity(eid)
			if String(ent.get("kind", "")) != "chip":
				continue
			var need := int((m as Dictionary).get("level", 1))
			var cap := mini(_level_cap(eid), maxi(need, 1))
			for lv in range(1, cap + 1):
				var key := "%s@%d" % [eid, lv]
				if seen.has(key):
					continue
				seen[key] = true
				pool.append({"entity": eid, "level": lv, "weight": 1.0})
	return pool


## 一台生成器这一次该吐什么：先走它自己的顺序队列，吐完转随机池；
## 都没有（极端空数据）再退回旧的 outputs 池，保证老夹具不至于变哑巴。
func pick_generator_output(pos: Vector2i, item: Dictionary, entity_id: String) -> Dictionary:
	var mode := String(item.get("mode", "random"))
	var raw_seq = item.get("sequence", [])
	var seq: Array = raw_seq if typeof(raw_seq) == TYPE_ARRAY else []
	if mode == "sequence" and not seq.is_empty():
		var idx := int(gen_seq_index.get(pos, 0))
		if idx < seq.size():
			var entry = seq[idx]
			if typeof(entry) == TYPE_DICTIONARY:
				gen_seq_index[pos] = idx + 1
				return {"entity": String((entry as Dictionary).get("entity", "")),
						"level": int((entry as Dictionary).get("level", 1)),
						"source": "sequence"}
	var pool := random_pool()
	if pool.is_empty():
		pool = tap_pool(entity_id)
	if pool.is_empty():
		return {}
	var pick_idx: int = rng.pick_weighted(pool)
	if pick_idx < 0 or pick_idx >= pool.size():
		return {}
	var picked: Dictionary = pool[pick_idx]
	return {"entity": String(picked.get("entity", "")), "level": int(picked.get("level", 1)),
			"source": "random"}


func tap_pool(entity_id: String) -> Array:
	var pool: Array = []
	if model == null:
		return pool
	var cfg: Dictionary = model.generator(entity_id)
	if cfg.is_empty():
		return pool
	var outputs = cfg.get("outputs", [])
	if typeof(outputs) == TYPE_ARRAY:
		for o in outputs:
			if typeof(o) != TYPE_DICTIONARY:
				continue
			pool.append({
				"entity": String(o.get("entity", "")),
				"level": int(o.get("level", 1)),
				"weight": float(o.get("weight", 0.0)),
				"rare": false,
			})
	var rares = cfg.get("rareOutputs", [])
	if typeof(rares) == TYPE_ARRAY:
		for r in rares:
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var re := String(r.get("entity", ""))
			var rl := int(r.get("level", 1))
			# directOrder decides WHY a rare is in the pool:
			#   true  (default) - it exists to satisfy an open order: only eligible while
			#                     an unfinished mission still lacks exactly this entity+level
			#   false           - it is an ordinary jackpot: eligible unconditionally
			# The default is `true` on purpose: data written before the flag existed keeps
			# its current behaviour instead of silently gaining unconditional rares.
			var direct_order := bool(r.get("directOrder", true))
			if direct_order and not _rare_is_wanted(re, rl):
				continue
			pool.append({
				"entity": re,
				"level": rl,
				"weight": float(r.get("weight", 0.0)),
				"rare": true,
			})
	return pool


func _rare_is_wanted(entity_id: String, level: int) -> bool:
	for o in orders:
		if bool(o.get("done", false)):
			continue
		for it in o["mission"]:
			if int(it["have"]) >= 1:
				continue
			if String(it["entity"]) == entity_id and int(it["level"]) == level:
				return true
	return false


## Free (unoccupied, unobstructed) cells, in board order. The generator picks one of
## them with the sim RNG so a drop no longer always lands on the first free slot.
func _free_cells() -> Array:
	var out: Array = []
	for y in board.height:
		for x in board.width:
			var pos := Vector2i(x, y)
			if board.has_item(pos) or board.is_blocked(pos):
				continue
			out.append(pos)
	return out


func stockpile_config() -> Dictionary:
	if model == null:
		return {}
	var lvl: Dictionary = model.level(level_index)
	var raw = lvl.get("stockpile", {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func stockpile_remaining() -> int:
	var cfg := stockpile_config()
	if cfg.is_empty() or not bool(cfg.get("enabled", false)):
		return 0
	if stockpile_count < 0:
		stockpile_count = int(cfg.get("count", 0))
	return stockpile_count


## 面板上默认显示的那枚棋子：配置优先，否则取第一个未完成订单的低一级。
func stockpile_preview() -> Dictionary:
	# 2026-11-12：库存有两种投放物 —— 飞棋子 / 飞生成器。
	# 飞棋子时预览"下一枚会飞什么"（顺序优先，否则随机池第一条）；
	# 飞生成器时预览那台生成器（沿用旧口径：第一张未完成订单的第一行等级 - 1）。
	var cfg := stockpile_config()
	var drop := String(cfg.get("drop", "generator"))
	if drop == "chip":
		var seq: Array = cfg.get("sequence", []) if typeof(cfg.get("sequence", [])) == TYPE_ARRAY else []
		var idx := stockpile_seq_index
		if idx < seq.size():
			var e = seq[idx]
			if typeof(e) == TYPE_DICTIONARY:
				return {"kind": "chip", "entity": String((e as Dictionary).get("entity", "")),
						"level": int((e as Dictionary).get("level", 1))}
		var pool := random_pool()
		if not pool.is_empty():
			return {"kind": "chip", "entity": String((pool[0] as Dictionary).get("entity", "")),
					"level": int((pool[0] as Dictionary).get("level", 1))}
		return {}
	if not stockpile_chip.is_empty():
		return stockpile_chip
	var want := String(cfg.get("entity", ""))
	var lvl := int(cfg.get("level", 0))
	if not want.is_empty() and lvl > 0:
		stockpile_chip = {"entity": want, "level": lvl}
		return stockpile_chip
	var gen := String(cfg.get("generator", ""))
	if not gen.is_empty():
		var best := 0
		for order in orders:
			if bool(order.get("done", false)):
				continue
			var mission: Array = order.get("mission", [])
			if not mission.is_empty():
				best = int((mission[0] as Dictionary).get("level", 1))
			break
		if best <= 0:
			best = 2
		stockpile_chip = {"kind": "generator", "entity": gen,
				"level": clampi(best - 1, 1, _level_cap(gen))}
		return stockpile_chip
	return {}


## 左侧库存：点一下少一次，棋子从面板飞到棋盘随机空位（跟生成器同一套飞行数据）。
## 左上角面板"画谁"：配了 icon 就用 icon；飞棋子且没 icon 时固定用生成器实体，
## 否则面板图标会跟着队列里下一枚棋子在变（操作者 2026-11-13 报的）。
func _stockpile_panel_entity() -> String:
	var cfg := stockpile_config()
	if not String(cfg.get("icon", "")).is_empty():
		return String(cfg.get("generator", ""))
	return String(stockpile_preview().get("entity", ""))


func _do_stockpile_tap(_payload: Dictionary) -> Dictionary:
	last_spawn = {}
	var cfg: Dictionary = stockpile_config().duplicate(true)
	if cfg.is_empty() or not bool(cfg.get("enabled", false)):
		return _err("SIM_NO_STOCKPILE", "this level has no stockpile")
	var drop := String(cfg.get("drop", "generator"))
	if stockpile_count < 0:
		stockpile_count = int(cfg.get("count", 0))
	if drop == "generator":
		# 只允许飞一次：之后后台失效（画面不做提示）。
		if stockpile_used:
			return _err("SIM_STOCKPILE_SPENT", "the stockpile already dropped its generator")
	elif stockpile_count <= 0:
		return _err("SIM_STOCKPILE_EMPTY", "stockpile is empty")
	var free_cells := _free_cells()
	if free_cells.is_empty():
		board_full_pending = true
		return _err("SIM_BOARD_FULL", "board is full; stockpile kept")
	var free: Vector2i = free_cells[rng.next_int(free_cells.size())]
	var spawn_icon := String(cfg.get("icon", ""))
	var spawn_icon_level := int(cfg.get("iconLevel", 0))
	var spawn_entity := ""
	var spawn_level := 1
	var spawn_kind := "chip"
	var extra := {}
	if drop == "generator":
		var pick := stockpile_preview()
		if pick.is_empty():
			return _err("SIM_NO_STOCKPILE", "stockpile has no configured generator")
		spawn_entity = String(pick.get("entity", ""))
		spawn_level = clampi(int(pick.get("level", 1)), 1, _level_cap(spawn_entity))
		spawn_kind = "generator"
		# 飞出来的生成器跟库存用同一份产出配置（操作者口径）
		extra["mode"] = String(cfg.get("mode", "random"))
		if typeof(cfg.get("sequence", [])) == TYPE_ARRAY:
			extra["sequence"] = cfg.get("sequence", [])
		stockpile_used = true
	else:
		# 飞棋子：顺序优先，吐完转随机池；受 count 限制。
		var seq: Array = cfg.get("sequence", []) if typeof(cfg.get("sequence", [])) == TYPE_ARRAY else []
		var mode := String(cfg.get("mode", "random"))
		var picked := {}
		if mode == "sequence" and stockpile_seq_index < seq.size():
			var e = seq[stockpile_seq_index]
			if typeof(e) == TYPE_DICTIONARY:
				picked = {"entity": String((e as Dictionary).get("entity", "")),
						"level": int((e as Dictionary).get("level", 1))}
				stockpile_seq_index += 1
		if picked.is_empty():
			var pool := random_pool()
			if pool.is_empty():
				pool = tap_pool(String(cfg.get("generator", "")))
			if pool.is_empty():
				return _err("SIM_NO_STOCKPILE", "stockpile has no configured output")
			var idx: int = rng.pick_weighted(pool)
			if idx < 0 or idx >= pool.size():
				return _err("SIM_NO_STOCKPILE", "weighted output pick failed")
			picked = {"entity": String((pool[idx] as Dictionary).get("entity", "")),
					"level": int((pool[idx] as Dictionary).get("level", 1))}
		spawn_entity = String(picked.get("entity", ""))
		spawn_level = clampi(int(picked.get("level", 1)), 1, _level_cap(spawn_entity))
	# 2026-11-13（操作者报的 bug）：库存的 icon/iconLevel 是给**飞出去的那台生成器**用的；
	# 飞棋子模式下必须让棋子用它自己的系列图，否则 5 次点击全是同一个"生成器样子"的 clip。
	if drop != "generator":
		spawn_icon = ""
		spawn_icon_level = 0
	board.put(free, spawn_entity, spawn_level, spawn_icon, spawn_icon_level, extra)
	last_spawn = {"from": [-1, -1], "to": [free.x, free.y],
			"entity": spawn_entity, "level": spawn_level, "kind": spawn_kind,
			"icon": spawn_icon, "icon_level": spawn_icon_level}
	stockpile_count = maxi(stockpile_count - 1, 0)
	return _ok("stockpile spawned " + spawn_entity + " lv" + str(spawn_level) + " at " + str(free))


func _do_tap(payload: Dictionary) -> Dictionary:
	last_spawn = {}
	var target = payload.get("target", null)
	var pos := INVALID_POS
	if typeof(target) == TYPE_DICTIONARY:
		pos = _to_pos((target as Dictionary).get("slot", null))
	if not board.in_bounds(pos):
		return _err("SIM_SLOT_OOB", "tap target slot is missing or out of bounds")
	if not board.has_item(pos):
		return _err("SIM_TAP_NO_GENERATOR", "tapped slot holds no item")
	var item: Dictionary = board.item(pos)
	var entity_id := String(item.get("entity", ""))
	var ent: Dictionary = model.entity(entity_id)
	if String(ent.get("kind", "")) != "generator":
		return _err("SIM_TAP_NO_GENERATOR", "\"" + entity_id + "\" is not a generator")
	var cfg: Dictionary = model.generator(entity_id)
	if cfg.is_empty():
		return _err("SIM_TAP_NO_GENERATOR", "\"" + entity_id + "\" has no generator behaviour")
	var gs: Dictionary = _generator_slot(entity_id, cfg)
	# 2026-11-05: the generator's stock IS the energy bar — no separate charge counter,
	# so "88 energy" means exactly 88 taps.
	gs["charges"] = int(hud.get("energy", 0))
	if int(hud.get("energy", 0)) <= 0:
		return _err("SIM_NO_ENERGY", "out of energy")
	if time < float(gs["ready_at"]):
		return _err("SIM_COOLDOWN", "\"" + entity_id + "\" ready at " + str(gs["ready_at"]))
	# Check for space BEFORE drawing from the RNG: a rejected command must not
	# consume randomness, otherwise later drops shift and the digest cannot see it.
	var free_cells := _free_cells()
	if free_cells.is_empty():
		board_full_pending = true
		return _err("SIM_BOARD_FULL", "board is full; charge kept")
	var free: Vector2i = free_cells[rng.next_int(free_cells.size())]
	# 2026-11-12（操作者口径）：每台生成器自己的 mode/sequence；顺序吐完转随机池，
	# 随机池 = 本关所有订单子任务 lv1..需求等级，等权。旧 outputs/missionPool 不再参与。
	var picked: Dictionary = pick_generator_output(pos, item, entity_id)
	if picked.is_empty():
		return _err("SIM_TAP_NO_GENERATOR", "\"" + entity_id + "\" has no usable output")
	var spawn_entity := String(picked["entity"])
	var spawn_level: int = int(picked["level"])
	spawn_level = clampi(spawn_level, 1, _level_cap(spawn_entity))
	board.put(free, spawn_entity, spawn_level)
	last_spawn = {"from": [pos.x, pos.y], "to": [free.x, free.y],
			"entity": spawn_entity, "level": spawn_level}
	hud["energy"] = int(hud.get("energy", 0)) - 1
	gs["charges"] = int(hud["energy"])
	gs["ready_at"] = time + float(cfg.get("cooldown", 0.0))
	return _ok("spawned " + spawn_entity + " lv" + str(spawn_level) + " at " + str(free))


# ---------------------------------------------------------------------- merge

func _do_merge(payload: Dictionary) -> Dictionary:
	var from := _to_pos(payload.get("from", null))
	var to := _to_pos(payload.get("to", null))
	if from == INVALID_POS or to == INVALID_POS:
		return _err("SIM_SLOT_OOB", "merge needs two [x, y] cells")
	if from == to:
		return _err("SIM_SAME_CELL", "from and to are the same cell")
	if not board.in_bounds(from) or not board.in_bounds(to):
		return _err("SIM_SLOT_OOB", "merge endpoint is outside the board")
	# 2026-11-11：目标格被**蜘蛛网**盖住时不再一律拒绝 —— 拖一枚同款棋子上去
	# 就是"解锁网 + 合成高一级"。冰/盒子/柜子仍然挡住。
	var web_unlock := false
	if board.is_blocked(to):
		if not board.obstacle_types(to).has("web"):
			return _err("SIM_BLOCKED", "an obstacle covers one of the cells")
		web_unlock = true
	if board.is_blocked(from):
		return _err("SIM_BLOCKED", "an obstacle covers one of the cells")
	if not board.has_item(from):
		return _err("SIM_SOURCE_EMPTY", "source cell is empty")
	if not board.has_item(to):
		return _err("SIM_TARGET_EMPTY", "target cell is empty")
	var src: Dictionary = board.item(from)
	var dst: Dictionary = board.item(to)
	var se := String(src.get("entity", ""))
	var de := String(dst.get("entity", ""))
	if se != de:
		return _err("SIM_ENTITY_MISMATCH", se + " vs " + de)
	# M0 decision: only chips merge. Generators keep a per-entity charge pool, so a
	# merged generator would share charges across levels; specials have no level
	# semantics at all. Everything else is rejected instead of silently levelling up.
	var kind := String(model.entity(se).get("kind", ""))
	if kind != "chip":
		return _err("SIM_NOT_MERGEABLE", se + " is kind=\"" + kind + "\"; only chips merge")
	var sl := int(src.get("level", 1))
	var dl := int(dst.get("level", 1))
	if sl != dl:
		return _err("SIM_LEVEL_MISMATCH", "lv" + str(sl) + " vs lv" + str(dl))
	var next_level := sl + 1
	var cap := _level_cap(se)
	if next_level > cap:
		return _err("SIM_MAX_LEVEL", "lv" + str(next_level) + " exceeds cap " + str(cap))
	if web_unlock:
		board.remove_obstacle(to, "web")
	board.put(to, se, next_level)
	board.take(from)
	# 2026-11-06: a merge breaks the obstacles around it (ice/web lock a chip, the
	# box and the "?" pay out a fresh chip from the generator pool).
	last_unlocks = _unlock_neighbours(to)
	var out := _ok("merged " + se + " into lv" + str(next_level) + " at " + str(to))
	if web_unlock:
		out["web_unlocked"] = true
	return out


## 冰的倒计时长度（秒）。关卡 JSON 的 `ice_seconds` 是**关卡自带冰**的时长
## （第 1 关配成 45 秒，显示 00:45）；每格也可以用 `obstacle.seconds` 单独配。
func ice_seconds(_kind: String, cell: Vector2i) -> int:
	# 关卡里给这一格写了 `seconds` 就用它（每块冰可以不一样）。
	if ice_lengths.has(cell):
		return maxi(int(ice_lengths[cell]), 1)
	var raw = model.level(int(level_index)).get("ice_seconds", 0)
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		var v := int(raw)
		if v > 0:
			return v
	return IceCell.start_seconds(cell)


## 网 / 冰下面那枚棋子：JSON 指定优先，否则沿用确定性生成的那一枚。
func _trapped_chip(cell: Vector2i) -> Dictionary:
	if trapped_chips.has(cell):
		return trapped_chips[cell]
	return IceCell.chip(model.project, cell)


## 某格冰还剩多少秒（给视图显示用，和融化判定同一份算法）。
func ice_remaining(cell: Vector2i) -> int:
	if not ice_since.has(cell):
		return 0
	var start := float(ice_since[cell])
	return maxi(ice_seconds("ice", cell) - int(floor(maxf(time - start, 0.0))), 0)


## 时间推进到 `t`：到点的冰**自己化掉**（这是冰唯一的解锁方式）。
## 返回 [{"cell": [x, y], "kind": "ice", "melt": true}, ...]，实机与成片各播一次。
func tick_to(t: float) -> Array:
	time = maxf(time, t)
	var out: Array = []
	for cell in ice_since.keys():
		var kinds: Array = board.obstacle_types(cell)
		if not kinds.has("ice"):
			continue
		if ice_remaining(cell) > 0:
			continue
		var kind := "ice"
		if board.remove_obstacle(cell, kind):
			var frozen := _trapped_chip(cell)
			if not frozen.is_empty() and not board.has_item(cell):
				board.put(cell, String(frozen.get("entity", "CleanSet_Ca")),
						int(frozen.get("level", 1)))
			ice_since.erase(cell)
			out.append({"cell": [cell.x, cell.y], "kind": kind, "melt": true})
	return out


## 合并炸开的半径：来自关卡 JSON 的 `blast`（1 = 上下左右四个邻格；2 = 曼哈顿距离再外一层）。
func blast_radius() -> int:
	var raw = model.level(int(level_index)).get("blast", 1)
	return clampi(int(raw), 1, 3)


func _unlock_neighbours(centre: Vector2i) -> Array:
	var out: Array = []
	var radius := blast_radius()
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			if absi(dx) + absi(dy) > radius:
				continue
			var cell: Vector2i = centre + Vector2i(dx, dy)
			if not board.in_bounds(cell):
				continue
			var kinds: Array = board.obstacle_types(cell)
			if kinds.is_empty():
				continue
			for kind in kinds:
				var k := String(kind)
				if k == "safe":
					continue
				# 2026-11-10：冰**只能等时间到**自己化掉，合并的爆炸不许波及。
				# 2026-11-11（操作者口径）：蜘蛛网也**不再被爆炸炸开** ——
				# 只能拖一枚同款棋子压上去，解锁并合成高一级（见 _do_merge）。
				if k == "ice" or k == "web":
					continue
				# 2026-11-11（操作者改口径）：蓝盒子（lock）砸开后**只出蜘蛛网 + 棋子**，
				# 冰块那条路去掉（冰只保留关卡自己摆的 `ice`）。
				if k == "lock":
					if board.remove_obstacle(cell, k):
						board.add_obstacle(cell, "web")
						# 2026-11-11：盒子变出来的网**也要压一枚棋子**（和关卡自带的网一致），
						# 否则玩家拖"同款"过来没有比较对象 —— `_do_merge` 只会报目标为空。
						if not board.has_item(cell):
							# 甲：忽略 JSON 里指定的 chip，一律走新的订单随机池
							var webbed_chip := random_pool_pick()
							if webbed_chip.is_empty():
								# 乙：池子为空 → 退回坐标确定性那一枚
								webbed_chip = IceCell.chip(model.project, cell)
							if not webbed_chip.is_empty():
								var wce := String(webbed_chip.get("entity", ""))
								var wcl := int(webbed_chip.get("level", 1))
								board.put(cell, wce, wcl)
								# 视图靠这份表画"网/冰下面压着的那一枚"，不写会画成另一枚
								trapped_chips[cell] = {"entity": wce, "level": wcl}
						out.append({"cell": [cell.x, cell.y], "kind": "box", "became": "web"})
					continue
				if board.remove_obstacle(cell, k):
					if k == "ice" or k == "web":
						var frozen := _trapped_chip(cell)
						if not frozen.is_empty() and not board.has_item(cell):
							board.put(cell, String(frozen.get("entity", "CleanSet_Ca")),
									int(frozen.get("level", 1)))
					elif not board.has_item(cell):
						var picked := random_pool_pick()
						if picked.is_empty():
							picked = IceCell.chip(model.project, cell)
						if not picked.is_empty():
							board.put(cell, String(picked["entity"]), int(picked["level"]))
					out.append({"cell": [cell.x, cell.y], "kind": k})
	return out


## 2026-11-13（操作者口径，1=甲 / 2=乙）：锁盒与问号袋炸开时，
## 里面的 clip 走**和普通生成器「真随机」完全一样**的池子：
## 本关所有订单（含已完成）子任务的系列 lv1..需求，去重等权。
## 池子为空时返回 {}（调用方再退回坐标确定性那一枚）。
func random_pool_pick() -> Dictionary:
	var pool := random_pool()
	if pool.is_empty():
		return {}
	var idx: int = rng.pick_weighted(pool)
	if idx < 0 or idx >= pool.size():
		return {}
	var picked: Dictionary = pool[idx]
	return {"entity": String(picked.get("entity", "")),
			"level": clampi(int(picked.get("level", 1)), 1, _level_cap(String(picked.get("entity", ""))))}


## 高级生成器的产出池：本关未完成订单的子任务行（entity 跟任务，level = 任务级别 - 1）。
func _mission_pool() -> Array:
	var pool: Array = []
	for order in orders:
		if bool(order.get("done", false)):
			continue
		for m in order.get("mission", []):
			var entity := String((m as Dictionary).get("entity", ""))
			if entity.is_empty():
				continue
			var need_lv := int((m as Dictionary).get("level", 1))
			pool.append({
				"entity": entity,
				"level": clampi(need_lv - 1, 1, _level_cap(entity)),
				"weight": 1.0,
				"rare": false,
			})
	return pool


## A deterministic chip from any generator's pool (the box payout).
func _sample_generator_output() -> Dictionary:
	var gen_ids := []
	for eid in model.entity_ids():
		if String(model.entity(eid).get("kind", "")) == "generator":
			gen_ids.append(String(eid))
	gen_ids.sort()
	for gid in gen_ids:
		var pool: Array = tap_pool(gid)
		if pool.is_empty():
			continue
		var idx: int = rng.pick_weighted(pool)
		if idx >= 0 and idx < pool.size():
			var picked: Dictionary = pool[idx]
			return {"entity": String(picked["entity"]),
					"level": clampi(int(picked["level"]), 1, _level_cap(String(picked["entity"])))}
	return {}


## Drag-and-drop swap (2026-11-05): a chip trades places with another chip on an
## unlocked cell, or slides into an empty one. A same entity+level drop is a merge
## instead — that decision is made by FreeMode.drag_action before this command runs.
## Move a generator to another free cell (drag to reposition).
func _do_move(payload: Dictionary) -> Dictionary:
	var from := _to_pos((payload as Dictionary).get("from", null))
	var to := _to_pos((payload as Dictionary).get("to", null))
	if not board.in_bounds(from) or not board.in_bounds(to):
		return _err("SIM_SLOT_OOB", "move endpoints are out of bounds")
	if from == to:
		return _err("SIM_NOOP", "move target equals source")
	if board.is_blocked(to) or board.has_item(to):
		return _err("SIM_BLOCKED", "move target is occupied or blocked")
	if not board.has_item(from):
		return _err("SIM_NO_ITEM", "move source is empty")
	var item: Dictionary = board.item(from)
	var extra := {}
	if item.has("mode"):
		extra["mode"] = String(item.get("mode", ""))
	if item.has("sequence"):
		extra["sequence"] = item.get("sequence", [])
	board.take(from)
	board.put(to, String(item.get("entity", "")), int(item.get("level", 1)),
			String(item.get("icon", "")), int(item.get("icon_level", 0)), extra)
	if gen_seq_index.has(from):
		gen_seq_index[to] = int(gen_seq_index[from])
		gen_seq_index.erase(from)
	last_spawn = {}
	return _ok("moved to " + str(to))


func _do_swap(payload: Dictionary) -> Dictionary:
	var from := _to_pos(payload.get("from", null))
	var to := _to_pos(payload.get("to", null))
	if from == INVALID_POS or to == INVALID_POS:
		return _err("SIM_SLOT_OOB", "swap needs two [x, y] cells")
	if from == to:
		return _err("SIM_SAME_CELL", "from and to are the same cell")
	if not board.in_bounds(from) or not board.in_bounds(to):
		return _err("SIM_SLOT_OOB", "swap endpoint is outside the board")
	if board.is_blocked(from) or board.is_blocked(to):
		return _err("SIM_BLOCKED", "an obstacle covers one of the cells")
	if not board.has_item(from):
		return _err("SIM_SOURCE_EMPTY", "source cell is empty")
	var src: Dictionary = board.item(from)
	var src_entity := String(src.get("entity", ""))
	var src_level := int(src.get("level", 1))
	if String(model.entity(src_entity).get("kind", "")) != "chip":
		return _err("SIM_NOT_SWAPPABLE", src_entity + " is not a chip; only chips swap")
	if not board.has_item(to):
		board.take(from)
		board.put(to, src_entity, src_level)
		return _ok("moved " + src_entity + " to " + str(to))
	var dst: Dictionary = board.item(to)
	var dst_entity := String(dst.get("entity", ""))
	var dst_level := int(dst.get("level", 1))
	if String(model.entity(dst_entity).get("kind", "")) != "chip":
		return _err("SIM_NOT_SWAPPABLE", dst_entity + " is not a chip; only chips swap")
	board.put(to, src_entity, src_level)
	board.put(from, dst_entity, dst_level)
	return _ok("swapped " + src_entity + " and " + dst_entity)


# ------------------------------------------------------------ deliver / claim

func _do_deliver(payload: Dictionary) -> Dictionary:
	var order_id := String(payload.get("order", ""))
	var oi := _find_order(order_id)
	if oi < 0:
		return _err("SIM_ORDER_UNKNOWN", "no order \"" + order_id + "\" in this level")
	var order: Dictionary = orders[oi]
	if bool(order.get("done", false)):
		return _err("SIM_DELIVER_MISMATCH", "order \"" + order_id + "\" is already claimed")
	var from := _to_pos(payload.get("from", null))
	if not board.in_bounds(from):
		return _err("SIM_SLOT_OOB", "deliver source is outside the board")
	if not board.has_item(from):
		return _err("SIM_DELIVER_MISMATCH", "no item to deliver at " + str(from))
	var it: Dictionary = board.item(from)
	# 2026-11-10：交付只推进**一行的一枚**。payload 可以带 row 精确指定行
	# （右键点卡上某个任务格子走这条），不带就按"第一行还没收满的"落。
	var row_hint := int(payload.get("row", -1))
	var k := _unsatisfied_match(order, String(it.get("entity", "")), int(it.get("level", 1)), row_hint)
	if k < 0:
		return _err("SIM_DELIVER_MISMATCH", "item does not match an unsatisfied mission entry")
	order["mission"][k]["have"] = int(order["mission"][k]["have"]) + 1
	board.take(from)
	var out := _ok("delivered " + String(it.get("entity", "")) + " to \"" + order_id + "\"")
	out["row"] = k
	out["have"] = int(order["mission"][k]["have"])
	out["need"] = int(order["mission"][k].get("need", 1))
	# 每一行都收满 = 整单交付完成：和点卡结算走同一段入账逻辑（不重复取棋盘棋子）。
	if _order_rows_full(order):
		_settle_order(order)
		out["settled"] = true
	return out


func _unsatisfied_match(order: Dictionary, entity_id: String, level: int, row_hint: int = -1) -> int:
	var mission: Array = order["mission"]
	# 指定了行就只认那一行（右键点卡上的任务格子）
	if row_hint >= 0:
		if row_hint >= mission.size():
			return -1
		var want: Dictionary = mission[row_hint]
		if int(want["have"]) >= int(want.get("need", 1)):
			return -1
		if String(want["entity"]) == entity_id and int(want["level"]) == level:
			return row_hint
		return -1
	for k in range(mission.size()):
		var it: Dictionary = mission[k]
		if int(it["have"]) >= int(it.get("need", 1)):
			continue
		if String(it["entity"]) == entity_id and int(it["level"]) == level:
			return k
	return -1


## 这一单的每一行都收满了没有（交付完成判定）。
func _order_rows_full(order: Dictionary) -> bool:
	for it in order["mission"]:
		if int(it["have"]) < int(it.get("need", 1)):
			return false
	return true


## 整单入账：奖励、done 标记、关卡完成标记。交付与点卡结算共用这一段。
func _settle_order(order: Dictionary) -> void:
	for it in order["mission"]:
		it["have"] = 0
	order["done"] = true
	hud["coin"] = int(hud.get("coin", 0)) + int(order.get("coin", 0))
	# 2026-11-09：钻石/体力与金币同一时刻入账（视图层据此播飞行 + 数字跳）。
	hud["gem"] = int(hud.get("gem", 0)) + int(order.get("gem", 0))
	hud["energy"] = int(hud.get("energy", 0)) + int(order.get("energy", 0))
	if _all_orders_done():
		level_complete_pending = true


## Claim = "turn in the order". Satisfied either by delivered units (have >= 1)
## or by exact items still sitting on the board, which are consumed row-major.
## Everything is planned before anything is mutated: an unsatisfied claim leaves
## the state - and therefore the digest - untouched.
func _do_order_claim(payload: Dictionary) -> Dictionary:
	var order_id := String(payload.get("order", ""))
	var oi := _find_order(order_id)
	if oi < 0:
		return _err("SIM_ORDER_UNKNOWN", "no order \"" + order_id + "\" in this level")
	var order: Dictionary = orders[oi]
	if bool(order.get("done", false)):
		return _err("SIM_ORDER_DONE", "order \"" + order_id + "\" is already claimed")
	var mission: Array = order["mission"]
	var plan: Array = []
	var used := {}
	# 2026-11-09：交付优先消耗"被点击的那一格"。以前只看 sorted_cells 的第一个匹配格，
	# 第 2 关棋子多、订单多时就会去别处取棋，玩家点的格子原地不动（"交了但没消失"）。
	var src_cell := INVALID_POS
	var raw_src = payload.get("src", null)
	if typeof(raw_src) == TYPE_ARRAY and (raw_src as Array).size() >= 2:
		src_cell = Vector2i(int((raw_src as Array)[0]), int((raw_src as Array)[1]))
	for k in range(mission.size()):
		var need: Dictionary = mission[k]
		var want := int(need.get("need", 1))
		var already := int(need["have"])
		# 已经交付过的那几枚直接记账，剩下的从棋盘上取
		while already < want:
			var found := Vector2i(-1, -1)
			if src_cell.x >= 0 and not used.has(src_cell) and board.has_item(src_cell):
				var clicked: Dictionary = board.item(src_cell)
				if String(clicked.get("entity", "")) == String(need["entity"]) \
						and int(clicked.get("level", 1)) == int(need["level"]):
					found = src_cell
			if found.x < 0:
				for pos in board.sorted_cells():
					if used.has(pos):
						continue
					var it: Dictionary = board.item(pos)
					if String(it.get("entity", "")) == String(need["entity"]) and int(it.get("level", 1)) == int(need["level"]):
						found = pos
						break
			if found.x < 0:
				return _err("SIM_ORDER_UNSATISFIED", "\"" + order_id + "\" still needs " + String(need["entity"]) + " lv" + str(int(need["level"])))
			used[found] = true
			plan.append({"k": k, "delivered": false, "slot": found})
			already += 1

	var taken: Array = []
	for step in plan:
		if not bool(step["delivered"]):
			var slot: Vector2i = step["slot"]
			board.take(slot)
			taken.append([int(slot.x), int(slot.y)])
	_settle_order(order)
	var out := _ok("claimed \"" + order_id + "\"")
	# 视图层据此为每一枚被消耗的棋子播一次飞行动画（2 枚任务就飞 2 枚）。
	out["taken"] = taken
	return out


# ------------------------------------------------------------ level / energy

func _do_board_full(_payload: Dictionary) -> Dictionary:
	return _ok("board_full is a no-op marker; nothing changed")


func _do_energy_tick(payload: Dictionary) -> Dictionary:
	var delta := 0
	var raw = payload.get("delta", 0)
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		delta = int(raw)
	var before := int(hud.get("energy", 0))
	hud["energy"] = maxi(0, before + delta)
	return _ok("energy " + str(before) + " -> " + str(int(hud["energy"])))


func _do_level_complete(_payload: Dictionary) -> Dictionary:
	if not level_complete_pending:
		return _err("SIM_LEVEL_NOT_COMPLETE", "every order must be claimed first")
	return _ok("level \"" + current_level_id() + "\" is complete")


func _do_level_next(_payload: Dictionary) -> Dictionary:
	if not level_complete_pending:
		return _err("SIM_LEVEL_NOT_COMPLETE", "every order must be claimed first")
	var next_index := level_index + 1
	if model == null or next_index >= model.level_count():
		return _err("SIM_NO_MORE_LEVELS", "no level after index " + str(level_index))
	level_index = next_index
	_load_level(level_index)
	return _ok("entered \"" + current_level_id() + "\"")


# ------------------------------------------------------------- snapshots

func snapshot() -> Dictionary:
	# 2026-11-09：库存次数进快照，实机与成片都读同一份（成片才能回放 stockpile_tap）。
	var hud_snap := {}
	var hud_keys: Array = hud.keys()
	hud_keys.sort()
	for k in hud_keys:
		hud_snap[String(k)] = hud[k]

	var gen_snap := {}
	var gen_ids: Array = generator_state.keys()
	gen_ids.sort()
	for gid in gen_ids:
		var gs: Dictionary = generator_state[gid]
		gen_snap[String(gid)] = {
			"charges": int(gs.get("charges", 0)),
			"ready_at": float(gs.get("ready_at", 0.0)),
		}

	var order_rows: Array = []
	for o in orders:
		var mission_rows: Array = []
		for it in o["mission"]:
			# 2026-11-10：第 4 位带上 need（一行可能要多枚），视图层据此画 0/2、1/2
			mission_rows.append([String(it["entity"]), int(it["level"]), int(it["have"]),
					int(it.get("need", 1))])
		order_rows.append({
			"id": String(o["id"]),
			"character": String(o["character"]),
			"mission": mission_rows,
			"coin": int(o["coin"]),
			"gem": int(o.get("gem", 0)),
			"energy": int(o.get("energy", 0)),
			"done": bool(o["done"]),
		})

	var board_snap := {}
	if board != null:
		board_snap = board.snapshot()
		# 2026-11-11：网/冰下面那枚棋子与每格冰的秒数由 JSON 决定，
		# 视图层只照着画 —— 不再各算一份 IceCell.chip()。
		var trapped := {}
		for cell in trapped_chips.keys():
			trapped["%d,%d" % [cell.x, cell.y]] = (trapped_chips[cell] as Dictionary).duplicate()
		board_snap["trapped"] = trapped
		var ice_len := {}
		for cell in ice_lengths.keys():
			ice_len["%d,%d" % [cell.x, cell.y]] = int(ice_lengths[cell])
		board_snap["ice_lengths"] = ice_len

	return {
		"level_index": level_index,
		"stockpile": {
			"enabled": not stockpile_config().is_empty() and bool(stockpile_config().get("enabled", false)),
			"count": stockpile_remaining(),
			# 面板外观要固定：飞棋子且没配 icon 时，实体用**生成器**（不能跟着下一枚棋子变）
			"entity": _stockpile_panel_entity(),
			"level": int(stockpile_preview().get("level", 1)),
			"kind": String(stockpile_preview().get("kind", "chip")),
			# 2026-11-13（操作者）：左上角面板的图标必须**固定**，不能跟着下一枚棋子在变。
			# 配了 icon 就一直是它；没配就走生成器图。飞出去的棋子用自己的图（见 _do_stockpile_tap）。
			"icon": String(stockpile_config().get("icon", "")),
			"iconLevel": int(stockpile_config().get("iconLevel", 0)),
			"drop": String(stockpile_config().get("drop", "generator")),
			"used": stockpile_used,
		},
		"level_id": current_level_id(),
		"hud": hud_snap,
		"orders": order_rows,
		"generators": gen_snap,
		"level_complete_pending": level_complete_pending,
		"board_full_pending": board_full_pending,
		"board": board_snap,
	}


func digest() -> String:
	return StateDigest.of(snapshot())
