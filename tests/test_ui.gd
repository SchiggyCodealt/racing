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


const VolumeBarScript := preload("res://ui/volume_bar.gd")


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
	_settings_audio(t)
	_terminal(t)
	_hud(t)
	_finish(t)
	_career(t)
	_upgrades(t)
	_unlocks(t)
	_field_ui(t)
	_cup_ui(t)
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
	t.section("the car page (v6.19.0): six cars at every window size")
	Fx.save_data_v5()
	for sz: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1366, 768), Vector2(1024, 600), Vector2(900, 700), Vector2(700, 900)]:
		var h := _holder(t, sz)
		var menu := MainMenu.new()
		h.add_child(menu)
		menu.show_menu(true)
		menu.ask_car("drive")
		_settle(h)
		var grid: GridContainer = menu.car_page.cars_grid
		var cards: Array = menu.car_page.cards
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
		# at 1280 x 720 and up the page shows every car, the parts and START without scrolling
		var all_shown := true
		if sz.x >= 1280:
			for r in rects:
				all_shown = all_shown and r.end.y <= sz.y + 0.5
			all_shown = all_shown and menu.car_page.start_btn.get_global_rect().end.y <= sz.y + 0.5 and menu.car_page.parts_row.is_visible_in_tree()
		t.check(menu.car_page.is_open and cards.size() == 6 and inside and not overlap and cols_ok and all_shown,
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
		# from 1280 x 720 up every tile is on screen without scrolling (the e2e menu scenario checks the
		# whole menu with real frames)
		var on_screen := bottom <= sz.y + 0.5 if sz.x >= 1280 else true
		t.check(tiles.size() == 15 and menu.columns == int(case[1]) and inside and not overlap and on_screen,
			"%dx%d: %d tiles, %d a row, inside the window and apart%s" % [sz.x, sz.y, tiles.size(), menu.columns,
				", every tile on screen (lowest ends at %d px, maps %d px)" % [roundi(bottom), roundi(menu.map_h)] if sz.x >= 1280 else ""])
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
	t.check(menu.car_page.is_open and drives[0] == 0 and menu.pending == "drive" and
		menu.car_page.event_text == "Time trial · %s %s" % [UiFormat.track_number(0), UiData.track_info(0).name],
		"v6.19: Enter chooses a time trial and the car page opens first (\"%s\"); nothing starts yet" % menu.car_page.event_text)
	menu.handle_keys(_press(inp, ["KeyC"]))
	var c_next := UiData.picked_car()
	menu.handle_keys(_press(inp, ["ArrowLeft"]))
	var back := UiData.picked_car()
	menu.handle_keys(_press(inp, ["ArrowDown"]))
	var below := UiData.picked_car()
	menu.handle_keys(_press(inp, ["ArrowUp", "Digit3"]))
	t.check(c_next == "kestrel" and back == "racer" and below == "drifter" and UiData.picked_car() == "racer" and menu.selected_track == 0 and
		menu.car_page.card() == menu.car_page.cards[0] and menu.car_page.cards[0].selected,
		"on the car page C and the arrows pick the car (three a row: down from the Racer is the Drifter); the track keys do nothing there")
	menu.handle_keys(_press(inp, ["NumpadEnter"]))
	t.check(drives[0] == 1 and menu.car_page.start_btn.text == "START", "Enter on the car page starts (START): drive goes out")
	menu.handle_keys(_press(inp, ["Escape"]))
	t.check(not menu.car_page.is_open and drives[0] == 1, "Esc goes back to the menu without starting")
	(menu.get("_ghost_btn") as Button).pressed.emit()
	var ghosts := [0]
	menu.race_ghost.connect(func() -> void: ghosts[0] += 1)
	var ev := menu.car_page.event_text
	menu.car_page.start_btn.pressed.emit()
	menu.car_page.close()
	(menu.get("_field_btn") as Button).pressed.emit()
	var fields := [0]
	menu.race_field.connect(func() -> void: fields[0] += 1)
	var ev2 := menu.car_page.event_text
	menu.handle_keys(_press(inp, ["Space"]))
	menu.show_car_page(false)
	t.check(ghosts[0] == 1 and fields[0] == 1 and drives[0] == 1 and ev.begins_with("Race the Rookie AI · ") and ev.ends_with("no nitro") and ev2.begins_with("Race the field (Rookie) · "),
		"Race the AI and Race the field ask for the car too (\"%s\", \"%s\"); START sends race_ghost / race_field" % [ev, ev2])
	menu.handle_keys(_press(inp, ["KeyH"]))
	t.check(menu.controls.is_open, "H opens the Controls screen")
	menu.handle_keys(_press(inp, ["Digit3", "Enter"]))
	t.check(not menu.controls.is_open and menu.selected_track == 0 and drives[0] == 1 and not menu.car_page.is_open, "on Controls, Enter only closes it")
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
	t.check(menu.pad_target() == menu.get("_drive_btn"), "down from the bottom row: TIME TRIAL (v6.19: the race buttons)")
	menu.handle_keys(_press(inp, ["NavDown"], true))
	var under: Control = menu.pad_target()
	menu.handle_keys(_press(inp, ["NavUp"], true))
	t.check(under != menu.get("_drive_btn") and under != null and menu.pad_target() == menu.get("_drive_btn"), "down and up along the race buttons")
	menu.handle_keys(_press(inp, ["PadRB"], true))
	menu.handle_keys(_press(inp, ["PadRB"], true))
	t.check(UiData.picked_car() == "thunder" and menu.pad_target() == menu.get("_drive_btn"), "RB picks the next car (the records shown), the highlight stays")
	menu.handle_keys(_press(inp, ["NavLeft"], true))
	t.check(menu.pad_target() == menu.get("_tiles")[14], "left from the buttons goes back to the tracks")
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
	t.check(menu.car_page.is_open and drives[0] == 0 and menu.pad_target() == null, "A on a track chooses a time trial: the car page opens")
	UiData.set_setting("car", "racer")
	menu.refresh()
	_settle(hm[0])
	menu.handle_keys(_press(inp, ["NavRight"], true))
	t.check(menu.car_page.pad_target() == menu.car_page.card() and UiData.picked_car() == "racer", "on the car page the first press only shows the highlight (on the picked car)")
	menu.handle_keys(_press(inp, ["NavRight"], true))
	t.check(UiData.picked_car() == "kestrel" and menu.car_page.pad_target() == menu.car_page.card(), "right picks the Kestrel, the highlight follows")
	menu.handle_keys(_press(inp, ["PadLB"], true))
	menu.handle_keys(_press(inp, ["NavDown"], true))
	t.check(UiData.picked_car() == "drifter", "LB back to the Racer, down a row: the Drifter")
	menu.handle_keys(_press(inp, ["PadLB"], true))
	menu.handle_keys(_press(inp, ["PadLB"], true))
	menu.handle_keys(_press(inp, ["PadLB"], true))
	menu.handle_keys(_press(inp, ["NavDown"], true))
	menu.handle_keys(_press(inp, ["NavDown"], true))
	var on_chip: bool = menu.car_page.part_chips.has(menu.car_page.pad_target())
	menu.handle_keys(_press(inp, ["NavDown"], true))
	t.check(UiData.picked_car() == "drifter" or on_chip, "down from the bottom row of cars: the parts")
	t.check(menu.car_page.pad_target() == menu.car_page.start_btn, "down from the parts: START")
	menu.handle_keys(_press(inp, ["PadA"], true))
	t.check(drives[0] == 1, "A on START starts")
	menu.handle_keys(_press(inp, ["PadB"], true))
	t.check(not menu.car_page.is_open, "B goes back to the menu")
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
	t.check(s.selected_row == 1 and UiData.get_setting("grime") == true, "down: Screen dirt and snow (v6.10.0), On by default")
	s.handle_keys(_press(inp, ["Enter"]))
	t.check(UiData.get_setting("grime") == false and got.back() == ["grime", false], "Enter: Off, and setting_changed")
	s.handle_keys(_press(inp, ["Enter"]))
	t.check(UiData.get_setting("grime") == true, "Enter again: On")
	s.handle_keys(_press(inp, ["ArrowDown"]))
	s.handle_keys(_press(inp, ["Enter"]))
	t.check(s.selected_row == 2 and UiData.get_setting("fullscreen") == true, "down, Enter: Fullscreen on")
	for i in 2:
		s.handle_keys(_press(inp, ["ArrowDown"]))
	s.handle_keys(_press(inp, ["ArrowRight"]))
	t.check(is_equal_approx(float(UiData.get_setting("ui_scale")), 1.0), "Interface size: Auto -> 100%")
	s.handle_keys(_press(inp, ["ArrowLeft"]))
	t.check(UiData.get_setting("ui_scale") == "auto", "and back to Auto")
	s.handle_keys(_press(inp, ["ArrowUp", ]))
	t.check(s.selected_row == 3, "up a row")
	var acted := []
	s.action.connect(func(k: String) -> void: acted.append(k))
	var rows: Array = s.get("_rows")
	var last: Dictionary = rows[rows.size() - 2]
	t.check(str(last.def.key) == "terminal" and str(last.def.type) == "action" and str(last.def.section) == "Career" and
		(last.segs[0] as Button).has_meta("label") and str((last.segs[0] as Button).get_meta("label").text) == "Open",
		"the Career section starts with the Terminal (v6.7.0): an Open button with its ` key cap")
	s.step_row(rows.size() - 2, 1)
	(last.segs[0] as Button).pressed.emit()
	t.check(acted == ["terminal", "terminal"], "Enter on the Terminal row and a click on Open emit action(\"terminal\")")
	acted.clear()
	# (v6.18.0) the last row: Reset all progress (the app asks twice before it wipes)
	var reset_row: Dictionary = rows[rows.size() - 1]
	t.check(str(reset_row.def.key) == "reset" and str(reset_row.def.type) == "action" and not reset_row.def.has("section") and
		(reset_row.segs[0] as Button).text == "Reset" and str(reset_row.def.hint).contains("backup"),
		"the last row is Reset all progress (v6.18.0, in Career): a Reset button; its hint names the backup")
	s.step_row(rows.size() - 1, 1)
	(reset_row.segs[0] as Button).pressed.emit()
	t.check(acted == ["reset", "reset"], "Enter on the Reset row and a click on Reset emit action(\"reset\")")
	acted.clear()
	s.add_row({"section": "Tools", "key": "tool", "label": "A tool", "type": "action", "button": "Open", "hint": "A test row."})
	s.step_row(s.get("_rows").size() - 1, 1)
	t.check(acted == ["tool"], "an added action row emits action(key)")
	s.handle_keys(_press(inp, ["PadB"], true))
	t.check(not s.is_open, "B closes it")
	h.free()
	UiData.reset()


## (v6.12.0) The Settings screen's Audio rows: volume sliders stepped by the keys, the pad and the
## mouse, the background mute toggle, the interface's sounds, and the two columns at 1280 x 720.
func _settings_audio(t) -> void:
	t.section("Settings: the Audio rows (v6.12.0)")
	UiData.reset()
	UiSound.clear()
	var h := _holder(t)
	var s := SettingsScreen.new()
	s.apply_display = false
	h.add_child(s)
	s.open()
	_settle(h)
	var inp := Fx.FakeInput.new()
	var got := []
	s.setting_changed.connect(func(k: String, v: Variant) -> void: got.append([k, v]))
	var rows: Array = s.get("_rows")
	var keys := []
	for r: Dictionary in rows:
		keys.append(str(r.def.key))
	var at := keys.find("vol_master")
	t.check(keys.slice(at, at + 5) == ["vol_master", "vol_music", "vol_sfx", "vol_engine", "mute_unfocused"] and str(rows[at].def.section) == "Audio"
		and keys.slice(at + 5) == ["terminal", "reset"], "the Audio section: Master, Music, Effects, Engines, Mute in the background (then Career's Terminal and Reset)")
	t.check(is_equal_approx(float(UiData.get_setting("vol_master")), 1.0) and is_equal_approx(float(UiData.get_setting("vol_music")), 0.7)
		and is_equal_approx(float(UiData.get_setting("vol_sfx")), 0.8) and is_equal_approx(float(UiData.get_setting("vol_engine")), 0.8)
		and UiData.get_setting("mute_unfocused") == true, "defaults: master 100%, music 70%, effects 80%, engines 80%, muted in the background")
	var bar: Control = rows[at + 1].segs[0]
	t.check(is_equal_approx(float(bar.get("value")), 0.7) and bar.call("text") == "70%", "the Music slider shows 70%")
	# keys: down to the Music row, left / right step a tenth, Enter goes up, the ends hold
	while s.selected_row != at + 1:
		s.handle_keys(_press(inp, ["ArrowDown"]))
	UiSound.clear()
	s.handle_keys(_press(inp, ["ArrowLeft"]))
	t.check(is_equal_approx(float(UiData.get_setting("vol_music")), 0.6) and got.back()[0] == "vol_music" and is_equal_approx(float(got.back()[1]), 0.6) and is_equal_approx(float(bar.get("value")), 0.6)
		and UiSound.count("ui_move") == 1, "left: 60%, setting_changed, the bar follows, one click")
	for i in 9:
		s.handle_keys(_press(inp, ["ArrowLeft"]))
	t.check(float(UiData.get_setting("vol_music")) == 0.0 and bar.call("text") == "0%" and UiSound.count("ui_move") == 7,
		"down to 0 (Off); more presses hold it there without a click")
	s.handle_keys(_press(inp, ["Enter"]))
	s.handle_keys(_press(inp, ["KeyD"]))
	t.check(is_equal_approx(float(UiData.get_setting("vol_music")), 0.2), "Enter and D step it up (20%)")
	for i in 12:
		s.handle_keys(_press(inp, ["ArrowRight"]))
	t.check(is_equal_approx(float(UiData.get_setting("vol_music")), 1.0), "up to 100% and no further")
	# the pad: the d-pad / stick left and right
	s.handle_keys(_press(inp, ["NavLeft"], true))
	t.check(is_equal_approx(float(UiData.get_setting("vol_music")), 0.9), "the pad's left (d-pad or stick): 90%")
	# the mouse: a click on the bar sets the nearest tenth
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(VolumeBarScript.STEPS * (VolumeBarScript.BLOCK_W + VolumeBarScript.BLOCK_GAP) * 0.5 - 2.0, 10.0)
	bar.call("_gui_input", ev)
	t.check(is_equal_approx(float(UiData.get_setting("vol_music")), 0.5) and s.selected_row == at + 1, "a click half way along the bar: 50%")
	# the toggle
	while s.selected_row != at + 4:
		s.handle_keys(_press(inp, ["ArrowDown"]))
	s.handle_keys(_press(inp, ["Enter"]))
	t.check(UiData.get_setting("mute_unfocused") == false and got.back() == ["mute_unfocused", false], "Mute in the background: Off with Enter")
	UiSound.clear()
	s.handle_keys(_press(inp, ["Escape"]))
	t.check(not s.is_open and UiSound.count("ui_back") == 1, "Esc closes it with the back sound")
	# the layout: two columns at 1280 x 720 (Audio and Career on the right), one at 1024 x 600
	s.open()
	s.call("_on_layout", 1280.0)
	_settle(h)
	var right: Array = s.get("_col")
	t.check(s.two_columns and (rows[at].box as Control).get_parent() == right[1] and (rows[0].box as Control).get_parent() == right[0]
		and (rows[rows.size() - 1].box as Control).get_parent() == right[1], "1280 wide: two columns, Graphics to Race on the left, Audio and Career on the right")
	s.selected_row = at - 1
	s.handle_keys(_press(inp, ["ArrowDown"]))
	t.check(s.selected_row == at, "down from the left column's last row goes to the top of the right one (Master volume)")
	s.call("_on_layout", 1024.0)
	_settle(h)
	t.check(not s.two_columns and (rows[at].box as Control).get_parent() == s.get("_list"), "1024 wide: one column, in ROWS order")
	h.free()
	UiSound.clear()
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
	UiSound.clear()
	for ch in "hi":
		_type_key(t, (ch.to_upper().unicode_at(0)) as Key, ch)
	_type_key(t, KEY_ENTER)
	t.check(fake.ran == ["hi"] and term.line.text == "" and term.log_text().contains("> hi") and term.log_text().contains("ran hi") and
		term.log_text().contains("Money") and term.history == PackedStringArray(["hi"]), "typing hi and Enter (key events): the line runs, the log shows it and the result (a row too); the input is empty")
	t.check(UiSound.count("key") == 2 and UiSound.count("key_enter") == 1, "(v6.12.0) each key clicks, Enter has its own sound")
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
	menu.settings.selected_row = srows.size() - 2
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
	t.check(not menu.terminal.is_open and drives[0] == 0 and not menu.car_page.is_open, "exit + Enter closes it without choosing a race (that frame's keys were typed into it)")
	menu.handle_keys(_press(inp, ["Enter"]))
	t.check(menu.car_page.is_open and drives[0] == 0, "the next Enter chooses a time trial again (the car page)")
	menu.show_car_page(false)
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
	menu.ask_car("drive") # (v6.19: the cars are on the car page)
	var cards: Array = menu.car_page.cards
	var locked: Array = []
	var can: Array = []
	for c: Control in cards:
		if c.get("locked"):
			locked.append(c.get("car_id"))
		if c.get("affordable"):
			can.append(c.get("car_id"))
	t.check(locked == ["kestrel", "thunder", "drifter", "dune", "vortex"] and int(cards[1].get("price")) == 10000 and can.has("kestrel") and can.has("drifter") and
		not can.has("vortex"), "five cars locked, each with its price (the Kestrel $10,000); with $15,000 the Kestrel and the Drifter are affordable")
	var drive_btn: Button = menu.car_page.start_btn
	var lock: Label = menu.car_page.car_lock
	t.check(drive_btn.text == "START" and not lock.visible and (menu.get("_drive_btn") as Button).text == "TIME TRIAL" and menu.car_page.money_l.text == "$15,000",
		"the Racer (owned): START on the car page (the menu's button reads TIME TRIAL); the page shows the money")
	UiData.set_setting("car", "drifter")
	menu.refresh()
	t.check(drive_btn.text == "BUY $14,000" and lock.visible and lock.text.contains("$14,000") and menu.car_page.car_desc_name.text == "Drifter" and
		menu.car_page.car_desc.text != "" and (menu.get("_drive_btn") as Button).text == "TIME TRIAL", "the Drifter picked: BUY $14,000, its stats and description still shown")
	UiData.set_setting("car", "vortex")
	menu.refresh()
	t.check(drive_btn.text == "LOCKED" and drive_btn.tooltip_text.contains("$15,000 more to go") and not (menu.get("_ghost_btn") as Button).disabled,
		"the Vortex ($30,000): LOCKED, $15,000 more to go (Race the AI on the menu stays on: the car is picked after it)")
	var r1 := UiData.buy_car("drifter")
	var r2 := UiData.buy_car("vortex")
	var r3 := UiData.buy_car("drifter")
	menu.refresh()
	t.check(r1.ok and not r2.ok and r2.error == "money" and int(r2.short) == 29000 and r3.error == "owned" and UiData.money() == 1000 and
		UiData.owns_car("drifter") and not cards[3].get("locked") and money_l.text == "$1,000" and menu.car_page.money_l.text == "$1,000", "buying the Drifter: $1,000 left, its card unlocked; the Vortex is $29,000 short")
	menu.show_car_page(false)
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
		(menu.get("_watch_btn") as Button).text == "Watch AI" and (menu.get("_watch_btn") as Button).tooltip_text.begins_with("Watch the Pro AI") and st.contains("Pro AI") and st.contains(UiFormat.time(pro_t)) and
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


## v6.11.0: the picked car's upgrades on the car picker (the in-memory store: career.upgrades):
## a chip per part (levels, the next price, MAX), a locked car's chips off, the bars with what the
## upgrades add, the parts row or the description in a short window (both in a taller one), the
## pad highlight to the chips and back, the store's buy_upgrade.
func _upgrades(t) -> void:
	t.section("car upgrades on the car picker (v6.11.0)")
	Fx.save_data_v5()
	UiData.store.career.money = 20000
	UiData.set_setting("car", "racer")
	var hm := _menu(t)
	var menu: MainMenu = hm[1]
	menu.ask_car("drive") # (v6.19: the upgrades are on the car page)
	_settle(hm[0])
	var chips: Array = menu.car_page.part_chips
	var parts_row: Control = menu.car_page.parts_row
	var desc_row: Control = menu.car_page.desc_row
	var names: Array = chips.map(func(c: Control) -> String: return str(c.get("part_name")))
	var prices_ok := true
	for k in chips.size():
		var pid: String = UiData.upgrade_parts()[k].id
		prices_ok = prices_ok and int(chips[k].get("price")) == Upgrades.price("racer", pid, 1) and int(chips[k].get("level")) == 0 and \
			bool(chips[k].get("affordable")) and not (chips[k] as Button).disabled
	t.check(chips.size() == 4 and names == ["Engine", "Tyres", "Nitro", "Loose grip"] and prices_ok and parts_row.is_visible_in_tree() and desc_row.is_visible_in_tree(),
		"the Racer (yours) at 1280 x 720: four part chips (Engine, Tyres, Nitro, Loose grip) at level 0 with the next level's price, over the description line")
	var tip: String = (chips[0] as Control).tooltip_text
	t.check(tip.contains("Level 1 (+5 %% power) costs %s" % UiFormat.money(Upgrades.price("racer", "engine", 1))) and tip.contains("Medal times and the AI opponents stay stock") and
		str((parts_row.get_child(0).get_child(0) as Control).tooltip_text).contains("Medal times and the AI opponents stay"),
		"the chip's tooltip: what the next level does and costs; medal times and the AI opponents stay stock (the caption says so too)")
	# buy in the store: in order, not past the top, not for a locked car, not without the money
	var r1 := UiData.buy_upgrade("racer", "engine")
	var r2 := UiData.buy_upgrade("vortex", "engine")
	var r3 := UiData.buy_upgrade("racer", "turbo")
	menu.refresh()
	t.check(r1.ok and int(r1.level) == 1 and UiData.money() == 20000 - Upgrades.price("racer", "engine", 1) and r2.error == "locked" and r3.error == "unknown" and
		UiData.upgrade_levels("racer") == PackedInt32Array([1, 0, 0, 0]) and int(chips[0].get("level")) == 1 and int(chips[0].get("price")) == Upgrades.price("racer", "engine", 2),
		"buying the Racer's engine: level 1, the chip shows the next price; a locked car or an unknown part: nothing")
	UiData.store.career.money = 10
	menu.refresh()
	var r4 := UiData.buy_upgrade("racer", "tyres")
	t.check(not r4.ok and r4.error == "money" and int(r4.short) == Upgrades.price("racer", "tyres", 1) - 10 and not bool(chips[1].get("affordable")) and
		(chips[1] as Control).tooltip_text.contains("more to go"), "$10: the chips' prices are grey, the store says how much is missing")
	# everything at level 3: the chips offer level 4 (v6.16); the card's bars at 3
	UiData.store.career.upgrades = {"racer": [3, 3, 3, 3]}
	UiData.store.career.money = 100000
	menu.refresh()
	var at3 := true
	for k in chips.size():
		at3 = at3 and not (chips[k] as Button).disabled and int(chips[k].get("level")) == 3 and int(chips[k].get("max_level")) == 10 and \
			int(chips[k].get("price")) == Upgrades.price("racer", UiData.upgrade_parts()[k].id, 4)
	var b3: Dictionary = (menu.car_card().get("bars_up") as Dictionary).duplicate()
	var top3: float = float(menu.car_card().get("top_up"))
	t.check(at3, "v6.16: everything at level 3 is not the top: each chip offers level 4 of 10 (the engine's %s)" % UiFormat.money(Upgrades.price("racer", "engine", 4)))
	# everything at level 10: MAX, off; the card's bars and top speed with the upgrades
	UiData.store.career.upgrades = {"racer": [10, 10, 10, 10]}
	menu.refresh()
	var maxed := true
	for c: Button in chips:
		maxed = maxed and c.disabled and c.call("price_text") == "MAX"
	var r5 := UiData.buy_upgrade("racer", "nitro")
	var card: Control = menu.car_card()
	var b0: Dictionary = UiData.car_info("racer").bars
	var bu: Dictionary = card.get("bars_up")
	var grew := true
	for k: String in ["speed", "acceleration", "grip", "nitro"]:
		grew = grew and float(bu[k]) >= float(b3[k]) and (float(bu[k]) > float(b3[k]) or float(b3[k]) >= 1.0)
	t.check(maxed and r5.error == "max" and float(bu.speed) > float(b0.speed) and float(bu.acceleration) > float(b0.acceleration) and float(bu.grip) > float(b0.grip) and
		float(bu.nitro) > float(b0.nitro) and grew and float(card.get("top_up")) > top3 and top3 > float(UiData.car_info("racer").top) and
		card.tooltip_text.contains("Upgrades: engine 10, tyres 10, nitro 10, loose grip 10"),
		"every level bought (10): the chips read MAX (off); the Racer's card shows the bars with the upgrades (speed %.2f -> %.2f -> %.2f, grip %.2f -> %.2f -> %.2f, stock -> 3 -> 10) and %d -> %d km/h" % [
		float(b0.speed), float(b3.speed), float(bu.speed), float(b0.grip), float(b3.grip), float(bu.grip), roundi(top3), roundi(float(card.get("top_up")))])
	# a locked car: its description in a short window, its chips off
	UiData.set_setting("car", "vortex")
	menu.refresh()
	var off := true
	for c: Button in chips:
		off = off and c.disabled and bool(c.get("locked"))
	t.check(off and desc_row.is_visible_in_tree() and (chips[0] as Control).tooltip_text.contains("Buy the Vortex first") and menu.car_page._pad_parts().is_empty(),
		"the Vortex (not yours): its description shows, its parts are off (buy the car first)")
	# the pad: down from the picked car (bottom row) to its parts, up back to the car
	UiData.set_setting("car", "drifter")
	UiData.store.career.cars = ["racer", "drifter"]
	menu.refresh()
	_settle(hm[0])
	var inp := Fx.FakeInput.new()
	menu.handle_keys(_press(inp, ["NavDown"], true))
	var on_car: bool = menu.car_page.pad_target() == menu.car_card()
	menu.handle_keys(_press(inp, ["NavDown"], true))
	var first_chip: Control = menu.car_page.pad_target()
	menu.handle_keys(_press(inp, ["NavRight"], true))
	var right_chip: bool = chips.has(menu.car_page.pad_target()) and menu.car_page.pad_target() != first_chip
	var asked := []
	menu.upgrade.connect(func(part: String) -> void: asked.append(part))
	menu.handle_keys(_press(inp, ["PadA"], true))
	menu.handle_keys(_press(inp, ["NavUp"], true))
	t.check(on_car and chips.has(first_chip) and right_chip and asked.size() == 1 and asked[0] != "" and menu.car_page.pad_target() == menu.car_card() and UiData.picked_car() == "drifter",
		"the pad: down from the Drifter to its part chips, right along them, A asks to buy one (%s), up back to the car" % [asked])
	menu.handle_keys(_press(inp, ["Digit2"]))
	t.check(asked.size() == 2 and asked[1] == "tyres", "the 2 key asks to buy the second part's next level (tyres)")
	hm[0].free()
	UiData.reset()


## v6.8.0: locked tracks on the menu (the in-memory store: career.tracks_open) and the finish
## panel's unlock line.
func _unlocks(t) -> void:
	t.section("locked tracks (v6.8.0)")
	Fx.save_data_v5()
	var hm := _menu(t)
	var menu: MainMenu = hm[1]
	var tiles: Array = menu.get("_tiles")
	var drive_btn: Button = menu.get("_drive_btn")
	t.check(UiData.store.career.tracks_open == null and UiData.open_track_count() == 15 and tiles.all(func(x: Control) -> bool: return not x.locked),
		"the store's default (tests, previews): every track open")
	UiData.store.career.tracks_open = ["hairpin-valley"]
	UiData.set_setting("car", "racer")
	menu.select(0)
	t.check(UiData.open_track_count() == 2 and not tiles[0].locked and not tiles[1].locked and tiles[2].locked and tiles[14].locked and
		tiles[2].lock_note == "Bronze on 02" and tiles[14].lock_note == "Bronze on 14" and str(tiles[2].tooltip_text).contains("Locked: bronze on Hairpin Valley opens it") and
		UiData.track_lock(2) == {"medal": "bronze", "index": 1, "name": "Hairpin Valley"} and UiData.track_lock(1).is_empty(),
		"Rookie Oval and Hairpin Valley open: tiles 3-15 locked (Ramp Rally: \"%s\", its tooltip says what opens it)" % tiles[2].lock_note)
	var inp := Fx.FakeInput.new()
	var drives := [0]
	menu.drive.connect(func() -> void: drives[0] += 1)
	menu.handle_keys(_press(inp, ["Digit3"]))
	var lock_text: String = (menu.get("_td_lock_text") as RichTextLabel).get_parsed_text()
	t.check(menu.selected_track == 2 and (menu.get("_td_lock") as Control).visible and lock_text.begins_with("Locked: win bronze or better on Hairpin Valley (02, any car)") and
		lock_text.ends_with("Watch AI and Train AI work here anyway; they pay nothing.") and drive_btn.text == "LOCKED" and drive_btn.theme_type_variation == "" and
		drive_btn.tooltip_text.begins_with("Ramp Rally is locked: win bronze or better on Hairpin Valley"),
		"3 picks locked Ramp Rally: its panel says what opens it and that the AI lab works there; Drive reads LOCKED")
	menu.handle_keys(_press(inp, ["Enter"]))
	menu.handle_keys(_press(inp, ["ArrowRight"]))
	t.check(drives[0] == 1 and not menu.car_page.is_open and menu.selected_track == 3 and tiles[3].locked, "Enter still asks to drive, with no car page (the game refuses with a message); the arrows move on over locked tiles")
	var ghost_btn: Button = menu.get("_ghost_btn")
	var watch_btn: Button = menu.get("_watch_btn")
	UiData.set_setting("opponent", "rookie")
	menu.refresh()
	t.check(ghost_btn.tooltip_text.contains("Banked Speedway is locked") and ghost_btn.tooltip_text.contains("Watch AI works here") and
		not watch_btn.tooltip_text.contains("locked"), "Race the AI's tooltip says the track is locked; Watch the AI's doesn't")
	UiData.set_setting("car", "kestrel")
	menu.refresh()
	t.check(drive_btn.text == "LOCKED" and drive_btn.tooltip_text.contains("is locked"), "v6.19: a car for sale changes nothing on the menu (the car page sells it): LOCKED is the track's")
	UiData.set_setting("car", "racer")
	UiData.store.career.money = 0
	menu.select(1)
	t.check(drive_btn.text == "TIME TRIAL" and drive_btn.theme_type_variation == "PrimaryButton" and not (menu.get("_td_lock") as Control).visible, "an open track: TIME TRIAL, no lock note")
	# NEW: a track a finish just opened, until it is picked or the menu is left
	UiData.store.career.tracks_open = ["hairpin-valley", "ramp-rally"]
	UiData.mark_new_track("ramp-rally")
	menu.refresh()
	var was_new: bool = tiles[2].is_new and not tiles[2].locked and not tiles[1].is_new
	menu.select(2)
	var picked_clears: bool = not tiles[2].is_new and not UiData.is_new_track("ramp-rally")
	UiData.mark_new_track("ramp-rally")
	menu.select(0)
	menu.show_menu(false)
	menu.show_menu(true)
	t.check(was_new and picked_clears and not tiles[2].is_new, "the tile of a track a finish opened is NEW until it is picked, or the menu is left")
	# (whether the side column still fits 1280 x 720 with the lock note needs real frames: the e2e
	# unlock scenario measures it)
	hm[0].free()

	# the finish panel: the track the run opened
	var h := _holder(t)
	var f := FinishPanel.new()
	h.add_child(f)
	var sizes_ok := true
	var heights: PackedStringArray = []
	for sz: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1024, 600), Vector2(800, 600), Vector2(480, 800)]:
		h.size = sz
		f.set_window_size(sz)
		f.update(Fx.panel_payout())
		_settle(h)
		var h0 := f.size.y
		f.update(Fx.panel_unlock())
		_settle(h)
		var r := f.get_global_rect()
		sizes_ok = sizes_ok and r.end.y <= sz.y + 0.5 and r.position.y >= -0.5 and r.end.x <= sz.x + 0.5 and r.position.x >= -0.5
		heights.append("%dx%d: %d px high, +%d (at %d, %d)" % [sz.x, sz.y, roundi(r.size.y), roundi(r.size.y - h0), roundi(r.position.x), roundi(r.position.y)])
	var narrow := _texts(f)
	f.set_window_size(Vector2(1280, 720))
	f.update(Fx.panel_unlock())
	var texts := _texts(f)
	t.check(texts.has("Lighthouse Bay unlocked") and texts.has("track 11 is open: pick it on the menu") and narrow.has("Lighthouse Bay unlocked") and
		not narrow.has("track 11 is open: pick it on the menu") and sizes_ok,
		"the finish panel says Lighthouse Bay unlocked, track 11 is open (480 px wide: the first part only); with the payout it fits (%s)" % ", ".join(heights))
	f.update(Fx.panel_payout())
	t.check(not _texts(f).has("Lighthouse Bay unlocked"), "no unlock: no such line")
	h.free()
	UiData.reset()


