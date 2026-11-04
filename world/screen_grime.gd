class_name ScreenGrime
extends CanvasLayer
## screen_grime.gd (v6.10)
## ------------------------------------------------------------------
## Mud and snow on the screen, in place of v6.3's camera rumble on loose ground:
##   dirt: splats of mud (some run down in a drip) and a film of dried mud and specks
##         creeping in from the corners and the bottom edge;
##   snow: flecks of snow that melt into clear drops, and frost growing in from the corners;
##   both: a few clods or flakes flying past close to the camera.
## It builds with speed, with sliding and with the dust or spray of a car close ahead
## (ahead_of()); on asphalt it stops building, the drops slide outward in the wind and
## everything fades within a couple of seconds. Nothing is ever drawn inside the keep-out
## ellipse around the middle of the screen (KEEP_C, KEEP_R), so the road ahead stays readable:
## the splats are placed and kept outside it, the flyers start on its edge and leave the screen,
## and the film and frost stop at it (world/shaders/screen_film.gdshader).
## Graphics quality scales the number of splats and flyers (CarEffects.spark_share); the
## Settings row "Screen dirt and snow" (setting "grime", on by default) switches it off
## (ScreenGrime.enabled, set by game/app.gd).
##
## How much each surface throws at the screen is its "grime" (sim/surfaces.gd, a look column),
## by its kind of "dust": "dust" makes mud, "snow" makes snow.
##
## Usage (modes/play_mode.gd; only on a track with dirt or snow):
##   var g := ScreenGrime.new(track)
##   add_child(g)
##   g.update(dt, pose, track, ScreenGrime.ahead_of(pose, other_pose, track))  # every drawn frame
##   g.clear()                                                                # restart / respawn

const SPLAT_SHADER = preload("res://world/shaders/screen_splat.gdshader")
const FILM_SHADER = preload("res://world/shaders/screen_film.gdshader")
const Tex = preload("res://world/textures.gd")

## Below the interface (ui/ui_root.gd is layer 10).
const LAYER := 4
## The keep-out ellipse: centre and radii as fractions of the screen's width and height.
const KEEP_C := Vector2(0.5, 0.5)
const KEEP_R := Vector2(0.34, 0.31)
## Splats and flyers at High quality (fewer at lower quality, by CarEffects.spark_share).
const MAX_SPLATS := 40
const MAX_FLYERS := 12
## New splats a second at full grime, and flyers a second at full grime and 40 m/s.
const SPLAT_RATE := 8.0
const FLY_RATE := 6.0
## A splat's life in seconds on loose ground; off it, they age AGE_OFF times faster.
const LIFE_MIN := 3.0
const LIFE_MAX := 6.5
const AGE_OFF := 3.0
## Splat radius in pixels at 720 lines (mud, snow), the smallest and the largest.
const MUD_SIZE := Vector2(14.0, 46.0)
const SNOW_SIZE := Vector2(14.0, 44.0)
## A car this far ahead (m) or nearer, in your lane, throws its dust or spray at the camera.
const AHEAD_FAR := 28.0

## Off switch (the "grime" setting).
static var enabled := true

static var _GRIME: PackedFloat64Array = Surfaces.column("grime")


class Blob:
	var pos := Vector2.ZERO   # px
	var vel := Vector2.ZERO   # px/s (flyers)
	var size := 0.0           # radius, px
	var kind := 0             # 0 mud, 1 snow, 2 flying clod or flake
	var seed := 0.0
	var age := 0.0
	var life := 1.0
	var drip := 0.0           # mud: how far its drip ran 0..1; snow: how far it melted 0..1
	var drip_rate := 0.0
	var col := Color.WHITE


## How strongly mud (x) and snow (y) build up now (0..1.2, smoothed).
var level := Vector2.ZERO
## The film of mud and the frost (0..1, slow).
var film := 0.0
var frost := 0.0
var rng := RandomNumberGenerator.new()

