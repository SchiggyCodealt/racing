extends RefCounted
## test_ui.gd: headless checks of the interface (ui/): the formats, the data adapter and medal
## rules, the minimap fitting, the key names, gamepad geometry, the menu's keyboard and gamepad
## navigation (menu.js handleKeys / handlePad), the Controls and Settings screens, the HUD's
## states and the finish panel; (v6.5.0) money and points on the menu, the car shop's locks and
## prices, the opponent picker and the finish panel's payout; (v6.7.0) the terminal screen (log, input,
## history, Tab, the keys that open and close it on the menu and Settings). The look is checked by eye with tests/visual/ui_preview.gd.
## No frames pass here, so the containers are laid out by hand (_settle).

const Fx := preload("res://tests/visual/ui_fixture.gd")
const PadNav := preload("res://ui/pad_nav.gd")
const TrackMapView := preload("res://ui/track_map_view.gd")
const NitroGauge := preload("res://ui/nitro_gauge.gd")
const CheckToggle := preload("res://ui/check_toggle.gd")


func run(t) -> bool:
	_formats(t)
	_data(t)
	_maps(t)
	_keys(t)
	_pad_nav(t)
	_menu_keys(t)
	_menu_pad(t)
	_menu_cars(t)
	_menu_tracks(t)
	_settings(t)
	_terminal(t)
	_hud(t)
	_finish(t)
	_career(t)
	_scale(t)
	UiData.reset()
	return true


## Lay out every container under `n` now (normally done before the next frame is drawn).
func _settle(n: Node) -> void:
	for i in 4:
		_sort(n)


func _sort(n: Node) -> void:
	if n is Container:
		n.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c in n.get_children():
		_sort(c)


## A 1280 x 720 holder under the tree's root (the menu and HUD fill their parent).
func _holder(t, size := Vector2(1280, 720)) -> Control:
	var h := Control.new()
	h.size = size
	t.tree.root.add_child(h)
	return h


func _press(inp, codes: Array, pad := false) -> Object:
	inp.pad_active = pad
	for c in codes:
		inp.press(c)
	return inp


func _formats(t) -> void:
	t.section("formats (race.js formatTime / formatDelta, score.js formatPoints)")
	t.check(UiFormat.time(221.967) == "3:41.967", "time 221.967 -> 3:41.967")
	t.check(UiFormat.time(754.321) == "12:34.321", "time 754.321 -> 12:34.321 (12 minutes)")
	t.check(UiFormat.time(119.9996) == "2:00.000", "time rounds once: 119.9996 -> 2:00.000")
	t.check(UiFormat.time(null) == "--:--.---", "no time -> --:--.---")
	t.check(UiFormat.delta(6.917) == "+6.917" and UiFormat.delta(-0.412) == "-0.412", "deltas +6.917 / -0.412")
	t.check(UiFormat.points(40940) == "40,940" and UiFormat.points(9876543) == "9,876,543", "points with thousands commas")
	t.check(UiFormat.points(-560) == "−560", "negative points with a real minus sign")
	t.check(UiFormat.track_number(0) == "01" and UiFormat.km(3120.0) == "3.12", "track number 01, 3.12 km")


func _data(t) -> void:
	t.section("data adapter and medals (medals.js medalFor / nextMedal)")
	Fx.save_data_v5()
	t.check(UiData.track_count() == 15, "15 tracks (%d)" % UiData.track_count())
	t.check(UiData.track_id(9) == "night-highway" and UiData.track_info(9).name == "Night Highway", "track 10 is Night Highway")
	var real: bool = not UiData._tracks.is_empty()
	t.check(real, "tracks come from sim/ (Tracks.build), not the fixture")
	var surf := []
	for i in UiData.track_count():
		surf.append(UiData.track_info(i).surfaces)
	t.check(surf[0] == "Asphalt" and surf[1] == "Asphalt + packed snow" and surf[2] == "Asphalt + dirt" and surf[7] == "Asphalt + dirt + packed snow" and \
		surf[8] == "Asphalt + dirt" and surf[12] == "Asphalt + dirt" and surf[13] == "Asphalt + packed snow" and surf[14] == "Asphalt + dirt + packed snow" and \
		surf.count("Asphalt") == 8, "the road surfaces of every track (v6.3, v6.4): %s" % ", ".join(surf))
	t.check(UiData.car_ids() == ["racer", "kestrel", "thunder", "drifter", "dune", "vortex"], "cars in picker order: %s" % [UiData.car_ids()])
	var racer := UiData.car_info("racer")
	t.check(absf(racer.top - 277.7) < 0.01 and racer.mass == 1250.0, "racer: 277.7 km/h, 1250 kg (%s, %s)" % [racer.top, racer.mass])
	t.check(UiData.car_info("nope").id == "racer", "an unknown car gives the racer")
	t.check(racer.rev.redline > racer.rev.upshift_rpm and racer.rev.upshift_rpm > racer.rev.idle_rpm, "rev limits idle < upshift < redline")
	var got := UiData.medal_times("night-highway", "racer")
	var from_sim := FileAccess.file_exists(UiData.MEDALS_JSON)
	t.check((got.size() == 4 and got.author < got.gold and got.gold < got.silver and got.silver < got.bronze) or (from_sim and got.is_empty()),
		"medal times from %s: four, author fastest (%s)" % ["data/medals.json" if from_sim else "the fixture", got])
	var m := {"author": 196.5, "gold": 209.0, "silver": 236.0, "bronze": 295.0} # (fixed times: medals.js rules)
	t.check(UiData.medal_for(m, 215.05) == "silver", "3:35.050 earns silver")
	t.check(UiData.medal_for(m, m.gold) == "gold" and UiData.medal_for(m, m.gold + 0.0004) == "gold" and UiData.medal_for(m, m.gold + 0.001) == "silver",
		"medals to the millisecond shown")
	t.check(UiData.medal_for(m, m.bronze + 1.0) == "" and UiData.medal_for(m, null) == "" and UiData.medal_for({}, 100.0) == "", "no medal: too slow, no time, no medal times")
	var nx := UiData.next_medal(m, 215.05)
	t.check(nx.medal == "gold" and is_equal_approx(nx.time, m.gold), "next medal after silver is gold")
	t.check(UiData.next_medal(m, null).medal == "bronze" and UiData.next_medal(m, m.author - 1.0).is_empty(), "next medal: bronze with no time, none after author")
	t.check(UiData.best_score("night-highway", "racer") == 66000 and UiData.best_score("rookie-oval", "racer") == -1, "best score, -1 for none")
	t.check(UiData.has_ghost("night-highway", "racer") and not UiData.has_ghost("rookie-oval", "racer"), "ghost saved only where set")
	t.check(UiData.ai_status().ready and UiData.ai_status().generation == 60, "AI status from the stored network")
	var changed := []
	UiData.on_setting_changed = func(k: String, v: Variant) -> void: changed.append([k, v])
	UiData.set_setting("quality", "low")
	t.check(UiData.get_setting("quality") == "low" and changed == [["quality", "low"]], "settings write through and notify")
	UiData.on_setting_changed = Callable()
	t.check(UiData.get_setting("ui_scale") == "auto" and UiData.get_setting("vsync") == true, "setting defaults")


