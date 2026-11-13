class_name EngineVoice
extends RefCounted
## engine_voice.gd (v6.12.0): a car's engine, synthesized in real time from the sim's rpm,
## throttle, load and nitro.
## ------------------------------------------------------------------
## Source and filter, like a real exhaust: each cylinder's firing is a pressure pulse (an impulse
## shaped by a two-pole low-pass: brighter with load and revs, a little combustion noise on top)
## that rings an exhaust pipe (a feedback comb: a delay line one pipe period long with a low-pass
## in the loop) and three body resonances (band-passes at fixed frequencies, so the timbre stays
## put while the pitch follows the revs). On top: intake roar (band-passed noise with the throttle),
## a gear or supercharger whine (a sine locked to the revs), a turbo whistle with its spool, a
## mechanical rattle, crackles on a lift from high revs and the rev limiter's cut. The pitch is
## exactly the sim's rpm: one firing every 720° / cylinders of crank, interpolated across a block.
##
## Each car's character is one ENGINES entry (data, see its keys); `gain` sets the level (every
## car about the same loudness at full load, tools/engine_preview.gd measures it).
##
## Use (game/audio/car_audio.gd feeds it once a frame from the car):
##   var v := EngineVoice.new("thunder", 32000.0)
##   v.rpm = car.rpm; v.load = 1.0; v.throttle = 1.0; v.boost = 0.0; v.limiter = false
##   var frames: PackedVector2Array = v.render(n)     # n samples at the mix rate, -1..1 stereo
## Gear changes come from the sim itself: the rpm drops to the next gear's and the load is 0
## while the car's _shift timer runs (no drive), then picks up. The voice is plain data and maths
## (no nodes), so tests and tools render it offline.