var _blobs: Array[Blob] = []
var _acc := 0.0
var _fly_acc := 0.0
var _mm := MultiMesh.new()
var _mmi := MultiMeshInstance2D.new()
var _rect := ColorRect.new()
var _film_mat := ShaderMaterial.new()
var _mud_col := Color(0.3, 0.22, 0.15)
var _snow_col := Color(0.95, 0.97, 1.0)


## `track`: picks the mud's colour from its dirt (optional).
func _init(track: BuiltTrack = null) -> void:
	layer = LAYER
	name = "ScreenGrime"
	rng.seed = 7
	for s in Surfaces.count():
		var d: Dictionary = Surfaces.def(s)
		if d.dust == "dust" and (track == null or _has_surface(track, s)):
			_mud_col = Color.html(d.road).darkened(0.42)
			break
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_film_mat.shader = FILM_SHADER
	_film_mat.set_shader_parameter("mud_color", _mud_col)
	_film_mat.set_shader_parameter("keep", Vector4(KEEP_C.x, KEEP_C.y, KEEP_R.x, KEEP_R.y))
	_film_mat.set_shader_parameter("noise", Tex.loose().map)
	_rect.material = _film_mat
	_rect.visible = false
	add_child(_rect)
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _quad()
	_mm.instance_count = MAX_SPLATS + MAX_FLYERS
	_mm.visible_instance_count = 0
	_mmi.multimesh = _mm
	var m := ShaderMaterial.new()
	m.shader = SPLAT_SHADER
	_mmi.material = m
	add_child(_mmi)


static func _has_surface(t: BuiltTrack, s: int) -> bool:
	var n := t.surf_n
	if n <= s:
		return false
	for i in t.count:
		if t.surf_w[i * n + s] > 0.0:
			return true
	return false


## A unit quad (-0.5..0.5) with UVs 0..1, y down.
static func _quad() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## How much mud (x) and snow (y) the ground at sample idx throws up (the surfaces' "grime").
static func ground(tr: BuiltTrack, idx: int) -> Vector2:
	if tr == null or tr.surf_w.is_empty() or idx < 0:
		return Vector2.ZERO
	var n := tr.surf_n
	var i := clampi(idx, 0, tr.count - 1)
	var out := Vector2.ZERO
	for s in n:
		var w := tr.surf_w[i * n + s] * _GRIME[s]
		var kind: String = Surfaces.def(s).dust
		if kind == "dust":
			out.x += w
		elif kind == "snow":
			out.y += w
	return out


## How much of the dust (x) or spray (y) of `other` reaches the camera behind `me`: a car on
## loose ground at speed, ahead within AHEAD_FAR m and roughly in the same lane.
static func ahead_of(me: CarEffects.Pose, other: CarEffects.Pose, tr: BuiltTrack) -> Vector2:
	if other == null or not other.grounded:
		return Vector2.ZERO
	var dx := other.x - me.x
	var dz := other.z - me.z
	var along := dx * sin(me.yaw) + dz * cos(me.yaw)
	var lat := absf(dx * cos(me.yaw) - dz * sin(me.yaw))
	if along < 1.5 or along > AHEAD_FAR:
		return Vector2.ZERO
	var f := (1.0 - smoothstep(6.0, AHEAD_FAR, along)) * (1.0 - smoothstep(1.8, 4.5, lat)) * smoothstep(8.0, 30.0, other.speed)
	return ground(tr, other.idx) * f


## The screen size in canvas pixels.
func screen() -> Vector2:
	if is_inside_tree():
		return get_viewport().get_visible_rect().size
	return Vector2(1280, 720)


## How far a circle (centre px, radius px) is from the keep-out ellipse: >= 1 outside it.
func keep_metric(p: Vector2, r: float) -> float:
	var s := screen()
	var q := Vector2((p.x - KEEP_C.x * s.x) / (KEEP_R.x * s.x + r), (p.y - KEEP_C.y * s.y) / (KEEP_R.y * s.y + r))
	return q.length()


## How far a splat or flyer reaches from its centre as drawn (px).
func reach(b: Blob) -> float:
	if b.kind == 2:
		return b.size * (1.0 + b.age * 6.0) * (1.0 + b.vel.length() / 350.0)
	return b.size


