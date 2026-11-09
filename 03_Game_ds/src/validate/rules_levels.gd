extends RefCounted
## Level / entity / generator / order rules, including the M0 level-10 cap, the
## "levels array order is the level order, `next` is deleted" rule and order
## reachability.
##
## F1 (P0): reachability is decided per level. A mission item counts only when
## THIS level's board can supply it:
##   * chips already placed in levels[li].board.slots (slot.level, clamped to the
##     entity cap),
##   * generators actually placed on that board — once per entity id, because
##     sim.generator_state is keyed by entity id, so a second placement of the same
##     generator shares one charge pool and adds no extra charges,
##   * that generator's charges for every distinct (chain, level) it outputs,
##   * the merge closure inside one chain (2 x lv N -> 1 x lv N+1).
## The project-level `generators` table is behaviour config: on its own it is not
## a source on any level, and levels never borrow items from each other.
##
## N1: JSON values are type-checked before use. `String(<number>)` is not a valid
## GDScript constructor, so a mistyped field used to abort the whole rule function
## instead of producing a precise error.

const Ctx = preload("res://src/validate/validate_ctx.gd")

const M0_MAX_LEVEL := 10
const M0_MAX_LEVELS := 10
const KNOWN_KINDS := ["chip", "generator", "special", "character"]


static func check(ctx) -> void:
	_check_entities(ctx)
	_check_levels(ctx)
	_check_generators(ctx)
	_check_orders(ctx)
	# abort gate (N1): the validator only reaches this line when no runtime error
	# interrupted one of the checks above
	ctx.rule_done()


# ------------------------------------------------------------------ type helpers

## Reads a string field without ever calling `String()` on a non-string value.
static func _str_field(source, key: String) -> String:
	if typeof(source) != TYPE_DICTIONARY:
		return ""
	var v = (source as Dictionary).get(key, null)
	if typeof(v) != TYPE_STRING:
		return ""
	return String(v)


static func _type_label(v) -> String:
	return type_string(typeof(v))


static func _kind_of(entity) -> String:
	return _str_field(entity, "kind")


## One bucket per (family, chain). Chips without a usable family/chain fall back to
## their own entity id so unrelated malformed chips are never merged together.
static func _chain_key(eid: String, ent: Dictionary) -> String:
	var family := _str_field(ent, "family")
	var chain := _str_field(ent, "chain")
	if family.is_empty() or chain.is_empty():
		return "entity|" + eid
	return "%s|%s" % [family, chain]


static func _add_bucket(avail: Dictionary, key: String, level: int, count: int) -> void:
	if count <= 0:
		return
	var lvl := clampi(level, 1, M0_MAX_LEVEL)
	if not avail.has(key):
		avail[key] = {}
	var bucket: Dictionary = avail[key]
	bucket[lvl] = int(bucket.get(lvl, 0)) + count


# ------------------------------------------------------------------ entities

static func _check_entities(ctx) -> void:
	var entities = ctx.project.get("entities", {})
	if typeof(entities) != TYPE_DICTIONARY:
		return
	for eid in (entities as Dictionary).keys():
		var key := String(eid)
		var path := "entities.%s" % key
		var e = (entities as Dictionary)[eid]
		if typeof(e) != TYPE_DICTIONARY:
			ctx.err("SCHEMA_TYPE", path, "entity entry must be an object")
			continue
		var raw_kind = (e as Dictionary).get("kind", null)
		if raw_kind == null:
			ctx.err("ENTITY_KIND", path + ".kind", "entity kind is required")
			continue
		if typeof(raw_kind) != TYPE_STRING:
			ctx.err("ENTITY_KIND_TYPE", path + ".kind", "entity kind must be a string (got %s)" % _type_label(raw_kind))
			continue
		var kind := String(raw_kind)
		if kind.is_empty():
			ctx.err("ENTITY_KIND", path + ".kind", "entity kind is required")
			continue
		if not KNOWN_KINDS.has(kind):
			ctx.err("ENTITY_KIND", path + ".kind", "unknown entity kind \"%s\" (expected one of %s)" % [kind, str(KNOWN_KINDS)])
			continue
		if kind == "chip":
			if not Ctx.is_str_val((e as Dictionary).get("family", "")):
				ctx.err("ENTITY_CHIP_FAMILY", path + ".family", "chip entities need a family")
			if not Ctx.is_str_val((e as Dictionary).get("chain", "")):
				ctx.err("ENTITY_CHIP_CHAIN", path + ".chain", "chip entities need a chain")
			var max_level = (e as Dictionary).get("maxLevel", null)
			if not Ctx.is_int_val(max_level):
				ctx.err("ENTITY_MAX_LEVEL", path + ".maxLevel", "chip maxLevel must be an integer")
			else:
				var ml := Ctx.as_int(max_level)
				if ml < 1 or ml > M0_MAX_LEVEL:
					ctx.err("ENTITY_MAX_LEVEL", path + ".maxLevel", "chip maxLevel must be 1..%d in M0 (got %d)" % [M0_MAX_LEVEL, ml])
		elif kind == "generator":
			var gmax = (e as Dictionary).get("maxLevel", null)
			if not Ctx.is_int_val(gmax) or Ctx.as_int(gmax) < 1:
				ctx.err("ENTITY_MAX_LEVEL", path + ".maxLevel", "generator maxLevel must be an integer >= 1")
		# special / character need no numeric fields in M0


