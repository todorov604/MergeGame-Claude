extends RefCounted
## Reference integrity: every referenced id must be defined, and with the right kind.
## This is the rule that catches the historical `CleanSet_Cb` trap (an id that only
## ever appeared inside a generator output).


static func _entities(ctx) -> Dictionary:
	var e = ctx.project.get("entities", {})
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	return e


static func _kind(ctx, id: String) -> String:
	var e = _entities(ctx).get(id, null)
	if typeof(e) != TYPE_DICTIONARY:
		return ""
	return String(e.get("kind", ""))


static func check(ctx) -> void:
	_check_generators(ctx)
	_check_characters(ctx)
	_check_level_slots(ctx)
	_check_orders(ctx)


static func _check_generators(ctx) -> void:
	var gens = ctx.project.get("generators", {})
	if typeof(gens) != TYPE_DICTIONARY:
		return
	for gid in gens.keys():
		var key := String(gid)
		var path := "generators.%s" % key
		var g = gens[gid]
		if typeof(g) != TYPE_DICTIONARY:
			ctx.err("SCHEMA_TYPE", path, "generator entry must be an object")
			continue
		var kind := _kind(ctx, key)
		if kind.is_empty():
			ctx.err("REF_UNDEFINED", path, "generator \"%s\" is not declared in entities" % key, {"id": key})
		elif kind != "generator":
			ctx.err("REF_KIND_MISMATCH", path, "generator \"%s\" must be entities.kind=generator (got \"%s\")" % [key, kind])
		for list_name in ["outputs", "rareOutputs"]:
			var list = g.get(list_name, [])
			if typeof(list) != TYPE_ARRAY:
				ctx.err("SCHEMA_TYPE", path + "." + list_name, "must be an array")
				continue
			for i in list.size():
				var item = list[i]
				var ipath := "%s.%s[%d]" % [path, list_name, i]
				if typeof(item) != TYPE_DICTIONARY:
					ctx.err("SCHEMA_TYPE", ipath, "output entry must be an object")
					continue
				var eid := String(item.get("entity", ""))
				if eid.is_empty():
					ctx.err("REF_UNDEFINED", ipath + ".entity", "output entity is required")
					continue
				var k := _kind(ctx, eid)
				if k.is_empty():
					ctx.err("REF_UNDEFINED", ipath + ".entity", "output entity \"%s\" is not declared in entities" % eid, {"id": eid})
				elif k != "chip":
					ctx.err("REF_KIND_MISMATCH", ipath + ".entity", "output entity \"%s\" must be kind=chip (got \"%s\")" % [eid, k])


static func _check_characters(ctx) -> void:
	var chars = ctx.project.get("characters", {})
	if typeof(chars) != TYPE_DICTIONARY:
		return
	for cid in chars.keys():
		var key := String(cid)
		var path := "characters.%s" % key
		var kind := _kind(ctx, key)
		if kind.is_empty():
			ctx.err("REF_UNDEFINED", path, "character \"%s\" is not declared in entities" % key, {"id": key})
		elif kind != "character":
			ctx.err("REF_KIND_MISMATCH", path, "character \"%s\" must be entities.kind=character (got \"%s\")" % [key, kind])


static func _check_level_slots(ctx) -> void:
	var levels = ctx.project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		return
	for li in levels.size():
		var lv = levels[li]
		if typeof(lv) != TYPE_DICTIONARY:
			continue
		var board = lv.get("board", {})
		if typeof(board) != TYPE_DICTIONARY:
			continue
		var slots = board.get("slots", [])
		if typeof(slots) != TYPE_ARRAY:
			continue
		for si in slots.size():
			var s = slots[si]
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var ipath := "levels[%d].board.slots[%d].entity" % [li, si]
			var eid := String(s.get("entity", ""))
			if eid.is_empty():
				ctx.err("REF_UNDEFINED", ipath, "slot entity is required")
				continue
			var kind := _kind(ctx, eid)
			if kind.is_empty():
				ctx.err("REF_UNDEFINED", ipath, "slot entity \"%s\" is not declared in entities" % eid, {"id": eid})
			elif kind == "character":
				ctx.err("REF_KIND_MISMATCH", ipath, "slot entity \"%s\" is a character; characters live in orders, not on the board" % eid)


static func _check_orders(ctx) -> void:
	var levels = ctx.project.get("levels", [])
	if typeof(levels) != TYPE_ARRAY:
		return
	var chars = ctx.project.get("characters", {})
	var chars_dict: Dictionary = chars if typeof(chars) == TYPE_DICTIONARY else {}
	for li in levels.size():
		var lv = levels[li]
		if typeof(lv) != TYPE_DICTIONARY:
			continue
		var orders = lv.get("orders", [])
		if typeof(orders) != TYPE_ARRAY:
			continue
		for oi in orders.size():
			var o = orders[oi]
			if typeof(o) != TYPE_DICTIONARY:
				continue
			var base := "levels[%d].orders[%d]" % [li, oi]
			var cid := String(o.get("character", ""))
			if cid.is_empty():
				ctx.err("REF_UNDEFINED", base + ".character", "order character is required")
			else:
				var kind := _kind(ctx, cid)
				if kind.is_empty():
					ctx.err("REF_UNDEFINED", base + ".character", "order character \"%s\" is not declared in entities" % cid, {"id": cid})
				elif kind != "character":
					ctx.err("REF_KIND_MISMATCH", base + ".character", "order character \"%s\" must be kind=character (got \"%s\")" % [cid, kind])
				elif not chars_dict.has(cid):
					ctx.err("CHAR_TABLE_MISSING", base + ".character", "character \"%s\" has no entry in the characters table (idle/done config)" % cid, {"id": cid})
			var mission = o.get("mission", [])
			if typeof(mission) != TYPE_ARRAY:
				continue
			for mi in mission.size():
				var m = mission[mi]
				var mpath := "%s.mission[%d].entity" % [base, mi]
				if typeof(m) != TYPE_DICTIONARY:
					ctx.err("SCHEMA_TYPE", "%s.mission[%d]" % [base, mi], "mission item must be an object")
					continue
				var eid := String(m.get("entity", ""))
				if eid.is_empty():
					ctx.err("REF_UNDEFINED", mpath, "mission entity is required")
					continue
				var kind2 := _kind(ctx, eid)
				if kind2.is_empty():
					ctx.err("REF_UNDEFINED", mpath, "mission entity \"%s\" is not declared in entities" % eid, {"id": eid})
				elif kind2 != "chip":
					ctx.err("REF_KIND_MISMATCH", mpath, "mission entity \"%s\" must be kind=chip (got \"%s\")" % [eid, kind2])
