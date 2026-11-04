extends RefCounted
## Level / entity / generator / order rules, including the M0 level-10 cap,
## the "levels array order is the level order, `next` is deleted" rule and
## order reachability (a mission item must be producible or already on the board).

const Ctx = preload("res://src/validate/validate_ctx.gd")

const M0_MAX_LEVEL := 10
const M0_MAX_LEVELS := 10
const KNOWN_KINDS := ["chip", "generator", "special", "character"]


static func check(ctx) -> void:
	_check_entities(ctx)
	_check_levels(ctx)
	_check_generators(ctx)
	_check_orders(ctx)


static func _check_entities(ctx) -> void:
	var entities = ctx.project.get("entities", {})
	if typeof(entities) != TYPE_DICTIONARY:
		return
	for eid in entities.keys():
		var key := String(eid)
		var path := "entities.%s" % key
		var e = entities[eid]
		if typeof(e) != TYPE_DICTIONARY:
			ctx.err("SCHEMA_TYPE", path, "entity entry must be an object")
			continue
		var kind := String(e.get("kind", ""))
		if kind.is_empty():
			ctx.err("ENTITY_KIND", path + ".kind", "entity kind is required")
			continue
		if not KNOWN_KINDS.has(kind):
			ctx.err("ENTITY_KIND", path + ".kind", "unknown entity kind \"%s\" (expected one of %s)" % [kind, str(KNOWN_KINDS)])
			continue
		if kind == "chip":
			if not Ctx.is_str_val(e.get("family", "")):
				ctx.err("ENTITY_CHIP_FAMILY", path + ".family", "chip entities need a family")
			if not Ctx.is_str_val(e.get("chain", "")):
				ctx.err("ENTITY_CHIP_CHAIN", path + ".chain", "chip entities need a chain")
			var max_level = e.get("maxLevel", null)
			if not Ctx.is_int_val(max_level):
				ctx.err("ENTITY_MAX_LEVEL", path + ".maxLevel", "chip maxLevel must be an integer")
			else:
				var ml := Ctx.as_int(max_level)
				if ml < 1 or ml > M0_MAX_LEVEL:
					ctx.err("ENTITY_MAX_LEVEL", path + ".maxLevel", "chip maxLevel must be 1..%d in M0 (got %d)" % [M0_MAX_LEVEL, ml])
		elif kind == "generator":
			var gmax = e.get("maxLevel", null)
			if not Ctx.is_int_val(gmax) or Ctx.as_int(gmax) < 1:
				ctx.err("ENTITY_MAX_LEVEL", path + ".maxLevel", "generator maxLevel must be an integer >= 1")
		# special / character need no numeric fields in M0


static func _check_levels(ctx) -> void:
	var levels = ctx.project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		ctx.err("SCHEMA_TYPE", "levels", "levels must be an array")
		return
	ctx.stats["levels"] = levels.size()
	if levels.is_empty():
		ctx.err("LEVELS_EMPTY", "levels", "at least one level is required")
		return
	if levels.size() > M0_MAX_LEVELS:
		ctx.err("LEVELS_OVER_CAP", "levels", "M0 supports at most %d levels (got %d)" % [M0_MAX_LEVELS, levels.size()])
	var seen := {}
	for li in levels.size():
		var lv = levels[li]
		var base := "levels[%d]" % li
		if typeof(lv) != TYPE_DICTIONARY:
			ctx.err("SCHEMA_TYPE", base, "level must be an object")
			continue
		if lv.has("next"):
			ctx.err("LEVEL_NEXT_REMOVED", base + ".next", "`next` was removed in schema v2; level order is the levels array order")
		var id := String(lv.get("id", ""))
		if id.is_empty():
			ctx.err("LEVEL_ID_MISSING", base + ".id", "level id is required")
		elif seen.has(id):
			ctx.err("LEVEL_DUP_ID", base + ".id", "duplicate level id \"%s\" (first at %s)" % [id, seen[id]])
		else:
			seen[id] = base
		if typeof(lv.get("board", null)) != TYPE_DICTIONARY:
			ctx.err("SCHEMA_TYPE", base + ".board", "board must be an object")
		if typeof(lv.get("orders", null)) != TYPE_ARRAY:
			ctx.err("SCHEMA_TYPE", base + ".orders", "orders must be an array")
		if typeof(lv.get("obstacles", null)) != TYPE_ARRAY:
			ctx.err("SCHEMA_TYPE", base + ".obstacles", "obstacles must be an array")


