## car_shapes.gd
## ------------------------------------------------------------------
## The four car bodies (carMesh.js SHAPES and its procedural geometry):
## one detailed model with different proportions and parts per car.
## Every part is laid out in the racer's frame and then stretched by warp():
## x * width, y * height + lift, z * front (z > 0) or rear (z < 0).
## Only the drawing changes: every car has the racer's collision capsule.
##
## Car frame: x = left, y = up, z = forward; the origin is on the road
## surface between the axles. Geometry is returned as Geo (world/geo.gd).
##
##   front, rear, width, height  stretch factors; lift (m) raises the body off the wheels
##   track     wheel x as a share of the stretched racer's
##   wheels    [front radius, front width, rear radius, rear width] (m)
##   haunch    rear fender width factor (fat rear tyres)
##   glass     the glass (loft stations [z, x, y, w, h, n]); mirror: [x, y, z] of the door mirrors
##   stripes   x of each livery stripe (stripeW half width; stripeAccent: accent colour, else
##             white on dark paint and dark on light paint)
##   exhausts  tail pipes [x, y, z of the pipe end, radius]: the nitro flames come out of them
##   rain      the rain light [x, y, z]
##   parts     extra parts, one material each (paint, accent, carbon, glass or head):
##             loft | box [sx, sy, sz] | wing [span, chord, thickness] | hoop [radius, tube] |
##             lamp [radius, depth] | fin; placed at `at` after a tilt rx about x;
##             sym: mirrored to -x as well; flat: left out of the side view (profile)
extends RefCounted

const Geo = preload("res://world/geo.gd")

## Wheels of the racer: [x, z, radius, width, front]
const WHEELS := [
	[0.86, 1.45, 0.37, 0.3, true], [-0.86, 1.45, 0.37, 0.3, true],
	[0.86, -1.42, 0.4, 0.36, false], [-0.86, -1.42, 0.4, 0.36, false],
]

## The racer's engine-cover fin, outline in (z, y).
const FIN := [[-0.9, 0.95], [-2.05, 1.12], [-2.15, 0.7], [-0.9, 0.7]]


## A loft station: [z, x, y, w, h, n] (w, h half sizes, n superellipse exponent).
static func ST(z: float, x: float, y: float, w: float, h: float, n := 5.0) -> Array:
	return [z, x, y, w, h, n]


## The racer's glass canopy (also drawn by the AI fleet).
static func canopy_stations() -> Array:
	return [ST(-1.25, 0, 0.74, 0.22, 0.06, 3), ST(-0.95, 0, 0.8, 0.36, 0.16, 3), ST(-0.5, 0, 0.84, 0.42, 0.24, 3),
		ST(0.1, 0, 0.84, 0.42, 0.24, 3), ST(0.6, 0, 0.78, 0.36, 0.16, 3), ST(0.95, 0, 0.7, 0.18, 0.04, 3)]


static var _shapes: Dictionary = {}


