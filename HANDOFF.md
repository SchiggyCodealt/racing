# Handoff notes

Status notes for whoever (person or AI agent) picks this project up next.
Read this first, then [README.md](README.md) for how the game works and how to run everything.
The history of versions 1-5 (the browser game) is in [web/HANDOFF.md](web/HANDOFF.md).

_Last updated: 2026-10-29 (v6.5.0: feature 5 of 9, money and career points from medals and AI opponents, a car
shop; v6.4.0: feature 4, three new tracks on three new themes; v6.3.0: feature 3, road
surfaces: dirt and packed snow; v6.2.0: feature 2, AI
training with every car; v6.1.0: feature 1, two more cars and detailed car models with a moving driver; v6.0.0 was
the port from the browser to the Godot 4.7 engine)._

## Status: v6.5.0, features 1-5 of 9 done (two more cars and detailed models; AI training with every car; dirt and snow; three new tracks; money, points and AI opponents)

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
Features 6-9 are not built yet; nothing was designed out of them (the car list, medal ratios, settings rows, track
list, surfaces, rewards and AI levels are data).

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
| Tests: headless suite (640 checks), end-to-end tests of the real game, CI | done | `tests/`, `.github/workflows/test.yml` |
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
| Medal times | `tools/medals.gd` (50 autopilot runs per track and car) | 47 of 48 identical; Technical Trial with the Racer 3:45.083 against 3:44.033 (see Known limitations). The v6.1.0 sweep for six cars left the 48 old entries unchanged. (v6.3.0 put dirt and snow on four tracks, which have new times; the parity scripts compare the all-asphalt versions, `Tracks.build_asphalt`) |
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
- **Static types everywhere** (typed GDScript is much faster, and `:=` on an untyped value is a parse error here).
  Tabs, snake_case, PascalCase classes; `class_name` only for types other folders need. After adding a
  `class_name`, run `godot --headless --path . --import` once before running scripts.
- **Data, not code**, where the next features will grow: the cars (`sim/cars.gd` `CARS`), medals (`sim/medals.gd`
  `ORDER` / `FACTORS`, stored with the times in `data/medals.json`), the settings rows (`ui/settings_screen.gd`
  `ROWS`, with an `action` row type for a terminal), the tracks (`data/tracks.json`), the themes (`world/themes.gd`),
  the road surfaces (`sim/surfaces.gd` `DEFS`: physics and look columns; FleetSim gets the physics columns from
  `Trainer.track_data`, the road shader has colour slots for table entries 1 and 2; v6.4.0 added the optional look
  column `spray`, the colour of what the tyres throw up), the rewards (`sim/economy.gd` `REWARDS`, `TRACK_STEP`), the
  car prices (`price` in `sim/cars.gd`; 0 = owned from the start) and the AI levels (`sim/opponents.gd` `LEVELS`:
  id, name, pace, blurb; a new level also needs an `ai-<id>` reward and a `tools/opponents.gd` run).
- **Road surfaces** are marked in the track designs (`tools/gen_tracks.gd`, turtle `.surface("dirt")` ...
  `.surface("asphalt")`; the design rules want stretches of 60 m or more and the start grid on asphalt). A track
  without them has no `"surfaces"` key and an empty `BuiltTrack.surf_w`, and every surface branch in `sim/car.gd`,
  the autopilots and FleetSim is skipped for it: keep it that way, so asphalt tracks stay bit-identical.
  `Tracks.build_asphalt(id)` is a track with its surfaces stripped (the browser's version, for the parity tools and
  the web checks in `tests/test_sim.gd`).
- **Track signatures**: `BuiltTrack.signature()` is "count:length" (the layout) plus "|dirt168-730,..." when the track
  has surfaces; `Tracks.signature(id)` caches it. Records, best scores and ghosts store it as `sig`; an entry whose
  `sig` is not the track's current one is archived when the save is loaded (`SaveData._archive_stale`).
  `Tracks.LEGACY_SIGS` holds the v6.2 signatures for untagged (version 2) entries: never change it. Changing a track
  (layout or surfaces) therefore retires its old records by itself; re-run `tools/medals.gd --update --tracks=<id>`.
