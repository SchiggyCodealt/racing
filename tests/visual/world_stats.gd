extends SceneTree
## world_stats.gd: build time and draw cost of every track at each quality level, in one run.
##
##   godot --path . --resolution 1280x720 --script res://tests/visual/world_stats.gd -- \
##       tracks=rookie-oval,night-highway qualities=high,low at=0.1 out=/tmp/world_stats.json
##
## Options (key=value, all optional):
##   tracks     comma-separated track ids, default every track (Tracks.ids())
##   qualities  comma-separated quality levels, default high,low
##   at         where the car stands (fraction of the lap), the camera chases it; default 0.1
##   frames     frames rendered before reading the counters (default 4)
##   out        a JSON file for the rows (optional)
##   terrain_shadows  0 | 1: override the level's terrain shadow casting
## Prints one line per track and level: world build ms, draw calls and primitives
## (all passes; visible pass; shadow pass), terrain vertices and scenery instances.
## Needs a rendering device (not --headless): xvfb-run works, on llvmpipe too.

const Themes = preload("res://world/themes.gd")

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var ids: PackedStringArray = Tracks.ids()
	if o.has("tracks"):
		ids = String(o["tracks"]).split(",")
	var levels: PackedStringArray = String(o.get("qualities", "high,low")).split(",")
	var at := float(o.get("at", "0.1"))
	var frames := int(o.get("frames", "4"))
	var rows: Array = []
	print("track            quality  build ms  calls (vis+shadow)   primitives (vis + shadow)")
	for id in ids:
		var track := Tracks.build(id)
		if track == null:
			push_error("unknown track " + id)
			continue
		for q in levels:
			var t0 := Time.get_ticks_msec()
			var world := World.build(track, q)
			var ms := Time.get_ticks_msec() - t0
			get_root().add_child(world)
			if o.has("terrain_shadows"):
				var qd := Themes.get_quality(q).duplicate()
				qd["terrain_shadows"] = o["terrain_shadows"] == "1"
				world.track_node.apply_quality(qd)
			var i := int(at * track.count) % track.count
			var yaw := track.heading(i)
			var v := 120.0 / 3.6
			var state := {"x": track.px[i], "y": track.py[i], "z": track.pz[i], "yaw": yaw, "vx": sin(yaw) * v, "vz": cos(yaw) * v,
				"speed": v, "forward_speed": v, "idx": i, "throttle": 1.0, "grounded": true}
			var car := CarModel.new("racer")
			world.add_child(car)
			var cam := ChaseCamera.new()
			world.add_child(cam)
			cam.make_current()
			for f in frames:
				car.update(state, null, 1.0, 1.0 / 60.0, track)
				if f == 0:
					cam.snap(state, track)
				else:
					cam.update(state, 1.0 / 60.0, track)
				await process_frame
			await RenderingServer.frame_post_draw
			var s := world.render_stats()
			var ts: Dictionary = s.get("track_stats", {})
			var row := {"track": id, "quality": q, "terrain_shadows": o.get("terrain_shadows", "level"), "build_ms": ms, "calls": s["calls"], "primitives": s["primitives"],
				"visible_calls": s["visible_calls"], "visible_primitives": s["visible_primitives"],
				"shadow_calls": s["shadow_calls"], "shadow_primitives": s["shadow_primitives"],
				"terrain_ms": ts.get("terrain_ms", 0), "terrain_verts": ts.get("terrain_verts", 0), "scenery": ts.get("scenery_instances", 0)}
			rows.append(row)
			print("%-16s %-7s %6d    %4d (%3d + %3d)    %8d (%7d + %7d)" % [id, q, ms, row["calls"], row["visible_calls"], row["shadow_calls"],
				row["primitives"], row["visible_primitives"], row["shadow_primitives"]])
			world.queue_free()
			await process_frame
	if o.has("out"):
		var f := FileAccess.open(String(o["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rows, "  "))
	quit(0)
