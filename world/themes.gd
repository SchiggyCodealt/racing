## themes.gd
## ------------------------------------------------------------------
## The look of each theme and the graphics quality levels (scene.js THEMES
## and QUALITY of the web game, same numbers). Colours are sRGB hex
## integers (0xRRGGBB), as in the JS; col() turns one into a Color and
## lin() into a linear Color (vertex colours, shader maths).
##
## Theme fields: sky (zenith, horizon, below, clouds, cloudLit, cloudShade,
## haze, stars), sun (color, intensity, elevation, azimuth in degrees),
## hemi (sky, ground, intensity), env (environment light scale), fog
## (color, near, far in m), exposure, bloom (strength, radius, threshold),
## ground colours, hills / mountains (m) and mountainStyle (peaks | mesa),
## accent (barrier panel colours), lamps (lit lamps and gates), scenery
## (species names), tuft (grass colours or null); extras: glow (night
## barrier stripes), skyline (night city), sea (seaside coast).
## Light intensities are the Three.js values; World converts them.
extends RefCounted

const THEMES := {
	"meadow": {
		"sky": {"zenith": 0x2a66cc, "horizon": 0xc7def0, "below": 0x6d8a4f, "clouds": 0.42, "cloudLit": 0xffffff, "cloudShade": 0x9fb2c8, "haze": 0.5},
		"sun": {"color": 0xfff0d8, "intensity": 3.3, "elevation": 54.0, "azimuth": 35.0},
		"hemi": {"sky": 0xd6ebff, "ground": 0x5d6f3c, "intensity": 0.3},
		"env": 1.0,
		"fog": {"color": 0xc4dbec, "near": 320.0, "far": 2900.0},
		"exposure": 1.0,
		"bloom": {"strength": 0.22, "radius": 0.45, "threshold": 1.15},
		"ground": {"a": 0x4b7a30, "b": 0x6a9541, "dry": 0x8f9150, "dirt": 0x86704f, "rock": 0x86847b, "snow": -1, "far": 0x648a45},
		"hills": 9.0, "mountains": 150.0, "mountainStyle": "peaks",
		"accent": [0x2f6df6, 0xf2f5fa], "lamps": false,
		"scenery": ["broadleaf", "pine", "bush", "rock"],
		"tuft": {"color": 0x6f9f3f, "tip": 0xa8c46a},
	},
	"desert": {
		"sky": {"zenith": 0x3c7cc9, "horizon": 0xf0dcc0, "below": 0xc8a06a, "clouds": 0.14, "cloudLit": 0xfff6ea, "cloudShade": 0xd2b9a0, "haze": 0.9},
		"sun": {"color": 0xffe1b0, "intensity": 3.6, "elevation": 46.0, "azimuth": 120.0},
		"hemi": {"sky": 0xffe9cc, "ground": 0xa07a4c, "intensity": 0.3},
		"env": 1.0,
		"fog": {"color": 0xe9d4b6, "near": 180.0, "far": 2300.0},
		"exposure": 0.95,
		"bloom": {"strength": 0.2, "radius": 0.45, "threshold": 1.3},
		"ground": {"a": 0xd6b07a, "b": 0xc89b62, "dry": 0xb98d58, "dirt": 0xa77a4f, "rock": 0xa86b45, "snow": -1, "far": 0xd3ab74},
		"hills": 7.0, "mountains": 130.0, "mountainStyle": "mesa",
		"accent": [0xe8742c, 0xf6efe4], "lamps": false,
		"scenery": ["saguaro", "barrel", "shrubDry", "rockRed"],
		"tuft": {"color": 0xb59a5c, "tip": 0xe0cc8a},
	},
	"alpine": {
		"sky": {"zenith": 0x1b58bd, "horizon": 0xd2e3f3, "below": 0xdbe5ee, "clouds": 0.36, "cloudLit": 0xffffff, "cloudShade": 0xa9b8cc, "haze": 0.4},
		"sun": {"color": 0xf1f5ff, "intensity": 3.0, "elevation": 34.0, "azimuth": 205.0},
		"hemi": {"sky": 0xdbe9ff, "ground": 0x9aa4b0, "intensity": 0.3},
		"env": 0.95,
		"fog": {"color": 0xcfe0ef, "near": 380.0, "far": 3300.0},
		"exposure": 0.88,
		"bloom": {"strength": 0.18, "radius": 0.4, "threshold": 1.7},
		"ground": {"a": 0xe9eef4, "b": 0xdfe6ee, "dry": 0x8f9a7c, "dirt": 0x7d7a74, "rock": 0x7c7f86, "snow": 0xf4f7fb, "far": 0xe4ebf2},
		"hills": 12.0, "mountains": 330.0, "mountainStyle": "peaks",
		"accent": [0xd6262e, 0xf4f6f8], "lamps": false,
		"scenery": ["pineSnow", "pine", "rockGrey"],
		"tuft": null,
	},
	"canyon": {
		"sky": {"zenith": 0x3874c2, "horizon": 0xeecaa6, "below": 0xa65a38, "clouds": 0.24, "cloudLit": 0xfff1e4, "cloudShade": 0xc9a58e, "haze": 0.8},
		"sun": {"color": 0xffd8a6, "intensity": 3.5, "elevation": 40.0, "azimuth": 300.0},
		"hemi": {"sky": 0xffe2c8, "ground": 0x8c4a2e, "intensity": 0.3},
		"env": 1.0,
		"fog": {"color": 0xe4bf9c, "near": 220.0, "far": 2500.0},
		"exposure": 0.95,
		"bloom": {"strength": 0.2, "radius": 0.45, "threshold": 1.3},
		"ground": {"a": 0xb4643a, "b": 0xc47a48, "dry": 0xa98a5a, "dirt": 0x8e4a2c, "rock": 0x9a4a2c, "snow": -1, "far": 0xb86a3e},
		"hills": 10.0, "mountains": 170.0, "mountainStyle": "mesa",
		"accent": [0x1f9fb8, 0xf3ebe1], "lamps": false,
		"scenery": ["shrubDry", "hoodoo", "rockRed", "juniper"],
		"tuft": {"color": 0x9f8a55, "tip": 0xd2b878},
	},
	"dusk": {
		"sky": {"zenith": 0x1f2a63, "horizon": 0xff9152, "below": 0x3a2c38, "clouds": 0.5, "cloudLit": 0xffa070, "cloudShade": 0x5b4b72, "haze": 1.6},
		"sun": {"color": 0xff9a55, "intensity": 2.6, "elevation": 15.0, "azimuth": 250.0},
		"hemi": {"sky": 0x7378c0, "ground": 0x3c2a26, "intensity": 0.95},
		"env": 1.2,
		"fog": {"color": 0xc07a68, "near": 140.0, "far": 2400.0},
		"exposure": 1.1,
		"bloom": {"strength": 0.55, "radius": 0.55, "threshold": 0.9},
		"ground": {"a": 0x4a7332, "b": 0x5d8338, "dry": 0x7b7a46, "dirt": 0x6b5842, "rock": 0x6f6a66, "snow": -1, "far": 0x4c6e34},
		"hills": 9.0, "mountains": 120.0, "mountainStyle": "peaks",
		"accent": [0x8a3cf0, 0xf2f2f6], "lamps": true,
		"scenery": ["broadleaf", "pine", "bush", "rock"],
		"tuft": {"color": 0x58803a, "tip": 0x93a95a},
	},
	"night": {
		# the "sun" is the moon: cool, low light; most of the light comes from the lamps and stripes
		"sky": {"zenith": 0x040817, "horizon": 0x1b2850, "below": 0x0a1020, "clouds": 0.22, "cloudLit": 0x34405e, "cloudShade": 0x0b1020, "haze": 0.7, "stars": 1.0},
		"sun": {"color": 0xa9bcff, "intensity": 0.95, "elevation": 36.0, "azimuth": 140.0},
		"hemi": {"sky": 0x4a5f9a, "ground": 0x1c2030, "intensity": 1.1},
		"env": 2.4,
		"fog": {"color": 0x0b1224, "near": 220.0, "far": 2600.0},
		"exposure": 1.3,
		"bloom": {"strength": 0.5, "radius": 0.5, "threshold": 0.8},
		"ground": {"a": 0x3d5233, "b": 0x4a5e3a, "dry": 0x5d5e44, "dirt": 0x524638, "rock": 0x5c5d63, "snow": -1, "far": 0x2b3826},
		"hills": 6.0, "mountains": 30.0, "mountainStyle": "peaks",
		"accent": [0x16d0ff, 0xeef2f8], "lamps": true, "glow": true, "skyline": true,
		"scenery": ["pine", "broadleaf", "bush", "rock"],
		"tuft": {"color": 0x40603a, "tip": 0x6c8456},
	},
	"seaside": {
		"sky": {"zenith": 0x2470d4, "horizon": 0xcde6f6, "below": 0x2d6f8f, "clouds": 0.3, "cloudLit": 0xffffff, "cloudShade": 0xa7bccf, "haze": 0.6},
		"sun": {"color": 0xfff1d8, "intensity": 3.3, "elevation": 48.0, "azimuth": 205.0},
		"hemi": {"sky": 0xd8ecff, "ground": 0xb9a57c, "intensity": 0.32},
		"env": 1.0,
		"fog": {"color": 0xc9e0ee, "near": 380.0, "far": 3400.0},
		"exposure": 1.0,
		"bloom": {"strength": 0.22, "radius": 0.45, "threshold": 1.15},
		"ground": {"a": 0x6a9346, "b": 0x7fa04c, "dry": 0xb9a873, "dirt": 0xa98f62, "rock": 0x8e8a80, "snow": -1, "far": 0x14465f},
		"hills": 6.0, "mountains": 120.0, "mountainStyle": "peaks",
		"accent": [0x1d86d6, 0xf4f6f8], "lamps": false,
		"sea": {"level": 1.6, "water": 0x1b6a8c, "deep": 0x123f5a, "shallow": 0x58b8b4, "sand": 0xe4d2a0},
		"scenery": ["palm", "bushCoast", "rock"],
		"tuft": {"color": 0x8aa456, "tip": 0xd2c98a},
	},
}

