class_name Podium
extends Node3D
## podium.gd (v6.13.0): the podium at the end of a field race (modes/field_mode.gd).
## ------------------------------------------------------------------
## Three blocks on the road of the start straight (the grid's stretch, which every track keeps straight
## and clear), across the road: 2nd on the left, 1st in the middle and highest, 3rd on the right (seen
## from the camera, which stands further up the road looking back), gold, silver and bronze with their
## number on the front, on a dark plinth; the top three cars stand on them turned a little towards the
## camera, each with its driver's name above it. A slow camera move goes round the front. Cheap: four
## boxes, three number labels and three name labels; the cars are the race's own models, moved here.
##
##   var p := Podium.new(track, sample)        # world.add_child(p)
##   p.put(place, model, name, color)          # place 1..3: the car model and the name above it
##   p.has(place), p.clear()
##   p.put_trophy(place)                       # (v6.14) the cup's trophy on block `place` (world/trophy.gd:
##                                             # gold, silver, bronze), in front of its car
##   p.camera                                  # make_current() to look at it; update(dt) moves it
##   p.view_shift                              # 0..0.5 of the view's width the podium sits left of
##                                             # the middle (the finish panel docks on the right)

const BLOCK_W := 3.4      # m across the road, each
const BLOCK_D := 5.8      # m along it
const HEIGHTS := [1.25, 0.85, 0.55]   # 1st, 2nd, 3rd
const GAP := 0.25
const COLORS := [Color("#d9b23a"), Color("#c3c7cf"), Color("#c0773a")]
const CAM_DIST := 15.5
const CAM_H := 4.2
const TURN := 0.38        # rad the cars are turned towards the camera's side
const ORBIT := 0.32       # rad the camera swings either way
const ORBIT_SPEED := 0.12 # rad/s

var camera: Camera3D
## Share of the view's width the podium sits left of the middle.
var view_shift := 0.18
var spots: Array[Transform3D] = []
var _t := 0.0
var _base: Transform3D
var _names: Array[Label3D] = []
var _filled := [false, false, false]
var _trophies: Array = [null, null, null]
var _xs: Array = []
## (v6.14) the trophies' heights (1st, 2nd, 3rd) and where they stand on their block (m from its middle:
## across, towards the outside; along, towards the camera)
const TROPHY_H := [1.15, 1.0, 0.9]
const TROPHY_X := [1.15, -1.05, 1.05]
const TROPHY_Z := 2.35


## True when place `place` (1..3) has its car.
func has(place: int) -> bool:
	return place >= 1 and place <= 3 and bool(_filled[place - 1])


## Empty blocks again (a new race).
func clear() -> void:
	_filled = [false, false, false]
	for nm in _names:
		nm.text = ""
	for k in 3:
		if _trophies[k] != null and is_instance_valid(_trophies[k]):
			(_trophies[k] as Node).queue_free()
		_trophies[k] = null


## (v6.14) The cup's trophy on block `place` (1..3), in front of the car on it.
func put_trophy(place: int) -> void:
	if place < 1 or place > 3 or _trophies[place - 1] != null:
		return
	var k := place - 1
	var t := Trophy.new(Cups.trophy(place), TROPHY_H[k])
	t.position = Vector3(float(_xs[k]) + float(TROPHY_X[k]), 0.18 + float(HEIGHTS[k]), TROPHY_Z)
	t.rotation.y = -0.25 * signf(float(TROPHY_X[k]))
	add_child(t)
	_trophies[k] = t


## (v6.14) The trophy on block `place` (null none).
func trophy(place: int) -> Trophy:
	return _trophies[place - 1] if place >= 1 and place <= 3 else null


func _init(track: BuiltTrack, sample: int) -> void:
	name = "Podium"
	var i := clampi(sample, 0, track.count - 1)
	var at := Vector3(track.px[i], track.py[i], track.pz[i])
	var fwd := Vector3(track.tx[i], 0.0, track.tz[i]).normalized()
	# the podium faces back down the road (towards the camera, which stands ahead of it)
	var face := -fwd
	var right := Vector3.UP.cross(face).normalized() # (+x: the camera's right)
	_base = Transform3D(Basis(right, Vector3.UP, face), at)
	transform = _base
	# the plinth
	var plinth := _box(Vector3(3.0 * BLOCK_W + 2.0 * GAP + 1.2, 0.18, BLOCK_D + 1.0), Color("#1d2026"), 0.7, 0.1)
	plinth.position = Vector3(0, 0.09, 0)
	add_child(plinth)
	# the blocks: x across (+ = the camera's right): 2nd on the left, 1st in the middle, 3rd on the right
	var xs := [0.0, -(BLOCK_W + GAP), BLOCK_W + GAP]
	_xs = xs
	for k in 3:
		var h: float = HEIGHTS[k]
		var b := _box(Vector3(BLOCK_W, h, BLOCK_D), COLORS[k], 0.35, 0.55)
		b.position = Vector3(xs[k], 0.18 + h * 0.5, 0)
		add_child(b)
		var num := Label3D.new()
		num.text = str(k + 1)
		num.font = UiStyle.font("display_bold", 96)
		num.font_size = 96
		num.pixel_size = 0.006
		num.modulate = Color("#14161a")
		num.outline_size = 0
		num.position = Vector3(xs[k], 0.18 + h * 0.5, BLOCK_D * 0.5 + 0.02)
		num.double_sided = false
		add_child(num)
		# where the car stands: on top, facing the camera, turned a little towards the middle
		var turn: float = [0.15, TURN, -TURN][k]
		spots.append(Transform3D(Basis(Vector3.UP, turn), Vector3(xs[k], 0.18 + h, 0.0)))
		var nm := Label3D.new()
		nm.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nm.font = UiStyle.font("display_bold", 48)
		nm.font_size = 48
		nm.pixel_size = 0.0075
		nm.outline_size = 10
		nm.outline_modulate = Color(0, 0, 0, 0.75)
		nm.position = Vector3(xs[k], 0.18 + h + 2.1, 0.0)
		nm.no_depth_test = true
		add_child(nm)
		_names.append(nm)
	camera = Camera3D.new()
	camera.name = "PodiumCamera"
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 3000.0
	add_child(camera)
	update(0.0)


func _box(size: Vector3, color: Color, rough: float, metal: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	bm.material = mat
	mi.mesh = bm
	return mi


## Put car `model` (a CarModel already in the world) on place `place` (1..3), with `who` above it.
func put(place: int, model: Node3D, who: String, color: Color = Color.WHITE) -> void:
	if place < 1 or place > 3:
		return
	_filled[place - 1] = true
	if model != null:
		model.global_transform = global_transform * spots[place - 1]
		model.visible = true
	var nm := _names[place - 1]
	nm.text = who
	nm.modulate = color.lerp(Color.WHITE, 0.35)


## The camera's slow swing round the front (dt: the frame time).
func update(dt: float) -> void:
	_t += dt
	var a := sin(_t * ORBIT_SPEED * TAU / 2.0) * ORBIT
	var pos := Vector3(sin(a) * CAM_DIST, CAM_H, cos(a) * CAM_DIST)
	var look := Vector3(0, 1.6, 0)
	camera.transform = Transform3D(Basis(), pos).looking_at(look, Vector3.UP)
	# the podium sits left of the middle (the finish panel docks on the right)
	var vp := get_viewport()
	var aspect := 16.0 / 9.0
	if vp != null:
		var r := vp.get_visible_rect().size
		aspect = r.x / maxf(1.0, r.y)
	camera.h_offset = view_shift * 2.0 * pos.distance_to(look) * tan(deg_to_rad(camera.fov) * 0.5) * aspect
