extends SceneTree
## ui_preview.gd
## ------------------------------------------------------------------
## Renders every screen of the interface with fixture data (tests/visual/ui_fixture.gd) at the
## window size Godot was started with, saves PNGs and checks the layout: nothing outside the
## window, no HUD read-outs on top of each other, no button or label squeezed below its size.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path <copy> --resolution 1280x720 \
##     --script res://tests/visual/ui_preview.gd -- --out=/tmp/shots [--bg=/dir] [--screens=menu,hud]
## --bg: a folder with backdrops bg-menu-WxH.png / bg-drive-WxH.png (the web game's 3D view
## without its interface; the 1280x720 ones are scaled to other sizes), else a dark gradient.
## Prints one line per screen and "LAYOUT PROBLEMS: n"; quits with 1 when there are any.

const Fx := preload("res://tests/visual/ui_fixture.gd")

var out_dir := "/tmp/ui_shots"
var bg_dir := ""
var only: PackedStringArray = []
var problems: Array[String] = []
var _bg: TextureRect
var _tag := ""
var _view := Vector2(1280, 720)   # the interface's size (UiRoot.frame) in its own pixels


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--bg="):
			bg_dir = a.substr(5)
		elif a.begins_with("--screens="):
			only = a.substr(10).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _want(name: String) -> bool:
	return only.is_empty() or only.has(name) or only.has(name.get_slice("-", 0))


func _run() -> void:
	var win := get_root().size
	_tag = "%dx%d" % [win.x, win.y]
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	get_root().add_child(_bg)
	await _menu_screens()
	await _hud_screens()
	print("LAYOUT PROBLEMS: %d" % problems.size())
	for p in problems:
		print("  ", p)
	quit(1 if not problems.is_empty() else 0)


func _backdrop(kind: String) -> void:
	var tex: Texture2D = null
	if bg_dir != "":
		for f in ["%s/bg-%s-%s.png" % [bg_dir, kind, _tag], "%s/bg-%s-1280x720.png" % [bg_dir, kind]]:
			if FileAccess.file_exists(f):
				tex = ImageTexture.create_from_image(Image.load_from_file(f))
				break
	if tex == null:
		var g := Gradient.new()
		g.set_color(0, Color("#0d1424"))
		g.set_color(1, Color("#06070a"))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		tex = gt
	_bg.texture = tex


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := "%s/%s-%s.png" % [out_dir, name, _tag]
	img.save_png(path)
	print("saved ", path)


# ================================================================= the menu

## The interface as the game adds it (UiRoot: its own pixels, the menu or the HUD).
func _make_ui(track: int) -> UiRoot:
	var ui := UiRoot.new()
	ui.menu.selected_track = track
	ui.menu.input = null # (the shots drive the menu with fake presses)
	get_root().add_child(ui)
	_view = ui.frame.size
	return ui


## Rename track `i` for the stress shots (the built track when sim/ is there, else the fixture).
func _rename(i: int, name_: String) -> void:
	UiData.track_count()
	if not UiData._tracks.is_empty():
		UiData._tracks[i].name = name_
	else:
		UiData.fixture().tracks[i].name = name_


func _menu_screens() -> void:
	_backdrop("menu")
	Fx.save_data_v5()
	var ui := _make_ui(9)
	ui.show_menu(true)
	var menu := ui.menu
	await process_frame
	print("interface %s at scale %.2f" % [_view, ui.ui_scale])
	if _want("menu"):
		await _shot("menu")
		_check_menu(menu, "menu")
	if _want("menu-pad"):
		# the gamepad: down from the bottom row of tracks to the cars, then right to the Kestrel
		var inp := Fx.FakeInput.new()
		inp.pad_active = true
		for code in ["NavDown", "NavDown", "NavRight"]:
			inp.press(code)
			menu.handle_keys(inp)
			await process_frame
		await _shot("menu-pad")
		menu.handle_keys(_pad_press("PadB"))
		UiData.set_setting("car", "racer")
		menu.refresh()
	if _want("controls"):
		menu.show_controls(true)
		await _shot("controls")
		_check_inside(menu.controls.panel, "controls panel", true)
		menu.show_controls(false)
	if _want("settings"):
		menu.show_settings(true)
		await _shot("settings")
		_check_inside(menu.settings.panel, "settings panel", true)
		menu.show_settings(false)
	if _want("menu-stress"):
		# long names, 12-minute times, a seven-digit score, a long AI status, the Thunder picked, no network buttons
		Fx.save_data_stress()
		var names: Array = []
		for i in UiData.track_count():
			names.append(UiData.track_info(i).name)
		_rename(9, "Night Highway Extended Grand Prix Circuit")
		_rename(3, "Banked Speedway Of The Seven Hills")
		ui.queue_free()
		ui = _make_ui(9)
		ui.show_menu(true)
		menu = ui.menu
		await process_frame
		await _shot("menu-stress")
		_check_menu(menu, "menu-stress")
		for i in names.size():
			_rename(i, names[i])
		UiData.store.network = null
		UiData.set_setting("car", "drifter")
		ui.queue_free()
		ui = _make_ui(5)
		ui.show_menu(true)
		menu = ui.menu
		await process_frame
		await _shot("menu-nonet")
		_check_menu(menu, "menu-nonet")
	ui.queue_free()
	await process_frame


