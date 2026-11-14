## textures.gd (procedural textures of web/src/game/trackMesh.js)
## ------------------------------------------------------------------
## Shared by every track and made once: asphalt (colour, roughness and
## normal maps), loose ground (dirt and packed snow detail, v6.3; gravel, sand, mud and ice, v6.23), grey detail noise, start-line checker, chevron boards,
## sponsor banners, the lamp light pool, sea ripple normals; plus the gate
## banner atlas of a track (one row per gate). All mipmapped, repeat where
## the JS repeats. Noise comes from FastNoiseLite seamless images (the JS
## fbmP is far too slow per pixel in GDScript); text from the project font
## (Barlow Condensed Bold, slanted and emboldened like the JS "italic 900"),
## blitted glyph by glyph from the font cache, so it needs no viewport.
extends RefCounted

const FONT_PATH := "res://assets/fonts/BarlowCondensed-Bold.woff2"

## Material colour (sRGB) whose linear value is 1/0.86: the JS brightens vertex
## colours by that much to make up for the detail texture (~14 % darker on average).
static var BOOST := Color(1.0 / 0.86, 1.0 / 0.86, 1.0 / 0.86).linear_to_srgb()

static var _cache: Dictionary = {}


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Seamless value-noise fbm image (L8, 0..1 stretched), `cells` lattice cells across.
static func _noise_image(size: int, cells: float, octaves: int, seed: int) -> Image:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_VALUE
	n.seed = seed
	n.frequency = cells / size
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n.get_seamless_image(size, size, false, false, 0.1, true)


## Asphalt: {map, rough, normal} (512 px, 7 m a tile on the road).
static func asphalt() -> Dictionary:
	if _cache.has("asphalt"):
		return _cache["asphalt"]
	var S := 512
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var blot_img := _noise_image(S, 6.0, 4, 11)
	var blot_px := blot_img.get_data()
	var bpp := blot_px.size() / (S * S)
	var hgt := PackedFloat32Array()
	hgt.resize(S * S)
	var cd := PackedByteArray()
	var rd := PackedByteArray()
	cd.resize(S * S * 3)
	rd.resize(S * S)
	for k in S * S:
		# the noise image is stretched to 0..1: bring it back to fbm's usual spread
		var blot := 0.5 + (blot_px[k * bpp] / 255.0 - 0.5) * 0.6
		var grain := rng.randf()
		var speck := 1.0 if rng.randf() < 0.02 else 0.0
		hgt[k] = grain * 0.7 + speck * 0.9 + blot * 0.4
		var g := 54.0 + (blot - 0.5) * 30.0 + (grain - 0.5) * 26.0 + speck * 36.0
		cd[k * 3] = clampi(int(g - 1.0), 0, 255)
		cd[k * 3 + 1] = clampi(int(g), 0, 255)
		cd[k * 3 + 2] = clampi(int(g + 4.0), 0, 255)
		rd[k] = clampi(int(215.0 + (blot - 0.5) * 70.0 + (grain - 0.5) * 34.0 - speck * 40.0), 0, 255)
	var cimg := Image.create_from_data(S, S, false, Image.FORMAT_RGB8, cd)
	var rimg := Image.create_from_data(S, S, false, Image.FORMAT_L8, rd)
	var nimg := Image.create_from_data(S, S, false, Image.FORMAT_RF, hgt.to_byte_array())
	nimg.bump_map_to_normal_map(2.4)
	var out := {"map": _tex(cimg), "rough": _tex(rimg), "normal": _tex(nimg)}
	_cache["asphalt"] = out
	return out


