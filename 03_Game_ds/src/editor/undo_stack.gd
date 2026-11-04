extends RefCounted
## Snapshot undo/redo stack for project.json edits.
##
## Every entry stores a full deep copy of the project dictionary, so undo never
## re-applies a "reverse operation" and cannot drift. Two rules keep the history
## honest:
##
##   1. `canon()` serializes a value with sorted dictionary keys, so two projects
##      that only differ by key insertion order compare equal and a no-op edit is
##      not recorded at all.
##   2. Pushing after an undo drops the redo tail, which is what every editor does
##      and what makes "undo 60 / redo 60" symmetric.
##
## Capacity is a ring: the oldest entry is dropped once the stack is full.

const DEFAULT_CAPACITY := 64

var capacity: int = DEFAULT_CAPACITY
var _entries: Array = []
var _cursor: int = 0


func _init(capacity_in: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(1, capacity_in)


# --------------------------------------------------------------- deterministic

## Key-sorted canonical form. Ints and integral floats collapse to the same text
## so a JSON round trip that turns 2 into 2.0 does not look like an edit.
static func canon(value) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			return _canon_float(float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(String(value))
		TYPE_ARRAY:
			var items: Array = []
			for v in (value as Array):
				items.append(canon(v))
			return "[" + ",".join(items) + "]"
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var keys: Array = d.keys()
			keys.sort_custom(func(a, b): return String(a) < String(b))
			var parts: Array = []
			for k in keys:
				parts.append(JSON.stringify(String(k)) + ":" + canon(d[k]))
			return "{" + ",".join(parts) + "}"
	return JSON.stringify(str(value))


static func _canon_float(f: float) -> String:
	if not is_finite(f):
		return "null"
	if f == 0.0:
		return "0"
	if f == floor(f) and absf(f) < 1e15:
		return str(int(round(f)))
	var s := "%.9f" % f
	if s.find(".") >= 0:
		while s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s


static func same(a, b) -> bool:
	return canon(a) == canon(b)


# ------------------------------------------------------------------ public API

func push(label: String, before: Dictionary, after: Dictionary) -> Dictionary:
	var before_key := canon(before)
	var after_key := canon(after)
	if before_key == after_key:
		return {"ok": false, "code": "UNDO_NO_CHANGE", "label": label}
	if _cursor < _entries.size():
		_entries = _entries.slice(0, _cursor)
	_entries.append({
		"label": label,
		"before": before.duplicate(true),
		"after": after.duplicate(true),
		"before_key": before_key,
		"after_key": after_key,
	})
	_cursor = _entries.size()
	var dropped := 0
	while _entries.size() > capacity:
		_entries.pop_front()
		_cursor -= 1
		dropped += 1
	if _cursor < 0:
		_cursor = 0
	return {
		"ok": true,
		"code": "",
		"label": label,
		"size": _entries.size(),
		"cursor": _cursor,
		"dropped": dropped,
	}


func undo() -> Dictionary:
	if not can_undo():
		return {"ok": false, "code": "UNDO_EMPTY", "state": {}}
	_cursor -= 1
	var e: Dictionary = _entries[_cursor]
	return {
		"ok": true,
		"code": "",
		"label": String(e["label"]),
		"state": (e["before"] as Dictionary).duplicate(true),
		"cursor": _cursor,
	}


func redo() -> Dictionary:
	if not can_redo():
		return {"ok": false, "code": "REDO_EMPTY", "state": {}}
	var e: Dictionary = _entries[_cursor]
	_cursor += 1
	return {
		"ok": true,
		"code": "",
		"label": String(e["label"]),
		"state": (e["after"] as Dictionary).duplicate(true),
		"cursor": _cursor,
	}


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _entries.size()


func last_label() -> String:
	if _cursor <= 0:
		return ""
	return String((_entries[_cursor - 1] as Dictionary)["label"])


func next_redo_label() -> String:
	if _cursor >= _entries.size():
		return ""
	return String((_entries[_cursor] as Dictionary)["label"])


func size() -> int:
	return _entries.size()


func depth() -> int:
	return _cursor


func clear() -> void:
	_entries = []
	_cursor = 0


func labels() -> Array:
	var out: Array = []
	for e in _entries:
		out.append(String((e as Dictionary)["label"]))
	return out