func _pad_press(code: String) -> Object:
	var inp := Fx.FakeInput.new()
	inp.pad_active = true
	inp.press(code)
	return inp


## The menu must fit the window without scrolling from 1280 x 720 up, and nothing may stick out.
func _check_menu(menu: MainMenu, name: String) -> void:
	var main: Control = menu.get("_main")
	var r := main.get_global_rect()
	var view := Rect2(Vector2.ZERO, menu.size)
	var scrolls := r.end.y > view.end.y + 0.5 or r.position.y < -0.5
	if scrolls and view.size.x >= 1280 and view.size.y >= 720:
		problems.append("%s %s: the menu is %d px tall in a %d px window (it scrolls)" % [name, _tag, r.size.y, view.size.y])
	if scrolls:
		# (smaller windows scroll the menu, as the web's does: only the width must fit)
		print("%s %s: the menu scrolls (%d px in %d)" % [name, _tag, r.size.y, view.size.y])
		view = Rect2(0, -100000, view.size.x, 200000)
	_check_tree(main, name, view)


## Every visible Control of `root` inside `view`, and no Button or Label narrower than its minimum.
func _check_tree(root: Control, name: String, view: Rect2) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var c: Control = stack.pop_back()
		if not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if r.size.x > 0 and r.size.y > 0 and not view.grow(1.0).encloses(r):
			problems.append("%s %s: %s %s sticks out of %s" % [name, _tag, c.get_class(), _describe(c), r])
		if (c is Button or c is Label) and c.size.x + 0.5 < c.get_combined_minimum_size().x:
			problems.append("%s %s: %s %s squeezed (%d < %d)" % [name, _tag, c.get_class(), _describe(c), c.size.x, c.get_combined_minimum_size().x])
		for k in c.get_children():
			if k is Control:
				stack.append(k)


func _describe(c: Control) -> String:
	if c is Label:
		return "'%s'" % (c as Label).text.left(30)
	if c is Button:
		return "'%s'" % (c as Button).text
	return str(c.name)


func _check_inside(c: Control, what: String, may_scroll: bool = false) -> void:
	var view := Rect2(Vector2.ZERO, _view)
	if may_scroll and (_view.x < 1280 or _view.y < 720):
		view = Rect2(0, -100000, _view.x, 200000) # (a dialog scrolls in a small window, as the web's does)
	var r := c.get_global_rect()
	if not view.grow(1.0).encloses(r):
		problems.append("%s %s: %s outside the window (%s)" % [what, _tag, what, r])


# ================================================================= the race HUD