func _maps(t) -> void:
	t.section("minimaps (menu.js trackMap)")
	var m := UiData.track_map(9)
	t.check(m.points.size() >= 80 and m.points.size() <= 200, "minimap has %d points (about 160)" % m.points.size())
	var inside := true
	for p: Vector2 in m.points:
		inside = inside and p.x >= 0.0 and p.y >= 0.0 and p.x <= m.size.x + 0.01 and p.y <= m.size.y + 0.01
	t.check(inside, "every point inside the map's box")
	# a tall track is turned a quarter, so the map is wider than tall
	var px := PackedFloat64Array()
	var pz := PackedFloat64Array()
	for k in 100:
		var a := TAU * k / 100.0
		px.append(30.0 * cos(a))
		pz.append(200.0 * sin(a))
	var tall := TrackMapView.make_map(px, pz, 100, true, 0, -1)
	t.check(tall.size.x >= tall.size.y, "a tall track is drawn turned (%s)" % tall.size)
	t.check(tall.finish == null and tall.closed, "a circuit has no finish dot")


func _key(code: Key, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.shift_pressed = shift
	e.pressed = true
	return e


func _keys(t) -> void:
	t.section("key names (the web's KeyboardEvent.code)")
	t.check(MenuInput.key_code(_key(KEY_H)) == "KeyH" and MenuInput.key_code(_key(KEY_1)) == "Digit1", "KeyH, Digit1")
	t.check(MenuInput.key_code(_key(KEY_KP_3)) == "Numpad3" and MenuInput.key_code(_key(KEY_KP_ENTER)) == "NumpadEnter", "Numpad3, NumpadEnter")
	t.check(MenuInput.key_code(_key(KEY_MINUS)) == "Minus" and MenuInput.key_code(_key(KEY_EQUAL)) == "Equal", "Minus, Equal")
	t.check(MenuInput.key_code(_key(KEY_UP)) == "ArrowUp" and MenuInput.key_code(_key(KEY_ESCAPE)) == "Escape", "ArrowUp, Escape")
	t.check(MenuInput.key_code(_key(KEY_QUOTELEFT)) == "Backquote", "the key under Esc is Backquote (the terminal, v6.7.0)")
	var inp := MenuInput.new()
	inp.press("KeyC")
	t.check(inp.consume(["KeyX", "KeyC"]) and not inp.consume(["KeyC"]), "consume takes a press once")
	inp.press("NavLeft")
	t.check(inp.nav_dir() == "left" and inp.nav_dir() == "", "nav_dir reads the d-pad once")
	inp.free()


func _pad_nav(t) -> void:
	t.section("gamepad highlight geometry (input.js nearestTo)")
	# a 3 x 2 grid of 100 x 80 tiles, 10 apart, and a wide bar under it
	var r: Array = []
	for row in 2:
		for col in 3:
			r.append(Rect2(col * 110, row * 90, 100, 80))
	r.append(Rect2(0, 200, 320, 40))
	t.check(PadNav.nearest(r[0], "right", r, 0) == 1, "right of the first tile: the second")
	t.check(PadNav.nearest(r[1], "down", r, 1) == 4, "down from the top middle: the bottom middle")
	t.check(PadNav.nearest(r[5], "down", r, 5) == 6, "down from the bottom row: the bar")
	t.check(PadNav.nearest(r[2], "right", r, 2) == -1 and PadNav.nearest(r[0], "up", r, 0) == -1, "nothing beyond the edge")
	t.check(PadNav.nearest(r[6], "up", r, 6) == 4, "up from the bar: the tile above its centre")
	t.check(PadNav.same_row(r[0], r[2]) and not PadNav.same_row(r[0], r[3]), "same row")


func _menu(t) -> Array:
	var h := _holder(t)
	var menu := MainMenu.new()
	menu.selected_track = 9
	h.add_child(menu)
	menu.show_menu(true)
	_settle(h)
	return [h, menu]


func _menu_cars(t) -> void:
	t.section("menu car picker: six cars at every window size")
	Fx.save_data_v5()
	for sz: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1366, 768), Vector2(1024, 600), Vector2(900, 700), Vector2(700, 900)]:
		var h := _holder(t, sz)
		var menu := MainMenu.new()
		h.add_child(menu)
		menu.show_menu(true)
		_settle(h)
		var grid: GridContainer = menu.get("_cars_grid")
		var cards: Array = menu.get("_cards")
		var rects: Array[Rect2] = []
		var inside := true
		var overlap := false
		for c: Control in cards:
			var r := c.get_global_rect()
			inside = inside and r.position.x >= -0.5 and r.end.x <= sz.x + 0.5 and r.size.x > 120.0
			for o in rects:
				overlap = overlap or o.grow(-0.5).intersects(r)
			rects.append(r)
		var cols_ok := grid.columns == (3 if sz.x >= 1280 else grid.columns)
		# at 1280 x 720 and up the menu shows every car without scrolling
		var all_shown := true
		if sz.x >= 1280:
			for r in rects:
				all_shown = all_shown and r.end.y <= sz.y + 0.5
		t.check(cards.size() == 6 and inside and not overlap and cols_ok and all_shown,
			"%dx%d: %d cards, %d a row, inside the window and apart%s" % [sz.x, sz.y, cards.size(), grid.columns, ", all on screen" if sz.x >= 1280 else ""])
		h.free()