## Loose ground for world/shaders/road_surface.gdshader: {map, normal} (512 px, 7 m a tile).
## v6.10: richer and less regular. map is linear data:
##   R dirt detail: layered grain, scattered gravel and pebbles of 2-9 cm (light and dark, each a
##     rounded stone), fine cracks
##   G large soft patches (0..1): the shader samples it at several scales for the ragged surface
##     borders, damp patches, puddles and icy patches, and to hide the tiling
##   B packed snow detail: soft drifts, fine grain and a few glints (255: the shader makes them sparkle)
##   A medium noise of its own (0..1): clumps where the surface changes, powder lumps, frost
## normal: the stones, the grain and the cracks (the shader keeps it faint on snow).
static func loose() -> Dictionary:
	if _cache.has("loose"):
		return _cache["loose"]
	var S := 512
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var blot := _noise_image(S, 7.0, 4, 41).get_data()
	var patch := _noise_image(S, 3.0, 3, 43).get_data()
	var fine := _noise_image(S, 22.0, 3, 47).get_data()
	var mid := _noise_image(S, 5.0, 3, 53).get_data()
	var crack := _noise_image(S, 11.0, 2, 59).get_data()
	var bpp := blot.size() / (S * S)
	var hgt := PackedFloat32Array()
	hgt.resize(S * S)
	var dirt := PackedFloat32Array()
	dirt.resize(S * S)
	var cd := PackedByteArray()
	cd.resize(S * S * 4)
	for k in S * S:
		var b := 0.5 + (blot[k * bpp] / 255.0 - 0.5) * 0.6
		var f := fine[k * bpp] / 255.0
		var cr := absf(crack[k * bpp] / 255.0 - 0.5) # (cracks along the noise's mid line)
		var grain := rng.randf()
		var line := 1.0 - clampf(cr / 0.025, 0.0, 1.0)
		dirt[k] = 0.8 + (b - 0.5) * 0.34 + (f - 0.5) * 0.12 + (grain - 0.5) * 0.16 - line * 0.12
		hgt[k] = grain * 0.35 + b * 0.5 + f * 0.25 - line * 0.35
		var snow := 0.93 + (f - 0.5) * 0.07 + (b - 0.5) * 0.05 + (grain - 0.5) * 0.035
		cd[k * 4 + 1] = patch[k * bpp]
		cd[k * 4 + 2] = clampi(int(snow * 254.0), 0, 254)
		cd[k * 4 + 3] = mid[k * bpp]
	# gravel and pebbles: rounded stones of 1-4 px radius (most small), light or dark, wrapping at the edges
	for n in 3400:
		var cx := rng.randi_range(0, S - 1)
		var cy := rng.randi_range(0, S - 1)
		# (in drifts: denser where the medium noise is high, few where it is low)
		if rng.randf() > smoothstep(0.25, 0.75, mid[(cy * S + cx) * bpp] / 255.0) * 0.9 + 0.1:
			continue
		var r := 1.0 + pow(rng.randf(), 2.6) * 3.4
		var tone := rng.randf_range(0.08, 0.17) if rng.randf() < 0.5 else -rng.randf_range(0.14, 0.27)
		var ri := ceili(r)
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var d2 := float(dx * dx + dy * dy) / (r * r)
				if d2 > 1.0:
					continue
				var k := posmod(cy + dy, S) * S + posmod(cx + dx, S)
				var dome := sqrt(1.0 - d2)
				dirt[k] = lerpf(dirt[k], 0.8 + tone - (0.06 if dx + dy > 0 else -0.04) * dome, 0.85)
				hgt[k] = maxf(hgt[k], 0.6 + dome * 0.9 * r / 3.0)
	for k in S * S:
		cd[k * 4] = clampi(int(dirt[k] * 255.0), 0, 255)
	# glints in the snow: a few single bright crystals
	for n in 900:
		cd[(rng.randi_range(0, S - 1) * S + rng.randi_range(0, S - 1)) * 4 + 2] = 255
	var nimg := Image.create_from_data(S, S, false, Image.FORMAT_RF, hgt.to_byte_array())
	nimg.bump_map_to_normal_map(3.0)
	var out := {"map": _tex(Image.create_from_data(S, S, false, Image.FORMAT_RGBA8, cd)), "normal": _tex(nimg)}
	_cache["loose"] = out
	return out