static func _check_generators(ctx) -> void:
	var generators = ctx.project.get("generators", {})
	if typeof(generators) != TYPE_DICTIONARY:
		return
	for gid in generators.keys():
		var key := String(gid)
		var path := "generators.%s" % key
		var g = generators[gid]
		if typeof(g) != TYPE_DICTIONARY:
			continue
		for bad_key in ["entity", "visual", "icon", "chips"]:
			if g.has(bad_key):
				ctx.err("GEN_NON_BEHAVIOR_FIELD", "%s.%s" % [path, String(bad_key)], "generators store behaviour only; `%s` belongs in entities" % String(bad_key))
		var charges = g.get("charges", null)
		if not Ctx.is_int_val(charges) or Ctx.as_int(charges) < 0:
			ctx.err("GEN_CHARGES", path + ".charges", "charges must be an integer >= 0")
		var cooldown = g.get("cooldown", 0.0)
		if not Ctx.is_num(cooldown) or float(cooldown) < 0.0:
			ctx.err("GEN_COOLDOWN", path + ".cooldown", "cooldown must be a number >= 0")
		var outputs = g.get("outputs", [])
		if typeof(outputs) != TYPE_ARRAY or outputs.is_empty():
			ctx.err("GEN_OUTPUTS_EMPTY", path + ".outputs", "at least one output is required")
			continue
		for ln in ["outputs", "rareOutputs"]:
			var list = g.get(ln, [])
			if typeof(list) != TYPE_ARRAY:
				continue
			for i in list.size():
				var item = list[i]
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var ipath := "%s.%s[%d]" % [path, ln, i]
				var w = item.get("weight", null)
				if not Ctx.is_num(w) or float(w) <= 0.0:
					ctx.err("GEN_WEIGHT", ipath + ".weight", "weight must be a number > 0")
				if ln == "rareOutputs":
					var lvl = item.get("level", null)
					if not Ctx.is_int_val(lvl):
						ctx.err("GEN_RARE_LEVEL", ipath + ".level", "rareOutputs.level must be an integer")
					else:
						var l := Ctx.as_int(lvl)
						if l < 1 or l > M0_MAX_LEVEL:
							ctx.err("GEN_RARE_LEVEL", ipath + ".level", "rareOutputs.level must be 1..%d in M0 (got %d)" % [M0_MAX_LEVEL, l])


static func _chain_table(ctx) -> Dictionary:
	var out := {}
	var entities = ctx.project.get("entities", {})
	if typeof(entities) != TYPE_DICTIONARY:
		return out
	for eid in entities.keys():
		var e = entities[eid]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if String(e.get("kind", "")) != "chip":
			continue
		var key := "%s|%s" % [String(e.get("family", "")), String(e.get("chain", ""))]
		if not out.has(key):
			out[key] = {"max": 0, "levels": {}, "via": ""}
		out[key]["max"] = maxi(int(out[key]["max"]), Ctx.as_int(e.get("maxLevel", 0), 0))
	return out


static func _reachable_levels(ctx) -> Dictionary:
	var table := _chain_table(ctx)
	var entities = ctx.project.get("entities", {})
	var generators = ctx.project.get("generators", {})
	if typeof(generators) == TYPE_DICTIONARY:
		for gid in generators.keys():
			var g = generators[gid]
			if typeof(g) != TYPE_DICTIONARY:
				continue
			for ln in ["outputs", "rareOutputs"]:
				var list = g.get(ln, [])
				if typeof(list) != TYPE_ARRAY:
					continue
				for item in list:
					if typeof(item) != TYPE_DICTIONARY:
						continue
					var eid := String(item.get("entity", ""))
					var ent = entities.get(eid, null)
					if typeof(ent) != TYPE_DICTIONARY:
						continue
					var key := "%s|%s" % [String(ent.get("family", "")), String(ent.get("chain", ""))]
					if not table.has(key):
						continue
					var start := Ctx.as_int(item.get("level", 1), 1)
					var top: int = mini(M0_MAX_LEVEL, int(table[key]["max"]))
					for lvl in range(maxi(start, 1), top + 1):
						table[key]["levels"][lvl] = true
					if String(table[key]["via"]).is_empty():
						table[key]["via"] = "generator " + String(gid)
	# items already on the board also satisfy a mission (no merge needed)
	var levels = ctx.project.get("levels", [])
	if typeof(levels) == TYPE_ARRAY:
		for lv in levels:
			if typeof(lv) != TYPE_DICTIONARY:
				continue
			var board = lv.get("board", {})
			if typeof(board) != TYPE_DICTIONARY:
				continue
			var slots = board.get("slots", [])
			if typeof(slots) != TYPE_ARRAY:
				continue
			for s in slots:
				if typeof(s) != TYPE_DICTIONARY:
					continue
				var eid := String(s.get("entity", ""))
				var ent = entities.get(eid, null)
				if typeof(ent) != TYPE_DICTIONARY:
					continue
				var key2 := "%s|%s" % [String(ent.get("family", "")), String(ent.get("chain", ""))]
				if not table.has(key2):
					continue
				var lvl2 := Ctx.as_int(s.get("level", 0), 0)
				if lvl2 >= 1:
					table[key2]["levels"][lvl2] = true
				if String(table[key2]["via"]).is_empty():
					table[key2]["via"] = "board"
	return table