# ------------------------------------------------------------------ levels

static func _check_levels(ctx) -> void:
	var levels = ctx.project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		ctx.err("SCHEMA_TYPE", "levels", "levels must be an array")
		return
	ctx.stats["levels"] = (levels as Array).size()
	if (levels as Array).is_empty():
		ctx.err("LEVELS_EMPTY", "levels", "at least one level is required")
		return
	if (levels as Array).size() > M0_MAX_LEVELS:
		ctx.err("LEVELS_OVER_CAP", "levels", "M0 supports at most %d levels (got %d)" % [M0_MAX_LEVELS, (levels as Array).size()])
	var seen := {}
	for li in (levels as Array).size():
		var lv = (levels as Array)[li]
		var base := "levels[%d]" % li
		if typeof(lv) != TYPE_DICTIONARY:
			ctx.err("SCHEMA_TYPE", base, "level must be an object")
			continue
		if (lv as Dictionary).has("next"):
			ctx.err("LEVEL_NEXT_REMOVED", base + ".next", "`next` was removed in schema v2; level order is the levels array order")
		var raw_id = (lv as Dictionary).get("id", null)
		if raw_id == null:
			ctx.err("LEVEL_ID_MISSING", base + ".id", "level id is required")
		elif typeof(raw_id) != TYPE_STRING:
			ctx.err("LEVEL_ID_TYPE", base + ".id", "level id must be a string (got %s)" % _type_label(raw_id))
		else:
			var id := String(raw_id)
			if id.is_empty():
				ctx.err("LEVEL_ID_MISSING", base + ".id", "level id is required")
			elif seen.has(id):
				ctx.err("LEVEL_DUP_ID", base + ".id", "duplicate level id \"%s\" (first at %s)" % [id, seen[id]])
			else:
				seen[id] = base
		if typeof((lv as Dictionary).get("board", null)) != TYPE_DICTIONARY:
			ctx.err("SCHEMA_TYPE", base + ".board", "board must be an object")
		if typeof((lv as Dictionary).get("orders", null)) != TYPE_ARRAY:
			ctx.err("SCHEMA_TYPE", base + ".orders", "orders must be an array")
		if typeof((lv as Dictionary).get("obstacles", null)) != TYPE_ARRAY:
			ctx.err("SCHEMA_TYPE", base + ".obstacles", "obstacles must be an array")


# ------------------------------------------------------------------ generators

