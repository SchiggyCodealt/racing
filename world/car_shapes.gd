## car_shapes.gd
## ------------------------------------------------------------------
## The six car bodies (carMesh.js SHAPES and its procedural geometry, plus
## the Dune buggy and the Vortex hypercar): one body plan with different
## proportions and parts per car. world/car_build.gd turns a shape into the
## whole skinned car (wheels, suspension, lights, decals, the driver).
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
##             sym: mirrored to -x as well; flat: left out of the side view (profile);
##             bone: "flap" for an active wing (car_build.gd moves it)
##   fenders, pods  false: no wheel arches / side pods (the buggy's open wheels); floorW: floor half width
##   open      an open cockpit (no canopy over the driver)
##   number    the race number on the doors; decal [z, y, radius] of its roundel (racer frame)
##   lights    "round" | "strip" (LED strips) | "buggy" (small lamps and a light bar)
##   hip, lean, wheel   the driver: hip point [x, z, y] (racer frame), recline (rad), steering
##             wheel [z, y, tilt]; tray [z0, z1, half width] the dark cockpit floor; seats [[x, z]]
##   suit, helmet, helmet_stripe, visor, gloves, rim, spokes, caliper, cage   colours (0xRRGGBB) and counts
##   seams     panel lines [axis (0: plane z = c, 1: plane |x| = c), c, r0, r1 (the |x| or z range), y0, y1]
##   vents     louvres on top of the body [x, z, length, half width, slats] (both sides)
##   tubes     roll cage / bars in the car's own frame [x0, y0, z0, x1, y1, z1, radius, sym]
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


## Keys every shape has (shapes() fills in the ones a car leaves out).
const DEFAULTS := {
	"fenders": true, "pods": true, "open": false, "number": "1", "lights": "round",
	"rim": 0xc3c7cf, "spokes": 6, "caliper": 0xd8322b,
	"suit": 0x202226, "helmet": 0xf2f2f2, "helmet_stripe": 0xd7263d, "visor": 0x10161f, "gloves": 0x1b1c20,
	"tray": [], "seats": [], "seams": [], "vents": [], "tubes": [], "decal": [-0.05, 0.45, 0.15],
	"cage": 0x3a3d42,
}


