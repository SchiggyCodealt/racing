class_name World
extends Node3D
## world.gd
## ------------------------------------------------------------------
## The 3D world of a race (the Godot side of the web game's scene.js plus
## the track handling of main.js): sky, sun, fog, tone mapping, bloom,
## environment light, the graphics quality level and the track with its
## scenery. Cars, ghosts, effects and the camera are added by the modes.
##
## Use:
##   var world := World.build(track, "high")   # a BuiltTrack (sim/), quality high | medium | low
##   add_child(world)                          # (or World.new(), then show_track(track))
##   world.set_checkpoint_state(k, "next")     # "next" | "passed" | "idle"
##   world.set_quality("low")                  # any time; auto_quality steps it down by itself
##   world.render_stats()                      # draw calls, primitives, quality, build ms
##   # switching tracks without a hitch: build the track in a WorkerThreadPool task, then
##   var node := World.build_track_node(track)  # (in the task)
##   world.show_track(track, node)              # (back on the main thread)
##
## What Godot does for the hand-made WebGL parts:
##   - sky: a sky shader (world/shaders/sky.gdshader). Its cubemap pass is the
##     theme's environment (sky x env, ground below, hemisphere light), so
##     ambient light and reflections come from it like the PMREM map did.
##   - ACES tone mapping with the theme's exposure, depth fog (linear from
##     near to far, the sky unfogged), glow for the bloom (high only).
##   - the sun is a DirectionalLight3D with split shadow maps that follow
##     the camera (no shadow box to steer; focus_shadows() is kept as a no-op
##     for the modes that call it), SSAO on high.
##   - quality: render scale and MSAA instead of the pixel ratio, shadow map
##     size and distance, scenery share and shadows, grass, sparks.
##
## Light units: Godot multiplies a light's energy by PI, Three.js does not,
## so the sun energy is the theme intensity / PI; emissive values and the
## exposure carry over as they are.

signal quality_changed(level: String)

const Themes = preload("res://world/themes.gd")
const SKY_SHADER = preload("res://world/shaders/sky.gdshader")
const TrackMeshScript = preload("res://world/track_mesh.gd")
const Effects = preload("res://world/car_effects.gd")

## Step the quality down by itself when frames are slow (as the web game's governor).
@export var auto_quality := false

var theme_name := ""
var theme: Dictionary = {}
var quality := "high"
var track: BuiltTrack = null
## The track's 3D node (world/track_mesh.gd), null until show_track().
var track_node: TrackMeshScript = null

var env: Environment
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var sun_dir := Vector3(0.5, 0.8, 0.3).normalized()

var _cloud_clock := 0.0
var _frames := PackedFloat32Array()
var _slow_run := 0
var _last_ms := 0
var _build_ms := 0


func _init() -> void:
	name = "World"
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 16.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_aerial_perspective = 0.0
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_bloom = 0.0
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.0
	world_env = WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)

	set_theme("meadow")
	_apply_quality()


## A world showing `track` with its theme, at graphics quality `level`.
static func build(p_track: BuiltTrack, level := "high") -> World:
	var w := World.new()
	w.quality = level if Themes.QUALITY.has(level) else "high"
	w._apply_quality()
	w.show_track(p_track)
	return w


func _enter_tree() -> void:
	_apply_viewport()


func _process(delta: float) -> void:
	# drift the clouds (high and medium; low keeps a still sky)
	if quality != "low":
		_cloud_clock = fmod(_cloud_clock + delta, 100000.0)
		sky_mat.set_shader_parameter("cloud_time", _cloud_clock)
	if auto_quality:
		_govern()


# ---- theme --------------------------------------------------------------------

## Switch sky, light, fog, environment and bloom to a theme ("meadow" if unknown).
func set_theme(p_name: String) -> void:
	var key := p_name if Themes.THEMES.has(p_name) else "meadow"
	if key == theme_name:
		return
	theme_name = key
	theme = Themes.THEMES[key]
	var th := theme
	sun_dir = Themes.sun_direction(th)
	var s: Dictionary = th["sky"]
	sky_mat.set_shader_parameter("zenith", Themes.col(s["zenith"]))
	sky_mat.set_shader_parameter("horizon", Themes.col(s["horizon"]))
	sky_mat.set_shader_parameter("below", Themes.col(th["fog"]["color"]))
	sky_mat.set_shader_parameter("ground", Themes.col(s["below"]))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("sun_color", Themes.col(th["sun"]["color"]))
	sky_mat.set_shader_parameter("cloud_cover", s["clouds"])
	sky_mat.set_shader_parameter("cloud_lit", Themes.col(s["cloudLit"]))
	sky_mat.set_shader_parameter("cloud_shade", Themes.col(s["cloudShade"]))
	sky_mat.set_shader_parameter("haze", s["haze"])
	sky_mat.set_shader_parameter("stars", s.get("stars", 0.0))
	sky_mat.set_shader_parameter("aurora", s.get("aurora", 0.0))
	sky_mat.set_shader_parameter("aurora_color", Themes.col(s.get("auroraColor", 0x33ff9a)))
	sky_mat.set_shader_parameter("aurora_edge", Themes.col(s.get("auroraEdge", 0x8a4dff)))
	sky_mat.set_shader_parameter("env", th["env"])
	sky_mat.set_shader_parameter("hemi_sky", Themes.col(th["hemi"]["sky"]))
	sky_mat.set_shader_parameter("hemi_ground", Themes.col(th["hemi"]["ground"]))
	sky_mat.set_shader_parameter("hemi", float(th["hemi"]["intensity"]) / PI)

	env.fog_light_color = Themes.col(th["fog"]["color"])
	env.fog_depth_begin = th["fog"]["near"]
	env.fog_depth_end = th["fog"]["far"]
	env.tonemap_exposure = th["exposure"]
	var b: Dictionary = th["bloom"]
	# UnrealBloom (strength, radius, threshold) -> glow: intensity, spread over the levels, HDR threshold
	env.glow_intensity = float(b["strength"]) * 1.6
	env.glow_strength = 1.0
	env.glow_hdr_threshold = b["threshold"]
	env.glow_hdr_scale = 2.0
	var r := float(b["radius"])
	for lv in 7:
		env.set_glow_level(lv, 0.0)
	env.set_glow_level(1, 1.0 - r * 0.5)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6 + r)
	env.set_glow_level(4, r * 1.2)
	env.set_glow_level(5, r * 0.8)

	sun.light_color = Themes.col(th["sun"]["color"])
	sun.light_energy = float(th["sun"]["intensity"]) / PI
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.BACK)