static func _check_generators(ctx) -> void:
	var generators = ctx.project.get("generators", {})
	if typeof(generators) != TYPE_DICTIONARY:
		return
	for gid in (generators as Dictionary).keys():
		var key := String(gid)
		var path := "generators.%s" % key
		var g = (generators as Dictionary)[gid]
		if typeof(g) != TYPE_DICTIONARY:
			continue
		for bad_key in ["entity", "visual", "icon", "chips"]:
			if (g as Dictionary).has(bad_key):
				ctx.err("GEN_NON_BEHAVIOR_FIELD", "%s.%s" % [path, String(bad_key)], "generators store behaviour only; `%s` belongs in entities" % String(bad_key))
		var charges = (g as Dictionary).get("charges", null)
		if not Ctx.is_int_val(charges) or Ctx.as_int(charges) < 0:
			ctx.err("GEN_CHARGES", path + ".charges", "charges must be an integer >= 0")
		var cooldown = (g as Dictionary).get("cooldown", 0.0)
		if not Ctx.is_num(cooldown) or float(cooldown) < 0.0:
			ctx.err("GEN_COOLDOWN", path + ".cooldown", "cooldown must be a number >= 0")
		var outputs = (g as Dictionary).get("outputs", [])
		if typeof(outputs) != TYPE_ARRAY or (outputs as Array).is_empty():
			ctx.err("GEN_OUTPUTS_EMPTY", path + ".outputs", "at least one output is required")
			continue
		for ln in ["outputs", "rareOutputs"]:
			var list = (g as Dictionary).get(ln, [])
			if typeof(list) != TYPE_ARRAY:
				continue
			for i in (list as Array).size():
				var item = (list as Array)[i]
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var ipath := "%s.%s[%d]" % [path, ln, i]
				if (item as Dictionary).has("entity"):
					var raw_out_e = (item as Dictionary)["entity"]
					if typeof(raw_out_e) != TYPE_STRING:
						ctx.err("GEN_OUTPUT_ENTITY_TYPE", ipath + ".entity", "output entity must be a string (got %s)" % _type_label(raw_out_e))
				var w = (item as Dictionary).get("weight", null)
				if not Ctx.is_num(w) or float(w) <= 0.0:
					ctx.err("GEN_WEIGHT", ipath + ".weight", "weight must be a number > 0")
				if ln == "rareOutputs" and (item as Dictionary).has("directOrder"):
					if typeof((item as Dictionary)["directOrder"]) != TYPE_BOOL:
						ctx.err("GEN_DIRECT_ORDER_TYPE", ipath + ".directOrder", "directOrder must be a boolean (M0 v0.20 §2.1.10)")
				if ln == "rareOutputs":
					var lvl = (item as Dictionary).get("level", null)
					if not Ctx.is_int_val(lvl):
						ctx.err("GEN_RARE_LEVEL", ipath + ".level", "rareOutputs.level must be an integer")
					else:
						var l := Ctx.as_int(lvl)
						if l < 1 or l > M0_MAX_LEVEL:
							ctx.err("GEN_RARE_LEVEL", ipath + ".level", "rareOutputs.level must be 1..%d in M0 (got %d)" % [M0_MAX_LEVEL, l])


# ------------------------------------------------------------------ availability

## (entity, level) pairs this level's own orders ask for — what a rare output with
## the default `directOrder: true` is allowed to serve.
static func _order_mission_keys(lv: Dictionary) -> Dictionary:
	var out := {}
	var orders = lv.get("orders", [])
	if typeof(orders) != TYPE_ARRAY:
		return out
	for o in orders:
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var mission = (o as Dictionary).get("mission", [])
		if typeof(mission) != TYPE_ARRAY:
			continue
		for m in mission:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var eid := _str_field(m, "entity")
			if eid.is_empty():
				continue
			var raw_level = (m as Dictionary).get("level", null)
			if not Ctx.is_int_val(raw_level):
				continue
			out["%s@%d" % [eid, Ctx.as_int(raw_level)]] = true
	return out


## Whether a rareOutput contributes on this level. `directOrder` defaults to true,
## which means "only when one of this level's orders asks for exactly that item";
## an explicit false means the rare item is granted unconditionally. A mistyped
## directOrder is reported as GEN_DIRECT_ORDER_TYPE and grants nothing.
static func _rare_is_granted(item: Dictionary, eid: String, lvl: int, wanted: Dictionary) -> bool:
	if item.has("directOrder"):
		var raw = item["directOrder"]
		if typeof(raw) != TYPE_BOOL:
			return false
		if not bool(raw):
			return true
	return wanted.has("%s@%d" % [eid, lvl])


