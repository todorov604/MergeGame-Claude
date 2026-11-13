extends RefCounted
## Board geometry rules: 7x9 baseline, slot coordinates, occupancy, slot levels,
## obstacles (lock / web / bubble / bag / ice).
##
## Obstacles are grid decorations, not slots: per the M0 sample an obstacle may sit
## on an empty cell (that is exactly how a "blocked but empty" cell looks).

const Ctx = preload("res://src/validate/validate_ctx.gd")
const Safeboxes = preload("res://src/core/safeboxes.gd")

const KNOWN_OBSTACLE_TYPES := ["lock", "web", "bubble", "bag", "ice"]
const M0_BOARD_W := 7
const M0_BOARD_H := 9
const M0_MAX_LEVEL := 10


static func check(ctx) -> void:
	var levels = ctx.project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		# the schema rule owns the type error; ending the abort gate here keeps a
		# malformed project from being reported as an internal script error too
		ctx.rule_done()
		return
	var entities = ctx.project.get("entities", {})
	var ents: Dictionary = entities if typeof(entities) == TYPE_DICTIONARY else {}
	for li in levels.size():
		var lv = levels[li]
		if typeof(lv) != TYPE_DICTIONARY:
			continue
		var base := "levels[%d]" % li
		var board = lv.get("board", null)
		if typeof(board) != TYPE_DICTIONARY:
			continue
		var w := Ctx.as_int(board.get("width", null), -1)
		var h := Ctx.as_int(board.get("height", null), -1)
		if w <= 0 or h <= 0:
			ctx.err("BOARD_DIM", base + ".board", "width/height must be positive integers (got %dx%d)" % [w, h])
			continue
		if w != M0_BOARD_W or h != M0_BOARD_H:
			ctx.warn("BOARD_DIM_NON_M0", base + ".board", "M0 baseline board is %dx%d (got %dx%d)" % [M0_BOARD_W, M0_BOARD_H, w, h])

		# ---- slots ----
		var slots = board.get("slots", [])
		if typeof(slots) != TYPE_ARRAY:
			ctx.err("SCHEMA_TYPE", base + ".board.slots", "slots must be an array")
			slots = []
		var seen := {}
		for si in slots.size():
			var s = slots[si]
			var ipath := "%s.board.slots[%d]" % [base, si]
			if typeof(s) != TYPE_DICTIONARY:
				ctx.err("SCHEMA_TYPE", ipath, "slot must be an object")
				continue
			var x := Ctx.as_int(s.get("x", null), -1)
			var y := Ctx.as_int(s.get("y", null), -1)
			if x < 0 or y < 0 or x >= w or y >= h:
				ctx.err("SLOT_OOB", ipath, "slot (%d,%d) is outside %dx%d" % [x, y, w, h])
				continue
			var key := "%d,%d" % [x, y]
			if seen.has(key):
				ctx.err("SLOT_DUP", ipath, "slot (%d,%d) is already occupied by %s" % [x, y, String(seen[key])])
			else:
				seen[key] = ipath
			if s.has("chip"):
				ctx.err("SLOT_CHIP_KEY_LEGACY", ipath + ".chip", "schema v2 slots use `entity`; the legacy `chip` key was removed")
			var raw_eid = s.get("entity", null)
			var eid := ""
			if not Ctx.is_string(raw_eid):
				ctx.err("SLOT_ENTITY_TYPE", ipath + ".entity", "slot entity must be a string (got %s)" % type_string(typeof(raw_eid)))
			else:
				eid = String(raw_eid)
			var ent = ents.get(eid, null)
			var lvl = s.get("level", null)
			if not Ctx.is_int_val(lvl):
				ctx.err("SLOT_LEVEL_RANGE", ipath + ".level", "slot level must be an integer")
				continue
			var l := Ctx.as_int(lvl)
			if typeof(ent) == TYPE_DICTIONARY:
				var cap: int = mini(M0_MAX_LEVEL, Ctx.as_int(ent.get("maxLevel", M0_MAX_LEVEL), M0_MAX_LEVEL))
				if l < 1 or l > cap:
					ctx.err("SLOT_LEVEL_RANGE", ipath + ".level", "%s level %d is outside 1..%d" % [eid, l, cap])
			elif l < 1 or l > M0_MAX_LEVEL:
				ctx.err("SLOT_LEVEL_RANGE", ipath + ".level", "slot level %d is outside 1..%d" % [l, M0_MAX_LEVEL])
			# 2026-11-12：生成器产出模式（per-slot）：random / sequence + 顺序队列
			if s.has("mode"):
				var raw_mode = s.get("mode", null)
				if not Ctx.is_string(raw_mode):
					ctx.err("GEN_MODE_INVALID", ipath + ".mode", "generator mode must be a string")
				elif not ["random", "sequence"].has(String(raw_mode)):
					ctx.err("GEN_MODE_INVALID", ipath + ".mode",
							"generator mode must be random or sequence (got \"%s\")" % String(raw_mode))
			if s.has("sequence"):
				_validate_sequence(ctx, s.get("sequence", null), ipath + ".sequence", ents)

			# 2026-11-12：编辑器可以给某一格「换图标」（slot.icon）。它必须是已登记的棋子系列，
			# 否则游戏侧会静默退回 entity 的图，看起来像"改了没生效"。
			if s.has("icon"):
				var raw_icon = s.get("icon", null)
				if not Ctx.is_string(raw_icon):
					ctx.err("SLOT_ICON_TYPE", ipath + ".icon", "slot icon must be a string (got %s)" % type_string(typeof(raw_icon)))
				elif not String(raw_icon).is_empty():
					var ient = ents.get(String(raw_icon), null)
					if typeof(ient) != TYPE_DICTIONARY:
						ctx.err("SLOT_ICON_UNKNOWN", ipath + ".icon", "slot icon \"%s\" is not a registered entity" % String(raw_icon))
					elif String((ient as Dictionary).get("kind", "chip")) != "chip":
						ctx.err("SLOT_ICON_TYPE_ENTITY", ipath + ".icon", "slot icon \"%s\" is not a chip series" % String(raw_icon))
			# 图标等级：只在写了 icon 的时候有意义，1..10
			if s.has("iconLevel"):
				var raw_ilv = s.get("iconLevel", null)
				if not Ctx.is_int_val(raw_ilv):
					ctx.err("SLOT_ICON_LEVEL_TYPE", ipath + ".iconLevel", "slot iconLevel must be an integer")
				elif int(raw_ilv) < 1 or int(raw_ilv) > M0_MAX_LEVEL:
					ctx.err("SLOT_ICON_LEVEL_RANGE", ipath + ".iconLevel",
							"slot iconLevel %d is outside 1..%d" % [int(raw_ilv), M0_MAX_LEVEL])

		# ---- obstacles ----
		var obs = lv.get("obstacles", [])
		if typeof(obs) != TYPE_ARRAY:
			ctx.err("SCHEMA_TYPE", base + ".obstacles", "obstacles must be an array")
			obs = []
		var seen_ob := {}
		for oi in obs.size():
			var o = obs[oi]
			var ipath2 := "%s.obstacles[%d]" % [base, oi]
			if typeof(o) != TYPE_DICTIONARY:
				ctx.err("SCHEMA_TYPE", ipath2, "obstacle must be an object")
				continue
			var slot = o.get("slot", null)
			if typeof(slot) != TYPE_ARRAY or slot.size() != 2:
				ctx.err("OBSTACLE_SLOT", ipath2 + ".slot", "obstacle slot must be [x, y]")
				continue
			var ox := Ctx.as_int(slot[0], -1)
			var oy := Ctx.as_int(slot[1], -1)
			if ox < 0 or oy < 0 or ox >= w or oy >= h:
				ctx.err("OBSTACLE_OOB", ipath2 + ".slot", "obstacle (%d,%d) is outside %dx%d" % [ox, oy, w, h])
				continue
			var raw_t = o.get("type", null)
			if not Ctx.is_string(raw_t):
				ctx.err("OBSTACLE_TYPE", ipath2 + ".type", "obstacle type must be a string (got %s)" % type_string(typeof(raw_t)))
				continue
			var t := String(raw_t)
			if not KNOWN_OBSTACLE_TYPES.has(t):
				ctx.err("OBSTACLE_TYPE", ipath2 + ".type", "unknown obstacle type \"%s\" (expected one of %s)" % [t, str(KNOWN_OBSTACLE_TYPES)])
				continue
			var okey := "%d,%d|%s" % [ox, oy, t]
			if seen_ob.has(okey):
				ctx.err("OBSTACLE_DUP", ipath2, "duplicate %s obstacle at (%d,%d)" % [t, ox, oy])
			else:
				seen_ob[okey] = ipath2
		# ---- safeboxes（2026-11-12：JSON 指定坐标，旧的尺寸字符串写法已废弃）----
		var occupied := {}
		if typeof(slots) == TYPE_ARRAY:
			for raw_s in slots:
				if typeof(raw_s) == TYPE_DICTIONARY:
					occupied[Vector2i(Ctx.as_int(raw_s.get("x", -1), -1), Ctx.as_int(raw_s.get("y", -1), -1))] = "a chip"
		if typeof(obs) == TYPE_ARRAY:
			for raw_o in obs:
				if typeof(raw_o) == TYPE_DICTIONARY:
					var oslot = raw_o.get("slot", null)
					if typeof(oslot) == TYPE_ARRAY and (oslot as Array).size() == 2:
						occupied[Vector2i(Ctx.as_int(oslot[0], -1), Ctx.as_int(oslot[1], -1))] = "%s obstacle" % str(raw_o.get("type", "an"))
		var safe_errs: Array = Safeboxes.validate_entries(lv.get("safes", []), w, h, occupied)
		for raw_e in safe_errs:
			var e: Dictionary = raw_e
			var idx := int(e.get("index", -1))
			var spath := base + ".safes" + (("[%d]" % idx) if idx >= 0 else "")
			ctx.err(String(e.get("code", "SAFE_INVALID")), spath, String(e.get("msg", "invalid safebox")))
		# 库存面板的图标覆盖（stockpile.icon）同样要指向一个已登记的棋子系列
		var sp = lv.get("stockpile", null)
		if typeof(sp) == TYPE_DICTIONARY and (sp as Dictionary).has("icon"):
			var raw_sp_icon = (sp as Dictionary).get("icon", null)
			var spath2 := base + ".stockpile.icon"
			if not Ctx.is_string(raw_sp_icon):
				ctx.err("STOCKPILE_ICON_TYPE", spath2, "stockpile icon must be a string (got %s)" % type_string(typeof(raw_sp_icon)))
			elif not String(raw_sp_icon).is_empty():
				var sp_ent = ents.get(String(raw_sp_icon), null)
				if typeof(sp_ent) != TYPE_DICTIONARY:
					ctx.err("STOCKPILE_ICON_UNKNOWN", spath2, "stockpile icon \"%s\" is not a registered entity" % String(raw_sp_icon))
				elif String((sp_ent as Dictionary).get("kind", "chip")) != "chip":
					ctx.err("STOCKPILE_ICON_TYPE_ENTITY", spath2, "stockpile icon \"%s\" is not a chip series" % String(raw_sp_icon))
			if (sp as Dictionary).has("iconLevel"):
				var raw_sp_lv = (sp as Dictionary).get("iconLevel", null)
				if not Ctx.is_int_val(raw_sp_lv):
					ctx.err("STOCKPILE_ICON_LEVEL_TYPE", base + ".stockpile.iconLevel", "stockpile iconLevel must be an integer")
				elif int(raw_sp_lv) < 1 or int(raw_sp_lv) > M0_MAX_LEVEL:
					ctx.err("STOCKPILE_ICON_LEVEL_RANGE", base + ".stockpile.iconLevel",
							"stockpile iconLevel %d is outside 1..%d" % [int(raw_sp_lv), M0_MAX_LEVEL])
	# abort gate (N1): reached unless a runtime script error interrupted the loop
	ctx.rule_done()