static func shapes() -> Dictionary:
	if not _shapes.is_empty():
		return _shapes
	_shapes = {
		# the v3 sports car: low wedge, bubble canopy, rear wing on swan necks, fin
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
			# the driver (racer frame): hip [x, z, y], recline (rad), steering wheel [z, y, tilt]
			"number": "1", "hip": [0.0, -0.22, 0.26], "lean": 0.45, "wheel": [-0.1, 0.86, 0.35],
			"tray": [-0.95, 0.72, 0.36],
			"suit": 0xe6e6e9, "gloves": 0xd7263d, "helmet": 0xf2f2f2, "helmet_stripe": 0xd7263d,
			"rim": 0xc3c7cf, "spokes": 6, "caliper": 0xd8322b,
			# panel lines (racer frame): [axis 0 = plane z, 1 = plane |x|; c; r0, r1 (|x| or z range); y0, y1]
			"seams": [[0, 0.62, 0.55, 1.2, 0.2, 0.76], [0, -0.6, 0.55, 1.2, 0.2, 0.8], [0, 1.05, 0.0, 0.5, 0.55, 0.9],
				[1, 0.5, 1.05, 2.3, 0.3, 0.9], [0, -1.3, 0.0, 0.55, 0.6, 1.0]],
			# louvres: [x, z, along-z length, half width, slats] on the top of the body (sym: both sides)
			"vents": [[0.32, 1.62, 0.34, 0.11, 5], [0.27, -1.5, 0.34, 0.1, 5]],
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
				# two headrest fairings and roll hoops behind the seats (the open cockpit is the tray)
				{"mat": "paint", "sym": true, "loft": [ST(-1.85, 0.22, 0.76, 0.04, 0.02, 3), ST(-1.35, 0.22, 0.78, 0.1, 0.07, 3),
					ST(-0.85, 0.22, 0.8, 0.13, 0.13, 3), ST(-0.66, 0.22, 0.8, 0.12, 0.14, 3)]},
				{"mat": "accent", "hoop": [0.13, 0.022], "at": [0.22, 0.86, -0.6], "sym": true},
				{"mat": "accent", "wing": [1.36, 0.2, 0.045], "at": [0, 0.77, -2.12], "rx": 0.3}, # ducktail lip
			],
			"number": "7", "open": true, "hip": [0.22, -0.2, 0.36], "lean": 0.32, "wheel": [0.13, 0.84, 0.42],
			"tray": [-0.8, 0.24, 0.42], "seats": [[0.22, -0.52], [-0.22, -0.52]],
			"suit": 0x2c4a9a, "gloves": 0xf2c14e, "helmet": 0x2b2d42, "helmet_stripe": 0xf2c14e,
			"rim": 0x24262b, "spokes": 10, "caliper": 0xd8322b,
			"seams": [[0, 0.55, 0.5, 1.2, 0.2, 0.74], [0, -0.55, 0.5, 1.2, 0.2, 0.76], [0, 0.95, 0.0, 0.48, 0.5, 0.9],
				[0, -1.62, 0.0, 0.5, 0.55, 0.95]],
			"vents": [[0.3, 1.55, 0.26, 0.09, 4]],
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
			"number": "3", "hip": [0.0, -0.55, 0.22], "lean": 0.48, "wheel": [-0.42, 0.84, 0.38],
			"tray": [-1.6, 0.4, 0.38],
			"suit": 0x2f6fd8, "gloves": 0xeef2f8, "helmet": 0xeef2f8, "helmet_stripe": 0x3a86ff,
			"rim": 0x5a5f69, "spokes": 5, "caliper": 0xffc83d,
			"seams": [[0, 0.3, 0.55, 1.2, 0.2, 0.78], [0, -1.05, 0.55, 1.2, 0.2, 0.82], [0, 0.65, 0.0, 0.52, 0.55, 0.95],
				[1, 0.52, 0.65, 2.3, 0.3, 0.95], [0, -1.95, 0.0, 0.55, 0.55, 1.0]],
			"vents": [[0.3, 1.35, 0.4, 0.12, 6]],
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
			"number": "5", "hip": [0.3, -0.3, 0.36], "lean": 0.24, "wheel": [0.16, 0.9, 0.55],
			"tray": [-1.9, 0.75, 0.55], "seats": [[0.3, -0.62], [-0.3, -0.62]],
			"suit": 0x1f6f69, "gloves": 0xff9f1c, "helmet": 0xff9f1c, "helmet_stripe": 0xf4f4f2,
			"rim": 0xd6a940, "spokes": 8, "caliper": 0xd8322b,
			"seams": [[0, 0.45, 0.55, 1.2, 0.2, 0.76], [0, -0.75, 0.55, 1.2, 0.2, 0.8], [0, 0.95, 0.0, 0.5, 0.5, 0.9]],
			# a rally cage behind the seats, in the car's own frame: [x0, y0, z0, x1, y1, z1, radius] (sym: mirrored)
			"tubes": [[0.5, 0.9, -0.85, 0.5, 1.33, -0.85, 0.022, true], [0.5, 1.33, -0.85, -0.5, 1.33, -0.85, 0.022, false],
				[0.5, 1.33, -0.85, 0.45, 0.92, -1.75, 0.02, true], [0.5, 1.33, -0.85, -0.5, 0.92, -1.75, 0.02, false]],
		},
		# open dune buggy: tube roll cage on a narrow tub, big tyres on long exposed arms, engine at the back
		"dune": {
			"front": 0.84, "rear": 0.86, "width": 0.82, "height": 1.0, "lift": 0.2, "track": 1.38, "haunch": 1.0,
			"wheels": [0.43, 0.32, 0.45, 0.4],
			"fenders": false, "pods": false, "open": true, "floorW": 0.62,
			"glass": [], "mirror": [],
			"stripes": [0.0], "stripeW": 0.1, "stripeAccent": true,
			"exhausts": [[0.2, 0.94, -2.32, 0.055], [-0.2, 0.94, -2.32, 0.055]],
			"rain": [0.0, 0.78, -2.3],
			"lights": "buggy",
			"parts": [
				{"mat": "carbon", "box": [0.78, 0.36, 0.62], "at": [0, 0.62, -1.78]},             # engine
				{"mat": "carbon", "box": [0.86, 0.06, 0.5], "at": [0, 0.46, 1.9]},               # skid plate
				{"mat": "accent", "box": [0.9, 0.05, 0.52], "at": [0, 0.83, -1.78]},              # engine lid
			],
			"number": "9", "hip": [0.0, -0.32, 0.4], "lean": 0.3, "wheel": [0.2, 0.92, 0.5],
			"seats": [[0.0, -0.64]],
			"suit": 0x6b6a4e, "helmet": 0xf4f4f2, "helmet_stripe": 0x8cc63f, "gloves": 0xb08a5a,
			"rim": 0x2a2c30, "spokes": 6, "caliper": 0x8cc63f,
			"decal": [-0.1, 0.46, 0.13],
			"cage": 0x2b2e33,
			# roll cage, nudge bar, light bar and side bars, in the car's own frame
			"tubes": [
				[0.46, 0.9, -0.82, 0.42, 1.62, -0.86, 0.03, true], [0.42, 1.62, -0.86, -0.42, 1.62, -0.86, 0.03, false],
				[0.46, 0.92, 0.6, 0.4, 1.56, 0.02, 0.028, true], [0.4, 1.56, 0.02, -0.4, 1.56, 0.02, 0.028, false],
				[0.42, 1.62, -0.86, 0.4, 1.56, 0.02, 0.028, true],
				[0.42, 1.62, -0.86, 0.4, 0.84, -1.98, 0.026, true], [0.4, 0.84, -1.98, -0.4, 0.84, -1.98, 0.026, false],
				[0.46, 0.92, 0.6, 0.34, 0.7, 1.72, 0.026, true],
				[0.5, 0.86, 0.56, 0.5, 0.86, -0.8, 0.024, true], [0.5, 0.86, 0.1, 0.52, 1.18, -0.36, 0.022, true],
				[0.34, 0.7, 1.72, 0.36, 0.5, 2.02, 0.03, true], [0.36, 0.5, 2.02, -0.36, 0.5, 2.02, 0.032, false],
				[0.36, 0.72, 1.98, -0.36, 0.72, 1.98, 0.028, false],
			],
		},
		# very low, wide mid-engine hypercar: cab-forward bubble, roof scoop, long tail, big diffuser, active wing
		"vortex": {
			"front": 1.05, "rear": 1.1, "width": 1.06, "height": 0.9, "lift": -0.02, "track": 1.0, "haunch": 1.12,
			"wheels": [0.36, 0.3, 0.4, 0.42],
			"glass": [ST(-1.05, 0, 0.74, 0.2, 0.05, 3), ST(-0.75, 0, 0.8, 0.36, 0.15, 3), ST(-0.3, 0, 0.86, 0.43, 0.25, 3),
				ST(0.25, 0, 0.85, 0.43, 0.24, 3), ST(0.8, 0, 0.77, 0.36, 0.15, 3), ST(1.2, 0, 0.68, 0.18, 0.04, 3)],
			"mirror": [0.66, 0.86, 0.72],
			"stripes": [0.2, -0.2], "stripeW": 0.04, "stripeAccent": true,
			"exhausts": [[0.13, 0.66, -2.42, 0.062], [-0.13, 0.66, -2.42, 0.062]],
			"rain": [0.0, 0.5, -2.4],
			"lights": "strip",
			"parts": [
				{"mat": "accent", "loft": [ST(-0.35, 0, 1.1, 0.07, 0.015, 4), ST(-0.6, 0, 1.13, 0.15, 0.07, 4), ST(-1.0, 0, 1.08, 0.16, 0.08, 4),
					ST(-1.45, 0, 0.96, 0.12, 0.05, 4), ST(-1.7, 0, 0.88, 0.06, 0.02, 4)]}, # roof scoop
				{"mat": "paint", "fin": true},
				{"mat": "carbon", "wing": [2.02, 0.44, 0.07], "at": [0, 1.2, -2.0], "bone": "flap"},      # active wing
				{"mat": "accent", "box": [0.035, 0.3, 0.5], "at": [1.0, 1.2, -2.18], "sym": true, "bone": "flap"},
				{"mat": "carbon", "box": [0.045, 0.5, 0.2], "at": [0.36, 0.95, -2.02], "sym": true},  # wing pylons
				{"mat": "carbon", "box": [2.0, 0.035, 0.34], "at": [0, 0.12, 2.36]},              # splitter
				{"mat": "carbon", "box": [0.05, 0.1, 0.32], "at": [0.96, 0.28, 2.14], "sym": true}, # canards
				{"mat": "carbon", "box": [1.7, 0.3, 0.4], "at": [0, 0.27, -2.25]},               # diffuser
				{"mat": "carbon", "loft": [ST(-1.25, 0.98, 0.5, 0.03, 0.04, 4), ST(-0.95, 0.99, 0.5, 0.07, 0.13, 4),
					ST(-0.7, 0.98, 0.5, 0.06, 0.14, 4), ST(-0.55, 0.97, 0.5, 0.02, 0.1, 4)], "sym": true}, # side intakes
			],
			"number": "6", "hip": [0.0, 0.06, 0.14], "lean": 0.58, "wheel": [0.22, 0.8, 0.42],
			"tray": [-0.9, 1.0, 0.36],
			"suit": 0x34363e, "gloves": 0xff6b1a, "helmet": 0x15161a, "helmet_stripe": 0xff6b1a, "visor": 0x1b2c4a,
			"rim": 0x1d1f23, "spokes": 10, "caliper": 0xffc83d,
			"seams": [[0, 0.8, 0.55, 1.2, 0.2, 0.74], [0, -0.55, 0.55, 1.2, 0.2, 0.78], [0, 1.2, 0.0, 0.5, 0.5, 0.9],
				[0, -1.25, 0.0, 0.5, 0.6, 1.0]],
			"vents": [[0.32, 1.7, 0.28, 0.1, 4], [0.3, -1.55, 0.4, 0.12, 6]],
		},
	}
	for id: String in _shapes:
		var sh: Dictionary = _shapes[id]
		for k: String in DEFAULTS:
			if not sh.has(k):
				sh[k] = DEFAULTS[k]
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
## bone: only the parts on that bone ("" the body's, "*" every part).
static func part_geometries(shape: Dictionary, mat: String, detail := 1, bone := "*") -> Array:
	var out := []
	for p in shape["parts"]:
		if p["mat"] != mat:
			continue
		if bone != "*" and String(p.get("bone", "")) != bone:
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