static func shapes() -> Dictionary:
	if not _shapes.is_empty():
		return _shapes
	_shapes = {
		# the v3 sports car exactly as it was: low wedge, bubble canopy, rear wing on swan necks, fin
		"racer": {
			"front": 1.0, "rear": 1.0, "width": 1.0, "height": 1.0, "lift": 0.0, "track": 1.0, "haunch": 1.0,
			"wheels": [0.37, 0.3, 0.4, 0.36],
			"glass": canopy_stations(), "mirror": [0.64, 0.85, 0.46],
			"stripes": [0.0], "stripeW": 0.15, "stripeAccent": false,
			"exhausts": [[0.22, 0.38, -2.42, 0.05], [-0.22, 0.38, -2.42, 0.05]],
			"rain": [0.0, 0.98, -2.24],
			"parts": [
				{"mat": "carbon", "wing": [1.9, 0.5, 0.09], "at": [0, 1.06, -1.88]},
				{"mat": "carbon", "wing": [1.86, 0.22, 0.05], "at": [0, 1.2, -2.26]},
				{"mat": "carbon", "box": [0.04, 0.42, 0.14], "at": [0.3, 0.88, -1.95], "sym": true}, # wing pylons
				{"mat": "paint", "fin": true},
				{"mat": "paint", "box": [0.035, 0.42, 0.62], "at": [0.97, 1.08, -2.12], "sym": true}, # wing end plates
			],
		},
		# small, short, low roadster: open cockpit with a wraparound screen, roll hoops, ducktail lip, narrow track
		"kestrel": {
			"front": 0.88, "rear": 0.86, "width": 0.94, "height": 0.94, "lift": -0.01, "track": 0.97, "haunch": 1.0,
			"wheels": [0.34, 0.26, 0.355, 0.29],
			"glass": [ST(0.26, 0, 0.8, 0.44, 0.08, 3), ST(0.32, 0, 0.8, 0.5, 0.11, 3), ST(0.45, 0, 0.77, 0.5, 0.09, 3),
				ST(0.56, 0, 0.73, 0.48, 0.05, 3), ST(0.66, 0, 0.69, 0.42, 0.015, 3)],
			"mirror": [0.6, 0.78, 0.5],
			"stripes": [0.0], "stripeW": 0.13, "stripeAccent": true,
			"exhausts": [[0.1, 0.34, -2.42, 0.045], [-0.1, 0.34, -2.42, 0.045]],
			"rain": [0.0, 0.74, -2.37],
			"parts": [
				# open cockpit (a dark well in the deck), two headrest fairings and roll hoops behind the seats
				{"mat": "carbon", "flat": true, "loft": [ST(-0.85, 0, 0.79, 0.3, 0.03, 4), ST(-0.6, 0, 0.8, 0.42, 0.035, 4),
					ST(-0.1, 0, 0.765, 0.43, 0.035, 4), ST(0.22, 0, 0.73, 0.36, 0.03, 4)]},
				{"mat": "paint", "sym": true, "loft": [ST(-1.85, 0.22, 0.76, 0.04, 0.02, 3), ST(-1.35, 0.22, 0.78, 0.1, 0.07, 3),
					ST(-0.85, 0.22, 0.8, 0.13, 0.13, 3), ST(-0.66, 0.22, 0.8, 0.12, 0.14, 3)]},
				{"mat": "accent", "hoop": [0.13, 0.022], "at": [0.22, 0.86, -0.6], "sym": true},
				{"mat": "accent", "wing": [1.36, 0.2, 0.045], "at": [0, 0.77, -2.12], "rx": 0.3}, # ducktail lip
			],
		},
		# long, wide grand tourer: cabin set back (long bonnet), fat rear tyres, big wing, splitter, four pipes
		"thunder": {
			"front": 1.06, "rear": 1.02, "width": 1.03, "height": 0.97, "lift": 0.0, "track": 1.0, "haunch": 1.08,
			"wheels": [0.38, 0.32, 0.42, 0.46],
			"glass": [ST(-1.85, 0, 0.75, 0.2, 0.05, 3), ST(-1.5, 0, 0.79, 0.34, 0.12, 3), ST(-0.95, 0, 0.83, 0.42, 0.2, 3),
				ST(-0.3, 0, 0.84, 0.43, 0.22, 3), ST(0.2, 0, 0.78, 0.38, 0.16, 3), ST(0.55, 0, 0.7, 0.2, 0.04, 3)],
			"mirror": [0.62, 0.84, 0.12],
			"stripes": [0.14, -0.14], "stripeW": 0.055, "stripeAccent": true,
			"exhausts": [[0.16, 0.42, -2.42, 0.048], [0.3, 0.42, -2.42, 0.048], [-0.16, 0.42, -2.42, 0.048], [-0.3, 0.42, -2.42, 0.048]],
			"rain": [0.0, 0.74, -2.37],
			"parts": [
				{"mat": "carbon", "wing": [2.0, 0.6, 0.1], "at": [0, 1.2, -1.84]},
				{"mat": "carbon", "wing": [1.96, 0.26, 0.05], "at": [0, 1.36, -2.26], "rx": 0.2},
				{"mat": "carbon", "box": [0.045, 0.56, 0.18], "at": [0.42, 0.95, -1.98], "sym": true},
				{"mat": "accent", "box": [0.04, 0.38, 0.6], "at": [1.02, 1.24, -2.08], "sym": true}, # wing end plates
				{"mat": "carbon", "box": [1.95, 0.035, 0.3], "at": [0, 0.13, 2.35]},            # splitter
				{"mat": "carbon", "box": [0.04, 0.12, 0.3], "at": [0.94, 0.3, 2.16], "sym": true}, # dive planes
			],
		},
		# tall rally hatchback: raised ride, boxy greenhouse with a roof, scoop, roof spoiler, light pod, mud flaps
		"drifter": {
			"front": 0.9, "rear": 0.88, "width": 0.97, "height": 1.0, "lift": 0.09, "track": 1.0, "haunch": 1.0,
			"wheels": [0.37, 0.27, 0.37, 0.27],
			"glass": [ST(-2.14, 0, 0.8, 0.48, 0.04, 4), ST(-1.95, 0, 1.02, 0.56, 0.24, 4), ST(-1.4, 0, 1.02, 0.6, 0.3, 4),
				ST(-0.4, 0, 1.02, 0.6, 0.3, 4), ST(0.2, 0, 1.0, 0.58, 0.28, 4), ST(0.85, 0, 0.74, 0.46, 0.04, 4)],
			"mirror": [0.68, 0.98, 0.5],
			"stripes": [0.0], "stripeW": 0.12, "stripeAccent": true,
			"exhausts": [[-0.55, 0.3, -2.42, 0.065]],
			"rain": [0.0, 0.74, -2.37],
			"parts": [
				{"mat": "paint", "loft": [ST(-1.95, 0, 1.27, 0.52, 0.02, 4), ST(-1.8, 0, 1.31, 0.6, 0.035, 4), ST(-0.4, 0, 1.33, 0.61, 0.035, 4),
					ST(0.1, 0, 1.3, 0.59, 0.03, 4), ST(0.22, 0, 1.28, 0.5, 0.01, 4)]}, # roof
				{"mat": "accent", "loft": [ST(-0.55, 0, 1.36, 0.12, 0.02, 4), ST(-0.3, 0, 1.38, 0.16, 0.05, 4), ST(0.0, 0, 1.39, 0.17, 0.06, 4),
					ST(0.08, 0, 1.385, 0.16, 0.055, 4)]}, # roof scoop
				{"mat": "paint", "box": [0.05, 0.56, 0.3], "at": [0.6, 1.02, -1.62], "sym": true}, # C-pillars ...
				{"mat": "paint", "box": [0.05, 0.56, 0.1], "at": [0.6, 1.02, -0.62], "sym": true}, # ... and B-pillars
				{"mat": "accent", "wing": [1.24, 0.34, 0.05], "at": [0, 1.33, -1.72], "rx": 0.15}, # roof spoiler
				{"mat": "paint", "box": [0.03, 0.14, 0.36], "at": [0.62, 1.31, -1.9], "sym": true},
				{"mat": "carbon", "box": [1.12, 0.12, 0.07], "at": [0, 0.56, 1.72]},              # light pod on the bonnet
				{"mat": "head", "lamp": [0.075, 0.05], "at": [0.17, 0.56, 1.765], "sym": true},
				{"mat": "head", "lamp": [0.075, 0.05], "at": [0.43, 0.56, 1.765], "sym": true},
				{"mat": "accent", "box": [0.3, 0.26, 0.025], "at": [0.85, 0.2, 0.92], "sym": true},  # mud flaps
				{"mat": "accent", "box": [0.3, 0.26, 0.025], "at": [0.85, 0.2, -1.95], "sym": true},
			],
		},
	}
	return _shapes


