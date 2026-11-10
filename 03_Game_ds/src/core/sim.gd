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
	# 2026-11-10：关卡自带的冰从关卡开始计时。
	ice_since = {}
	for cell in board.obstacles.keys():
		var kinds0: Array = board.obstacle_types(cell)
		if kinds0.has("ice") or kinds0.has("icebox"):
			ice_since[cell] = 0.0
	# Multi-cell safeboxes: the level declares the sizes it wants (e.g. ["1x7","2x4"]);
	# their cells are blocked for the whole level, so no spawn/drop/merge lands there.
	safeboxes = []
	var sizes = lvl.get("safes", [])
	if typeof(sizes) == TYPE_ARRAY and not (sizes as Array).is_empty():
		var occupied: Array = []
		for pos in board.cells.keys():
			occupied.append(pos)
		safeboxes = Safeboxes.layout(board.width, board.height, seed_value, index, sizes, occupied)
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
		"star": int(raw.get("star", 0)),
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
	# 2026-11-06: 进关时定死一种产物，交付后不换（它就是个固定生成器）。
	if not stockpile_chip.is_empty():
		return stockpile_chip
	var cfg := stockpile_config()
	var want := String(cfg.get("entity", ""))
	var lvl := int(cfg.get("level", 0))
	if not want.is_empty() and lvl > 0:
		stockpile_chip = {"entity": want, "level": lvl}
		return stockpile_chip
	for order in orders:
		if bool(order.get("done", false)):
			continue
		for m in order.get("mission", []):
			var entity := String((m as Dictionary).get("entity", ""))
			if entity.is_empty():
				continue
			stockpile_chip = {"entity": entity,
					"level": maxi(int((m as Dictionary).get("level", 1)) - 1, 1)}
			return stockpile_chip
	return {}


## 左侧库存：点一下少一次，棋子从面板飞到棋盘随机空位（跟生成器同一套飞行数据）。
func _do_stockpile_tap(_payload: Dictionary) -> Dictionary:
	last_spawn = {}
	var cfg: Dictionary = {}
	if model != null:
		var lvl: Dictionary = model.level(level_index)
		var raw = lvl.get("stockpile", {})
		if typeof(raw) == TYPE_DICTIONARY:
			cfg = raw
	if stockpile_count < 0 and not cfg.is_empty():
		stockpile_count = int(cfg.get("count", 0))
	cfg = cfg.duplicate(true)
	cfg["count"] = stockpile_count
	if cfg.is_empty() or not bool(cfg.get("enabled", false)):
		return _err("SIM_NO_STOCKPILE", "this level has no stockpile")
	if int(cfg.get("count", 0)) <= 0:
		return _err("SIM_STOCKPILE_EMPTY", "stockpile is empty")
	var free_cells := _free_cells()
	if free_cells.is_empty():
		board_full_pending = true
		return _err("SIM_BOARD_FULL", "board is full; stockpile kept")
	var free: Vector2i = free_cells[rng.next_int(free_cells.size())]
	var pick := stockpile_preview()
	if pick.is_empty():
		return _err("SIM_NO_STOCKPILE", "stockpile has no configured chip")
	var spawn_entity := String(pick["entity"])
	var spawn_level: int = clampi(int(pick["level"]), 1, _level_cap(spawn_entity))
	board.put(free, spawn_entity, spawn_level)
	last_spawn = {"from": [-1, -1], "to": [free.x, free.y],
			"entity": spawn_entity, "level": spawn_level}
	stockpile_count = int(cfg.get("count", 0)) - 1
	return _ok("stockpile spawned " + spawn_entity + " lv" + str(spawn_level) + " at " + str(free))


## 配置优先；否则取「当前订单需求的低一级」，多订单时按 RNG 抽一个。
func _stockpile_output(cfg: Dictionary) -> Dictionary:
	var want := String(cfg.get("entity", ""))
	var lvl := int(cfg.get("level", 0))
	if not want.is_empty() and lvl > 0:
		return {"entity": want, "level": lvl}
	var candidates: Array = []
	for order in orders:
		if bool(order.get("done", false)):
			continue
		for m in order.get("mission", []):
			var entity := String((m as Dictionary).get("entity", ""))
			var need := int((m as Dictionary).get("level", 1))
			if entity.is_empty():
				continue
			candidates.append({"entity": entity, "level": maxi(need - 1, 1)})
	if candidates.is_empty():
		return {}
	return candidates[rng.next_int(candidates.size())]


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
	var pool: Array = tap_pool(entity_id)
	if pool.is_empty():
		return _err("SIM_TAP_NO_GENERATOR", "\"" + entity_id + "\" has no usable output")
	var idx: int = rng.pick_weighted(pool)
	if idx < 0 or idx >= pool.size():
		return _err("SIM_TAP_NO_GENERATOR", "weighted output pick failed")
	var picked: Dictionary = pool[idx]
	var spawn_entity := String(picked["entity"])
	var spawn_level: int = clampi(int(picked["level"]), 1, _level_cap(spawn_entity))
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
	if board.is_blocked(from) or board.is_blocked(to):
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
	board.put(to, se, next_level)
	board.take(from)
	# 2026-11-06: a merge breaks the obstacles around it (ice/web lock a chip, the
	# box and the "?" pay out a fresh chip from the generator pool).
	last_unlocks = _unlock_neighbours(to)
	return _ok("merged " + se + " into lv" + str(next_level) + " at " + str(to))