## The detail texture of a road surface (sim/surfaces.gd `tex`): {map, normal}, 512 px, 7 m a tile.
## "loose" is loose() (dirt and packed snow); v6.23, the rally stages' own, linear data:
##   gravel  R crushed stone packed tight (every stone its own shade, lit from one side), G each
##           stone's hue (0 cool grey .. 1 warm brown), A height; normal: the stones
##   sand    R wind ripples (about 25 cm apart, wavy, fading in and out) and fine grain, G a slow
##           hue drift, A height; normal: the ripples
##   mud     R churned lumps and clods, dark where it is low and wet, G hue, B the wet sheen
##           (1 in the hollows), A height; normal: the lumps
##   ice     R cloudy ice with white bubbles, G cracks (1 on a crack: big plates and finer
##           cracks inside them), B soft patches (where snow lies on it), A fine grain (sparkle);
##           normal: faint, the cracks
static func surface(kind: String) -> Dictionary:
	if kind == "loose" or not ["gravel", "sand", "mud", "ice"].has(kind):
		return loose()
	if _cache.has(kind):
		return _cache[kind]
	var S := 512
	var rng := RandomNumberGenerator.new()
	rng.seed = 61 + kind.hash() % 1000
	var blot := _noise_image(S, 7.0, 4, 141).get_data()
	var fine := _noise_image(S, 22.0, 3, 147).get_data()
	var mid := _noise_image(S, 4.0, 3, 153).get_data()
	var bpp := blot.size() / (S * S)
	var lum := PackedFloat32Array()
	lum.resize(S * S)
	var hue := PackedFloat32Array()
	hue.resize(S * S)
	var gloss := PackedFloat32Array()
	gloss.resize(S * S)
	var hgt := PackedFloat32Array()
	hgt.resize(S * S)
	var bump := 3.0
	match kind:
		"gravel":
			for k in S * S:
				var b := blot[k * bpp] / 255.0
				var f := fine[k * bpp] / 255.0
				var grain := rng.randf()
				lum[k] = 0.7 + (b - 0.5) * 0.24 + (f - 0.5) * 0.16 + (grain - 0.5) * 0.24
				hue[k] = 0.5 + (mid[k * bpp] / 255.0 - 0.5) * 0.7
				hgt[k] = grain * 0.3 + f * 0.25
			_stamp_stones(S, rng, 9000, 1.0, 3.4, 2.2, lum, hue, hgt, 0.5, 1.1)
			bump = 4.0
		"sand":
			var warp := _noise_image(S, 3.0, 2, 159).get_data()
			for k in S * S:
				var u := float(k % S) / S
				var v := float(k / S) / S
				var b := blot[k * bpp] / 255.0
				var amp := smoothstep(0.25, 0.65, mid[k * bpp] / 255.0)
				var ph := TAU * (26.0 * v + 5.0 * u) + (warp[k * bpp] / 255.0 - 0.5) * 11.0
				var r := sin(ph)
				# (a steeper lee side: the crest sits past the middle)
				var crest := 0.5 + 0.5 * sin(ph + 0.6 * r)
				var grain := rng.randf()
				lum[k] = 0.84 + (crest - 0.5) * 0.16 * amp + (b - 0.5) * 0.1 + (grain - 0.5) * 0.09
				hue[k] = 0.5 + (b - 0.5) * 0.9
				hgt[k] = crest * amp * 0.8 + grain * 0.1
			_stamp_stones(S, rng, 260, 1.0, 2.2, 2.4, lum, hue, hgt, 0.62, 0.9)
			bump = 2.6
		"mud":
			for k in S * S:
				var b := blot[k * bpp] / 255.0
				var m := mid[k * bpp] / 255.0
				var f := fine[k * bpp] / 255.0
				var h := clampf(0.5 + (b - 0.5) * 1.5 + (m - 0.5) * 0.7, 0.0, 1.0)
				var grain := rng.randf()
				lum[k] = (0.66 + h * 0.3 + (f - 0.5) * 0.14 + (grain - 0.5) * 0.08) * lerpf(0.78, 1.0, smoothstep(0.3, 0.6, h))
				hue[k] = 0.5 + (m - 0.5) * 0.7
				gloss[k] = 1.0 - smoothstep(0.32, 0.6, h)
				hgt[k] = h * 1.1 + f * 0.2
			_stamp_stones(S, rng, 420, 1.2, 3.2, 2.2, lum, hue, hgt, 0.7, 1.0)
			bump = 3.4
		"ice":
			var cell := FastNoiseLite.new()
			cell.noise_type = FastNoiseLite.TYPE_CELLULAR
			cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
			cell.cellular_jitter = 1.0
			cell.fractal_type = FastNoiseLite.FRACTAL_NONE
			cell.domain_warp_enabled = true
			cell.domain_warp_amplitude = 18.0
			cell.domain_warp_frequency = 0.02
			cell.seed = 163
			cell.frequency = 4.0 / S
			var plates := cell.get_seamless_image(S, S, false, false, 0.1, false).get_data()
			cell.seed = 167
			cell.frequency = 11.0 / S
			var veins := cell.get_seamless_image(S, S, false, false, 0.1, false).get_data()
			var cb := plates.size() / (S * S)
			for k in S * S:
				var b := blot[k * bpp] / 255.0
				var f := fine[k * bpp] / 255.0
				var c := 1.0 - smoothstep(0.0, 0.045, plates[k * cb] / 255.0)
				var c2 := (1.0 - smoothstep(0.0, 0.05, veins[k * cb] / 255.0)) * smoothstep(0.4, 0.7, b) * 0.55
				var crack := maxf(c, c2)
				lum[k] = clampf(0.5 + (b - 0.5) * 1.1 + (f - 0.5) * 0.25, 0.0, 1.0)
				hue[k] = crack
				gloss[k] = mid[k * bpp] / 255.0
				hgt[k] = rng.randf()
			# bubbles: clusters of small white dots frozen in
			for n in 90:
				var cx := rng.randi_range(0, S - 1)
				var cy := rng.randi_range(0, S - 1)
				for j in rng.randi_range(4, 16):
					var k := posmod(cy + int(rng.randfn(0.0, 6.0)), S) * S + posmod(cx + int(rng.randfn(0.0, 6.0)), S)
					lum[k] = minf(1.0, lum[k] + 0.45)
			bump = 1.2
	var cd := PackedByteArray()
	cd.resize(S * S * 4)
	for k in S * S:
		cd[k * 4] = clampi(int(lum[k] * 255.0), 0, 255)
		cd[k * 4 + 1] = clampi(int(hue[k] * 255.0), 0, 255)
		cd[k * 4 + 2] = clampi(int(gloss[k] * 255.0), 0, 255)
		cd[k * 4 + 3] = clampi(int(hgt[k] * 200.0), 0, 255)
	if kind == "ice":
		# (its height for the normal: the cracks, a little cloud)
		for k in S * S:
			hgt[k] = lum[k] * 0.15 - hue[k] * 0.6
	var nimg := Image.create_from_data(S, S, false, Image.FORMAT_RF, hgt.to_byte_array())
	nimg.bump_map_to_normal_map(bump)
	var out := {"map": _tex(Image.create_from_data(S, S, false, Image.FORMAT_RGBA8, cd)), "normal": _tex(nimg)}
	_cache[kind] = out
	return out


