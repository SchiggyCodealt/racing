# Handoff notes

Status notes for whoever (person or AI agent) picks this project up next.
Read this first, then [README.md](README.md) for how the game works and how to run everything.
The history of versions 1-5 (the browser game) is in [web/HANDOFF.md](web/HANDOFF.md).

_Last updated: 2026-10-28 (v6.1.0: feature 1 of 9, two more cars and detailed car models with a moving driver;
v6.0.0 was the port from the browser to the Godot 4.7 engine)._

## Status: v6.1.0, feature 1 of 9 done (two more cars, detailed models)

The owner (on Windows, not a programmer by trade) asked to "port it to an engine", and listed nine new features
for after the port (see [Next](#next-the-owners-nine-features)). v6.0.0 was the port: the Godot game does
everything the browser game v5.0.0 does, plays the same and looks at least as good. v6.1.0 adds feature 1: the
**Dune** (a soft, forgiving buggy) and the **Vortex** (a light, twitchy hypercar), and new models for all six cars
with spinning and steering wheels, suspension, head and brake lights, body detail and a driver who steers, looks
into corners, leans and pumps a fist at the finish. The Racer is unchanged bit for bit, so old records, ghosts and
networks still count. Features 2-9 are not built yet; nothing was designed out of them (the car list, medal
ratios, settings rows and track list are data).

| Area | State | Where |
| --- | --- | --- |
| Game logic without graphics: tracks (builder, collision), car physics and nitro, the six cars, race timing, points, ghosts, medals, save file, autopilot | done; the four browser cars checked number for number against the browser version, the Dune and Vortex (v6.1.0) by tests and the medal sweep | `sim/`, `data/tracks.json`, `data/medals.json` |
| 3D world: track mesh, terrain and scenery for 7 themes, sky, lighting, glow, car models, smoke, skid marks, sparks, nitro flames, chase camera, AI fleet, sensor rays, quality levels (high / medium / low) | done, compared with v5 screenshots at 14 moments | `world/` |
| Car models (v6.1.0): one skinned mesh per car (17 bones) with spinning / steering wheels, suspension, head and brake lights, panel lines, a driver who moves; headlights at night and dusk; a cheaper level of detail on low and for the AI fleet | done, checked by tests and screenshots (software rendering only) | `world/car_shapes.gd`, `world/car_build.gd`, `world/car_kit.gd`, `world/car_model.gd`, `world/shaders/car*.gdshader` |
| Interface: menu (1 Track / 2 Car / 3 Drive; six car cards, three a row from a 780 px wide picker), Controls and Settings screens, HUD, finish panel, pad navigation, Barlow fonts | done, layout checked at 6 window sizes | `ui/`, `assets/fonts/` |
| AI: network, evolution, sensors and driver, trainer (walls ride / crash, multi-track), training screen with 1× / Fast ×6 / Max on a background thread | done, lockstep-identical to the browser version | `ai/`, `modes/train_mode.gd`, `ui/train_*.gd` |
| FleetSim: the C++ GDExtension that steps the whole population (sensors, network, physics, rules) on several threads | done, bit-identical to the GDScript simulation; Linux and Windows libraries built | `native/`, `bin/`, `trackrush.gdextension` |
| Game shell: modes (menu, Drive, Race the AI ghost, Watch the AI, training), keyboard and gamepad, threaded track loading, quality governor, fullscreen / vsync, network files, messages | done | `main.tscn`, `game/`, `modes/` |
| New in the Godot version: Settings screen (quality, fullscreen, vsync, interface size, ghost), native file dialogs for networks, the save file instead of browser storage | done | `ui/settings_screen.gd`, `game/app.gd`, `sim/save.gd` |
| Tests: headless suite (437 checks), end-to-end tests of the real game, CI | done | `tests/`, `.github/workflows/test.yml` |
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
| Medal times | `tools/medals.gd` (50 autopilot runs per track and car) | 47 of 48 identical; Technical Trial with the Racer 3:45.083 against 3:44.033 (see Known limitations). The v6.1.0 sweep for six cars left the 48 old entries unchanged |
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
  `ROWS`, with an `action` row type for a terminal), the tracks (`data/tracks.json`), the themes (`world/themes.gd`).
- **Car models are made in code and are only looks**: nothing in `sim/` reads them. `world/car_shapes.gd` holds each
  car's shape as data (body sections, wheel places, wing, cockpit, suit and glove colours; the paint comes from
  `look` in `sim/cars.gd`), `world/car_build.gd` turns a shape into one skinned mesh per car and detail level
  (`CarKit` triangles tagged with a bone and a material kind, cached), and `world/car_model.gd` poses its 17 bones
  every frame from the car state (body, 4 uprights, 4 spinning wheels, steering wheel, driver torso / head / arms,
  rear flap). One opaque and one glass surface: 2-4 draw calls a car whatever the detail. To add a car: an entry in
  `sim/cars.gd` (spec, look, description; `tools/car_stats.gd`, `tools/medals.gd`), a shape in `car_shapes.gd`, then
  look at it with `tests/visual/car_studio.gd`.
- **Version tags** decide what old saved data still counts: `Car.PHYSICS_VERSION` (3: best times, ghosts, medals),
  `ScoreState.SCORE_RULES` (1: best scores, medals), `Sensors.SENSOR_VERSION` (2: network files), `SaveData.VERSION`
  (1), ghost format 3. Bump the right one when old data should stop counting; re-run `tools/medals.gd` after any
  change to the physics, a car, the points, a track or its laps, and `tools/car_stats.gd` after changing a car.
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
- **Technical Trial, Racer**: the medal autopilot's best run grinds a wall for 281 steps, and a last-bit difference
  turns into a different finish: 3:45.083 here against 3:44.033 in the browser, so gold / silver / bronze are 3:59 /
  4:31 / 5:38 (browser 3:58 / 4:29 / 5:37). Lockstep from the JS states reproduces every step, so it is not a port
  bug. All other 47 track-and-car medal sets are identical.