# ---- quality ------------------------------------------------------------------

## "high" | "medium" | "low". Set auto_quality = false as well to pin it.
func set_quality(level: String) -> void:
	if not Themes.QUALITY.has(level) or level == quality:
		return
	quality = level
	_apply_quality()
	quality_changed.emit(level)


func _apply_quality() -> void:
	var q := Themes.get_quality(quality)
	env.glow_enabled = q["bloom"]
	env.ssao_enabled = q["ssao"]
	var splits: int = q["splits"]
	sun.directional_shadow_mode = (DirectionalLight3D.SHADOW_ORTHOGONAL if splits == 1
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if splits == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	sun.directional_shadow_max_distance = q["shadow_dist"]
	RenderingServer.directional_shadow_atlas_set_size(q["shadow"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality == "high" else RenderingServer.SHADOW_QUALITY_SOFT_LOW
		if quality == "medium" else RenderingServer.SHADOW_QUALITY_HARD)
	Effects.spark_share = q["sparks"]
	if track_node != null:
		track_node.apply_quality(q)
	_apply_viewport()


func _apply_viewport() -> void:
	if not is_inside_tree():
		return
	var q := Themes.get_quality(quality)
	var vp := get_viewport()
	vp.scaling_3d_scale = q["scale"]
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][[0, 2, 4].find(q["msaa"])]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if int(q["msaa"]) > 0 else Viewport.SCREEN_SPACE_AA_FXAA


## Step the quality down when most frames over ~2 s were slower than ~55 fps,
## or at once after five frames in a row of over 250 ms (scene.js _govern).
func _govern() -> void:
	var now := Time.get_ticks_msec()
	var gap := float(now - _last_ms)
	_last_ms = now
	if gap > 250.0:
		_frames.clear()
		_slow_run = _slow_run + 1 if gap < 15000.0 else 0
		if _slow_run >= 5:
			_slow_run = 0
			_step_down()
		return
	_slow_run = 0
	_frames.append(gap)
	if _frames.size() < 120:
		return
	var slow := 0
	for t in _frames:
		if t > 18.5:
			slow += 1
	_frames.clear()
	if slow > 80:
		_step_down()


func _step_down() -> void:
	var i := Themes.QUALITY_ORDER.find(quality)
	if i >= 0 and i < Themes.QUALITY_ORDER.size() - 1:
		set_quality(Themes.QUALITY_ORDER[i + 1])
		print("Track Rush: graphics quality lowered to \"%s\" to keep the frame rate up." % quality)


# ---- track --------------------------------------------------------------------

## Show `p_track` (rebuilt only when it changes): its theme and its 3D track.
func show_track(p_track: BuiltTrack, prebuilt: TrackMeshScript = null) -> TrackMeshScript:
	if p_track == track and track_node != null:
		return track_node
	if track_node != null:
		track_node.queue_free()
		track_node = null
	track = p_track
	if p_track == null:
		return null
	set_theme(p_track.theme)
	var t0 := Time.get_ticks_msec()
	track_node = prebuilt if prebuilt != null else TrackMeshScript.build(p_track)
	_build_ms = int(track_node.stats.get("build_ms", 0)) if prebuilt != null else Time.get_ticks_msec() - t0
	add_child(track_node)
	track_node.apply_quality(Themes.get_quality(quality))
	return track_node


## Builds the 3D track for show_track(track, node) without touching the scene: safe in a
## WorkerThreadPool task, so a menu can switch tracks without a hitch (the build is about
## 1 s of GDScript; World.build itself also runs in a task, the node joins the tree after).
static func build_track_node(p_track: BuiltTrack) -> TrackMeshScript:
	return TrackMeshScript.build(p_track)


## Colour a checkpoint gate: "next" (cyan), "passed" (green) or "idle".
func set_checkpoint_state(k: int, state: String) -> void:
	if track_node != null:
		track_node.set_checkpoint_state(k, state)


## Kept for the modes ported from the web game: the split shadow maps follow the camera.
func focus_shadows(_x: float, _y: float, _z: float) -> void:
	pass


## Draw calls, primitives and objects of the last frame (whole viewport), the quality and track build time.
func render_stats() -> Dictionary:
	return {
		"calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		# the same split into the camera pass and the sun's shadow maps
		"visible_calls": _vp_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives": _vp_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_calls": _vp_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_primitives": _vp_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"quality": quality,
		"build_ms": _build_ms,
		"track_stats": track_node.stats if track_node != null else {},
	}


func _vp_info(type: Viewport.RenderInfoType, info: Viewport.RenderInfo) -> int:
	return get_viewport().get_render_info(type, info) if is_inside_tree() else 0