## 顺序队列：必须是数组，每项 {entity, level}；entity 要是已登记的棋子，level 1..该系列 maxLevel。
static func _validate_sequence(ctx, raw, path: String, ents: Dictionary) -> void:
	if typeof(ents) != TYPE_DICTIONARY:
		return   # 上层已报 SCHEMA/ENTITY 错误，这里不要再崩一次
	if typeof(raw) != TYPE_ARRAY:
		ctx.err("SEQUENCE_TYPE", path, "sequence must be an array")
		return
	var arr: Array = raw
	for i in arr.size():
		var item = arr[i]
		var ip := "%s[%d]" % [path, i]
		if typeof(item) != TYPE_DICTIONARY:
			ctx.err("SEQUENCE_ITEM", ip, "sequence item must be an object")
			continue
		var raw_e = (item as Dictionary).get("entity", null)
		if not Ctx.is_string(raw_e):
			ctx.err("SEQUENCE_ENTITY_TYPE", ip + ".entity", "sequence entity must be a string")
			continue
		var eid := String(raw_e)
		var ent = ents.get(eid, null)
		if typeof(ent) != TYPE_DICTIONARY:
			ctx.err("SEQUENCE_ENTITY_UNKNOWN", ip + ".entity", "sequence entity \"%s\" is not registered" % eid)
			continue
		if String((ent as Dictionary).get("kind", "chip")) != "chip":
			ctx.err("SEQUENCE_ENTITY_KIND", ip + ".entity", "sequence entity \"%s\" is not a chip" % eid)
			continue
		var raw_l = (item as Dictionary).get("level", null)
		if not Ctx.is_int_val(raw_l):
			ctx.err("SEQUENCE_LEVEL_TYPE", ip + ".level", "sequence level must be an integer")
			continue
		var lv := Ctx.as_int(raw_l)
		var cap: int = mini(M0_MAX_LEVEL, Ctx.as_int((ent as Dictionary).get("maxLevel", M0_MAX_LEVEL), M0_MAX_LEVEL))
		if lv < 1 or lv > cap:
			ctx.err("SEQUENCE_LEVEL_RANGE", ip + ".level",
					"%s level %d is outside 1..%d" % [eid, lv, cap])