- **Terrain noise differs**: the terrain uses Godot's FastNoiseLite, statistically like the browser's noise but the
  hills are in different places. The road, walls and scenery rules are the same.
- **Track building is slower** (0.8-1.7 s against 0.16-0.45 s in the browser); the menu builds on a worker thread so
  the orbit never stops, and a race waits for its track.
- **GDScript physics is about 40× slower than the browser's JS**: fine for playing, but `tools/medals.gd` takes about
  35 minutes for six cars on 3 cores (`--jobs=3`; it only writes `data/medals.json` after a full sweep) and
  `tools/car_stats.gd` about a minute (52 s for six cars on 4 threads).
- **Car models and headlights were only ever seen through software rendering** (llvmpipe): the headlight
  brightness (high: two spotlights a car, medium: one, low: a glowing pool on the road), the panel lines and the
  driver's colours were tuned on screenshots from it. The low-quality headlight pool looks blocky up close.
- **The Vortex is the fastest car on every track and the Dune the slowest** by the medal autopilot (the Dune's
  strength, grip on dirt, is a `dirtGrip` field that nothing reads until feature 3 adds dirt).
- A ghost car on High and Medium now costs about 16,500 triangles (was about 10,600) because it is the full model
  in the ghost material (on Low about 6,700); it is 2 draw calls instead of 38.
- **The Linux training library needs glibc 2.38** (Ubuntu 24.04 or newer); on older Linux the game falls back to
  GDScript training. The Windows DLL needs only `KERNEL32.dll` and `msvcrt.dll`.
- The AI trains and drives the Racer only, never uses nitro, and its speed input is scaled by the Racer's top speed
  (`Sensors.SPEED_SCALE` 77 m/s). `Trainer` already accepts a `car_id` (and `tools/headless_train.gd --car`), but
  the training screen has no car choice yet.
- Best times are not tagged with the track's layout (ghosts and medals are, with `BuiltTrack.signature()`): changing a
  track keeps its old best times. Tag records with the signature before reworking tracks (see Next, item 6).
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
   items: buying cars and **starting with only the Racer** (item 5), the AI driving other cars (item 2), dirt
   reading `dirtGrip` (item 3).
2. **AI training with different vehicles.** Add a car choice to the training form (`ui/train_dashboard.gd`), pass it
   as `car_id` to `Trainer` (FleetSim already takes any spec through `set_spec`), scale the speed input by the
   chosen car's top speed (a new `SENSOR_VERSION`, or keep 77 for the Racer), store the car in the network file's
   metadata, and let Watch the AI / Race the AI ghost use the network's car instead of always the Racer.
3. **Terrain such as dirt.** Default: **dirt sections with less grip and dust**. A per-sample surface in the track
   data (for example ranges of samples or checkpoints marked `dirt` in `tools/gen_tracks.gd`), a surface array on
   `BuiltTrack`, a grip factor in `sim/car.gd` (where `_surface_env` reads the road under the car) and the same in
   `native/src/car_sim.cpp`, a dirt road material in `world/track_mesh.gd` and dust in `world/car_effects.gd`. Old
   tracks without dirt keep their numbers; tracks that get dirt need new medal times.
4. **Three new maps.** Design them with the turtle in `tools/gen_tracks.gd` (the design rules check them), maybe on a
   new theme in `world/themes.gd`, then `tools/medals.gd`. The menu grid is 6 columns, so 15 tracks make a third row:
   check the menu still fits at 1280x720 without scrolling (`ui/main_menu.gd`, `tests/visual/ui_preview.gd`); keys
   1-9, 0, -, = reach 12 tracks, the rest by mouse, arrows or pad.
5. **Money and points from beating medal times and AIs (more for more skilled AIs).** Defaults: **money buys cars
   (start with the Racer); points are a career total** (separate from the per-run style score); **AI opponents from
   Rookie to Elite, harder ones paying more**. Needs: new save fields (money, career points, owned cars, rewards
   already paid per track / car / medal so they are paid once) in `sim/save.gd` with `VERSION` 2 and a migration,
   a data-driven reward table, AI opponents as shipped networks of rising skill (train them with
   `tools/headless_train.gd`, put them in `data/`), racing them through the existing Race the AI ghost path
   (`modes/play_mode.gd`), the payout on the finish panel, money and points on the menu, and a car shop on the car
   picker.
6. **Rework the tight corners on the old maps** (make them more forgiving). The hairpins have a 13-19 m radius
   (Canyon Run 13 m, Technical Trial 15 m, Grand Marathon 16 m, Hairpin Valley 17 m, Mountain Pass 18-19 m) and are
   taken at about 55-65 km/h: widen the radius or the road there in `tools/gen_tracks.gd`. Changed tracks need new medal times and invalidate old ghosts automatically, but old best
   times would stay: first tag records with `BuiltTrack.signature()` (see Known limitations) and ignore or archive
   records of a changed layout.
7. **A terminal in Settings** for adding points, money and so on. Default: **in Settings and on the ` key, with
   commands like `money 5000`, `points 200`, `unlock all`**. The Settings screen already has an `action` row type
   (`ui/settings_screen.gd`, emits `action(key)`); the menu input names keys like the browser (`ui/menu_input.gd`
   `key_code`), so add `KEY_QUOTELEFT` as "Backquote" there. Commands should go through the same save functions as
   the game (item 5) and print what they did.
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
