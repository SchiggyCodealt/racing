# Handoff notes

Status notes for whoever (person or AI agent) picks this project up next.
Read this first, then [README.md](README.md) for how the game works and how to run everything.
The history of versions 1-5 (the browser game) is in [web/HANDOFF.md](web/HANDOFF.md).

_Last updated: 2026-11-12 (v6.19.0: round 5, item 2 of 8: the car page (`ui/car_screen.gd`): track and race first, the
car last, and before every race of a cup; a tidier Home;
v6.18.0: round 5, item 1 of 8: Settings has a **Reset all progress** button (asks twice, then
`SaveData.reset_everything`), and a terminal command that asks first takes `yes` as the answer;
v6.17.0: round 4, item C, the last: the terminal's `reset everything` puts the game back to
a fresh install (career, records, ghosts, scores, medals, trophies, AI networks), keeps the settings, and writes a
backup of the save next to it first; v6.16.0: round 4, item B: upgrades to level 10: seven more levels per part, each adding
less (level 10 = 6.5 steps) and costing more (levels 8-10 a late-career goal), ten pips on the car picker; v6.15.0: round 4, item A: the trained AI uses nitro (a tank input and a nitro output,
sensor version 3, FleetSim "trackrush-native 5", the tank refilled by clean checkpoints and laps), older networks widened
with zero weights; no nitro for anyone in races against AI cars (Race the AI, Race the field, cups), the HUD and menu say
so; v6.14.0: round 3, item 2: championships: five cups of three tracks raced back to back
against the same five AI drivers at a picked level, 10-8-6-5-4-3 points, standings between the races that set the next
grid, a trophy moment on the podium with gold, silver and bronze trophies, a cup payout by final place, a trophy cabinet
on the menu's Cups button, a cup in progress kept in the save file; v6.13.0: round 3, item 1: Race the field: you against five AI drivers on a two-wide starting
grid with solid cars (deterministic capsule contacts, only in this mode), a light traffic layer and a watchdog for the
AI, the place and standings on the HUD, the finishing order on the finish panel, a podium, pay by place; v6.12.0: round 2, item 3 of 3: sound and music: every car's engine synthesized live from the
sim's rpm, throttle, load, gear and nitro (six characters), tyres, gravel, snow, wind, walls, landings, nitro, the
race's cues, the menus' clicks and the shop's cash, four synthesized music loops, Master / Music / Effects / Engines
volumes and a background mute in Settings; v6.11.0: round 2, item 2 of 3: car upgrades: engine, tyres, nitro and loose grip, three
levels each, bought on the car picker, shown on the stat bars and the model; medal times and AI opponents stay stock;
v6.10.0: round 2, item 1 of 3: dirt and snow polish: mud and snow on the screen instead of
the camera rumble, richer dirt and snow textures, ragged surface changes, dirty and slidier barriers, better brakes on
loose ground; v6.9.0: feature 9 of 9, the last of the first round: a faster bronze medal, 1.3 × the author time instead of
1.5 ×; v6.8.0: feature 8, the tracks open one at a time: a bronze or better on a track opens the next; v6.7.0: feature 7, a terminal in Settings and on the `` ` `` key for money, points, cars
and unlocks; v6.6.0: feature 6, the tightest corners of five old tracks made more forgiving; v6.5.0: feature 5, money and career points from medals and AI opponents, a car shop; v6.4.0: feature 4, three new
tracks on three new themes; v6.3.0: feature 3, road surfaces: dirt and packed snow; v6.2.0: feature 2, AI training
with every car; v6.1.0: feature 1, two more cars and detailed car models with a moving driver; v6.0.0 was the port
from the browser to the Godot 4.7 engine)._

## Status: v6.19.0, round 5 under way (2 of 8 done: the Reset button, the car page and tidier menu); round 4 done (AI nitro, upgrades to 10, reset everything); round 3 items 1-2 done (Race the field, championships); round 2 done (dirt and snow polish, car upgrades, sound and music); before them all nine features of round 1 (two more cars and detailed models; AI training with every car; dirt and snow; three new tracks; money, points and AI opponents; more forgiving corners; a terminal; tracks that open one at a time; a faster bronze)

Round 5 (asked on 2026-11-12, eight items, built one at a time and pushed after each): see
[Round 5](#round-5-eight-items-v6180-on) for the list, the order, the defaults chosen and what is done.
Round 4 (asked on 2026-11-10): A. **the AI uses nitro, none in races against the AI (v6.15.0, done)**, B. **upgrades
to level 10 (v6.16.0, done)**, C. **a `reset everything` command (v6.17.0, done)**. See [Round 4](#round-4-ai-nitro-upgrades-to-level-10-reset-everything-v6150-v6170).
Round 3, item 2: **Championships (v6.14.0, done)**. See [Round 3, item 2](#round-3-item-2-championships-v6140) and
[How v6.14.0 was verified](#how-v6140-championships-was-verified).
Round 3, item 1: **Race the field (v6.13.0, done)**. See [Round 3](#round-3-race-the-field-v6130) and
[How v6.13.0 was verified](#how-v6130-race-the-field-was-verified).
Round 2 (asked on 2026-11-04, built one at a time in this order): 1. **dirt and snow polish (v6.10.0, done)**,
2. **car upgrades (v6.11.0, done)**, 3. **sound and music (v6.12.0, done)**. See [Round 2](#round-2-the-owners-three-new-items).

The owner (on Windows, not a programmer by trade) asked to "port it to an engine", and listed nine new features
for after the port (see [Next](#next-the-owners-nine-features)). v6.0.0 was the port: the Godot game does
everything the browser game v5.0.0 does, plays the same and looks at least as good. v6.1.0 adds feature 1: the
**Dune** (a soft, forgiving buggy) and the **Vortex** (a light, twitchy hypercar), and new models for all six cars
with spinning and steering wheels, suspension, head and brake lights, body detail and a driver who steers, looks
into corners, leans and pumps a fist at the finish. The Racer is unchanged bit for bit, so old records, ghosts and
networks still count. v6.2.0 adds feature 2: the AI trains with any of the six cars (a car choice on the training
screen, FleetSim and the GDScript trainer take the car's spec as data), every car keeps its own AI network in the
save file, and Watch the AI / Race the AI ghost use the picked car's network driving that car. Racer networks
(old saves, old files, the browser's) drive exactly as before. v6.3.0 adds feature 3: road surfaces as data
(`sim/surfaces.gd`: asphalt, dirt, packed snow), with less grip (each car its own share: the Dune keeps 97 % on
dirt, the Vortex 55 %), more rolling resistance and easier slides, mixed per axle and blended over about 10 m;
dirt on Ramp Rally, Canyon Run and Mountain Pass, packed snow on Hairpin Valley and Mountain Pass's summit; dirt and
snow roads, dust, snow spray, coloured tyre marks and a camera rumble; the menu names a track's surfaces. Those four
tracks are new versions: records, scores and ghosts now carry the track's signature, and old ones move to an
archive in the save file. The eight all-asphalt tracks and every car on them run the v6.2 physics bit for bit.
v6.4.0 adds feature 4: tracks 13-15 after Seaside Stunts, harder from one to the next, each on a new data-driven
theme: **Forest Rally** (difficulty 3, a 3-lap circuit, 88 % dirt, autumn woods), **Northern Lights** (4, a 3-lap
circuit, 79 % packed snow in banked bowls, an arctic night with the northern lights) and **Summit Rush** (5, a
4.38 km sprint on asphalt, dirt and snow up to 18 m, highland). Medal times for all six cars; the first 12 tracks,
their signatures and medal times are bit for bit those of v6.3 (tests). The menu lays 15 tiles out as three rows of
five, which fit 1280 x 720 without scrolling. The snow spray is blue-grey now, so it shows on the white road.
v6.5.0 adds feature 5: a career. Medals (bronze to author) and wins against five AI opponents (Rookie, Amateur, Pro,
Expert, Elite) pay money and career points from one data table (`sim/economy.gd` `REWARDS`), once per track, car and
medal or AI level, more on later tracks (× 1 + 0.1 × the track's index). Money buys cars: a new player owns the Racer,
the other five cost $10,000-30,000 on the car picker (locked cards show a padlock and the price; Drive becomes BUY,
which asks first). The AI opponents are 90 shipped networks (`data/opponents/<car>.json`, one per track and car,
trained with FleetSim on that track with that car); a level is that network with a speed cap calibrated so its race
takes 1.6 / 1.4 / 1.25 / 1.13 / 1.0 × the author time, and its race time is stored. The menu's AI block picks the
opponent (or My AI, the player's own network as before); Race the AI is the old Race the AI ghost path; the finish
panel shows the payout. The save file is `VERSION` 4 (a `career` section); older saves are paid once for the medals
they hold, own only the Racer, and get a one-time message.
v6.6.0 adds feature 6: the corners that caught cars out the most on five of the old tracks are more forgiving. Every
hairpin is at least 24 m round (were 13-19 m) on a road 2-3 m wider: Hairpin Valley (switchbacks 16 → 22 m, hairpins
17 → 24 m, 15 m road; the snowy ridge corner keeps 40 m but is 15 m wide and banked 12°), Technical Trial (hairpins
15 → 24 m, 16 m road), Grand Marathon (its hairpin 16 → 24 m and the corners beside it 20 → 24 m, 17 m road),
Mountain Pass (six hairpins 18-19 → 24-25 m, 15 m road) and Canyon Run (the tongue's hairpin 13 → 24 m and its
rights 20 → 26 m on 13 m, the gravel turnaround 22 → 28 m on 12 m). The straights beside each corner are shorter by
as much as it grew, so the tracks keep their shape, start, dirt and snow; the other ten tracks are bit for bit as in
v6.5.0. Measured with the medal autopilot over all 50 sweep settings and six cars (`tools/corners.gd`, new), wall
contact per lap drops 6-41 % on the five tracks and the hairpins are taken 10-17 km/h faster. The five tracks have
new signatures (old records, scores and ghosts move to the archive), new medal times and new AI opponents (30
networks retrained, levels recalibrated); rewards already paid on them stay paid, on purpose (see Known
limitations). The tests and the parity tools compare with the browser game on its own layouts
(`Tracks.build_web`).
v6.7.0 adds feature 7: a terminal. Settings has a Career section with a Terminal row (Open, or A on the pad), and the
`` ` `` key (the key under Esc, by physical position) opens it on the menu and on Settings; in a race `` ` `` does nothing. It
is a console in the dialogs' style (`ui/terminal_screen.gd`): a scrolling log, a one-line input with a blinking
caret, history on Up / Down, Tab completion of command names and their first argument, Esc or `` ` `` to close. The
commands are one table in `game/terminal.gd` (name, usage, help, method, Tab words, `wipes`): `help [command]`,
`money <n>` / `money set <n>`, `points <n>` / `points set <n>`, `car <name> | all`, `buy <car>`, `unlock all | cars |
tracks`, `status`, `reset career` (asks: `reset career confirm`), `clear`, `exit`. Each prints what it did and the new
value and goes through the save file's own functions (`SaveData.add_money`, `add_points`, `give_car`, the new
`unlock_tracks` and `reset_career`, `Economy.buy`); the menu redraws at once. `unlock all` also sets a new
`career.tracks_unlocked` flag in the save file (version 4 kept: absent = off) for item 8 to read.
v6.8.0 adds feature 8: the tracks open one at a time, in menu order (`sim/unlocks.gd`). A new career has Rookie Oval;
a bronze or better (`Unlocks.MEDAL`) on a track, with any car, opens the next one for good: the finish claims it
(`Unlocks.claim`, from the medal the payout used) and the save file keeps the opened tracks in `career.tracks_open`
(version 4 kept), so a later version that makes bronze faster (item 9) or changes a track never locks one again.
A save from v6.7.0 or older (every track was open) gets the list once from its best times: every track it has a best
time on (current or archived, any car) and the track after every bronze or better (archived times against today's
bronze). The terminal's `unlock tracks` flag opens everything; `reset career` turns it off but keeps the tracks medals
opened. Locked tiles are darker with a padlock and "Bronze on 02"; a locked track can still be picked (keys, pad,
mouse), its panel says what opens it, and Drive reads LOCKED; Drive and Race the AI there are refused with a message
(`GameApp.play`), as is Race best on the training screen; Watch the AI and Train the AI work on every track. The
finish panel says "Ramp Rally unlocked" and the new tile is NEW until it is picked or the menu is left. The terminal's
`status` counts the open tracks and names what opens the next one.
v6.9.0 adds feature 9, the last of the nine: a faster bronze medal. Bronze is 1.3 × the author time, rounded up to a
whole second (it was 1.5 ×, as in the browser version): `Medals.FACTORS.bronze`, and `data/medals.json`'s 90 bronze
times worked out again from the stored author times with the new `tools/medals.gd --factors` (no sweep; gold, silver,
author times and runs untouched), 13-54 s faster (Rookie Oval with the Racer: 2:39 instead of 3:03). Medals are
worked out from best times when shown, so saved records re-rate themselves: a best time that was a bronze at 1.5 × but
is slower than the new bronze holds no medal now, but the tracks it opened stay open (v6.8.0's `career.tracks_open`)
and what it paid stays paid (a new bronze there pays nothing again). The AI levels were not recalibrated: their
measured times sit where they did, so the Amateur (1.39-1.41 × the author time) is now a little slower than bronze
and the Pro (1.24-1.27 ×) between silver and bronze; the menu's level texts say so (tests check them against every
track and car). The browser comparison (`tools/medals.gd --js`) checks author, gold and silver only
(`Medals.WEB_FACTORS` keeps the browser's 1.5 ×). With this, the nine features the owner asked for after the port
are all done: see [Next](#next-the-owners-nine-features) for what is left open across them.
v6.10.0 is round 2's item 1, dirt and snow polish. The owner: "instead of shaking the camera on bad terrain add a
particle or mud\snow overlay to the screen also make the textures for mud and snow more complex / more random. Make
the change from normal terrain a little prettier than just a straight line. The walls should also be slidier on mud
and snow make the dirty as well. Improve the brake handling a little as well on bad roads". What it does:
- **Mud and snow on the screen** (`world/screen_grime.gd`, a CanvasLayer at layer 4 under the interface, made by
  `modes/play_mode.gd` only on a track with surfaces; shaders `world/shaders/screen_splat.gdshader`, one
  MultiMeshInstance2D quad per splat, and `screen_film.gdshader`, a full-screen ColorRect): mud splats (metaball
  lumps with droplets, some with a drip that runs down) and a film of dried mud and specks from the corners and the
  bottom on dirt; flecks of snow that melt into clear drops and frost from the corners on snow; a few clods or flakes
  flying past. It builds with speed and sliding (from the surfaces' new look column `grime`, which replaces v6.3's
  `rumble`: dirt 1, snow 0.85) and with the AI opponent close ahead (`ScreenGrime.ahead_of`: within 28 m, in your lane,
  at speed on loose ground; the opponent's ghost now throws up dust and snow too, `CarModel` opts `dust`, the best-run
  ghost stays clean); on asphalt the splats age 3 × faster and slide outward and the film and frost fade (all gone
  within about 2.5 s). Nothing is ever drawn inside a keep-out ellipse around the middle of the screen (`KEEP_C`,
  `KEEP_R`: 34 % × 31 % of the screen's width and height as radii): splats are placed and kept outside it, flyers
  start on its edge and leave, the film and frost stop at it. At most 40 splats and 12 flyers at High, scaled by
  `CarEffects.spark_share` (12 and 4 at Low). Settings has a new row **Screen dirt and snow** (setting `grime`, on by
  default, `SaveData.SETTINGS` and `UiData.SETTING_DEFAULTS`; `GameApp` sets `ScreenGrime.enabled`). The camera's
  ground rumble is gone (`ChaseCamera.ground_rumble` removed); wall hits and scrapes still shake it.
- **Richer textures**: `Tex.loose()` is now 512 px (R: dirt detail with cracks and clustered rounded pebbles; G: big
  patches; B: snow detail with glints; A: medium noise) with a normal map from its height; the road shader
  (`world/shaders/road_surface.gdshader`, rewritten) mixes two samples at different scales and angles by a large
  noise (no visible tile), drifts the dirt's colour over 50-200 m, and draws procedural wheel ruts (two lanes of two
  tracks, wandering, stronger in some places than others), damp patches, small dark puddles in the ruts; on snow
  packed tracks, loose powder at the sides, glints that twinkle with the view (a little emission), glossy ice and
  bluish hollows; the normals follow (rut walls, flat puddles and ice).
- **Prettier surface changes**: the road's vertices carry `CUSTOM0` = (lateral fraction, half width, the *wide*
  weights of surfaces 1 and 2), the wide weights being the surface shares smoothed with a triangle filter over ±10
  samples (about ±20 m, `TrackMesh.wide_weights()`). The shader's `cover()` puts the 50 % line where mix(wide,
  physics, 0.35) crosses 0.5, made ragged by big patches, tongues stretched along the road (dirt carried along the wheel
  tracks, snow drifting in from the edges) and scattered clumps, with a dusty or frosted film on the tarmac round it.
  The physics blend is unchanged (±2 samples, about 10 m), and the look's middle follows it, so look and feel agree.
  On asphalt away from any surface (both wide weights 0) the road is exactly the old asphalt.
- **Dirty barriers**: on a track with surfaces the barriers use `world/shaders/barrier_grime.gdshader`: the plain
  colours times the detail texture as before, and the vertex alpha says what the road beside them throws at them (0.5
  nothing, 1 dirt, 0 snow, from the wide weights, so it fades in and out): along dirt dust darkening the lower half,
  smears and procedural drops of mud, wet mud at the foot, grime streaks from the top; along snow a crust on the top
  faces, snow piled at the foot, rime and flecks low down, a glossy glaze of ice. All-asphalt tracks keep the plain
  StandardMaterial3D.
- **Slidier walls** (physics column `wall`: dirt 0.55, snow 0.45; `sim/car.gd` `_impulse` and `_rub` on loose ground):
  the linear wall friction of a hit and the rub are scaled, the crush term (the speed going into the wall) is not, so
  a wall still costs time (`tests/test_sim.gd`: the medal autopilot beats never braking with the Racer on all seven
  surface tracks).
- **Better brakes on loose ground** (physics columns `brake`: dirt 1.24, snow 1.28; `abs`: asphalt 0.97, loose 0.9):
  on loose ground the brake force × `brake`, the rear's longitudinal limit and the front's braking limit are `abs` ×
  `brake` × the tyre's grip, and a braked front tyre keeps its cornering grip on a friction ellipse (semi-axis `brake`
  × grip) instead of the circle. The autopilot plans its braking with grip × `brake` × `abs` / 0.97. Every car stops
  12-14 % shorter from 100 km/h on dirt and 15 % on snow; braking flat out in a 120 m curve from 0.45 g no car spins
  any more (v6.9.0: five of six on snow, two on dirt). Asphalt is untouched (the `_env_loose` branch), so the eight
  all-asphalt tracks run bit for bit as before.
- **FleetSim** mirrors it (`native/src/`: `surf_brake`, `surf_abs`, `surf_wall`, `version()` "trackrush-native 4");
  all four libraries rebuilt. `Car.PHYSICS_VERSION` stays 3 on purpose: asphalt is unchanged, and on the surface tracks
  old records and ghosts (which store positions) keep counting against the new medal times.
- **Knock-on**: medal times of the seven surface tracks worked out again (`tools/medals.gd --update`; the eight
  asphalt tracks unchanged to the byte), their 42 AI opponents recalibrated (`tools/opponents.gd --tracks=...`) and
  the Drifter's Forest Rally network retrained (its Elite had fallen to 1.066 × the author time, slower than gold);
  `--check` reproduces every stored race.