## Each car's engine. cylinders: four-stroke, one firing every 720 / cylinders degrees.
## intervals: relative firing intervals (uneven = burble), amps: the pulse size per firing slot
## (bank and pipe differences), jitter: random size per firing. pulse: the pulse's low-pass (Hz)
## off load at idle and at full load and revs. pipe: the exhaust pipe's resonance (Hz), its
## feedback (- = closed end: odd harmonics, hollow) and damping (0..1 low-pass in the loop).
## body: three resonances [Hz, Q, gain]. direct: the pulse itself in the mix. tone: the output
## low-pass (Hz). rough: combustion noise. intake: roar level and band (Hz). whine: a sine at
## whine_ratio × the crank frequency (gear / supercharger whine) on load. turbo: whistle level
## (0 = none) between turbo_hz [low, high] with the spool. rattle: mechanical clatter. drive:
## soft-clip drive at full load. off: the level off throttle (engine braking). crackle: pops on a
## lift from high revs (0 none). limiter_hz: the rev limiter's cut rate. gain: output level.
const ENGINES := {
	"racer": {
		"name": "race V6", "cylinders": 6,
		"intervals": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0], "amps": [1.0, 0.9, 0.97, 1.0, 0.88, 0.95], "jitter": 0.05,
		"pulse": [420.0, 2600.0], "pipe": [190.0, 0.55, 0.35],
		"body": [[150.0, 1.3, 1.0], [720.0, 2.2, 0.55], [2300.0, 3.0, 0.22]], "direct": 0.35,
		"tone": 6500.0, "rough": 0.16, "intake": [0.08, 1600.0], "whine": [0.010, 7.0],
		"turbo": 0.0, "turbo_hz": [0.0, 0.0], "rattle": 0.0, "drive": 1.6, "off": 0.32, "crackle": 0.3,
		"limiter_hz": 18.0, "gain": 1.34,
	},
	"kestrel": {
		"name": "high-revving four", "cylinders": 4,
		"intervals": [1.0, 1.0, 1.0, 1.0], "amps": [1.0, 0.95, 0.98, 0.94], "jitter": 0.05,
		"pulse": [600.0, 3600.0], "pipe": [330.0, 0.5, 0.3],
		"body": [[260.0, 1.5, 0.85], [1150.0, 2.4, 0.65], [3300.0, 3.2, 0.32]], "direct": 0.3,
		"tone": 8500.0, "rough": 0.28, "intake": [0.16, 2300.0], "whine": [0.008, 6.0],
		"turbo": 0.0, "turbo_hz": [0.0, 0.0], "rattle": 0.0, "drive": 2.4, "off": 0.28, "crackle": 0.15,
		"limiter_hz": 22.0, "gain": 1.19,
	},
	"thunder": {
		"name": "cross-plane V8", "cylinders": 8,
		"intervals": [1.06, 0.94, 1.02, 0.98, 1.05, 0.95, 1.03, 0.97], "amps": [1.0, 0.68, 1.0, 1.0, 0.7, 1.0, 0.68, 0.72], "jitter": 0.07,
		"pulse": [260.0, 1500.0], "pipe": [92.0, -0.6, 0.4],
		"body": [[82.0, 1.0, 1.2], [320.0, 1.8, 0.6], [1250.0, 2.5, 0.16]], "direct": 0.45,
		"tone": 3800.0, "rough": 0.22, "intake": [0.06, 900.0], "whine": [0.0, 0.0],
		"turbo": 0.0, "turbo_hz": [0.0, 0.0], "rattle": 0.0, "drive": 1.9, "off": 0.42, "crackle": 0.6,
		"limiter_hz": 14.0, "gain": 0.90,
	},
	"drifter": {
		"name": "turbo rally four", "cylinders": 4,
		"intervals": [1.02, 0.98, 1.01, 0.99], "amps": [1.0, 0.9, 0.97, 0.92], "jitter": 0.06,
		"pulse": [380.0, 2100.0], "pipe": [240.0, -0.5, 0.4],
		"body": [[180.0, 1.4, 1.0], [860.0, 2.2, 0.5], [2600.0, 3.0, 0.2]], "direct": 0.35,
		"tone": 5200.0, "rough": 0.3, "intake": [0.06, 1300.0], "whine": [0.0, 0.0],
		"turbo": 1.0, "turbo_hz": [2600.0, 6800.0], "rattle": 0.0, "drive": 1.9, "off": 0.3, "crackle": 0.55,
		"limiter_hz": 16.0, "gain": 1.28,
	},
	"dune": {
		"name": "air-cooled buggy four", "cylinders": 4,
		"intervals": [1.08, 0.92, 1.05, 0.95], "amps": [1.0, 0.78, 0.94, 0.74], "jitter": 0.16,
		"pulse": [320.0, 1500.0], "pipe": [150.0, 0.42, 0.45],
		"body": [[130.0, 1.2, 1.0], [520.0, 1.6, 0.65], [1750.0, 2.0, 0.3]], "direct": 0.4,
		"tone": 4200.0, "rough": 0.42, "intake": [0.05, 1100.0], "whine": [0.0, 0.0],
		"turbo": 0.0, "turbo_hz": [0.0, 0.0], "rattle": 0.38, "drive": 2.1, "off": 0.4, "crackle": 0.12,
		"limiter_hz": 11.0, "gain": 1.14,
	},
	"vortex": {
		"name": "screaming V12", "cylinders": 12,
		"intervals": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
		"amps": [1.0, 0.97, 0.99, 0.95, 1.0, 0.98, 0.96, 1.0, 0.95, 0.99, 0.98, 0.96], "jitter": 0.04,
		"pulse": [900.0, 5200.0], "pipe": [430.0, 0.5, 0.25],
		"body": [[400.0, 1.8, 0.75], [1550.0, 2.6, 0.7], [3900.0, 3.2, 0.45]], "direct": 0.25,
		"tone": 10000.0, "rough": 0.1, "intake": [0.14, 2900.0], "whine": [0.012, 8.0],
		"turbo": 0.0, "turbo_hz": [0.0, 0.0], "rattle": 0.0, "drive": 2.2, "off": 0.3, "crackle": 0.2,
		"limiter_hz": 24.0, "gain": 0.83,
	},
	"apex": {
		"name": "shrieking V10", "cylinders": 10,
		"intervals": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
		"amps": [1.0, 0.93, 0.98, 0.9, 1.0, 0.95, 0.91, 1.0, 0.94, 0.97], "jitter": 0.05,
		"pulse": [1000.0, 6000.0], "pipe": [520.0, -0.45, 0.22],
		"body": [[470.0, 2.0, 0.7], [1900.0, 2.8, 0.75], [4600.0, 3.4, 0.5]], "direct": 0.22,
		"tone": 11000.0, "rough": 0.12, "intake": [0.18, 3400.0], "whine": [0.02, 9.0],
		"turbo": 0.0, "turbo_hz": [0.0, 0.0], "rattle": 0.0, "drive": 2.5, "off": 0.26, "crackle": 0.25,
		"limiter_hz": 28.0, "gain": 0.77,
	},
}
const DEFAULT := "racer"