## Distinct (chain -> levels) this generator can output with one charge each.
static func _generator_output_slots(cfg: Dictionary, entities: Dictionary, wanted: Dictionary) -> Dictionary:
	var out := {}
	for list_name in ["outputs", "rareOutputs"]:
		var list = cfg.get(list_name, [])
		if typeof(list) != TYPE_ARRAY:
			continue
		var is_rare := String(list_name) == "rareOutputs"
		for item in list:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var out_eid := _str_field(item, "entity")
			if out_eid.is_empty():
				continue
			var ent = entities.get(out_eid, null)
			if typeof(ent) != TYPE_DICTIONARY:
				continue  # refs reports an undeclared output
			if _kind_of(ent) != "chip":
				continue  # refs reports the wrong kind
			var lvl := 1
			var raw_level = (item as Dictionary).get("level", null)
			if raw_level != null:
				if not Ctx.is_int_val(raw_level):
					continue
				lvl = Ctx.as_int(raw_level)
				if lvl < 1 or lvl > M0_MAX_LEVEL:
					continue
			if is_rare and not _rare_is_granted(item, out_eid, lvl, wanted):
				continue
			var key := _chain_key(out_eid, ent)
			if not out.has(key):
				out[key] = {}
			(out[key] as Dictionary)[lvl] = true
	return out


## level -> count of chips one level can actually supply, per chain key.
## This is a per-level upper bound. One charge produces exactly one item, so every
## distinct (chain, level) an output list can produce is credited up to `charges`
## (the reviewer's requested reading: "每种产出各计 charges"); duplicate entries
## for the same (chain, level) are counted once, never stacked.
static func _level_availability(ctx, li: int) -> Dictionary:
	var avail := {}
	var entities = ctx.project.get("entities", {})
	if typeof(entities) != TYPE_DICTIONARY:
		return avail
	var levels = ctx.project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY or li < 0 or li >= (levels as Array).size():
		return avail
	var lv = (levels as Array)[li]
	if typeof(lv) != TYPE_DICTIONARY:
		return avail
	var board = (lv as Dictionary).get("board", {})
	var slots: Array = []
	if typeof(board) == TYPE_DICTIONARY:
		var raw_slots = (board as Dictionary).get("slots", [])
		if typeof(raw_slots) == TYPE_ARRAY:
			slots = raw_slots

	# ---- 1) chips already on this board; generators placed on this board ----
	var placed_generators: Array = []
	var seen_generators := {}
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var eid := _str_field(s, "entity")
		if eid.is_empty():
			continue
		var ent = (entities as Dictionary).get(eid, null)
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		var kind := _kind_of(ent)
		if kind == "chip":
			var ent_max := Ctx.as_int((ent as Dictionary).get("maxLevel", 1), 1)
			var top: int = mini(M0_MAX_LEVEL, maxi(1, ent_max))
			var raw_level = (s as Dictionary).get("level", 1)
			var lvl := clampi(Ctx.as_int(raw_level, 1), 1, top)
			_add_bucket(avail, _chain_key(eid, ent), lvl, 1)
		elif kind == "generator" and not seen_generators.has(eid):
			# sim.generator_state is keyed by entity id: a second placement of the
			# same generator shares one charge pool, so it is counted once.
			seen_generators[eid] = true
			placed_generators.append(eid)

	# ---- 2) charges of the generators actually placed on this board ----
	var generators = ctx.project.get("generators", {})
	if typeof(generators) != TYPE_DICTIONARY:
		return avail
	var wanted := _order_mission_keys(lv)
	for gid in placed_generators:
		var cfg = (generators as Dictionary).get(gid, null)
		if typeof(cfg) != TYPE_DICTIONARY:
			continue
		var charges := maxi(0, Ctx.as_int((cfg as Dictionary).get("charges", 0), 0))
		if charges <= 0:
			continue
		var slots_out := _generator_output_slots(cfg, entities, wanted)
		for key in slots_out.keys():
			var levels_out: Dictionary = slots_out[key]
			for lvl in levels_out.keys():
				# duplicate output entries for the same (chain, level) take the max
				# (= charges once), they never stack.
				_add_bucket(avail, String(key), int(lvl), charges)

	# ---- 3) merge closure inside one chain: 2 x lv N -> 1 x lv N+1 ----
	for key in avail.keys():
		var bucket: Dictionary = avail[key]
		for lvl in range(1, M0_MAX_LEVEL):
			var have := int(bucket.get(lvl, 0))
			if have <= 0:
				continue
			var up := floori(float(have) / 2.0)
			if up > 0:
				bucket[lvl + 1] = int(bucket.get(lvl + 1, 0)) + up
	return avail


# ------------------------------------------------------------------ orders