static func paint_geometry(shape: Dictionary, detail := 1, bone := "*") -> Geo:
	var parts := body_panels(shape, detail).values()
	parts.append_array(part_geometries(shape, "paint", detail, bone))
	return warp(Geo.merge(parts), shape)


## The painted panels in the racer frame: {tub, front_l, front_r, pod_l, pod_r, rear_l, rear_r}
## (fenders and pods only when the shape has them).
static func body_panels(shape: Dictionary, detail := 1) -> Dictionary:
	var st := body_stations(shape)
	var ring := 18 if detail else 10
	var steps := 3 if detail else 1
	var out := {"tub": loft(st["tub"], ring, steps)}
	if shape["fenders"]:
		out["front_l"] = loft(st["frontFender"], ring, steps)
		out["front_r"] = loft(mirror_x(st["frontFender"]), ring, steps)
		out["rear_l"] = loft(st["rearFender"], ring, steps)
		out["rear_r"] = loft(mirror_x(st["rearFender"]), ring, steps)
	if shape["pods"]:
		out["pod_l"] = loft(st["sidePod"], ring, steps)
		out["pod_r"] = loft(mirror_x(st["sidePod"]), ring, steps)
	return out


static func stripe_geometry(shape: Dictionary) -> Geo:
	var parts := []
	for st in body_stations(shape)["stripes"]:
		parts.append(loft(st, 12, 3))
	return warp(Geo.merge(parts), shape)