# ---- what the car does (set before each render) ----
## Engine speed (rpm, the sim's car.rpm). The render glides from the last block's to this one.
var rpm := 1000.0
## The driver's throttle 0..1 (intake roar, turbo spool).
var throttle := 0.0
## How hard the engine works 0..1: the throttle while in gear and not shifting (0 off throttle,
## engine braking, or during a gear change).
var load := 0.0
## Nitro burning 0..1: harder and brighter, plus a whine an octave up.
var boost := 0.0
## On the rev limiter (full throttle at the redline): the ignition cuts in and out.
var limiter := false
## Overall level 0..1 (fades the voice in and out).
var level := 1.0

var car_id := DEFAULT
var character: Dictionary = {}
var mix_rate := 32000.0
## The turbo's spool 0..1 (the blow-off sound reads it on a lift).
var spool := 0.0
## Pops left in the current crackle burst window (s); counts of what happened (tests).
var crackle_time := 0.0
var fired := 0
var popped := 0
var cut := 0

# per-car constants
var _cyl := 4
var _iv := PackedFloat32Array()
var _amp := PackedFloat32Array()
var _jit := 0.05
var _idle := 1000.0
var _red := 8000.0
var _pipe_len := 100
var _pipe_fb := 0.5
var _pipe_damp := 0.3
var _bq := PackedFloat32Array() # 3 band-passes × [b0, a1, a2] (b2 = -b0)
var _bgain := PackedFloat32Array()
var _direct := 0.3
var _tone_k := 0.5
var _rough := 0.2
var _intake := 0.0
var _ib := PackedFloat32Array() # intake band-pass [b0, a1, a2]
var _whine := 0.0
var _whine_ratio := 0.0
var _turbo := 0.0
var _turbo_lo := 0.0
var _turbo_hi := 0.0
var _rattle := 0.0
var _drive := 1.5
var _off := 0.3
var _crackle := 0.0
var _lim_hz := 16.0
var _gain := 0.5
var _pulse_lo := 400.0
var _pulse_hi := 2000.0

# running state
var _rpm_now := -1.0
var _load_now := 0.0
var _boost_now := 0.0
var _lvl_now := 0.0
var _fph := 0.0       # phase within the current firing interval (intervals)
var _slot := 0
var _carry := 0.0     # the part of a firing's impulse that lands on the next sample
var _p1 := 0.0        # pulse low-pass (two one-poles)
var _p2 := 0.0
var _env := 0.0       # combustion noise envelope (decays after each firing)
var _pipe := PackedFloat32Array()
var _pw := 0
var _pl := 0.0        # the pipe loop's low-pass
var _bx1 := PackedFloat32Array([0, 0, 0])
var _bx2 := PackedFloat32Array([0, 0, 0])
var _by1 := PackedFloat32Array([0, 0, 0])
var _by2 := PackedFloat32Array([0, 0, 0])
var _ix1 := 0.0
var _ix2 := 0.0
var _iy1 := 0.0
var _iy2 := 0.0
var _wph := 0.0       # whine phase
var _tph := 0.0       # turbo whistle phase
var _rat := 0.0       # rattle envelope
var _rat_hp := 0.0
var _pop := 0.0       # pop envelope
var _pop_hp := 0.0
var _lim_ph := 0.0
var _dc_x := 0.0
var _dc_y := 0.0
var _lp := 0.0
var _seed := 22222
var _last_load := 0.0
var _high_load_t := 0.0


