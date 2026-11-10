extends RefCounted
## Free-mode take: the recorded cursor path, the click log and the sim events a
## human produced by playing. Everything here is pure data + math, so one script
## serves three callers:
##
##   live screen  game_screen.gd  records it while the player clicks (R to start/stop)
##   film         movie_scene.gd  replays it frame-exactly (`render.sh --take=<file>`)
##   tests        t_free_mode.gd  checks the sampling math with no window at all
##
## Take shape (schema 1):
##   {
##     "schema": 1, "seed": 7, "fps": 60, "duration": 12.345,
##     "project": "res://data/sample_project.json",
##     "cursor": [[t, x, y], ...],   # 1080x1920 design-space samples, time-ordered
##     "clicks": [{"t": .., "x": .., "y": .., "type": .., "cell": [x,y]|null, "ok": bool}],
##     "timeline": [{"id": "free_000", "at": .., "type": .., "payload": {}}]
##   }
##
## Coordinates are design-space (1080x1920), never window-space: the F5 window is
## 540x960 (half scale), so a take recorded there must replay into the 1080x1920 film
## without any rescaling.

const SCHEMA := 1
## How long the hand reads as "pressed" after a click, and how much it shrinks.
## 2026-11-10：按下状态保持更久（右键是一闪而过，看不出"下去再上来"）。
const PRESS_SECONDS := 0.22
## 按下白环：0.25s 内从 0 扩散到 RING_RADIUS，透明度线性淡出。
const RING_SECONDS := 0.25
const RING_RADIUS := 150.0
const PRESS_SCALE := 0.80

const EventModel = preload("res://src/core/event_model.gd")


static func build(seed_value: int, fps: int, duration: float, cursor: Array,
		clicks: Array, timeline: Array, project_path: String, drag: Array = []) -> Dictionary:
	return {
		"schema": SCHEMA,
		"seed": seed_value,
		"fps": fps,
		"duration": snappedf(duration, 0.001),
		"project": project_path,
		"cursor": cursor.duplicate(true),
		"clicks": clicks.duplicate(true),
		"drag": drag.duplicate(true),
		"timeline": timeline.duplicate(true),
	}


## 拖动轨迹取样：{from: [x,y], pos: Vector2} 或 {}（不在拖动中）。
## rows 是 [[t, from_x, from_y, pos_x, pos_y], ...]，按时间线性插值。
static func drag_at(take: Dictionary, t: float) -> Dictionary:
	var rows = take.get("drag", [])
	if typeof(rows) != TYPE_ARRAY or (rows as Array).is_empty():
		return {}
	var arr: Array = rows
	var head: Array = arr[0]
	var tail: Array = arr[arr.size() - 1]
	if t < float(head[0]) or t > float(tail[0]):
		return {}
	var prev: Array = head
	var next: Array = head
	for row in arr:
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 5:
			continue
		if float((row as Array)[0]) <= t:
			prev = row
		else:
			next = row
			break
	var t0 := float((prev as Array)[0])
	var t1 := float((next as Array)[0])
	# 2026-11-10：drag 采样只在**真正拖拽的那几段**里密集。两条样本之间隔太久
	# （> 0.25s）说明这是两次手势之间的空档，不能插值——否则成片会把上一次拖拽的
	# 棋子一直画在原地，看起来像"一枚棋子飘在棋盘上"（帧 1129 就是这个）。
	if prev != next and t1 - t0 > 0.25:
		return {}
	var p := 0.0 if t1 <= t0 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	var pos := Vector2(float((prev as Array)[3]), float((prev as Array)[4])).lerp(
			Vector2(float((next as Array)[3]), float((next as Array)[4])), p)
	return {"from": [int((prev as Array)[1]), int((prev as Array)[2])], "pos": pos}