static func carbon_geometry(shape: Dictionary, detail := 1, exhausts := true, bone := "*") -> Geo:
	var parts := []
	# floor with a front splitter
	var fw: float = shape.get("floorW", 0.9)
	var fl := PackedVector2Array([Vector2(-fw, -2.25), Vector2(fw, -2.25), Vector2(fw, 2.2)])
	Geo.quadratic(fl, Vector2(fw, 2.2), Vector2(fw * 0.955, 2.5), Vector2(0.4 * fw / 0.9, 2.52), 12)
	fl.append(Vector2(-0.4 * fw / 0.9, 2.52))
	Geo.quadratic(fl, Vector2(-0.4 * fw / 0.9, 2.52), Vector2(-fw * 0.955, 2.5), Vector2(-fw, 2.2), 12)
	parts.append(Geo.extrude(fl, 0.05).rotate_x(PI / 2.0).translate(0, 0.16, 0))
	# the racer: rear wing on swan-neck pylons
	parts.append_array(part_geometries(shape, "carbon", detail, bone))
	# diffuser fins
	for x in [-0.6, -0.2, 0.2, 0.6]:
		parts.append(box(0.03, 0.22, 0.4, x, 0.25, -2.12))
	# side intakes and mirror stalks
	var m: Array = shape["mirror"]
	for s in [1.0, -1.0]:
		if shape["pods"]:
			parts.append(box(0.04, 0.2, 0.06, s * 0.72, 0.42, 0.83))
		if not m.is_empty():
			parts.append(box(0.03, 0.03, 0.14, s * (m[0] - 0.09), m[1] - 0.02, m[2] + 0.04))
	if detail and exhausts:
		# exhausts
		for e in shape["exhausts"]:
			parts.append(Geo.cylinder(e[3], e[3], 0.2, 10).rotate_x(PI / 2.0).translate(e[0], e[1], e[2] + 0.1))
	return warp(Geo.merge(parts), shape)


