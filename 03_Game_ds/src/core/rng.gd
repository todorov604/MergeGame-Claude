extends RefCounted
## Deterministic RNG for the core sim.
##
## Seed + stream id is the entire input: no global rand(), no time seeding, no
## engine-dependent mixing. `state` is kept inside 63 bits so `>>` stays a
## logical shift and the printed/digested sequence is stable on every platform.
##
## make(seed, stream) -> instance; state is warmed up so nearby seeds diverge
## immediately (seed 7 and seed 8 must not produce the same first draw).

const MASK := 0x7FFFFFFFFFFFFFFF
const MANTISSA_MASK := 0x1FFFFFFFFFFFFF
const MANTISSA_SCALE := 9007199254740992.0

const K1 := 0x9E3779B1
const K2 := 0x85EBCA6B
const K3 := 0xC2B2AE35
const K4 := 0x7F4A7C15

var state: int = 0
var seed_value: int = 0
var stream_id: int = 0


static func make(seed_value_in: int, stream_id_in: int):
	var script: GDScript = load("res://src/core/rng.gd")
	var r = script.new()
	r.seed_value = seed_value_in
	r.stream_id = stream_id_in
	r.state = r.mix_seed(seed_value_in, stream_id_in)
	for i in range(6):
		r.next_u64()
	return r


func mix_seed(seed_in: int, stream_in: int) -> int:
	var x: int = seed_in & MASK
	x = (x ^ (stream_in * K1)) & MASK
	x = (x ^ (x >> 30)) & MASK
	x = (x * K2) & MASK
	x = (x ^ (x >> 27)) & MASK
	x = (x * K3) & MASK
	x = (x ^ (x >> 31)) & MASK
	x = (x + K4 + stream_in) & MASK
	if x == 0:
		x = 0x2545F4914F6CDD1D & MASK
	return x


func next_u64() -> int:
	var x: int = state & MASK
	x = (x ^ (x << 13)) & MASK
	x = (x ^ (x >> 7)) & MASK
	x = (x ^ (x << 17)) & MASK
	state = x
	return x


func next_float() -> float:
	var v: int = next_u64() & MANTISSA_MASK
	return float(v) / MANTISSA_SCALE


func next_int(n: int) -> int:
	if n <= 0:
		return 0
	return next_u64() % n


## Weighted pick over entries carrying "weight". Returns the index, or -1 when
## the list is empty / every weight is <= 0. Order matters, so callers must pass
## a deterministically built list.
func pick_weighted(entries: Array) -> int:
	if entries.is_empty():
		return -1
	var weights: Array = []
	var total := 0.0
	for e in entries:
		var w := 0.0
		if typeof(e) == TYPE_DICTIONARY:
			var raw = e.get("weight", 0)
			if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
				w = float(raw)
		if w < 0.0:
			w = 0.0
		weights.append(w)
		total += w
	if total <= 0.0:
		return -1
	var r := next_float() * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += float(weights[i])
		if r < acc:
			return i
	for i in range(weights.size() - 1, -1, -1):
		if float(weights[i]) > 0.0:
			return i
	return -1
