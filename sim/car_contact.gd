class_name CarContact
extends RefCounted
## car_contact.gd (v6.13.0): solid cars. Car-to-car contacts for the field race (sim/field_race.gd).
## ------------------------------------------------------------------
## Only Race the field uses this: Drive, Race the AI (the see-through car), the ghosts, the medal
## sweep, the AI opponents' stored races and FleetSim training never call it, so they run exactly
## as before (nothing in sim/car.gd changed).
##
## Each car is the capsule its walls already use (sim/car.gd _walls): a core segment of ±spec.core
## along its heading with spec.radius around it, on the ground plane. After every car has made its
## 60 Hz step, each pair of solid cars that overlaps is
##   1. pushed apart along the contact normal by the overlap, shared by mass (the lighter car moves
##      more), at most MAX_PUSH a step each (a car squeezed against a wall is never shoved through it:
##      the wall pushes it back in its next step, and what is left is pushed in the next pass);
##   2. given an impulse at the contact point when they are closing: a little bounce (RESTITUTION),
##      friction along the contact (FRICTION × the normal impulse) and a yaw kick at SPIN of what a rigid
##      body would get (the tyres hold the rest; at most MAX_SPIN), then a little speed lost (SCRUB × the
##      impact).
## Purely planar: no vertical speed is added, so nothing is launched, and a car SKIP_DY higher than
## the other (over a kicker) flies over it. Nothing is applied when the cars move apart, so they never
## stick. The overlap is resolved in full every step, and a step moves two cars together by at most
## 3.1 m (both flat out head-on, 2 × 92 m/s), less than the thinnest two cars together (4 m: twice
## the two radii), so a contact is never missed (no tunnelling; tests/test_sim.gd checks it).
##
## Deterministic and symmetric: collide(a, b) and collide(b, a) do exactly the same thing, bit for bit
## (the pair is put in a fixed order by position first), and resolve() takes the pairs in index order.
##
##   CarContact.collide(a, b, hit = null) -> true when they touched (hit: what happened)
##   CarContact.resolve(cars, solid, hits = []) -> how many pairs touched (solid[i] false: car i is
##       not solid; hits gets one Hit per pair, with the cars' indices)
##   CarContact.overlap(a, b, margin = 0.0) -> how deep the capsules overlap (m, <= 0 apart)

const RESTITUTION: float = 0.2
const FRICTION: float = 0.25
const SPIN: float = 0.25
## The most yaw rate one contact gives a car (rad/s).
const MAX_SPIN: float = 1.5
const MAX_PUSH: float = 0.5
## Speed kept after an impact of v m/s: 1 - min(SCRUB_MAX, SCRUB × v / 10).
const SCRUB: float = 0.03
const SCRUB_MAX: float = 0.06
const SKIP_DY: float = 1.2
const EPS: float = 1e-9


## What one contact did.
class Hit:
	var a: int = -1
	var b: int = -1
	## overlap before the push (m)
	var depth: float = 0.0
	## normal from a to b, contact point
	var nx: float = 0.0
	var nz: float = 0.0
	var x: float = 0.0
	var z: float = 0.0
	## closing speed along the normal before the impulse (m/s, 0 when they were not closing)
	var speed: float = 0.0
	## the normal impulse (N s)
	var impulse: float = 0.0


## How deep the two cars' capsules overlap (m; zero or less: apart, by that much), plus `margin`.
static func overlap(a: Car, b: Car, margin: float = 0.0) -> float:
	var r := _closest(a, b)
	var dx: float = r[2] - r[0]
	var dz: float = r[3] - r[1]
	return a.spec.radius + b.spec.radius + margin - sqrt(dx * dx + dz * dz)


## The closest points of the two capsules' cores: [ax, az, bx, bz].
static func _closest(a: Car, b: Car) -> PackedFloat64Array:
	var afx: float = sin(a.yaw) * a.spec.core
	var afz: float = cos(a.yaw) * a.spec.core
	var bfx: float = sin(b.yaw) * b.spec.core
	var bfz: float = cos(b.yaw) * b.spec.core
	var p1x: float = a.x - afx
	var p1z: float = a.z - afz
	var p2x: float = b.x - bfx
	var p2z: float = b.z - bfz
	var d1x: float = 2.0 * afx
	var d1z: float = 2.0 * afz
	var d2x: float = 2.0 * bfx
	var d2z: float = 2.0 * bfz
	var rx: float = p1x - p2x
	var rz: float = p1z - p2z
	var aa: float = d1x * d1x + d1z * d1z
	var e: float = d2x * d2x + d2z * d2z
	var f: float = d2x * rx + d2z * rz
	var s: float = 0.0
	var t: float = 0.0
	if aa <= EPS and e <= EPS:
		pass
	elif aa <= EPS:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c: float = d1x * rx + d1z * rz
		if e <= EPS:
			s = clampf(-c / aa, 0.0, 1.0)
		else:
			var bb: float = d1x * d2x + d1z * d2z
			var den: float = aa * e - bb * bb
			s = clampf((bb * f - c * e) / den, 0.0, 1.0) if den > EPS else 0.0
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / aa, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / aa, 0.0, 1.0)
	return PackedFloat64Array([p1x + d1x * s, p1z + d1z * s, p2x + d2x * t, p2z + d2z * t])


## True when car `p` comes before car `q` in the fixed pair order (by position, then heading).
static func _first(p: Car, q: Car) -> bool:
	if p.x != q.x:
		return p.x < q.x
	if p.z != q.z:
		return p.z < q.z
	return p.yaw <= q.yaw


