extends RefCounted
## Free-mode click rules, as pure functions.
##
## The live screen owns input, the selection highlight and rendering; this file owns
## the mapping "click at a page point -> sim event". Keeping it pure means the rules
## are testable headless (tests/t_free_mode.gd) and the film cannot drift from them:
## the film replays the recorded events through the very same sim.

const ACTION_NONE := "none"
const ACTION_BLOCKED := "blocked"
const ACTION_CLEAR := "clear"
const ACTION_SELECT := "select"
const ACTION_TAP := "tap"
const ACTION_MERGE := "merge"


## Page-space point -> board cell, or (-1,-1) outside the container. The geometry
## (origin, size, cols, rows) comes from BoardView at every call site, so a board
## layout change moves the hit test with it instead of leaving a stale copy.
static func cell_at(point: Vector2, origin: Vector2, board_size: Vector2, cols: int,
		rows: int) -> Vector2i:
	if cols <= 0 or rows <= 0 or board_size.x <= 0.0 or board_size.y <= 0.0:
		return Vector2i(-1, -1)
	var local := point - origin
	if local.x < 0.0 or local.y < 0.0:
		return Vector2i(-1, -1)
	if local.x >= board_size.x or local.y >= board_size.y:
		return Vector2i(-1, -1)
	var x := int(local.x / (board_size.x / float(cols)))
	var y := int(local.y / (board_size.y / float(rows)))
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


## Resolve one click on the board. Returns
##   {"kind": none|blocked|clear|select|tap|merge,
##    "selected": Vector2i, "payload": {}, "entity": String, "level": int}
## `kind` tells the screen what to do: apply the event (tap/merge), move the
## highlight (select), drop it (clear), or ignore the click (none/blocked).
static func board_click(cell: Vector2i, sim, model, selected: Vector2i) -> Dictionary:
	var out := {
		"kind": ACTION_NONE,
		"selected": selected,
		"payload": {},
		"entity": "",
		"level": 0,
	}
	if sim == null or sim.board == null or not sim.board.in_bounds(cell):
		return out
	if sim.board.is_blocked(cell):
		out["kind"] = ACTION_BLOCKED
		return out
	if not sim.board.has_item(cell):
		out["kind"] = ACTION_CLEAR
		out["selected"] = Vector2i(-1, -1)
		return out
	var item: Dictionary = sim.board.item(cell)
	var entity_id := String(item.get("entity", ""))
	var level := int(item.get("level", 1))
	var kind := String(model.entity(entity_id).get("kind", "")) if model != null else ""
	out["entity"] = entity_id
	out["level"] = level
	if kind == "generator":
		out["kind"] = ACTION_TAP
		out["selected"] = Vector2i(-1, -1)
		out["payload"] = {"target": {"slot": [cell.x, cell.y]}}
		return out
	if kind != "chip":
		# Specials have no click semantics in the M0/M1 rules: ignore the click
		# instead of inventing one.
		return out
	if selected.x < 0 or not sim.board.has_item(selected):
		out["kind"] = ACTION_SELECT
		out["selected"] = cell
		return out
	if selected == cell:
		out["kind"] = ACTION_CLEAR
		out["selected"] = Vector2i(-1, -1)
		return out
	var first: Dictionary = sim.board.item(selected)
	if String(first.get("entity", "")) == entity_id and int(first.get("level", 1)) == level:
		out["kind"] = ACTION_MERGE
		out["selected"] = Vector2i(-1, -1)
		out["payload"] = {"from": [selected.x, selected.y], "to": [cell.x, cell.y]}
		return out
	out["kind"] = ACTION_SELECT
	out["selected"] = cell
	return out
