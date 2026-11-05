extends RefCounted
## Scale feedback for pickup / drop / merge.
##
## Every curve is a pure function of (started_at, now): the live board feeds `_clock`,
## the film feeds frame/FPS, so a preview and a shipped frame animate identically.
## PEAK is capped so a chip never grows past the white corner frame (select frame is
## 160px wide, chip base is 132px; the drag frame is drawn 1.14x so 1.34 still fits).

const PEAK := 1.34
const DRAG_IN := 0.12
const SETTLE_DURATION := 0.2
const MERGE_DURATION := 0.4


static func _ease_out(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k)


## Chip in hand: grows to PEAK in DRAG_IN seconds and stays there while held.
static func drag_scale(started_at: float, now: float) -> float:
	var t := (now - started_at) / DRAG_IN
	if t <= 0.0:
		return 1.0
	if t >= 1.0:
		return PEAK
	return lerpf(1.0, PEAK, _ease_out(t))


## Chip just dropped: shrinks from PEAK back to its slot size.
static func settle_scale(started_at: float, now: float) -> float:
	var t := (now - started_at) / SETTLE_DURATION
	if t <= 0.0:
		return PEAK
	if t >= 1.0:
		return 1.0
	return lerpf(PEAK, 1.0, _ease_out(t))


## Merge result: 1.0 -> PEAK -> 1.0 over 0.4 s.
static func merge_scale(started_at: float, now: float) -> float:
	var t := (now - started_at) / MERGE_DURATION
	if t <= 0.0 or t >= 1.0:
		return 1.0
	return 1.0 + (PEAK - 1.0) * sin(PI * t)


static func scale_at(kind: String, started_at: float, now: float) -> float:
	match kind:
		"drag":
			return drag_scale(started_at, now)
		"settle":
			return settle_scale(started_at, now)
		"merge":
			return merge_scale(started_at, now)
	return 1.0


static func duration_of(kind: String) -> float:
	match kind:
		"drag":
			return DRAG_IN
		"settle":
			return SETTLE_DURATION
		"merge":
			return MERGE_DURATION
	return 0.0