func _menu_tracks(t) -> void:
	t.section("menu track grid: 15 tracks at every window size (v6.4)")
	Fx.save_data_v5()
	# [window, tiles a row]: three rows of five from 1200 px wide, rows of four from 760, three below
	for case: Array in [[Vector2(1280, 720), 5], [Vector2(1920, 1080), 5], [Vector2(1366, 768), 5], [Vector2(1200, 700), 5],
			[Vector2(1024, 600), 4], [Vector2(900, 700), 4], [Vector2(700, 900), 3], [Vector2(640, 720), 3]]:
		var sz: Vector2 = case[0]
		var h := _holder(t, sz)
		var menu := MainMenu.new()
		h.add_child(menu)
		menu.show_menu(true)
		_settle(h)
		var tiles: Array = menu.get("_tiles")
		var rects: Array[Rect2] = []
		var inside := true
		var overlap := false
		var bottom := 0.0
		for c: Control in tiles:
			var r := c.get_global_rect()
			inside = inside and r.position.x >= -0.5 and r.end.x <= sz.x + 0.5 and r.size.x > 100.0 and r.size.y > 60.0
			for o in rects:
				overlap = overlap or o.grow(-0.5).intersects(r)
			rects.append(r)
			bottom = maxf(bottom, r.end.y)
		for c: Control in menu.get("_cards"):
			bottom = maxf(bottom, c.get_global_rect().end.y)
		# from 1280 x 720 up every tile and car card is on screen without scrolling (the e2e menu
		# scenario checks the whole menu with real frames)
		var on_screen := bottom <= sz.y + 0.5 if sz.x >= 1280 else true
		t.check(tiles.size() == 15 and menu.columns == int(case[1]) and inside and not overlap and on_screen,
			"%dx%d: %d tiles, %d a row, inside the window and apart%s" % [sz.x, sz.y, tiles.size(), menu.columns,
				", every tile and car card on screen (lowest ends at %d px)" % roundi(bottom) if sz.x >= 1280 else ""])
		h.free()


func _menu_keys(t) -> void:
	t.section("menu keys (menu.js handleKeys)")
	Fx.save_data_v5()
	var hm := _menu(t)
	var menu: MainMenu = hm[1]
	var inp := Fx.FakeInput.new()
	t.check(menu.selected_track == 9 and menu.columns == 5, "Night Highway selected, five tiles a row at 1280 x 720 (15 tracks: three rows)")
	var picked := []
	menu.track_selected.connect(func(i: int) -> void: picked.append(i))
	for pair in [["Digit1", 0], ["Digit0", 9], ["Minus", 10], ["Equal", 11], ["Numpad5", 4]]:
		menu.handle_keys(_press(inp, [pair[0]]))
		t.check(menu.selected_track == pair[1], "%s picks track %d" % [pair[0], pair[1] + 1])
	t.check(picked.has(10), "track_selected emitted")
	# tracks 13-15 have no key: the arrows reach them (on from track 12, = picks it)
	menu.handle_keys(_press(inp, ["Equal"]))
	for want: int in [12, 13, 14]:
		menu.handle_keys(_press(inp, ["ArrowRight"]))
		t.check(menu.selected_track == want, "= then ArrowRight: track %d, %s" % [want + 1, UiData.track_info(want).name])
	menu.handle_keys(_press(inp, ["ArrowUp"]))
	t.check(menu.selected_track == 13, "ArrowUp: back to track 14")
	menu.select(2)
	var meta: Label = menu.get("_td_meta")
	t.check(meta.text == "Circuit · 3 laps · 2.37 km a lap · Asphalt + dirt", "the track panel names the road surfaces: \"%s\"" % meta.text)
	menu.select(7)
	t.check(meta.text.ends_with("km · Asphalt + dirt + packed snow"), "... and a sprint's: \"%s\"" % meta.text)
	menu.select(14)
	menu.handle_keys(_press(inp, ["ArrowRight"]))
	t.check(menu.selected_track == 0, "ArrowRight from the last track (15) wraps to the first")
	menu.handle_keys(_press(inp, ["ArrowUp"]))
	t.check(menu.selected_track == 14, "ArrowUp from the first wraps to the last")
	menu.handle_keys(_press(inp, ["KeyS"]))
	t.check(menu.selected_track == 0, "S moves on like ArrowDown")
	UiData.set_setting("car", "racer")
	menu.handle_keys(_press(inp, ["KeyC"]))
	t.check(UiData.picked_car() == "kestrel", "C picks the next car")
	menu.handle_keys(_press(inp, ["KeyC", "Shift+KeyC"]))
	t.check(UiData.picked_car() == "racer", "Shift+C picks the previous car")
	menu.handle_keys(_press(inp, ["KeyC", "Shift+KeyC"]))
	t.check(UiData.picked_car() == "vortex", "Shift+C wraps to the last car")
	UiData.set_setting("car", "racer")
	var drives := [0]
	menu.drive.connect(func() -> void: drives[0] += 1)
	menu.handle_keys(_press(inp, ["Enter"]))
	menu.handle_keys(_press(inp, ["NumpadEnter"]))
	t.check(drives[0] == 2, "Enter and NumpadEnter drive")
	menu.handle_keys(_press(inp, ["KeyH"]))
	t.check(menu.controls.is_open, "H opens the Controls screen")
	menu.handle_keys(_press(inp, ["Digit3", "Enter"]))
	t.check(not menu.controls.is_open and menu.selected_track == 0 and drives[0] == 2, "on Controls, Enter only closes it")
	menu.handle_keys(_press(inp, ["Slash"]))
	menu.handle_keys(_press(inp, ["Escape"]))
	t.check(not menu.controls.is_open, "? opens and Esc closes Controls")
	menu.handle_keys(_press(inp, ["PadBack"], true))
	t.check(menu.controls.is_open, "the pad's View opens Controls")
	menu.handle_keys(_press(inp, ["PadB"], true))
	t.check(not menu.controls.is_open, "the pad's B closes it")
	var closed := [0]
	menu.controls.closed.connect(func() -> void: closed[0] += 1)
	menu.show_controls(true)
	menu.controls.close_button.pressed.emit()
	t.check(not menu.controls.is_open and closed[0] == 1, "the Close button closes it")
	menu.handle_keys(_press(inp, ["KeyO"]))
	t.check(menu.settings.is_open, "O opens Settings")
	menu.handle_keys(_press(inp, ["Escape"]))
	t.check(not menu.settings.is_open, "Esc closes Settings")
	hm[0].free()


