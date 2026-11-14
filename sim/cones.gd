class_name Cones
extends RefCounted
## cones.gd (v6.27.0): the traffic cones along the edges of a track without barriers
## (BuiltTrack.open_edges: every track with loose surfaces). Pure logic (no nodes): where they
## stand, which ones a car knocks over and the time it costs. The play modes keep one set a race
## (shared by every car on the road), the world (world/cone_field.gd) draws them and throws the
## knocked ones aside.
## ------------------------------------------------------------------
## A cone stands EDGE m beyond each road edge, every SPACING m on a straight and closer in corners
## (down to SPACING_TIGHT m at a 30 m radius), on the run-off's slope at that point. A car knocks
## one over when its capsule (Car: core segment, radius) comes within RADIUS of it while the car is
## not flying over it; a knocked cone stays down for the rest of the race. Each one costs PENALTY s
## (RaceState.penalize).
##
##   var cones := Cones.new(track)        (track.open_edges false: no cones)
##   cones.count() -> int;  cones.x / z / y (PackedFloat32Array), cones.side (+1 left, -1 right),
##   cones.sample (PackedInt32Array);  cones.down (PackedByteArray: 1 = knocked)
##   cones.hit(car) -> PackedInt32Array   the cones `car` knocked over in its last step
##   cones.reset()                        all standing again (a restart)

const EDGE: float = 0.45
const SPACING: float = 12.0
const SPACING_TIGHT: float = 5.0
const RADIUS: float = 0.25
const PENALTY: float = 0.5
## how many samples either side of the car's sample are looked at (the longest car with margin)
const WINDOW: int = 5

var x := PackedFloat32Array()
var z := PackedFloat32Array()
var y := PackedFloat32Array()
var side := PackedFloat32Array()
var sample := PackedInt32Array()
var down := PackedByteArray()
var _track: BuiltTrack
var _first := PackedInt32Array()   # per sample: the first cone at or after it (cones are in sample order)


func _init(track: BuiltTrack) -> void:
	_track = track
	if track == null or not track.open_edges:
		return
	var n: int = track.count
	var last: int = n if track.closed else n - 1
	for o in 2:
		var s: float = 1.0 if o == 0 else -1.0
		var since: float = SPACING # (a cone on the first sample)
		for i in last:
			var j: int = track.wrap(i + 2)
			var h: int = track.wrap(i - 2)
			var d: float = track.heading(j) - track.heading(h)
			d = atan2(sin(d), cos(d))
			var r: float = 4.0 * track.seg_len / maxf(absf(d), 1e-6) # radius of the road here
			var gap: float = clampf(SPACING_TIGHT + (SPACING - SPACING_TIGHT) * (r - 30.0) / 170.0, SPACING_TIGHT, SPACING)
			if since >= gap:
				since = 0.0
				_add(track, i, s)
			since += track.seg_len
	_sort()
	down.resize(x.size())
	down.fill(0)


func count() -> int:
	return x.size()


func reset() -> void:
	down.fill(0)


## The cones `car` knocked over in its last step (and marks them down).
func hit(car: Car) -> PackedInt32Array:
	var out := PackedInt32Array()
	if x.is_empty():
		return out
	var t := _track
	var P: CarSpec = car.spec
	var fx: float = sin(car.yaw)
	var fz: float = cos(car.yaw)
	var ax: float = car.x - fx * P.core
	var az: float = car.z - fz * P.core
	var ex: float = fx * 2.0 * P.core
	var ez: float = fz * 2.0 * P.core
	var ee: float = ex * ex + ez * ez
	var reach: float = P.radius + RADIUS
	var n: int = t.N if t.closed else t.count
	for k in range(-WINDOW, WINDOW + 1):
		var i: int = car.idx + k
		if t.closed:
			i = posmod(i, n)
		elif i < 0 or i >= n:
			continue
		var c: int = _first[i]
		while c < sample.size() and sample[c] == i:
			if down[c] == 0 and car.y - y[c] < 1.0:
				var u: float = ((x[c] - ax) * ex + (z[c] - az) * ez) / ee if ee > 0.0 else 0.0
				u = clampf(u, 0.0, 1.0)
				var qx: float = ax + ex * u - x[c]
				var qz: float = az + ez * u - z[c]
				if qx * qx + qz * qz < reach * reach:
					down[c] = 1
					out.append(c)
			c += 1
	return out


func _add(t: BuiltTrack, i: int, s: float) -> void:
	var lat: float = (t.hw[i] + EDGE) * s
	x.append(t.px[i] + t.nx[i] * lat)
	z.append(t.pz[i] + t.nz[i] * lat)
	var edge: float = t.py[i] - t.hw[i] * s * tan(t.bank[i])
	y.append(edge + (t.side_y[i] - edge) * Collision.off_slope(edge - t.side_y[i], EDGE))
	side.append(s)
	sample.append(i)


## Cones in sample order (both sides merged) and the index of the first one at each sample.
func _sort() -> void:
	var order: Array = range(x.size())
	order.sort_custom(func(a: int, b: int) -> bool: return sample[a] < sample[b] or (sample[a] == sample[b] and side[a] > side[b]))
	var nx := PackedFloat32Array()
	var nz := PackedFloat32Array()
	var ny := PackedFloat32Array()
	var ns := PackedFloat32Array()
	var nsm := PackedInt32Array()
	for k: int in order:
		nx.append(x[k])
		nz.append(z[k])
		ny.append(y[k])
		ns.append(side[k])
		nsm.append(sample[k])
	x = nx
	z = nz
	y = ny
	side = ns
	sample = nsm
	var n: int = _track.count
	_first.resize(n)
	var c: int = 0
	for i in n:
		while c < sample.size() and sample[c] < i:
			c += 1
		_first[i] = c