v6.11.0 is round 2's item 2, car upgrades. The owner: "Car upgrades: engine, tyres, nitro tank and dirt/snow grip,
three levels each, so money is still useful once all six cars are bought." What it does:
- **The parts are data** (`sim/upgrades.gd`, `class_name Upgrades`): `PARTS` (id, name, short letter, `step` per level,
  `cost` weight, aliases for the terminal, the texts), `MAX_LEVEL` 3, `LEVEL_SHARE` [0.1, 0.2, 0.35] (a level's price
  as a share of the car's price), `FREE_CAR_BASE` 12000 (what the free Racer counts as). A car's levels are 4 ints
  [engine, tyres, nitro, loose]. `Upgrades.spec(car, levels)` is `CarSpec.make(changes, Cars.spec(car))`, built once
  per car and levels (cached under a mutex, so training threads can share it); level 0 everywhere returns the stock
  spec object itself, so stock runs are bit for bit as before.
  - **Engine**: the torque curve × (1 + 0.05 × level). **Tyres**: `mu` × (1 + 0.04 × level), with the dirt and snow
    shares divided by the same factor, so the grip on loose ground is the loose grip part's alone. **Nitro**:
    `nitro_time` and the new `CarSpec.nitro_refill` (1.0 stock; `sim/score.gd` multiplies the tanks a banked point
    buys by it) × (1 + 0.1 × level). **Loose grip**: `dirt_grip` and `snow_grip` × (1 + 0.05 × level), never above 1 (the
    asphalt grip). `max_speed` (the AI's speed input scale), the mass, brakes and steering never change.
  - Measured (`tools/upgrades.gd`, new: `tools/car_stats.gd`'s measurements of the upgraded specs; the engine and
    tyre levels are stored in `Upgrades.MEASURED` for the picker's bars and checked by a test): each engine level is
    4-8 % quicker to 200 km/h and 1-2 % faster at the top, each tyre level about 3-5 % more grip on the skidpads, loose
    grip about +15 % at level 3 on dirt and snow (the Dune +2 % on dirt, capped by its asphalt grip), nitro level 3 a
    30 % longer tank. The nitro steps are 10 %, not 3-5 %: at 5 % a level the part did next to nothing on a lap (see
    the verification).
- **Prices** scale with the car's price and rise per level: base × `LEVEL_SHARE`[level-1] × the part's `cost`
  (engine 1.25, tyres 1.0, nitro 0.6, loose 0.75), rounded to $50. Racer $1,500 / $3,000 / $5,250 for the engine;
  every part of a car $23,450 (Kestrel) to $70,250 (Vortex), all six $248,200 against $94,000 for the cars (3.4 gold +
  Expert careers' money with one car, 2.0 author + Elite ones, cars included).
- **The save file is `VERSION` 5**: `career.upgrades {car: [e, t, n, l]}`, only owned cars, stock entries dropped,
  cleaned on load (`_repair_career`); older files start with `upgrades = {}` (every car stock). `SaveData.get_upgrades`,
  `purchase_upgrade(car, part, level, price)` ("" or unknown / locked / max / order / money, one write) and
  `set_upgrades` (the terminal). `reset_career` makes every car stock. Records and ghosts carry `up` (the run's levels,
  only when not stock) for information: ghosts store poses, so they replay exactly whatever the car has now.
  `Economy.upgrade_price` / `buy_upgrade`; `UiData` has the same for the menu (and an in-memory version for the tests).
- **Where they apply**: `modes/play_mode.gd` builds the player's car with its upgrades (`levels`, `car_spec`), and the
  player's own network's car too (My AI: Watch the AI, Race my AI, the training screen's Watch / Race best); an AI
  opponent (`level` set) always drives the stock car, so its stored race is the one `tools/opponents.gd` measured.
  `modes/train_mode.gd` gives the trainer `opts.spec` (the upgraded car; `Trainer` takes it only for its own car id), so
  FleetSim gets the upgraded spec as data (v6.15.0: `nitroRefill` included, the AI's tank refills with it). No
  native change. Medal times (`tools/medals.gd`) and opponents (`ai/opponent_race.gd`) use `Cars.spec`: stock.
- **The car picker** (`ui/main_menu.gd`, `ui/part_chip.gd`, `ui/car_card.gd`): a row under the cards with an
  "Upgrades" caption and four chips (name, three level pips, the next price in the accent / grey, MAX), which emit
  `upgrade(part)`; `GameApp.offer_upgrade` asks first (or says the car is locked, at the top, or how much is missing)
  and `buy_upgrade` buys. A locked car's chips are off. Under 760 px of window height (1280 x 720) the row replaces the
  description line for an owned car (a locked car shows its description); from 760 px both show. The pad goes down
  from the picked car to the chips and up again; A buys. The card's bars draw the stock value and, in `UiStyle.GOOD`
  green, what the upgrades add (`Upgrades.bars`: `Cars.stat_bars` of the measured stats with the levels); the top
  speed is the upgraded one, green when higher; the tooltip lists the levels.
- **On the model** (`CarBuild.upgrades(id, levels, detail)`, `CarModel` opts `levels`, one more skinned mesh "Upgrades"
  with the car's material; not on ghosts): bigger polished exhaust tips per engine level, a yellow sidewall ring on
  every tyre (wider per tyre level, on the spinning bones), a blue band round each tail pipe per nitro level, mud
  flaps with an accent strip behind the rear wheels for loose grip on cars with arches and no flaps of their own
  (shape key `mudflaps`: the Drifter has them; the open-wheeled Dune gets none). 840-2,736 triangles more with everything
  at level 3 (the Thunder has four tail pipes).
- **The terminal**: `upgrade` (every car's levels), `upgrade <car>` (its levels and next prices), `upgrade <car>
  <part> <0-3>`, `upgrade <car> max | stock`, `upgrade all max | stock` (owned cars, free), `buy <car> <part>` (with
  money), and an Upgrades row in `status` (each upgraded car's code, "Racer E3 T3 N3 L3", and what its parts cost).
- **A v6.10.0 layout slip fixed on the way** (`ui/settings_screen.gd`): since v6.10.0's Screen dirt and snow row the
  Settings screen was 20 px too tall for 1280 x 720 (740 px of content, the e2e `terminal` scenario's fit check, which
  v6.10.0 did not run); short windows (760 px and less) now pad a row 4 px above and below (was 6; 1024 x 600 already
  had 4), so every setting fits again.

v6.12.0 is round 2's item 3, sound and music (the game had none before). The owner: "Sound and music: engine sound
that follows the revs, tyre squeal, gravel and snow crunch, wall hits, nitro, music and volume sliders." What it does:
- **Buses** (`audio/game_audio.gd`, `class_name GameAudio`, one per game: `GameApp.audio`): Music, SFX and Engine send
  to Master, which has an `AudioEffectHardLimiter` (ceiling -0.5 dB, release 80 ms; `setup_buses()` is idempotent and
  works without a game, for tests). Volumes are settings 0..1 in tenths (`vol_master` 1.0, `vol_music` 0.7, `vol_sfx`
  0.8, `vol_engine` 0.8 by default) applied as `volume_db = linear_to_db(v²)` (half way is -12 dB; 0 mutes the bus);
  `mute_unfocused` (on) mutes Master on `NOTIFICATION_APPLICATION_FOCUS_OUT` until focus comes back. Effects play from
  pools made once (14 plain players, 8 positional), each sound with a level, a random pitch spread, a shortest gap
  and a voice limit (the oldest stops) from `audio/sound_bank.gd` (data); `play_after()` queues the finish's stingers;
  `history` / `total` / `sounds_since()` let tests see what played. Music: two players cross-fading (1.2 s), a level
  per context (`music_level`: races -3 dB) and `duck()` (the finish panel -8 dB). `shutdown()` stops everything, every car's sound too
  (the `CarAudio.GROUP` nodes; on `NOTIFICATION_WM_CLOSE_REQUEST`; the e2e harness calls it before quitting, see
  Known limitations). The settings are applied when the save file has been read (`GameApp._ready`).
- **Engines** (`audio/engine_voice.gd`, `class_name EngineVoice`, plain RefCounted maths, no nodes): synthesized live
  into an `AudioStreamGenerator` (24 kHz for the player's car, 16 kHz for the AI car) by a source-filter model: one
  pressure pulse per cylinder firing (`firing_hz = rpm / 120 × cylinders`, the per-car firing intervals and pulse
  sizes give the V8's burble and the buggy's lope), low-passed brighter with load, revs and nitro, plus combustion
  noise, through an exhaust-pipe feedback comb and three fixed body resonances (so the timbre stays put while the
  pitch follows the revs), plus intake roar, a whine locked to the revs (the nitro adds one an octave up), a turbo
  whistle with spool, a rattle, crackle pops after a lift from high revs, the rev limiter's ignition cut, a DC blocker
  and a soft clip. Each car is one `ENGINES` entry (data: cylinders, intervals, amps, jitter, pulse, pipe, body,
  intake, whine, turbo, rattle, crackle, limiter, gain): Racer race V6, Kestrel high-revving four (loud intake),
  Thunder cross-plane V8 (uneven firing, the lowest pipe, most crackle), Drifter turbo four (spool whistle, blow-off),
  Dune air-cooled buggy four (jitter, rattle), Vortex V12 (bright, whine). `follow(car)` reads `car.rpm`, `throttle`,
  `gear`, `_shift` (the load is 0 while a gear change runs, so the drop and pick-up come from the sim itself) and
  `boost`. Every car is calibrated to about -17 dBFS RMS on load at two thirds of its redline (`gain`).
- **A car's sounds** (`audio/car_audio.gd`, `class_name CarAudio`, a child of the car model, fed once a frame from
  `PlayMode.render`): the engine (rendered 2.5 frames, 50-120 ms, ahead of what has played; `queued()` and `skips()`
  say how far ahead and how often it ran dry), loops on SFX with level
  and pitch from the sim (tyre squeal from `car.slip` on the asphalt share, gravel and snow from the surface weights
  under the car × speed × slip, road roar, wind from speed, scrape from `car.wall_scrape`, nitro rush from
  `car.boost`), one-shots (wall hits light / medium / heavy by the speed into the wall from `car.wall_impact` and the
  wall normal, landings by the speed down, the nitro lighting, the turbo's blow-off on a lift at spool > 0.45). A
  respawn or restart (a jump of more than 20 m) starts it over without a hit. The AI car you race gets a positional
  one (`AudioStreamPlayer3D`, 0.6 level; the chase camera is the listener); the best-run ghost has none (silent: it
  would double your own engine). In the countdown the throttle revs the engine freely (72 % of the rev range).
- **The race's cues** (`modes/play_mode.gd`): "count" at 3, 2, 1 and "go", "checkpoint" / "lap" in the step a gate is
  taken, "finish", then 0.9 s later "medal" (a new medal) or "best" (a new best time without one) and "unlock" (a
  track opened) after it; the music ducks under the finish panel; R drops the queued stingers; Esc stops the car.
  The menu plays `SoundBank.MENU_MUSIC`, a race its theme's (`SoundBank.RACE_MUSIC`: meadow, seaside, highland →
  Overdrive; night, dusk, arctic → Neon Rush; desert, canyon, alpine, autumn → Dust Devil).
- **The interface** (`ui/ui_sound.gd`, `class_name UiSound`: a static `player` Callable the app points at
  `GameAudio.play_ui`, so `ui/` doesn't depend on `audio/`; `played` keeps the last names for tests): "ui_move" when a
  selection or value moves, "ui_confirm" when a button or screen opens, "ui_back" on close, "ui_error" with
  every refusal message (`GameApp.refuse()`), "cash" when a car or upgrade is bought, "key" / "key_enter" in the
  terminal.
- **Settings** (`ui/settings_screen.gd`): a `slider` row type (`ui/volume_bar.gd`: ten slanted blocks and the per cent;
  keys and pad step 10 %, a click or drag sets it), the Audio section (Master, Music, Effects, Engines, Mute in the
  background) and two columns from 1100 px of width (`TWO_COLUMNS`; Audio and Career in the right one, set by the
  section's `"column": 1`; the keys still go through `ROWS` in order). Narrower windows keep one column, which now
  scrolls at 1024 x 600; the picked row is kept in view.
- **Files** (`tools/gen_sounds.py`, Python + numpy, ffmpeg for Ogg; deterministic, about a minute): 32 effects
  (`assets/audio/sfx/*.wav`, 16-bit mono 44.1 kHz, 3.0 MB; imported as QOA, the 7 loops with `edit/loop_mode=2`) and 4
  music loops (`assets/audio/music/*.ogg`, Vorbis q5 stereo, 3.4 MB, `loop=true`): "Pit Lane" (menus, 108 BPM house,
  16 bars, 35.6 s), "Overdrive" (128 BPM electro house), "Neon Rush" (138 BPM trance), "Dust Devil" (164 BPM
  breakbeat), each 32 bars with reverb and delay tails wrapped round so they loop without a seam. All synthesized;
  nothing downloaded (`assets/audio/CREDITS.md`). `tools/engine_preview.gd` renders the engines to WAV and measures them.

| Area | State | Where |
| --- | --- | --- |
| Game logic without graphics: tracks (builder, collision), car physics and nitro, the six cars, race timing, points, ghosts, medals, save file, autopilot | done; the four browser cars checked number for number against the browser version, the Dune and Vortex (v6.1.0) by tests and the medal sweep | `sim/`, `data/tracks.json`, `data/medals.json` |
| 3D world: track mesh, terrain and scenery for 10 themes (3 new in v6.4.0), sky (v6.4.0: northern lights), lighting, glow, car models, smoke, skid marks, sparks, nitro flames, chase camera, AI fleet, sensor rays, quality levels (high / medium / low) | done, compared with v5 screenshots at 14 moments | `world/` |
| Car models (v6.1.0): one skinned mesh per car (17 bones) with spinning / steering wheels, suspension, head and brake lights, panel lines, a driver who moves; headlights at night and dusk; a cheaper level of detail on low and for the AI fleet | done, checked by tests and screenshots (software rendering only) | `world/car_shapes.gd`, `world/car_build.gd`, `world/car_kit.gd`, `world/car_model.gd`, `world/shaders/car*.gdshader` |
| Interface: menu (1 Track / 2 Car / 3 Drive; track tiles in full rows of up to six, 15 tracks as three rows of five; six car cards, three a row from a 780 px wide picker), Controls and Settings screens, HUD, finish panel, pad navigation, Barlow fonts | done, layout checked at 6 window sizes | `ui/`, `assets/fonts/` |
| AI: network, evolution, sensors and driver, trainer (walls ride / crash, multi-track), training screen with 1× / Fast ×6 / Max on a background thread | done, lockstep-identical to the browser version (the Racer) | `ai/`, `modes/train_mode.gd`, `ui/train_*.gd` |
| Road surfaces (v6.3.0): the surface table, per-sample surfaces and blend weights on `BuiltTrack`, per-axle physics (GDScript and FleetSim), track signatures on records / scores / ghosts with an archive, dirt and snow road shader, dust and snow spray, tinted tyre marks, camera rumble, the menu's surface line | done, FleetSim bit-identical on the surface tracks for all six cars, asphalt tracks bit-identical to v6.2; new medal times for the four changed tracks | `sim/surfaces.gd`, `sim/car.gd`, `sim/track_builder.gd`, `sim/save.gd`, `sim/tracks.gd`, `native/src/`, `world/track_mesh.gd`, `world/shaders/road_surface.gdshader`, `world/car_effects.gd` |
| Tracks 13-15 (v6.4.0): Forest Rally, Northern Lights, Summit Rush in `tools/gen_tracks.gd`; themes autumn, arctic, highland (`woods`, `sky.aurora`, `ground.roadSnow`, scenery species `build` / `leaf` / `onSnow`); medal times; the menu's grid as full rows | done; design rules, signatures, medal entries, menu fit and the AI's first finish are tests; the 12 old tracks bit-identical | `tools/gen_tracks.gd`, `data/tracks.json`, `data/medals.json`, `world/themes.gd`, `world/track_scenery.gd`, `world/track_terrain.gd`, `world/shaders/sky.gdshader`, `ui/main_menu.gd` |
| AI with every car (v6.2.0): the training screen's car tiles, a session per car, one network per car in the save file, network files that name their car, Watch / Race the AI with the picked car's network | done, every car checked in lockstep (FleetSim against GDScript) and by a short training run | `ui/car_chip.gd`, `modes/train_mode.gd`, `sim/save.gd`, `game/app.gd` |
| FleetSim: the C++ GDExtension that steps the whole population (sensors, network, physics, rules) on several threads | done, bit-identical to the GDScript simulation for all six cars; Linux and Windows libraries built | `native/`, `bin/`, `trackrush.gdextension` |
| Game shell: modes (menu, Drive, Race the AI ghost, Watch the AI, training), keyboard and gamepad, threaded track loading, quality governor, fullscreen / vsync, network files, messages | done | `main.tscn`, `game/`, `modes/` |
| New in the Godot version: Settings screen (quality, fullscreen, vsync, interface size, ghost), native file dialogs for networks, the save file instead of browser storage | done | `ui/settings_screen.gd`, `game/app.gd`, `sim/save.gd` |
| Career (v6.5.0): money and points (the reward table, paid once), the car shop, the save file's `career` (VERSION 4, migration pays held medals once), the menu's wallet and locked cards, the finish panel's payout | done; reward table, paid-once rule, shop, migrations (v1-v3) and junk are tests; prices checked against a simulated career | `sim/economy.gd`, `sim/save.gd`, `sim/cars.gd` (`price`), `ui/main_menu.gd`, `ui/car_card.gd`, `ui/finish_panel.gd`, `game/app.gd`, `game/message_screen.gd` |
| AI opponents (v6.5.0): 90 shipped networks with five levels each (a speed cap and the race's time), the menu's opponent chips, Race / Watch the AI against a level | done; every level of every track and car finishes and is slower than the one above (tests); stored races re-run to the millisecond | `data/opponents/`, `sim/opponents.gd`, `ai/opponent_race.gd`, `ai/sensors.gd` (`AIDriver.speed_cap`), `tools/opponents.gd`, `modes/play_mode.gd`, `game/ai_link.gd` |
| Reworked corners (v6.6.0): five old tracks with rounder, wider hairpins in `tools/gen_tracks.gd`; their medal times and AI opponents; `tools/corners.gd` (each corner's radius, width and how the medal autopilot takes it); `Tracks.build_web` (the browser's layouts for the parity checks) | done; the new minimum radius and width, the unchanged hairpin count and surfaces, the ten untouched tracks and their medal entries, and a v6.5 save's archive and paid rewards are tests | `tools/gen_tracks.gd`, `data/tracks.json`, `data/medals.json`, `data/opponents/`, `tools/corners.gd`, `sim/tracks.gd` |
| Faster bronze (v6.9.0): `Medals.FACTORS.bronze` 1.3, `Medals.WEB_FACTORS` (the browser's), `tools/medals.gd --factors` (gold / silver / bronze from the stored author times, no sweep) and `--js` comparing only the medals whose factor is the browser's; `data/medals.json`'s bronze times; the AI levels' menu texts | done; the factors, the file, every bronze, a v6.8.0 player whose bronze no longer counts (open tracks and paid rewards kept), the level texts against every track and car are tests; e2e `unlock` takes the new bronze | `sim/medals.gd`, `tools/medals.gd`, `data/medals.json`, `sim/opponents.gd` |
| Unlocking tracks (v6.8.0): the rule and the claim at the finish, the save file's `career.tracks_open` (with the one-time upgrade from best times), the menu's locked and NEW tiles and lock note, the refusals in the app and on the training screen, the finish panel's line, the terminal's `status` row | done; the rule, stickiness across a medal-time change and a changed track, the upgrade (current and archived times, unknown cars, junk), the flag and the reset, the refusals, Watch / Train on a locked track, the menu and the finish panel are tests; e2e `unlock` | `sim/unlocks.gd`, `sim/save.gd`, `ui/ui_data.gd`, `ui/track_tile.gd`, `ui/main_menu.gd`, `ui/finish_panel.gd`, `ui/widgets.gd`, `modes/play_mode.gd`, `modes/train_mode.gd`, `game/app.gd`, `game/terminal.gd` |
| Terminal (v6.7.0): the console screen (log, input, history, Tab), the commands table, the Settings row, the `` ` `` key on the menu and Settings, the save file's tracks flag and career reset | done; every command with good and bad input, Tab, the save effects, the keys that open and close it, `` ` `` in a race are tests; e2e `terminal` | `game/terminal.gd`, `ui/terminal_screen.gd`, `ui/settings_screen.gd`, `ui/main_menu.gd`, `ui/menu_input.gd`, `sim/save.gd` |
| Dirt and snow polish (v6.10.0): the screen overlay and its setting, the loose texture and road shader, the ragged surface changes (`CUSTOM0`, wide weights), the barrier grime shader, wall friction, brake and ABS columns (GDScript, autopilot and FleetSim), the AI opponent's dust; new medal times and AI levels for the seven surface tracks | done; overlay (builds, fades, quality, setting, the middle kept clear, the car ahead), barriers, no ground rumble, brakes against v6.9.0, curve braking, wall scrape, walls cost time, FleetSim parity are tests; e2e `surfaces`, `settings1/2` | `world/screen_grime.gd`, `world/shaders/screen_*.gdshader`, `world/shaders/road_surface.gdshader`, `world/shaders/barrier_grime.gdshader`, `world/textures.gd`, `world/track_mesh.gd`, `sim/surfaces.gd`, `sim/car.gd`, `sim/autopilot.gd`, `native/src/`, `modes/play_mode.gd`, `ui/settings_screen.gd` |
| Car upgrades (v6.11.0): the parts table, upgraded specs, prices, the save file's `career.upgrades` (VERSION 5), the picker's part chips and green bars, the app's ask-first purchase, play and train modes driving the upgraded car (opponents stock), records and ghosts tagged with the levels, the parts on the model, the terminal's `upgrade` / `buy <car> <part>` / `status` row, `tools/upgrades.gd` | done; specs per part / level / car, measured effects, laps, stability (jumps, lane keeping, curve braking on three surfaces), prices and buying, migration and junk, an upgraded ghost replaying exactly, FleetSim parity with upgraded specs, the app, the terminal, the picker and the model are tests; e2e `upgrades` | `sim/upgrades.gd`, `sim/car_spec.gd`, `sim/score.gd`, `sim/save.gd`, `sim/economy.gd`, `sim/replay.gd`, `sim/autopilot.gd`, `ai/trainer.gd`, `modes/play_mode.gd`, `modes/train_mode.gd`, `ui/part_chip.gd`, `ui/main_menu.gd`, `ui/car_card.gd`, `ui/ui_data.gd`, `game/app.gd`, `game/terminal.gd`, `world/car_build.gd`, `world/car_model.gd`, `world/car_shapes.gd`, `tools/upgrades.gd` |
| Sound and music (v6.12.0): buses with a limiter, volumes and the background mute (settings), pooled effects, music with cross-fade and ducking, the live engine synthesizer (six characters), a car's loops and one-shots from the sim, the race's cues, the interface's clicks, the shop's cash, the Settings sliders in two columns, the generated effects and music | done; buses, volumes, saving, the mute, every file, pools, the queue, music, the engines (pitch against rpm, levels, gear change, limiter, crackle, turbo, nitro), a car's events and loops, the app's sounds of a race and the shop, the sliders are tests; e2e `audio` under Movie Maker (levels, clipping, pitch against the sim's rpm, cues on time, the mute) | `audio/`, `assets/audio/`, `tools/gen_sounds.py`, `tools/engine_preview.gd`, `ui/volume_bar.gd`, `ui/ui_sound.gd`, `ui/settings_screen.gd`, `ui/main_menu.gd`, `ui/terminal_screen.gd`, `game/app.gd`, `game/message_screen.gd`, `modes/play_mode.gd`, `sim/save.gd`, `ui/ui_data.gd` |
| Tests: headless suite (929 checks), end-to-end tests of the real game, CI | done | `tests/`, `.github/workflows/test.yml` |
| Exports: Windows (`TrackRush.exe` + DLL, zip with a README.txt) and Linux | done (built on Linux; the Windows build was never run on Windows) | `export_presets.cfg`, `build/` (not in git) |
| README, this file, screenshots | done | `README.md`, `HANDOFF.md`, `docs/screenshots/` |
| Project licence | open: waiting for the owner to choose one, or none | add `LICENSE` + a README section |

The browser game is kept unchanged in `web/` (Godot ignores it through `web/.gdignore`); its CI job still runs.

## How the port was verified

Each part was ported line by line from `web/src` and compared with the browser version by running both on the
same inputs (the scripts are in `tools/parity/`: `.mjs` files run the browser code in Node.js, `.gd` files the
Godot code; numbers travel as hex bits because Godot's JSON reader is not exact for 17-digit numbers).

| What | Compared | Result |
| --- | --- | --- |
| Track data | `tools/gen_tracks.gd` output against the JS `TRACKS` | identical: 12 tracks, 4,275 points, 0 differences; the design-rule report is byte-identical |
| Built tracks | 684,227 numbers (centre line, normals, widths, banking, gates, kickers, wall grid) | identical, except segment / lap lengths on 4 tracks that differ by at most 1.1e-11 m (`pow()` in a different maths library) |
| Collision | 4,800 random locate / raycast / capsule queries, 66,216 numbers | 1 number differs, by 1 unit in the last place |
| Car physics | 34 scenarios (autopilot on every track, every car, kickers, random keyboard tapes with handbrake, nitro, reverse, walls) stepped in lockstep from the JS states | 39,906 of 46,200 steps bit-identical, the largest difference 8.3e-11; in free runs 48 full races (12 tracks × 4 cars) finish on the same step with the same wall-contact counts |
| Race timing and points | 72 runs, 2,964 events (48 medal-autopilot races + 24 random-key tapes with respawns) | 71 runs identical (every event, total, breakdown, split, nitro); 1 random wall-banging tape has one wall-contact end 2 steps later after 90 s |
| Ghosts | recorded runs packed by both | byte-identical (format 3 = the browser's format 2 bytes in base64); replay within 3 cm of the run (8 mm measured) |
| Car stats | `tools/car_stats.gd` against `web/tools/carStats.mjs` | identical, 4 cars × 12 stats (the Dune and Vortex have no browser counterpart) |
| Medal times | `tools/medals.gd` (50 autopilot runs per track and car) | 47 of 48 identical; Technical Trial with the Racer 3:45.083 against 3:44.033 (see Known limitations). The v6.1.0 sweep for six cars left the 48 old entries unchanged. (v6.3.0 put dirt and snow on four tracks, which have new times; the parity scripts compare the all-asphalt versions, `Tracks.build_asphalt`. Since v6.9.0 bronze is 1.3 × the author time here and 1.5 × in the browser, so `--js` compares author, gold, silver and the runs, not bronze, and says so: 4 of 4 entries identical on Rookie Oval and Banked Speedway with the Racer and the Kestrel) |
| AI | sensors and network in lockstep (683k inputs, 76k controls); the browser's saved network driving from two track starts | 0 differences, bit for bit; GDScript and FleetSim give the same numbers at every step |
| Interface | screenshots against the approved v5 ones | about 4 % of pixels differ on the menu (font rendering); 0 layout problems at 1024x600 to 1920x1080 |
| 3D world | 14 moments side by side with the browser version | close; draw calls 158-216 at high (web 106-127), 74-99 at low (web 78-102) |
| The whole game | `tests/e2e/game_e2e.gd races`: the medal autopilot drives through the game's own input layer | finishes exactly on the author time for every car on 3 tracks, then the record, score, ghost and menu are checked |

Speed (one 4-core Linux machine, software rendering): GDScript `Car.step` 37-48 µs against 0.94 µs in the browser
(about 40 times slower), fine for the player, ghosts and AI ghosts (a race frame takes about 1.3 ms of script
time, 2.5 ms with an AI ghost). That is why training uses FleetSim: 80 cars run 66-78× real time on 1 thread,
200-250× on 4 (benchmark), about 120-150× at Max in the game (the browser's Max: 32-37×). Without FleetSim,
GDScript trains at about 1.2× real time.

v6.0.0 (2026-10-28): a fresh import in the checkout opened without errors or warnings (editor and main scene); the
Windows and Linux release exports were made from a fresh import and the Linux one was run as a smoke test (menu, a
drive with nitro, training at Max: 130× real time with the native library).

v6.1.0 (2026-10-28): the headless suite passes (437 checks: sim 50, ui 120, world 126, game 66, ai 75); the
end-to-end scenarios pass (races: 18 races, every car on Rookie Oval, Seaside Stunts and Mountain Pass, 324 checks;
modes 29, menu 24, settings1 5 + settings2 6, perf 1: 1.37 ms of script time a race frame, shots 5); the Windows
release export was made from a fresh import (not started: no Windows here).

v6.2.0 (2026-10-28): the headless suite passes (509 checks: sim 52, ui 120, world 126, game 76, ai 135); the
end-to-end scenarios pass (cars 17 with the Vortex and a trained network on Lighthouse Bay, 16 with the Dune on
Rookie Oval; modes 29, menu 24, races 108: every car on Rookie Oval, shots 4); the four FleetSim libraries were
rebuilt; the Windows release export was made from a fresh import (no errors or warnings) and zipped as
`build/TrackRush-6.2.0-windows.zip` (not started: no Windows here).

v6.3.0 (2026-10-29): the headless suite passes (534 checks: sim 64, ui 123, world 133, game 76, ai 138); the
end-to-end scenarios pass (surfaces 13 with `gfx=high`; races 324: every car on Rookie Oval, Seaside Stunts and
Mountain Pass, which now has dirt and snow, finishing exactly on the new author times; modes 29, menu 24, cars 16,
perf 1: 1.65 ms of script time a race frame on Ramp Rally with the dust, 1.36 ms on Night Highway); the four FleetSim
libraries were rebuilt; the Windows release export was made from a fresh import (no errors or warnings) and zipped
as `build/TrackRush-6.3.0-windows.zip` (not started: no Windows here).

v6.4.0 (2026-10-29): the headless suite passes (587 checks: sim 75, ui 137, world 160, game 76, ai 139); the
end-to-end scenarios pass (races 432: every car on Rookie Oval, Seaside Stunts, Mountain Pass and Summit Rush,
finishing exactly on the author times; menu 28 with the 15-track fit check, cars 16 with the Dune on Forest Rally,
surfaces 13 with `gfx=high`, modes 29, perf 1: 1.60 ms of script time a race frame on Forest Rally, shots with
`gfx=high` on the three new tracks); the FleetSim libraries were not touched; the Windows release export was made
from a fresh import (no errors or warnings) and zipped as `build/TrackRush-6.4.0-windows.zip` (not started: no
Windows here).

v6.5.0 (2026-10-29): the headless suite passes (640 checks: sim 84, ui 155, world 160, game 93, ai 148; 5 min 56 s
after a fresh import); `tools/opponents.gd --check` reproduces all 450 stored opponent races; the end-to-end
scenarios pass at 1280 x 720 (economy 19 with `gfx=high`; races 216: every car on Rookie Oval and Summit Rush on the
author times; modes 29, menu 28, cars 16, settings 5 + 6, shots 2 with `gfx=high`, perf 1: 1.44 ms of script time a
race frame on Night Highway); the FleetSim libraries were not touched (the speed cap is only in the GDScript driver,
which the opponents use in the game); the Windows release export was made from a fresh import (no errors or
warnings; the opponents' data and scripts are in the pack) and zipped as `build/TrackRush-6.5.0-windows.zip` (not
started: no Windows here).

v6.7.0 (2026-10-29): the headless suite passes (733 checks: sim 88, ui 187, world 160, game 150, ai 148; 312 s); the
end-to-end scenarios pass at 1280 x 720 (terminal 34 with `gfx=high`, menu 28, settings1 5 + settings2 6, economy 19,
modes 29); the FleetSim libraries were not touched (nothing in the simulation changed); the Windows release export
was made from a fresh import (no errors or warnings) and zipped as `build/TrackRush-6.7.0-windows.zip` (not
started: no Windows here).

v6.8.0 (2026-11-04): the headless suite passes (766 checks: sim 93, ui 198, world 160, game 166, ai 149; 421 s); the
end-to-end scenarios pass at 1280 x 720 (unlock 17, economy 21, menu 28, settings1 5 + settings2 6, modes 29, races
72 on Hairpin Valley and Summit Rush with the Racer and the Dune, all with `gfx=low`; terminal 34 with `gfx=low` and
again with `gfx=high` for its screenshot; surfaces 13 with `gfx=high`). With `gfx=low`, `scenario=surfaces` failed its
snow-spray check (7 puffs alive, 8 wanted) twice; v6.7.0 from `git archive` passed it once with 8 at the same spot.
Low graphics emits 30 % of the spray, about 7.8 puffs alive on average there, so with `gfx=low` that check is a coin
flip in either version (nothing in v6.8.0 touches the effects): run `surfaces` with `gfx=high` (17 puffs). The FleetSim
libraries were not touched (nothing in the simulation changed); the Windows release export was made from a fresh
import (no errors or warnings; `sim/unlocks.gd` is in the pack) and zipped as `build/TrackRush-6.8.0-windows.zip`
(not started: no Windows here).

v6.9.0 (2026-11-04): the headless suite passes (770 checks: sim 96, ui 198, world 160, game 166, ai 150; 434 s); the
end-to-end scenarios pass at 1280 x 720 with `gfx=low` (unlock 17, economy 21, surfaces 13 twice, menu 28, races 72
on Rookie Oval and Hairpin Valley with the Racer and the Dune, modes 29) and with `gfx=high` (terminal 34, for its screenshot); the FleetSim libraries
were not touched (nothing in the simulation changed); the Windows release export was made from a fresh import (no
errors or warnings; the pack's `data/medals.json` has bronze 1.3) and zipped as `build/TrackRush-6.9.0-windows.zip`
(not started: no Windows here).

v6.10.0 (2026-11-04): the headless suite passes (784 checks: sim 98, ui 201, world 168, game 166, ai 151; 353 s); the
end-to-end scenarios pass at 1280 x 720 (surfaces 16 with `gfx=high`; races 108 on Hairpin Valley, Northern Lights
and Ramp Rally with the Racer and the Dune, settings1 6 + settings2 7, menu 28, modes 29, economy 21 with `gfx=low`);
all four FleetSim libraries were rebuilt ("trackrush-native 4") and match the GDScript simulation step for step on
the surface tracks; the medal times of the seven dirt and snow tracks and their AI opponents were redone (`--check`
reproduces every stored time); the Windows release export was made from a fresh import (no errors or warnings; the
new shaders and `world/screen_grime.gd` are in the pack) and zipped as `build/TrackRush-6.10.0-windows.zip` (not
started: no Windows here).

v6.11.0 (2026-11-04): the headless suite passes (845 checks: sim 110, ui 209, world 170, game 194, ai 162; 410 s);
the end-to-end scenarios pass at 1280 x 720 with `gfx=low` (upgrades 15, menu 28, economy 21, terminal 34, settings1 6
+ settings2 7; `upgrades` also ran with `gfx=high` for its screenshots: 14 of 15, the one failure the first draft's 2 %
line, see below); the FleetSim libraries were not touched (an upgrade only changes spec numbers FleetSim already
takes); the Windows release export was made from a fresh import (no errors or warnings; `sim/upgrades.gd` and
`ui/part_chip.gd` are in the pack) and zipped as `build/TrackRush-6.11.0-windows.zip` (not started: no Windows here).

v6.12.0 (2026-11-05): the headless suite passes (929 checks: sim 110, ui 224, world 199, game 234, ai 162; 554 s; no
audio errors with the dummy driver); the end-to-end scenarios pass at 1280 x 720 with `gfx=low` and
`--audio-driver Dummy` (settings1 7 + settings2 8, menu 28, terminal 34, upgrades 15, economy 21, perf 1: 1.9 ms of
script time a race frame at 60 fps with the sound) and `surfaces` 16 with `gfx=high`; `audio` 54 under Movie
Maker at 640 x 360 (see below); the FleetSim libraries were not touched; the Windows release export was made from a
fresh import (no errors or warnings; the 4 music and 32 effect files and `audio/` are in the pack, 43.5 MB zipped)
and zipped as `build/TrackRush-6.12.0-windows.zip` (not started: no Windows here).

v6.14.0 (2026-11-07): the headless suite passes (1002 checks: sim 142, ui 239, world 199, game 258, ai 164; 413 s);
the end-to-end scenarios pass at 1280 x 720 (cup 16 with `gfx=low` and `gfx=high`, menu 28, field 10, economy 21 with
`gfx=low`); the FleetSim libraries were not touched (no physics change); the Windows release export was made from a fresh import
(no errors or warnings; `sim/cups.gd`, `sim/cup_run.gd`, `ui/cup_*.gd` and `world/trophy.gd` are in the pack; the exe
115,032,704 bytes) and zipped as `build/TrackRush-6.14.0-windows.zip` (43.6 MB; not started: no Windows here).

v6.15.0 (2026-11-10): the headless suite passes (1026 checks: sim 142, ui 239, world 199, game 267, ai 179); the
end-to-end scenarios pass at 1280 x 720 (modes 30 with `gfx=high` and a trained network that fires nitro, economy 21,
field 10, cup 13 with `races=1`, menu 28 with `gfx=low`); `tools/opponents.gd --check` reproduces all 450 stored
opponent races; all four FleetSim libraries were rebuilt ("trackrush-native 5") and match GDScript step for step
(the lockstep tests now also check that nitro is used and refilled); the Windows release export was made from a
fresh import (no errors or warnings; the exe 115,032,352 bytes) and zipped as `build/TrackRush-6.15.0-windows.zip`
(43.8 MB; not started: no Windows here).

v6.16.0 (2026-11-10): the headless suite passes (1029 checks: sim 142, ui 240, world 199, game 269, ai 179); the
end-to-end scenarios pass at 1280 x 720 (upgrades 15 with `gfx=low`: 40 clicks buy every level, the same autopilot 2.9 %
quicker, the ghost replays the level-10 run within 0.7 cm; with `gfx=high` it took the screenshot but ran past the
25-minute limit after 12 checks; menu 28, terminal 34 with `gfx=low`, its Tab test fixed: `cup` (v6.14) made it list
car, cup, clear); `tools/upgrades.gd` measured the new levels (stats 1,759 s, `--quick`
laps 1,227 s); the FleetSim libraries were not touched (upgrades are spec data); the Windows release export was made
from a fresh import (no errors or warnings; the exe 115,033,984 bytes) and zipped as
`build/TrackRush-6.16.0-windows.zip` (43.8 MB; not started: no Windows here).

v6.17.0 (2026-11-10): the headless suite passes (1037 checks: sim 145, ui 240, world 199, game 274, ai 179; new: a
reset with everything filled in, the backup's contents, the file read back, a second reset keeping the first backup,
no reset when the backup can't be written, the terminal asking first, the app dropping the network and cup it held);
the end-to-end terminal scenario passes at 1280 x 720 (38 with `gfx=low`: `reset everything` typed in asks first,
`reset everything confirm` redraws the menu's header at $0 / 0 pts at once, the backup holds the old career, the
settings stay; screenshot `terminal_reset_everything`); the FleetSim libraries were not touched; the Windows release
export was made from a fresh import (no errors or warnings; the exe 115,037,136 bytes) and zipped as
`build/TrackRush-6.17.0-windows.zip` (43.6 MB; not started: no Windows here).

## How v6.14.0 (championships) was verified

- **The cups and the maths** (`tests/test_sim.gd` `_cups`, 16 checks): five cups of three tracks covering all 15
  tracks once, rising difficulty (mean 2.0, 2.7, 3.7, 4.0, 4.7), each opening with its last track (3, 10, 12, 13, 15);
  points 10-8-6-5-4-3 and 0 for a DNF; ties: equal points go to the better best place, then to the latest race
  (four constructed ties); a cup run: the same five drivers in every race with their paces, the grid after race 1 in
  standings order, a JSON round trip, damaged runs rejected, a whole cup's table (you 4th with 16 points, the leader
  23).
- **The grid with you anywhere** (`Field.grid` with an anchor): on all 15 tracks for your slot 0-4 (every car on
  asphalt with 1 m to spare beside the widest car, at least 2 m apart, at most 20° of turn, alternating sides, located
  back on the right sample); a race from pole on Rookie Oval: the four AI behind the line cross it without counting
  an early lap. The v6.13 field grid (you last) is unchanged: the field tests in sim, game and ai pass as before.
- **Pay and the cabinet**: a 3rd then a win in the Pro Rookie Cup pays $1,500, then $4,800 ($6,300 and 166 points in
  all, as a win straight away); the same again pays nothing; 5th and 6th nothing; later cups and harder levels more
  (a Rookie-level Rookie Cup win $2,520, an Elite Grand Finale win $25,200); the cabinet survives a restart, keeps the
  best place, `reset career` keeps trophies and clears cup payouts and the run, a damaged `career.cups` is repaired,
  an old save has none.
- **The game** (`tests/test_game.gd` `_app_cup`, 11 checks, through the app): the empty cabinet, T opens the picker,
  a locked cup refused naming its tracks, Enter starts race 1 (you last, the cup in the save file), race 1 driven by
  the medal autopilot to the finish (paid as a field race, the panel's points line and "Enter: standings"), R ignored
  after the finish, Enter: the standings (table, next track picked behind them, the save file), race 2 from your
  standings slot on the usual start spot with the cars ahead of you in the standings ahead of you, Esc mid-race not
  counted, the trophy moment (podium trophies gold / silver / bronze, `cup_final`, the cup's pay ids, the cabinet, the
  run gone from the save), Enter: the menu with the trophy, the same place pays nothing again, Quit cup asks and pays
  nothing. The terminal's `cup` (2 checks). `tests/test_ui.gd` `_cup_ui` (9 checks): the picker's rows and keys, the
  standings table and keys, the cabinet button's cells and tooltip, the final-standings panel docked right at
  1280 x 720 (131-590 px) and fitting 800 x 600.
- **E2E** (`scenario=cup`, xvfb and llvmpipe, 1280 x 720, the Rookie Cup at Rookie with the Racer, every race driven
  by the author run's medal autopilot; 16 of 16 checks at `gfx=low` in 155 s and at `gfx=high` in 1018 s): the menu
  fits 1280 x 720 with the Cups button (content 720 of 720 px); the picker fits (panel 68-651 px, no scrolling); race 1
  from last on the grid: 1st in 2:07.383; the standings fit (144-575 px); race 2 from pole: 1st in 3:56.850; race 3
  from pole: 1st in 3:13.400; the trophy moment (gold, silver, bronze on the podium; you 1st with 30 points); the
  menu's cabinet shows the Rookie Cup's gold. Money $0 to $9,780: $7,260 from the three races (medals and places),
  $2,520 from the cup. The Controls screen (with the new row) fits 1280 x 720 at 714 px after a shorter terminal tip.
  The e2e `menu` (28), `field` (10) and `economy` (21) scenarios pass unchanged at `gfx=low`.
- Not verified: a cup at a level where you don't win (a grid with you in the middle in 3D: covered by the sim test on
  every track only), a gamepad in hand, a real graphics card, Windows.

## How v6.13.0 (Race the field) was verified

- **Contacts** (`tests/test_sim.gd`, `sim/car_contact.gd`): two cars 0.3 m into each other are pushed apart exactly,
  shared by mass (Racer 0.171 m, Thunder 0.129 m), the closing speed mostly gone, no energy made; flat (no vertical
  speed, no launch); no sticking once apart; a car 1.3 m higher flies over; `collide(a, b)` and `collide(b, a)` give
  the same cars bit for bit (20 glancing hits) and the same again on a re-run; no tunnelling at 92 m/s (rear-end,
  head-on, T-bone: each car ends on its own side; what the push's limit of 0.5 m a car leaves after a deep first step is
  gone the step after); 30 random hits between all six cars: never more kinetic energy, finite, yaw kick ≤ 1.5 rad/s.
- **The grid on every track** (15 tracks, 6 cars): the player on the usual start spot (right lane), the AI ahead
  alternating sides 10 m apart, all on asphalt road with 1 m to spare beside the widest car, before the first
  checkpoint, at least 2 m apart, on a stretch that turns at most 20°.
- **Whole AI field races** (`tools/field.gd`, every car driven by its AI opponent network, the player's slot too at the
  level's cap; the Racer; 5 tracks: Rookie Oval, Hairpin Valley, Forest Rally, Coastal GP, Summit Rush):
  - 25 races (all five levels): every AI finished in every race (125 of 125), 0 stuck or wrong-way respawns, 62 new
    AI-AI contacts a race (8.5 closing faster than 3 m/s), 30 with the player's car; the finishing order follows the
    drivers' paces in 84 % of AI pairs (the whole order in 10 of 25 races); about 1.0 ms of script time a step for the
    six cars on one thread.
  - 15 races (Rookie, Pro, Elite, after the cap fix below, `--solo`): 75 of 75 finished, 0 respawns, 75.6 AI-AI
    contacts a race (9.2 hard), 30.9 with the player; pace order in 83 % of pairs (5 of 15 races exactly); against each
    AI's own race alone with the same cap the order is kept in 83 % of pairs and a field race is 1.1 % off the solo
    time on average (the traffic costs little time).
  - A contact is counted each time two cars start touching, so rubbing side by side counts many times; "hard" ones are
    the real knocks.
  - `tests/test_ai.gd` runs three of them (Pro oval, Elite Forest Rally, Elite Summit Rush: all finish) and one twice
    (the same finish times bit for bit).
- **The game** (`tests/test_game.gd`, through the app): the menu button (off with My AI, refused asking for a level,
  a locked track refused, an unowned car offered), a Pro field on Rookie Oval driven by the medal autopilot: the grid,
  the HUD's field block, the finish (place, the place rewards, money, the panel docked right), the medal, record and
  Hairpin Valley opened as in Drive, the podium with every AI finished out of sight, R and Esc. `tests/test_ui.gd`: the
  HUD's block (P3/6, ahead / behind, standings with +12.5 and "out") and the finish panel's rows ("racing…", gaps),
  docked right at 1280 x 720 and full width in a narrow window. `tests/test_sim.gd`: lineup, cap_for, five identical
  autopilots 0.25 s apart (gaps), standings with finished and out cars, the traffic layer braking and steering to the
  free side, pay by place (paid once, a better place pays the difference, levels and tracks scale).
- **E2E** (`scenario=field`, xvfb and llvmpipe, 1280 x 720, Elite field on Rookie Oval, the author run's medal
  autopilot; one run at gfx=low, one at gfx=high, 10 of 10 checks): the grid during the countdown, a battle (P3/6
  side by side with Nils Haugen, 0.01 s), a win in 2:02.733 paying $4,600 with the gold (five place rewards), the
  podium (You, Nils Haugen, Kai Ostrom), R, Esc. Script time: the field's step 1.05-1.11 ms (six cars, the
  autopilot's input included); the AI engines 1.04-1.18 µs a sample, 1.24-1.42 ms a frame at 60 fps for the 3 voices
  heard (the two farthest are paused); with the player's car (0.75 ms in v6.12.0) and the rest a frame stays far under
  16 ms. Not measured on a real graphics card. The e2e `menu`, `economy`, `upgrades` and `terminal` scenarios pass
  unchanged.

## How v6.12.0 (sound and music) was verified

Nobody listened: everything here is measured (see Known limitations). The game's sound was recorded with Movie Maker
(`scenario=audio` under `--write-movie`, lockstep: every frame 1/60 s of game and 800 samples at 48 kHz) on a copy of
the project at 640 x 360, and analysed in Python (levels of the recorded AVI's audio, the engine's pitch against the
rpm the frames logged, spectrograms with the firing frequency drawn over them).
- **Engines** (`tests/test_world.gd`, each car on load at a third and two thirds of its redline): the firing
  frequency stands out of the spectrum by 25-44 dB and doubles exactly with the rpm (Racer 144 / 287 Hz, Kestrel 110
  / 219, Thunder 175 / 350, Drifter 89 / 177, Dune 79 / 159, Vortex 322 / 644); levels -15.2 to -18.3 dBFS RMS
  (within 3.1 dB of each other); a gear change 369 → 262 Hz (× 0.71, the rpm's ratio) with the load gone in the
  shift; the limiter cuts 64 of 219 firings; the Thunder pops 11 times on a lift, never on load; the Drifter's turbo
  spools to 0.83 and falls to 0.10 on a lift (one blow-off); nitro 4.0 dB louder and 2.1 dB brighter; engine braking
  -22.8 dBFS; the same inputs give the same samples. Script time 1.4-2.0 µs a sample (0.6-0.8 ms a frame at 24 kHz).
- **In a race** (Movie Maker, the medal autopilot; Seaside Stunts with the Drifter, Mountain Pass with the Dune): the
  engine's pitch is within 50 cents of the sim's firing frequency in 99 % of 679 and 1,125 windows (median error 3.1
  and 2.3 cents); at every upshift (7 and 19) the pitch drops, 57-58 ms after the rpm does (median; 3.5 frames: the 50
  ms the engine is rendered ahead and the mix); the engine never ran dry. The first recording found it 8 frames late: an
  `AudioStreamGenerator`'s ring is a power of two (8,191 frames for 0.25 s at 24 kHz), so `CarAudio` filled it 91 ms
  further than meant; it now counts from the empty ring (`queued()`; `tests/test_world.gd` checks 50 ms).
- **Levels** (the recording, after the master volume, defaults): menu music RMS -23.5 dBFS (peak -10.2); race 1
  -18.6 dBFS (peak -1.4), race 2 -18.9 (peak -1.1), engine bus -17.9 / -18.2, effects -20.0 / -21.0, music -18.7 /
  -18.5; a flat-out wall hit with the Thunder at 64 m/s peaks at -0.5 dBFS (the limiter's ceiling; nothing at full
  scale anywhere); Music at 0: the mix silent (-200 dBFS); the window in the background: digital silence.
- **Timing**: the countdown's beeps 1.000-1.017 s apart; every checkpoint, lap and finish chime in the frame its gate
  is taken (7 of 7, 12 of 12), the checkpoints raising the effects bus 4.4-17.3 dB within 83 ms; the medal stinger
  0.883 s after the finish (`STINGER_AT` 0.9 s, within a frame) with the music down to -11 dB; the wall hit in its
  contact frame, +9.1 dB within 83 ms; the races' events: 9 blow-offs, 6 landings, 16 and 14 nitro lightings, gravel
  on 586 frames of dirt and snow on 1,189 frames of snow (none on 4,865 of asphalt), wind up to 0.49.
- **The AI car** (`Race the AI` with a Racer network): its engine positional (`AudioStreamPlayer3D` at the AI car's
  model, level 0.6, 16 kHz, 482 updates in the run), the best-run ghost silent. All 54 checks of the third recording
  pass (the second stopped race 2 after 1,200 s of real time: the limit is in game time now).
- **Headless** (`tests/test_game.gd`): buses and the limiter, the volume law, saved volumes (and applied when the
  game starts: the first e2e `settings2` run found they weren't, `GameAudio._ready` ran before the save was read), the
  background mute, every file, the pools and voice limits, the queue, music levels and cross-fades, an app race's
  sounds step by step, the shop's sounds, quitting mid-race. No audio errors with the dummy driver.
- **Settings** (`tests/test_ui.gd`, e2e `settings1` / `settings2` and `audio`): the five rows, keys, pad, a click on a
  bar, two columns at 1280 x 720 (a real frame: every row on screen, no scrolling), one column at 1024 x 600 (scrolls,
  the picked row kept in view); the Music volume and the mute off survive a restart.
- **Cost** (e2e `perf`, Night Highway): 1.9 ms of script time a race frame at 60 fps, of which the car's sound is
  0.75 ms (1.8-1.9 µs a sample); 1.4-1.6 ms before v6.12.0.
- Clips (not in git): the menu music, the first 30 s of both races and the wall hit as Ogg files, the races' Engine
  bus as float WAV.

## How v6.11.0 (car upgrades) was verified

- **What a level does** (`tools/upgrades.gd`, new, 447 s on 3 threads: `tools/car_stats.gd`'s measurements of every
  car stock, engine 1-3, tyres 1-3, nitro 3 and everything at 3; the engine and tyre rows are `Upgrades.MEASURED`,
  `--check` compares): to 200 km/h, engine 3 against stock, Racer 9.78 → 8.33 s, Kestrel 11.28 → 9.30, Thunder 8.20 →
  7.18, Drifter 9.23 → 7.98, Dune 12.68 → 10.28, Vortex 6.22 → 5.40 (each level 4-8 % on the one before); top speed
  277.7 → 289.5, 230.2 → 237.7, 312.7 → 327.9, 264.3 → 275.7, 222.4 → 231.6, 321.4 → 342.0 km/h; tyres 3, the 30 m / 120 m
  skidpads, Racer 1.68 / 1.58 → 1.89 / 1.73 g, Kestrel 1.78 / 1.59 → 2.00 / 1.71, Thunder 1.47 / 1.56 → 1.69 / 1.74,
  Drifter 1.59 / 1.52 → 1.82 / 1.67, Dune 1.71 / 1.43 → 1.92 / 1.58, Vortex 1.68 / 1.75 → 1.90 / 1.98 (2.6-5.0 % a
  level); nitro 3: every tank 30 % longer (Racer 5.0 → 6.5 s, 145 → 223 m on one tank). Loose grip 3 on dirt (30 m
  skidpad / 100-0 km/h): Racer 1.15 → 1.32 g / 29.8 → 27.2 m, Kestrel 1.26 → 1.45, Thunder 0.90 → 1.04, Drifter 1.15
  → 1.32, Dune 1.63 → 1.67 (capped at its asphalt grip), Vortex 0.89 → 1.03; on snow +14-16 % for every car (the Dune
  1.21 → 1.40). Tyres 3 change nothing on dirt and snow (within 0.7 %), as meant. Drift held changes little (Racer
  0.83 → 0.73 s with everything at 3; the Vortex's engine 3 alone 1.22 → 1.55 s: more power holds a slide longer).
- **Laps** (`tests/test_sim.gd`, the medal autopilot at 20 m/s² and lookK 0.75 with nitro, everything at 3 against
  stock): Rookie Oval Racer 2:11.417 → 2:06.283, Thunder 2:09.717 → 2:04.950, Dune 2:19.683 → 2:12.433; Ramp Rally
  Racer 3:10.833 → 2:56.717, Thunder 3:17.417 → 3:05.733, Dune 3:03.383 → 2:55.117. `tools/upgrades.gd --laps --quick` (the medal autopilot's best race of 10 settings with nitro, 4 tracks × 6 cars,
  863 s on 3 threads): everything at 3 is 4.0-8.1 % quicker for every car on every track (Rookie Oval 5.3-7.1 %,
  Technical Trial 4.8-6.9 %, Ramp Rally 4.1-8.1 %, Hairpin Valley 5.6-7.0 %; the Racer on Rookie Oval 2:11.417 →
  2:03.138, on Ramp Rally 3:09.200 → 2:53.932); one part at level 3: tyres 3.4-5.4 % on the two asphalt tracks
  (0.5-3.7 % on the dirt and snow ones), engine 0.6-2.2 %, loose grip 1.2-4.1 % on Ramp Rally and Hairpin Valley (the
  Dune 0.25 % on Ramp Rally; nothing on asphalt, as meant), nitro 0-0.8 % (the Vortex 0.18 % slower on Technical
  Trial: noise of the setting search). The steps against a wall and the largest sideslip of the fastest run go both
  ways (the Racer on Ramp Rally 279 → 0 wall steps, the Thunder on Technical Trial 138 → 47; the Drifter on Rookie
  Oval 39 → 103, its slip on Hairpin Valley 25° → 38°): the autopilot's settings were tuned on stock cars and the
  tool keeps the fastest run, not the cleanest (see Known limitations).
- **Stability** (`tests/test_sim.gd`, every car with everything at 3): 240 jumps, no bounce, no spin, at most 29.5° of
  turn with a steer key held (limit 35°); braking hard in a 120 m curve from 0.45 g no car spins (sideslip at most
  1.2° on asphalt, 1.5° on dirt, 1.9° on snow); keyboard lane keeping: no slide, and no car weaves more than 0.5°
  beyond its stock self (the Racer with tyres 3 weaves 5.05° against 4.89° at 120 km/h with a 20 m look-ahead,
  sliding 2°: the old fishtail test's 5° line counted it as one, see Known limitations).
- **Specs** (`tests/test_sim.gd`): every part, level and car changes only its own keys by the exact formula; max_speed,
  mass and brakes never; tyres + loose grip on dirt = loose grip alone; level 0 is the stock spec object; on all-asphalt
  Rookie Oval loose grip 3 gives the Dune's race bit for bit; nitro 3 refills 1.30 × the tank for the same points.
- **FleetSim** (`tests/test_ai.gd` "FleetSim with upgraded cars"): every car at 4 upgrade sets reaches FleetSim with
  every number the same; lockstep training of an upgraded Racer on Ramp Rally and an upgraded Thunder on Hairpin
  Valley: states, sensor inputs, fitness, reasons and history the same; every car with everything at 3 over Ramp
  Rally's dirt, sliding (12 drives of 600 steps, 4038 with an axle on dirt): the same at every step. No native change.
- **Prices and buying** (`tests/test_sim.gd`): rising, multiples of $50, the Racer's base $12,000, the Vortex's engine 3 ×
  3 the Kestrel's; $248,200 for everything against $94,000 for the cars, 3.4 gold + Expert careers (2.0 author +
  Elite) with the cars; buying: not without the money (says how much), in order, not past 3, not for a car not owned,
  read back from the file; the save migration from versions 4 and 3 and 5 kinds of junk; reset makes every car stock.
- **Ghosts**: an upgraded Racer's run on Ramp Rally (2:56.717 against 3:10.833 stock) is saved with `up` [3, 3, 3, 3]
  on the record and the ghost; after the car went back to stock the ghost replays it within 2.3 cm at every step.
- **The app and the terminal** (`tests/test_game.gd`): the chips through the app (locked, short of money, asks first,
  Cancel, yes, MAX), Drive / Race the Rookie AI (its car stock) / Watch the AI and Race my AI with the upgraded car;
  every `upgrade` form, 11 bad lines, `buy <car> <part>`, the `status` row, Tab, reset.
- **The picker** (`tests/test_ui.gd`): four chips at level 0 with prices in place of the description at 1280 x 720,
  tooltips, the store's buying, grey prices when short, MAX, the card's green bars and upgraded top speed, a locked
  car's chips off and its description shown, the pad down to the chips and up again, both rows at 1366 x 768.
- **The model** (`tests/test_world.gd`): no parts on a stock car or a ghost; with everything at 3, 840-2,736 more
  triangles in one more skinned mesh with the car's material; mud flaps on four cars; fewer on low detail.
  `tests/visual/car_studio.gd up=3,3,3,3` was looked at from the side and behind.
- **End to end** (`tests/e2e/game_e2e.gd` `upgrades`, 205 s with `gfx=low`): a new career at $0 shows the Racer's four
  chips greyed and the Kestrel's off; the medal autopilot drives the stock Racer's author run on Rookie Oval (2:01.867,
  the author time, clean); with the money it earned and more from the terminal ($33,050) the chips fit 1280 x 720,
  each of the 12 clicks asks first and buys ($28,050), the chips read MAX and the card's bars grow (speed 0.60 →
  0.69, acceleration 0.51 → 0.81, grip 0.55 → 0.85, nitro 0.74 → 0.97); the same autopilot settings in the upgraded
  car: 2:00.250, 1.3 % quicker (the check asks for 0.5 %: this run touched the walls 9 times, the stock one never;
  the first draft's 2 % line failed once with `gfx=high`), an author medal, the record's `up` [3, 3, 3, 3]; R races
  its ghost, at most 0.006 m from the car. Screenshots: `docs/screenshots/upgrades.png` (every part at MAX) and the
  ask, race and finish screens, all looked at.

## How v6.10.0 (dirt and snow polish) was verified

- **Brakes** (`tests/test_sim.gd`, against the v6.9.0 distances it keeps as a table, `V69_BRAKE100`;
  `tools/car_stats.gd --surface=dirt|snow`): 100-0 km/h on dirt 29.8 / 27.3 / 37.7 / 30.0 / 27.4 / 37.2 m (Racer,
  Kestrel, Thunder, Drifter, Dune, Vortex; v6.9.0 34.0 / 31.2 / 43.0 / 34.8 / 31.2 / 42.4: 12-14 % shorter), on snow
  36.6 / 32.8 / 47.1 / 34.5 / 28.7 / 47.1 m (43.0 / 38.5 / 55.2 / 40.5 / 33.8 / 55.2: 15 % shorter). The test wants
  10-20 % on every car and surface, the Dune shortest on snow and within 0.2 m of the shortest on dirt, the Thunder
  and the Vortex longest. Asphalt is bit for bit as before (`car_stats.gd` on asphalt gives v6.9.0's numbers for all
  six cars: 30.7 / 27.7 / 33.8 / 33.1 / 31.7 / 28.8 m; the medal times of the eight asphalt tracks are byte for byte
  the same and the v6.5 medal hashes of the asphalt tracks still match). Braking flat out from 0.45 g in a 120 m
  curve: in v6.9.0 five of six cars spun on snow and the Thunder and Vortex on dirt; now none, at most 1.7° of
  sideslip on dirt and 2.5° on snow (a test).
- **Walls** (`tests/test_sim.gd`): coasting at 108 km/h into a wall at 11° and scraping it for 2 s, the Racer loses
  11.3 m/s on asphalt (as before), 7.1 on dirt (v6.9.0 10.7) and 5.4 on snow (7.1). Walls still cost time: the medal
  autopilot's lap against never braking (riding the walls), Racer, one lap: Hairpin Valley 1:21.967 / 1:26.900, Ramp
  Rally 1:05.950 / 1:09.233, Mountain Pass 1:55.217 / 1:58.283, Canyon Run 1:29.950 / 1:39.300, Forest Rally 1:09.683
  / 1:11.633, Northern Lights 1:07.650 / 1:07.783 (v6.9.0: +0.433 s, now +0.133 s), Summit Rush 1:49.317 / 1:53.017.
  With the Vortex and the Thunder never braking is faster on Northern Lights (see Known limitations).
- **FleetSim** (`tests/test_ai.gd` "FleetSim on dirt and snow: every car", now with Northern Lights): every car over
  the entries and exits of the loose stretches of Ramp Rally, Hairpin Valley, Mountain Pass and Northern Lights (72
  drives of 900 steps; 38231 steps with an axle on loose ground, 3962 of them braking, 891 touching a wall) is the
  same in FleetSim as in GDScript at every step. All four libraries were rebuilt (Linux and Windows, debug and
  release; `version()` "trackrush-native 4", checked by a test).
- **Medal times** (`tools/medals.gd --update --jobs=3` for the seven surface tracks): the eight asphalt tracks'
  entries are unchanged (JSON compared); the new author times (Racer / Kestrel / Thunder / Drifter / Dune / Vortex,
  against v6.9.0): Hairpin Valley -3.68 / -4.10 / -3.27 / -4.33 / -1.82 / -3.73 s, Ramp Rally -1.48 / -1.57 / -2.57 /
  -2.17 / +0.03 / -3.87, Mountain Pass -0.70 / -0.12 / -1.27 / -0.50 / -0.05 / -0.98, Canyon Run -0.42 / -0.95 / -1.52
  / -0.15 / +1.78 / -0.93, Forest Rally -3.45 / -2.33 / -7.73 / -1.35 / +2.00 / -8.28, Northern Lights -2.53 / -1.35 /
  -6.22 / -0.53 / -0.25 / -9.32, Summit Rush -1.88 / -1.57 / -2.85 / -2.62 / +0.67 / -3.80.
- **AI opponents** (`tools/opponents.gd levels` for the seven tracks, all six cars): all 42 recalibrated; the
  Drifter's Forest Rally network was retrained (`--train --retrain`, 80 generations, 3:11.133 against the author's
  3:14.500) because its Elite came out at 1.066 × the author time, slower than gold. Rookie 1.582-1.618 × the author
  time, Amateur 1.384-1.415, Pro 1.238-1.261, Expert 1.118-1.143, Elite 0.988-1.021, each level slower than the one
  above on every track and car; `--check` reproduces every stored time (496 s). Opened tracks and paid rewards are in
  the save file and nothing touches them (`Car.PHYSICS_VERSION` stays 3, so records and ghosts set before still
  count).
- **The screen overlay** (`tests/test_world.gd`, a ScreenGrime fed car poses on Ramp Rally and Hairpin Valley): 3 s on
  dirt at speed, 20 splats and a film of 0.66; after 2.5 s on asphalt none left and the film at 0.12, nothing at all
  after 6.5 s; nothing inside the keep-out ellipse at any time; the AI car close ahead raises it (standing on the
  dirt: no mud; a car 12 m ahead at 108 km/h: 0.82 of its dust, 10 splats; none from a car behind or on asphalt, none
  from 50 m); Low graphics keeps it at 8 or fewer (cap 12); the setting off draws nothing; 4 s on snow: 21 flecks and
  frost at 0.65, no mud. The chase camera stays still on dirt at 126 km/h (no rumble) and still shakes on a wall hit.
  The AI opponent's ghost throws up dust on dirt (19 puffs); the best-run ghost none.
- **The barriers** (`tests/test_world.gd`): on a surface track they carry the grime shader with the same vertex
  colours as the track built all-asphalt and the dirt and snow weights in the alpha (Ramp Rally: 30632 vertices dirty;
  Hairpin Valley: 17248 snowy); an all-asphalt track keeps the plain material.
- **Settings and jumps** (`tests/test_ui.gd`): the new row is on by default, Enter turns it off and on and emits the
  setting; the rows below moved one down. Jumps (`tests/test_sim.gd`, every car): the test's slow driver now takes a
  surface track's grip into account (`Autopilot.basic` with the car's spec), as the Vortex hit a wall on Forest
  Rally's dirt at 41 m/s with the old one and took off sideways; 240 jumps, no bounce, no spin, at most 28.5° of turn.
- **End to end** (1280 x 720): `surfaces` with `gfx=high` 16 passed (Ramp Rally with the Dune: 64 dust puffs, 28 mud
  splats and a film of 0.70 on the dirt, none in the middle, no camera shake; back on asphalt the screen was clean
  after 22.8 s of real time at the software renderer's frame rate (the overlay's step is capped at 0.1 s a frame, so
  about 2 s of its time); Hairpin Valley with the Racer: 26 snow puffs, 19 flecks, frost 0.55); `races` 108 passed
  with `gfx=low` on Hairpin Valley, Northern Lights and Ramp Rally with the Racer and the Dune (every finish equals
  the new author time to the millisecond, e.g. Hairpin Valley 3:54.500 and 3:48.050); `settings1` 6 + `settings2` 7
  (the new row turned off, still off after a restart and in the save file); `menu` 28, `modes` 29, `economy` 21. The
  first `surfaces` run failed only its wait for the clean screen (20 s of real time at about 0.7 frames a second); it
  now waits up to 120 s and reports the time.
- **Pictures** (`tests/visual/world_preview.gd`, now with `grime=` and `slip=`, and the e2e shots at 1280 x 720,
  `gfx=high`, all looked at): the overlay was toned down twice (its first shapes read as leaves and bubbles, the frost
  as lightning; now metaball lumps with droplets and drips, and a grainy frost haze), the barrier mud went from
  blotches to drops. `docs/screenshots/screen_mud.png` and `screen_snow.png` are from `scenario=surfaces`;
  `border_old.png` (v6.9.0, from a copy of that version) and `border_new.png` are `world_preview` from the same camera
  on Ramp Rally.

## How v6.9.0 (a faster bronze) was verified

- **The medal times** (`tools/medals.gd -- --factors`, about a second): 90 of 90 bronze times rewritten, 0 gold, 0
  silver; a diff with the bronze values masked shows only the method line (the factors line says 1.3); recomputed
  independently (1.3 × the author time, rounded to the millisecond half up as JS does, then up to a whole second):
  0 differences; 13-54 s faster than before. `-- --factors --check` reports a file made with other factors as out of
  date (exit 1). `tests/test_sim.gd` "a faster bronze medal": the factors (gold 1.06, silver 1.2 unchanged), the file's
  factors and method (and `method_text()` makes the same line), Rookie Oval with the Racer 2:01.867 / 2:10 / 2:27 /
  2:39, all 90 bronzes faster than before and slower than silver; the v6.5 medal hashes of the ten kept tracks still
  match once their bronze is put back to 1.5 × (`Medals.WEB_FACTORS`), and every track's bronze is 1.3 ×.
- **The browser comparison** (`node tools/parity/dump_medals.mjs` then `tools/medals.gd -- --tracks=rookie-oval,banked-speedway
  --cars=racer,kestrel --js=...`, 100 s): 4 of 4 entries identical (author, gold, silver, winning setting, steps, wall
  steps), "not compared: bronze (1.3 × the author time here, 1.5 × in the browser)", exit 0. The test checks that
  `compared_medals()` is author, gold and silver.
- **A player from before** (`tests/test_sim.gd`, its own save file): a v6.8.0 save with 3:03.000 on Rookie Oval (the
  old bronze), Hairpin Valley opened and the bronze paid: no medal now and the next medal to aim for is bronze at
  2:39, Hairpin Valley still open, $300 / 10 pts still there; the same time again pays and opens nothing; a 2:39
  bronze pays nothing (paid before) and a silver then pays only silver ($500). A save from v6.7.0 with the same 3:03
  (no `tracks_open` yet) opens nothing after Rookie Oval; a track with a best time (Ramp Rally) stays open. The v6.8.0
  stickiness test (bronze patched 30 s faster) still passes.
- **The AI levels** (all 90 tracks × cars, their stored times against the new medals): Rookie 1.58-1.62 × the author
  time, slower than bronze everywhere (at least 1.212 × bronze); Amateur 1.385-1.414 ×, slower than bronze
  everywhere (at least 1.058 ×), so "between silver and bronze pace" had become false; Pro 1.237-1.265 ×, between
  silver and bronze everywhere (was "about silver medal pace"); Expert between gold and silver; Elite at gold or
  faster (36 at the author time or under). Not recalibrated; the Amateur's and Pro's texts changed and
  `tests/test_ai.gd` checks every level's text against every track and car.
- **End to end**: `scenario=unlock` takes the new bronze with a faster slow autopilot (`Autopilot.basic`, corner grip
  13 m/s², 50 m/s at most): 2:32.900 against bronze 2:39 and silver 2:27, the same to the millisecond as a headless run
  (which also gave v6.8.0's 2:49.750 for 11 m/s² and 40 m/s; 55 m/s with 11 m/s² only reaches 2:38.283); its 17 checks
  pass, the finish panel shows a bronze and Hairpin Valley unlocked. `economy` (21) pays and opens as before; the
  HUD's target in its race reads BRONZE 2:39.000. `surfaces` with `gfx=low` passes twice: the snow-spray check now
  takes the most puffs alive over 12 frames (8 and 9) against a threshold scaled by the quality's share (3 at low, 6
  at medium, 8 at high); the dust peaked at 19. Screenshots retaken: `docs/screenshots/menu.png` and `finish.png`
  (from `economy`: Seaside Stunts' medal times 1:08.233 / 1:13 / 1:22 / 1:29), `locked.png` (from `unlock`: Hairpin
  Valley 5:10) and `terminal.png` (`terminal` with `gfx=high`: the Rookie Oval panel behind it).

## How v6.8.0 (unlocking tracks) was verified

- **The rule and the save file** (`tests/test_sim.gd` "tracks open one at a time", on its own save file): a new
  career has only Rookie Oval open; no medal opens nothing; bronze (and author) on Rookie Oval opens Hairpin Valley
  once (announced once: `claim` returns the id only when it was locked); a medal on a locked track opens nothing;
  silver on Hairpin Valley opens Ramp Rally; the list is in the file's career (still version 4) and read back; the
  last track opens nothing. **Sticky**: the bronze that opened Hairpin Valley earns no medal once `medals.json`'s
  bronze is 30 s faster (patched in memory), and Hairpin Valley stays open; also when the record moves to the archive
  (another signature). **The upgrade** of a v6.7 save: Rookie Oval at bronze, Hairpin Valley driven without a medal,
  an archived Ramp Rally time under today's bronze, an archived Technical Trial time without a medal, an unknown car
  on Coastal GP, the Kestrel's bronze on Canyon Run and three kinds of junk open exactly Hairpin Valley, Ramp Rally,
  Banked Speedway, Technical Trial, Coastal GP, Canyon Run and Night Highway (8 open), stored in the file; a version 3
  save the same way; the flag opens all 15. **Junk**: five non-lists are worked out again; a list keeps known and
  unknown ids once each. **Terminal and reset**: `unlock tracks` opens all 15, a gold while the flag is on opens the
  next track for good without an announcement, `reset_career` turns the flag off and keeps what medals opened.
- **The menu and the finish panel** (`tests/test_ui.gd` "locked tracks", the in-memory store): its default is every
  track open (so the older interface tests are unchanged); with Hairpin Valley opened, tiles 3-15 are locked with
  "Bronze on 02" ... "Bronze on 14" and a tooltip; 3 picks locked Ramp Rally (its panel's note, Drive LOCKED, not the
  primary style); Enter still emits drive (the app refuses); the arrows move over locked tiles; Race the AI's tooltip
  says the track is locked, Watch the AI's doesn't; a car for sale shows LOCKED / BUY first on a locked track; NEW
  until picked or the menu is left. The finish panel's line ("Lighthouse Bay unlocked", "track 11 is open: pick it
  on the menu"; only the first part 480 px wide) with the tallest payout fits: 693 px at 1280 x 720 (+30), 522 at
  800 x 600 and 1024 x 600 (+26), 795 at 480 x 800 (+30).
- **In the app** (`tests/test_game.gd` "the app: the tracks open one at a time", a new save file): 14 tiles locked;
  Hairpin Valley picked: the panel's note, Drive LOCKED; Drive, Race the Rookie AI and Enter are refused with the
  message; Watch the Rookie AI drives Hairpin Valley; Train the AI opens on it; Rookie Oval drives, the medal
  autopilot's run opens Hairpin Valley (finish state and panel, read at 1280 x 720: the headless window the panel
  gets depends on the tests run before it, and 520 px or narrower shows only "Hairpin Valley unlocked"), the tile is NEW, picking it clears NEW and Drive
  reads DRIVE, leaving the menu clears a NEW too. The career test opens Seaside Stunts first and checks its author run
  opens Forest Rally; the terminal tests check the new `status` row, the reset warning and that a reset keeps the
  medal-opened track. `tests/test_ai.gd`: the training screen's Race best races on Rookie Oval and, on locked Hairpin
  Valley, gives a note instead (Watch best still works there).
- **End to end** (`scenario=unlock`, 1280 x 720, 17 checks, 175 s with `gfx=low`): a new career shows 14 locked tiles;
  2 picks Hairpin Valley (its note, LOCKED); with the lock note on each of the 14 locked tracks the menu still fits
  without scrolling (the lowest button ends at 718 px; the note is 66 px high, above the stats); Enter and a click on
  Race the Rookie AI are refused with the message; Watch the Rookie AI (clicked) drives Hairpin Valley, Train the AI
  (clicked) opens there; a slow autopilot (`Autopilot.basic`, 40 m/s at most) takes bronze on Rookie Oval in 2:49.750
  (bronze 3:03): the finish panel says Hairpin Valley unlocked; back on the menu it is NEW and Ramp Rally locked;
  2 picks it (NEW gone), Enter drives it; the save file holds `tracks_open: ["hairpin-valley"]`. `scenario=economy`
  now also checks that its Elite gold opened Hairpin Valley and, after opening tracks 3-12 itself, that the Seaside
  Stunts run opened Forest Rally (the menu: Forest Rally NEW, the last two locked). The other scenarios open every
  track first (`unlock tracks`). Screenshots: `docs/screenshots/menu.png` and `finish.png` (from `economy`, new: the
  NEW tile, the locked tiles and the unlock line; the five reworked tracks' minimaps are current), `locked.png`
  (from `unlock`) and `terminal.png` again (from `terminal` with `gfx=high`: `status` now ends with the Tracks row,
  "1 of 15 open; next: Hairpin Valley (bronze on Rookie Oval)", and the tiles behind it are locked).

## How v6.7.0 (the terminal) was verified

- **Commands** (`tests/test_game.gd` "the terminal's commands", on its own save file): the table (10 commands, each
  with help, usage and a method), an empty line, `help` and `help money`, an unknown command (`mony 5000`: "Did you
  mean money?"; `xyzzy`: no guess), money and points up, down (stopping at 0 and saying so), `set`, any case,
  commas / sign / `$` / `_`, the largest amount (1,000,000,000 at a time), 14 bad amounts (letters, decimals, two
  numbers, none, below 0 for `set`, too big, `5k`, full-width digits) each giving one error and changing nothing;
  `car` (the list), `car Vortex`, again, `car bus`, two cars, `car all`; `buy` short of money (it says how much and
  what to type), bought, again, unknown; `unlock` / `unlock everything` (errors), `unlock tracks`, `unlock cars`,
  `unlock all` (in the file, version 4), again; `status` with a gold and a bronze on Rookie Oval (`medal_counts`);
  `reset career` (only warns), bad `reset` / `confirm` lines, `Reset Career CONFIRM` (records stay); `clear`, `exit`;
  15 Tab cases; 18 odd lines (control characters, BBCode, 300 characters, emoji) answered with known line kinds.
- **The save file** (`tests/test_sim.gd`): a v6.6 file has the flag off; `unlock_tracks` turns it on once, it is in
  the file's career (still version 4) and read back; off removes the key; five junk values read as off;
  `reset_career` gives $0, 0 points, only the Racer, the flag off and nothing paid (a gold pays $1,600 again on
  Rookie Oval) while the record, settings and AI network stay.
- **The screen** (`tests/test_ui.gd`, key events pushed through the viewport to the focused input): typing and
  Enter run a line, the log shows it and the result (a table row too), `changed` is emitted, the history keeps a
  repeated line once and the last 50, Up / Down step through it and back to the draft, Tab completes and lists
  several matches, `` ` `` and Esc type nothing into the input, Backquote / Escape / PadB / PadStart close it and release
  the focus, other keys don't, a command can clear or close it, Ctrl+L clears, the log keeps the last 300 lines, no
  commands is not an error. On the menu: `` ` `` opens it; O, H, C, 3, Enter and → typed into it never reach the menu; Esc
  closes it; `` ` `` over Settings opens and closes it; the pad's A on the Terminal row opens it, B closes it and then
  Settings; `` ` `` on the Controls screen does nothing; `exit` + the Enter that ran it closes it without driving (that
  frame's keys are dropped: `MainMenu._terminal_was_open`), the next Enter drives; leaving the menu closes it.
  `MenuInput.key_code(KEY_QUOTELEFT)` is "Backquote" and `menu_terminal` maps the key.
- **In the app** (`tests/test_game.gd` "the app: the terminal"): the app hands over the commands; money, points,
  `car dune`, `buy kestrel`, `reset career confirm` (the picked Dune shows LOCKED) and `unlock all` change the
  menu's header and Drive button at once; `` ` `` over Settings and the Terminal row; `exit` + Enter stays on the menu; in a
  race `` ` `` (and its action) changes nothing: 10 more race steps, no terminal; back on the menu it is closed.
- **End to end** (`scenario=terminal`, 1280 x 720, 34 checks: 69 s with `gfx=low`, 478 s with `gfx=high`): from a new career, `` ` `` opens it with the input focused;
  typed key events run help, money 25000 (header and save file at once), points 200, a typo, a bad number,
  status; the typed letters and Enters never reached the menu; Up / Down and Tab; `` ` `` closes and reopens it with
  nothing typed; the money buys the Kestrel on the car picker; Settings fits 1280 x 720 without scrolling and shows
  the Terminal row; its Open button (clicked) opens the terminal over Settings, where buy dune is $3,000 short,
  money 3000 and buy dune buy it; Esc back to Settings, `` ` `` opens and closes it there; the pad opens it from the row
  (A) and closes it (B); exit + Enter doesn't drive; Drive with the Dune: `` ` `` in the race does nothing (the race steps
  on). Screenshots: the terminal over the menu (`docs/screenshots/terminal.png`), Settings with the Terminal row,
  the terminal over Settings.
- **Fit** (real frames under xvfb): the Settings content is 668 px in a 720 px window at 1280 x 720 (it was 748 with
  the old spacing: Settings now uses its compact spacing up to 760 px high and a tighter one up to 640), 596 in 600 at
  1024 x 600, 748 in 768 at 1366 x 768; the terminal's panel is 558 px at 1280 x 720 and 474 at 1024 x 600 (its log
  is half the window's height, 140-460 px); the Controls screen, with its Terminal row and tip, is 700 px in 720 at
  1280 x 720 (a longer first wording was 735 and scrolled).

## How v6.6.0 (more forgiving corners) was verified

- **Which corners** (`tools/corners.gd --sweep` on v6.5.0's tracks and medal file: every corner under 45 m, driven by
  the medal autopilot with all 50 settings of the sweep and all six cars, 300 runs a track): the hairpins were hit on
  65-96 % of laps (Technical Trial's 92-93 %, 17 steps of wall contact a lap each; Canyon Run's 96 %, 20 steps;
  Mountain Pass's 65-66 %), Hairpin Valley's 16 m switchbacks on 87-100 % and its snowy ridge corner on 99 % (29.5
  steps, 2.5 hits a lap, the worst corner of all). The author runs' lowest speed in the hairpins was down to 1-2 km/h
  (Technical Trial, Grand Marathon: the autopilot stops against the wall).
- **Design** (`tools/gen_tracks.gd`, all design rules pass; `tools/corners.gd` measures the tightest radius over ±2
  samples, so a 24 m turn reads 23.8 m):

  | Track | Corner | Radius | Road | Length |
  | --- | --- | --- | --- | --- |
  | Hairpin Valley | 6 switchback corners / 2 hairpins / ridge corner | 16.0 → 21.8-22.0 / 16.9 → 23.8 / 39.4 → 38.6 m (banked 12°) | 13 → 15 m | 2,417 → 2,435 m a lap |
  | Technical Trial | 2 hairpins | 15.0 → 23.8 m | 14 → 16 m | 2,591 → 2,699 m a lap |
  | Grand Marathon | hairpin / the two rights | 15.9 → 23.8 / 19.8 → 23.9 m | 15 → 17 m | 7,468 → 7,491 m |
  | Mountain Pass | 3 hairpins up / 3 down | 17.9 → 23.8 / 19.0 → 24.8 m | 13 → 15 m | 4,783 → 4,925 m |
  | Canyon Run | hairpin / its two rights / turnaround | 13.0 → 23.7 / 20.0 → 25.8 / 21.9 → 27.8 m | 10 → 13 m (turnaround 10 → 12 m) | 2,853 → 2,896 m a lap |

  Hairpin Valley's ridge corner was first made 55 m: the sweep then showed 63 steps of wall contact a lap there
  instead of 29.5 (a faster arrival, the same slide on the snow, all hits on the outer wall). Variants measured with
  the Racer, Thunder and Vortex over the 50 settings (steps / hits a lap in that corner): v6.5 40 m 40.9 / 3.26, 55 m
  86.9 / 6.01, 55 m banked 8° 24.6 / 2.21, 40 m on 15 m 24.6 / 2.19, 40 m banked 8° 7.3 / 1.04, **40 m banked 12°
  5.4 / 0.85** (kept). Banking the snowy switchback pair 10° only took 18.7 to 13.4 there and was not kept.
- **After** (the same sweep on the new tracks and medal file; wall-contact steps per lap, the share of laps that hit,
  the lowest speed averaged over the runs):

  | Corner | Steps a lap | Laps hit | Lowest speed |
  | --- | --- | --- | --- |
  | Hairpin Valley switchbacks (asphalt) | 10.3-15.1 → 6.1-9.6 | 87-88 % → 77-80 % | 23-27 → 34-40 km/h |
  | Hairpin Valley switchbacks (snow) | 8.9-11.8 → 7.9-9.8 | 99-100 % → 98-99 % | 11-13 → 17-19 km/h |
  | Hairpin Valley ridge corner (snow) | 29.5 → 4.6 | 99 % → 71 % | 43 → 61 km/h |
  | Hairpin Valley hairpins | 17.2-17.3 → 11.6-11.9 | 93-94 % → 90-91 % | 17 → 27 km/h |
  | Technical Trial hairpins | 16.8-17.4 → 10.8-11.2 | 92-93 % → 88-89 % | 14 → 27 km/h |
  | Grand Marathon hairpin / rights | 13.3 → 8.5 / 8.4-9.9 → 6.2-8.5 | 91 → 87 % / 80-82 → 76-77 % | 17 → 28 / 33 → 38-40 km/h |
  | Mountain Pass hairpins | 9.0-9.7 → 6.8-7.6 | 65-66 % → 59 % | 48-51 → 60-63 km/h |
  | Canyon Run hairpin / its rights | 20.3 → 11.2 / 10.8-11.5 → 6.7-7.3 | 96 → 91 % / 78-79 → 68-70 % | 13 → 30 / 45-46 → 57-59 km/h |
  | Canyon Run turnaround (dirt) | 5.8-6.0 → 4.8-5.1 | 85 % → 79-80 % | 40 → 48-49 km/h |

  The whole track, steps of wall contact a lap over the sweep: Hairpin Valley 140.0 → 82.2, Technical Trial 104.2 →
  92.4, Grand Marathon 146.6 → 137.7, Mountain Pass 147.9 → 133.0, Canyon Run 159.1 → 139.2; the corners left alone
  read the same before and after (within 0.5 a lap). The author runs alone (one setting each, the fastest) are a
  noisier measure: their wall contact a lap (mean of six cars) went 82.7 → 33.6 on Hairpin Valley, 52.6 → 38.8 on
  Technical Trial, 86.7 → 79.8 on Grand Marathon and 110.3 → 88.3 on Mountain Pass, but 46.3 → 97.9 on Canyon Run,
  where the fastest settings are now more aggressive ones that lean on the S-bends and canyon walls left alone (in
  the reworked corners themselves they hit about as before). Scratch numbers, per corner and car: `tools/corners.gd
  --tracks=... --max-r=45 [--sweep]`, with `--tracks-json=` / `--medals=` pointing at v6.5's files for the before.
- **The other ten tracks are bit for bit v6.5.0**: their `data/tracks.json` entries, medal entries and opponents are
  identical (`tests/test_sim.gd` hashes each track's `tools/gen_tracks.gd` text and its medal entry against v6.5's,
  `V65_KEPT`), and so are their signatures.
- **Signatures and saves**: all five reworked tracks changed their sample count and length, so their signatures
  changed (`V65_SIGS` → `SIGS`; Hairpin Valley `1209:2417|snow480-812` → `1218:2435|snow492-815`). A test loads a
  v6.5 save (file version 4) holding a Hairpin Valley record, best score and ghost with the old signature, a Rookie
  Oval record and a career that was paid bronze, silver, gold and the Rookie there: the three Hairpin Valley entries
  move to the archive, Rookie Oval's stays, loading pays nothing, the paid list is kept, a slower time than the
  archived one is a new best, claiming gold and the Rookie again pays $0, author and the Amateur pay just those two,
  and the file on disk is version 4 with the archive.
- **Medal times** (`tools/medals.gd --update --tracks=<the five> --jobs=3`, 976 s, then Hairpin Valley again after
  its ridge corner, 236 s; the other 60 entries untouched): author times move by -10.65 s (Drifter, Hairpin Valley)
  to +5.22 s (Racer, Technical Trial, 108 m longer a lap); see the README for the table.
- **AI opponents** (`tools/opponents.gd --train --tracks=<the five>`: 30 networks, FleetSim on 3 threads, 38-124 s each;
  every one beat its gold time at generation 80; flat out 0.85 (Vortex, Hairpin Valley: it rides the walls) to 1.01
  (Kestrel, Grand Marathon) × the author time. Levels (330 s): Rookie 1.587-1.619, Amateur 1.387-1.414, Pro
  1.237-1.265, Expert 1.120-1.143, Elite 0.989-1.015 × the author time. `--check` re-ran all 450 stored races
  (474 s) and every time was reproduced to the millisecond.
- **Browser parity kept**: `Tracks.build_web(id)` reads the browser's own track data (`web/src/tracks/trackData.js`),
  so the web comparisons in `tests/test_sim.gd` and `tests/test_ai.gd` and the parity tools drive the five tracks as
  the browser has them (the v6.5 layouts, all asphalt); the test checks that `build_web` gives exactly the v6.5
  layout for them and `build_asphalt` for the other ten.
- **Tests**: the headless suite, 642 checks, all pass (`tests/run_tests.gd -- sim ui world game ai`, 328 s). New:
  "the reworked corners (v6.6)" (for each of the five, measured on the built track: the tightest corner and the
  tightest hairpin, a turn of 150° or more under 40 m, at least 21.5 / 23.5 m on Hairpin Valley and 23.5 / 23.5 m on
  the others, the hairpin road at least 15 / 16 / 17 / 15 / 13 m, all wider and rounder than the browser's layout, as
  many hairpins as before, the same surface stretches within 5 % of their length) and the v6.5 save above;
  rewritten: "the tracks: design rules and versions" (the ten kept tracks' text and medal hashes, the five's new
  signatures and medal entries, `build_web`). The web comparisons now run on `Tracks.build_web` and still match the
  browser to the millisecond on all 12. End to end, `scenario=races` (Rookie Oval, Hairpin Valley, Seaside Stunts,
  Mountain Pass, Canyon Run, Summit Rush, every car: through the menu to the author time, record, ghost, replay): 648
  checks pass (989 s); `scenario=surfaces` (it drives Hairpin Valley's snow) 13 and `scenario=menu` (the 15
  tiles at 1280 x 720 without scrolling) 28 pass.
- **Screenshots** (software rendering, the same free camera before and after: v6.5.0 built from `git archive` of
  commit ccf2f97): Technical Trial's first hairpin (in the README), Mountain Pass's first hairpin up and Hairpin
  Valley's second switchback corner; top-down overlays of all five layouts.

## How v6.5.0 (money, points and AI opponents) was verified

- **Reward table and rules** (`tests/test_sim.gd` "money and points"): nine rewards, each harder medal or AI level
  pays more money and points, every track pays more than the one before (gold: $800 / 40 pts on Rookie Oval, $1,920 /
  96 on Summit Rush); a gold plus a Pro win on track 1 pays bronze, silver, gold, Rookie, Amateur and Pro ($2,900,
  105 pts); paid once per track, car and reward (the same run again pays $0 and lists what was paid before; another
  car or track pays on its own; read back from the file); the shop ($9,000 can't buy the $10,000 Kestrel and takes
  nothing; $10,000 can; owned and unknown cars refused; `give_car`; money and points never below 0).
- **Save migration**: a version 3 file with a Racer gold and a Kestrel bronze on Rookie Oval (plus records that must
  not pay: no medal, an older track version, other physics, an unknown car or track) gets $1,900 and 80 pts once,
  owns only the Racer (its picked Vortex stays picked, locked), a one-time welcome note, and is version 4 on disk; a
  second load pays nothing; version 2 and version 1 files the same way (a v6.2 Ramp Rally record is archived, so not
  paid); four kinds of junk in the career section read as a new career, a hand-edited one is cleaned.
- **Prices** (`Economy.career()`, a test): a player who wins gold and beats the Expert everywhere with the Racer
  has $4,000 / $8,400 / $13,200 after one / two / three tracks (the $10,000 Kestrel after three), $92,400 after 14 and
  $102,000 after 15, against $94,000 for all five cars; silver and the Pro everywhere buy the Kestrel after five
  tracks ($12,600) and make $53,550 in all; author and the Elite everywhere make $173,400; bronze and the Rookie
  everywhere $12,750 (one car).
- **The opponents' networks** (`tools/opponents.gd --train`, FleetSim, 3 threads, 4,119 s for the 90): every one beat
  the gold medal at its first check (generation 80, 25-87 s each); flat out their races take 0.83 (Vortex, Hairpin
  Valley: it rides the walls on the snow) to 1.04 (Drifter, Night Highway) × the author time.
- **The levels** (`tools/opponents.gd`, 848 s on 3 threads): each level's race against the author time, over the 90
  tracks and cars: Rookie 1.581-1.618, Amateur 1.384-1.416, Pro 1.235-1.265, Expert 1.121-1.143, Elite 0.988-1.037
  (the network flat out on 39, capped on 51). Each level is at least 1.082 × the next one's time; every Elite is at
  most 0.974 × the gold time; every Rookie at least 1.050 × the bronze time. `tools/opponents.gd --check` re-ran all
  450 stored races (491 s) and every time reproduced to the millisecond. `tests/test_ai.gd` checks the ordering and
  bounds on all 90 and re-runs 11 races (all five Racer levels on Rookie Oval and one level of every car elsewhere).
  The first calibration stored caps made by `snappedf`, which do not survive the JSON file (25.900000000000002 reads
  back as 25.9) and changed one of the 11 re-run races by 0.55 s: caps are k / 100.0 now and everything was
  recalibrated.
- **A beginner can beat the Rookie**: the medal autopilot cornering at 10 m/s² (about 1 g; the medal sweep uses
  14-40) without nitro beats the Rookie on all 90 tracks and cars (its median race is 1.17 × the
  author time; the closest is the Vortex on Banked Speedway, 0.981 × the Rookie's time). No human was measured.
- **In the game** (`tests/test_game.gd` "the app: money, points ..."): a new save: $0, Racer only; a locked car's
  Drive with $0 says how much is missing; with $12,500 BUY asks, Cancel buys nothing, yes buys it ($2,500 left) and
  Drive then drives it; Race the Rookie AI on Seaside Stunts with the author run pays bronze to author and the Rookie
  ($6,300, 326 pts), and the Rookie's car, raced on by the play mode after the finish, ends on its stored time
  1:50.200 to the millisecond; a slower run loses to the Elite (its stored 1:08.100) and is paid nothing new; a
  version 3 save is paid with a message, once. `tests/test_ui.gd`: the header, locked cards and prices, BUY / LOCKED,
  the opponent chips and their status line, the payout block (and "nothing new" / "no medal and no win") at 1280 x 720
  and 800 x 600.
- **End to end** (`economy` scenario, `gfx=high`): from a new career, click the Elite chip, Race the Elite AI on
  Rookie Oval (the author autopilot starting a second late: the AI's car leads, then loses; 2:03.067, gold) and the
  Expert on Seaside Stunts (author time): $16,520 and 698 pts on the menu; the Vortex says $13,480 is missing; the
  Kestrel is bought with Enter, Enter and driven. The other scenarios start by owning every car and picking My AI.

## How v6.4.0 (three new tracks) was verified

- **Design** (`tools/gen_tracks.gd`, turtle programs after Seaside Stunts; the design-rule report):

  | Track | Type | Length | Min. radius | Heights | Jumps | Banking | Checkpoints | Surfaces |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | 13 Forest Rally (★★★, autumn) | 3 laps | 2.54 km a lap | 43.4 m | 2.0-7.9 m | 2 (3.9, 5.5 m) | ≤ 12° | 5 (gaps 422-428 m) | dirt 88 % |
  | 14 Northern Lights (★★★★, arctic) | 3 laps | 2.83 km a lap | 57.7 m | 4.0-10.0 m | 1 (4.8 m) | ≤ 24° | 6 (394-414 m) | snow 79 % |
  | 15 Summit Rush (★★★★★, highland) | sprint | 4.38 km | 39.2 m | 1.5-18.0 m | 2 (4.4, 5.0 m) | ≤ 16° | 10 (356-440 m) | dirt 30 %, snow 21 % |

  The old tracks' tightest corners are 13-19 m; Summit Rush's two "hairpins" (the report's word for 150° turns) are
  40 m switchbacks. `tests/test_sim.gd` "the tracks of v6.4" runs the design rules on all 15 designs (and that
  `data/tracks.json` is what they make), checks the menu order, difficulty, surfaces, race type and own themes.
- **The 12 old tracks are untouched**: their `tracks.json` text hashes to v6.3's whole file, their signatures are
  pinned (`SIGS`), their 72 medal entries hash as before (`V63_MEDALS_SHA`), the web game's test-autopilot times
  still match to the millisecond on all 12, and the medal sweep (`--update --tracks=forest-rally,northern-lights,
  summit-rush --jobs=3`, 588 s) only added entries.
- **Medal times** (author; gold / silver / bronze = 1.06 / 1.2 / 1.5 × as everywhere):

  | Track | Racer | Kestrel | Thunder | Drifter | Dune | Vortex |
  | --- | --- | --- | --- | --- | --- | --- |
  | Forest Rally | 3:23.333 | 3:18.617 | 3:38.783 | 3:15.850 | 3:03.350 | 3:34.967 |
  | Northern Lights | 3:08.283 | 3:06.617 | 3:21.617 | 3:01.700 | 3:02.750 | 3:25.667 |
  | Summit Rush | 1:47.417 | 1:46.933 | 1:53.850 | 1:47.550 | 1:42.067 | 1:49.950 |

  The Dune is quickest on Forest Rally and Summit Rush (it keeps the most grip on dirt and snow) and the Drifter on
  Northern Lights (1.05 s ahead of the Dune: it holds the long slides); the Thunder and Vortex are the slowest on all
  three. The
  author runs' wall steps: Forest Rally 0-764 (Thunder 685, Vortex 764), Northern Lights 76-1,801 (see Known
  limitations), Summit Rush 54-484. Every car finishes all three with the test autopilot (the existing test, now on
  15 tracks); the e2e `races` scenario drives Summit Rush with all six cars through the menu and finishes on the
  author time.
- **Walls still cost time** (test): one Racer lap, medal autopilot against never braking: Forest Rally 1:11.567
  against 1:12.867, Northern Lights 1:09.250 against 1:09.683, Summit Rush 1:50.967 against 1:56.283 (the best of
  the sweep's 18-40 m/s² settings for these three).
- **AI** (`tools/headless_train.gd`, FleetSim, 80 Racer networks, seed 1, 3 threads): on each new track alone the
  first finish comes in generation 0 with walls ride and with walls crash (crash, by generation 4: Forest Rally
  1:39.950 a lap, Northern Lights 1:37.867, Summit Rush 2:38.100; Mountain Pass for comparison: first finish in
  generation 5). All three together, walls ride, 60 generations (118 s): 1:07.150 / 1:03.733 a lap and 1:45.750.
  `tests/test_ai.gd` checks the crash run's first finish (generation 0 on each, 10 at most).
- **Menu**: `ui/main_menu.gd` makes rows as full as it can (at most six a row from 1200 px, four from 760, three
  below; 15 tiles: three rows of five), with 40 px maps and tighter tiles when three rows meet a short window
  (≤ 800 px) 1200 px or wider. `tests/test_ui.gd` "menu track grid" lays it out at 8 window sizes (1920x1080 to
  640x720): 15 tiles inside the window and apart, every tile and car card on screen from 1280 x 720 up; the menu
  keys and pad tests now cover tracks 13-15 (= then →; down through three rows). The e2e `menu` scenario checks
  with real frames that 1280 x 720 does not scroll. Below about 480 px wide the menu's content is wider than the
  window, as it was with 12 tracks.
- **Looks** (screenshots through software rendering; `tests/test_world.gd`): the arctic sky's northern lights (only
  that theme has them), Forest Rally's woods (737 trees and rocks within 50 m of the road against Rookie Oval's 278),
  Summit Rush's snowy land beside the snowy road (none beside the asphalt start) with the snowy pines only there.
  Frame cost at high (chase camera): Forest Rally 1.57 M primitives and 153 draw calls, against Lighthouse Bay 1.41 M
  / 96 and Canyon Run 1.12 M / 135. The snow spray got its own blue-grey colour and bigger puffs: seen on Summit
  Rush's snow behind a sliding Dune, where before it was invisible.

## How v6.3.0 (road surfaces) was verified

- **Design**: one table, `sim/surfaces.gd` `DEFS` (asphalt, dirt, packed snow): CarSpec-independent physics columns
  (`grip` default share, `roll` × rolling resistance, `stiffness` × tyre cornering stiffness, `esc` share of the
  stability control) and look columns. Each car's share is a `CarSpec` field (`dirt_grip`, new `snow_grip`;
  `surface_grip` holds all of them in table order). A track definition's `"surfaces"` is a list of
  `[id, from, to]` in fractional control-point indices (from the turtle's `.surface()`); `TrackBuilder` makes a
  surface per sample and blend weights box-filtered over ±`Surfaces.BLEND` samples (about 10 m). `sim/car.gd`
  reads the weights at the front and rear axle (`_surface_mix`), scales each axle's grip, stiffness and rolling
  resistance and the ESC moment, and skips all of it when both axles are on pure asphalt (`_env_loose`), so asphalt
  runs the old code path. FleetSim does the same (`native/src/car_sim.cpp`, "trackrush-native 3").
- **Asphalt unchanged**: medal-autopilot runs (nitro on, 2,400 steps) with all six cars on all 12 tracks hashed every
  50 steps: the 48 runs on the eight all-asphalt tracks are identical to v6.2's (only the four surface tracks
  differ). The browser parity scripts, run on the all-asphalt versions (`Tracks.build_asphalt`), give exactly the
  v6.0-6.2 results: car lockstep 39,906 of 46,200 steps bit-identical, races and points 71 of 72 runs, ghosts 12
  of 12, collision 1 number in 66,216 by 1 ulp, and the AI report (`check_ai.gd`) identical line for line to the one
  from the v6.2.0 checkout (0 of 683,352 inputs and 0 of 75,928 controls different).
- **FleetSim on dirt and snow**: `FleetSim.debug_drive` drives one car with a control tape; `tests/test_ai.gd`
  compares every step (position, yaw, velocity, speed, yaw rate, progress, slip) with `sim/car.gd` for all six cars
  from several starts on Ramp Rally, Hairpin Valley and Mountain Pass: bit-identical (about 23,000 steps on loose
  ground). The network's 18 inputs are unchanged (`SENSOR_VERSION` 2).
- **What the surfaces do** (`tools/car_stats.gd --surface=`; README "Road surfaces"): e.g. 100-0 km/h for the Racer
  30.7 / 34.0 / 43.0 m on asphalt / dirt / snow, the Dune 31.7 / 31.2 / 33.8, the Vortex 28.8 / 42.4 / 55.2; a 30 m
  circle on dirt 1.63 g for the Dune against 0.89 g for the Vortex (both about 1.7 g on asphalt). `tests/test_sim.gd`
  "road surfaces" checks the table, the four tracks and their blend, that the Racer on Ramp Rally drives bit for bit
  as on the all-asphalt version until its front axle reaches the dirt (9.9 s), the change onto dirt at 90 km/h (the
  front grip share goes from 1 to 0.70 over 10.4 m, at most 0.012 a step), braking and cornering per car.
- **Tuning**: with the first shares (Drifter 0.9 on dirt, Vortex 0.6) a sweep made the Drifter the quickest car on
  Ramp Rally (2:58.4 against the Dune's 3:00.1); the Drifter went to 0.74 / 0.6 and the Vortex to 0.55 / 0.42, so the
  Dune is the dirt and snow car: quickest of all on Ramp Rally and Hairpin Valley, second on Canyon Run, and it loses
  the least time on every changed track (0.8-11.1 s, the Vortex 8.8-36.6 s).
- **Medal times**: `tools/medals.gd --update --tracks=hairpin-valley,ramp-rally,mountain-pass,canyon-run --jobs=3`
  (1,023 s); the other 48 entries of `data/medals.json` are untouched. The medal and test autopilots take the car's
  spec and scale their planned corner speed and braking by its grip share on each sample (only on tracks with
  surfaces). Author times before (all asphalt) and after:

  | Track | Racer | Kestrel | Thunder | Drifter | Dune | Vortex |
  | --- | --- | --- | --- | --- | --- | --- |
  | Hairpin Valley | 3:46.583 → 4:07.233 | 3:44.050 → 4:02.267 | 3:48.433 → 4:18.500 | 3:46.833 → 4:06.783 | 3:47.233 → 3:58.333 | 3:31.383 → 4:07.933 |
  | Ramp Rally | 2:52.417 → 3:05.633 | 2:55.183 → 3:04.500 | 2:53.517 → 3:12.917 | 2:52.083 → 3:03.983 | 2:58.367 → 3:00.133 | 2:36.750 → 3:05.700 |
  | Mountain Pass | 1:47.683 → 1:53.267 | 1:48.250 → 1:52.333 | 1:49.150 → 1:56.517 | 1:48.500 → 1:53.267 | 1:51.083 → 1:52.683 | 1:40.433 → 1:49.233 |
  | Canyon Run | 4:15.450 → 4:24.067 | 4:11.933 → 4:19.883 | 4:25.167 → 4:31.817 | 4:12.150 → 4:21.400 | 4:17.733 → 4:18.500 | 4:02.100 → 4:16.333 |

- **Walls still cost time**: one Racer lap with the medal autopilot against the same autopilot never braking:
  Hairpin Valley 1:24.817 against 1:25.367, Ramp Rally 1:07.267 / 1:09.833, Mountain Pass 1:54.667 / 1:56.350,
  Canyon Run 1:29.933 / 1:37.183 (a test). On Hairpin Valley's snow the gap is small (0.55 s a lap, 4.6 s on the
  asphalt version): see Known limitations.
- **AI on dirt and snow** (`tools/headless_train.gd`, FleetSim, 80 cars): Ramp Rally (47 % dirt) with the Racer,
  walls crash: first finish in generation 1, best lap 1:21.283 by generation 7; walls ride: a finish in generation 0,
  1:10.033 by generation 6. Hairpin Valley (snow) with the Dune, walls crash: first finish in generation 23 (2:19.417).
- **Track versions** (`SaveData.VERSION` 3): records and scores get `sig` (`Tracks.signature()`: "count:length", plus
  "|dirt168-730,..." for a track with surfaces); version 2 files are tagged with the v6.2 signatures
  (`Tracks.LEGACY_SIGS`) on load; any entry (records, scores, ghosts) whose signature is not the track's current one
  moves to `archive[section][track][car][sig]` (`SaveData.get_archived`). The AI's best times carry `sig` too and the
  menu ignores stale ones (`AiLink._current_times`). Tests: a version 2 save's records, scores and ghosts on Ramp
  Rally move to the archive (by old signature) while Rookie Oval's stay; a slower run on the new Ramp Rally is a new
  best; a version 3 entry with a signature that no longer exists is archived, entries of unknown tracks are left alone.
- **Looks** (`tests/test_world.gd` "road surfaces", 7 checks; e2e `surfaces`, 13 checks): the road of a surface track
  is one mesh with a `ShaderMaterial` (`road_surface.gdshader`: vertex colour G / B = dirt / snow weight, a ragged
  border from noise, the asphalt texture elsewhere), all-asphalt tracks keep their `StandardMaterial3D`; no lane
  lines or kerbs where the road is loose; barrier vertices along dirt get dusty feet, along snow white tops; dust and
  snow pools (`CarEffects.Spray`, one MultiMesh each, made the first time a car touches loose ground) scale with the
  quality (`spark_share` 1 / 0.65 / 0.3); tyre marks carry the surface weights (`skid.gdshader` mixes the colours);
  `ChaseCamera.ground_rumble` (0 on asphalt, off with `reduce_motion`). Screenshots (software rendering only): a Dune
  throwing dust on Ramp Rally's dirt, the asphalt / dirt border ahead, a Racer sliding on Hairpin Valley's snow, the
  menu's surface line.

## How v6.2.0 (AI training with every car) was verified

- **Sensors** (`ai/sensors.gd`): the speed input and the corner-speed cap now use the car's own `CarSpec.max_speed`
  instead of the Racer's 77 m/s for every car. The Racer's is 77, so its inputs are the same bits as before and
  `SENSOR_VERSION` stays 2: `tools/parity/check_ai.gd` against the browser (`ai_runs.mjs` with the browser's
  network) still finds 0 of 683,352 inputs and 0 of 75,928 controls different, and its whole report (the free runs
  included) is identical to v6.1.0's; old Racer networks load and drive as before. Why: with 77 for every car the
  Vortex's speed input reaches 1.16 at its top speed (89.3 m/s) and its corner margins go negative on every
  straight above 277 km/h (the network reads "brake" at full speed), while the Dune's never passes 0.80. `CORNER_GRIP` (14.5 m/s²) stays shared: the cars' grip is within 13 % of the Racer's, so a
  corner speed moves by 6 % at most, under 0.05 of an input's range.
- **FleetSim** (`native/`, version "trackrush-native 2"): `set_spec` already took the whole spec; the sensors now read
  its `max_speed` and `set_rules` no longer takes `speed_scale`. `get_spec()` returns the spec as set: the test
  compares all 89 fields with every car's `CarSpec`. Each of the five new cars runs a lockstep test against the
  GDScript trainer (Kestrel on Hairpin Valley, Thunder on Banked Speedway, Drifter on Ramp Rally, Vortex on
  Seaside Stunts with walls crash, the Dune on Rookie Oval with walls ride): every car's state, inputs, fitness,
  reasons, best times and history identical. That found one old difference (GDScript keeps a `{lap: null, finish:
  null}` best-times entry once any car passes a gate, as the browser does; FleetSim only on a lap or finish, which
  no Racer test had hit): FleetSim now reports `get_any_gate()` and the trainer merges it.
- **Training with every car** (`tools/headless_train.gd --car <id>`, FleetSim, 4 threads, Rookie Oval, walls crash,
  40 cars, 20 generations, seed 1; best fitness of generation 0 and 19, first finish, best lap, speed):

  | Car | Gen 0 → 19 best | First finish | Best lap | × real time |
  | --- | --- | --- | --- | --- |
  | Racer | 336 → 1672 | gen 3 | 0:45.417 | 738× |
  | Kestrel | 340 → 1671 | gen 2 | 0:45.433 | 703× |
  | Thunder | 333 → 1644 | gen 5 | 0:48.250 | 800× |
  | Drifter | 340 → 1651 | gen 2 | 0:47.517 | 969× |
  | Dune | 335 → 1655 | gen 1 | 0:47.100 | 811× |
  | Vortex | 338 → 1725 | gen 6 | 0:40.833 | 815× |

  `tests/test_ai.gd` repeats a shorter run (12 generations, seed 4) for the five other cars: the average fitness
  rises by 330-480 and every car finishes. Each network driving each other car on the same track (the network
  alone, no mutation): 14 of the 30 pairs finish the lap, mostly slower than that car's own network; the rest
  crash out early (e.g. the Racer's network in the Thunder and the Vortex).
- **Save file** (`SaveData.VERSION` 2): `networks: {car: {"best": file}}`; a version 1 file's `network` moves to
  `networks.racer.best` on load (tests: migration, per-car round trip, junk, an old key next to a newer slot).
- **Game and screens**: `tests/test_game.gd` (the menu's AI block per car, the "no network" message, loading a Racer
  file into the Dune with its note, Watch the AI and the AI ghost driving the Dune, the Racer's network untouched);
  `tests/test_ai.gd` "training screen: cars" (the tiles, a Thunder session autosaving into the Thunder's slot, the
  badges, Watch / Race best with the session's car, switching car with and without asking, Save it then switch,
  a Racer file loaded into a Thunder session with its note); the new end-to-end scenario `cars` clicks through it
  all in the real game (train the Dune or Vortex at Max until it autosaves, Watch best, switch car, back on the
  menu Watch the AI and Race the AI ghost with it).

## How v6.1.0 (two more cars, detailed models) was verified

- **Physics**: the Racer still drives two autopilot minutes within 3.1e-11 of the browser game (`tests/test_sim.gd`);
  all six cars finish all 12 tracks with the test autopilot without touching a wall; the stats in `sim/cars.gd` are
  what `tools/car_stats.gd --check` measures; wall shots, NaN and lane-keeping checks run for every car.
- **Medal times**: a full `tools/medals.gd --jobs=3` sweep (2,029 s) for six cars; the 48 old entries in
  `data/medals.json` came out identical, 24 are new. The Vortex is the fastest car on all 12 tracks, the Dune the
  slowest.
- **Models** (`tests/test_world.gd`, 126 checks): one skinned mesh per car with its bones; wheels spin and steer, the
  steering wheel turns with the front wheels and the hands stay on it (within 2 mm) with the elbows joined; the
  head looks into the turn; the body rolls out of a left turn and the driver leans; braking dives the nose and
  lights the brake lights (and tilts the Vortex's flap); the wheels droop in the air and the body sinks and settles
  after a landing; the fist pump rises above the helmet and ends; headlights: 2 spotlights at High, 1 at Medium, a
  road decal at Low, none in daylight or on ghosts; Low models have under 0.6 × the triangles.
- **Draw cost** (`tests/visual/car_cost.gd`, one car in an empty world): the Racer at High went from 53 draw calls
  (19 + 34 shadow) and 10,592 visible triangles to 4 calls (2 + 2) and 17,180; at Low from 36 calls to 3 and
  6,772 visible triangles. The six cars: 3-4 calls and 15,900-19,000 visible triangles at High / Medium, 2-3 calls
  and 6,800-7,500 at Low. The 80-car AI fleet is unchanged (5 / 4 / 3 calls; 128,000 visible triangles).
- **Menu**: the car picker at 1280x720, 1920x1080, 1366x768, 1024x600, 900x700 and 700x900 (`tests/test_ui.gd`):
  six cards inside the window's width and apart; at 1280 and wider three a row, all on screen without scrolling.
- **Screenshots** (software rendering only): the six cars on a start grid, close-ups mid-corner, night at each
  quality, the menu; see README for the tools (`tests/visual/car_studio.gd`, `car_corner.gd`, `world_cars.gd`).

## Conventions

- **Coordinates** as in the browser game: x/z is the ground plane, y is up, forward = (sin yaw, 0, cos yaw),
  positive yaw change = left turn, positive steer = left. Godot's `rotation.y = yaw` maps a model's local +Z to that
  forward, exactly like Three.js, so models face +Z.
- **Fixed 60 Hz physics** everywhere, stepped by the modes with an accumulator (not `_physics_process`); the cars are
  drawn between the last two steps. The AI is trained and replayed at the same step, and ghosts are recorded and
  replayed on the race clock (physics steps since GO). Same inputs, same result.
- **`sim/` is the reference.** It is plain `RefCounted` / static GDScript with no nodes and no rendering, so tools,
  tests and threads can use it. It uses `float` (64-bit) and `PackedFloat64Array`, never `Vector2` / `Vector3`
  (32-bit), so its numbers match the browser's doubles; 32-bit floats only where the JS stores them (the network,
  sensor inputs, the built track arrays). Keep every tuning constant identical to the JS unless a feature changes it
  on purpose.
- **FleetSim mirrors the GDScript bit for bit**: `native/src/car_sim.cpp` = `sim/car.gd` + `sim/collision.gd`,
  `native/src/fleet_sim.cpp` = `ai/sensors.gd` + `ai/network.gd` + the rules in `ai/trainer.gd` and `sim/race.gd`.
  A change to one is a change to both, then rebuild the four libraries (`native/README.md`; fused multiply-adds
  stay off) and run `tests/test_ai.gd`, which compares them every step.
- **`JsMath`** (`sim/js_math.gd`): `JsMath.same(a, b)` compares JSON values like JS `===` (Godot's `==` raises an
  error on String against int); `JsMath.round` / `roundi` / `hypot2` / `to_fixed` reproduce V8's results.
- **Car-to-car contacts only in Race the field** (v6.13.0): `sim/car_contact.gd` is called by `sim/field_race.gd`
  alone. Drive, Race the AI, ghosts, training, FleetSim, the medal sweep and the opponents' calibration never touch
  it, so they stay bit for bit; keep it that way (or give FleetSim the same contacts first).
- **Static types everywhere** (typed GDScript is much faster, and `:=` on an untyped value is a parse error here).
  Tabs, snake_case, PascalCase classes; `class_name` only for types other folders need. After adding a
  `class_name`, run `godot --headless --path . --import` once before running scripts.
- **Data, not code**, where the next features will grow: the cars (`sim/cars.gd` `CARS`), medals (`sim/medals.gd`
  `ORDER` / `FACTORS`, stored with the times in `data/medals.json`; after changing a factor run
  `tools/medals.gd -- --factors`, no sweep; `WEB_FACTORS` are the browser's, for `--js`), the settings rows (`ui/settings_screen.gd`
  `ROWS`, with an `action` row type: v6.7.0's Terminal row), the terminal's commands (`game/terminal.gd` `COMMANDS`:
  name, usage, help, the method that runs it, the words Tab offers, `wipes` for commands that ask for `confirm`), the tracks (`data/tracks.json`), the themes (`world/themes.gd`),
  the road surfaces (`sim/surfaces.gd` `DEFS`: physics and look columns; FleetSim gets the physics columns from
  `Trainer.track_data`, the road shader has colour slots for table entries 1 and 2; v6.4.0 added the optional look
  column `spray`, the colour of what the tyres throw up; v6.10.0 the physics columns `brake`, `abs` and `wall`, which
  `Trainer.track_data` passes to FleetSim as `surf_brake` / `surf_abs` / `surf_wall`, and the look column `grime` in
  place of `rumble`), the rewards (`sim/economy.gd` `REWARDS`, `TRACK_STEP`), the
  car prices (`price` in `sim/cars.gd`; 0 = owned from the start), the AI levels (`sim/opponents.gd` `LEVELS`:
  id, name, pace, blurb; a new level also needs an `ai-<id>` reward and a `tools/opponents.gd` run) and the car
  upgrades (`sim/upgrades.gd` `PARTS`, `LEVEL_SHARE`, `FREE_CAR_BASE`; `MEASURED` is pasted from `tools/upgrades.gd`).
- **Road surfaces** are marked in the track designs (`tools/gen_tracks.gd`, turtle `.surface("dirt")` ...
  `.surface("asphalt")`; the design rules want stretches of 60 m or more and the start grid on asphalt). A track
  without them has no `"surfaces"` key and an empty `BuiltTrack.surf_w`, and every surface branch in `sim/car.gd`,
  the autopilots and FleetSim is skipped for it: keep it that way, so asphalt tracks stay bit-identical.
  `Tracks.build_asphalt(id)` is a track with its surfaces stripped. `Tracks.build_web(id)` (v6.6.0) is the track as
  the browser game has it: read from `web/src/tracks/trackData.js` when the layout differs from ours (the five tracks
  v6.6.0 reworked), `build_asphalt` otherwise; the parity tools (`tools/parity/`), `tests/test_ai.gd`'s sensor check
  and the web checks in `tests/test_sim.gd` use it, so they still compare like with like.
- **Track signatures**: `BuiltTrack.signature()` is "count:length" (the layout) plus "|dirt168-730,..." when the track
  has surfaces; `Tracks.signature(id)` caches it. Records, best scores and ghosts store it as `sig`; an entry whose
  `sig` is not the track's current one is archived when the save is loaded (`SaveData._archive_stale`).
  `Tracks.LEGACY_SIGS` holds the v6.2 signatures for untagged (version 2) entries: never change it. Changing a track
  (layout or surfaces) therefore retires its old records by itself; re-run `tools/medals.gd --update --tracks=<id>`.
  The layout part is the sample count and the length, so a change that keeps both (only a road width, a banking or
  a height) keeps the signature and the old records stay valid: v6.6.0's reworks all changed the length, and
  `tests/test_sim.gd` checks that each reworked track's signature differs from its v6.5 one (`V65_SIGS`). If you
  ever widen a road without changing its length, make the signature change some other way first.
- **Tracks are appended, never edited in passing** (v6.4.0): menu order is `data/tracks.json` order, the first 12
  are the browser's (as layouts: v6.6.0 reworked five of them on purpose, see its section), and `tests/test_sim.gd`
  pins every track's signature (`SIGS`), the text of the ten tracks v6.6.0 left alone (a SHA-256 of
  `tools/gen_tracks.gd`'s output for each) and their medal entries (`V65_KEPT`), what the reworked corners must be
  (`V66_REWORKED`) and their old signatures (`V65_SIGS`), and runs the design rules on all of them. A new track: its
  turtle program after the last one in `tools/gen_tracks.gd`, its theme's name in `THEMES` there, `tools/medals.gd
  --update --tracks=<id> --jobs=3`, then add its signature to `SIGS`.
- **Themes are data** (`world/themes.gd`; a theme lists every field, see its header). v6.4.0 added optional keys:
  `woods` ({count, spacing, peak, near, open}: a forest close to the road; without it the scenery is placed exactly
  as before), `sky.aurora` (+ `auroraColor`, `auroraEdge`: the northern lights, `world/shaders/sky.gdshader`) and
  `ground.roadSnow` ([full, gone] m: white land beside snowy road, `world/track_terrain.gd` `snow_at()`). Scenery
  species (`world/track_scenery.gd` `SPECIES`) can reuse another's shape in another colour (`build`, `leaf`) and grow
  only on or only off that snowy land (`onSnow`); new shapes: `birch`, `rockSnow`. A theme without the new keys
  draws as before.
- **Car models are made in code and are only looks**: nothing in `sim/` reads them. `world/car_shapes.gd` holds each
  car's shape as data (body sections, wheel places, wing, cockpit, suit and glove colours; the paint comes from
  `look` in `sim/cars.gd`), `world/car_build.gd` turns a shape into one skinned mesh per car and detail level
  (`CarKit` triangles tagged with a bone and a material kind, cached), and `world/car_model.gd` poses its 17 bones
  every frame from the car state (body, 4 uprights, 4 spinning wheels, steering wheel, driver torso / head / arms,
  rear flap). One opaque and one glass surface: 2-4 draw calls a car whatever the detail. To add a car: an entry in
  `sim/cars.gd` (spec, look, description; `tools/car_stats.gd`, `tools/medals.gd`), a shape in `car_shapes.gd`, then
  look at it with `tests/visual/car_studio.gd`.
- **Version tags** decide what old saved data still counts: `Car.PHYSICS_VERSION` (3: best times, ghosts, medals;
  unchanged by the surfaces, which only change tracks that have them), `ScoreState.SCORE_RULES` (1: best scores,
  medals), `Sensors.SENSOR_VERSION` (3 since v6.15.0: the nitro tank input and the nitro output; files of version 2 /
  none with 18 inputs and 2 outputs are widened with zero weights on load, `Trainer.parse_network_file`), `SaveData.VERSION` (3: track signatures on records and
  scores, the archive; `_migrate` upgrades versions 1 and 2; 4 (v6.5.0): the `career` section, started once from the
  medals held when it is missing; 5 (v6.11.0): `career.upgrades`, empty for older files), ghost format 3, the track signatures above, FleetSim's
  `version()` ("trackrush-native 5": v6.15.0's nitro for the AI (19 inputs, 3 outputs, the refill rule,
  `rules.nitro`); 4: v6.10.0's brakes, anti-lock limit and wall friction on loose ground; 3: road
  surfaces; 2 scaled the sensors by the spec's `max_speed`). Bump the right one when old data should stop counting; re-run `tools/medals.gd` after any
  change to the physics, a car, the points, a track or its laps, and `tools/car_stats.gd` after changing a car.
- **AI networks belong to a car.** `SaveData.load_network(car, slot)` / `save_network(data, car, slot)` keep one
  network per car and slot (`"best"`, the one the player trains; more slots per car can sit beside it, e.g. shipped
  AI opponents for item 5). A car's slot is the network that *drives* that car; the file's `"car"` field is the car it
  was *trained* with (`Trainer.network_car()`: none or unknown = the Racer, so browser files and old ones are Racer
  networks). They differ only after loading another car's file, which the game allows with a note. A network seeded
  from another car's starts a new history (generation 0, no fitness carried). A training session (`TrainMode.session`)
  has one car; another car is a new session.
- **The career goes through `SaveData`** (v6.5.0): `get_money` / `get_points`, `add_money(n)` / `add_points(n)`
  (never below 0), `owned_cars` / `owns_car` / `give_car(id)` / `purchase_car(id, price)`, `paid_rewards(track, car)`
  / `pay_rewards(...)`; `Economy` builds the payouts, the prices and `buy()` on top. The terminal (v6.7.0) calls
  `add_money`, `add_points`, `give_car`, `Economy.buy` and the new `unlock_tracks(on)` / `tracks_unlocked()` (the
  `career.tracks_unlocked` flag: true or absent, so the file stays version 4 and older games keep it) and
  `reset_career()` ($0, 0 points, the starting cars, nothing paid, the flag off; records, ghosts, scores, networks and
  settings stay); each writes the file, and the screen's `changed` signal redraws the menu. The paid list is per
  track id and car, not per track signature, on purpose (see Known limitations).
- **Upgrades change a spec, never the physics** (v6.11.0): an upgrade is a set of `CarSpec` changes made by
  `Upgrades.changes(car, levels)`; `Upgrades.spec(car, levels)` is the only way to get an upgraded car (cached; the stock
  spec object itself at level 0). Anything that should drive the player's car takes the spec from there
  (`Upgrades.player_spec(car)` reads the save file); anything that must stay comparable (medal times, the AI opponents,
  their stored races, the medal sweep, `tools/car_stats.gd`) keeps `Cars.spec`. A new part is a `PARTS` entry and a
  branch in `changes()`; if it touches a key FleetSim reads, nothing else is needed (the spec goes over as data); if it
  needs a new `CarSpec` field, add it to `KEYS` and either to FleetSim or to `Trainer.spec_data`'s erase list (since
  v6.15.0 FleetSim reads `nitroRefill`). Run `tools/upgrades.gd` and paste its `MEASURED` lines after changing a car
  or a step.
- **The terminal** (v6.7.0): `ui/terminal_screen.gd` is only the console (it takes any object with `run(line)` and
  `complete(line)`; the app gives it `game/terminal.gd`), so ui/ doesn't depend on game/. A command method gets the
  arguments (lower case) and an `Out` (`add(kind, text)`, `row(label, value)`, `confirm(what)`, `changed`, `close`,
  `clear`); line kinds are ok / info / gain / loss / error / warn / row, coloured by the screen (gains green, losses
  red, errors and warnings in the accent). It opens only where the menu reads keys (`MainMenu.handle_keys`: the menu
  and Settings), never in a race. While it is open the menu hands every key to it and drops the rest; when it closes
  itself (`exit`, its Close button) the keys of that frame are dropped too (`_terminal_was_open`), so the Enter that
  ran `exit` doesn't drive.
- **AI opponents are data made by a tool**: `data/opponents/<car>.json` holds, per track, the network (the web
  game's file format), the track signature it was trained on, and each level's `{cap, time}` (cap in m/s, null =
  none). `Opponents.entry()` refuses an entry whose `physics` or `sig` no longer match, so a changed track or physics
  shows "No ... AI here" until `tools/opponents.gd --train --retrain --tracks=<id>` and a levels run. The race an
  opponent drives (`ai/opponent_race.gd`) is the play mode's AI ghost loop step for step (drive, step, race update,
  stuck after 3 s: respawn standing); change one, change both, and `tools/opponents.gd --check` must say every stored
  time is reproduced. Caps are stored as k / 100.0 so they read back as the same double (`snappedf` does not).
- **The interface is built in code** from the tokens in `ui/ui_style.gd` (colours, four text sizes, 4 px spacing
  grid, one slant); red / green only for losses / gains, the yellow accent for the one thing that matters.
- **Locked tracks** (v6.8.0): `Unlocks.is_open(id)` is the one question (unknown ids, such as test roads, are open);
  the interface asks `UiData.track_open(i)` / `track_lock(i)`, whose in-memory store (tests, previews) has
  `career.tracks_open = null`, meaning every track open: set a list to test locked tiles. Only a finish opens a track
  (`Unlocks.claim` in `PlayMode._on_finish`); nothing derives it from the best times after the one-time upgrade.
  End-to-end scenarios other than `economy`, `terminal` and `unlock` start with `SaveData.unlock_tracks(true)`.
- **Medals are never stored with a best time** (v6.9.0 relies on it): records hold the time, and the medal is
  `Medals.medal_for(medal_times, time)` when shown, so a new factor re-rates every save at once. What must not move
  when a medal gets harder is stored on its own: the tracks a medal opened (`career.tracks_open`) and the rewards
  paid (`career.paid`). Text that relates something to the medal times (the AI levels' `blurb`) is checked against
  the measured times by `tests/test_ai.gd`.
- **Sound** (v6.12.0): everything plays through `GameApp.audio` (`GameAudio`) on one of four buses (Master with the
  limiter; Music, SFX, Engine into it); never make a stray `AudioStreamPlayer`, add a name to `audio/sound_bank.gd`
  (file, level, pitch spread, shortest gap, voices) and call `play()` / `play_3d()` / `play_after()`. A new car gets
  an `EngineVoice.ENGINES` entry (data; calibrate its `gain` with `tools/engine_preview.gd` to about -17 dBFS at
  two thirds of the redline on load). `ui/` stays free of `audio/`: interface sounds go through `UiSound.play(name)`.
  The files are generated: change `tools/gen_sounds.py`, run it (`python3 tools/gen_sounds.py`, numpy and ffmpeg),
  then reimport (`godot --headless --import`); the effects' `.import` files set QOA and the loops' loop mode, keep
  them. Sounds of a test or e2e scenario are read from `GameAudio.history` / `sounds_since()`, never by timing.
  An `AudioStreamGenerator`'s ring buffer is the next power of two above `buffer_length × mix_rate` (8,191 frames
  for 0.25 s at 24 kHz, not 6,000): count what is queued from the free space of the empty ring, as `CarAudio`
  does, or the engine runs 90 ms late (the first Movie Maker run of v6.12.0 found it: 8 frames of lag, now 4).
- **Recording what the game sounds like**: headless Godot has no audio output, so listen through Movie Maker
  (`--write-movie out.avi`, lockstep: 60 frames of picture and 800 audio samples each, whatever the machine's speed).
  It ignores `--resolution`: run a copy of the project with an `override.cfg` that sets
  `display/window/size/window_width_override` / `height_override` (640 x 360 keeps the AVI small). Add
  `--audio-driver Dummy` to runs under xvfb, or Godot prints two ALSA errors when no sound card is found.
- **Godot files in git**: commit the `.uid` files next to scripts and shaders and the `.import` files of assets
  (Godot 4.4+ needs them for stable references); never `.godot/` or `build/`.
- **Running Godot while others work**: the editor and `--import` write `.godot/` and `.import` files, so when several
  agents or people work in one checkout, run Godot on a copy (copy the tracked files to a run folder, keep its own
  `.godot`). Always put a time limit around headless runs (`timeout 1500 godot --headless ...`): a script error during
  start-up leaves Godot running instead of exiting.
- Exports are made from a fresh import (delete `.godot` first): a stale cache once gave a "main.tscn: invalid UID"
  warning in the exported game.
- Run the headless suite before committing; run the end-to-end scenarios after changing the game shell, modes,
  input or interface.

## Known limitations

- **Championships (v6.14.0)**:
  - Esc during a cup race goes back to the standings without counting it, so a race can be retried until it goes
    well (the field race already allows R). Leaving after your finish freezes the AI still racing in their running
    order then, so they never overtake you after your finish (the field race does the same at the finish).
  - The grid behind you on a sprint is compressed into the run-up before the start (Summit Rush and the other sprints
    have 18 samples there): the last cars start closer together than 10 m. Tested on every track for every slot (on
    asphalt, 1 m spare, 2 m apart, no turns over 20°); not looked at on every track in 3D.
  - The trophy cabinet button is small (a 16 px trophy per cup, 2 px level pips); the picker spells it out.
  - Drivers keep their pace slot for the whole cup (the slowest of the five stays the slowest); the standings mostly
    follow the paces, so the cup is about beating the fastest driver.
  - Nobody has played a whole cup with a real graphics card or a gamepad in hand; the e2e run drives it with the
    autopilot.

- **Race the field (v6.13.0)**:
  - The AI drive their shipped opponent networks with a speed cap; the rule-based traffic layer only eases off
    behind a car close ahead and nudges the steering to the freer side. They don't plan overtakes or defend, so
    they rub and bump a lot (60-75 new touches a race between AI cars, about 9 of them faster than 3 m/s) and
    finish in the order of their paces in about 83 % of pairs.
  - A driver's pace is a speed cap interpolated between its car's measured levels; where the Elite level has no cap
    (the network flat out) the cap is a power-law estimate, and some cars (the Vortex on Summit Rush) run faster
    than their slot's pace, so the grid's slowest-to-fastest order is approximate.
  - The grid is ahead of the usual start spot (you start on it, the AI 10-50 m further on), not behind the line, so
    your time counts for medals; the AI's times are from their own grid slots.
  - Contacts are capsule against capsule on the ground plane only (no roll, no pitch, no damage); a car squeezed
    against a wall by another can be pushed into the wall for a step (the wall pushes it back).
  - No terminal command for it (the terminal has no reference to the app; it would need a signal chain). (v6.14.0's
    `cup` command only reads and writes the trophy cabinet in the save file.)
  - The other drivers' names, paces and cars are data (`sim/field.gd` `DRIVERS`, `PACE`); there is no per-driver
    personality (aggression, mistakes).
  - Nobody has played it with a real graphics card or a gamepad in hand; the e2e run drives it with the autopilot.

- **Sound and music (v6.12.0)**:
  - **No person has listened to it.** Every sound is synthesized and was checked by measurement only (levels, peaks,
    the engine's pitch against the sim's rpm, cue timing, spectrograms; see
    [How v6.12.0 was verified](#how-v6120-sound-and-music-was-verified)). Whether the engines sound like engines,
    whether the music is any good and whether the mix is balanced by ear is still to be judged; the levels are
    settings and `SoundBank` / `ENGINES` data, quick to change.
  - The menu music ("Pit Lane") is darker than the race tracks (its 2-6 kHz band 6-11 dB lower) and is the
    quietest of the four (RMS -17.0 dBFS in the file against -15.5 for each race track).
  - There is no pause screen, so only the finish panel ducks the music; Esc leaves a race at once.
  - The engine is rendered 50-120 ms ahead on the main thread: below about 8 frames a second (a software renderer,
    a very slow machine) the generator runs dry and the engine stutters. The real-time e2e run under xvfb and
    llvmpipe (about 3.5 frames a second) does, which is why its engine-pitch and blow-off checks only run under
    Movie Maker or at 30 frames a second or more.
  - The shortest gap between two plays of a sound is in wall-clock milliseconds (`Time.get_ticks_msec`), not game
    time; a Movie Maker run whose frames take longer than the gap can therefore play a sound in two frames that a
    real-time run would skip.
  - Quitting while sounds play (an e2e harness quitting at once) can print "ObjectDB instances leaked at exit": the
    `AudioServer` frees a stopped playback only on its next mix. The game stops everything (music, effects, every
    car) on the window's close request; the e2e harness calls `GameAudio.shutdown()` and waits 3 frames; a silenced
    `CarAudio` stays silent (the race's next frames started its loops again, so `scenario=perf`, which quits
    mid-race, printed "6 ObjectDB instances leaked" until that was fixed); `tests/test_world.gd` runs its sound
    tests before the long ones.
  - Settings at 1024 x 600 (one column) now scroll (622 px at 640 x 360): the Audio section added 5 rows; from 1100 px
    wide there are two columns and everything fits.
  - Engine sounds don't change with upgrades (an engine 3 sounds like stock).
- **Car upgrades (v6.11.0)**:
  - **Medals and AI wins get easier with upgrades, on purpose** (the owner's default): a fully upgraded car beats the
    stock author time with the same driving (the medal autopilot's runs: 4-8 % faster on four tracks), and the
    best-time lists mix stock and upgraded runs (a record keeps its levels as `up`, but nothing shows them yet: the
    menu's record line, the finish panel and the HUD don't say a run was upgraded).
  - **The tyre level makes a keyboard driver weave a little more**: the Racer with tyres 3, holding a lane at 120 km/h
    by tapping the keys with a 20 m look-ahead, yaws 5.05° (stock 4.89°; v6.10's fishtail test calls 5° a fishtail)
    while sliding only 2°. The upgraded check compares with the stock car (no slide; at most 0.5° more slip or weave);
    every other car, and every car on jumps and braking in a curve, is unchanged or calmer.
  - **The grip bar jumps further than the others**: it maps 1.3-1.9 g onto the bar, so tyres 3 (+12 % grip) move the
    Racer's from 0.55 to 0.86, while engine 3 (+14 % to 200 km/h) moves acceleration less. The bars use the fixed
    scales of v6.1 on purpose (the same bar means the same grip on every car).
  - **No loose grip mark on two models**: the Drifter has its own mud flaps and the Dune has open wheels, so neither
    shows loose grip on the model (the chips and bars do).
  - **The AI opponents' networks were trained on stock cars**; the player's own network is trained on the upgraded
    car if the car was upgraded when training started (a session keeps the spec it started with; upgrading during a
    session takes effect in the next one).
  - The nitro part is 10 % a level (the brief said about 3-5 %): at that size it is worth 0-0.8 % of a race at level
    3, the least of the four (the medal autopilot burns it at full throttle whenever the wheel is near straight; a
    player who saves it for the long straights may get a little more).
  - **The medal autopilot is tuned on stock cars**: in `tools/upgrades.gd --laps` its fastest upgraded run is sometimes
    messier than the stock one (the Drifter on Rookie Oval 103 steps against a wall against 39, its largest sideslip
    on Hairpin Valley 38° against 25°; the e2e author run with the Racer 9 wall contacts against none) and sometimes
    cleaner (the Racer on Ramp Rally 0 against 279). The stability tests (jumps, curve braking, lane keeping) drive
    fixed inputs and pass; a human driver was not tried.
- **Dirt and snow polish (v6.10.0)**:
  - **Northern Lights still rewards riding the walls with some cars.** With the Racer the medal autopilot's lap beats
    never braking by only 0.13 s there (v6.9.0: 0.43 s; the other six surface tracks 1.9-9.4 s). With the Vortex and
    the Thunder, never braking was already faster in v6.9.0 (by 1.12 s and 0.17 s a lap) and is more so now (2.43 s
    and 0.83 s), and on Mountain Pass with the Vortex (1.88 → 2.40 s): its banked snow bowls hold a car that rides the
    outside wall, and the slidier snow walls (× 0.45) lose it less speed. Lower `wall` for snow towards 0.6-0.7 (then
    `tools/medals.gd --update` and the opponents) if the owner finds it exploitable.
  - **On dirt some cars now brake about as well as on asphalt**: the Racer 29.8 m from 100 km/h (asphalt 30.7), the
    Kestrel 27.3 (27.7), the Drifter 30.0 (33.1), the Dune 27.4 (31.7): the asked-for 10-20 % gain plus the dirt's
    rolling drag. Snow is still longer than asphalt for every car but the Dune. One number per surface (`brake`).
  - **The Dune's author times** came out slower on Canyon Run (+1.78 s), Forest Rally (+2.00 s), Summit Rush (+0.67 s)
    and Ramp Rally (+0.03 s), although it brakes better: its fastest autopilot setting changed; the other cars are
    0.1-9.3 s faster. Records set before stay (`Car.PHYSICS_VERSION` not bumped) and are judged against the new times.
  - **The screen overlay was only seen with software rendering**, at 1280 x 720 (cost on a real graphics card not
    measured: one full-screen pass for the film and frost, only while either is above zero, and up to 52 small quads).
    It also shows in Watch the AI (the camera follows the AI car there). It is a lens effect, not tied to the 3D view,
    so it does not react to the camera turning.
  - **Older pictures of dirt and snow**: `docs/screenshots/dirt.png`, `snow.png`, `forest-rally.png`,
    `northern-lights.png` and `summit-rush.png` show the dirt and snow textures, borders and barriers before v6.10.0
    (and an older bronze); `screen_mud.png`, `screen_snow.png` and `border_new.png` show v6.10.0's.
  - **Snow on white snow is hard to see**: the flecks are shaded blue-grey on their lower right and melt into drops
    with dark rims so they show, and the frost is a blue-grey haze with white grains; over the sky and trees they read
    best.

- **Never run on Windows, on a real graphics card or with a real gamepad.** Everything was run on Linux with
  software rendering (llvmpipe) and simulated input. The Windows `.exe` and `.dll` were built and packed but not
  started. Frame rates measured here mean nothing; the draw-call counts above are the best guide. Gamepad input was
  tested through Godot input events only.
- **Maths library drift**: Godot uses the system's maths library (glibc on Linux, Microsoft's on Windows), the
  browser V8's own; `sin`, `cos`, `exp`, `pow` differ in the last bit for about 10 % of inputs. Runs are
  deterministic on one machine, but long free runs with wall contact diverge after tens of seconds between
  browser and Godot, and could differ by milliseconds between Windows and Linux. Ghosts store positions, so they
  are unaffected; medal times were computed on Linux.
- **The AI opponents' times were measured on Linux.** An opponent's race is deterministic on one machine and the
  win is judged against the race it actually drives, so it is fair everywhere; but on Windows (another maths library)
  a capped network can drive a slightly different line, and its finish can differ from the time the menu shows by a
  few milliseconds or, after a wall contact, more.
- **The reworked corners (v6.6.0) were judged with the medal autopilot, not with players**: it plans its corner
  speed from a fixed grip, so on snow and in the slowest hairpins it still slides into a wall on most laps (Hairpin
  Valley's snowy switchbacks on 98-99 % of laps, the hairpins on 87-91 %), only less often and for less time. Its
  fastest setting per car (the author run) can also lean on walls more than before, as on Canyon Run (46 → 98 steps of
  contact a lap, in corners that were not changed). Nobody drove the new layouts by hand.
- **Rewards are paid per track id, not per track version, on purpose** (v6.6.0): the five reworked tracks moved
  their records, scores and ghosts to the archive (new signatures) and have new medal times and AI opponents, but
  medals and AI wins already paid on them stay paid and are not paid again, so reworking a track can't be farmed
  for money (and nothing is taken back). Beating the new times pays only what that track and car never paid
  (`tests/test_sim.gd` "career", a v6.5 save). The menu shows no medal on a reworked track until a new time is set.
  To pay again per version, key `paid` by signature in `SaveData` (and migrate the existing lists).
- **The AI opponents are a single network per track and car held to a lower top speed**, not different drivers: the
  slow levels take every corner at the same capped speed (the Rookie is very steady), they never use nitro (v6.15.0:
  nobody does in a race against them; their networks were trained without it and have zero nitro weights), and with
  walls ride they lean on walls in tight corners like the trained networks do. Elite is the network flat out where
  that is about the author time, else capped to it (on about half the track-and-car pairs; the networks are up to
  17 % faster than the author time on Hairpin Valley, where they ride the walls). The opponents' cars don't collide
  with yours and don't react to it.
- **The Rookie may still be hard for a brand-new player on long tracks**: it takes 1.6 × the author time, slower
  than bronze (1.3 × since v6.9.0), but it doesn't crash or make mistakes.
- **The faster bronze (v6.9.0) is harder for a new player**: a new career needs a bronze on Rookie Oval (2:39 with
  the Racer, the author time + 30 %) before anything else opens. The e2e `unlock` scenario's deliberately slow
  autopilot (corner grip 13 m/s², 50 m/s at most) makes 2:32.900; v6.8.0's (11 m/s², 40 m/s) made 2:49.750, which
  is no medal now. No person has tried it. The AI levels were left as they are: beating the Amateur no longer
  means a bronze (it is 1.39-1.41 × the author time), and beating the Rookie and the Amateur pays without any medal.
- **Old saves and the new bronze** (v6.9.0): medals are worked out from best times, so a best time between the new
  and the old bronze shows no medal and the HUD aims at the new bronze; tracks it opened stay open and rewards it
  paid stay paid (a new bronze pays nothing again: `career.paid` has it). Two one-time upgrades judge against
  today's medals, so they are less generous with an old 1.5 × bronze: a save from v6.7.0 or older (no
  `tracks_open` yet) opens the track after one only for a time under today's bronze (the track itself opens anyway:
  it has a best time), and a save from before v6.5.0 is paid once only for the medals its times hold today.
- **Screenshots with an old bronze**: the HUD's next-medal line in `docs/screenshots/driving.png`, `race-ai.png`,
  `dirt.png`, `snow.png`, `forest-rally.png`, `northern-lights.png` and `summit-rush.png` shows the bronze of the
  version they were taken in (some from before v6.6.0); v6.9.0 retook only `menu.png`, `finish.png`, `locked.png`
  and `terminal.png`, where the medal times are the subject.
- **Technical Trial, Racer** (the browser's layout, the game's until v6.5.0): the medal autopilot's best run grinds
  a wall for 281 steps, and a last-bit difference turns into a different finish: 3:45.083 here against 3:44.033 in
  the browser, so gold / silver / bronze were 3:59 / 4:31 / 5:38 (browser 3:58 / 4:29 / 5:37). Lockstep from the JS
  states reproduces every step, so it is not a port bug. All other 47 track-and-car medal sets were identical. Since
  v6.6.0 five tracks have layouts of their own, so their medal times no longer compare with the browser's at all.
- **Terrain noise differs**: the terrain uses Godot's FastNoiseLite, statistically like the browser's noise but the
  hills are in different places. The road, walls and scenery rules are the same.
- **Track building is slower** (0.8-1.7 s against 0.16-0.45 s in the browser); the menu builds on a worker thread so
  the orbit never stops, and a race waits for its track.
- **GDScript physics is about 40× slower than the browser's JS**: fine for playing, but `tools/medals.gd` takes about
  35 minutes for six cars on 3 cores (`--jobs=3`; it only writes `data/medals.json` after a full sweep; `--update
  --tracks=...` sweeps some tracks and keeps the rest, 17 minutes for four) and
  `tools/car_stats.gd` about a minute (52 s for six cars on 4 threads).
- **Car models and headlights were only ever seen through software rendering** (llvmpipe): the headlight
  brightness (high: two spotlights a car, medium: one, low: a glowing pool on the road), the panel lines and the
  driver's colours were tuned on screenshots from it. The low-quality headlight pool looks blocky up close.
- **The Vortex is the fastest car on the eight all-asphalt tracks, Mountain Pass and Canyon Run, and the Dune the
  slowest on asphalt** by the medal autopilot; on Ramp Rally and Hairpin Valley the Dune is the fastest and the
  Vortex fifth. The balance comes from the medal autopilot, which follows the centre line and slows for the grip
  share it is told; people may find dirt and snow easier or harder than that.
- **On snow the walls are nearly as good a brake as the brakes** for the simple autopilot: on Hairpin Valley a
  never-braking autopilot is only 0.55 s a lap slower than the best clean-ish one (4.6 s on the asphalt version),
  because the brakes lose grip on snow and the wall model does not. Walls still cost time on every track (a test), and
  the score punishes them; a wall-friction factor per surface would be the fix if players abuse it.
- **The AI does not see the surface**: its inputs are the rays, speed, slip, yaw, aims, corners and (v6.15.0) the
  nitro tank (`SENSOR_VERSION` 3), nothing about the ground; a network learns where the
  dirt is on the tracks it trains on. A Racer network trained on an all-asphalt track brakes too late on snow.
- **Surfaces were only seen through software rendering** (llvmpipe): the dirt and snow colours, the border noise,
  the dust and spray density were tuned on its screenshots. The snow spray (v6.4.0: blue-grey `spray` colour in the
  surface table, bigger and denser puffs) shows on the white road there; on a real screen it may need another look.
- **The terminal (v6.7.0) is a cheat on purpose**: money, points and cars it gives are the same as earned ones (no
  mark, no log), and nothing stops a player from using it. Its typing was only tested with simulated key events
  (Godot `InputEventKey`s with their characters): no real keyboard, no IME, no Windows. `` ` `` is the key under Esc by
  position (`physical_keycode` `KEY_QUOTELEFT`), whatever it types on the layout: on a German keyboard that is ^,
  which Windows may treat as a dead key (the terminal still opens and closes, the input ignores the key). A backquote
  typed with another key (German Shift+´) goes into the input as a character and does not close it.
- **Unlocking tracks (v6.8.0)**: the upgrade of an older save is generous on purpose: every track with any best time
  stays open (every track was open before), even without a medal on the track before it, and archived times count
  against today's bronze, not the bronze of their day (simpler; the old medal times are not kept). Records of other
  physics versions count too. A `reset career` after `unlock tracks` can leave gaps (a track opened by a medal while
  the flag was on stays open, the ones before it lock again). The NEW mark lives only in memory (a restart drops
  it). A bronze is judged with the medal the payout uses (`Medals.medal_for` against `medals.json`), so a run with
  no medal times (none for that track and car) opens nothing. A save written by v6.8.0 and then by an older game keeps
  `tracks_open` (older games don't touch unknown career keys), but medals won in the older game open nothing until a
  finish in v6.8.0 or later. Not done (not asked): unlocking cars or AI levels by progress, a message when a newer
  medal table would have opened a track.
- **The menu's side column is 28 px wider on tracks with a long surface line** (Hairpin Valley "Asphalt + packed
  snow", from v6.3.0, not new): the meta label doesn't wrap, so the tiles get a little narrower while such a track is
  picked. Seen on the v6.8.0 screenshots; harmless, but a wrap or an ellipsis there would keep the layout still.
- Archived records, scores and ghosts (save file `"archive"`) are kept but nothing in the game shows them yet
  (`SaveData.get_archived` reads them).
- `web/docs/tracks-overview.svg` shows the layouts only, not the surfaces, and only the first 12 tracks.
- **Northern Lights (v6.4.0) can be driven flat out**: its banked snow bowls let a never-braking Racer lap in
  1:09.683, only 0.43 s slower than the best medal-autopilot lap (1:09.250 at 40 m/s² of planned grip; 1:13.483 at
  the usual 18-22, which the bowls' banking beats). Sliding scrubs about as much speed as braking would; the walls are
  touched (133 steps) but cost little. The heavy cars' medal runs there touch a wall in about 15 % of their steps
  (Thunder 1,801 of 12,097, Vortex 1,786 of 12,340; aLat 40), against at most 409 on the older tracks; at 20 m/s²
  the Thunder touches 183 steps and is 23 s slower. A test keeps "walls cost time" true with the best of the sweep's
  settings for the v6.4 tracks. Tighter, less banked bowls (tried: banks 12-14°) did not change it much.
- **The new tracks are easy for the AI to learn**: 80 random Racer networks (FleetSim, seed 1) finish each of them in
  generation 0, even with walls crash (Mountain Pass: generation 5), because the roads are 14-16 m wide with no
  corner under a 39 m radius.
- The northern lights are only in the visible sky, not in the sky's radiance cubemap (it would rebake every frame
  as they drift), so they don't light the snow.
- A ghost car on High and Medium now costs about 16,500 triangles (was about 10,600) because it is the full model
  in the ghost material (on Low about 6,700); it is 2 draw calls instead of 38.
- **The Linux training library needs glibc 2.38** (Ubuntu 24.04 or newer); on older Linux the game falls back to
  GDScript training. The Windows DLL needs only `KERNEL32.dll` and `msvcrt.dll`.
- The AI's nitro refills by a simpler rule than the player's (`Sensors.NitroRefill`: the clean-checkpoint combo and
  the clean lap of `sim/score.gd`, no drift, jump or air points, which would need the score's whole state in
  FleetSim); a player who drifts refills faster. Its speed input is scaled by each car's `CarSpec.max_speed`, a round figure near the
  measured top speed (the Dune's 61 m/s against 61.8 measured, so its speed input can reach 1.01; the Vortex's 91
  against 89.3). Changing a car's `max_speed` changes what its networks see: treat it like a sensor change.
- Networks trained with `tools/headless_train.gd --car` before v6.2.0 have no `"car"` field and read as Racer
  networks; load them with that car picked on the menu (they then drive it, with a note), or add `"car": "<id>"`
  to the file.
- A network loaded from a file trained with another car drives the picked car as it is; the game says so but does
  not stop it, and it usually drives worse than the car's own network (see the v6.2.0 verification).
- There is no "reduce motion" option (the browser followed the system setting): the camera shake on wall hits and
  the nitro kick are always on (`ChaseCamera.reduce_motion` exists, nothing sets it).
- Browser saves (localStorage) can't be carried over. Browser network files load here (widened to 19 inputs and 3
  outputs); files saved since v6.15.0 don't load in the frozen browser version (it calls them version 1 networks).
- No track overview map is generated (`web/docs/tracks-overview.svg` still shows the same tracks).
- The file dialogs for networks are the system's native ones and were only exercised through code, not clicked.
- `TrackBuilder.get_gates()` caches gates for unusual lap counts lazily and is not thread-safe for those (the game
  only uses each track's own lap count, which is built up front).
- From the browser version, still true: medal times come from a simple centre-line autopilot (a good driver can beat
  author); car balance, nitro and points were tuned with autopilots, not people; with Walls:
  Ride them the AI uses walls as brakes on twisty tracks; tracks can't cross themselves (no bridges). See
  web/HANDOFF.md for the full list.

## Round 5: eight items (v6.18.0 on)

Asked on 2026-11-12: "Make the AIs in the races more competitive and better / make the car selection after the race
you've chosen starts not before and make it possible to change cars within a championship / make on more car / make 4
more maps in a rally stage style with new textures / make it possible to change the wheight of a car in the upgrades
aka lighter / make it possible to actually reset everything to zero including medals and map unlocks / redesign the ui
to be more streamlined and fix the leaderboard in more of a style of the f1 games / add a minimap with sectors make me
able to look up the fastest sector on each map with what car which upgrades and what times".

The order they are built in (the owner was told; each is pushed when done), and the defaults chosen where the request
left it open:

1. **Reset (v6.18.0, done)**: see below.
2. **Menu flow (v6.19.0, done)**: pick the track and the race type first, then the car on a page of its own (with its
   upgrades); in a cup that page comes up before every race, so the car can change between races. See below.
3. **Leaderboard**: an F1-style timing tower on the left of the HUD (position, colour bar, three-letter code, gap) and
   F1-style results and standings tables.
4. **Weight**: a fifth upgrade part that makes the car lighter, ten levels like the others.
5. **A seventh car**: an open-wheel formula car (the most grip, the best brakes, poor on loose ground).
6. **Four rally stages**: point-to-point, on new surfaces (gravel, sand, ice, mud) with their own textures, and a Rally Cup.
7. **The AI**: every level faster, the field closer together, the top level in an upgraded car, longer training so the
   networks scrape the walls less.
8. **A minimap with sectors**: three coloured sectors and the cars as dots in a race; a records page with the best
   time of each sector on each track, with the car and the upgrades it was set with.

### Item 1: the Reset button (v6.18.0, done)

The owner asked for a reset "to zero including medals and map unlocks" again, two days after v6.17.0's `reset
everything`. The command was checked once more on a save with medals, `unlock all`, cars and upgrades: it clears all
of it, also after the file is read again (as a restart). The likely trouble: `reset everything` on its own only says
what it would do, and the hint to type it again with `confirm` is easy to miss. So:
- `ui/settings_screen.gd`: a **Reset all progress** row (an `action` row, key `reset`, the last row, in Career).
  `MainMenu.reset_requested` passes it on; `GameApp.ask_reset_everything()` asks twice with `MessageScreen.ask` (the
  first Yes opens "Really reset everything?", so a double Enter can't wipe), then `reset_everything()` calls
  `SaveData.reset_everything()`, `_after_wipe()` and shows where the backup is and how to undo it.
- `game/terminal.gd`: `Out.confirm()` now says "Nothing has changed yet. Type yes to do it (or <line> confirm)" and
  sets `asked`; `run()` keeps that line as `_pending`: the next line `yes` / `y` runs it with `confirm`, `no` / `n`
  drops it with a note, any other line drops it and runs as usual.
- Tests: `tests/test_game.gd` (the row asks, Esc leaves everything, the first Yes asks again, the second wipes, the
  message, the file read again; the terminal's yes / no / a command in between), `tests/test_ui.gd` (the row).
- A helper for the releases: `tools/release.sh <version>` builds the Windows zip from a clean copy
  (`docs/windows-readme.txt` is the zip's README.txt).

### Item 2: the car page and the tidier menu (v6.19.0, done)

"make the car selection after the race you've chosen starts not before and make it possible to change cars within a
championship" and the menu half of "redesign the ui to be more streamlined".
- `ui/car_screen.gd` (`CarScreen`, a dialog like Settings; `MainMenu.car_page`): the car cards, the picked car's part
  chips and description (all moved out of `ui/main_menu.gd`), the money, START (BUY / LOCKED for a car that is not
  yours) and a line saying what is about to start (`event_text`). Keys: arrows / WASD, C / Shift+C, 1-9 buy a part,
  Enter starts, Esc back; the pad has its own highlight (cards, parts, START).
- `ui/main_menu.gd`: Home is "1 Track" and "2 Race". `ask_car(kind, args)` keeps what was chosen (`pending`: `drive`,
  `race_ghost`, `race_field`, `cup_start` with cup and level, `cup_next`) and opens the page; the page's `start`
  emits that signal (`_start_pending`). On a locked track the signal goes out at once (the app says what opens it).
  Before `cup_next` the page shows the cup's car. The primary button reads TIME TRIAL (the mode is still `drive` /
  "Drive" in the code, the HUD and older text). Watch AI, Train AI, Load AI…, Save AI… are small buttons under a rule
  and start directly. Race the AI / Race the field are no longer off for a car you don't own (the car comes later).
  `refresh()` also redraws the car page. The tiles' maps take the height the car picker used (`_layout`).
- `game/app.gd`: `ui.menu.cup_start` -> `start_cup`, `ui.menu.cup_next` -> `cup_next_race()`: the car picked now
  becomes `cup.car` (saved with the run); a car you don't own is offered for sale and nothing starts. The AI drivers
  and the standings don't depend on your car; the field's pace follows the new car as in any field race.
- `ui/cup_screen.gd`: START CUP no longer needs an owned car picked; its text says you pick the car before each race.
- Tests: `tests/test_ui.gd` (the page's keys, pad, sizes, shop states), `tests/test_game.gd` (the shop on the page, a
  cup's car page, the car change before race 3 and its refusal for a car that isn't yours). In `tests/e2e/game_e2e.gd`
  `auto_start` presses START for the scenarios written before the page; the menu, economy, terminal and upgrades
  scenarios turn it off where they use the page. Shots: `menu_home`, `menu_car_page`.
- Found on the way: `tests/test_ui.gd`'s Settings checks stopped at the Reset row since v6.18.0 (a script error on
  the plain button's missing label), and the e2e unlock scenario still expected save version 4. Both fixed.
- Not done: no separate "AI lab" page (the four AI tools stayed on Home as small buttons), and the README still says
  "Drive" for the time trial in its older sections.

## Round 4: AI nitro, upgrades to level 10, reset everything (v6.15.0-v6.17.0)

Asked on 2026-11-10: "make the trained ais be able to use nitro / take out the nitro from races vs the ai / add 7
upgrades to all the cars so the max level is 10 / add a command so i can reset everything to baseline even the
medals". Built in three steps, each pushed when done.

### Item A: the AI uses nitro, no nitro in races against the AI (v6.15.0, done)

How it is built:
- `ai/sensors.gd`: `INPUT_COUNT` 19 (input 18 = `car.nitro`, the tank 0..1), `OUTPUT_COUNT` 3 (output 2 = nitro: the
  mean of the straight and the mirrored answer, as the throttle; above 0 it is `controls.nitro`, that much),
  `SENSOR_VERSION` 3. `Sensors.NitroRefill` is the AI's tank refill: `sim/score.gd`'s clean checkpoint (500 × the
  combo x1..x5, the lap line counts, the finish doesn't) and clean lap (2,000) points / 16,000 a tank ×
  `spec.nitro_refill`, a wall contact (`car.hit_wall`) spoiling the checkpoint, the combo and the lap. `AIDriver`
  runs it (`refill`, on by default) when it gets the race; `Trainer` runs one per agent (GDScript path).
- `native/` (FleetSim, "trackrush-native 5"): the same input, output and refill (`refill_gate`, per gate passed in a
  step, after the gates), `Spec.nitro_refill` (`"nitroRefill"`), `Rules.nitro` (false: empty tanks, no refills),
  view states 37 floats (+ tank, boost). Bit for bit with GDScript (the lockstep parity tests on every track and car
  now check that the nitro is used and refilled).
- `ai/network.gd` `grown(n_in, n_out)` widens a network with zero weights; `Trainer.parse_network_file` widens files
  with 18 inputs and 2 outputs (sensor version 2 or none: the browser's, v6.0-6.14) and returns the file's own meta;
  `network_file()` writes sensor version 3. A widened network's steering and throttle are bit for bit what they were
  and its nitro output is exactly 0 (never fires). `ai/genetic.gd` `silent_outputs`: new random networks start with
  the nitro output's weights and bias at 0 (random drivers burning nitro into the walls stopped the v6.4 "80 random
  drivers finish" test); mutation evolves them from there.
- No nitro in races against AI cars: `PlayMode.nitro_on` (false with the AI ghost: Race the AI at any level and My
  AI; `FieldMode` sets it false for Race the field and cups) empties the player's tank, keeps the nitro key out of the
  controls, turns the score's refill off and hides the gauge; the HUD's `_nitro_off` label ("No nitro in AI races")
  takes its place, the finish panel says it, and the menu's 3 Drive heading row says "No nitro vs AI" (v6.16.0: shorter, so
  it fits beside the Cups button at 1280 x 720; the tooltip says the rest). The AI ghost and
  the field's AI cars run with empty tanks and `refill` off (`sim/field_race.gd`, `ai/opponent_race.gd`), so the
  shipped opponents' stored races are unchanged. Medals, records and unlocks from those races count as before
  (measured on the medal autopilot without nitro: Rookie Oval 2:04.083 instead of 2:01.867, still gold; Seaside
  Stunts 1:09.767 instead of 1:08.233, gold).
- `tools/opponents.gd` trains with `nitro = false` (the opponents race without it); `tools/headless_train.gd
  --no-nitro` does the same.

Choices made where the owner gave none: the AI's refill follows the clean-driving part of the player's points only;
watching the AI (Watch the AI, Watch best) and the AI's best lap use nitro, every race with AI cars in it doesn't
(also My AI's ghost); the shipped opponents were left as they are (see the check below).
**Measured** (`tools/headless_train.gd`, 80 cars, seed 1, 150 generations, then a 3-lap race as Watch the AI drives
it, with and without a tank): Rookie Oval 13 burns, 9.2 % of the race, 86 % of the burning with the road straight
25-60 m ahead (57 % of the race), at 153 km/h on average (race 190: out of the corners), 1.19 tanks refilled, race
2:02.817 with nitro and 2:04.533 with an empty tank; Night Highway 21 burns, 5.5 %, 93 % straight, 3:12.483 against
3:14.217. The same seed trained without nitro: best lap 43.150 against 42.383 (Night Highway 1:07.500 against
1:05.550); generation 0 is the same in both (the nitro output starts silent). `tools/opponents.gd --check`: all 450
stored opponent races reproduce with the widened networks (534 s), so the opponents were left alone. A network
trained with `--no-nitro` reads a full tank in Watch the AI, which it never saw (its tank input's weights drifted
unused): the Rookie Oval one drove 2:17.083 with a full tank against 2:02.800 empty (the opponents always race empty).

### Item B: upgrades to level 10 (v6.16.0, done)

How it is built:
- `sim/upgrades.gd`: `MAX_LEVEL` 10; `LEVEL_GAIN` (what a part adds at level k in steps over stock: 1, 2, 3 exactly
  as before, then 3.8, 4.5, 5.1, 5.6, 6.0, 6.3, 6.5: each level less than the one before); `gain()` reads it, so
  levels 1-3 are bit for bit the v6.11-6.15 specs (a test compares every field). `LEVEL_SHARE` 0.1, 0.2, 0.35 (as
  before), 0.55, 0.8, 1.1, 1.45, 1.85, 2.3, 2.8 (each rise 0.05 bigger than the last). `MEASURED` holds levels 1-10
  of the engine and the tyres per car (`tools/upgrades.gd`, now 25 specs a car, 1,759 s on 4 threads; levels 1-3
  came out identical to the old table). `clean()` clamps to 0..10, so saves holding 0-3 read the same and need no
  migration (the save file stays version 5; an older game reading a level above 3 clamps it to 3).
- `ui/part_chip.gd`: more than five levels draw ten narrower pips (3.5 px, 1.5 px apart; levels 8-10 a lighter
  green), prices from $100,000 shortened ("$105k"; the tooltip has the full price), a name that doesn't fit is cut to
  its first word ("Loose") before an ellipsis. Fits 1280 x 720 with the dearest price (`ui_preview` `menu-upgrades`).
- `world/car_build.gd`: levels 4-10 grow the same parts in small steps (exhaust tips +3 % a level instead of +10 %,
  tyre rings +3 mm, a fourth nitro band at 4, thicker bands from 5 to a sleeve at 10); level 10's parts sit within
  3.5 cm of level 3's (a test; the exhaust tips stick out 0.5 cm further a level instead of 3).
- The terminal's texts say 0 to 10 (`upgrade`), the menu's caption tooltip ten levels; nothing else needed a change
  (the picker, the app's buy flow, `Economy.buy_upgrade`, records and ghosts all read `MAX_LEVEL` or `clean()`).

Choices made where the owner gave none: the seven new levels add 0.8 to 0.2 of a step (level 10 = 6.5 steps: engine
+32.5 % torque, tyres +26 % grip, nitro +65 % tank and refill, loose grip +32.5 %); prices rise so that the Racer at
level 7 everywhere costs about one author-and-Elite career with it and levels 8-10 another 1.7 such careers; the
medal times, AI opponents and their stored races stay stock as before.
**Measured** (`tools/upgrades.gd --quick`: the medal autopilot's best of 10 settings, 4 tracks × 6 cars, 1,227 s):
everything at level 10 is 8.4-14.8 % quicker than stock and 4.4-8.2 % quicker than everything at 3 (the Racer on
Rookie Oval 2:11.417 → 2:03.133 → 1:54.950, on Ramp Rally 3:09.200 → 2:53.933 → 2:41.983); one part at 10: engine
1.0-4.5 %, tyres 1.9-11.2 %, nitro 0-1.4 %, loose grip 0 on asphalt and up to 6.2 % on dirt and snow. Stability: no
best run spins (largest body slip 38° at level 3, 71° at level 10: the Drifter on Ramp Rally, a 1.75 s slide on dirt
at about 105 km/h on lap 2, no wall, with the autopilot's setting of 26 m/s², which won its sweep; level 3's best run, at
22 m/s², never passes 40°); the stability tests run at level 10 (`tests/test_sim.gd`: jumps,
holding a lane, braking in a curve on asphalt, dirt and snow, every car; in the keyboard lane test a car at 10
  weaves up to 0.7° more than stock (the Drifter 5.0° against 4.3°: the tyres answer the keys more sharply) while it
  slides less, so that test allows 1° above level 3 instead of 0.5°). Stats at 10 (the Racer): 0-200 km/h 9.78 →
7.22 s, top speed 277.7 → 297.2 km/h (the top speed stops at engine level 7 on most cars: the gears run out), grip
1.68 / 1.58 → 2.13 / 1.83 g, tank 5.0 → 8.25 s, dirt grip 1.15 → 1.52 g; a level-10 car drifts less readily (the
Racer holds a keyboard drift 0.67 s against 0.83). Prices: every level of every part of every car $4,389,200 (levels
1-3 $248,200 as before); the Racer $196,500 for levels 1-7 and $300,200 for 8-10, against $102,000 for a gold +
Expert career with one car and $173,400 for author + Elite.

### Item C: `reset everything` (v6.17.0, done)

How it is built:
- `sim/save.gd` `reset_everything()`: under the save's lock it first writes the whole save as it is to
  `backup_path()` (next to the save: `trackrush_save.backup.json`); an older backup there is renamed with its file
  date (`trackrush_save.backup-2026-11-10-16-27-56.json`, `-2` and on if that is taken), so a second reset never
  overwrites the first one's backup. If the rename or the write fails it returns `ok = false` and changes nothing.
  Then it builds a new save as a fresh install does (`_start_career`, `_repair_career`, `Unlocks.from_records` on no
  records: only Rookie Oval open) with empty records, ghosts, scores, networks and archive, keeps the settings minus
  the picked car and opponent, and writes it. Returns `{ok, backup, kept}` (global paths).
- `game/terminal.gd`: `reset everything` is the second word of `reset` (Tab completes `career` / `everything`); it
  asks first like `reset career` (`reset everything confirm`), says what goes and what stays, prints the backup's path
  (and the older backup's new name) and how to undo it, and emits `wiped`.
- `game/app.gd` `_after_wipe()` (on `wiped`): drops what the app held from the old save: the networks cache, the
  network on the menu, the cup in progress, Train mode's kept session; picks Rookie Oval. The menu redraws from the
  terminal's `changed` as for every other command.

Choices made where the owner gave none: the settings stay as they are except the picked car (back to the Racer, the
only car owned) and the AI opponent (back to the default); the network files **Save best network** wrote to
`networks/` stay (they are the player's own files, like an exported network, and the reset message doesn't promise
them gone); an older backup is kept, not overwritten; no backup, no reset. Undo is by hand (close the game, rename the
backup to `trackrush_save.json`): the README says so, the terminal too.

## Round 3, item 2: Championships (v6.14.0)

The owner's pick: "Championships: cups of 3-4 tracks raced back to back against AI, with a points table, trophies and
a big payout." **Done in v6.14.0.** Built on Race the field: every cup race is a `FieldRace` in `modes/field_mode.gd`.

How it is built:
- `sim/cups.gd` (`Cups`, data): `CUPS` (five cups of three tracks, easiest first: Rookie, Asphalt, Technical, Dirt and
  Snow, Grand Finale; mean track difficulty 2.0, 2.7, 3.7, 4.0, 4.7; together all 15 tracks), `POINTS` (10, 8, 6, 5, 4,
  3; a DNF 0), `is_open()` (every track open: `Unlocks.is_open`), `table(entrants, races)` (points, then the best
  finishing place, then the places from the latest race back, then the entrant order) and `grid_order()` (the
  standings, leader on pole; before race 1 the field's own order with you last).
- `sim/cup_run.gd` (`CupRun`): a cup in progress (cup, level, car, the five drivers, each race's {id: {place, dnf}}),
  `field(track)` (the AI lineup in grid order, each driver keeping its pace slot from `Field.cup_drivers`, and your grid
  slot), `add(rows)` (validated), `to_dict()` / `from_dict()` (validated: a damaged run is dropped).
- `sim/field.gd`: `cup_drivers(cup, level)` (five drivers for the whole cup, the same seeded shuffle as a field's
  lineup), and `grid(t, n, anchor)`: the player's slot (`anchor`) is always on `start_idx`, so a cup race is as long as
  Drive and counts for medals and records; cars ahead of you in the standings are ahead as before, cars behind you go
  behind the start line (circuits: their race starts at lap -1, so crossing the line doesn't count a lap; sprints:
  compressed into the run-up, at least 3 samples from the start of the road). `sim/field_race.gd` takes `player_slot`.
- `sim/economy.gd`: `CUP_PLACES` (4th to 1st: $300-2,000, 5-60 points) × `FIELD_LEVELS` × `cup_scale` (1 + 0.25 × the
  cup's index); ids `cup-<cup>-<level>-<place>` (read from the end: cup ids may hold a dash) in a new `career.cups.paid`
  list; a place pays the places below it, once per cup and level (not per car). A Pro Rookie Cup win pays $6,300 and 166
  points; an Elite Grand Finale win $25,200 and 660.
- `sim/save.gd`: `career.cups` = {paid, trophies: {cup: {level: best place}}, run (the cup in progress)}; version 5
  kept (absent = empty); `finish_cup()` pays and records the place in one write and drops the run; `reset_career`
  keeps the trophies, clears the cup payouts and the run.
- `game/app.gd`: `start_cup()` (refuses a locked cup naming its locked tracks, an unowned car, no AI), `cup_race()`,
  `cup_result()` (the run saved after every race; the last one pays), `cup_standings()`, `end_cup()`, `ask_quit_cup()`.
- `modes/field_mode.gd`: in a cup, R only before the finish; Enter after it records the race (the AI still racing
  classified in their running order then) and shows the standings; Esc before the finish goes back without counting;
  after the last race the trophy moment: the podium with the top three of the final standings (`world/trophy.gd`:
  a cup from primitive meshes, gold, silver, bronze; `world/podium.gd` `put_trophy()`), the finish panel's
  `cup_final` state (final standings, the cup's pay).
- UI: `ui/cup_screen.gd` (the picker: cups with tracks, difficulty and a trophy place per level, the level chips, what
  a win pays, START CUP; the standings: `ui/cup_table.gd`, RACE n, Quit cup), `ui/cup_cabinet.gd` (the menu's **Cups**
  button on the 3 Drive heading row: a trophy per cup plus five level pips, a tooltip listing them; **T** opens it),
  `ui/finish_panel.gd` (`keys` override, `field.cup` line, `cup_final`), `ui/ui_data.gd` (`cup_list`, `cup_pays`,
  `cup_view`, `cup_trophies`). The terminal's `cup` lists the cabinet and sets a place without pay; `status` counts
  the trophies.

Choices made where the owner gave none: five cups of three tracks (the owner said 3-4: three keeps a cup about 8-12
minutes and covers the 15 tracks exactly); points 10-8-6-5-4-3; ties by best place then the latest race; a cup race
pays as a field race and counts for medals, records and unlocks as Drive does; the cup's pay is per cup and level, not
per car; 5th and 6th pay nothing; Quit cup pays nothing for the cup (the races keep their pay); Esc mid-race doesn't
count the race (it can be raced again, so a bad start can be retried); a cup in progress survives closing the game;
the cabinet shows the place at the highest level with a trophy; `reset career` keeps the trophies.
**Open**: see Known limitations.

## Round 3: Race the field (v6.13.0)

Item 1 of round 3. The owner's pick: "Full race against an AI field: five solid AI cars on a starting grid instead of
one see-through rival, with positions on the HUD, a podium, and pay by finishing place." **Done in v6.13.0.**

How it is built:
- `sim/car_contact.gd` (`CarContact`): car against car as two capsules on the ground plane (the car's core segment
  and radius from its spec): pushed apart along the normal by the overlap, shared by mass, at most 0.5 m a car a step;
  an impulse with restitution 0.2 and friction 0.25 on the closing speed, a small yaw kick (clamped to ±1.5 rad/s), a
  speed scrub of up to 6 %; skipped when their heights differ by more than 1.2 m. Each pair is resolved in a canonical
  order, so it is symmetric and deterministic bit for bit. Only `FieldRace` calls it: Drive, Race the AI, the ghosts,
  training, FleetSim and the medal times are untouched (no native change, no medal or opponent re-run).
- `sim/field.gd` (`Field`): the roster (`DRIVERS`: eight named drivers with a car and colour), `lineup()` (five of
  them shuffled by a seeded FNV hash of track and level, pole first; slot k aims at `PACE[k]` × the level's time with
  the player's car: 1.08 to 1.0; a car that can't reach it even at Elite is swapped for the player's car; the speed cap
  from `cap_for()`, log-interpolated between the car's measured levels), `grid()` (the player on `start_idx` in the
  right lane, the AI ahead 10 m apart alternating sides, ±3 m or 40 % of the half width).
- `sim/field_race.gd` (`FieldRace`): steps every car (the AI's controls from their drivers plus `traffic()`: brake
  when closing on a car ahead within 1.6 s, steer towards the freer side), resolves contacts, updates each race,
  respawns an AI stuck (`PlayMode.is_stuck`) or facing the wrong way for 2.5 s (a ghost, not solid, for 1 s after),
  counts contacts, marks every 5 samples for gaps, and gives `standings()`, `position()`, `gap()`, `board()` (the HUD)
  and `results()` (the finish panel). An AI still racing 90 s after the player's finish is out (DNF).
- `modes/field_mode.gd` (extends `play_mode.gd`, which gained small hooks: `_place_start`, `_race_step`,
  `_render_others`, `_grime_ahead`, `_hud_extra`, `_render_hud`, `_finish_payout`, `uses_pb`): the five AI models and
  positional engines (only the 3 nearest heard: `CarAudio.set_active`), contact sounds, the finish (the panel docked
  right, the AI finished in the background within 6 ms of script time a frame), the podium (`world/podium.gd`) 1.8 s
  after the finish with its own camera.
- `sim/economy.gd`: `FIELD_PLACES` (5th to 1st: $60-450, 1-15 points) × `FIELD_LEVELS` (0.6 to 3.0) × the track's
  scale; ids `field-<level>-<place>` in the existing paid list (no save version change); paid like medals (the places
  below too, once each).
- The menu: a **Race the field** button beside Train the AI (off with My AI or no AI; its tooltip says what a win
  pays); `GameApp.play_field()` refuses locked tracks, unowned cars and My AI.

Choices made where the owner gave none: the field's pace is the picked level's time with your car (the last AI on
the grid is that level's AI opponent), the others 2-8 % slower; you start last on the usual start spot so the run
counts for medals, records and unlocks; the best-run ghost does not race along; a place pays the places below it
once, as medals do (a Pro win on Rookie Oval $1,520, an Elite win $3,000 there); the podium is a simple 3D podium on
the start straight with a slow camera swing, the finish panel docked on the right; the AI still racing when you
finish are fast-forwarded out of sight while the podium shows; 3 AI engine voices at once; no terminal command.
**Open**: see Known limitations (no real overtaking AI, approximate pace order, rubbing counts, no terminal command).

## Round 2: the owner's three new items

Asked on 2026-11-04, to be built one at a time in this order, each pushed to GitHub when done. Kept from round 1:
tracks a player opened stay open (`career.tracks_open`), rewards already paid stay paid, medal times come from
`tools/medals.gd` with bronze 1.3 × the author time, the AI opponents ship in `data/opponents` (`tools/opponents.gd`
trains, calibrates and `--check`s them), everything runs locally.

1. **Dirt and snow polish.** **Done in v6.10.0** (see the status above and
   [How v6.10.0 was verified](#how-v6100-dirt-and-snow-polish-was-verified)). Choices made where the owner gave none:
   the overlay keeps an oval around the middle of the screen clear and can be switched off in Settings (on by
   default); the physics blend between surfaces stays about 10 m while the look spreads over about ±20 m; braking on
   loose ground is 12-15 % shorter; walls along dirt and snow keep 55 % and 45 % of their friction.
   **Open**: the Known limitations above (Northern Lights and wall riding with the Vortex and Thunder, dirt braking
   close to asphalt, never seen on a real graphics card).
2. **Car upgrades.** **Done in v6.11.0** (see the status above and
   [How v6.11.0 was verified](#how-v6110-car-upgrades-was-verified)). The owner's pick: "Car upgrades: engine, tyres,
   nitro tank and dirt/snow grip, three levels each, so money is still useful once all six cars are bought." Choices
   made where the owner gave none: parts bought one level at a time and in order, on the car picker (asking first);
   engine +5 % torque, tyres +4 % asphalt grip, loose grip +5 % dirt and snow share a level, nitro +10 % tank and
   refill a level (more than the others: smaller did next to nothing); prices from the car's price ($12,000 for the
   Racer) × 10 / 20 / 35 % × the part's weight; medal times and AI opponents stay stock; the player's own AI drives and
   trains the upgraded car; the career reset makes every car stock; a cheap mark per part on the model.
   **Open**: the Known limitations above (records don't show their levels, the keyboard weave with tyres 3, no
   loose grip mark on the Drifter and Dune).
3. **Sound and music.** **Done in v6.12.0** (see the status above and
   [How v6.12.0 was verified](#how-v6120-sound-and-music-was-verified)). The owner's pick: "Sound and music: engine
   sound that follows the revs, tyre squeal, gravel and snow crunch, wall hits, nitro, music and volume sliders."
   Choices made where the owner gave none: the engines are synthesized live from the sim (no recorded loops, so the
   pitch is exactly the revs through every gear change), one character per car; the AI car you race is heard
   positionally and quieter, the best-run ghost is silent; electronic music, one menu track and three race tracks
   chosen by theme, quieter in a race and ducked under the finish panel; every file generated by
   `tools/gen_sounds.py` (no downloads: the free sound sites were unreachable from here, and self-made needs no
   licence); volumes Master 100 %, Music 70 %, Effects 80 %, Engines 80 % by default, muted in the background (on);
   Settings in two columns from 1100 px so the Audio rows fit 1280 x 720.
   **Open**: the Known limitations above (nobody has listened to it, the darker menu music, no pause ducking,
   Settings scroll at 1024 x 600).

## Next: the owner's nine features

The owner asked for these after the port, in this order. **All nine are done (v6.1.0-v6.9.0)**; what is left open
across them is at the end of this section ([All nine done](#all-nine-done-what-is-left-open)). For anything new,
confirm it with the owner first. Anything that touches the physics: keep `sim/` and `native/` in step, and re-run the
medal times.

1. **Two more cars with detailed models (spinning wheels, a moving driver).** **Done in v6.1.0.** The Dune (buggy:
   all-wheel drive, forgiving grip and gentle slides, soft landings, 222 km/h, the most `dirtGrip` for item 3) and
   the Vortex (hypercar: the most power, 321 km/h, light and twitchy, the smallest nitro tank, 3 s) are in
   `sim/cars.gd` with stats and medal times for all 12 tracks; the Racer is unchanged bit for bit. All six cars got
   new models (see Conventions): grooved tyres, spoked rims and brake discs that spin and steer with their calipers,
   wishbones (and coil-over springs on the Dune) that follow the wheels, a body that rolls, dives and squats
   with the sim's own g coefficients and sinks on landings, head and brake lights (real headlights at night and
   dusk, theme key `headlights`), panel lines, vents, mirrors, wings, exhausts and race numbers; a driver whose hands
   turn the steering wheel (two-bone arm IK), whose head looks into corners, whose body leans with the g, rocks on
   braking and bumps on landings, and who pumps a fist after the finish (`CarModel.celebrate()`). The menu picker
   shows three cards a row (two on narrow windows); the silhouettes come from `CarModel.profile`. Left for later
   items: buying cars and **starting with only the Racer** (item 5), the AI driving other cars (item 2, done in
   v6.2.0), dirt reading `dirtGrip` (item 3, done in v6.3.0).
2. **AI training with different vehicles.** **Done in v6.2.0.** The training screen's form and run view have a Car
   row of six tiles (`ui/car_chip.gd`; "gen N" marks a car with a saved network); the session trains that car on
   both paths (FleetSim gets the spec as data), and picking another car while training starts a new session, asking
   first when the best network is not saved yet. The sensors scale speed by the car's own top speed (Racer
   unchanged, `SENSOR_VERSION` 2). Every car has its own network in the save file (`SaveData.VERSION` 2) and network
   files name their car (`"car"`). The menu's AI block, Watch the AI and Race the AI ghost use the picked car's
   network and say so when there is none. `tools/headless_train.gd --car` trains any car with FleetSim. No
   pre-trained networks are shipped.
3. **Terrain such as dirt.** **Done in v6.3.0.** Three surfaces as data (`sim/surfaces.gd`): asphalt, dirt (each
   car's `dirt_grip` share of its grip, 3 × rolling resistance, softer tyres that slide sooner, 60 % stability
   control) and packed snow (`snow_grip`, the lowest grip, 2.2 × rolling resistance). Per axle and blended over
   about 10 m in `sim/car.gd` and FleetSim (bit for bit). Dirt on Ramp Rally (a rally stage over the jumps), Canyon
   Run (the gravel turnaround) and Mountain Pass (the valley road), packed snow on Hairpin Valley (over the ridge)
   and Mountain Pass (the summit); the other eight tracks are unchanged bit for bit. Dirt and snow road shader,
   no lines or kerbs on loose road, dusty / snowy barriers, dust and snow spray (pooled, scaled by quality), tyre
   marks in the surface's colour, a camera rumble, the surfaces on the menu's track panel. The Dune keeps 97 % of its
   grip on dirt and 72 % on snow and is the quickest car on Ramp Rally and Hairpin Valley; the Vortex keeps 55 % /
   42 %. New medal times for the four tracks; records, scores and ghosts are tagged with the track's signature and
   old ones archived (`SaveData.VERSION` 3). Drifts on dirt score as usual.
4. **Three new maps.** **Done in v6.4.0.** Tracks 13-15 after Seaside Stunts in `tools/gen_tracks.gd`, harder from
   one to the next: Forest Rally (★★★, 2.54 km circuit, 88 % dirt, two jumps, theme autumn), Northern Lights (★★★★,
   2.83 km circuit, 79 % packed snow in bowls banked 20-24°, a jump, theme arctic with the northern lights) and Summit
   Rush (★★★★★, 4.38 km sprint: asphalt, a dirt forest climb with two wide switchbacks, snow on the 18 m summit, a
   jump, dirt on the way down; theme highland, snow on the land beside the snowy road). No corner under a 39 m radius
   (the old hairpins are 13-19 m). Medal times for all six cars (`tools/medals.gd --update --tracks=...`, 588 s); the
   other 72 entries untouched. The menu's grid makes full rows (three rows of five at 15 tracks) and shortens the
   maps a little when three rows meet a short window, so 1280 x 720 shows everything without scrolling; keys 1-9,
   0, -, = still reach the first 12, the rest by arrows, mouse or pad (the tile's tooltip names the key when it has
   one). The snow spray is blue-grey (`spray` in `sim/surfaces.gd`) and bigger, so it shows on the white road.
5. **Money and points from beating medal times and AIs (more for more skilled AIs).** **Done in v6.5.0.** Money
   buys cars (a new player owns the Racer; Kestrel $10,000, Drifter $14,000, Dune $18,000, Thunder $22,000, Vortex
   $30,000, bought on the car picker: locked cards show a padlock and the price, Drive becomes BUY and asks first);
   career points are a total separate from the style score. Rewards (`sim/economy.gd` `REWARDS`): medals $300 / $500 /
   $800 / $1,200 and 10 / 20 / 40 / 80 points, beating the Rookie / Amateur / Pro / Expert / Elite AI $200 / $400 /
   $700 / $1,100 / $1,600 and 5 / 10 / 20 / 40 / 80 points, × (1 + 0.1 × track index); each paid once per track, car
   and medal or AI level, a medal paying the medals below it and a win the levels below it. AI opponents: one network
   per track and car (90, trained with FleetSim, `tools/opponents.gd --train`, in `data/opponents/`), five levels by
   speed cap (1.6 / 1.4 / 1.25 / 1.13 / 1.0 × the author time); the menu's AI block picks the opponent (or My AI);
   Race the AI is the AI ghost path; the finish panel lists the payout; the menu's header shows the money and points.
   `SaveData.VERSION` 4 with a `career` section; older saves are paid once for their medals (a message says how
   much) and own only the Racer. Not done (not asked): selling cars, prices per track, an AI that reacts to the
   player.
6. **Rework the tight corners on the old maps** (make them more forgiving). **Done in v6.6.0.** The corners chosen
   from a sweep of the medal autopilot (all 50 settings, six cars, `tools/corners.gd --sweep`) were the tightest
   ones, which it hit on 65-100 % of laps (most on 85 % or more): every hairpin (Canyon Run 13 m, Technical Trial
   15 m, Grand Marathon 16 m, Hairpin Valley 17 m and its 16 m switchbacks, Mountain Pass 18-19 m), the corners next to
   them on Grand Marathon and Canyon Run, Canyon Run's gravel turnaround and Hairpin Valley's snowy left off the
   ridge (the worst single corner: 2.5 wall hits a lap). All hairpins are now 24-25 m (switchbacks 22 m) on a road
   2-3 m wider; the straights next to them are shorter by as much as the turns grew (a 90° turn of radius r moves
   the road 1.4244 r forward and sideways, a hairpin 2.053 r sideways), so start, shape and surface stretches stay.
   Hairpin Valley's ridge corner kept its 40 m and got 15 m of road and 12° of banking instead: at 55 m the
   autopilot only arrived faster and slid further into the outer wall on the snow (twice the contact). Left alone on
   purpose: Technical Trial's 10 m chicane, Canyon Run's narrow canyons and S-bends (their character; the autopilot
   hits them about half the laps, as before), and the other ten tracks, whose tightest corners are 28 m or more.
   Medal times (`tools/medals.gd --update`), AI opponents (`tools/opponents.gd --train` and the levels) and
   signatures are new for the five; see "How v6.6.0 was verified". Not done: the bronze ratio (item 9).
7. **A terminal in Settings** for adding points, money and so on. **Done in v6.7.0.** Settings' Career section has a
   Terminal row (Open; the pad's A), and `` ` `` (the key under Esc) opens it on the menu and on Settings, never in a race
   (the Controls screen says so). A console in the game's style: log, input with a blinking caret, Up / Down history,
   Tab completion, Esc / `` ` `` / the pad's B to close; typing needs a keyboard. Commands (one table, `game/terminal.gd`):
   `help [command]`, `money <n>` / `money set <n>`, `points <n>` / `points set <n>`, `car <name> | all`, `buy <car>`,
   `unlock all | cars | tracks`, `status`, `reset career` (then `reset career confirm`), `clear`, `exit`; each prints
   what it did and the new value, saves through `SaveData` / `Economy.buy` and redraws the menu. Choices made for the
   owner: `buy` and `reset career` were added (buying with the terminal's money; a fresh start), amounts take commas
   and are capped at 1,000,000,000 a command, only `reset career` asks for `confirm` (setting money or points lower is
   an explicit command, not a wipe), `reset career` keeps best times, ghosts, networks and settings.
8. **Unlock the next map after bronze.** **Done in v6.8.0.** The next track unlocks after a bronze (or better) on the
   previous one, with any car; track 1 is always open; "previous" is the menu order. `sim/unlocks.gd` has the rule;
   the finish claims the next track (`Unlocks.claim`) and the save file keeps opened tracks for good in
   `career.tracks_open` (version 4 kept), so they are **sticky**: a faster bronze (item 9) or a changed track never
   locks one again. Choices made for the owner: an older save opens, once, every track it has a best time on (current
   or archived, any car) and the track after every bronze or better, archived times judged against today's bronze
   (the simpler rule); locked tracks can't be driven or raced against the AI (Drive, Race the AI and the training
   screen's Race best say what opens them), Watch the AI and Train the AI work everywhere (the panel says so); locked
   tiles have a padlock and "Bronze on 02", and the keys, pad and mouse still pick them; the finish panel says "Ramp
   Rally unlocked" and the new tile is NEW once; `unlock all` / `unlock tracks` open everything; `reset career` turns
   that flag off but keeps the tracks medals opened (including those won while the flag was on); the terminal's
   `status` row counts the open tracks and names the next one's requirement.
9. **Faster bronze.** **Done in v6.9.0.** Bronze is **1.3 × the author time (was 1.5 ×)**, still rounded up to a whole
   second (`Medals.FACTORS.bronze`). `tools/medals.gd` names the factors from `Medals.FACTORS` in medals.json's method
   line and has a new `--factors` mode that works gold, silver and bronze out again from the stored author times (no
   sweep: about a second); it rewrote the 90 bronze times and nothing else. `--js` (the browser comparison) compares
   only the medals whose factor is still the browser's (`Medals.WEB_FACTORS`): author, gold and silver, and says that
   bronze is left out. Choices made for the owner: medals stay worked out from best times, so old records re-rate
   themselves at once; tracks a bronze opened stay open and paid rewards stay paid (a v6.8.0 player whose 3:03 on
   Rookie Oval was bronze keeps Hairpin Valley and the $300, but has no medal there until a 2:39, which pays nothing
   new); the AI levels were not recalibrated (their measured times are where they were), only the Amateur's and the
   Pro's menu texts, which the new bronze made wrong or loose ("a little slower than bronze", "between silver and
   bronze pace"). The e2e `unlock` scenario's slow autopilot now takes 2:32.900 (13 m/s² corners, 50 m/s), and the
   `surfaces` snow-spray check counts the most puffs over 12 frames against a threshold scaled by the graphics
   quality (it was a coin flip with `gfx=low`).

### All nine done: what is left open

Every feature the owner listed after the port is built (v6.1.0-v6.9.0). Nothing is half done, but these are open
across them (details in [Known limitations](#known-limitations)):

- **Never seen on the owner's kind of machine.** Everything ran on Linux with software rendering (llvmpipe) and
  simulated input. The Windows `.exe` / `.dll` are built and zipped but were never started on Windows; no real graphics
  card (frame rates, the car models, headlights, dirt and snow shaders, the dust and spray), no real gamepad (the pad
  paths are tested with simulated events), no real keyboard layout for the terminal's `` ` `` key (a dead key on some
  Windows layouts), and the AI opponents' stored times were measured with Linux's maths library (Windows may differ
  by milliseconds; a win is judged against the race actually driven, so it stays fair).
- **No human play-testing.** The difficulty of every feature was judged with autopilots: the reworked corners (v6.6.0),
  the AI levels (v6.5.0; the Rookie may still be hard on long tracks), the prices and rewards (v6.5.0), Northern
  Lights' flat-out bowls (v6.4.0) and now the faster bronze, which a new career needs on Rookie Oval before anything
  else opens (v6.8.0 + v6.9.0). The owner should play the first tracks of a new career and say whether 1.3 × feels
  right; the factor is one number plus `tools/medals.gd -- --factors`.
- **Deliberate simplifications** the owner may want to revisit: one AI network per track and car, slowed down for the
  lower levels (they drive the same line, just slower); the AI does not see the road surface; rewards are paid per
  track id, not per track version; the terminal is a cheat with no limits; unlocks are generous when upgrading old
  saves; the NEW mark on a just-opened track lives only in memory.
- **Small known issues**: the menu's side column is 28 px wider while a track with a long surface line is picked;
  seven README screenshots show an older bronze in the HUD (and five of them the dirt and snow before v6.10.0); Technical Trial with the Racer differs from the browser
  by 1 s (a last-bit difference in a wall-grinding run); terrain noise differs from the browser's.
- **Waiting for the owner**: a licence for the project (none is chosen; no `LICENSE` file on purpose) and, if wanted,
  a release on GitHub with `TrackRush-6.10.0-windows.zip` (built locally, not in git).
