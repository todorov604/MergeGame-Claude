extends RefCounted
## "This chip currently satisfies an order" — the single rule behind the green cell
## fill and the finish badge. Shared by the live screen and the film, so a preview and
## a delivered frame cannot disagree about which chips read as done.
##
## A cell counts when an order that is not claimed yet has an unsatisfied mission
## entry (have < 1) for exactly that entity+level. Pure data in, pure data out: the
## film's determinism is untouched.

static func from_snapshot(snap: Dictionary) -> Array:
	var wanted := {}
	var orders = snap.get("orders", [])
	if typeof(orders) == TYPE_ARRAY:
		for raw in orders:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var order: Dictionary = raw
			if bool(order.get("done", false)):
				continue
			var mission = order.get("mission", [])
			if typeof(mission) != TYPE_ARRAY:
				continue
			for item in mission:
				if typeof(item) != TYPE_ARRAY or (item as Array).size() < 3:
					continue
				var slot: Array = item
				# 2026-11-10：一行可能要多枚（快照第 4 位是 need），收满才停。
				var need := int(slot[3]) if slot.size() >= 4 else 1
				if int(slot[2]) >= maxi(need, 1):
					continue
				wanted["%s@%d" % [String(slot[0]), int(slot[1])]] = true

	# 2026-11-06: a chip that sits under an obstacle is not deliverable — the web / ice /
	# box hides it until a neighbouring merge breaks the obstacle, so it must not turn a
	# mission row (or its cell) green.
	var blocked := {}
	var raw_obs = (snap.get("board", {}) as Dictionary).get("obstacles", []) if typeof(snap.get("board", {})) == TYPE_DICTIONARY else []
	if typeof(raw_obs) == TYPE_ARRAY:
		for row in raw_obs:
			if typeof(row) == TYPE_ARRAY and (row as Array).size() >= 2:
				blocked["%d@%d" % [int((row as Array)[0]), int((row as Array)[1])]] = true

	var out: Array = []
	var board = snap.get("board", {})
	if typeof(board) != TYPE_DICTIONARY:
		return out
	var cells = (board as Dictionary).get("cells", [])
	if typeof(cells) != TYPE_ARRAY:
		return out
	for raw in cells:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 4:
			continue
		var row: Array = raw
		if blocked.has("%d@%d" % [int(row[0]), int(row[1])]):
			continue
		if wanted.has("%s@%d" % [String(row[2]), int(row[3])]):
			out.append([int(row[0]), int(row[1])])
	return out