## The shape of car `id` (unknown ids: the racer's).
static func shape_of(id: String) -> Dictionary:
	var s := shapes()
	return s.get(id, s["racer"])


static func is_racer_frame(s: Dictionary) -> bool:
	return s["front"] == 1.0 and s["rear"] == 1.0 and s["width"] == 1.0 and s["height"] == 1.0 and s["lift"] == 0.0


## Stretch a geometry laid out in the racer's frame onto shape `s` (in place).
static func warp(g: Geo, s: Dictionary) -> Geo:
	if is_racer_frame(s):
		return g
	var w: float = s["width"]
	var h: float = s["height"]
	var lift: float = s["lift"]
	var fr: float = s["front"]
	var re: float = s["rear"]
	for k in g.pos.size():
		var p := g.pos[k]
		g.pos[k] = Vector3(p.x * w, lift + p.y * h, p.z * (fr if p.z > 0.0 else re))
	g.compute_normals()
	return g


## A point of the racer's frame on shape `s` (as warp).
static func warp_point(s: Dictionary, x: float, y: float, z: float) -> Vector3:
	return Vector3(x * s["width"], s["lift"] + y * s["height"], z * (s["front"] if z > 0.0 else s["rear"]))


## Wheels of shape `s`: [x, z, radius, width, front].
static func wheel_layout(s: Dictionary) -> Array:
	var out := []
	var wh: Array = s["wheels"]
	for w in WHEELS:
		var front: bool = w[4]
		out.append([w[0] * s["width"] * s["track"], w[1] * (s["front"] if w[1] > 0.0 else s["rear"]),
			wh[0] if front else wh[2], wh[1] if front else wh[3], front])
	return out