static func glass_geometry(shape: Dictionary, detail := 1) -> Geo:
	var parts := []
	if not (shape["glass"] as Array).is_empty():
		parts.append(loft(shape["glass"], 20 if detail else 10, 3 if detail else 1))
	parts.append_array(part_geometries(shape, "glass", detail))
	return warp(Geo.merge(parts), shape)


## Parts in the car's accent colour, or null when it has none.
static func accent_geometry(shape: Dictionary, detail := 1, bone := "*") -> Geo:
	var parts := part_geometries(shape, "accent", detail, bone)
	return warp(Geo.merge(parts), shape) if not parts.is_empty() else null


static func mirror_geometry(shape: Dictionary) -> Geo:
	var m: Array = shape["mirror"]
	var parts := []
	if m.is_empty():
		return Geo.new()
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


## The lamps (warped onto the shape): head (glowing), tail (glowing red) and housing (dark bezels).
## Styles: "round" (lens and running-light strip), "strip" (thin LED blades), "buggy" (small
## round lamps at the nose; car_build.gd adds the light bar on the cage).
static func light_geometries(shape: Dictionary, detail := 1) -> Dictionary:
	var head := []
	var tail := []
	var housing := []
	var style: String = shape["lights"]
	var seg := 12 if detail else 8
	for s in [1.0, -1.0]:
		if style == "round":
			head.append(Geo.sphere(0.1, seg, 6).scale(1.5, 0.42, 0.85).rotate_x(-0.55).translate(s * 0.79, 0.485, 2.31))
			head.append(box(0.2, 0.018, 0.05, s * 0.79, 0.555, 2.2)) # daytime running light
			housing.append(Geo.sphere(0.112, seg, 6).scale(1.5, 0.5, 0.85).rotate_x(-0.55).translate(s * 0.79, 0.48, 2.29))
		elif style == "strip":
			head.append(box(0.36, 0.022, 0.05, 0, 0, 0).rotate_y(s * 0.32).rotate_x(-0.2).translate(s * 0.7, 0.5, 2.28))
			head.append(Geo.sphere(0.045, seg, 6).scale(1.0, 0.8, 0.6).translate(s * 0.58, 0.455, 2.36))
			head.append(Geo.sphere(0.045, seg, 6).scale(1.0, 0.8, 0.6).translate(s * 0.68, 0.45, 2.32))
			housing.append(box(0.34, 0.09, 0.05, 0, 0, 0).rotate_y(s * 0.3).translate(s * 0.64, 0.46, 2.3))
		else:
			head.append(Geo.sphere(0.075, seg, 6).scale(1.0, 1.0, 0.5).translate(s * 0.3, 0.42, 2.4))
			housing.append(Geo.cylinder(0.085, 0.085, 0.07, seg).rotate_x(PI / 2.0).translate(s * 0.3, 0.42, 2.36))
	head.append_array(part_geometries(shape, "head", detail)) # the rally car's light pod
	if style == "strip":
		tail.append(box(1.96, 0.026, 0.03, 0, 0.66, -2.375)) # full-width LED blade
		for s in [1.0, -1.0]:
			tail.append(box(0.04, 0.2, 0.03, s * 0.92, 0.58, -2.36))
	elif style == "round":
		tail.append(box(1.9, 0.045, 0.03, 0, 0.6, -2.375)) # full-width light blade
		for s in [1.0, -1.0]:
			tail.append(box(0.05, 0.16, 0.03, s * 0.86, 0.55, -2.37))
	var r: Array = shape["rain"]
	tail.append(box(0.12, 0.06, 0.04, r[0], r[1], r[2])) # rain light
	return {"head": warp(Geo.merge(head), shape), "tail": warp(Geo.merge(tail), shape),
		"housing": warp(Geo.merge(housing), shape)}