## v6.13.0: Race the field on the HUD (place, the cars ahead and behind, the standings) and on the
## finish panel (the place line, the field's rows with times and gaps, docked on the right).
func _field_ui(t) -> void:
	t.section("Race the field: the HUD's field block and the finish panel (v6.13.0)")
	var h := _holder(t)
	var hud := RaceHud.new()
	h.add_child(hud)
	hud.show_hud(true)
	var s := Fx.hud_drive()
	hud.update(s, 0.016)
	var plate: Control = hud.get("_field_plate")
	var off := not plate.visible and hud.field_text.is_empty()
	var cols := [Color("#eef0f2"), Color("#2b2e36"), Color("#d7263d"), Color("#d63af9"), Color("#c8a96a"), Color("#6f4cff")]
	var codes := ["BRA", "VAN", "YOU", "PAR", "REY", "OST"]
	var gaps: Array = [-3.41, -0.85, null, 1.24, 12.5, 0.0]
	var rows: Array = []
	for k in 6:
		rows.append({"i": k, "code": codes[k], "name": codes[k], "color": cols[k], "gap": gaps[k], "me": k == 2, "finished": false, "dnf": k == 5})
	s.field = {"pos": 3, "of": 6, "rows": rows, "ahead": {"code": "VAN", "gap": 0.85}, "behind": {"code": "PAR", "gap": 1.24}}
	hud.update(s, 0.016)
	_settle(h)
	var ft := hud.field_text
	t.check(off and plate.visible and ft == PackedStringArray(["P3/6", "ahead VAN 0.85", "behind PAR 1.24", "1 BRA Leader", "2 VAN +2.56", "3 YOU +3.41", "4 PAR +4.65", "5 REY +15.9", "6 OST OUT"]),
		"the HUD: no field block in Drive; in a field race P3/6, the cars ahead and behind with their gaps, the timing tower's rows with the gaps to the leader (+15.9 past 10 s, an out car): %s" % " | ".join(ft))
	# (v6.20) the timing tower: on the left under the lap plate, one row per car, yours marked
	var tower: TimingTower = hud.get("_tower")
	var lap_plate: Control = hud.get("_race_plate")
	var tr := tower.get_global_rect()
	t.check(tower.visible and tower.rows.size() == 6 and bool(tower.rows[2].me) and tower.head.begins_with("Lap ") and tr.position.x < 80.0 and
		tr.position.y >= lap_plate.get_global_rect().end.y - 0.5 and tr.end.y < 720.0 and is_equal_approx(tr.size.x, TimingTower.WIDTH),
		"the timing tower: six rows on the left under the lap plate (\"%s\", %d x %d px at y %d), your row marked" % [tower.head, roundi(tr.size.x), roundi(tr.size.y), roundi(tr.position.y)])
	t.check(TimingTower.gap_text(0.004) == "+0.00" and TimingTower.gap_text(9.994) == "+9.99" and TimingTower.gap_text(12.34) == "+12.3" and
		TimingTower.leader_gaps([{"gap": null}, {"gap": 0.7}, {"gap": 3.0}]) == PackedFloat64Array([0.0, 0.7, 3.0]) and TimingTower.leader_gaps([]).is_empty(),
		"tower gaps: to the leader (+0.00, +9.99, +12.3 from ten seconds); leading yourself they are the gaps to you")
	# you pass VAN: the rows swap places by sliding, a green arrow on yours and a red one on VAN's
	var swapped: Array = [rows[0].duplicate(), rows[2].duplicate(), rows[1].duplicate(), rows[3], rows[4], rows[5]]
	swapped[0].gap = -2.56
	swapped[1].gap = null
	swapped[2].gap = 0.4
	s.field = {"pos": 2, "of": 6, "rows": swapped, "ahead": {"code": "BRA", "gap": 2.56}, "behind": {"code": "VAN", "gap": 0.4}}
	hud.update(s, 0.016)
	var ys: Dictionary = tower.get("_y")
	var arrows: Dictionary = tower.get("_arrow")
	var mid := float(ys[2]) > tower._row_y(1) and float(ys[2]) < tower._row_y(2) and float(ys[1]) > tower._row_y(1) and float(ys[1]) < tower._row_y(2)
	var marked := arrows.size() == 2 and int(arrows[2].dir) == 1 and int(arrows[1].dir) == -1
	for k in 60:
		hud.update(s, 0.016)
	var there := is_equal_approx(float(ys[2]), tower._row_y(1)) and is_equal_approx(float(ys[1]), tower._row_y(2)) and arrows.size() == 2
	for k in 120:
		hud.update(s, 0.016)
	t.check(mid and marked and there and arrows.is_empty() and hud.field_text[4] == "2 YOU +2.56" and hud.field_text[5] == "3 VAN +2.96",
		"a pass: the two rows slide to their new places (not a jump), a green arrow on your row and a red one on VAN's for %.1f s; then \"%s\", \"%s\"" % [TimingTower.ARROW_TIME, hud.field_text[4], hud.field_text[5]])
	s.field = {"pos": 1, "of": 6, "rows": rows.slice(0, 2), "ahead": {}, "behind": {"code": "VAN", "gap": 0.5}}
	hud.update(s, 0.016)
	t.check(hud.field_text[0] == "P1/6" and hud.field_text[1] == "ahead " and not (hud.get("_ahead_l") as Control).visible and tower.rows.size() == 2, "leading: no car ahead shown; the tower follows the field (two rows)")
	t.check(RaceHud.field_gap(0.004) == "+0.00" and RaceHud.field_gap(-10.04) == "-10.0", "gaps: two decimals, one past 10 s")
	hud.show_hud(false)
	hud.show_hud(true)
	hud.update(Fx.hud_drive(), 0.016)
	t.check(not tower.visible and tower.rows.is_empty() and hud.field_text.is_empty(), "the next Drive: no tower")
	h.free()
	h = _holder(t)
	var f := FinishPanel.new()
	h.add_child(f)
	f.set_window_size(Vector2(1280, 720))
	var st := Fx.panel_finish()
	var res: Array = []
	var names := ["Ada Brandt", "You", "Rico Vance", "Juno Park", "Sol Reyes", "Kai Ostrom"]
	var times: Array = [150.2, 151.45, 153.0, INF, INF, INF]
	for k in 6:
		res.append({"place": k + 1, "i": k, "name": names[k], "code": names[k].substr(0, 3).to_upper(), "car": "Racer", "color": cols[k],
			"time": times[k], "gap": float(times[k]) - 150.2, "me": k == 1, "dnf": k == 5})
	st.field = {"place": 2, "of": 6, "level": "Pro", "rows": res}
	st.dock = "right"
	f.update(st)
	_settle(h)
	var texts := _texts(f)
	var frows: Array = f.find_children("*", "ResultRow", true, false)
	t.check(texts.has("2nd") and texts.has("of 6 · Pro field") and texts.has("You") and texts.has("Ada Brandt") and texts.has("2:31.450") and texts.has("Winner") and texts.has("+1.250") and texts.has("racing…") and texts.has("OUT"),
		"the finish panel: 2nd of 6 · Pro field, every driver with the time and the gap to the winner so far (racing… for the cars still on track, OUT for a car out)")
	var lined := frows.size() == 6
	for k in frows.size():
		var rr: ResultRow = frows[k]
		lined = lined and rr.place == k + 1 and rr.me == (k == 1) and is_equal_approx(rr.size.x, (frows[0] as ResultRow).size.x) and rr.get_global_rect().end.x <= f.get_global_rect().end.x
	t.check(lined, "the results as six F1-style rows (the place in a box, the car's colour, driver, car, time, gap), yours marked, all one width inside the panel (%d px)" % roundi((frows[0] as ResultRow).size.x if frows.size() > 0 else 0.0))
	t.check(f.position.x + f.size.x > 1280.0 - 40.0 and f.position.x > 1280.0 * 0.3, "docked on the right (x %.0f, %.0f wide): the podium is on the left" % [f.position.x, f.size.x])
	f.set_window_size(Vector2(800, 600))
	_settle(h)
	t.check(is_equal_approx(f.size.x, 800.0 - 24.0), "a narrow window keeps it full width")
	h.free()


