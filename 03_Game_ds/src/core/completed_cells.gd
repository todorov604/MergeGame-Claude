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
				if int(slot[2]) >= 1:
					continue
				wanted["%s@%d" % [String(slot[0]), int(slot[1])]] = true

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
		if wanted.has("%s@%d" % [String(row[2]), int(row[3])]):
			out.append([int(row[0]), int(row[1])])
	return out
