class_name Collision
extends RefCounted
## collision.gd (port of web/src/physics/collision.js)
## ------------------------------------------------------------------
## Fast 2D queries against a built track:
##   - locate():          where a point is relative to the centre line
##                        (segment index, lateral offset, ground height, ...)
##   - build_wall_grid(): wall segments bucketed in a uniform grid
##   - raycast():         distance to the nearest wall along a ray
##                        (used by the AI distance sensors)
##   - collide_capsule(): car-shaped capsule against the wall segments
##                        (used by the car physics)
##
## The world is treated as 2.5D: walls are vertical, so all wall tests
## happen on the X/Z plane and height comes from the road surface.
##
## Coordinate conventions used across the project:
##   forward(yaw) = (sin yaw, cos yaw)   on the (x, z) plane
##   left(yaw)    = (cos yaw, -sin yaw)
##   A positive yaw change is a turn to the LEFT.
##
## locate() uses a *smooth* track frame. Between two samples i and j the
## centre point and the left normal are both interpolated linearly
## (C(t) = lerp(p_i, p_j, t), N(t) = lerp(n_i, n_j, t)) and a point P is
## mapped to (t, lat) with P = C(t) + lat * N(t). This is continuous across
## segment boundaries, so `lat`, the ground height on banked corners and the
## progress never jump. At lat = ±hw the mapping traces exactly the wall
## polylines built below.
##
## Thread safety (Godot port): nothing here writes to the track, so several
## cars may be stepped on one track from several threads. (The JS keeps a
## per-track "stamp" array to skip wall segments listed in more than one grid
## cell; collide_capsule does the same with each segment's cell range instead,
## which visits exactly the same segments in the same order.)

## How many segments either side of the hint locate() searches.
const SEARCH_WINDOW: int = 8
## cos of the normal change across one segment above which the segment counts as a kink.
const KINK_DOT: float = 0.5


## A point located on the track (the JS `out` object of locate()).
class Loc:
	## segment index (from sample idx to idx + 1)
	var idx: int = 0
	## 0..1 position along that segment
	var t: float = 0.0
	## unclamped t (open tracks: < 0 before the start, > 1 past the end)
	var t_raw: float = 0.0
	## idx + t, "local progress" in sample units
	var prog: float = 0.0
	## signed lateral offset from the centre line (+ = left)
	var lat: float = 0.0
	## unit left normal of the track at the point (smooth)
	var nx: float = 0.0
	var nz: float = 0.0
	## road surface height at the point (includes banking)
	var ground_y: float = 0.0
	## signed bank angle (rad) at the point
	var bank: float = 0.0
	## road half width at the point
	var hw: float = 0.0


## The deepest wall contact found by collide_capsule().
class Contact:
	var depth: float = 0.0
	## unit normal from the wall into the road
	var nx: float = 0.0
	var nz: float = 0.0
	## contact point on the capsule surface
	var px: float = 0.0
	var pz: float = 0.0
	## wall segment index
	var seg: int = 0


## Wall segments and the uniform grid that buckets them (build_wall_grid()).
class WallGrid:
	## 4 numbers per segment: ax, az, bx, bz (float32, as the JS)
	var segs: PackedFloat32Array
	## 2 per segment: unit normal pointing into the road
	var inward: PackedFloat64Array
	var cell: float = 12.0
	var min_x: float = 0.0
	var min_z: float = 0.0
	var cols: int = 0
	var rows: int = 0
	## 4 per segment: ax, az, bx - ax, bz - az (the fast form the queries use)
	var seg_d: PackedFloat64Array
	## segment ids of cell c are cell_segs[cell_start[c] .. cell_start[c + 1]]
	var cell_start: PackedInt32Array
	var cell_segs: PackedInt32Array
	## 2 per segment: the first grid column and row it is listed in (de-duplication)
	var seg_cell: PackedInt32Array

	## Segment ids listed in cell (col, row).
	func cell_list(col: int, row: int) -> PackedInt32Array:
		var ci: int = row * cols + col
		return cell_segs.slice(cell_start[ci], cell_start[ci + 1])