## Tail pipe ends of shape `s` in the body frame: [Vector3 end, radius].
static func nozzles(s: Dictionary) -> Array:
	var out := []
	for e in s["exhausts"]:
		out.append([warp_point(s, e[0], e[1], e[2]), e[3]])
	return out


# ---- loft --------------------------------------------------------------------

## A smooth body through superellipse cross-sections along z (stations ascending in z).
static func loft(stations: Array, ring := 18, steps := 3) -> Geo:
	var rows := []
	var S := stations.size()
	for s in S - 1:
		var p0: Array = stations[maxi(0, s - 1)]
		var p1: Array = stations[s]
		var p2: Array = stations[s + 1]
		var p3: Array = stations[mini(S - 1, s + 2)]
		for t in steps:
			var u := float(t) / steps
			var u2 := u * u
			var u3 := u2 * u
			var r := []
			for k in 6:
				r.append(0.5 * (2.0 * p1[k] + (-p0[k] + p2[k]) * u + (2.0 * p0[k] - 5.0 * p1[k] + 4.0 * p2[k] - p3[k]) * u2
					+ (-p0[k] + 3.0 * p1[k] - 3.0 * p2[k] + p3[k]) * u3))
			rows.append(r)
	rows.append(stations[S - 1])
	var g := Geo.new()
	for r in rows:
		_ring_points(g.pos, r, ring)
	for r in rows.size() - 1:
		for k in ring:
			var a := r * ring + k
			var b := r * ring + (k + 1) % ring
			var c := b + ring
			var d := a + ring
			g.tri(a, b, c)
			g.tri(a, c, d)
	# end caps with their own vertices (hard edge)
	for cap in 2:
		var r: Array = rows[0] if cap == 0 else rows[rows.size() - 1]
		var base := g.pos.size()
		g.pos.append(Vector3(r[1], r[2], r[0]))
		_ring_points(g.pos, r, ring)
		for k in ring:
			var a := base + 1 + k
			var b := base + 1 + (k + 1) % ring
			if cap == 1:
				g.tri(base, a, b)
			else:
				g.tri(base, b, a)
	g.compute_normals()
	return g


static func _ring_points(out: PackedVector3Array, r: Array, ring: int) -> void:
	var e := 2.0 / float(r[5])
	for k in ring:
		var a := float(k) / ring * TAU
		var c := cos(a)
		var s := sin(a)
		out.append(Vector3(r[1] + r[3] * signf(c) * pow(absf(c), e), r[2] + r[4] * signf(s) * pow(absf(s), e), r[0]))


