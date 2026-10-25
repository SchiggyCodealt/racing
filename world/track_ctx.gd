## track_ctx.gd
## ------------------------------------------------------------------
## Track analysis of trackMesh.js (analyseTrack, planGrandstand, planCoast,
## coastEnvelope, planLighthouse): per-sample helpers shared by all the
## builders of the track mesh (world/track_mesh.gd and friends).
##
##   kappa       signed curvature (+ = left turn), 1/m
##   G           terrain level next to the road (never above the lowest road edge)
##   corner      1 on corners that get curbs (radius under ~150 m, short runs removed)
##   seed        per-track seed (the JS seed's 32 bits)
##   pads        flat pads reserved for the grandstand and the lighthouse
##   coast       seaside only: the side of the sea and its shoreline envelope
extends RefCounted

const VNoise = preload("res://world/noise.gd")
const TrackCtx = preload("res://world/track_ctx.gd")

const BARRIER_H := 1.1   # barrier height (m)
const BARRIER_W := 0.66  # barrier footprint beyond the road edge (m)
const ZONE := 12.0       # the terrain stays under the road up to this far beyond the edge (m)

var track: BuiltTrack
var theme: Dictionary
var segs := 0
var count := 0
var closed := true
var tan_b := PackedFloat32Array()
var kappa := PackedFloat32Array()
var G := PackedFloat32Array()
var corner := PackedByteArray()
var seed := 0
var gate_samples := PackedInt32Array()
## [{kind, cx, cz, y, r, pts: PackedVector2Array, (grandstand) ax, az, ox, oz, L, D}]
var pads: Array[Dictionary] = []
## seaside: {level, water, deep, shallow, sand (theme.sea), dx, dz (towards the sea), env: Envelope, off}
var coast: Dictionary = {}
var has_coast := false
## the terrain (world/track_terrain.gd), set once built
var terrain: RefCounted = null
var scenery_count := 0


## Shoreline envelope: outermost road edge towards (dx, dz) as a function of the position across it.
class Envelope:
	var u0 := 0.0
	var bin := 20.0
	var n := 2
	var env := PackedFloat32Array()

	func at(u: float) -> float:
		var f := clampf((u - u0) / bin, 0.0, float(n - 1))
		var b := mini(n - 2, int(floorf(f)))
		return env[b] + (env[b + 1] - env[b]) * (f - b)


static func analyse(p_track: BuiltTrack, p_theme: Dictionary) -> TrackCtx:
	var c := TrackCtx.new()
	c.track = p_track
	c.theme = p_theme
	c.count = p_track.count
	c.closed = p_track.closed
	c.segs = c.count if c.closed else c.count - 1
	var n := c.count
	c.tan_b.resize(n)
	for i in n:
		c.tan_b[i] = tan(p_track.bank[i])

	# Signed curvature (+ = left turn), 1/m.
	c.kappa.resize(n)
	for i in n:
		var a := c.wrap(i - 2)
		var b := c.wrap(i + 2)
		var m := 4 if c.closed else b - a
		if m <= 0:
			continue
		var d := p_track.heading(b) - p_track.heading(a)
		d = atan2(sin(d), cos(d))
		c.kappa[i] = d / (m * p_track.seg_len)

	# Lowest road edge and the terrain level next to the road. erode+blur with
	# the same radius guarantees G[i] <= low[i] (terrain never above the road).
	var low := PackedFloat32Array()
	low.resize(n)
	for i in n:
		low[i] = p_track.py[i] - p_track.hw[i] * absf(c.tan_b[i])
	c.G = _blur(_erode(low, 30, c.closed), 30, c.closed)
	for i in n:
		c.G[i] -= 0.35

	# Corners get curbs: radius under ~150 m, short runs removed.
	c.corner.resize(n)
	for i in n:
		c.corner[i] = 1 if absf(c.kappa[i]) > 1.0 / 150.0 else 0
	_dilate_mask(c.corner, 2, c.closed)
	_remove_short_runs(c.corner, 6)

	c.seed = VNoise.track_seed(p_track.id)
	if c.closed:
		c.gate_samples.append(0)
	else:
		c.gate_samples.append(p_track.start_line)
		c.gate_samples.append(p_track.finish_idx)
	c.gate_samples.append_array(p_track.cp_samples)
	c._plan_grandstand()
	if p_theme.has("sea"):
		c._plan_coast()
	return c