## Locate a point on the track, searching around a hint segment index.
## Searching locally (instead of the whole track) keeps it fast and stops the
## car from "snapping" to a different part of the track that happens to be
## close by in 2D. Fills `out` (see Loc) and returns it.
static func locate(track: BuiltTrack, x: float, z: float, hint: int, out: Loc) -> Loc:
	# Coarse: nearest straight segment in a window around the hint.
	var N: int = track.N
	var closed: bool = track.closed
	var px: PackedFloat32Array = track.px
	var pz: PackedFloat32Array = track.pz
	var seg_count: int = track.seg_count
	var best: float = INF
	var bi: int = 0
	for k in range(-SEARCH_WINDOW, SEARCH_WINDOW + 1):
		var i: int = hint + k
		if closed:
			i = posmod(i, N)
		elif i < 0 or i >= seg_count:
			continue
		var j: int = (i + 1) % N if closed else i + 1
		var ax: float = px[i]
		var az: float = pz[i]
		var ex: float = px[j] - ax
		var ez: float = pz[j] - az
		var t: float = ((x - ax) * ex + (z - az) * ez) / (ex * ex + ez * ez)
		t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
		var qx: float = ax + ex * t - x
		var qz: float = az + ez * t - z
		var d2: float = qx * qx + qz * qz
		if d2 < best:
			best = d2
			bi = i
	# Fine: smooth projection, walking to the neighbour segment if needed.
	return locate_near(track, x, z, bi, out)


## Smooth projection starting at segment `i`, walking forwards/backwards (at
## most a few segments) until the point projects inside a segment. O(1) when
## `i` is already right (the car physics calls this every sub-step with the
## last sub-step's segment). Fills `out` like locate().
static func locate_near(track: BuiltTrack, x: float, z: float, i: int, out: Loc) -> Loc:
	var N: int = track.N
	var closed: bool = track.closed
	var px: PackedFloat32Array = track.px
	var pz: PackedFloat32Array = track.pz
	var nx: PackedFloat32Array = track.nx
	var nz: PackedFloat32Array = track.nz
	var seg_count: int = track.seg_count
	if closed:
		i = posmod(i, N)
	else:
		i = 0 if i < 0 else (seg_count - 1 if i >= seg_count else i)

	var t: float = 0.0
	var dir: int = 0
	for iter in 8:
		# t = _smooth_t(track, x, z, i), inlined (this runs several times per car step)
		var j0: int = (i + 1) % N if closed else i + 1
		var wx: float = x - px[i]
		var wz: float = z - pz[i]
		var ex0: float = px[j0] - px[i]
		var ez0: float = pz[j0] - pz[i]
		if nx[i] * nx[j0] + nz[i] * nz[j0] < KINK_DOT:
			var ee: float = ex0 * ex0 + ez0 * ez0
			t = (wx * ex0 + wz * ez0) / (ee if ee != 0.0 else 1e-9)
		else:
			var tix: float = -nz[i]
			var tiz: float = nx[i]
			var dtx: float = -nz[j0] - tix
			var dtz: float = nx[j0] - tiz
			var a2: float = -(ex0 * dtx + ez0 * dtz)
			var a1: float = wx * dtx + wz * dtz - (ex0 * tix + ez0 * tiz)
			var a0: float = wx * tix + wz * tiz
			if absf(a2) < 1e-9 * absf(a1):
				t = -a0 / a1
			else:
				var disc: float = a1 * a1 - 4.0 * a2 * a0
				if disc < 0.0:
					t = -a0 / a1
				else:
					t = a0 / (-0.5 * (a1 + (-1.0 if a1 < 0.0 else 1.0) * sqrt(disc)))
		if t < 0.0:
			if not closed and i == 0:
				break
			if dir == 1:
				t = 0.0 # ping-pong between two segments: on the boundary
				break
			dir = -1
			i = (i - 1 + N) % N if closed else i - 1
		elif t > 1.0:
			if not closed and i == seg_count - 1:
				break
			if dir == -1:
				t = 1.0
				break
			dir = 1
			i = (i + 1) % N if closed else i + 1
		else:
			break

	var j: int = (i + 1) % N if closed else i + 1
	var t_raw: float = t
	var tc: float = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
	# For points beyond the ends of an open track, extrapolate along the end segment.
	var te: float = tc if closed else t_raw
	var cx: float = px[i] + (px[j] - px[i]) * te
	var cz: float = pz[i] + (pz[j] - pz[i]) * te
	var mx: float = nx[i] + (nx[j] - nx[i]) * tc
	var mz: float = nz[i] + (nz[j] - nz[i]) * tc
	if nx[i] * nx[j] + nz[i] * nz[j] < KINK_DOT:
		# kink: use the segment's own left normal (see _smooth_t)
		var ex: float = px[j] - px[i]
		var ez: float = pz[j] - pz[i]
		var el: float = sqrt(ex * ex + ez * ez)
		if el == 0.0:
			el = 1.0
		mx = ez / el
		mz = -ex / el
	var m2: float = mx * mx + mz * mz
	var lat: float = ((x - cx) * mx + (z - cz) * mz) / m2
	var inv: float = 1.0 / sqrt(m2)
	var bk: PackedFloat32Array = track.bank
	var bank_i: float = bk[i]
	var bank: float = bank_i + (bk[j] - bank_i) * tc
	var py: PackedFloat32Array = track.py
	var py_i: float = py[i]
	var cy: float = py_i + (py[j] - py_i) * tc
	var hw: PackedFloat32Array = track.hw
	var hw_i: float = hw[i]

	out.idx = i
	out.t = tc
	out.t_raw = t_raw
	out.prog = i + tc
	out.lat = lat
	out.nx = mx * inv
	out.nz = mz * inv
	out.bank = bank
	out.hw = hw_i + (hw[j] - hw_i) * tc
	# Positive bank (left-hand turn) raises the right edge (negative lat).
	out.ground_y = cy - lat * tan(bank)
	return out


