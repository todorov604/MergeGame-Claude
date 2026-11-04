extends RefCounted
## Registry + dispatcher for sim-channel event types.
##
## "Registers" here means code: an unknown type is rejected with
## SIM_UNKNOWN_TYPE instead of being silently ignored, matching the M0 rule that
## new event types are written, not invented by data.
##
## The mechanics live on the Sim object; this file only maps type -> handler so
## sim.gd stays a facade and the type list is one obvious place to look.

const TYPES := [
	"tap",
	"drag",
	"merge",
	"deliver",
	"order_claim",
	"board_full",
	"energy_tick",
	"level_complete",
	"level_next",
]


static func is_registered(type: String) -> bool:
	return TYPES.has(type)


static func types() -> Array:
	return TYPES.duplicate()


## `drag` is the same state command as `merge` (the view decides whether the
## gesture was a drag or a tap); both resolve to the merge rules.
static func apply(sim, event: Dictionary) -> Dictionary:
	if sim == null:
		return {"ok": false, "code": "SIM_UNKNOWN_TYPE", "note": "no sim instance"}
	var type := String(event.get("type", ""))
	var payload = event.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		payload = {}
	match type:
		"tap":
			return sim._do_tap(payload)
		"merge", "drag":
			return sim._do_merge(payload)
		"deliver":
			return sim._do_deliver(payload)
		"order_claim":
			return sim._do_order_claim(payload)
		"board_full":
			return sim._do_board_full(payload)
		"energy_tick":
			return sim._do_energy_tick(payload)
		"level_complete":
			return sim._do_level_complete(payload)
		"level_next":
			return sim._do_level_next(payload)
	return {"ok": false, "code": "SIM_UNKNOWN_TYPE", "note": "unregistered sim type: " + type}