## 冰的倒计时长度（秒）。关卡 JSON 的 `ice_seconds` 是**关卡自带冰**的时长
## （第 1 关配成 45 秒，显示 00:45）；盒子开出来的 `icebox` 仍按 5~10 分钟。
func ice_seconds(kind: String, cell: Vector2i) -> int:
	if kind == "icebox":
		return IceCell.start_seconds_between(cell, 5 * 60, 10 * 60)
	var raw = model.level(int(level_index)).get("ice_seconds", 0)
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		var v := int(raw)
		if v > 0:
			return v
	return IceCell.start_seconds(cell)


## 某格冰还剩多少秒（给视图显示用，和融化判定同一份算法）。
func ice_remaining(cell: Vector2i) -> int:
	if not ice_since.has(cell):
		return 0
	var kinds: Array = board.obstacle_types(cell)
	var kind := "icebox" if kinds.has("icebox") else "ice"
	var start := float(ice_since[cell])
	return maxi(ice_seconds(kind, cell) - int(floor(maxf(time - start, 0.0))), 0)


## 时间推进到 `t`：到点的冰**自己化掉**（这是冰唯一的解锁方式）。
## 返回 [{"cell": [x, y], "kind": "ice"/"icebox", "melt": true}, ...]，实机与成片各播一次。
func tick_to(t: float) -> Array:
	time = maxf(time, t)
	var out: Array = []
	for cell in ice_since.keys():
		var kinds: Array = board.obstacle_types(cell)
		if not kinds.has("ice") and not kinds.has("icebox"):
			continue
		if ice_remaining(cell) > 0:
			continue
		var kind := "icebox" if kinds.has("icebox") else "ice"
		if board.remove_obstacle(cell, kind):
			var frozen := IceCell.chip(model.project, cell)
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
				if k == "ice" or k == "icebox":
					continue
				# 2026-11-10：蓝盒子（lock）不再是死物 —— 砸开后变成**网 + 棋子**
				# 或 **冰 + 棋子（倒计时 5~10 分钟）**，二选一按格子坐标定死（成片可复现）。
				if k == "lock":
					if board.remove_obstacle(cell, k):
						# 用高位混一下，别让整片菱形都落在同一种（13x+7y 的奇偶性在局部会相关）
						var h := absi(cell.x * 73856093 ^ cell.y * 19349663)
						var rolled := "icebox" if (h >> 5) % 2 == 1 else "web"
						board.add_obstacle(cell, rolled)
						if rolled == "icebox":
							ice_since[cell] = time
						out.append({"cell": [cell.x, cell.y], "kind": "box", "became": rolled})
					continue
				if board.remove_obstacle(cell, k):
					if k == "ice" or k == "web" or k == "icebox":
						var frozen := IceCell.chip(model.project, cell)
						if not frozen.is_empty() and not board.has_item(cell):
							board.put(cell, String(frozen.get("entity", "CleanSet_Ca")),
									int(frozen.get("level", 1)))
					elif not board.has_item(cell):
						var picked := _sample_generator_output()
						if not picked.is_empty():
							board.put(cell, String(picked["entity"]), int(picked["level"]))
					out.append({"cell": [cell.x, cell.y], "kind": k})
	return out


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
	board.take(from)
	board.put(to, String(item.get("entity", "")), int(item.get("level", 1)))
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
	hud["star"] = int(hud.get("star", 0)) + int(order.get("star", 0))
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
			"star": int(o["star"]),
			"coin": int(o["coin"]),
			"gem": int(o.get("gem", 0)),
			"energy": int(o.get("energy", 0)),
			"done": bool(o["done"]),
		})

	var board_snap := {}
	if board != null:
		board_snap = board.snapshot()

	return {
		"level_index": level_index,
		"stockpile": {
			"enabled": not stockpile_config().is_empty() and bool(stockpile_config().get("enabled", false)),
			"count": stockpile_remaining(),
			"entity": String(stockpile_preview().get("entity", "")),
			"level": int(stockpile_preview().get("level", 1)),
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