static func _check_orders(ctx) -> void:
	var levels = ctx.project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		return
	var entities = ctx.project.get("entities", {})
	var ents: Dictionary = entities if typeof(entities) == TYPE_DICTIONARY else {}
	var order_total := 0
	for li in (levels as Array).size():
		var lv = (levels as Array)[li]
		if typeof(lv) != TYPE_DICTIONARY:
			continue
		var orders = (lv as Dictionary).get("orders", [])
		if typeof(orders) != TYPE_ARRAY:
			continue
		# reachability is a property of this level's board, never of another level
		var avail := _level_availability(ctx, li)
		var seen_ids := {}
		for oi in (orders as Array).size():
			var o = (orders as Array)[oi]
			if typeof(o) != TYPE_DICTIONARY:
				ctx.err("SCHEMA_TYPE", "levels[%d].orders[%d]" % [li, oi], "order must be an object")
				continue
			order_total += 1
			var base := "levels[%d].orders[%d]" % [li, oi]
			var oid := ""
			var raw_id = (o as Dictionary).get("id", null)
			if raw_id == null:
				ctx.err("ORDER_ID_MISSING", base + ".id", "order id is required")
			elif typeof(raw_id) != TYPE_STRING:
				ctx.err("ORDER_ID_TYPE", base + ".id", "order id must be a string (got %s)" % _type_label(raw_id))
				continue
			else:
				oid = String(raw_id)
				if oid.is_empty():
					ctx.err("ORDER_ID_MISSING", base + ".id", "order id is required")
				elif seen_ids.has(oid):
					ctx.err("ORDER_DUP_ID", base + ".id", "duplicate order id \"%s\" inside level %d" % [oid, li])
				else:
					seen_ids[oid] = base
			var raw_char = (o as Dictionary).get("character", null)
			if raw_char != null and typeof(raw_char) != TYPE_STRING:
				ctx.err("ORDER_CHARACTER_TYPE", base + ".character", "order character must be a string (got %s)" % _type_label(raw_char))
			for coin_key in ["star", "coin", "gem", "energy"]:
				var v = (o as Dictionary).get(coin_key, 0)
				if not Ctx.is_num(v) or float(v) < 0.0:
					ctx.err("ORDER_REWARD", base + "." + String(coin_key), "%s must be a number >= 0" % String(coin_key))
			var mission = (o as Dictionary).get("mission", [])
			if typeof(mission) != TYPE_ARRAY:
				continue
			if (mission as Array).size() < 1 or (mission as Array).size() > 2:
				ctx.err("ORDER_MISSION_COUNT", base + ".mission", "M0 orders need 1-2 mission items (got %d)" % (mission as Array).size())
			for mi in (mission as Array).size():
				var m = (mission as Array)[mi]
				if typeof(m) != TYPE_DICTIONARY:
					continue
				var mpath := "%s.mission[%d]" % [base, mi]
				var raw_eid = (m as Dictionary).get("entity", null)
				if raw_eid == null:
					continue  # refs module reports the missing reference
				if typeof(raw_eid) != TYPE_STRING:
					ctx.err("MISSION_ENTITY_TYPE", mpath + ".entity", "mission entity must be a string (got %s)" % _type_label(raw_eid))
					continue
				var eid := String(raw_eid)
				if eid.is_empty():
					continue  # refs module reports the empty reference
				var ent = ents.get(eid, null)
				if typeof(ent) != TYPE_DICTIONARY:
					continue  # refs module already reported it
				if _kind_of(ent) != "chip":
					continue  # refs reports the wrong kind; orders only ask for chips
				var lvl_req = (m as Dictionary).get("level", null)
				if not Ctx.is_int_val(lvl_req):
					ctx.err("ORDER_ITEM_LEVEL", mpath + ".level", "mission level must be an integer")
					continue
				var req := Ctx.as_int(lvl_req)
				if req < 1 or req > M0_MAX_LEVEL:
					ctx.err("ORDER_ITEM_LEVEL", mpath + ".level", "mission level must be 1..%d in M0 (got %d)" % [M0_MAX_LEVEL, req])
					continue
				var key := _chain_key(eid, ent)
				var bucket = avail.get(key, null)
				var count := 0
				if typeof(bucket) == TYPE_DICTIONARY:
					count = int((bucket as Dictionary).get(req, 0))
				if count < 1:
					ctx.err("ORDER_UNREACHABLE", mpath, "order \"%s\" needs %s lv%d, but this level's board cannot supply it (no chip in place and no placed generator with charges reaches that level)" % [oid, eid, req], {"order": oid, "entity": eid, "level": req})
	ctx.stats["orders"] = order_total