## Splats (mud and snow) on the screen now.
func count() -> int:
	var n := 0
	for b in _blobs:
		if b.kind != 2:
			n += 1
	return n


func flyer_count() -> int:
	return _blobs.size() - count()


## The splats and flyers (read only: tests).
func blobs() -> Array[Blob]:
	return _blobs


## Everything off the screen (restart, respawn, the setting switched off).
func clear() -> void:
	_blobs.clear()
	level = Vector2.ZERO
	film = 0.0
	frost = 0.0
	_acc = 0.0
	_fly_acc = 0.0
	_mm.visible_instance_count = 0
	_rect.visible = false


## One drawn frame: `car` is the car the camera follows (between the last two steps), `ahead`
## what a car in front throws at the camera (ahead_of()).
func update(dt: float, car: CarEffects.Pose, track: BuiltTrack, ahead := Vector2.ZERO) -> void:
	dt = clampf(dt, 0.0, 0.1)
	if not enabled:
		if visible:
			clear()
			visible = false
		return
	visible = true
	var s := screen()
	var k := s.y / 720.0
	# how hard it builds: speed and sliding on loose ground, the car ahead
	var g := ground(track, car.idx) if car.grounded else Vector2.ZERO
	var slip := car.slip if car.has_slip else clampf((absf(car.side_speed) - 4.0) / 6.0, 0.0, 1.0)
	var drive := smoothstep(4.0, 32.0, car.speed) * 0.75 + slip * 0.7 * minf(1.0, car.speed / 8.0)
	var target := (g * drive + ahead).clamp(Vector2.ZERO, Vector2(1.2, 1.2))
	level += (target - level) * (1.0 - exp(-dt * 2.5))
	var mud_to := minf(1.0, level.x)
	var frost_to := minf(1.0, level.y * 1.2)
	film += (mud_to - film) * (1.0 - exp(-dt * (0.45 if mud_to > film else 0.9)))
	frost += (frost_to - frost) * (1.0 - exp(-dt * (0.35 if frost_to > frost else 0.8)))
	if film < 0.01 and mud_to < 0.01:
		film = 0.0
	if frost < 0.01 and frost_to < 0.01:
		frost = 0.0
	# new splats and flyers (fewer at lower quality)
	var share := CarEffects.spark_share
	var sum := level.x + level.y
	if sum > 0.04:
		_acc += dt * SPLAT_RATE * sum * share
		var fly := smoothstep(10.0, 40.0, car.speed)
		_fly_acc += dt * FLY_RATE * minf(1.0, sum) * fly * share
	else:
		_acc = 0.0
		_fly_acc = 0.0
	var cap := maxi(3, roundi(MAX_SPLATS * share))
	var fcap := maxi(2, roundi(MAX_FLYERS * share))
	while _acc >= 1.0:
		_acc -= 1.0
		if count() < cap:
			_spawn_splat(rng.randf() * sum < level.x, s, k)
	while _fly_acc >= 1.0:
		_fly_acc -= 1.0
		if flyer_count() < fcap:
			_spawn_flyer(rng.randf() * sum < level.x, s, k)
	# age, drip, melt, slide in the wind, fade
	var loose := target.x + target.y > 0.05
	var wind := clampf(car.speed / 50.0, 0.0, 1.0)
	var c := KEEP_C * s
	var i := 0
	while i < _blobs.size():
		var b := _blobs[i]
		if b.kind == 2:
			b.age += dt
			b.vel *= 1.0 + 3.5 * dt
			b.pos += b.vel * dt
			if b.age > b.life or b.pos.x < -40.0 or b.pos.y < -40.0 or b.pos.x > s.x + 40.0 or b.pos.y > s.y + 40.0:
				_blobs.remove_at(i)
				continue
		else:
			b.age += dt * (1.0 if loose else AGE_OFF)
			if b.age >= b.life:
				_blobs.remove_at(i)
				continue
			var out := (b.pos - c).normalized()
			if b.kind == 0:
				if b.age > 0.5:
					b.drip = minf(1.0, b.drip + b.drip_rate * dt)
				b.pos += out * wind * 6.0 * k * dt
			else:
				b.drip = smoothstep(0.35, 0.8, b.age / b.life) # melting
				b.pos += (out * wind * (8.0 + 30.0 * b.drip) + Vector2(0.0, 10.0 * b.drip)) * k * dt
			# never into the middle (gravity could pull a drop in from above)
			var m := keep_metric(b.pos, b.size)
			if m < 1.0:
				b.pos = c + (b.pos - c) / maxf(m, 0.05) * 1.001 + out * b.size
		i += 1
	_refresh()