func wrap(i: int) -> int:
	if closed:
		return posmod(i, count)
	return clampi(i, 0, count - 1)


## Road surface height at sample i, lat metres left of the centre line.
func surf_y(i: int, lat: float) -> float:
	return track.py[i] - lat * tan_b[i]


## Height of the road edge on side s (+1 left, -1 right).
func edge_y(i: int, s: float) -> float:
	return track.py[i] - s * track.hw[i] * tan_b[i]


## Point on the road surface at sample i, lat metres left of the centre, dy above it.
func P(i: int, lat: float, dy := 0.0) -> Vector3:
	return Vector3(track.px[i] + track.nx[i] * lat, surf_y(i, lat) + dy, track.pz[i] + track.nz[i] * lat)


## True when sample i is within r samples of a gate.
func near_gate(i: int, r: int) -> bool:
	for g in gate_samples:
		var d := absi(g - i)
		if closed:
			d = mini(d, count - d)
		if d <= r:
			return true
	return false


## The pad of a kind ({} when there is none).
func pad(kind: String) -> Dictionary:
	for p in pads:
		if p["kind"] == kind:
			return p
	return {}


## Find a free spot for the grandstand next to the start; reserves a flat pad.
func _plan_grandstand() -> void:
	var t := track
	var anchor := 0 if closed else mini(count - 1, t.start_idx + 12)
	var L := 40.0
	var D := 13.0
	var gap := 5.0
	for s: float in [-1.0, 1.0]:
		var off := s * (t.hw[anchor] + BARRIER_W + gap + D / 2.0)
		var cx := t.px[anchor] + t.nx[anchor] * off
		var cz := t.pz[anchor] + t.nz[anchor] * off
		var ax := t.tx[anchor]
		var az := t.tz[anchor]
		var ox := t.nx[anchor] * s
		var oz := t.nz[anchor] * s
		var ok := true
		var a := -1.0
		while a <= 1.0 and ok:
			var b := -1.0
			while b <= 1.0 and ok:
				var qx := cx + ax * a * (L / 2.0 + 4.0) + ox * b * (D / 2.0 + 2.0)
				var qz := cz + az * a * (L / 2.0 + 4.0) + oz * b * (D / 2.0 + 2.0)
				for j in count:
					var dx := t.px[j] - qx
					var dz := t.pz[j] - qz
					var r := t.hw[j] + 3.5
					if dx * dx + dz * dz < r * r:
						ok = false
						break
				b += 0.5
			a += 0.25
		if not ok:
			continue
		var pts := PackedVector2Array()
		var q := -L / 2.0
		while q <= L / 2.0:
			pts.append(Vector2(cx + ax * q, cz + az * q))
			q += 5.0
		pads.append({"kind": "grandstand", "cx": cx, "cz": cz, "ax": ax, "az": az, "ox": ox, "oz": oz, "L": L, "D": D,
			"y": G[anchor], "r": D / 2.0 + 2.0, "pts": pts})
		return


## Seaside themes: put the sea on the side of the track that runs along it
## most (one of 16 directions), with the shoreline following the outermost
## parts of the track on that side, and reserve a pad for the lighthouse.
func _plan_coast() -> void:
	var t := track
	var best_along := -1
	var best_dx := 0.0
	var best_dz := 1.0
	var best_env: Envelope = null
	for k in 16:
		var a := float(k) / 16.0 * TAU
		var dx := sin(a)
		var dz := cos(a)
		var env := coast_envelope(t, dx, dz)
		var along := 0  # samples of road within 30 m of the coast-side envelope
		for i in count:
			if t.px[i] * dx + t.pz[i] * dz + t.hw[i] > env.at(t.pz[i] * dx - t.px[i] * dz) - 30.0:
				along += 1
		if along > best_along:
			best_along = along
			best_dx = dx
			best_dz = dz
			best_env = env
	coast = (theme["sea"] as Dictionary).duplicate()
	coast["dx"] = best_dx
	coast["dz"] = best_dz
	coast["env"] = best_env
	coast["off"] = 42.0
	has_coast = true
	_plan_lighthouse()