## Stamps `count` rounded stones of radius r0..r1 px (most small: the spread's power `pw`) into
## the luminance, hue and height maps, wrapping at the edges: each its own shade (lo..hi) and
## hue, lighter towards one side like a lit dome.
static func _stamp_stones(S: int, rng: RandomNumberGenerator, count: int, r0: float, r1: float, pw: float,
		lum: PackedFloat32Array, hue: PackedFloat32Array, hgt: PackedFloat32Array, lo: float, hi: float) -> void:
	for n in count:
		var cx := rng.randi_range(0, S - 1)
		var cy := rng.randi_range(0, S - 1)
		var r := r0 + pow(rng.randf(), pw) * (r1 - r0)
		var tone := rng.randf_range(lo, hi)
		var h := rng.randf()
		var top := 0.6 + rng.randf() * 0.6
		var ri := ceili(r)
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var d2 := float(dx * dx + dy * dy) / (r * r)
				if d2 > 1.0:
					continue
				var k := posmod(cy + dy, S) * S + posmod(cx + dx, S)
				var dome := sqrt(1.0 - d2)
				lum[k] = tone * (0.86 + 0.14 * dome) - (0.05 if dx + dy > 0 else -0.04) * (1.0 - dome * 0.5)
				hue[k] = h
				hgt[k] = maxf(hgt[k], top * (0.35 + dome * 0.75 * r / 3.0))