func _menu_pad(t) -> void:
	t.section("menu gamepad (menu.js handlePad)")
	Fx.save_data_v5()
	var hm := _menu(t)
	var menu: MainMenu = hm[1]
	var inp := Fx.FakeInput.new()
	menu.handle_keys(_press(inp, ["NavDown"], true))
	t.check(menu.pad_target() == menu.get("_tiles")[9] and menu.selected_track == 9, "the first press only shows the highlight (on the track)")
	menu.handle_keys(_press(inp, ["NavDown"], true))
	t.check(menu.pad_target() == menu.get("_tiles")[14] and menu.selected_track == 14, "down a row: track 15 (Summit Rush, the third row of five)")
	menu.handle_keys(_press(inp, ["NavDown"], true))
	t.check(menu.pad_target() == menu.car_card(), "down from the bottom row: the picked car")
	menu.handle_keys(_press(inp, ["NavRight"], true))
	t.check(UiData.picked_car() == "kestrel" and menu.pad_target() == menu.car_card(), "right on the cars picks the Kestrel")
	menu.handle_keys(_press(inp, ["PadRB"], true))
	t.check(UiData.picked_car() == "thunder" and menu.pad_target() == menu.car_card(), "RB picks the next car, the highlight follows")
	menu.handle_keys(_press(inp, ["PadA"], true))
	t.check(menu.pad_target() == menu.get("_tiles")[14], "A on a car goes back to the tracks")
	menu.handle_keys(_press(inp, ["NavLeft"], true))
	t.check(menu.selected_track == 13, "left on the tracks moves to the previous track")
	menu.handle_keys(_press(inp, ["NavUp"], true))
	t.check(menu.selected_track == 8, "up a row")
	menu.handle_keys(_press(inp, ["NavUp"], true))
	t.check(menu.selected_track == 3, "up a row again: the top row")
	menu.handle_keys(_press(inp, ["NavUp"], true))
	t.check(menu.pad_target() == menu.get("_controls_btn"), "up from the top row: the Controls button")
	menu.handle_keys(_press(inp, ["NavLeft"], true))
	t.check(menu.pad_target() == menu.get("_settings_btn"), "left along the header: the Settings button")
	menu.handle_keys(_press(inp, ["PadA"], true))
	t.check(menu.settings.is_open, "A presses it: Settings opens")
	menu.handle_keys(_press(inp, ["PadB"], true))
	t.check(not menu.settings.is_open, "B closes Settings")
	menu.handle_keys(_press(inp, ["NavDown"], true))
	t.check(menu.pad_target() == menu.get("_settings_btn"), "after a screen closes, the first press shows the highlight where it was")
	menu.handle_keys(_press(inp, ["NavDown"], true))
	t.check(menu.pad_target() == menu.get("_tiles")[3], "down from the header: back to the tracks (the tile under the Settings button)")
	menu.handle_keys(_press(inp, ["PadLB"], true))
	t.check(UiData.picked_car() == "kestrel", "LB picks the previous car from anywhere")
	var drives := [0]
	menu.drive.connect(func() -> void: drives[0] += 1)
	menu.handle_keys(_press(inp, ["PadA"], true))
	t.check(drives[0] == 1, "A on a track drives")
	menu.handle_keys(_press(inp, ["ArrowRight"], false))
	t.check(menu.pad_target() == null, "a key press hides the highlight")
	UiData.set_setting("car", "racer")
	hm[0].free()


func _settings(t) -> void:
	t.section("Settings screen")
	UiData.reset()
	var h := _holder(t)
	var s := SettingsScreen.new()
	s.apply_display = false
	h.add_child(s)
	s.open()
	_settle(h)
	var inp := Fx.FakeInput.new()
	var got := []
	s.setting_changed.connect(func(k: String, v: Variant) -> void: got.append([k, v]))
	t.check(s.selected_row == 0 and UiData.get_setting("quality") == "high", "first row (quality), High")
	s.handle_keys(_press(inp, ["ArrowRight"]))
	t.check(UiData.get_setting("quality") == "low" and got == [["quality", "low"]], "right: Low, and setting_changed")
	s.handle_keys(_press(inp, ["ArrowRight"]))
	t.check(UiData.get_setting("quality") == "high", "right again wraps to High")
	s.handle_keys(_press(inp, ["ArrowDown"]))
	s.handle_keys(_press(inp, ["Enter"]))
	t.check(s.selected_row == 1 and UiData.get_setting("fullscreen") == true, "down, Enter: Fullscreen on")
	for i in 2:
		s.handle_keys(_press(inp, ["ArrowDown"]))
	s.handle_keys(_press(inp, ["ArrowRight"]))
	t.check(is_equal_approx(float(UiData.get_setting("ui_scale")), 1.0), "Interface size: Auto -> 100%")
	s.handle_keys(_press(inp, ["ArrowLeft"]))
	t.check(UiData.get_setting("ui_scale") == "auto", "and back to Auto")
	s.handle_keys(_press(inp, ["ArrowUp", ]))
	t.check(s.selected_row == 2, "up a row")
	var acted := []
	s.action.connect(func(k: String) -> void: acted.append(k))
	var rows: Array = s.get("_rows")
	var last: Dictionary = rows[rows.size() - 1]
	t.check(str(last.def.key) == "terminal" and str(last.def.type) == "action" and str(last.def.section) == "Career" and
		(last.segs[0] as Button).has_meta("label") and str((last.segs[0] as Button).get_meta("label").text) == "Open",
		"the last row is the Terminal (v6.7.0, section Career): an Open button with its ` key cap")
	s.step_row(rows.size() - 1, 1)
	(last.segs[0] as Button).pressed.emit()
	t.check(acted == ["terminal", "terminal"], "Enter on the Terminal row and a click on Open emit action(\"terminal\")")
	acted.clear()
	s.add_row({"section": "Tools", "key": "tool", "label": "A tool", "type": "action", "button": "Open", "hint": "A test row."})
	s.step_row(s.get("_rows").size() - 1, 1)
	t.check(acted == ["tool"], "an added action row emits action(key)")
	s.handle_keys(_press(inp, ["PadB"], true))
	t.check(not s.is_open, "B closes it")
	h.free()
	UiData.reset()


