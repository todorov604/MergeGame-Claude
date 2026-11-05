extends RefCounted
## Spawn flight: the chip a generator produces travels from the generator cell to the
## cell the sim picked, on a quadratic arc whose lift grows with the distance.
##
## Pure math on (from, to, progress): the live screen feeds `_clock`, the film feeds
## frame/FPS, so both draw the same curve at the same frame.

const DURATION := 0.34


static func progress(started_at: float, now: float) -> float:
	if DURATION <= 0.0:
		return 1.0
	return clampf((now - started_at) / DURATION, 0.0, 1.0)


static func point(from: Vector2, to: Vector2, t: float) -> Vector2:
	var k := clampf(t, 0.0, 1.0)
	var dir := to - from
	var dist := dir.length()
	if dist < 1.0:
		return from.lerp(to, k)
	var normal := Vector2(-dir.y, dir.x) / dist
	if normal.y > 0.0:
		normal = -normal  # bow toward the top of the screen, whatever the direction
	var lift := clampf(dist * 0.16, 14.0, 120.0)
	var control := (from + to) * 0.5 + normal * lift
	var u := 1.0 - k
	return u * u * from + 2.0 * u * k * control + k * k * to


## Height of the arc at the halfway point, used by tests to prove the lift scales.
static func lift_for(distance: float) -> float:
	return clampf(distance * 0.16, 14.0, 120.0)