func _init(p_car_id: String = DEFAULT, p_mix_rate: float = 32000.0) -> void:
	car_id = p_car_id if ENGINES.has(p_car_id) else DEFAULT
	mix_rate = p_mix_rate
	character = ENGINES[car_id]
	var sp := Cars.spec(car_id)
	_idle = sp.idle_rpm
	_red = sp.redline
	rpm = _idle
	_seed = 1 + absi(hash(car_id)) % 100000
	_setup()


## The engine character of car `id` (unknown ids: the Racer's).
static func of(id: String) -> Dictionary:
	return ENGINES.get(id, ENGINES[DEFAULT])


## The firing frequency (Hz) of a car with `cylinders` at `rpm`: the pitch the ear follows.
static func firing_hz(cylinders: int, at_rpm: float) -> float:
	return at_rpm / 120.0 * cylinders


func _setup() -> void:
	var c := character
	_cyl = int(c.cylinders)
	_iv = PackedFloat32Array(c.intervals)
	_amp = PackedFloat32Array(c.amps)
	var s := 0.0
	for v in _iv:
		s += v
	for i in _iv.size():
		_iv[i] = _iv[i] * _cyl / s # (they sum to the cylinder count: one cycle)
	_jit = float(c.jitter)
	_pulse_lo = float(c.pulse[0])
	_pulse_hi = float(c.pulse[1])
	_pipe_len = maxi(2, roundi(mix_rate / float(c.pipe[0])))
	_pipe_fb = float(c.pipe[1])
	_pipe_damp = float(c.pipe[2])
	_pipe = PackedFloat32Array()
	_pipe.resize(_pipe_len)
	_bq = PackedFloat32Array()
	_bgain = PackedFloat32Array()
	for b: Array in c.body:
		var co := _bandpass(float(b[0]), float(b[1]))
		_bq.append_array(co)
		_bgain.append(float(b[2]))
	_direct = float(c.direct)
	_tone_k = 1.0 - exp(-TAU * minf(float(c.tone), mix_rate * 0.45) / mix_rate)
	_rough = float(c.rough)
	_intake = float(c.intake[0])
	_ib = _bandpass(float(c.intake[1]), 0.9)
	_whine = float(c.whine[0])
	_whine_ratio = float(c.whine[1])
	_turbo = float(c.turbo)
	_turbo_lo = float(c.turbo_hz[0])
	_turbo_hi = float(c.turbo_hz[1])
	_rattle = float(c.rattle)
	_drive = float(c.drive)
	_off = float(c.off)
	_crackle = float(c.crackle)
	_lim_hz = float(c.limiter_hz)
	_gain = float(c.gain)


## How hard the cylinders fire at load `ld` with `rn_lo` = 1 - the share of the rev range: the
## off-throttle level `off` up to 1 at full load, and at idle the work of keeping it turning.
func off_work(ld: float, rn_lo: float) -> float:
	return _off + (1.0 - _off) * maxf(ld, 0.35 * rn_lo * rn_lo)


## Take rpm, throttle, load, nitro and the limiter from the sim's car (after its last step): the
## load is the throttle in the gear's direction, 0 while the gearbox shifts (no drive then).
func follow(car: Car) -> void:
	rpm = car.rpm
	var thr := car.throttle
	var fwd := car.gear >= 0
	throttle = maxf(0.0, thr if fwd else -thr)
	load = throttle if car._shift <= 0.0 else 0.0
	boost = car.boost
	limiter = load > 0.5 and car.rpm >= _red * 0.985


## RBJ band-pass (0 dB peak) at `f` Hz with quality `q`: [b0, a1, a2] normalised (b2 = -b0).
func _bandpass(f: float, q: float) -> PackedFloat32Array:
	var w := TAU * minf(f, mix_rate * 0.45) / mix_rate
	var al := sin(w) / (2.0 * q)
	var a0 := 1.0 + al
	return PackedFloat32Array([al / a0, -2.0 * cos(w) / a0, (1.0 - al) / a0])