## A stand-in for game/terminal.gd: run echoes the line (or closes / clears / changes on
## exit / clear / money), complete offers some names.
class FakeTerminal:
	extends RefCounted
	var ran: Array = []
	func run(line: String) -> Dictionary:
		ran.append(line)
		var w := line.strip_edges()
		return {"lines": [["ok", "ran " + w], ["row", "Money", "$5"]], "changed": w.begins_with("money"), "close": w == "exit", "clear": w == "clear"}
	func complete(line: String) -> Dictionary:
		if line == "mo":
			return {"line": "money ", "options": ["money"]}
		if line == "c":
			return {"line": "c", "options": ["car", "clear"]}
		return {"line": line, "options": []}


## A key press through the viewport (as a keyboard sends it to the focused control).
func _type_key(t, code: Key, ch: String = "", ctrl := false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.unicode = ch.unicode_at(0) if ch != "" else 0
	e.ctrl_pressed = ctrl
	e.pressed = true
	t.tree.root.push_input(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	up.unicode = 0
	t.tree.root.push_input(up)


func _terminal(t) -> void:
	t.section("the terminal screen (v6.7.0)")
	UiData.reset()
	var h := _holder(t)
	var term := TerminalScreen.new()
	h.add_child(term)
	var fake := FakeTerminal.new()
	term.commands = fake
	var changes := [0]
	term.changed.connect(func() -> void: changes[0] += 1)
	term.open()
	_settle(h)
	t.check(term.is_open and term.line.has_focus() and term.log_text().contains("Type help for the commands"), "open: the input has the focus, a welcome line in the log")
	for ch in "hi":
		_type_key(t, (ch.to_upper().unicode_at(0)) as Key, ch)
	_type_key(t, KEY_ENTER)
	t.check(fake.ran == ["hi"] and term.line.text == "" and term.log_text().contains("> hi") and term.log_text().contains("ran hi") and
		term.log_text().contains("Money") and term.history == PackedStringArray(["hi"]), "typing hi and Enter (key events): the line runs, the log shows it and the result (a row too); the input is empty")
	term.submit("money 5")
	term.submit("money 5")
	t.check(changes[0] == 2 and term.history == PackedStringArray(["hi", "money 5"]), "a command that changed the career emits changed; the same line twice is kept once in the history")
	_type_key(t, KEY_D, "d")
	_type_key(t, KEY_UP)
	var a := term.line.text
	_type_key(t, KEY_UP)
	var b := term.line.text
	_type_key(t, KEY_UP)
	var c := term.line.text
	_type_key(t, KEY_DOWN)
	_type_key(t, KEY_DOWN)
	var d := term.line.text
	_type_key(t, KEY_DOWN)
	t.check(a == "money 5" and b == "hi" and c == "hi" and d == "d" and term.line.text == "d" and term.line.has_focus(), "Up / Down: the lines run before (newest first, stopping at the oldest), then back to what was being typed (%s, %s, %s, %s)" % [a, b, c, d])
	term.line.text = "mo"
	term.line.caret_column = 2
	_type_key(t, KEY_TAB)
	t.check(term.line.text == "money " and term.line.caret_column == 6 and term.line.has_focus(), "Tab completes mo to \"money \" (the focus stays on the input)")
	term.line.text = "c"
	_type_key(t, KEY_TAB)
	t.check(term.line.text == "c" and term.log_text().contains("Tab: car, clear"), "Tab with several matches lists them")
	term.line.text = ""
	_type_key(t, KEY_QUOTELEFT, "`")
	_type_key(t, KEY_ESCAPE)
	t.check(term.line.text == "" and term.is_open, "` and Esc type nothing into the input (handle_keys closes on them)")
	var inp := Fx.FakeInput.new()
	term.handle_keys(_press(inp, ["KeyO", "Enter", "Digit1"]))
	t.check(term.is_open, "other keys leave it open")
	for code: String in ["Backquote", "Escape", "PadB", "PadStart"]:
		term.open()
		inp.clear_pressed()
		term.handle_keys(_press(inp, [code], code.begins_with("Pad")))
		t.check(not term.is_open and not term.line.has_focus(), "%s closes it (the input lets go of the focus)" % code)
	term.open()
	term.submit("clear")
	t.check(not term.log_text().contains("ran hi") and term.log_text().contains("ran clear"), "a command that clears: the log starts over")
	_type_key(t, KEY_L, "l", true)
	t.check(term.log_text().strip_edges() == "" and term.line.text == "", "Ctrl+L clears the log")
	term.submit("exit")
	t.check(not term.is_open, "a command that closes (exit) closes it")
	term.open()
	for i in TerminalScreen.MAX_LINES:
		term.print_lines([["info", "line %d" % i]])
	t.check((term.get("_entries") as Array).size() == TerminalScreen.MAX_LINES and term.log_text().contains("line %d" % (TerminalScreen.MAX_LINES - 1)) and
		not term.log_text().contains("ran clear"), "the log keeps the last %d lines" % TerminalScreen.MAX_LINES)
	for i in TerminalScreen.MAX_HISTORY + 10:
		term.submit("x%d" % i)
	t.check(term.history.size() == TerminalScreen.MAX_HISTORY and term.history[term.history.size() - 1] == "x%d" % (TerminalScreen.MAX_HISTORY + 9), "the history keeps the last %d lines" % TerminalScreen.MAX_HISTORY)
	term.commands = null
	term.submit("anything")
	t.check(term.log_text().contains("No commands here"), "without commands it says so (no script error)")
	term.close()
	h.free()

	t.section("the terminal on the menu (v6.7.0)")
	Fx.save_data_v5()
	var hm := _menu(t)
	var menu: MainMenu = hm[1]
	menu.terminal.commands = FakeTerminal.new()
	inp = Fx.FakeInput.new()
	menu.handle_keys(_press(inp, ["Backquote"]))
	t.check(menu.terminal.is_open and menu.terminal.line.has_focus(), "` on the menu opens the terminal")
	var drives := [0]
	menu.drive.connect(func() -> void: drives[0] += 1)
	var sel := menu.selected_track
	menu.handle_keys(_press(inp, ["KeyO", "KeyH", "KeyC", "Digit3", "Enter", "ArrowRight"]))
	t.check(menu.terminal.is_open and not menu.settings.is_open and not menu.controls.is_open and drives[0] == 0 and menu.selected_track == sel and
		UiData.picked_car() == "racer", "keys typed into it never reach the menu (O, H, C, 3, Enter, →)")
	menu.handle_keys(_press(inp, ["Escape"]))
	t.check(not menu.terminal.is_open and not menu.settings.is_open, "Esc closes it")
	menu.handle_keys(_press(inp, ["KeyO"]))
	menu.handle_keys(_press(inp, ["Backquote"]))
	t.check(menu.terminal.is_open and menu.settings.is_open, "` on Settings opens it over Settings")
	menu.handle_keys(_press(inp, ["Backquote"]))
	t.check(not menu.terminal.is_open and menu.settings.is_open, "` closes it: back to Settings")
	var srows: Array = menu.settings.get("_rows")
	menu.settings.selected_row = srows.size() - 1
	menu.handle_keys(_press(inp, ["PadA"], true))
	t.check(menu.terminal.is_open, "pad A on Settings' Terminal row opens it")
	menu.handle_keys(_press(inp, ["PadB"], true))
	menu.handle_keys(_press(inp, ["PadB"], true))
	t.check(not menu.terminal.is_open and not menu.settings.is_open, "pad B closes it, then Settings")
	menu.handle_keys(_press(inp, ["KeyH"]))
	menu.handle_keys(_press(inp, ["Backquote"]))
	t.check(menu.controls.is_open and not menu.terminal.is_open, "on Controls ` does nothing")
	menu.handle_keys(_press(inp, ["Escape"]))
	menu.show_terminal(true)
	menu.handle_keys(_press(inp, []))
	menu.terminal.submit("exit")
	menu.handle_keys(_press(inp, ["Enter"])) # (the Enter that ran exit, read by the menu in the same frame)
	t.check(not menu.terminal.is_open and drives[0] == 0, "exit + Enter closes it without driving (that frame's keys were typed into it)")
	menu.handle_keys(_press(inp, ["Enter"]))
	t.check(drives[0] == 1, "the next Enter drives again")
	menu.show_terminal(true)
	menu.show_menu(false)
	t.check(not menu.terminal.is_open, "leaving the menu closes it")
	hm[0].free()
	UiData.reset()


func _hud(t) -> void:
	t.section("race HUD states (hud.js)")
	Fx.save_data_v5()
	var h := _holder(t)
	var hud := RaceHud.new()
	h.add_child(hud)
	hud.show_hud(true)
	var s := Fx.hud_drive()
	hud.update(s, 0.016)
	_settle(h)
	t.check(hud.get("_time").text == "0:57.533" and hud.get("_lap_val").text == "1/3" and hud.get("_cp_val").text == "6/7", "time, lap and checkpoint")
	t.check(hud.get("_speed").text == "154" and hud.get("_points").text == "10,000" and hud.get("_combo_l").text == "x5", "speed, score, combo")
	t.check(hud.get("_medal_plate").visible and hud.get("_medal_val").text == "3:28.000", "the next medal under the best time")
	var w0: float = hud.get("_time").get_combined_minimum_size().x
	s.time = 51.111
	hud.update(s, 0.016)
	t.check(is_equal_approx(hud.get("_time").get_combined_minimum_size().x, w0), "the time keeps its width while the digits change")
	s.best = null
	s.medal = null
	s.nitro = null
	s.score = null
	s.sprint = true
	hud.update(s, 0.016)
	t.check(hud.get("_best_val").text == "—", "no best time shows a dash")
	t.check(not hud.get("_medal_plate").visible and not hud.get("_nitro").visible and not hud.get("_score_plate").visible,
		"no medal, nitro or score: their plates go")
	t.check(hud.get("_lap_lbl").text == "Sprint" and not hud.get("_lap_val").get_parent().visible, "a sprint shows 'Sprint' and no lap count")
	s = Fx.hud_drive()
	s.time = 300.0
	hud.update(s, 0.016)
	t.check(hud.get("_medal_strike").visible and not hud.get("_medal_check").visible, "past the medal time: struck through")
	s.finished = true
	s.time = 200.0
	hud.update(s, 0.016)
	t.check(hud.get("_medal_check").visible, "finished inside it: ticked")
	t.check(NitroGauge.state_for(0.0, false) == "empty" and NitroGauge.state_for(50.0, true) == "boost" and NitroGauge.state_for(20.0, false) == "low"
		and NitroGauge.state_for(60.0, false) == "", "nitro gauge states")
	hud.score_pops(Fx.pops())
	hud.score_pops(Fx.pops())
	t.check(hud.get("_pops").size() == RaceHud.POP_MAX, "at most %d popups" % RaceHud.POP_MAX)
	hud.show_panel(Fx.panel_finish())
	t.check(hud.panel_open and not hud.get("_speed_row").visible and not hud.get("_keys").visible, "the finish panel hides speed and key hints")
	hud.hide_panel()
	t.check(not hud.panel_open and hud.get("_keys").visible, "and they come back")
	h.free()


func _finish(t) -> void:
	t.section("finish panel (playMode.js onFinish)")
	var h := _holder(t)
	var f := FinishPanel.new()
	h.add_child(f)
	f.set_window_size(Vector2(1280, 720))
	f.update(Fx.panel_finish())
	_settle(h)
	var texts := _texts(f)
	t.check(texts.has("3:41.967") and texts.has("Silver medal") and texts.has("+6.917") and texts.has("+13.967"), "time, medal, deltas to the best and the next medal")
	t.check(texts.has("Nitro earned: 2.5 tanks") and texts.has("+40,000") and texts.has("−560"), "breakdown points and the nitro note")
	t.check(f.get("_bd_rows").size() == 4, "four breakdown rows")
	var p := Fx.panel_record()
	p.score.nitro_earned = 1.0
	p.score.nitro_lost = 0.0
	f.update(p)
	texts = _texts(f)
	t.check(texts.has("Nitro earned: 1.0 tank") and texts.has("New personal best") and texts.has("New best score"), "one tank; record and best-score lines")
	f.update(Fx.panel_stress())
	texts = _texts(f)
	t.check(texts.has("12:34.321") and texts.has("1,234,567") and texts.has("No medal: bronze is 4:53.000"), "12-minute time, a seven-digit score, no medal")
	f.set_window_size(Vector2(800, 600))
	_settle(h)
	t.check(is_equal_approx(f.size.x, 800.0 - 24.0), "narrow window: full width less 24 px (%s)" % f.size.x)
	h.free()


## v6.5.0: money, points, the car shop and the AI opponents on the menu (the in-memory store's
## career), and the finish panel's payout block.
func _career(t) -> void:
	t.section("money, points, the car shop and the AI opponents (v6.5.0)")
	t.check(UiFormat.money(12345) == "$12,345" and UiFormat.money(0) == "$0" and UiFormat.money(-50) == "−$50", "money: $12,345, $0, −$50")
	Fx.save_data_v5()
	UiData.store.career.money = 15000
	UiData.store.career.points = 1234
	var hm := _menu(t)
	var menu: MainMenu = hm[1]
	var money_l: Label = menu.get("_money_l")
	var points_l: Label = menu.get("_points_l")
	t.check(money_l.text == "$15,000" and points_l.text == "1,234 pts" and money_l.is_visible_in_tree() and
		money_l.get_global_rect().end.x <= 1280.0 and money_l.get_global_rect().position.y >= 0.0, "the header shows the money and the points: %s, %s" % [money_l.text, points_l.text])
	var cards: Array = menu.get("_cards")
	var locked: Array = []
	var can: Array = []
	for c: Control in cards:
		if c.get("locked"):
			locked.append(c.get("car_id"))
		if c.get("affordable"):
			can.append(c.get("car_id"))
	t.check(locked == ["kestrel", "thunder", "drifter", "dune", "vortex"] and int(cards[1].get("price")) == 10000 and can.has("kestrel") and can.has("drifter") and
		not can.has("vortex"), "five cars locked, each with its price (the Kestrel $10,000); with $15,000 the Kestrel and the Drifter are affordable")
	var drive_btn: Button = menu.get("_drive_btn")
	var lock: Label = menu.get("_car_lock")
	t.check(drive_btn.text == "DRIVE" and not lock.visible, "the Racer (owned): DRIVE")
	UiData.set_setting("car", "drifter")
	menu.refresh()
	t.check(drive_btn.text == "BUY $14,000" and lock.visible and lock.text.contains("$14,000") and (menu.get("_car_desc_name") as Label).text == "Drifter" and
		(menu.get("_car_desc") as Label).text != "", "the Drifter picked: BUY $14,000, its stats and description still shown")
	UiData.set_setting("car", "vortex")
	menu.refresh()
	t.check(drive_btn.text == "LOCKED" and drive_btn.tooltip_text.contains("$15,000 more to go") and (menu.get("_ghost_btn") as Button).disabled,
		"the Vortex ($30,000): LOCKED, $15,000 more to go; Race the AI off")
	var r1 := UiData.buy_car("drifter")
	var r2 := UiData.buy_car("vortex")
	var r3 := UiData.buy_car("drifter")
	menu.refresh()
	t.check(r1.ok and not r2.ok and r2.error == "money" and int(r2.short) == 29000 and r3.error == "owned" and UiData.money() == 1000 and
		UiData.owns_car("drifter") and not cards[3].get("locked") and money_l.text == "$1,000", "buying the Drifter: $1,000 left, its card unlocked; the Vortex is $29,000 short")
	# the opponent picker
	UiData.set_setting("car", "racer")
	var btns: Dictionary = menu.get("_opp_btns")
	menu.refresh()
	t.check(btns.size() == 6 and btns.has(UiData.MY_AI) and UiData.opponent() == "rookie" and (btns["rookie"] as Button).theme_type_variation == "ChipOnButton" and
		(btns["pro"] as Button).theme_type_variation == "ChipButton", "six opponent chips (Rookie to Elite, My AI); the Rookie by default")
	menu.select_opponent("pro")
	var tid := UiData.track_id(menu.selected_track)
	var pro_t := Opponents.time_of(tid, "racer", "pro")
	var pays := Economy.payout(tid, "", "pro", PackedStringArray())
	var st := str(menu.get("_ai_status_text"))
	t.check(UiData.opponent() == "pro" and (btns["pro"] as Button).theme_type_variation == "ChipOnButton" and (menu.get("_ghost_btn") as Button).text == "Race the Pro AI" and
		(menu.get("_watch_btn") as Button).text == "Watch the Pro AI" and st.contains("Pro AI") and st.contains(UiFormat.time(pro_t)) and
		st.contains("+" + UiFormat.money(int(pays.money))) and not (menu.get("_ghost_btn") as Button).disabled,
		"Pro picked: Race / Watch the Pro AI; it finishes %s in %s; beating it pays %s (Rookie, Amateur and Pro)" % [tid, UiFormat.time(pro_t), UiFormat.money(int(pays.money))])
	UiData.store.career.paid["%s|racer" % tid] = ["ai-rookie", "ai-amateur", "ai-pro"]
	menu.refresh()
	t.check(str(menu.get("_ai_status_text")).contains("Beaten: paid") and UiData.opponent_levels(tid, "racer")[2].paid and
		int(UiData.opponent_levels(tid, "racer")[3].pays.money) == int(Economy.reward(tid, "ai-expert").money), "beaten before: paid; the Expert now pays only its own reward")
	UiData.set_setting("opponent", "nobody")
	t.check(UiData.opponent() == "rookie", "an unknown stored opponent reads as the Rookie")
	menu.select_opponent(UiData.MY_AI)
	t.check((menu.get("_ghost_btn") as Button).text == "Race my AI" and (btns[UiData.MY_AI] as Button).theme_type_variation == "ChipOnButton", "My AI: the car's own network")
	# 1280 x 720: the six opponent chips share the side panel's width in one row (the heights need
	# real frames: the e2e menu and economy scenarios check that the whole menu fits)
	_settle(hm[0])
	var fit := true
	var side: Rect2 = (menu.get("_side") as Control).get_global_rect()
	var y0: float = (btns["rookie"] as Button).get_global_rect().position.y
	for b: Button in btns.values():
		var r := b.get_global_rect()
		fit = fit and r.position.x >= side.position.x - 0.5 and r.end.x <= side.end.x + 0.5 and r.end.x <= 1280.5 and r.size.x >= 40.0 and \
			is_equal_approx(r.position.y, y0) and \
			b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x + \
			b.get_theme_stylebox("normal").get_minimum_size().x <= r.size.x + 0.5
	t.check(fit, "1280 x 720: the six opponent chips in one row across the side panel, each name whole (each %d px wide)" % roundi((btns["rookie"] as Button).size.x))
	hm[0].free()

	# the finish panel's payout
	var h := _holder(t)
	var f := FinishPanel.new()
	h.add_child(f)
	f.set_window_size(Vector2(1280, 720))
	var p := Fx.panel_payout()
	f.update(p)
	_settle(h)
	var texts := _texts(f)
	var want_m: int = 0
	for id: String in ["silver", "gold", "ai-rookie", "ai-amateur", "ai-pro"]:
		want_m += int(Economy.reward("night-highway", id).money)
	t.check(int(p.payout.money) == want_m and texts.has("Earned") and texts.has("+" + UiFormat.money(want_m)) and texts.has("+%d pts" % int(p.payout.points)) and
		texts.has("You have $24,350 · 862 pts") and texts.has("Silver medal") and texts.has("Gold medal") and texts.has("Beat the Pro AI") and
		texts.has("+" + UiFormat.money(int(Economy.reward("night-highway", "gold").money))) and texts.has("Paid before: Bronze medal") and
		texts.has("Pro AI: 3:40.000, you win by 12.567 s!"), "payout: EARNED %s and %d pts, each reward (silver and gold, the Rookie, Amateur and Pro wins), the totals, what was paid before" % [
		UiFormat.money(want_m), int(p.payout.points)])
	t.check(f.get_global_rect().end.y <= 720.5 and f.get_global_rect().position.y >= -0.5, "with the payout the panel fits 1280 x 720 (%d px high)" % roundi(f.size.y))
	p.payout = {"items": [], "money": 0, "points": 0, "money_total": 100, "points_total": 5, "repeat": ["bronze", "silver"], "medal": "silver", "level": "", "won": false}
	f.update(p)
	texts = _texts(f)
	t.check(texts.has("+$0") and texts.has("Nothing new: Bronze medal, Silver medal paid before. A better medal or a harder AI pays more."), "nothing new: says what was paid before")
	p.payout = {"items": [], "money": 0, "points": 0, "money_total": 0, "points_total": 0, "repeat": [], "medal": "", "level": "elite", "won": false}
	f.update(p)
	t.check(_texts(f).has("No medal and no win: beat the bronze time or the Elite AI to earn money."), "no medal, lost to the Elite: how to earn money")
	f.set_window_size(Vector2(800, 600))
	f.update(Fx.panel_payout())
	_settle(h)
	t.check(f.get_global_rect().end.y <= 600.5, "800 x 600: the payout panel still fits (%d px high)" % roundi(f.size.y))
	h.free()
	UiData.reset()


func _texts(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if n is Label:
		out.append((n as Label).text.strip_edges())
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


func _scale(t) -> void:
	t.section("interface size (UiRoot)")
	t.check(UiRoot.scale_for(Vector2(1280, 720), "auto") == 1.0 and UiRoot.scale_for(Vector2(1920, 1080), "auto") == 1.0, "Auto: 100% up to 1920 x 1080")
	t.check(is_equal_approx(UiRoot.scale_for(Vector2(2560, 1440), "auto"), 2560.0 / 1920.0) and UiRoot.scale_for(Vector2(3840, 2160), "auto") == 2.0,
		"Auto grows with bigger windows (2 at 3840 x 2160)")
	t.check(UiRoot.scale_for(Vector2(1024, 600), "auto") == 1.0 and UiRoot.scale_for(Vector2(1920, 1080), 1.5) == 1.5, "small windows 100%; a set size is kept")
	var c := CheckToggle.new()
	t.tree.root.add_child(c) # (minimum sizes update only in the tree)
	var on := []
	c.toggled.connect(func(v: bool) -> void: on.append(v))
	c.text = "Race my best-run ghost"
	var one := c.get_combined_minimum_size()
	c.wrap_width = 100.0
	var two := c.get_combined_minimum_size()
	t.check(two.y > one.y and two.x < one.x, "the check box label wraps when told to")
	c.press()
	c.disabled = true
	c.press()
	t.check(on == [true], "the check box toggles, not while disabled")
	c.free()
	var f := UiStyle.font("text", UiStyle.FS_S)
	var wrapped := UiStyle.wrap_text("Gamepad connected: Xbox Wireless Controller · RT accelerate · LT brake", f, UiStyle.FS_S, 150.0)
	var ok := wrapped.split("\n").size() > 1
	for line in wrapped.split("\n"):
		ok = ok and (f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x <= 150.0 or not line.contains(" "))
	t.check(ok, "wrap_text keeps lines within the width")