## Parameter t of the smooth projection of (x, z) on segment i: solves
## (P - C(t)) · T(t) = 0 with T(t) = perp(N(t)), a quadratic in t.
static func _smooth_t(track: BuiltTrack, x: float, z: float, i: int) -> float:
	var px: PackedFloat32Array = track.px
	var pz: PackedFloat32Array = track.pz
	var nx: PackedFloat32Array = track.nx
	var nz: PackedFloat32Array = track.nz
	var j: int = (i + 1) % track.N if track.closed else i + 1
	var wx: float = x - px[i]
	var wz: float = z - pz[i]
	var ex: float = px[j] - px[i]
	var ez: float = pz[j] - pz[i]
	# A kink (the normal turns by more than 60° within one segment) would make the
	# smooth frame singular: fall back to a plain projection on the segment there.
	if nx[i] * nx[j] + nz[i] * nz[j] < KINK_DOT:
		var ee: float = ex * ex + ez * ez
		return (wx * ex + wz * ez) / (ee if ee != 0.0 else 1e-9)
	# tangent = perp(normal): normal (nx, nz) -> tangent (-nz, nx)
	var tix: float = -nz[i]
	var tiz: float = nx[i]
	var dtx: float = -nz[j] - tix
	var dtz: float = nx[j] - tiz
	var a2: float = -(ex * dtx + ez * dtz)
	var a1: float = wx * dtx + wz * dtz - (ex * tix + ez * tiz)
	var a0: float = wx * tix + wz * tiz
	if absf(a2) < 1e-9 * absf(a1):
		return -a0 / a1
	var disc: float = a1 * a1 - 4.0 * a2 * a0
	if disc < 0.0:
		return -a0 / a1
	var q: float = -0.5 * (a1 + (-1.0 if a1 < 0.0 else 1.0) * sqrt(disc))
	return a0 / q # the root that matches the linear solution when the normals are parallel


