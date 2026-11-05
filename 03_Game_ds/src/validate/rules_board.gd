extends RefCounted
## Board geometry rules: 7x9 baseline, slot coordinates, occupancy, slot levels,
## obstacles (lock / web / bubble / bag / ice).
##
## Obstacles are grid decorations, not slots: per the M0 sample an obstacle may sit
## on an empty cell (that is exactly how a "blocked but empty" cell looks).

const Ctx = preload("res://src/validate/validate_ctx.gd")

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
	# abort gate (N1): reached unless a runtime script error interrupted the loop
	ctx.rule_done()
