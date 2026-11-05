extends RefCounted
## What is frozen inside an ice cell. The sim keeps obstacles and items disjoint, so
## the frozen chip is view-only: one deterministic pick from the project's chip
## entities, keyed by the cell, so a preview screenshot and a film frame agree and
## the content never flickers between frames.
##
## The ice also carries a countdown between 10:00 and 19:59, deterministic per cell
## and ticking once per second of level time (live clock / film frame time), never a
## wall-clock read.

const MIN_SECONDS := 10 * 60
const MAX_SECONDS := 20 * 60 - 1


static func chip(project: Dictionary, cell: Vector2i) -> Dictionary:
	var chips: Array = []
	var entities = project.get("entities", {})
	if typeof(entities) == TYPE_DICTIONARY:
		for key in (entities as Dictionary).keys():
			var entry = (entities as Dictionary)[key]
			if typeof(entry) == TYPE_DICTIONARY and String((entry as Dictionary).get("kind", "")) == "chip":
				chips.append(String(key))
	chips.sort()
	if chips.is_empty():
		return {}
	var index := int(abs(cell.x * 7 + cell.y * 5)) % chips.size()
	return {
		"entity": String(chips[index]),
		"level": 1 + int(abs(cell.x + cell.y)) % 2,
	}


## 10:00 <= start <= 19:59, fixed for a given cell.
static func start_seconds(cell: Vector2i) -> int:
	var span := MAX_SECONDS - MIN_SECONDS + 1
	var hash_value := int(abs(cell.x * 733 + cell.y * 977 + cell.x * cell.y * 31))
	return MIN_SECONDS + hash_value % span


## Whole seconds left: one tick per second of `elapsed` (level time, not wall clock).
static func remaining_seconds(cell: Vector2i, elapsed: float) -> int:
	var left := start_seconds(cell) - int(floor(maxf(elapsed, 0.0)))
	return clampi(left, 0, MAX_SECONDS)


static func format_clock(seconds: int) -> String:
	var safe := clampi(seconds, 0, 99 * 60 + 59)
	return "%02d:%02d" % [safe / 60, safe % 60]