## Build the wall segments and a uniform grid that buckets them, so ray casts
## and car collisions only test walls in nearby cells.
static func build_wall_grid(track: BuiltTrack) -> WallGrid:
	var count: int = track.count
	var closed: bool = track.closed
	var px: PackedFloat32Array = track.px
	var pz: PackedFloat32Array = track.pz
	var nx: PackedFloat32Array = track.nx
	var nz: PackedFloat32Array = track.nz
	var hw: PackedFloat32Array = track.hw
	var segs: PackedFloat64Array = PackedFloat64Array()
	var inward: PackedFloat64Array = PackedFloat64Array()

	var last: int = count if closed else count - 1
	for i in last:
		var j: int = (i + 1) % count
		for side: float in [1.0, -1.0]:
			# edge(i, side) = centre + left normal × half width × side
			var ax: float = px[i] + nx[i] * hw[i] * side
			var az: float = pz[i] + nz[i] * hw[i] * side
			var bx: float = px[j] + nx[j] * hw[j] * side
			var bz: float = pz[j] + nz[j] * hw[j] * side
			segs.append_array([ax, az, bx, bz])
			# The road is on the right of the left wall (side +1) and on the left of the right wall.
			var dx: float = bx - ax
			var dz: float = bz - az
			var l: float = JsMath.hypot2(dx, dz)
			if l == 0.0:
				l = 1.0
			dx /= l
			dz /= l
			# left normal of the direction (dx, dz) is (dz, -dx)
			inward.append_array([-side * dz, side * dx])
	if not closed:
		# End caps so the sprint track is fully enclosed.
		for i: int in [0, count - 1]:
			segs.append_array([px[i] + nx[i] * hw[i], pz[i] + nz[i] * hw[i], px[i] + nx[i] * hw[i] * -1.0, pz[i] + nz[i] * hw[i] * -1.0])
			var s: float = 1.0 if i == 0 else -1.0 # inward = along the track at the start, backwards at the end
			inward.append_array([track.tx[i] * s, track.tz[i] * s])

	var g := WallGrid.new()
	var seg_arr: PackedFloat32Array = PackedFloat32Array()
	seg_arr.resize(segs.size())
	for k in segs.size():
		seg_arr[k] = segs[k] # float32, like new Float32Array(segs)
	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for k in range(0, seg_arr.size(), 2):
		min_x = minf(min_x, seg_arr[k])
		max_x = maxf(max_x, seg_arr[k])
		min_z = minf(min_z, seg_arr[k + 1])
		max_z = maxf(max_z, seg_arr[k + 1])
	var cell: float = 12.0
	min_x -= cell
	min_z -= cell
	max_x += cell
	max_z += cell
	var cols: int = int(ceil((max_x - min_x) / cell))
	var rows: int = int(ceil((max_z - min_z) / cell))
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(cols * rows)
	var n_seg: int = seg_arr.size() / 4
	var seg_cell: PackedInt32Array = PackedInt32Array()
	seg_cell.resize(n_seg * 2)
	for s in n_seg:
		var o: int = s * 4
		var c0: int = int(floor((minf(seg_arr[o], seg_arr[o + 2]) - min_x) / cell))
		var c1: int = int(floor((maxf(seg_arr[o], seg_arr[o + 2]) - min_x) / cell))
		var r0: int = int(floor((minf(seg_arr[o + 1], seg_arr[o + 3]) - min_z) / cell))
		var r1: int = int(floor((maxf(seg_arr[o + 1], seg_arr[o + 3]) - min_z) / cell))
		seg_cell[s * 2] = c0
		seg_cell[s * 2 + 1] = r0
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				buckets[r * cols + c].append(s)

	var seg_d: PackedFloat64Array = PackedFloat64Array()
	seg_d.resize(n_seg * 4)
	for k in n_seg:
		var o: int = k * 4
		seg_d[o] = seg_arr[o]
		seg_d[o + 1] = seg_arr[o + 1]
		seg_d[o + 2] = seg_arr[o + 2] - seg_arr[o]
		seg_d[o + 3] = seg_arr[o + 3] - seg_arr[o + 1]
	var cell_start: PackedInt32Array = PackedInt32Array()
	cell_start.resize(buckets.size() + 1)
	var cell_segs: PackedInt32Array = PackedInt32Array()
	var total: int = 0
	for c in buckets.size():
		cell_start[c] = total
		total += buckets[c].size()
		cell_segs.append_array(buckets[c])
	cell_start[buckets.size()] = total

	g.segs = seg_arr
	g.inward = inward
	g.cell = cell
	g.min_x = min_x
	g.min_z = min_z
	g.cols = cols
	g.rows = rows
	g.seg_d = seg_d
	g.cell_start = cell_start
	g.cell_segs = cell_segs
	g.seg_cell = seg_cell
	return g


