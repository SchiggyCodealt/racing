extends SceneTree
## Answers the queries (numbers sent as exact hex, see hex_json.gd) of tools/parity/collision_queries.mjs with sim/collision.gd
## and compares every number with the browser game's answers.
##   godot --headless --path . --script res://tools/parity/check_collision.gd -- /abs/queries.json

func _initialize() -> void:
	var qs: Array = HexJson.read(OS.get_cmdline_user_args()[0])
	var bad: int = 0
	var numbers: int = 0
	var worst: float = 0.0
	var loc := Collision.Loc.new()
	var c := Collision.Contact.new()
	for q: Dictionary in qs:
		var t: BuiltTrack = Tracks.build_web(q.track)
		var x: float = q.x
		var z: float = q.z
		Collision.locate(t, x, z, int(q.hint), loc)
		var mine: Dictionary = {idx = loc.idx, t = loc.t, tRaw = loc.t_raw, prog = loc.prog, lat = loc.lat, nx = loc.nx, nz = loc.nz, bank = loc.bank, hw = loc.hw, groundY = loc.ground_y}
		mine.ray = Collision.raycast(t.grid, x, z, q.dx, q.dz, 100.0)
		var core: float = q.core
		var fx: float = q.fx
		var fz: float = q.fz
		mine.hit = Collision.collide_capsule(t.grid, x - fx * core, z - fz * core, x + fx * core, z + fz * core, q.R, c)
		var theirs: Dictionary = (q.loc as Dictionary).duplicate()
		theirs.ray = q.ray
		theirs.hit = q.hit
		if q.hit:
			for k: String in ["depth", "nx", "nz", "px", "pz", "seg"]:
				theirs["c_" + k] = q.c[k]
			mine.c_depth = c.depth; mine.c_nx = c.nx; mine.c_nz = c.nz; mine.c_px = c.px; mine.c_pz = c.pz; mine.c_seg = c.seg
		for k: String in theirs.keys():
			numbers += 1
			var va: Variant = theirs[k]
			var vb: Variant = mine[k]
			if typeof(va) == TYPE_BOOL or typeof(vb) == TYPE_BOOL:
				if bool(va) != bool(vb):
					bad += 1
				continue
			var d: float = absf(float(va) - float(vb))
			if d != 0.0:
				worst = maxf(worst, d)
				bad += 1
				if bad < 8:
					print("differ %s %s: js %s gd %s" % [q.track, k, va, vb])
	print("%d queries, %d numbers: %d differ (largest %s)" % [qs.size(), numbers, bad, worst])
	quit(1 if bad else 0)