- **Tracks are appended, never edited in passing** (v6.4.0): menu order is `data/tracks.json` order, the first 12
  are the browser's, and `tests/test_sim.gd` pins every track's signature (`SIGS`), the text of the first 12 entries
  (a SHA-256 of `tools/gen_tracks.gd`'s output for them) and their medal entries (`V63_MEDALS_SHA`), and runs the
  design rules on all of them. A new track: its turtle program after the last one in `tools/gen_tracks.gd`, its
  theme's name in `THEMES` there, `tools/medals.gd --update --tracks=<id> --jobs=3`, then add its signature to `SIGS`.
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
  medals), `Sensors.SENSOR_VERSION` (2: network files), `SaveData.VERSION` (3: track signatures on records and
  scores, the archive; `_migrate` upgrades versions 1 and 2; 4 (v6.5.0): the `career` section, started once from the
  medals held when it is missing), ghost format 3, the track signatures above, FleetSim's
  `version()` ("trackrush-native 3": road surfaces; 2 scaled the sensors by the spec's `max_speed`). Bump the right one when old data should stop counting; re-run `tools/medals.gd` after any
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
  / `pay_rewards(...)`; `Economy` builds the payouts, the prices and `buy()` on top. Item 7's terminal should call
  `add_money`, `add_points` and `give_car` (they write the file) and refresh the menu. The paid list is per track id
  and car, not per track signature (see Known limitations).
- **AI opponents are data made by a tool**: `data/opponents/<car>.json` holds, per track, the network (the web
  game's file format), the track signature it was trained on, and each level's `{cap, time}` (cap in m/s, null =
  none). `Opponents.entry()` refuses an entry whose `physics` or `sig` no longer match, so a changed track or physics
  shows "No ... AI here" until `tools/opponents.gd --train --retrain --tracks=<id>` and a levels run. The race an
  opponent drives (`ai/opponent_race.gd`) is the play mode's AI ghost loop step for step (drive, step, race update,
  stuck after 3 s: respawn standing); change one, change both, and `tools/opponents.gd --check` must say every stored
  time is reproduced. Caps are stored as k / 100.0 so they read back as the same double (`snappedf` does not).
- **The interface is built in code** from the tokens in `ui/ui_style.gd` (colours, four text sizes, 4 px spacing
  grid, one slant); red / green only for losses / gains, the yellow accent for the one thing that matters.
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
- **Rewards are paid per track id, not per track version**: when item 6 reworks a track, its records move to the
  archive (signature) but its paid medals stay paid, so beating the new medal times pays nothing for medals already
  paid. Decide with the owner whether a reworked track pays again (then key `paid` by signature in `SaveData`).
- **The AI opponents are a single network per track and car held to a lower top speed**, not different drivers: the
  slow levels take every corner at the same capped speed (the Rookie is very steady), they never use nitro, and with
  walls ride they lean on walls in tight corners like the trained networks do. Elite is the network flat out where
  that is about the author time, else capped to it (on about half the track-and-car pairs; the networks are up to
  17 % faster than the author time on Hairpin Valley, where they ride the walls). The opponents' cars don't collide
  with yours and don't react to it.
- **The Rookie may still be hard for a brand-new player on long tracks**: it takes 1.6 × the author time, slower
  than bronze (1.5 ×, 1.3 × after item 9), but it doesn't crash or make mistakes.
- **Technical Trial, Racer**: the medal autopilot's best run grinds a wall for 281 steps, and a last-bit difference
  turns into a different finish: 3:45.083 here against 3:44.033 in the browser, so gold / silver / bronze are 3:59 /
  4:31 / 5:38 (browser 3:58 / 4:29 / 5:37). Lockstep from the JS states reproduces every step, so it is not a port
  bug. All other 47 track-and-car medal sets are identical.
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
- **The AI does not see the surface**: its 18 inputs are unchanged (`SENSOR_VERSION` 2); a network learns where the
  dirt is on the tracks it trains on. A Racer network trained on an all-asphalt track brakes too late on snow.
- **Surfaces were only seen through software rendering** (llvmpipe): the dirt and snow colours, the border noise,
  the dust and spray density were tuned on its screenshots. The snow spray (v6.4.0: blue-grey `spray` colour in the
  surface table, bigger and denser puffs) shows on the white road there; on a real screen it may need another look.
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
- The AI never uses nitro. Its speed input is scaled by each car's `CarSpec.max_speed`, a round figure near the
  measured top speed (the Dune's 61 m/s against 61.8 measured, so its speed input can reach 1.01; the Vortex's 91
  against 89.3). Changing a car's `max_speed` changes what its networks see: treat it like a sensor change.
- Networks trained with `tools/headless_train.gd --car` before v6.2.0 have no `"car"` field and read as Racer
  networks; load them with that car picked on the menu (they then drive it, with a note), or add `"car": "<id>"`
  to the file.
- A network loaded from a file trained with another car drives the picked car as it is; the game says so but does
  not stop it, and it usually drives worse than the car's own network (see the v6.2.0 verification).
- There is no "reduce motion" option (the browser followed the system setting): the camera shake on wall hits and
  the nitro kick are always on (`ChaseCamera.reduce_motion` exists, nothing sets it).
- Browser saves (localStorage) can't be carried over; AI network files can, both ways.
- No track overview map is generated (`web/docs/tracks-overview.svg` still shows the same tracks).
- The file dialogs for networks are the system's native ones and were only exercised through code, not clicked.
- `TrackBuilder.get_gates()` caches gates for unusual lap counts lazily and is not thread-safe for those (the game
  only uses each track's own lap count, which is built up front).
- From the browser version, still true: medal times come from a simple centre-line autopilot (a good driver can beat
  author); car balance, nitro and points were tuned with autopilots, not people; with Walls:
  Ride them the AI uses walls as brakes on twisty tracks; tracks can't cross themselves (no bridges). See
  web/HANDOFF.md for the full list.

## Next: the owner's nine features

The owner asked for these after the port, in this order. The defaults below were already announced to the owner;
confirm anything else before building it. Several touch the physics: keep `sim/` and `native/` in step, and
re-run the medal times.

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
6. **Rework the tight corners on the old maps** (make them more forgiving). The hairpins have a 13-19 m radius
   (Canyon Run 13 m, Technical Trial 15 m, Grand Marathon 16 m, Hairpin Valley 17 m, Mountain Pass 18-19 m) and are
   taken at about 55-65 km/h: widen the radius or the road there in `tools/gen_tracks.gd`. Changed tracks need new
   medal times (`tools/medals.gd --update --tracks=...`); since v6.3.0 their old best times, scores and ghosts stop
   counting and move to the save file's archive by themselves (track signatures, see Conventions). Keep the surface
   stretches in place when reworking Hairpin Valley, Mountain Pass and Canyon Run (`.surface()` calls in the designs).
7. **A terminal in Settings** for adding points, money and so on. Default: **in Settings and on the ` key, with
   commands like `money 5000`, `points 200`, `unlock all`**. The Settings screen already has an `action` row type
   (`ui/settings_screen.gd`, emits `action(key)`); the menu input names keys like the browser (`ui/menu_input.gd`
   `key_code`), so add `KEY_QUOTELEFT` as "Backquote" there. Commands should go through the same save functions as
   the game (item 5: `SaveData.add_money(n)`, `add_points(n)`, `give_car(id)`, each returning the new value or
   whether it changed; then `app.ui.menu.refresh()`) and print what they did.
8. **Unlock the next map after bronze.** Default: **the next track unlocks after a bronze (or better) on the previous
   one, with any car**. Track 1 is always open; "previous" is the menu order (`data/tracks.json`). It can be derived
   from the saved best times (`Medals.medal_for` per car), so nothing new needs saving except the terminal's
   `unlock all`. Locked tiles need a look on the menu, and the keys / pad must skip or refuse them. Decide with the
   owner whether Watch / Train the AI may use locked tracks.
9. **Faster bronze.** Default: **bronze = 1.3 × the author time (was 1.5 ×)**, still rounded up to a whole second.
   Change `Medals.FACTORS.bronze` and the method text in `tools/medals.gd` (it names the factors); the bronze times in `data/medals.json` can be
   recomputed from the stored author times (`Medals.medal_set`) without the 20-minute sweep. Medals are worked out from
   best times when shown, so saved records re-rate themselves; the medal parity check against the browser version no
   longer applies to bronze.