## Cast a 2D ray against the track walls (grid DDA traversal).
## Returns the distance to the first wall hit, or max_dist if nothing is hit.
static func raycast(grid: WallGrid, ox: float, oz: float, dx: float, dz: float, max_dist: float) -> float:
	var cell: float = grid.cell
	var min_x: float = grid.min_x
	var min_z: float = grid.min_z
	var cols: int = grid.cols
	var rows: int = grid.rows
	var seg_d: PackedFloat64Array = grid.seg_d
	var cell_start: PackedInt32Array = grid.cell_start
	var cell_segs: PackedInt32Array = grid.cell_segs
	var cx: int = int(floor((ox - min_x) / cell))
	var cz: int = int(floor((oz - min_z) / cell))
	var step_x: int = 1 if dx > 0.0 else -1
	var step_z: int = 1 if dz > 0.0 else -1
	var t_delta_x: float = cell / absf(dx) if dx != 0.0 else INF
	var t_delta_z: float = cell / absf(dz) if dz != 0.0 else INF
	var t_max_x: float = ((cx + (1 if dx > 0.0 else 0)) * cell + min_x - ox) / dx if dx != 0.0 else INF
	var t_max_z: float = ((cz + (1 if dz > 0.0 else 0)) * cell + min_z - oz) / dz if dz != 0.0 else INF
	var best: float = max_dist

	while cx >= 0 and cz >= 0 and cx < cols and cz < rows:
		var ci: int = cz * cols + cx
		var end: int = cell_start[ci + 1]
		for k in range(cell_start[ci], end):
			var o: int = cell_segs[k] << 2
			var ex: float = seg_d[o + 2]
			var ez: float = seg_d[o + 3]
			var denom: float = dx * ez - dz * ex
			if denom > -1e-9 and denom < 1e-9:
				continue
			var wx: float = seg_d[o] - ox
			var wz: float = seg_d[o + 1] - oz
			var t: float = (wx * ez - wz * ex) / denom
			if t < 0.0 or t >= best:
				continue
			var s: float = (wx * dz - wz * dx) / denom
			if s >= 0.0 and s <= 1.0:
				best = t
		var t_next: float = t_max_x if t_max_x < t_max_z else t_max_z
		if best <= t_next or t_next > max_dist:
			break
		if t_max_x < t_max_z:
			cx += step_x
			t_max_x += t_delta_x
		else:
			cz += step_z
			t_max_z += t_delta_z
	return best