## Grey detail noise (multiplies vertex colours of terrain and concrete), linear data.
static func detail() -> ImageTexture:
	if _cache.has("detail"):
		return _cache["detail"]
	var S := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var src := _noise_image(S, 8.0, 4, 3).get_data()
	var bpp := src.size() / (S * S)
	var d := PackedByteArray()
	d.resize(S * S)
	for k in S * S:
		var n := 0.5 + (src[k * bpp] / 255.0 - 0.5) * 0.6
		d[k] = clampi(int(clampf(0.86 + (n - 0.5) * 0.36 + (rng.randf() - 0.5) * 0.08, 0.0, 1.0) * 255.0), 0, 255)
	# stored as sRGB bytes in the JS but used as data (NoColorSpace): the same here
	var img := Image.create_from_data(S, S, false, Image.FORMAT_L8, d)
	img.convert(Image.FORMAT_RGB8)
	var t := _tex(img)
	_cache["detail"] = t
	return t


static func checker() -> ImageTexture:
	if _cache.has("checker"):
		return _cache["checker"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for x in 2:
		for y in 2:
			img.fill_rect(Rect2i(x * 32, y * 32, 32, 32), Color8(0x14, 0x14, 0x14) if (x + y) % 2 else Color8(0xf2, 0xf2, 0xf2))
	var t := _tex(img)
	_cache["checker"] = t
	return t


static func chevron() -> ImageTexture:
	if _cache.has("chevron"):
		return _cache["chevron"]
	var img := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color8(0xd4, 0x23, 0x2b))
	for x0: float in [40.0, 140.0]:
		fill_poly(img, PackedVector2Array([Vector2(x0, 16), Vector2(x0 + 40, 16), Vector2(x0 + 84, 64), Vector2(x0 + 40, 112),
			Vector2(x0, 112), Vector2(x0 + 44, 64)]), Color.WHITE)
	# 6 px stroke around (3, 3, 250, 122)
	for r: Rect2i in [Rect2i(0, 0, 256, 6), Rect2i(0, 122, 256, 6), Rect2i(0, 0, 6, 128), Rect2i(250, 0, 6, 128)]:
		img.fill_rect(r, Color.WHITE)
	var t := _tex(img)
	_cache["chevron"] = t
	return t


## Four fictional sponsor banners in one atlas (rows from the top).
static func banner() -> ImageTexture:
	if _cache.has("banner"):
		return _cache["banner"]
	var img := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	var rows := [
		{"bg": ["#123a8f", "#1d5fd6"], "fg": "#ffffff", "accent": "#ffc83d", "text": "TRACK RUSH"},
		{"bg": ["#f5c400", "#ffd84a"], "fg": "#111111", "accent": "#111111", "text": "NEURO RACING"},
		{"bg": ["#b3121b", "#e3262f"], "fg": "#ffffff", "accent": "#ffffff", "text": "GRIP+ TYRES"},
		{"bg": ["#16181d", "#2a2f39"], "fg": "#ffffff", "accent": "#2ed15a", "text": "FULL THROTTLE"},
	]
	for k in rows.size():
		var r: Dictionary = rows[k]
		var y := k * 128
		_gradient(img, Rect2i(0, y, 1024, 128), Color(r["bg"][1]), Color(r["bg"][0]))
		var acc := Color(r["accent"])
		img.fill_rect(Rect2i(0, y + 112, 1024, 8), acc)
		fill_poly(img, PackedVector2Array([Vector2(40, y + 100), Vector2(90, y + 28), Vector2(120, y + 28), Vector2(70, y + 100)]), acc)
		fill_poly(img, PackedVector2Array([Vector2(904, y + 100), Vector2(954, y + 28), Vector2(984, y + 28), Vector2(934, y + 100)]), acc)
		draw_text(img, r["text"], Vector2(512, y + 62), 88, Color(r["fg"]), 880.0)
	var t := _tex(img)
	_cache["banner"] = t
	return t


