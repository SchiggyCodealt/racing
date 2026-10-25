extends SceneTree
## Dumps every built track (arrays, gates, kickers, wall grid) as JSON for
## tools/parity/compare_tracks.mjs, which compares them with the browser
## game's built tracks number for number.
##   godot --headless --path . --script res://tools/parity/dump_tracks.gd -- /abs/out.json

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() else "user://gd_built.json"
	var out: Array = []
	var t0: int = Time.get_ticks_usec()
	for id in Tracks.ids():
		var t: BuiltTrack = Tracks.build(id)
		var g: Collision.WallGrid = t.grid
		out.append({
			id = t.id, name = t.name, theme = t.theme, closed = t.closed, laps = t.laps, N = t.N, count = t.count, segLen = t.seg_len,
			length = t.length, segCount = t.seg_count, startIdx = t.start_idx, finishIdx = t.finish_idx, startLine = t.start_line,
			cpSamples = Array(t.cp_samples), kickers = t.kickers,
			px = Array(t.px), py = Array(t.py), pz = Array(t.pz), tx = Array(t.tx), tz = Array(t.tz), nx = Array(t.nx), nz = Array(t.nz),
			hw = Array(t.hw), bank = Array(t.bank), gates = TrackBuilder.get_gates(t, t.laps), raceLength = TrackBuilder.race_length(t, t.laps),
			grid = {cell = g.cell, minX = g.min_x, minZ = g.min_z, cols = g.cols, rows = g.rows, segs = Array(g.segs), inward = Array(g.inward),
				segD = Array(g.seg_d), cellStart = Array(g.cell_start), cellSegs = Array(g.cell_segs)},
		})
	print("built %d tracks in %.0f ms" % [out.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "", false, true))
	f.close()
	quit(0)