## Stations mirrored to the other side (x -> -x).
static func mirror_x(st: Array) -> Array:
	var out := []
	for s in st:
		var c: Array = s.duplicate()
		c[1] = -c[1]
		out.append(c)
	return out


static func box(sx: float, sy: float, sz: float, x: float, y: float, z: float) -> Geo:
	return Geo.box(sx, sy, sz).translate(x, y, z)


# ---- body ---------------------------------------------------------------------

## Painted body panels: tub, fenders, side pods, and the livery stripes (racer frame).
static func body_stations(shape: Dictionary) -> Dictionary:
	var tub := [ST(-2.36, 0, 0.47, 0.5, 0.2), ST(-2.2, 0, 0.5, 0.58, 0.26), ST(-1.6, 0, 0.52, 0.62, 0.28), ST(-0.9, 0, 0.5, 0.64, 0.3),
		ST(0.0, 0, 0.46, 0.64, 0.28), ST(0.7, 0, 0.42, 0.62, 0.24), ST(1.3, 0, 0.37, 0.6, 0.19), ST(1.9, 0, 0.32, 0.58, 0.14, 4.5),
		ST(2.3, 0, 0.29, 0.5, 0.1, 4), ST(2.47, 0, 0.27, 0.36, 0.06, 3)]
	var front_fender := [ST(0.5, 0.79, 0.47, 0.05, 0.04, 3), ST(0.68, 0.8, 0.5, 0.16, 0.11, 4), ST(1.0, 0.8, 0.57, 0.24, 0.2),
		ST(1.45, 0.81, 0.6, 0.26, 0.21), ST(1.9, 0.8, 0.55, 0.25, 0.19), ST(2.25, 0.78, 0.45, 0.2, 0.13, 4), ST(2.42, 0.74, 0.37, 0.12, 0.07, 3)]
	var side_pod := [ST(-1.05, 0.76, 0.52, 0.26, 0.26), ST(-0.6, 0.75, 0.44, 0.26, 0.24), ST(0.1, 0.74, 0.42, 0.26, 0.22),
		ST(0.6, 0.74, 0.43, 0.22, 0.2), ST(0.85, 0.74, 0.45, 0.12, 0.12, 4)]
	var rear_fender := [ST(-2.36, 0.78, 0.53, 0.18, 0.14, 4), ST(-2.15, 0.8, 0.58, 0.25, 0.22), ST(-1.75, 0.81, 0.63, 0.28, 0.24),
		ST(-1.42, 0.82, 0.64, 0.29, 0.25), ST(-1.0, 0.8, 0.6, 0.28, 0.24), ST(-0.62, 0.78, 0.52, 0.2, 0.16, 4), ST(-0.38, 0.77, 0.47, 0.06, 0.05, 3)]
	var haunch: float = shape["haunch"]
	if haunch != 1.0:
		# fat rear tyres: wider haunches, grown outwards
		for s in rear_fender:
			s[1] = s[1] + (haunch - 1.0) * s[3]
			s[3] = s[3] * haunch
	# livery stripes: thin bands just proud of the tub's top surface
	var stripes := []
	for x in shape["stripes"]:
		var st := []
		for i in range(1, tub.size() - 1):
			var t: Array = tub[i]
			st.append(ST(t[0], x, t[2] + t[4] - 0.025, shape["stripeW"], 0.035, 4))
		stripes.append(st)
	return {"tub": tub, "frontFender": front_fender, "sidePod": side_pod, "rearFender": rear_fender, "stripes": stripes}


## Airfoil wing extruded across the car (chord backwards along -z, span along x).
static func wing_geometry(span: float, chord: float, thick: float) -> Geo:
	var pts := PackedVector2Array([Vector2(0, 0)])
	Geo.bezier(pts, Vector2(0, 0), Vector2(chord * 0.25, thick * 1.2), Vector2(chord * 0.7, thick * 0.9), Vector2(chord, thick * 0.2), 6)
	pts.append(Vector2(chord, 0))
	Geo.bezier(pts, Vector2(chord, 0), Vector2(chord * 0.7, -thick * 0.15), Vector2(chord * 0.25, -thick * 0.25), Vector2(0, 0), 6)
	return Geo.extrude(pts, span).translate(0, 0, -span / 2.0).rotate_y(PI / 2.0)