## Deepest contact between a capsule (core segment P0-P1, radius R) and the
## walls. Only walls whose grid cells overlap the capsule are tested.
##
## One-sided walls: each wall segment knows which side the road is on
## (grid.inward). If the capsule's core has crossed a wall line it is pushed
## back to the road side, not through. Cores more than `max_behind` metres
## behind a wall are ignored, so a wall of another part of the track that
## runs back-to-back with this one is never "hit" from behind.
##
## Fills `out` (Contact) and returns true if there is a contact (depth > 0).
static func collide_capsule(grid: WallGrid, p0x: float, p0z: float, p1x: float, p1z: float, R: float, out: Contact, max_behind: float = 1.6) -> bool:
	var cell: float = grid.cell
	var min_x: float = grid.min_x
	var min_z: float = grid.min_z
	var cols: int = grid.cols
	var rows: int = grid.rows
	var seg_d: PackedFloat64Array = grid.seg_d
	var cell_start: PackedInt32Array = grid.cell_start
	var cell_segs: PackedInt32Array = grid.cell_segs
	var seg_cell: PackedInt32Array = grid.seg_cell
	var inward: PackedFloat64Array = grid.inward
	var x0: float = minf(p0x, p1x) - R
	var x1: float = maxf(p0x, p1x) + R
	var z0: float = minf(p0z, p1z) - R
	var z1: float = maxf(p0z, p1z) + R
	var c0: int = maxi(0, int(floor((x0 - min_x) / cell)))
	var c1: int = mini(cols - 1, int(floor((x1 - min_x) / cell)))
	var r0: int = maxi(0, int(floor((z0 - min_z) / cell)))
	var r1: int = mini(rows - 1, int(floor((z1 - min_z) / cell)))
	var best_depth: float = 0.0
	var found: bool = false
	var ux: float = p1x - p0x
	var uz: float = p1z - p0z
	var uu: float = ux * ux + uz * uz
	if uu == 0.0:
		uu = 1e-9

	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var ci: int = r * cols + c
			var end: int = cell_start[ci + 1]
			for k in range(cell_start[ci], end):
				var s: int = cell_segs[k]
				# each segment once: in the first cell of the query that lists it
				if c != maxi(c0, seg_cell[s * 2]) or r != maxi(r0, seg_cell[s * 2 + 1]):
					continue
				var o: int = s * 4
				var ax: float = seg_d[o]
				var az: float = seg_d[o + 1]
				var ex: float = seg_d[o + 2]
				var ez: float = seg_d[o + 3]
				var bx: float = ax + ex
				var bz: float = az + ez
				# quick reject: segment bounding box vs capsule bounding box
				if (ax < x0 and bx < x0) or (ax > x1 and bx > x1) or (az < z0 and bz < z0) or (az > z1 and bz > z1):
					continue
				var mx: float = inward[s * 2]
				var mz: float = inward[s * 2 + 1]
				var ee: float = ex * ex + ez * ez
				if ee == 0.0:
					ee = 1e-9
				# signed distances of the core ends to the wall line (+ = road side)
				var s0: float = (p0x - ax) * mx + (p0z - az) * mz
				var s1: float = (p1x - ax) * mx + (p1z - az) * mz
				var depth: float
				var n_x: float
				var n_z: float
				var min_s: float = s0 if s0 < s1 else s1
				if min_s < 0.0:
					# Some of the core is behind the wall line: inside the wall's span?
					if min_s < -max_behind:
						continue
					var qx: float = p0x if s0 < s1 else p1x
					var qz: float = p0z if s0 < s1 else p1z
					# where along the wall does the crossing (or the deepest end) sit?
					var tc: float
					if s0 * s1 < 0.0:
						var f: float = s0 / (s0 - s1)
						tc = ((p0x + ux * f - ax) * ex + (p0z + uz * f - az) * ez) / ee
					else:
						tc = ((qx - ax) * ex + (qz - az) * ez) / ee
					if not (tc < 0.0 or tc > 1.0):
						depth = R - min_s
						if depth > best_depth:
							best_depth = depth
							found = true
							out.depth = depth
							out.nx = mx
							out.nz = mz
							out.px = qx - mx * R
							out.pz = qz - mz * R
							out.seg = s
						continue
					# beyond the wall's ends: treat as an ordinary distance test below
				# Closest points between the two segments (they don't cross here):
				# the minimum is at an endpoint of one of them.
				var bd: float = INF
				var bcx: float = 0.0
				var bcz: float = 0.0
				var bwx: float = 0.0
				var bwz: float = 0.0
				# core ends against the wall segment
				var t: float = ((p0x - ax) * ex + (p0z - az) * ez) / ee
				t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
				var wx: float = ax + ex * t
				var wz: float = az + ez * t
				var d: float = (p0x - wx) * (p0x - wx) + (p0z - wz) * (p0z - wz)
				if d < bd:
					bd = d; bcx = p0x; bcz = p0z; bwx = wx; bwz = wz
				t = ((p1x - ax) * ex + (p1z - az) * ez) / ee
				t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
				wx = ax + ex * t
				wz = az + ez * t
				d = (p1x - wx) * (p1x - wx) + (p1z - wz) * (p1z - wz)
				if d < bd:
					bd = d; bcx = p1x; bcz = p1z; bwx = wx; bwz = wz
				# wall ends against the core
				t = ((ax - p0x) * ux + (az - p0z) * uz) / uu
				t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
				var cx: float = p0x + ux * t
				var cz: float = p0z + uz * t
				d = (cx - ax) * (cx - ax) + (cz - az) * (cz - az)
				if d < bd:
					bd = d; bcx = cx; bcz = cz; bwx = ax; bwz = az
				t = ((bx - p0x) * ux + (bz - p0z) * uz) / uu
				t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
				cx = p0x + ux * t
				cz = p0z + uz * t
				d = (cx - bx) * (cx - bx) + (cz - bz) * (cz - bz)
				if d < bd:
					bd = d; bcx = cx; bcz = cz; bwx = bx; bwz = bz
				if bd >= R * R:
					continue
				var dist: float = sqrt(bd)
				if dist > 1e-6:
					n_x = (bcx - bwx) / dist
					n_z = (bcz - bwz) / dist
					# never push towards the back of the wall
					if n_x * mx + n_z * mz < 0.0:
						n_x = mx
						n_z = mz
				else:
					n_x = mx
					n_z = mz
				depth = R - dist
				if depth > best_depth:
					best_depth = depth
					found = true
					out.depth = depth
					out.nx = n_x
					out.nz = n_z
					out.px = bcx - n_x * R
					out.pz = bcz - n_z * R
					out.seg = s
	if not found:
		out.depth = 0.0
	return found