## One pair: push apart and the impulse when the capsules overlap. True when they touched.
static func collide(a: Car, b: Car, hit: Hit = null) -> bool:
	if absf(a.y - b.y) > SKIP_DY:
		return false
	if not _first(a, b):
		var swap := a
		a = b
		b = swap
		if hit != null:
			var k := hit.a
			hit.a = hit.b
			hit.b = k
	var cp := _closest(a, b)
	var dx: float = cp[2] - cp[0]
	var dz: float = cp[3] - cp[1]
	var ra: float = a.spec.radius
	var rb: float = b.spec.radius
	var d2: float = dx * dx + dz * dz
	var reach: float = ra + rb
	if d2 >= reach * reach:
		return false
	var d: float = sqrt(d2)
	var nx: float
	var nz: float
	if d > 1e-6:
		nx = dx / d
		nz = dz / d
	else:
		# the cores cross (only in a head-on of two fast cars): apart along the line between the centres
		var cx: float = b.x - a.x
		var cz: float = b.z - a.z
		var cl: float = sqrt(cx * cx + cz * cz)
		if cl > 1e-6:
			nx = cx / cl
			nz = cz / cl
		else:
			nx = cos(a.yaw) # (one exactly on the other: a's left)
			nz = -sin(a.yaw)
	var depth: float = reach - d
	# the contact point: half way between the two surfaces
	var px: float = (cp[0] + nx * ra + cp[2] - nx * rb) * 0.5
	var pz: float = (cp[1] + nz * ra + cp[3] - nz * rb) * 0.5
	var ma: float = a.spec.mass
	var mb: float = b.spec.mass
	var ia: float = a.spec.inertia / SPIN
	var ib: float = b.spec.inertia / SPIN
	# 1. push apart, shared by mass
	var share_a: float = minf(MAX_PUSH, depth * mb / (ma + mb))
	var share_b: float = minf(MAX_PUSH, depth * ma / (ma + mb))
	a.x -= nx * share_a
	a.z -= nz * share_a
	b.x += nx * share_b
	b.z += nz * share_b
	# 2. the impulse at the contact point (relative to each centre, after the push)
	var rax: float = px - a.x
	var raz: float = pz - a.z
	var rbx: float = px - b.x
	var rbz: float = pz - b.z
	# a point at r on a car turning at yaw_rate w moves at w × (rz, -rx) (+ yaw = left)
	var vax: float = a.vx + a.yaw_rate * raz
	var vaz: float = a.vz - a.yaw_rate * rax
	var vbx: float = b.vx + b.yaw_rate * rbz
	var vbz: float = b.vz - b.yaw_rate * rbx
	var rvx: float = vbx - vax
	var rvz: float = vbz - vaz
	var vn: float = rvx * nx + rvz * nz
	var jn: float = 0.0
	if vn < 0.0:
		var can: float = raz * nx - rax * nz
		var cbn: float = rbz * nx - rbx * nz
		var k: float = 1.0 / ma + 1.0 / mb + can * can / ia + cbn * cbn / ib
		jn = -(1.0 + RESTITUTION) * vn / k
		# friction along the contact, at most FRICTION × the normal impulse
		var tx: float = -nz
		var tz: float = nx
		var vt: float = rvx * tx + rvz * tz
		var cat: float = raz * tx - rax * tz
		var cbt: float = rbz * tx - rbx * tz
		var kt: float = 1.0 / ma + 1.0 / mb + cat * cat / ia + cbt * cbt / ib
		var jt: float = clampf(-vt / kt, -FRICTION * jn, FRICTION * jn)
		var jx: float = nx * jn + tx * jt
		var jz: float = nz * jn + tz * jt
		a.vx -= jx / ma
		a.vz -= jz / ma
		b.vx += jx / mb
		b.vz += jz / mb
		a.yaw_rate -= clampf((raz * jx - rax * jz) / ia, -MAX_SPIN, MAX_SPIN)
		b.yaw_rate += clampf((rbz * jx - rbx * jz) / ib, -MAX_SPIN, MAX_SPIN)
		# and a little speed lost by both
		var keep: float = 1.0 - minf(SCRUB_MAX, SCRUB * -vn / 10.0)
		a.vx *= keep
		a.vz *= keep
		b.vx *= keep
		b.vz *= keep
	_refresh(a)
	_refresh(b)
	if hit != null:
		hit.depth = depth
		hit.nx = nx
		hit.nz = nz
		hit.x = px
		hit.z = pz
		hit.speed = maxf(0.0, -vn)
		hit.impulse = jn
	return true


## The speeds the HUD, the sounds and the AI's sensors read, after the velocity changed.
static func _refresh(c: Car) -> void:
	var fx: float = sin(c.yaw)
	var fz: float = cos(c.yaw)
	c.speed = sqrt(c.vx * c.vx + c.vz * c.vz)
	c.forward_speed = c.vx * fx + c.vz * fz
	c.side_speed = c.vx * fz - c.vz * fx


## Every pair of solid cars (solid[i] true), in index order. Returns how many pairs touched; each
## contact is appended to `hits` (a Hit with the two indices) when it is given.
static func resolve(cars: Array, solid: Array, hits: Variant = null) -> int:
	var n: int = cars.size()
	var touched: int = 0
	var reach_max: float = 0.0
	for c: Car in cars:
		reach_max = maxf(reach_max, c.spec.half_length)
	var far: float = 2.0 * reach_max + 0.5
	for i in n:
		if not bool(solid[i]):
			continue
		var a: Car = cars[i]
		for j in range(i + 1, n):
			if not bool(solid[j]):
				continue
			var b: Car = cars[j]
			if absf(a.x - b.x) > far or absf(a.z - b.z) > far:
				continue
			var h: Hit = Hit.new() if hits is Array else null
			if h != null:
				h.a = i
				h.b = j
			if collide(a, b, h):
				touched += 1
				if h != null:
					(hits as Array).append(h)
	return touched