static func fin_geometry() -> Geo:
	var pts := PackedVector2Array()
	for p in FIN:
		pts.append(Vector2(p[0], p[1]))
	# outline x is the car's z; rotating -90 degrees about y maps it to z and the extrusion to -x
	return Geo.extrude(pts, 0.04).rotate_y(-PI / 2.0).translate(0.02, 0, 0)


## The extra parts of `shape` made of material `mat` (racer frame, not warped yet).
static func part_geometries(shape: Dictionary, mat: String, detail := 1) -> Array:
	var out := []
	for p in shape["parts"]:
		if p["mat"] != mat:
			continue
		for s in ([1.0, -1.0] if p.get("sym", false) else [1.0]):
			var g: Geo = null
			if p.has("loft"):
				g = loft(p["loft"] if s > 0.0 else mirror_x(p["loft"]), 18 if detail else 10, 3 if detail else 1)
			elif p.has("box"):
				g = Geo.box(p["box"][0], p["box"][1], p["box"][2])
			elif p.has("wing"):
				g = wing_geometry(p["wing"][0], p["wing"][1], p["wing"][2])
			elif p.has("hoop"):
				g = Geo.torus(p["hoop"][0], p["hoop"][1], 6, 14 if detail else 8, PI)
			elif p.has("lamp"):
				g = Geo.cylinder(p["lamp"][0], p["lamp"][0], p["lamp"][1], 14 if detail else 8).rotate_x(PI / 2.0)
			elif p.has("fin"):
				g = fin_geometry()
			else:
				continue
			if p.has("rx"):
				g.rotate_x(p["rx"])
			if p.has("at"):
				g.translate(s * p["at"][0], p["at"][1], p["at"][2])
			out.append(g)
	return out


static func paint_geometry(shape: Dictionary, detail := 1) -> Geo:
	var st := body_stations(shape)
	var ring := 18 if detail else 10
	var steps := 3 if detail else 1
	var parts := [
		loft(st["tub"], ring, steps),
		loft(st["frontFender"], ring, steps), loft(mirror_x(st["frontFender"]), ring, steps),
		loft(st["sidePod"], ring, steps), loft(mirror_x(st["sidePod"]), ring, steps),
		loft(st["rearFender"], ring, steps), loft(mirror_x(st["rearFender"]), ring, steps),
	]
	parts.append_array(part_geometries(shape, "paint", detail))
	return warp(Geo.merge(parts), shape)


static func stripe_geometry(shape: Dictionary) -> Geo:
	var parts := []
	for st in body_stations(shape)["stripes"]:
		parts.append(loft(st, 12, 3))
	return warp(Geo.merge(parts), shape)


static func carbon_geometry(shape: Dictionary, detail := 1) -> Geo:
	var parts := []
	# floor with a front splitter
	var fl := PackedVector2Array([Vector2(-0.9, -2.25), Vector2(0.9, -2.25), Vector2(0.9, 2.2)])
	Geo.quadratic(fl, Vector2(0.9, 2.2), Vector2(0.86, 2.5), Vector2(0.4, 2.52), 12)
	fl.append(Vector2(-0.4, 2.52))
	Geo.quadratic(fl, Vector2(-0.4, 2.52), Vector2(-0.86, 2.5), Vector2(-0.9, 2.2), 12)
	parts.append(Geo.extrude(fl, 0.05).rotate_x(PI / 2.0).translate(0, 0.16, 0))
	# the racer: rear wing on swan-neck pylons
	parts.append_array(part_geometries(shape, "carbon", detail))
	# diffuser fins
	for x in [-0.6, -0.2, 0.2, 0.6]:
		parts.append(box(0.03, 0.22, 0.4, x, 0.25, -2.12))
	# side intakes and mirror stalks
	var m: Array = shape["mirror"]
	for s in [1.0, -1.0]:
		parts.append(box(0.04, 0.2, 0.06, s * 0.72, 0.42, 0.83))
		parts.append(box(0.03, 0.03, 0.14, s * (m[0] - 0.09), m[1] - 0.02, m[2] + 0.04))
	if detail:
		# exhausts
		for e in shape["exhausts"]:
			parts.append(Geo.cylinder(e[3], e[3], 0.2, 10).rotate_x(PI / 2.0).translate(e[0], e[1], e[2] + 0.1))
	return warp(Geo.merge(parts), shape)


