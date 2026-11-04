extends RefCounted
## Undo/redo tests: 60 edits round trip, ring capacity, deterministic comparison
## and the store integration.

const Store = preload("res://src/editor/project_store.gd")
const UndoStack = preload("res://src/editor/undo_stack.gd")

const SAMPLE := "res://data/sample_project.json"


func run(t) -> void:
	_canon(t)
	_sixty_edits(t)
	_capacity(t)
	_truncate_and_dedupe(t)
	_store_integration(t)


# ------------------------------------------------------- deterministic compare

func _canon(t) -> void:
	var p1 := {"a": 1, "b": {"y": 2, "x": 1}, "c": [1.0, 2.5, "s"]}
	var p2 := {"c": [1, 2.5, "s"], "b": {"x": 1, "y": 2}, "a": 1}
	t.eq(UndoStack.canon(p1), UndoStack.canon(p2), "key order never looks like an edit")
	t.ok(UndoStack.same(p1, p2), "same() compares canonically")
	t.eq(UndoStack.canon(2.0), UndoStack.canon(2), "integral float and int collapse")
	t.eq(UndoStack.canon(0.1 + 0.2), UndoStack.canon(0.3), "float noise is capped at 9 decimals")
	t.eq(UndoStack.canon([1, 2]), "[1,2]", "array canon")
	t.eq(UndoStack.canon({"k": "v"}), "{\"k\":\"v\"}", "object canon")
	t.ne(UndoStack.canon({"a": 1}), UndoStack.canon({"a": 2}), "different values differ")

	var s = UndoStack.new()
	var pushed: Dictionary = s.push("reorder", p1, p2)
	t.ok(not bool(pushed.get("ok", true)), "a reordered copy is not an undo entry")
	t.eq(s.size(), 0, "nothing recorded")


# ------------------------------------------------------------ 60 edits, 60 undos

func _sixty_edits(t) -> void:
	var store = Store.new()
	store.load_file(SAMPLE)
	var initial := UndoStack.canon(store.project)
	var applied := 0
	for i in 60:
		var r: Dictionary = store.apply_edit("coin+%d" % i, func(p):
			p["hud"]["coin"] = int(p["hud"]["coin"]) + 1
		)
		if bool(r.get("ok", false)):
			applied += 1
	t.eq(applied, 60, "60 edits applied")
	t.eq(int(store.project["hud"]["coin"]), 69, "60 increments landed on hud.coin")
	var final_key := UndoStack.canon(store.project)
	t.eq(store.history.size(), 60, "history holds 60 entries")
	t.eq(store.history.depth(), 60, "cursor sits at the top")
	t.eq(store.undo_label(), "coin+59", "last label is the last edit")

	var undone := 0
	for i in 60:
		if bool(store.undo().get("ok", false)):
			undone += 1
	t.eq(undone, 60, "undo 60 times")
	t.eq(UndoStack.canon(store.project), initial, "undo 60 returns to the initial tree")
	t.ok(not store.can_undo(), "nothing left to undo")
	t.eq(String(store.undo().get("code", "")), "UNDO_EMPTY", "undo past the start reports UNDO_EMPTY")

	var redone := 0
	for i in 60:
		if bool(store.redo().get("ok", false)):
			redone += 1
	t.eq(redone, 60, "redo 60 times")
	t.eq(UndoStack.canon(store.project), final_key, "redo 60 returns to the final tree")
	t.ok(not store.can_redo(), "nothing left to redo")
	t.eq(String(store.redo().get("code", "")), "REDO_EMPTY", "redo past the top reports REDO_EMPTY")


# ------------------------------------------------------------------- capacity

func _capacity(t) -> void:
	var s = UndoStack.new(64)
	t.eq(s.capacity, 64, "default capacity is 64")
	for i in 70:
		s.push("p%d" % i, {"n": i}, {"n": i + 1})
	t.eq(s.size(), 64, "the ring clamps at 64 entries")
	t.eq(s.depth(), 64, "cursor stays at the top after dropping old entries")
	t.eq(s.last_label(), "p69", "newest label survives")

	var steps := 0
	var last := {}
	while s.can_undo():
		var r: Dictionary = s.undo()
		last = r.get("state", {})
		steps += 1
	t.eq(steps, 64, "exactly 64 undos are available")
	t.eq(int(last.get("n", -1)), 6, "the oldest retained snapshot is n=6 (70-64)")

	var small = UndoStack.new(2)
	small.push("a", {"n": 0}, {"n": 1})
	small.push("b", {"n": 1}, {"n": 2})
	small.push("c", {"n": 2}, {"n": 3})
	t.eq(small.size(), 2, "capacity 2 keeps two entries")
	t.eq(small.labels(), ["b", "c"], "the oldest entry is the one dropped")


# --------------------------------------------------- redo tail + no-op edits

func _truncate_and_dedupe(t) -> void:
	var s = UndoStack.new(8)
	var a := {"x": 1}
	var b := {"x": 2}
	var c := {"x": 3}
	t.ok(not bool(s.push("same", a, a.duplicate(true)).get("ok", true)), "identical snapshots are not recorded")
	t.eq(s.size(), 0, "no-op push leaves the stack empty")

	s.push("a", a, b)
	s.push("b", b, c)
	t.eq(s.size(), 2, "two entries")
	t.ok(s.can_undo(), "can undo")
	t.ok(not s.can_redo(), "nothing to redo yet")
	t.eq(s.next_redo_label(), "", "no redo label at the top")

	s.undo()
	t.ok(s.can_redo(), "undo exposes a redo")
	t.eq(s.next_redo_label(), "b", "redo label is the undone edit")
	t.eq(s.last_label(), "a", "last applied label after undo")

	s.push("c", b, {"x": 9})
	t.eq(s.size(), 2, "pushing after undo drops the redo tail")
	t.ok(not s.can_redo(), "no redo after a new edit")
	t.eq(s.labels(), ["a", "c"], "the new edit replaces the dropped one")

	s.clear()
	t.eq(s.size(), 0, "clear empties the stack")
	t.ok(not s.can_undo() and not s.can_redo(), "clear resets both directions")


# ------------------------------------------------------------ store integration

func _store_integration(t) -> void:
	var store = Store.new()
	store.load_file(SAMPLE)
	t.eq(String(store.undo().get("code", "")), "UNDO_EMPTY", "undo on a fresh store reports empty")
	t.ok(not store.dirty, "fresh store is clean")

	var r: Dictionary = store.apply_edit("track", func(p):
		p["timeline"][0]["track"] = "board"
	)
	t.ok(bool(r.get("ok", false)), "apply_edit pushes", str(r))
	t.ok(store.dirty, "apply_edit sets dirty")
	t.eq(store.undo_label(), "track", "store exposes the last label")
	t.eq(String(store.project["timeline"][0].get("track", "")), "board", "edit landed")

	var noop: Dictionary = store.apply_edit("noop", func(p):
		pass
	)
	t.ok(not bool(noop.get("ok", true)), "a no-op edit is not recorded")
	t.eq(store.history.size(), 1, "history still has one entry")

	store.mark_clean()
	t.ok(not store.dirty, "mark_clean clears dirty")
	t.ok(bool(store.undo().get("ok", false)), "undo succeeds")
	t.ok(store.project["timeline"][0].get("track", "") == "", "undo removed the track key")
	t.ok(store.dirty, "undo marks the project dirty")
	t.ok(bool(store.redo().get("ok", false)), "redo succeeds")
	t.eq(String(store.project["timeline"][0].get("track", "")), "board", "redo restores the edit")