## Soft round light pool (white centre fading to black), for additive blending.
static func glow() -> ImageTexture:
	if _cache.has("glow"):
		return _cache["glow"]
	var S := 128
	var d := PackedByteArray()
	d.resize(S * S)
	for y in S:
		for x in S:
			var r := Vector2(x + 0.5 - 64.0, y + 0.5 - 64.0).length() / 64.0
			var a := 0.0
			if r < 0.35:
				a = lerpf(1.0, 0.55, r / 0.35)
			elif r < 1.0:
				a = lerpf(0.55, 0.0, (r - 0.35) / 0.65)
			d[y * S + x] = int(a * 255.0)
	var img := Image.create_from_data(S, S, false, Image.FORMAT_L8, d)
	img.convert(Image.FORMAT_RGB8)
	var t := _tex(img)
	_cache["glow"] = t
	return t


## Tileable ripple normals for the sea (24 m a tile).
static func water_normal() -> ImageTexture:
	if _cache.has("water"):
		return _cache["water"]
	var S := 256
	var a := _noise_image(S, 5.0, 4, 91).get_data()
	var b := _noise_image(S, 12.0, 3, 92).get_data()
	var bpa := a.size() / (S * S)
	var bpb := b.size() / (S * S)
	var hgt := PackedFloat32Array()
	hgt.resize(S * S)
	for k in S * S:
		hgt[k] = (0.5 + (a[k * bpa] / 255.0 - 0.5) * 0.6) + 0.4 * (0.5 + (b[k * bpb] / 255.0 - 0.5) * 0.6)
	var img := Image.create_from_data(S, S, false, Image.FORMAT_RF, hgt.to_byte_array())
	img.bump_map_to_normal_map(12.0)
	var t := _tex(img)
	_cache["water"] = t
	return t


## Gate banners for one track: one 128 px row per gate ({kind: "start" | "cp", label}).
static func gate_atlas(defs: Array) -> ImageTexture:
	var RH := 128
	var img := Image.create(1024, RH * defs.size(), false, Image.FORMAT_RGBA8)
	for k in defs.size():
		var d: Dictionary = defs[k]
		var y := k * RH
		_gradient(img, Rect2i(0, y, 1024, RH), Color("#2a2f3a"), Color("#10131a"))
		if d["kind"] == "start":
			for x in 6:
				for r in 4:
					var c := Color("#111111") if (x + r) % 2 else Color("#f4f4f4")
					img.fill_rect(Rect2i(x * 21, y + r * 32, 21, 32), c)
					img.fill_rect(Rect2i(1024 - 126 + x * 21, y + r * 32, 21, 32), c)
		else:
			var cy := Color("#19d3ff")
			img.fill_rect(Rect2i(0, y, 24, RH), cy)
			img.fill_rect(Rect2i(1000, y, 24, RH), cy)
			img.fill_rect(Rect2i(36, y + 20, 8, RH - 40), cy)
			img.fill_rect(Rect2i(980, y + 20, 8, RH - 40), cy)
		draw_text(img, d["label"], Vector2(512, y + RH / 2.0 + 3.0), 86 if d["kind"] == "start" else 80, Color.WHITE, 740.0)
	return _tex(img)


# ---- drawing helpers ---------------------------------------------------------

## Vertical gradient from `top` to `bottom` over rect r.
static func _gradient(img: Image, r: Rect2i, top: Color, bottom: Color) -> void:
	for j in r.size.y:
		img.fill_rect(Rect2i(r.position.x, r.position.y + j, r.size.x, 1), top.lerp(bottom, (j + 0.5) / r.size.y))


## Fills a polygon (4 samples a pixel for soft edges).
static func fill_poly(img: Image, pts: PackedVector2Array, c: Color) -> void:
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var subs := [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]
	for y in range(maxi(0, floori(lo.y)), mini(img.get_height(), ceili(hi.y))):
		for x in range(maxi(0, floori(lo.x)), mini(img.get_width(), ceili(hi.x))):
			var cov := 0
			for s: Vector2 in subs:
				if Geometry2D.is_point_in_polygon(Vector2(x, y) + s, pts):
					cov += 1
			if cov > 0:
				var dst := img.get_pixel(x, y)
				img.set_pixel(x, y, dst.lerp(Color(c.r, c.g, c.b, 1.0), cov / 4.0))


static var _font_var: FontVariation = null