static func glass_geometry(shape: Dictionary) -> Geo:
	var parts := [loft(shape["glass"], 20, 3)]
	parts.append_array(part_geometries(shape, "glass"))
	return warp(Geo.merge(parts), shape)


## Parts in the car's accent colour, or null when it has none.
static func accent_geometry(shape: Dictionary) -> Geo:
	var parts := part_geometries(shape, "accent")
	return warp(Geo.merge(parts), shape) if not parts.is_empty() else null


static func mirror_geometry(shape: Dictionary) -> Geo:
	var m: Array = shape["mirror"]
	var parts := []
	for s in [1.0, -1.0]:
		parts.append(Geo.sphere(0.07, 10, 6).scale(1.4, 0.7, 1.1).translate(s * m[0], m[1], m[2]))
	return warp(Geo.merge(parts), shape)


## Tyre (lathe), rim with spokes, and brake disc + caliper (vertex colours). Rim face towards +x.
static func wheel_geometries(R: float, W: float) -> Dictionary:
	var tp := PackedVector2Array([Vector2(0.25, -W / 2), Vector2(R - 0.05, -W / 2), Vector2(R - 0.012, -W / 2 + 0.03),
		Vector2(R, -W / 2 + 0.08), Vector2(R, W / 2 - 0.08), Vector2(R - 0.012, W / 2 - 0.03), Vector2(R - 0.05, W / 2), Vector2(0.25, W / 2)])
	var tyre := Geo.lathe(tp, 28).rotate_z(-PI / 2.0)
	var rp := PackedVector2Array([Vector2(0.0, W / 2 - 0.05), Vector2(0.07, W / 2 - 0.05), Vector2(0.08, W / 2 - 0.1),
		Vector2(0.23, W / 2 - 0.12), Vector2(0.25, W / 2 - 0.03), Vector2(0.25, -W / 2 + 0.03), Vector2(0.22, -W / 2 + 0.03)])
	var rim_parts := [Geo.lathe(rp, 28).rotate_z(-PI / 2.0)]
	for k in 6:
		rim_parts.append(Geo.box(0.035, 0.16, 0.045).translate(W / 2 - 0.085, 0.15, 0).rotate_x(float(k) / 6.0 * TAU))
	rim_parts.append(Geo.cylinder(0.035, 0.035, 0.03, 10).rotate_z(PI / 2.0).translate(W / 2 - 0.035, 0, 0))
	var rim := Geo.merge(rim_parts)
	var disc := Geo.cylinder(0.21, 0.21, 0.028, 24).rotate_z(PI / 2.0).translate(-W / 2 + 0.11, 0, 0)
	var caliper := Geo.box(0.07, 0.15, 0.12).translate(-W / 2 + 0.11, 0.17, -0.1)
	disc.paint_solid(Color.hex(0x8a8d93ff).srgb_to_linear())
	caliper.paint_solid(Color.hex(0xd8322bff).srgb_to_linear())
	return {"tyre": tyre, "rim": rim, "brake": Geo.merge([disc, caliper])}