## Linear sample of the recorded path. `visible` is false when the take carries no
## cursor track at all (a timeline-only film), so the film can skip the overlay.
static func cursor_at(take: Dictionary, t: float) -> Dictionary:
	var samples = take.get("cursor", [])
	if typeof(samples) != TYPE_ARRAY or (samples as Array).is_empty():
		return {"visible": false}
	var arr: Array = samples
	var first = arr[0]
	if typeof(first) != TYPE_ARRAY or (first as Array).size() < 3:
		return {"visible": false}
	var head: Array = first
	var tail: Array = arr[arr.size() - 1]
	if t <= float(head[0]):
		return {"visible": true, "x": float(head[1]), "y": float(head[2])}
	if t >= float(tail[0]):
		return {"visible": true, "x": float(tail[1]), "y": float(tail[2])}
	var lo := 0
	var hi := arr.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		var row = arr[mid]
		if typeof(row) == TYPE_ARRAY and float((row as Array)[0]) <= t:
			lo = mid
		else:
			hi = mid
	var a: Array = arr[lo]
	var b: Array = arr[hi]
	var span := float(b[0]) - float(a[0])
	var k := 0.0 if span <= 0.0 else clampf((t - float(a[0])) / span, 0.0, 1.0)
	return {
		"visible": true,
		"x": lerpf(float(a[1]), float(b[1]), k),
		"y": lerpf(float(a[2]), float(b[2]), k),
	}


## Nearest click within PRESS_SECONDS ({} when the frame is not near a click). The
## film uses it for the hand's press feedback; the live screen uses it for nothing.
static func click_at(take: Dictionary, t: float) -> Dictionary:
	var best := {}
	var best_dt := PRESS_SECONDS + 1.0e-6
	for raw in take.get("clicks", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = raw
		var dt: float = absf(float(c.get("t", -1.0)) - t)
		if dt <= best_dt:
			best_dt = dt
			best = c
	return best


## Structural check the film runs before it renders a single frame: a broken take
## must fail loudly instead of producing a film with a frozen or jumping cursor.
static func validate(take: Dictionary) -> Dictionary:
	var errors: Array = []
	if int(take.get("schema", 0)) != SCHEMA:
		errors.append("schema must be %d" % SCHEMA)
	if typeof(take.get("timeline", null)) != TYPE_ARRAY:
		errors.append("timeline must be an array")
	if typeof(take.get("cursor", [])) != TYPE_ARRAY:
		errors.append("cursor must be an array")
	if typeof(take.get("clicks", [])) != TYPE_ARRAY:
		errors.append("clicks must be an array")
	if int(take.get("fps", 0)) <= 0:
		errors.append("fps must be positive")
	var last_t := -1.0
	var checked := 0
	for raw in take.get("cursor", []):
		if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
			errors.append("cursor sample must be [t, x, y]")
			break
		var row: Array = raw
		var t := float(row[0])
		if t < last_t - 1.0e-6:
			errors.append("cursor samples must be time-ordered")
			break
		last_t = t
		checked += 1
	if checked == 0 and typeof(take.get("cursor", [])) == TYPE_ARRAY:
		errors.append("cursor track is empty")
	return {"ok": errors.is_empty(), "errors": errors}


## A recording only produces sim events, but a hand-written take (or a take from an
## older build) may omit `channel`. Without it the evaluator rejects every event with
## EV_CHANNEL and the film happily renders the cursor over a frozen board — the exact
## "I clicked merge and nothing happened" dud. Fill the channel in from the type
## table; an unknown type is left alone so the evaluator still reports it loudly.
static func normalize_timeline(timeline: Array) -> Array:
	var out: Array = []
	for raw in timeline:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = (raw as Dictionary).duplicate(true)
		if String(event.get("channel", "")).is_empty():
			var type := String(event.get("type", ""))
			if EventModel.SIM_TYPES.has(type):
				event["channel"] = "sim"
			elif EventModel.VIEW_TYPES.has(type):
				event["channel"] = "view"
			elif EventModel.AUDIO_TYPES.has(type):
				event["channel"] = "audio"
		out.append(event)
	return out


static func save(take: Dictionary, path: String) -> bool:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(take, "  ", false))
	file.close()
	return true


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return parser.data


## One-line summary for the live screen and the film log.
static func summary(take: Dictionary) -> String:
	var cursor: Array = take.get("cursor", []) if typeof(take.get("cursor", [])) == TYPE_ARRAY else []
	var clicks: Array = take.get("clicks", []) if typeof(take.get("clicks", [])) == TYPE_ARRAY else []
	var timeline: Array = take.get("timeline", []) if typeof(take.get("timeline", [])) == TYPE_ARRAY else []
	return "cursor=%d clicks=%d events=%d duration=%.3f seed=%d" % [
		cursor.size(), clicks.size(), timeline.size(),
		float(take.get("duration", 0.0)), int(take.get("seed", 0)),
	]