func _spawn_splat(mud: bool, s: Vector2, k: float) -> void:
	var b := Blob.new()
	b.kind = 0 if mud else 1
	var sz := MUD_SIZE if mud else SNOW_SIZE
	b.size = lerpf(sz.x, sz.y, pow(rng.randf(), 1.7)) * k
	# mostly low and at the sides (thrown up from the wheels), outside the keep-out ellipse
	for tries in 12:
		var p := Vector2(rng.randf() * s.x, (1.0 - pow(rng.randf(), 2.4)) * s.y)
		if keep_metric(p, b.size) >= 1.0:
			b.pos = p
			break
	if b.pos == Vector2.ZERO:
		b.pos = Vector2(rng.randf() * s.x, s.y - b.size)
	b.seed = rng.randf()
	b.life = rng.randf_range(LIFE_MIN, LIFE_MAX)
	b.drip_rate = rng.randf_range(0.12, 0.35) if mud and rng.randf() < 0.6 and b.size > 14.0 * k else 0.0
	if mud:
		var v := rng.randf_range(0.8, 1.15)
		b.col = Color(_mud_col.r * v, _mud_col.g * v, _mud_col.b * v)
	else:
		b.col = _snow_col
	_blobs.append(b)


func _spawn_flyer(mud: bool, s: Vector2, k: float) -> void:
	var b := Blob.new()
	b.kind = 2
	# from the edge of the keep-out ellipse, mostly its lower half, straight out
	var a := rng.randf_range(-0.35, PI + 0.35) if rng.randf() < 0.8 else rng.randf_range(PI, TAU)
	var dir := Vector2(cos(a), sin(a))
	b.size = rng.randf_range(2.5, 5.0) * k
	b.vel = dir * rng.randf_range(0.5, 1.1) * s.y
	b.pos = KEEP_C * s + Vector2(dir.x * KEEP_R.x * s.x, dir.y * KEEP_R.y * s.y)
	while keep_metric(b.pos, reach(b)) < 1.02:
		b.pos += dir * 2.0
	b.life = 0.9
	b.seed = rng.randf()
	b.col = _mud_col.darkened(0.2) if mud else _snow_col
	_blobs.append(b)


func _refresh() -> void:
	var n := 0
	for b in _blobs:
		var a := 1.0
		var xf: Transform2D
		var drip := b.drip
		if b.kind == 2:
			# grows and stretches as it comes closer
			var len := reach(b)
			xf = Transform2D(b.vel.angle(), Vector2(len * 2.0, b.size * (1.0 + b.age * 6.0) * 2.0), 0.0, b.pos)
			a = 0.85
		else:
			var pop := minf(1.0, b.age / 0.07)
			var d := b.size * 2.0 * (0.6 + 0.4 * pop)
			xf = Transform2D(0.0, Vector2(d, d), 0.0, b.pos)
			a = 1.0 - smoothstep(0.65, 1.0, b.age / b.life)
		_mm.set_instance_transform_2d(n, xf)
		_mm.set_instance_color(n, Color(b.col.r, b.col.g, b.col.b, a))
		_mm.set_instance_custom_data(n, Color(b.seed, b.kind / 3.0, drip, 0.0))
		n += 1
	_mm.visible_instance_count = n
	_rect.visible = film > 0.0 or frost > 0.0
	if _rect.visible:
		var s := screen()
		_film_mat.set_shader_parameter("mud", film)
		_film_mat.set_shader_parameter("frost", frost)
		_film_mat.set_shader_parameter("aspect", s.x / maxf(1.0, s.y))