## Start over (a restart): the next render starts from `rpm` without a glide.
func reset() -> void:
	_rpm_now = -1.0
	_fph = 0.0
	_carry = 0.0
	_p1 = 0.0
	_p2 = 0.0
	_env = 0.0
	_pipe.fill(0.0)
	_pl = 0.0
	for i in 3:
		_bx1[i] = 0.0
		_bx2[i] = 0.0
		_by1[i] = 0.0
		_by2[i] = 0.0
	_ix1 = 0.0
	_ix2 = 0.0
	_iy1 = 0.0
	_iy2 = 0.0
	_rat = 0.0
	_pop = 0.0
	spool = 0.0
	crackle_time = 0.0


## `n` stereo samples of the engine (both channels the same; a 3D player places it).
func render(n: int) -> PackedVector2Array:
	var mono := render_mono(n)
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var v := mono[i]
		out[i] = Vector2(v, v)
	return out


## `n` mono samples of the engine at mix_rate (tools and tests).
func render_mono(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	if n <= 0:
		return out
	var fs := mix_rate
	var dt_block := n / fs
	# ---- block parameters (glide from the last block's values) ----
	var r1 := clampf(rpm, 300.0, _red * 1.05)
	var r0 := r1 if _rpm_now < 0.0 else _rpm_now
	_rpm_now = r1
	var ld1 := clampf(load, 0.0, 1.0)
	var ld0 := _load_now
	_load_now = ld1
	var bo1 := clampf(boost, 0.0, 1.0)
	var bo0 := _boost_now
	_boost_now = bo1
	var lv1 := clampf(level, 0.0, 1.0)
	var lv0 := _lvl_now
	_lvl_now = lv1
	var rn := clampf((r1 - _idle) / maxf(1.0, _red - _idle), 0.0, 1.0)
	# crackle: a lift (load falling from high) at high revs opens a window of pops
	if _last_load > 0.6 and ld1 < 0.15 and rn > 0.45 and _crackle > 0.0:
		crackle_time = 0.35 + 0.9 * _crackle
	_last_load = ld1
	if crackle_time > 0.0:
		crackle_time = maxf(0.0, crackle_time - dt_block)
	# (about 6-20 pops a second whatever the firing rate)
	var pop_chance := clampf(_crackle * 22.0 / maxf(1.0, firing_hz(_cyl, r1)), 0.0, 0.5) if crackle_time > 0.0 and ld1 < 0.2 else 0.0
	# turbo spool: builds with load and revs, falls when the throttle lifts
	var sp_to := ld1 * clampf((r1 - 0.3 * _red) / (0.55 * _red), 0.0, 1.0) if _turbo > 0.0 else 0.0
	spool += (sp_to - spool) * minf(1.0, dt_block * (1.6 if sp_to > spool else 4.0))
	# pulse brightness: off load at idle .. full load at the redline (nitro brighter still)
	var bright := clampf(0.15 + 0.5 * ld1 + 0.35 * rn + 0.4 * bo1, 0.0, 1.3)
	var pf := _pulse_lo * pow(_pulse_hi / _pulse_lo, bright)
	var pk := 1.0 - exp(-TAU * minf(pf, fs * 0.45) / fs)
	var pnorm := 6.0 * pow(0.25 / pk, 0.4) # (a duller pulse carries less energy: keep most of the level)
	# how hard the cylinders fire: off throttle `off`, more with load; idle keeps a little work
	var rn_lo := 1.0 - rn
	var work0 := off_work(ld0, rn_lo)
	var work1 := off_work(ld1, rn_lo)
	var env_k := exp(-1.0 / (0.0012 * fs))          # combustion noise decays in ~1 ms
	var rat_k := exp(-1.0 / (0.0025 * fs))
	var pop_k := exp(-1.0 / (0.004 * fs))
	var pipe_fb := _pipe_fb
	var pdamp := _pipe_damp
	var inc_k := _cyl / (120.0 * fs)               # firing intervals per sample per rpm
	var whine_k := _whine_ratio / (60.0 * fs)       # whine cycles per sample per rpm
	var whine_amp0 := _whine * ld0 + 0.05 * bo0
	var whine_amp1 := _whine * ld1 + 0.05 * bo1
	var turbo_amp := _turbo * 0.035 * spool * spool
	var turbo_inc := (_turbo_lo + (_turbo_hi - _turbo_lo) * spool) / fs
	var intake_amp := _intake * clampf(throttle, 0.0, 1.0) * (0.25 + 0.75 * rn * rn)
	var lim_on := limiter
	var lim_inc := _lim_hz / fs
	var drv := 1.0 + (_drive - 1.0) * (0.3 + 0.7 * ld1) + 1.2 * bo1
	var norm := (1.0 + drv) / drv * 0.5
	var g := _gain * (1.0 + 0.25 * bo1)
	var dr := (r1 - r0) / n
	var dl := (ld1 - ld0) / n
	var db := (bo1 - bo0) / n
	var dlv := (lv1 - lv0) / n
	var dwa := (whine_amp1 - whine_amp0) / n
	var dwk := (work1 - work0) / n
	# ---- running state into locals ----
	var fph := _fph
	var slot := _slot
	var carry := _carry
	var p1 := _p1
	var p2 := _p2
	var env := _env
	var pipe := _pipe
	var plen := _pipe_len
	var pw := _pw
	var pl := _pl
	var bq := _bq
	var b0a := bq[0]; var a1a := bq[1]; var a2a := bq[2]
	var b0b := bq[3]; var a1b := bq[4]; var a2b := bq[5]
	var b0c := bq[6]; var a1c := bq[7]; var a2c := bq[8]
	var ga := _bgain[0]; var gb := _bgain[1]; var gc := _bgain[2]
	var xa1 := _bx1[0]; var xa2 := _bx2[0]; var ya1 := _by1[0]; var ya2 := _by2[0]
	var xb1 := _bx1[1]; var xb2 := _bx2[1]; var yb1 := _by1[1]; var yb2 := _by2[1]
	var xc1 := _bx1[2]; var xc2 := _bx2[2]; var yc1 := _by1[2]; var yc2 := _by2[2]
	var ib0 := _ib[0]; var ia1 := _ib[1]; var ia2 := _ib[2]
	var ix1 := _ix1; var ix2 := _ix2; var iy1 := _iy1; var iy2 := _iy2
	var wph := _wph
	var tph := _tph
	var rat := _rat
	var rat_hp := _rat_hp
	var pop := _pop
	var pop_hp := _pop_hp
	var lim_ph := _lim_ph
	var dcx := _dc_x
	var dcy := _dc_y
	var lp := _lp
	var tone_k := _tone_k
	var seed := _seed
	var iv := _iv
	var amps := _amp
	var cyl := _cyl
	var jit := _jit
	var rough := _rough
	var direct := _direct
	var rattle := _rattle
	var r := r0
	var ld := ld0
	var bo := bo0
	var lv := lv0
	var wa := whine_amp0
	var wk := work0
	var n_fired := 0
	var n_pop := 0
	var n_cut := 0
	for i in n:
		r += dr
		ld += dl
		bo += db
		lv += dlv
		wa += dwa
		wk += dwk
		# the rev limiter: the ignition cuts out for part of each period and the revs sag
		var cutting := false
		if lim_on:
			lim_ph += lim_inc
			if lim_ph >= 1.0:
				lim_ph -= 1.0
			cutting = lim_ph < 0.42
		var rr := r * (0.975 if cutting else 1.0)
		# firing
		var x := carry
		carry = 0.0
		var inc := rr * inc_k
		fph += inc
		var len_s := iv[slot]
		if fph >= len_s:
			fph -= len_s
			seed = (seed * 1103515245 + 12345) & 0x7fffffff
			var u := float(seed) / 2147483648.0
			var a := amps[slot] * (1.0 + jit * (2.0 * u - 1.0)) * wk * (0.8 + 0.2 * rr / 6000.0)
			if cutting:
				a = 0.0
				n_cut += 1
			elif ld < 0.15 and u < 0.06:
				a *= 0.3 # a lazy firing off throttle: burble
			if pop_chance > 0.0 and u > 1.0 - pop_chance:
				pop = 0.5 + 0.5 * u
				a += 1.2 * pop # (a bang through the pipe, then the crack of the noise burst)
				n_pop += 1
			var f := fph / inc # how far past the crossing (0..1 samples)
			x += a * (1.0 - f)
			carry = a * f
			env = maxf(env, a)
			if rattle > 0.0:
				rat = maxf(rat, rattle * (0.5 + u))
			n_fired += 1
			slot += 1
			if slot >= cyl:
				slot = 0
		# noise (one LCG for everything)
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var nz := float(seed) / 1073741824.0 - 1.0
		# the pulse: two one-pole low-passes of the impulse, plus combustion noise
		var exc := x * pnorm + nz * env * rough
		p1 += (exc - p1) * pk
		p2 += (p1 - p2) * pk
		var pulse := p2
		# the exhaust pipe: feedback comb with a low-pass in the loop
		var back := pipe[pw]
		pl += (back - pl) * (1.0 - pdamp)
		var py := pulse + pipe_fb * pl
		pipe[pw] = py
		pw += 1
		if pw >= plen:
			pw = 0
		# body resonances
		var ya := b0a * (py - xa2) - a1a * ya1 - a2a * ya2
		xa2 = xa1; xa1 = py; ya2 = ya1; ya1 = ya
		var yb := b0b * (py - xb2) - a1b * yb1 - a2b * yb2
		xb2 = xb1; xb1 = py; yb2 = yb1; yb1 = yb
		var yc := b0c * (py - xc2) - a1c * yc1 - a2c * yc2
		xc2 = xc1; xc1 = py; yc2 = yc1; yc1 = yc
		var s := ya * ga + yb * gb + yc * gc + py * direct
		# intake roar: band-passed noise, pulsing with the firings
		if intake_amp > 0.0:
			var iy := ib0 * (nz - ix2) - ia1 * iy1 - ia2 * iy2
			ix2 = ix1; ix1 = nz; iy2 = iy1; iy1 = iy
			s += iy * intake_amp * (0.6 + 0.4 * minf(1.0, env))
		# whine locked to the revs (gear whine on load, the nitro's harder tone an octave up)
		if wa > 0.0005:
			wph += rr * whine_k
			if wph >= 1.0:
				wph -= 1.0
			var sw := sin(TAU * wph)
			s += wa * (sw + 0.5 * bo * sw * sw * sw)
		# turbo whistle
		if turbo_amp > 0.0001:
			tph += turbo_inc
			if tph >= 1.0:
				tph -= 1.0
			s += turbo_amp * sin(TAU * tph) * (0.8 + 0.2 * nz)
		# rattle: high-passed noise bursts on the firings
		if rat > 0.001:
			rat_hp += (nz - rat_hp) * 0.35
			s += (nz - rat_hp) * rat * 0.5
			rat *= rat_k
		# a crackle: a sharp burst of bright noise
		if pop > 0.001:
			pop_hp += (nz - pop_hp) * 0.2
			s += (nz - pop_hp) * pop * 0.55
			pop *= pop_k
		env *= env_k
		# DC blocker, tone low-pass, soft clip
		dcy = s - dcx + 0.996 * dcy
		dcx = s
		lp += (dcy - lp) * tone_k
		var d := lp * drv
		out[i] = d / (1.0 + absf(d)) * norm * g * lv
	# ---- state back ----
	_fph = fph
	_slot = slot
	_carry = carry
	_p1 = p1
	_p2 = p2
	_env = env
	_pw = pw
	_pl = pl
	_bx1[0] = xa1; _bx2[0] = xa2; _by1[0] = ya1; _by2[0] = ya2
	_bx1[1] = xb1; _bx2[1] = xb2; _by1[1] = yb1; _by2[1] = yb2
	_bx1[2] = xc1; _bx2[2] = xc2; _by1[2] = yc1; _by2[2] = yc2
	_ix1 = ix1; _ix2 = ix2; _iy1 = iy1; _iy2 = iy2
	_wph = wph
	_tph = tph
	_rat = rat
	_rat_hp = rat_hp
	_pop = pop
	_pop_hp = pop_hp
	_lim_ph = lim_ph
	_dc_x = dcx
	_dc_y = dcy
	_lp = lp
	_seed = seed
	fired += n_fired
	popped += n_pop
	cut += n_cut
	return out