func _hud_screens() -> void:
	_backdrop("drive")
	Fx.save_data_v5()
	var ui := _make_ui(9)
	ui.show_menu(false)
	var hud := ui.hud
	hud.show_hud(true)
	hud.set_mode("Night Highway · Racer")
	hud.set_keys(Fx.STATE_KEYS, false)
	await process_frame
	if _want("drive"):
		hud.update(Fx.hud_drive(), 0.016)
		await _shot("drive")
		_check_hud(hud, "drive")
	if _want("drive-events"):
		# a drift building up, popups, a split and the countdown's GO!, ghost note; gamepad key names
		var s := Fx.hud_drive()
		s.score = {"total": 23450, "mult": 3, "live": {"kind": "drift", "time": 1.8, "points": 1240}}
		s.pad = true
		s.ghost_text = "Ghost on (Y)"
		s.countdown = "GO!"
		s.split = {"label": "CP 6", "time": 57.533, "delta": -0.412}
		s.pops = Fx.pops()
		hud.update(s, 0.016)
		for i in 3:
			s.erase("pops")
			s.erase("split")
			hud.update(s, 0.25)
		await _shot("drive-events")
		_check_hud(hud, "drive-events")
		hud.show_hud(true)
	if _want("drive-stress"):
		# 12-minute times, a seven-digit score, a wall contact, an empty tank, the medal ticked
		var s := Fx.hud_drive()
		s.merge({"time": 754.321, "lap": 12, "laps": 12, "cp": 17, "cps": 17, "best": 761.234, "nitro": 0.0, "boosting": false,
			"gear": -1, "rpm": 7900.0, "speed": 356.0 / 3.6, "finished": true,
			"medal": {"medal": "author", "time": 755.0, "all": true},
			"score": {"total": 9876543, "mult": 1, "live": {"kind": "wall", "time": 0.6, "points": -1350}},
			"ghost_text": "No Thunder ghost yet: set a best time first",
			"split": {"label": "LAP 12", "time": 700.123, "delta": 12.345}, "pops": [
				{"kind": "wall", "text": "Wall", "points": -1350, "mult": 1, "combo_lost": true},
				{"kind": "respawn", "text": "Respawn", "points": -500, "mult": 1},
				{"kind": "drift", "text": "Drift lost", "points": 0, "mult": 1},
				{"kind": "run", "text": "Clean run", "points": 5000, "mult": 1}]}, true)
		hud.set_mode("VS AI GHOST · Night Highway Extended Grand Prix Circuit · Thunder")
		hud.update(s, 0.016)
		s.erase("pops")
		s.erase("split")
		hud.update(s, 0.3)
		await _shot("drive-stress")
		_check_hud(hud, "drive-stress")
		hud.show_hud(true)
		hud.set_mode("Night Highway · Racer")
	if _want("drive-low"):
		var s := Fx.hud_drive()
		s.merge({"nitro": 0.18, "boosting": false, "best": null, "medal": {"medal": "bronze", "time": 293.0},
			"score": {"total": 0, "mult": 1, "live": {"kind": "air", "time": 1.2, "points": 600}}, "sprint": true, "lap": 1, "laps": 1}, true)
		hud.update(s, 0.016)
		await _shot("drive-low")
		_check_hud(hud, "drive-low")
	if _want("finish"):
		hud.show_hud(true)
		var s := Fx.hud_finish()
		s.split = {"label": "FINISH", "time": 221.967, "delta": 6.917}
		s.pops = [{"kind": "checkpoints", "text": "Clean finish", "points": 2500, "mult": 5}]
		hud.update(s, 0.016)
		s.erase("pops")
		s.erase("split")
		hud.update(s, 0.3)
		hud.show_panel(Fx.panel_finish())
		await _shot("finish")
		_check_hud(hud, "finish")
	if _want("finish-record"):
		hud.show_panel(Fx.panel_record())
		await _shot("finish-record")
		_check_hud(hud, "finish-record")
	if _want("finish-stress"):
		hud.show_panel(Fx.panel_stress())
		await _shot("finish-stress")
		_check_hud(hud, "finish-stress")
	if _want("watch"):
		hud.show_hud(true)
		hud.set_mode("WATCHING AI · Night Highway")
		hud.set_keys([["R", "restart", "View"], ["Esc", "menu", "Menu"]], false)
		var s := Fx.hud_drive()
		s.merge({"nitro": null, "score": null, "medal": null, "ghost_text": "AI was stuck: back to its last checkpoint", "boosting": false}, true)
		hud.update(s, 0.016)
		hud.show_watch(true)
		hud.watch_net(Fx.network())
		await _shot("watch")
		_check_hud(hud, "watch")
		hud.show_panel(Fx.panel_ai())
		await _shot("watch-finish")
		_check_hud(hud, "watch-finish")
		hud.show_watch(false)
	if _want("notice"):
		hud.hide_panel()
		var n := ui.notice
		n.show_text("Gamepad connected: Xbox Wireless Controller · RT accelerate · LT brake · A handbrake · X nitro · View on the menu lists every button")
		for i in 20:
			await process_frame
		n._process(1.0)
		await _shot("notice")
		_check_inside(n.get("_plate"), "notice")
	ui.queue_free()
	await process_frame


## The HUD's read-outs must stay inside the window and off each other (and off the finish panel).
func _check_hud(hud: RaceHud, name: String) -> void:
	var view := Rect2(Vector2.ZERO, hud.size)
	var parts := {}
	for key in ["_mode", "_time_plate", "_split", "_left", "_right", "_nitro", "_speed_row", "_rev", "_keys", "watch_panel", "finish"]:
		var c: Control = hud.get(key)
		if c.is_visible_in_tree() and c.modulate.a > 0.01:
			parts[key] = _content_rect(c)
	for key in parts:
		var r: Rect2 = parts[key]
		if not view.grow(1.0).encloses(r):
			problems.append("%s %s: %s outside the window (%s)" % [name, _tag, key, r])
	var keys := parts.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = parts[keys[i]]
			var b: Rect2 = parts[keys[j]]
			if a.intersects(b):
				problems.append("%s %s: %s overlaps %s (%s / %s)" % [name, _tag, keys[i], keys[j], a, b])


## The rect a HUD part really covers: its visible children (a column's empty space doesn't count),
## grown by the slant of the plates.
func _content_rect(c: Control) -> Rect2:
	if c is VBoxContainer or c is HFlowContainer:
		var r := Rect2()
		var first := true
		for k in c.get_children():
			if k is Control and k.is_visible_in_tree() and k.size.y > 0:
				var kr := _content_rect(k)
				r = kr if first else r.merge(kr)
				first = false
		return r
	if c is MarginContainer and c.get_child_count() == 1:
		return _content_rect(c.get_child(0))
	var g := c.get_global_rect()
	# a slanted plate reaches half its skew past its rect on each side
	var sb: StyleBox = c.get_theme_stylebox("panel") if c is PanelContainer else null
	if sb is StyleBoxFlat and (sb as StyleBoxFlat).skew.x != 0.0:
		var d := g.size.y * absf((sb as StyleBoxFlat).skew.x) * 0.5
		return g.grow_individual(d, 0, d, 0)
	return g