## v6.14.0: the championship screens: the cup picker and the standings at 1280 x 720 (inside the
## window, no scrolling), its keys, the menu's Cups button (the trophy cabinet) and the finish
## panel's final standings (the trophy moment) at 1280 x 720 and 800 x 600.
func _cup_ui(t) -> void:
	t.section("championships: the cup screen, the cabinet and the final standings (v6.14.0)")
	UiData.reset() # (every track open; the cabinet in the store)
	UiData.store.career.cups = {"paid": [], "trophies": {"rookie": {"pro": 1, "elite": 3}, "asphalt": {"rookie": 2}}}
	var h := _holder(t)
	var cs := CupScreen.new()
	h.add_child(cs)
	CupScreen.picked_cup = ""
	CupScreen.picked_level = "pro"
	cs.open()
	_settle(h)
	# (the heights need real frames, the wrapped lines: the e2e cup scenario checks that both faces fit)
	var rows: Array = cs.get("_rows")
	var start: Button = cs.get("_start_btn")
	var pr := cs.panel.get_global_rect()
	t.check(rows.size() == 5 and pr.end.x <= 1280.5 and pr.position.x >= 0.0 and not start.disabled and cs.picked_cup == "rookie" and (cs.get("_level_btns") as Dictionary).size() == 5,
		"the picker at 1280 x 720: five cup rows and five level chips across the window (%d px wide), START CUP on (every track open), the Rookie Cup picked" % roundi(pr.size.x))
	var tracks0 := String(((rows[0] as Dictionary).tracks as Label).text)
	t.check(tracks0.contains("Rookie Oval") and tracks0.contains("Hairpin Valley") and tracks0.contains("Ramp Rally"), "a cup row lists its three tracks: \"%s\"" % tracks0)
	var inp := MenuInput.new()
	cs.handle_keys(_press(inp, ["ArrowDown"]))
	cs.handle_keys(_press(inp, ["ArrowRight"]))
	var moved := cs.picked_cup == "asphalt" and cs.picked_level == "expert"
	cs.handle_keys(_press(inp, ["ArrowUp"]))
	cs.handle_keys(_press(inp, ["ArrowUp"]))
	var wrapped := cs.picked_cup == "finale"
	var got: Array = []
	cs.start_cup.connect(func(c: String, l: String) -> void: got.append([c, l]))
	cs.handle_keys(_press(inp, ["Enter"]))
	t.check(moved and wrapped and got == [["finale", "expert"]], "keys: down / right pick the next cup and level, up wraps to the Grand Finale, Enter starts it (%s)" % str(got))
	cs.handle_keys(_press(inp, ["Escape"]))
	t.check(not cs.visible, "Esc closes it")
	# the standings of a cup in progress
	var run := CupRun.start("rookie", "pro", "racer")
	var res: Array = [{"id": Cups.PLAYER, "place": 2}]
	for k in Field.AI_COUNT:
		res.append({"id": run.drivers[k], "place": 1 if k == 0 else k + 2})
	run.add(res)
	cs.run_view = func() -> Dictionary: return UiData.cup_view(run)
	cs.open()
	_settle(h)
	pr = cs.panel.get_global_rect()
	var tbl: CupTable = cs.get("_table")
	var race_b: Button = cs.get("_race_btn")
	var stexts := _texts(cs)
	var mine: ResultRow = tbl.rows[1] if tbl.rows.size() == 6 else null
	t.check(cs.is_standings and tbl.rows.size() == 6 and tbl.get_child_count() == 7 and mine != null and mine.me and mine.place == 2 and not (tbl.rows[0] as ResultRow).me and
		race_b.text == "RACE 2: HAIRPIN VALLEY" and stexts.has("Driver") and stexts.has("Pts") and stexts.has("Rookie") and stexts.has("You") and stexts.has("P1") and stexts.has("P2") and stexts.has("8") and stexts.has("·"),
		"the standings: the heads (Driver, Rookie / Hairpin / Ramp, Pts) and six F1-style rows (place box, colour, driver, P1 / P2 ... per race run, a dot for the ones to come, points): you 2nd with 8; RACE 2: HAIRPIN VALLEY")
	var nexts: Array = []
	var quits: Array = []
	cs.next_race.connect(func() -> void: nexts.append(1))
	cs.quit_cup.connect(func() -> void: quits.append(1))
	cs.handle_keys(_press(inp, ["Enter"]))
	cs.handle_keys(_press(inp, ["KeyQ"]))
	t.check(nexts.size() == 1 and quits.size() == 1, "standings keys: Enter races the next one, Q asks to quit the cup")
	h.free()
	# the menu's Cups button: the cabinet
	var cab := CupCabinet.new()
	var c0: Dictionary = cab.cells[0]
	var c1: Dictionary = cab.cells[1]
	t.check(cab.cells.size() == 5 and String(c0.trophy) == "bronze" and c0.levels == ["", "", "gold", "", "bronze"] and String(c1.trophy) == "silver" and
		cab.tooltip_text.contains("3 of 25") and cab.tooltip_text.contains("Rookie Cup: Pro gold, Elite bronze") and cab.custom_minimum_size.x < 240.0,
		"the Cups button's cabinet: the Rookie Cup's trophy at its highest level (Elite bronze) with gold and bronze level pips, the Asphalt Cup's silver; tooltip \"3 of 25\" (%d px wide)" % roundi(cab.custom_minimum_size.x))
	cab.free()
	# the trophy moment's panel: the final standings
	h = _holder(t)
	var f := FinishPanel.new()
	h.add_child(f)
	f.set_window_size(Vector2(1280, 720))
	run.add(res)
	run.add(res)
	var view := UiData.cup_view(run)
	var st := Fx.panel_finish()
	st.title = "Rookie Cup"
	st.cup_final = {"place": int(view.place), "of": 6, "level": "Pro", "trophy": Cups.trophy(int(view.place)), "rows": view.rows,
		"races": (view.races as Array).map(func(r: Dictionary) -> String: return String(r.name))}
	st.dock = "right"
	st.keys = [["Enter", "B", "menu"]]
	st.payout = Economy.cup_payout("rookie", "pro", int(view.place), [])
	f.update(st)
	_settle(h)
	var ft := _texts(f)
	var fr := f.get_global_rect()
	t.check(ft.has("2nd") and ft.has("Pts") and ft.has("menu") and fr.end.y <= 720.5 and fr.position.y >= -0.5 and fr.position.x > 1280.0 * 0.3,
		"the trophy moment's panel at 1280 x 720: 2nd, the final standings and the cup's pay, docked right (x %d, %d..%d px)" % [roundi(fr.position.x), roundi(fr.position.y), roundi(fr.end.y)])
	f.set_window_size(Vector2(800, 600))
	_settle(h)
	fr = f.get_global_rect()
	t.check(fr.end.y <= 600.5 and fr.position.y >= -0.5, "800 x 600: it still fits (%d px high)" % roundi(fr.size.y))
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
