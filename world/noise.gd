## noise.gd
## ------------------------------------------------------------------
## Small maths helpers of the 3D world: the web game's seeded random
## numbers (mulberry32), 2D value noise and fbm (exact ports, for the small
## jobs where the shape should match: displaced rocks and trees), and fast
## fbm made from Godot's FastNoiseLite for the big loops (terrain, scenery
## placement), which would be slow in GDScript. The fast noise has the same
## range (0..1) and character (value noise, smoothstep interpolation,
## octaves at x2.03), not the same values.
extends RefCounted

const M32 := 0xFFFFFFFF


## Low 32 bits of a * b (Math.imul without the sign).
static func imul(a: int, b: int) -> int:
	return (a * b) & M32


static func hash2(ix: int, iz: int, seed: int) -> float:
	var h := imul(ix, 0x27d4eb2d) ^ imul(iz, 0x165667b1) ^ imul(seed, 0x9e3779b1)
	h = imul(h ^ (h >> 15), 0x85ebca6b)
	h = imul(h ^ (h >> 13), 0xc2b2ae35)
	h ^= h >> 16
	return float(h) / 4294967296.0


## 2D value noise in 0..1 (trackMesh.js vnoise).
static func vnoise(x: float, z: float, seed: int) -> float:
	var fx0 := floorf(x)
	var fz0 := floorf(z)
	var ix := int(fx0)
	var iz := int(fz0)
	var fx := x - fx0
	var fz := z - fz0
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var a := hash2(ix, iz, seed)
	var b := hash2(ix + 1, iz, seed)
	var c := hash2(ix, iz + 1, seed)
	var d := hash2(ix + 1, iz + 1, seed)
	return a + (b - a) * ux + (c - a) * uz + (a - b - c + d) * ux * uz


static func fbm(x: float, z: float, oct: int, seed: int) -> float:
	var v := 0.0
	var a := 0.5
	var f := 1.0
	var norm := 0.0
	for k in oct:
		v += a * vnoise(x * f, z * f, seed + k * 101)
		norm += a
		a *= 0.5
		f *= 2.03
	return v / norm


## Tileable value noise (period P lattice cells), for textures.
static func vnoise_p(x: float, y: float, p: int, seed: int) -> float:
	var fx0 := floorf(x)
	var fy0 := floorf(y)
	var ix := int(fx0)
	var iy := int(fy0)
	var fx := x - fx0
	var fy := y - fy0
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var x0 := posmod(ix, p)
	var x1 := posmod(ix + 1, p)
	var y0 := posmod(iy, p)
	var y1 := posmod(iy + 1, p)
	var a := hash2(x0, y0, seed)
	var b := hash2(x1, y0, seed)
	var c := hash2(x0, y1, seed)
	var d := hash2(x1, y1, seed)
	return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy


static func fbm_p(x: float, y: float, p: int, oct: int, seed: int) -> float:
	var v := 0.0
	var a := 0.5
	var f := 1
	var norm := 0.0
	for k in oct:
		v += a * vnoise_p(x * f, y * f, p * f, seed + k * 13)
		norm += a
		a *= 0.5
		f *= 2
	return v / norm


## A FastNoiseLite that gives fbm-like values: 0.5 + 0.5 * get_noise_2d(x, z).
static func fast_fbm(seed: int, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_VALUE
	n.seed = seed & 0x7FFFFFFF
	n.frequency = 1.0
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
		n.fractal_lacunarity = 2.03
		n.fractal_gain = 0.5
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n


static func smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Seed of a track from its id (trackMesh.js analyseTrack), as an unsigned 32-bit value.
static func track_seed(id: String) -> int:
	var seed := 1234
	for ch in id:
		seed = (imul(seed, 31) + ch.unicode_at(0)) & M32
	return seed


## The web game's mulberry32 generator: Rng.new(seed).next() in 0..1.
class Rng:
	var a: int

	func _init(seed: int) -> void:
		a = seed & 0xFFFFFFFF

	func next() -> float:
		a = (a + 0x6d2b79f5) & 0xFFFFFFFF
		var t := ((a ^ (a >> 15)) * (1 | a)) & 0xFFFFFFFF
		t = ((t + (((t ^ (t >> 7)) * (61 | t)) & 0xFFFFFFFF)) & 0xFFFFFFFF) ^ t
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
