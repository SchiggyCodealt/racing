class_name ParityTape
extends RefCounted
## The seeded random keyboard tape of the parity tools (tools/parity/*.mjs `tape(seed)`,
## mulberry32), in GDScript, so both sides drive the same keys: every 6-59 steps a new
## steer key (mostly full, some analogue), throttle/brake/reverse, handbrake (15 %) and nitro (20 %).
var _seed: int
var hold: int = 0
var ctrl := Car.Controls.new()

func _init(s: int) -> void:
	_seed = s

## JS Math.imul without 64-bit overflow: (a * b) mod 2^32 as a signed 32-bit int.
func _imul(a: int, b: int) -> int:
	var bb: int = b & 0xffffffff
	var lo: int = (a & 0xffff) * bb
	var hi: int = (((a >> 16) & 0xffff) * bb) & 0xffff
	return _i32(lo + (hi << 16))

func _i32(v: int) -> int:
	v &= 0xffffffff
	return v - 0x100000000 if v >= 0x80000000 else v

func _rnd() -> float:
	_seed = _i32(_seed + 0x6d2b79f5)
	var t: int = _imul(_seed ^ ((_seed & 0xffffffff) >> 15), 1 | _seed)
	t = _i32(_i32(t + _imul(t ^ ((t & 0xffffffff) >> 7), 61 | t)) ^ t)
	return float((t ^ ((t & 0xffffffff) >> 14)) & 0xffffffff) / 4294967296.0

func next() -> Car.Controls:
	hold -= 1
	if hold <= 0:
		hold = 6 + int(floor(_rnd() * 54))
		var keys: Array[float] = [-1.0, 0.0, 1.0]
		var key: float = keys[int(floor(_rnd() * 3))]
		ctrl.steer = key * (1.0 if _rnd() < 0.7 else _rnd())
		ctrl.throttle = maxf(-1.0, minf(1.0, _rnd() * 2.4 - 0.9))
		ctrl.handbrake = _rnd() < 0.15
		ctrl.nitro = 1.0 if _rnd() < 0.2 else 0.0
	return ctrl