static func _check_orders(ctx) -> void:
	var levels = ctx.project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		return
	var entities = ctx.project.get("entities", {})
	var reach := _reachable_levels(ctx)
	var order_total := 0
	for li in levels.size():
		var lv = levels[li]
		if typeof(lv) != TYPE_DICTIONARY:
			continue
		var orders = lv.get("orders", [])
		if typeof(orders) != TYPE_ARRAY:
			continue
		var seen_ids := {}
		for oi in orders.size():
			var o = orders[oi]
			if typeof(o) != TYPE_DICTIONARY:
				ctx.err("SCHEMA_TYPE", "levels[%d].orders[%d]" % [li, oi], "order must be an object")
				continue
			order_total += 1
			var base := "levels[%d].orders[%d]" % [li, oi]
			var oid := String(o.get("id", ""))
			if oid.is_empty():
				ctx.err("ORDER_ID_MISSING", base + ".id", "order id is required")
			elif seen_ids.has(oid):
				ctx.err("ORDER_DUP_ID", base + ".id", "duplicate order id \"%s\" inside level %d" % [oid, li])
			else:
				seen_ids[oid] = base
			for coin_key in ["star", "coin"]:
				var v = o.get(coin_key, 0)
				if not Ctx.is_num(v) or float(v) < 0.0:
					ctx.err("ORDER_REWARD", base + "." + coin_key, "%s must be a number >= 0" % coin_key)
			var mission = o.get("mission", [])
			if typeof(mission) != TYPE_ARRAY:
				continue
			if mission.size() < 1 or mission.size() > 2:
				ctx.err("ORDER_MISSION_COUNT", base + ".mission", "M0 orders need 1-2 mission items (got %d)" % mission.size())
			for mi in mission.size():
				var m = mission[mi]
				if typeof(m) != TYPE_DICTIONARY:
					continue
				var mpath := "%s.mission[%d]" % [base, mi]
				var eid := String(m.get("entity", ""))
				var ent = entities.get(eid, null)
				if typeof(ent) != TYPE_DICTIONARY:
					continue  # refs module already reported it
				var lvl_req = m.get("level", null)
				if not Ctx.is_int_val(lvl_req):
					ctx.err("ORDER_ITEM_LEVEL", mpath + ".level", "mission level must be an integer")
					continue
				var req := Ctx.as_int(lvl_req)
				if req < 1 or req > M0_MAX_LEVEL:
					ctx.err("ORDER_ITEM_LEVEL", mpath + ".level", "mission level must be 1..%d in M0 (got %d)" % [M0_MAX_LEVEL, req])
					continue
				var key := "%s|%s" % [String(ent.get("family", "")), String(ent.get("chain", ""))]
				if not reach.has(key):
					ctx.err("ORDER_UNREACHABLE", mpath, "order \"%s\" needs %s lv%d, but no generator produces that chain" % [oid, eid, req], {"order": oid, "entity": eid, "level": req})
					continue
				var chain: Dictionary = reach[key]
				var top: int = mini(M0_MAX_LEVEL, int(chain["max"]))
				if req > top:
					ctx.err("ORDER_UNREACHABLE", mpath, "order \"%s\" needs %s lv%d but the chain caps at lv%d" % [oid, eid, req, top], {"order": oid, "entity": eid, "level": req})
					continue
				if not Dictionary(chain["levels"]).has(req):
					ctx.err("ORDER_UNREACHABLE", mpath, "order \"%s\" needs %s lv%d, unreachable from %s" % [oid, eid, req, String(chain.get("via", "no source"))], {"order": oid, "entity": eid, "level": req})
	ctx.stats["orders"] = order_total