static func light_geometries(shape: Dictionary) -> Dictionary:
	var head := []
	var tail := []
	for s in [1.0, -1.0]:
		head.append(Geo.sphere(0.1, 12, 6).scale(1.5, 0.42, 0.85).rotate_x(-0.55).translate(s * 0.79, 0.485, 2.31))
		head.append(box(0.2, 0.018, 0.05, s * 0.79, 0.555, 2.2)) # daytime running light
	head.append_array(part_geometries(shape, "head")) # the rally car's light pod
	tail.append(box(1.9, 0.045, 0.03, 0, 0.6, -2.375)) # full-width light blade
	for s in [1.0, -1.0]:
		tail.append(box(0.05, 0.16, 0.03, s * 0.86, 0.55, -2.37))
	var r: Array = shape["rain"]
	tail.append(box(0.12, 0.06, 0.04, r[0], r[1], r[2])) # rain light
	return {"head": warp(Geo.merge(head), shape), "tail": warp(Geo.merge(tail), shape)}


# ---- side view ----------------------------------------------------------------

## Side view of car `id` for the car picker (plain numbers, same data as the 3D
## model): {parts: [{mat, pts: PackedVector2Array of (z, y)}], wheels: [Vector2(z, radius)]}
## in metres (z forward, y up). mat is "glass", "paint", "accent", "carbon" or "head".
## Draw the parts in order, then the wheels on top.
static func profile(id: String) -> Dictionary:
	var s := shape_of(id)
	var P := func(z: float, y: float) -> Vector2:
		var p := warp_point(s, 0, y, z)
		return Vector2(snappedf(p.z, 0.001), snappedf(p.y, 0.001))
	var side := func(st: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for t in st:
			out.append(P.call(t[0], t[2] + t[4]))
		for i in range(st.size() - 1, -1, -1):
			var t: Array = st[i]
			out.append(P.call(t[0], t[2] - t[4]))
		return out
	var rect := func(z: float, y: float, dz: float, dy: float) -> PackedVector2Array:
		return PackedVector2Array([P.call(z - dz, y - dy), P.call(z + dz, y - dy), P.call(z + dz, y + dy), P.call(z - dz, y + dy)])
	var b := body_stations(s)
	var parts := [{"mat": "glass", "pts": side.call(s["glass"])}]
	for key in ["sidePod", "rearFender", "frontFender", "tub"]:
		parts.append({"mat": "paint", "pts": side.call(b[key])})
	parts.append({"mat": "carbon", "pts": rect.call(0.13, 0.135, 2.38, 0.025)}) # floor
	for p in s["parts"]:
		if p.get("flat", false):
			continue
		var at: Array = p.get("at", [0, 0, 0])
		var y: float = at[1]
		var z: float = at[2]
		var pts := PackedVector2Array()
		if p.has("loft"):
			pts = side.call(p["loft"])
		elif p.has("box"):
			pts = rect.call(z, y, p["box"][2] / 2.0, p["box"][1] / 2.0)
		elif p.has("hoop"):
			pts = rect.call(z, y + (p["hoop"][0] + p["hoop"][1]) / 2.0, p["hoop"][1], (p["hoop"][0] + p["hoop"][1]) / 2.0)
		elif p.has("lamp"):
			pts = rect.call(z, y, p["lamp"][1] / 2.0, p["lamp"][0])
		elif p.has("fin"):
			for f in FIN:
				pts.append(P.call(f[0], f[1]))
		elif p.has("wing"):
			var chord: float = p["wing"][1]
			var thick: float = p["wing"][2]
			var a: float = p.get("rx", 0.0)
			var tz := z - chord * cos(a)
			var ty := y + chord * sin(a)
			pts = PackedVector2Array([P.call(z, y), P.call(z - chord * 0.3, y + thick), P.call(tz, ty + thick * 0.25), P.call(tz, ty),
				P.call(z - chord * 0.3, y - thick * 0.2)])
		if not pts.is_empty():
			parts.append({"mat": p["mat"], "pts": pts})
	var wheels := []
	for w in wheel_layout(s):
		if w[0] > 0.0:
			wheels.append(Vector2(snappedf(w[1], 0.001), w[2]))
	return {"parts": parts, "wheels": wheels}