## Outermost road edge towards (dx, dz) as a function of the position across it, widened and smoothed.
static func coast_envelope(t: BuiltTrack, dx: float, dz: float, bin := 20.0, reach := 140.0) -> Envelope:
	var n_s := t.count
	var U := PackedFloat32Array()
	var Q := PackedFloat32Array()
	U.resize(n_s)
	Q.resize(n_s)
	var u0 := INF
	var u1 := -INF
	for i in n_s:
		U[i] = t.pz[i] * dx - t.px[i] * dz
		Q[i] = t.px[i] * dx + t.pz[i] * dz + t.hw[i]
		u0 = minf(u0, U[i])
		u1 = maxf(u1, U[i])
	var n := maxi(2, ceili((u1 - u0) / bin) + 1)
	var mx := PackedFloat32Array()
	mx.resize(n)
	mx.fill(-1e9)
	for i in n_s:
		var b := roundi((U[i] - u0) / bin)
		if Q[i] > mx[b]:
			mx[b] = Q[i]
	# dilate (the shore never cuts in between two parts of the track), then smooth over half that reach
	var r := roundi(reach / bin)
	var r2 := maxi(1, roundi(r / 2.0))
	var dil := PackedFloat32Array()
	dil.resize(n)
	var e := Envelope.new()
	e.env.resize(n)
	for b in n:
		var m := -1e9
		for k in range(maxi(0, b - r), mini(n - 1, b + r) + 1):
			m = maxf(m, mx[k])
		dil[b] = m
	for b in n:
		var sum := 0.0
		for k in range(-r2, r2 + 1):
			sum += dil[clampi(b + k, 0, n - 1)]
		e.env[b] = sum / (2 * r2 + 1)
	e.u0 = u0
	e.bin = bin
	e.n = n
	return e


## A flat pad for the lighthouse on the shore, seaward of the outermost road (away from the gates).
func _plan_lighthouse() -> void:
	var t := track
	var dx: float = coast["dx"]
	var dz: float = coast["dz"]
	var order: Array[int] = []
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		order.append(i)
		out[i] = t.px[i] * dx + t.pz[i] * dz + t.hw[i]
	order.sort_custom(func(a: int, b: int) -> bool: return out[a] > out[b] or (out[a] == out[b] and a < b))
	for oi in mini(count, 600):
		var i := order[oi]
		if near_gate(i, 12):
			continue
		var off := t.hw[i] + BARRIER_W + 34.0
		var cx := t.px[i] + dx * off
		var cz := t.pz[i] + dz * off
		var ok := true
		var j := 0
		while j < count and ok:
			var r := t.hw[j] + 22.0
			if (t.px[j] - cx) * (t.px[j] - cx) + (t.pz[j] - cz) * (t.pz[j] - cz) < r * r:
				ok = false
			j += 2
		if not ok:
			continue
		pads.append({"kind": "lighthouse", "cx": cx, "cz": cz, "y": G[i], "r": 9.0, "pts": PackedVector2Array([Vector2(cx, cz)])})
		return


# ---- small array helpers (trackMesh.js erode, blur, dilateMask, removeShortRuns) ----

static func _erode(a: PackedFloat32Array, r: int, cl: bool) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var m := INF
		for k in range(-r, r + 1):
			var j := i + k
			if cl:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			if a[j] < m:
				m = a[j]
		out[i] = m
	return out


static func _blur(a: PackedFloat32Array, r: int, cl: bool) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := 0.0
		var c := 0
		for k in range(-r, r + 1):
			var j := i + k
			if cl:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			s += a[j]
			c += 1
		out[i] = s / c
	return out


static func _dilate_mask(m: PackedByteArray, r: int, cl: bool) -> void:
	var n := m.size()
	var src := m.duplicate()
	for i in n:
		if src[i]:
			continue
		for k in range(-r, r + 1):
			var j := i + k
			if cl:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			if src[j]:
				m[i] = 1
				break


static func _remove_short_runs(m: PackedByteArray, min_len: int) -> void:
	var n := m.size()
	var i := 0
	while i < n:
		if not m[i]:
			i += 1
			continue
		var j := i
		while j < n and m[j]:
			j += 1
		if j - i < min_len and not (i == 0 or j == n):
			for k in range(i, j):
				m[k] = 0
		i = j