const NAMES := ["meadow", "desert", "alpine", "canyon", "dusk", "night", "seaside"]

## Quality levels (scene.js QUALITY, plus what Godot does with them): render scale
## (the web's pixel-ratio cap at 1x DPI), bloom (glow), sun shadow map size and
## distance, share of scenery drawn, grass tufts, scenery shadows, share of wall
## sparks and nitro glow; msaa, ssao and lamp lights are Godot extras.
const QUALITY := {
	"high": {"scale": 1.0, "bloom": true, "shadow": 4096, "shadow_dist": 320.0, "splits": 4, "scenery": 1.0, "tufts": true,
		"scenery_shadows": true, "sparks": 1.0, "msaa": 2, "ssao": true, "lamp_lights": true},
	"medium": {"scale": 1.0, "bloom": false, "shadow": 2048, "shadow_dist": 200.0, "splits": 2, "scenery": 0.75, "tufts": true,
		"scenery_shadows": true, "sparks": 0.65, "msaa": 2, "ssao": false, "lamp_lights": false},
	"low": {"scale": 0.85, "bloom": false, "shadow": 1024, "shadow_dist": 110.0, "splits": 1, "scenery": 0.4, "tufts": false,
		"scenery_shadows": false, "sparks": 0.3, "msaa": 0, "ssao": false, "lamp_lights": false},
}
const QUALITY_ORDER := ["high", "medium", "low"]


static func get_theme(theme_name: String) -> Dictionary:
	return THEMES.get(theme_name, THEMES["meadow"])


static func get_quality(level: String) -> Dictionary:
	return QUALITY.get(level, QUALITY["high"])


## sRGB Color from a 0xRRGGBB integer.
static func col(hex: int) -> Color:
	return Color.hex((hex << 8) | 0xff)


## Linear Color from a 0xRRGGBB integer (Three.js Color.setHex).
static func lin(hex: int) -> Color:
	return col(hex).srgb_to_linear()


## Unit vector pointing at the sun of a theme.
static func sun_direction(theme: Dictionary) -> Vector3:
	var el := deg_to_rad(float(theme["sun"]["elevation"]))
	var az := deg_to_rad(float(theme["sun"]["azimuth"]))
	return Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