## The banner font: Barlow Condensed Bold, emboldened and slanted ("italic 900").
## Italic slant of the drawn text (x shift per pixel of height).
const SLANT := 0.21


static func font() -> Font:
	if _font_var == null:
		var base: Font = null
		if ResourceLoader.exists(FONT_PATH):
			base = load(FONT_PATH) as Font
		if base == null and FileAccess.file_exists(FONT_PATH):
			var ff := FontFile.new()
			if ff.load_dynamic_font(FONT_PATH) == OK:
				base = ff
		if base == null:
			base = ThemeDB.fallback_font
		_font_var = FontVariation.new()
		_font_var.base_font = base
		_font_var.variation_embolden = 0.55
	return _font_var


## Draws `text` centred on `center` (cap height centred, like textBaseline "middle"),
## shrunk to fit max_width. Glyphs are rendered into the font cache and blended in.
static func draw_text(img: Image, text: String, center: Vector2, size: int, color: Color, max_width := 1e9) -> void:
	var ts := TextServerManager.get_primary_interface()
	var f := font()
	var line := TextLine.new()
	line.add_string(text, f, size)
	var w := line.get_line_width()
	if w > max_width:
		size = int(size * max_width / w)
		line = TextLine.new()
		line.add_string(text, f, size)
		w = line.get_line_width()
	var rid := line.get_rid()
	var ascent := ts.shaped_text_get_ascent(rid)
	var descent := ts.shaped_text_get_descent(rid)
	# baseline so that the middle of the em box sits on center.y
	var pen := Vector2(center.x - w / 2.0, center.y + (ascent - descent) / 2.0 - size * 0.06)
	var glyphs: Array = ts.shaped_text_get_glyphs(rid)
	var src_cache: Dictionary = {}
	for g: Dictionary in glyphs:
		var frid: RID = g["font_rid"]
		var gi: int = g["index"]
		var fs := Vector2i(int(g["font_size"]), 0)
		var at := pen + (g["offset"] as Vector2)
		pen.x += float(g["advance"])
		if not frid.is_valid():
			continue
		ts.font_render_glyph(frid, fs, gi)
		var tex_idx := ts.font_get_glyph_texture_idx(frid, fs, gi)
		if tex_idx < 0:
			continue
		var uv := ts.font_get_glyph_uv_rect(frid, fs, gi)
		var off := ts.font_get_glyph_offset(frid, fs, gi)
		var gsize := ts.font_get_glyph_size(frid, fs, gi)
		if uv.size.x <= 0.0 or uv.size.y <= 0.0:
			continue
		var key := "%s:%d" % [frid.get_id(), tex_idx]
		if not src_cache.has(key):
			var im := ts.font_get_texture_image(frid, fs, tex_idx)
			if im == null:
				continue
			im = im.duplicate()
			if im.is_compressed():
				im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			src_cache[key] = im
		var src: Image = src_cache[key]
		var region := Rect2i(Vector2i(uv.position.round()), Vector2i(uv.size.round()))
		var glyph := src.get_region(region)
		# white glyph with coverage in alpha: tint it, then blend at the glyph's spot
		var tinted := Image.create(glyph.get_width(), glyph.get_height(), false, Image.FORMAT_RGBA8)
		tinted.fill(Color(color.r, color.g, color.b, 0.0))
		var gd := glyph.get_data()
		var td := tinted.get_data()
		for p in range(0, gd.size(), 4):
			td[p + 3] = gd[p + 3]
		tinted.set_data(glyph.get_width(), glyph.get_height(), false, Image.FORMAT_RGBA8, td)
		var dst := Vector2i((at + off).round())
		if gsize.x > 0.0 and absf(gsize.x - region.size.x) > 1.0:
			tinted.resize(int(gsize.x), int(gsize.y), Image.INTERPOLATE_BILINEAR)
		# italic (the canvas font is "italic 900"): each row slides right by SLANT x its height
		# above the baseline (the glyph cache ignores a FontVariation transform)
		var rise := at.y - dst.y
		for r in tinted.get_height():
			var shift := roundi(SLANT * (rise - r))
			img.blend_rect(tinted, Rect2i(0, r, tinted.get_width(), 1), dst + Vector2i(shift, r))
