# Handoff notes

Status notes for whoever (person or AI agent) picks this project up next.
Read this first, then `README.md` for how things work.

_Last updated: 2026-10-25 (v5: the interface restyled; v4: four cars, nitro, points for clean driving, three new tracks, per-car best times, ghosts and medals)._

## Status: v5 complete

v1 covered the original request (racer, 6 tracks, neuroevolution AI, dashboard). v2 answered the owner's
second round (a better engine, realistic physics, longer and more varied maps, better assets), v2.1 let the AI
use the walls, v3 was the owner's third round of six improvements, and v4 is the fourth round: more maps, more
cars, nitro and points for clean driving (see "v4" below). v5 restyled the interface only (see "v5" below): no
physics, scoring, AI or saved-data changes.

| Area | State | Where |
| --- | --- | --- |
| Physics v2: two-axle tyre model, friction circle, weight transfer, downforce, 6-speed auto gearbox, AWD, handbrake drifting | done | `src/physics/car.js` |
| Keyboard stability: speed-sensitive steering lock + ESC-style yaw control (off with the handbrake) | done | `src/physics/car.js` |
| Walls: capsule vs real wall segments every sub-step, rebound capped at 1 m/s, no tunnelling; v3: hits and rubbing cost real speed, a pinned car can slide off | done | `src/physics/car.js`, `src/physics/collision.js` |
| Smooth track frame (no lateral/height jumps between segments, a cause of the v1 corner glitches) | done | `src/physics/collision.js` |
| Jumps: look-ahead take-off, ballistic flight, small air steering, no landing bounce | done | `src/physics/car.js` |
| 12 tracks, 2.2-7.2 km, varying width, height and banking, 7 themes (v4: Night Highway, Lighthouse Bay, Seaside Stunts and the `night` and `seaside` themes); sprints with run-off | done | `tools/generateTracks.mjs` → `src/tracks/trackData.js`, `src/game/scene.js`, `trackMesh.js` |
| Visuals: PBR + ACES, procedural sky + environment map, bloom, detailed car, smoke and skid marks, themed scenery, quality levels | done | `src/game/scene.js`, `trackMesh.js`, `carMesh.js` |
| v3: wall sparks (pooled, scaled by quality level) and chase-camera shake (off with reduced motion) | done | `src/game/carMesh.js`, `camera.js`, `scene.js` |
| v4: four cars (Racer = the v3 car, bit for bit; Kestrel, Thunder, Drifter) with their own specs, 3D models and measured stats; car picker on the menu | done | `src/physics/car.js`, `src/physics/cars.js`, `tools/carStats.mjs`, `src/game/carMesh.js`, `src/ui/menu.js` |
| v4: nitro (a tank per car, refilled by points; gauge, exhaust flames, camera kick) | done | `src/physics/car.js`, `src/game/carMesh.js`, `camera.js`, `input.js`, `src/ui/hud.js` |
| v4: points for clean driving (combo, drifts, air, close calls, wall and respawn penalties, clean lap and run bonuses), live HUD, finish breakdown, best score per track and car | done | `src/game/score.js`, `playMode.js`, `storage.js`, `src/ui/hud.js`, `menu.js` |
| v4: best times, ghosts (format 2, with the car and its nitro) and medal times per track and car; v3 data carried over as the Racer's | done | `src/game/storage.js`, `replay.js`, `tools/medals.mjs` → `src/tracks/medals.js` |
| AI v2: 18 inputs, mirrored driving, wall rules `ride` / `crash` (always the Racer, never nitro) | done | `src/ai/` |
| v3: Max-speed training in a Web Worker, with hand-over both ways and a fallback on the page | done | `src/ai/trainWorker.js`, `src/game/trainMode.js`, `src/ai/trainer.js` |
| v3: player ghost of the best run (record, pack, replay, G / Y toggle, menu option) | done | `src/game/replay.js`, `playMode.js`, `storage.js` |
| v3: gamepad (analogue driving, menu and training-screen navigation) | done | `src/game/input.js`, `src/ui/menu.js`, `trainMode.js`, `playMode.js`, `src/ui/hud.js` |
| HUD (gear, revs, next medal, nitro, score), menu (car picker, 12 tracks, keys 1-9, 0, -, =, medals; no scrolling from 1280x720 up) | done | `src/ui/`, `css/style.css` |
| v5: one design system (colour / type / spacing tokens, Barlow fonts), menu as 1 Track / 2 Car / 3 Drive with track minimaps and one track panel, Controls screen (H, ?, View) | done | `css/style.css`, `index.html`, `src/ui/menu.js`, `vendor/fonts/` |
| Fixed 60 Hz physics with render interpolation in every mode | done | `src/game/playMode.js`, `trainMode.js` |
| README, screenshots, `npm test` (72 checks), CI | done | `README.md`, `docs/`, `tools/selfTest.mjs` |
| Project licence | open: waiting for the owner (schiggy) to choose one, or none | add `LICENSE` + `"license"` in `package.json` + README section |

## v5: interface restyle (2026-10-25)

The owner asked: "is there a smart way to make the ui look less vibecoded?" The answer given, and built:

1. **One type system.** Barlow (text) and Barlow Condensed (headings, numbers, buttons), vendored as woff2 subsets
   in `vendor/fonts/` (four weights, 81,924 bytes, SIL OFL 1.1, `OFL.txt` beside them; the README licence section
   says so). Four text sizes (13 / 16 / 20 / 32 px, `--fs-s` ... `--fs-xl`) plus the big HUD numbers, tabular
   figures everywhere a number changes.
2. **A restrained palette as tokens** at the top of `css/style.css`: near-black and greys (`--bg-0` ... `--bg-4`),
   white / grey text (`--text`, `--text-2`, `--text-3`), one accent (`--accent`, the yellow), `--good` / `--bad`
   only for gains and losses (time deltas are now green / red, not blue / red), medal colours only for medals.
   No gradients; the only glow is the nitro gauge while it burns. Borders mostly replaced by spacing and panel tone.
3. **One shape language**: buttons, tags, step numbers and HUD plates are slanted (`--skew`, drawn by a `::before`
   so the text stays upright; the pad highlight follows the slant). The menu is three steps: **1 Track** (tiles
   with a minimap drawn at start-up from each track's centre line, number, name, difficulty bars, medal and best
   time for the picked car), **2 Car** (the cards with silhouettes and stat bars), **3 Drive** (Drive, the
   ghost option and the AI block). The selected track's details are in one panel: description, length and laps,
   then with the picked car the best time, best score, ghost, AI best and the medal times; in tall windows the
   panel also shows a bigger map. The key help moved to a **Controls** screen (button, **H** / **?**, **View** on
   a pad); the menu keeps one hint line (keyboard or pad, whichever was used last).
4. **The same tokens in the race**: HUD read-outs are small labels plus values on dark slanted plates, key hints
   are key caps, the finish panel, Max-speed overlay, pad notice, watch panel and training dashboard use the same
   panels, buttons and spacing (4 px grid, `--s1` ... `--s6`).

Behaviour kept: all element ids, keys (1-9, 0, -, =, numpad, arrows, C / Shift+C, Enter, Esc, G, R), gamepad
navigation (on the tiles the d-pad moves like the arrow keys; down from the bottom row goes to the cars, which
are now under the tracks; up from the top row goes to the Controls button), every menu action, the finish panel
content, training controls, reduced motion, quality levels, and the layouts (the menu fits without scrolling at
every size checked from 1280x720 to 1920x1080; narrower or shorter windows scroll, with Drive in a bar stuck to
the bottom below 1000 px wide).
Small changes: the HUD names the pad's Back / Start buttons View / Menu (their Xbox names), the pad notice is
shorter and points to the Controls screen, the HUD best time shows a dash until there is one, and in windows
under 1000 px wide the finish panel hides the best / medal / split rows it covers (it shows them itself).

Code: `css/style.css` (rewritten), `index.html` (menu, Controls screen, HUD labels), `src/ui/menu.js` (tiles,
`trackMap()` minimaps, track panel, Controls screen, pad navigation), `src/ui/hud.js` (labelled read-outs, key
caps, rev colours as classes), `src/game/playMode.js` (finish panel markup), `src/game/input.js` (? key, pad
notice), `src/ui/fitnessChart.js` and `networkView.js` (font and colours; the network's blue / red weight colours
are data and stay). The README screenshots menu, driving, training and network were retaken (cars.png has no UI).

## v4 (2026-10-25)

The owner asked: "make more maps and cars with different handling and stats add nitro and add a point system
for clean driving etc."

Defaults chosen (and announced to the owner before the work started):

- 3 new maps, 12 in all.
- 4 cars with different handling and stats. The existing car stays exactly as it was (the same physics, bit for
  bit, when nitro is not used) as the default car, the **Racer**, so its best times, ghosts, medals and trained AI
  networks stay valid. The other three have their own character: light and grippy, heavy and fast, loose and
  drifty. No real brand names.
- Nitro: a tank per car; holding the nitro control adds drive power while the tank lasts. Points from clean
  driving refill it, and every run starts with a full tank. The AI does not use nitro (its inputs are unchanged,
  so `SENSOR_VERSION` stays).
- Points for clean driving: clean checkpoints with a combo multiplier, drifts, air time and close calls,
  penalties for wall contacts and respawns, a clean-run bonus; shown live on the HUD, broken down on the finish
  panel, with a best score per track and car.
- Best times, ghosts and medals per track and car.

It was built in five parts by separate agents, then two independent reviewers checked everything (one with Node
scripts, one in a headless browser). A release pass fixed their findings, re-ran their scripts, re-did the
screenshots and wrote the docs (see "Review findings fixed in v4").

### 1. Cars and nitro physics

- `src/physics/car.js`: every car has a spec. `CAR` is the Racer (id `racer`) and is unchanged; `makeSpec(changes,
  base = CAR)` builds another car from it, `createCar(track, idx, spec = CAR)` uses it, and the constants derived
  from a spec are worked out once and cached. `PHYSICS_VERSION` stays 3. New car fields: `nitro` (tank, 0-1, full
  at `createCar`, kept by `placeCar`), `boost` (0-1, this step) and `boosting`; `addNitro(car, amount)` refills.
- Nitro (`ctrl.nitro`, true or 0-1) only works on the ground, in a forward gear, not while braking and not while
  the handbrake is held. It adds `min(nitroForce, nitroPower / speed)` of drive force, fading out over the last
  `nitroFade` 3 m/s below the car's `nitroTop`; a full tank lasts `nitroTime` (4-6 s). One tank is worth about
  0.3-0.5 s on a long straight.
- `src/physics/cars.js`: `CARS`, `CAR_IDS` (`racer`, `kestrel`, `thunder`, `drifter`), `DEFAULT_CAR`, `getCar(id)`;
  each car has a name, a one-line description, its look, its spec and its measured stats.
- `tools/carStats.mjs` (`npm run cars`, about 2.5 s) measures the stats with the real physics; `-- --check`
  fails when the numbers in `cars.js` are stale (`npm test` checks this too).

| Car | Mass | 0-100 km/h | 0-200 km/h (nitro) | Top speed (nitro) | Tank | 100-0 km/h | Grip 30 m / 120 m | Drift held |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Racer | 1,250 kg | 2.70 s | 9.78 s (7.57 s) | 277.7 km/h (291.8) | 5 s | 30.7 m | 1.68 / 1.58 g | 0.83 s |
| Kestrel | 950 kg | 2.43 s | 11.28 s (9.78 s) | 230.2 km/h (239.8) | 4 s | 27.7 m | 1.78 / 1.59 g | 0.75 s |
| Thunder | 1,650 kg | 2.68 s | 8.20 s (6.08 s) | 312.7 km/h (328.9) | 6 s | 33.8 m | 1.47 / 1.56 g | 1.07 s |
| Drifter | 1,150 kg | 2.50 s | 9.23 s (7.57 s) | 264.3 km/h (278.9) | 5 s | 33.1 m | 1.59 / 1.52 g | 1.63 s |

Balance (centre-line autopilot sweep and the medal times): the Kestrel is quickest on twisty tracks (Hairpin
Valley, Technical Trial, Canyon Run, Lighthouse Bay), the Thunder where the straights are long (Banked Speedway
by 4.3 %, where the Kestrel is 11.9 % slower than the Racer; Grand Marathon, Night Highway), the Drifter over the
jumps (Ramp Rally, Seaside Stunts), and the Racer is within 4.8 % of the best car everywhere.

### 2. Three new maps

`tools/generateTracks.mjs` (designs and the two new themes) → `src/tracks/trackData.js` and
`docs/tracks-overview.svg`; scenery in `src/game/scene.js` (themes `night` and `seaside`, star field, night
bloom) and `src/game/trackMesh.js` (coast, water, lighthouse, boats, palms, city skyline, glowing barrier stripes).

| Track | Type | Theme | Built for | Autopilot (no nitro) |
| --- | --- | --- | --- | --- |
| Night Highway | 3 laps × 3.12 km, 18 m wide | night | km-long straights into slow corners (R 28-45 m): nitro | 3:46.800 |
| Lighthouse Bay | 3 laps × 2.35 km, 17-18 m | seaside | long constant-radius bends (R 62-109 m): drifts | 3:15.917 |
| Seaside Stunts | sprint 3.02 km, 16 m | seaside | six kickers of 3.9-7.5 m with step-downs: air | 1:20.250 |

The menu has keys 0, - and = for tracks 10-12; it is now up to 1240 px wide with four columns of track cards
(fewer on narrow windows). The AI learns the new tracks quickly (80 cars, Crash out): first finish in generation
2-13 on Night Highway, 0-2 on Lighthouse Bay, 0-7 on Seaside Stunts. Draw cost on the new tracks (software WebGL,
1280x720, high quality): 88-139 draw calls and 440k-760k triangles.

### 3. Car picker, car models, nitro controls and effects

- Menu (`src/ui/menu.js`, `css/style.css`): four car cards above the tracks (side view, name, top speed, mass,
  five stat bars) and a line describing the picked car. Pick with a click (double-click drives), C / Shift+C, or
  RB / LB (or the d-pad up from the top track row). The choice is kept in `trackrush.settings` (`car`; junk
  gives the Racer). Drive and Race the AI ghost use the picked car; Watch the AI, the AI ghost and training are
  always the Racer.
- Models (`src/game/carMesh.js`, the Racer's unchanged): Kestrel a low open-cockpit roadster, Thunder a wide
  fastback with a big wing, Drifter a tall rally car with a roof scoop, light pod and mud flaps.
- Nitro on either Shift, pad X or RB (`src/game/input.js`). HUD: a ten-segment NITRO gauge above the speed that
  glows while boosting, turns amber below 25 % and reads EMPTY. Flames: a blue-white jet per exhaust and a
  pooled glow trail (64 slots a car, scaled by quality, nothing allocated per frame); ghosts show the jets too.
  Camera: up to +5° field of view and 0.6 m of pull-back at full boost, eased, off with reduced motion.

### 4. Points for clean driving

- `src/game/score.js` (no DOM, runs in Node): `new ScoreState(track, {nitro})`, `update(car, race, dt)` every
  physics step after `stepCar` and `race.update`, `respawn()`; `SCORE` holds every number and `SCORE_RULES` (1)
  tags saved best scores and the medal times. The rules are in the README ("Points for clean driving").
- New road only (release fix): drifts, jumps and close calls only score within `replayGap` (15 m) of the
  furthest point the car has reached, so a respawn or driving back can't farm them.
- Nitro refills: every 16,000 banked points put back one tank (`addNitro`); penalties take nothing out, and
  respawns and the finish bonuses refill nothing.
- HUD (`src/ui/hud.js`): SCORE with the combo under LAP / CP, a live line (drift / air / wall in progress), up to
  four popups. Finish panel: total, NEW BEST SCORE, breakdown and "Nitro earned". Best scores:
  `trackrush.scores.v1` `{trackId: {carId: {score, date, rules, physics}}}`.
- Clean autopilot runs: Rookie Oval 43,500 points and 2.13 tanks back per race; Night Highway 66,000 / 3.53;
  Lighthouse Bay 51,000 / 2.59 (75,870-83,160 / 4.15-4.60 with handbrake drifts); Seaside Stunts 23,980-25,160 /
  1.03-1.10. With the refills a nitro autopilot is 1.5-2.0 s faster on Rookie Oval, 2.4-3.6 s on Ramp Rally and
  Night Highway and 1.1-1.5 s on Lighthouse Bay than with one tank.

### 5. Best times, ghosts and medals per car

- `src/game/storage.js`: best times in `trackrush.records.v4` `{trackId: {carId: {time, splits, date, physics}}}`;
  `trackrush.records.v3` is read as the Racer's until the first v4 save copies it across (the v3 key is never
  written or removed). Ghosts in `trackrush.ghost.<track>.<car>`; the v3 ghost `trackrush.ghost.<track>` is read
  as the Racer's until a new Racer ghost replaces it (then it is removed).
- `src/game/replay.js`: ghosts store the car and its nitro (so replays show flames). Format 2 packs 15 bits a
  character (U+0800-U+87FF): about 8,500 characters a minute (format 1: 21,300, still read). 48 ghosts at bronze
  pace take about 1.67 M of the 5.24 M characters Chromium allows. When storage is full the ghost being replaced
  is removed and the save tried again; if that fails the finish panel says "Ghost not saved".
- Medals (`tools/medals.mjs` → `src/tracks/medals.js`) for every track and car. Method: the 50-setting
  centre-line autopilot of v3 (sideways grip it plans for × how far ahead it aims) drives exactly the race the
  player gets, with a full tank, nitro at full throttle while its steering is within 0.25 of straight, and refills
  from a real `ScoreState`. The author time is the fastest of the 50 finishes; gold, silver and bronze are author
  × 1.06, 1.2 and 1.5, rounded up to a whole second. `medals.js` is tagged with `MEDALS_PHYSICS` and
  `MEDALS_SCORE_RULES`, and `medalTimes(track, car, laps)` returns nothing when the layout, laps, physics or
  scoring rules don't match. Worker threads (`--jobs=N`, default one per core up to 4, identical result): 12-30 s
  on 4 cores depending on load, 39-48 s on one. The full table is in the README.
- Racer author times are 0.9-3.3 s faster than in v3 because the autopilot now uses nitro (Rookie Oval 2:01.867,
  was 2:04.083; Seaside Stunts 1:08.233 against 1:09.767 before nitro). Some author runs lean on walls (Thunder on
  Canyon Run 417 wall-contact steps, Racer on Technical Trial 284).
- Menu cards (best, medal disc, "· ghost", score) and the medal times by the title follow the picked car; HUD and
  finish panel use the car driven; the AI's finish panel compares with the Racer.

### Review findings fixed in v4

The Node reviewer found one major and four minor problems, the browser reviewer two minor ones. All seven are
fixed; none was rejected. Each was reproduced with the reviewer's own script first and re-checked with it after.

- **A respawn loop farmed points and free nitro** (major, `score.js`). A respawn puts the car back at the last
  checkpoint with its speed, and checkpoints sit 30-100 m before the kickers, so jump, land, respawn, repeat gave
  +1,100-1,350 air points a loop for −500. Before, 40 loops: Seaside Stunts 46,100 points and 3.98 tanks (clean run
  24,800 and 1.08), Ramp Rally 58,190 (35,990), Grand Marathon 57,080 (28,300), Technical Trial 26,290 (6,540),
  Canyon Run 14,760 (750). Fix: the scorer keeps the furthest point reached; drifts, jumps (by take-off point)
  and close calls only score within 15 m of it. After, 40 loops (Racer): Seaside Stunts 12,430, Ramp Rally 29,510,
  Grand Marathon 19,810, Technical Trial 6,220, Canyon Run 750, all with the clean run's air points (within 20 for
  both cars on all five tracks); putting the car 150 m back before the kicker instead (like driving back) scores
  within ±640 of the clean run; respawning after every drift on Lighthouse Bay 13,940 against 75,870 clean. The
  one small gain left (Drifter on Technical Trial, +1,270 over 40 loops against a clean 5,080, about 30 a loop)
  is not air (within 20 of the clean run) but the run going differently after the teleports.
- **A wall touch up to 0.4 s before a checkpoint also spoiled the next section and lap** (`score.js`): the
  contact stays open for the 0.4 s merge window. Before, a touch ending 0.08 s or 0.20 s before the lap line
  scored 23,910 against 28,460 for one ending a second before it. Now only a car still touching at the gate spoils
  the next section: 28,410 and 28,460. A second touch inside the merge window after the gate spoils the new
  section too.
- **Nitro burned while the handbrake was held**, even standing still (`car.js`): 2 s standing with both held
  boosted 120 of 120 steps, emptied the tank to 0.50-0.67 and crept 3-5 m. Now no burn and no push with the
  handbrake: 0 steps, tank 1.000, 0.00 m for all four cars (and 0 of 60 boosting steps at 100 km/h). The car stats
  and medal times did not move (`npm run cars -- --check` and `npm run medals -- --check` up to date).
- **Thunder's description said "planted in fast corners"** but its 120 m grip (1.56 g) is below the Racer's. It
  now reads "Heavy and brutal: the most power and top speed. Grips more the faster it goes; slow in tight
  turns." (its grip on a 30 m circle, 1.47 g, is the lowest of the four). It was also shortened so it fits the
  picker line at 800x600 and 844x390, where the first rewording was cut off.
- **Nothing pinned the Racer to v3** (`tools/selfTest.mjs`): the bit-for-bit check compared v4 with nitro off to v4.
  Now block 4e hashes the Racer's state every 600 steps over two minutes of autopilot (Hairpin Valley, Ramp Rally)
  and a minute of seeded random controls on Canyon Run (811 wall-contact steps, 444 with the handbrake), and
  compares it with a stored hash, `b9f58c60`. The v3 code, v4 before the fixes and v4 now all give `b9f58c60`;
  changing `mu` or `mass` by one part in 10^12 changes it.
- **The finish panel ran into the bottom HUD on short windows** (`css/style.css`, `src/ui/hud.js`): the score
  block makes it 120-140 px taller, and at 1024x600 it covered the nitro gauge and speed (more at 915x412 and
  844x390; at 800x600 the FINISH popup). Now the panel is drawn above the HUD, the speed, gear and rev bar, nitro
  gauge and key hints are hidden while it is open, the panel is compact below 700 px of height, and below 520 px
  it is smaller still and the top HUD rows are hidden too (`hud.js` no longer forces the rev bar visible). Checked
  at 1920x1080, 1366x768, 1280x720, 1280x600, 1024x600, 800x600, 915x412, 844x390 and 390x844 with the reviewer's
  worst case (20 lines): the panel is inside the window and nothing overlaps it (844x390: 54-336 px of 390).
- **Driven tracks lost their score on the menu cards at mid widths** (`src/ui/menu.js`, `css/style.css`): with a
  ghost, "Your best · ghost" pushed the score column out at about 760-1240 px wide (800x600: Rookie Oval's 43,500
  not shown). Now, when any card is too tight, all cards switch to short labels ("Best · ghost", "AI lap") and
  slightly smaller numbers, and only a card that still doesn't fit drops its score. Checked at the five sizes,
  1024x600, 1366x768 and every 20 px from 740 to 1240 wide: driven tracks keep their score everywhere, also a
  worst-case card (medal, ghost, AI time, 7-character score).
- Found during the release pass: at 801-860 px of height (1280-1920 wide) the menu scrolled by up to 41 px; the
  compact menu layout now applies up to 860 px. No scrolling from 1280x720 to 1920x1080.

**`SCORE_RULES` stays 1.** v4 has not been released, so no saved scores exist outside test browsers; a run that
doesn't respawn, drive back or touch a wall right before a gate scores exactly the same as before (the clean
autopilot runs above and all four browser test runs give identical totals), and the medal times are unchanged.

### How v4 was verified

- `npm test`: 72 checks, all pass (26 s on the release machine). New in v4: cars and nitro (the Racer is the
  default and pinned to the v3 hash, nitro off is bit-identical, the stats match the physics, every car finishes
  all 12 tracks with 0 wall-contact steps, rebound at most 1.00 m/s, 864 wall shots per car at nitro top speed
  + 10 % with 0 escapes, 72,000 random steps with nitro and 0 NaN, the nitro rules including the handbrake, 0 of 36
  keyboard fishtails per car, 120 jumps with 0 bounces or spins); the car models build; the score is exact,
  repeatable, rewards drifts and jumps, refills nitro and can't be farmed (30 respawns before kickers on Seaside
  Stunts bank 7,120 air, the clean run's 7,120) and the gate rule; medal times for all 48 track and car pairs
  with Seaside Stunts reproduced to the millisecond for every car; records, ghosts and scores per car with v3
  data carried over and junk ignored.
- `npm run medals -- --check` and `npm run cars -- --check`: up to date; `node tools/generateTracks.mjs --check`:
  all 12 tracks pass the design rules.
- Node review: the Racer bit-for-bit v3 over 324,000 steps, no spec leaks between cars, seeded training identical
  to v3, 192,000 fuzz steps with nitro (0 bad), 120 kicker runs at top speed with and without nitro, 96 score fuzz
  runs, v3 → v4 migration with real pre-v4 saved data, 1,200 ghost codec round trips, ghost sync through 7-25
  respawns within 2.8 cm. Its scripts were re-run after the fixes: the farming, gate and handbrake cases are fixed;
  the Racer is still bit-for-bit v3, the score fuzz holds every invariant and repeats exactly, and close calls,
  weaving and spinning in place give the same results. The other changes are the intended ones: Thunder, which
  touches walls near gates, scores more in the air script (Ramp Rally 9,490 → 11,040, Coastal GP 3,590 → 5,280;
  same jumps), the Drifter's best "donut" in a 29 m circle drops from 9,272 to 5,160 points in 50 s, and random
  driving banks fewer drifts and close calls, since it keeps going over the same road.
- Browser review and release smoke test (headless Chromium, software WebGL, seeded with real v3 saved data):
  each car driven to the finish twice, the second time against its ghost (Racer Rookie Oval 2:31.583 and 43,500
  points; Kestrel Lighthouse Bay 3:04.083, 51,000; Thunder Night Highway 3:39.233, 66,000, 3.5 tanks back; Drifter
  Seaside Stunts 1:16.883, 31,120), with nitro burn and refill, flames only while boosting, the FOV kick, gauge
  states, a deliberate wall hit and a respawn, breakdowns that add up and medals that match `medals.js`; Race the
  AI ghost (Thunder against the Racer AI: the AI never boosts); Watch the AI (no gauge, no score, no record);
  training at 1× and Max (in the worker) and back, Watch best and Race best. No console errors or warnings.
  Layouts at 1920x1080, 1280x720, 800x600, 390x844 and 844x390 (plus the sizes above).
- Not verified: how the cars, the nitro and the points feel to a human on a real keyboard or gamepad; anything on
  a real GPU; storage in Firefox and Safari.

## v3 (2026-10-20)

The owner asked for six improvements, in this order:

1. wall hits cost more speed, for every car;
2. Max-speed training runs on a background thread;
3. sparks and camera shake on wall hits;
4. a ghost of the player's own best run;
5. medal times per track;
6. gamepad support.

Each was built by its own agent, then two independent reviewers (one with Node scripts, one in a headless
browser) checked all six. Their findings and how they were dealt with are listed under "Review findings fixed
in v3".

### 1. Walls cost more speed (physics v3)

`src/physics/car.js`, `CAR` constants and `PHYSICS_VERSION = 3`:

- A hit takes `(wallFriction + wallCrush × jn) × jn` of the speed along the wall, where `jn` is the speed into
  it (m/s): `wallFriction` 0.5 (v2: a flat 0.28) and the new `wallCrush` 0.06, so hard hits cost far more than grazes.
- New rub: while touching a wall the car loses `wallRub` 15 % of its sliding speed per second, building up over
  `wallRubBuild` 1 s of contact.
- `wallAlignGain` 12 (was a hard-coded 4) lines the nose up with the wall faster; `wallLatchSteps` 10 (was 6)
  keeps `hitWall` from flickering (at most 4 switches in 3 s).
- New `wallSlide` 5 m/s (a review fix, see below): below that sliding speed the hit friction fades out, so a car
  its own drive presses nose-in against a wall can slide and steer off.
- New car fields for effects: `wallImpact` (m/s of speed into a wall removed in the last step), `wallScrape`
  (sliding speed along the wall while touching), `wallX/Y/Z` (latest contact point, bumper height),
  `wallNx/Nz` (that wall's normal). `createCar` and `placeCar` reset them (so restart and respawn do).

What hits cost now (coasting, compared with the same car without the wall; v2 in brackets): 5° at 150 km/h
−16 to −18 km/h [−8 to −10]; 10° at 150 km/h about a quarter of the speed [about a tenth]; 15° at 200 km/h about
half [15 %]; 30° at 180 km/h, 45° and head-on stop the car [30° kept about two thirds]. Grinding along a wall at
full throttle settles at 87-97 km/h [160-220]. Rebound is still at most 1.00 m/s, there is no tunnelling, and
every non-wall number is unchanged (0-100 km/h 2.70 s, top speed 277.7 km/h, 100-0 km/h in 30.7 m,
skidpad 1.6-1.7 g).

Does the racing line pay now? (Autopilot comparisons, `/tmp/wallride/aggr.mjs` and the walls agent's
`adaptive.mjs`; not part of the repo.)
- Hairpin Valley: the best clean autopilot (81.6 s a lap) beats the best wall-hitting one (82.2 s) and one that
  never brakes (85.3 s). In v2 never braking was 68.6 s, 16 % faster than clean.
- On the other 8 tracks a fixed-target autopilot that touches walls is still 1.5-5.6 % faster than the best
  clean fixed-target one (v2: 7-16 %). Against an autopilot that learns where to slow down, the clean car wins on
  8 of 9 tracks (+0.1 to +1.8 %; Rookie Oval −0.8 %), and never braking is 1.2-8.2 % slower on every track.
- Full throttle with no steering at all now finishes all 9 tracks but 24-63 % slower than a clean autopilot
  (Hairpin Valley 1:41.2, v2: 1:15.7, which was faster than clean).

The AI was retrained on the final physics (80 cars, 100 generations, one track each):

| Track | `ride` | `crash` |
| --- | --- | --- |
| Hairpin Valley | first finish in generation 0, lap 1:12.9 (v2 1:05.5); 0 % braking, wall 11-13 % | generation 44, 1:27.1 (v2 1:29.5); braking 26 % |
| Technical Trial | generation 0, 1:13.3 (v2 1:07.7); braking 1.8 %, wall 7 % | generation 20, 1:23.3 (v2 1:27.6); braking 24 % |
| Canyon Run | generation 0, 1:27.5 (v2 1:18.4); 0 % braking, wall 7-8 % | generation 8, 1:30.6 (v2 1:33.8); braking 25 % |
| Mountain Pass | generation 0, finish 1:46.1 (v2 1:39.6); 0 % braking, wall 6 % | generation 8, 1:59.0 (v2 1:59.6); braking 17 % |

**The `ride` AI still uses the walls instead of braking.** It brakes in 0-2 % of steps (full throttle 76-100 % of
the time) and turns the hairpins off the outside wall, hitting it at up to 17-20 m/s. The gap to `crash` is about half of v2's, but
braking did not come back: a dead stop at a hairpin wall costs only about 0.7 s, so the wall is still a
stronger brake than the tyres. Every physics-only variant tried (more crush, more rub, a knock on contact, a
drive cut while touching, an engine cut after hard hits) still gave 0 % braking. The remaining lever is the
training-penalty option measured in v2.1 (a fitness cost per second of wall contact in `ride`: a cost of 8/s
brought braking back to 22.7 % of steps on Hairpin Valley). The owner chose costlier walls for everyone, not
that penalty, so it was not added. The `ride` networks also beat some author times (Hairpin Valley 3 laps
3:33.7-3:34.9 against 3:47.967; Mountain Pass 1:46.1 against 1:49.583): they drive a far better line than the
centre-line autopilot that sets them, as well as using the walls.

**Networks trained before v3 should be retrained**: they still load (the AI inputs didn't change, so
`SENSOR_VERSION` and the network storage key stay), but they learned walls that cost almost nothing.

### 2. Max-speed training on a background thread

At Max (and not paused) `trainMode.js` hands the whole session to a module Web Worker (`src/ai/trainWorker.js`)
with `Trainer.exportState()`. The worker trains in 25 ms slices and sends live stats and the shown network 8
times a second, plus a message after every generation, which keeps the page's copy of the trainer current
(population, best network, chart history, best times), so autosave, Save, Watch, Race and the seed info all
work during Max. Another speed, Pause, Watch / Race or leaving the screen asks for the session back, and it
returns mid-run exactly as the worker left it. Every hand-over has a run id; messages from a stopped or replaced
run are ignored. If the Worker API is missing, the worker can't load or it fails (or doesn't answer within 5 s),
Max simulates on the page as before and a note says so.

Measured in headless Chromium (software rendering, 1280x720, same seeded random numbers both ways):
generations per minute +8 to +43 % against the old on-page loop on a quiet machine; frame times median 16.7 ms,
p95 16.7-16.8 ms, no long tasks (on-page loop: median 33-50 ms, p95 50-100 ms). A hand-over costs the page
2-8 ms to send and 3-12 ms to take back; the session is about 533 KB (80 cars). The only long frames (about 1 s)
come right after switching to Max: they are the software renderer finishing 3D frames it was already given,
not our code.

### 3. Sparks and camera shake

- `carMesh.js`: a pooled `Sparks` effect (one instanced mesh, nothing allocated per frame): thin orange
  streaks that fall, bounce low off the road, cool to red and live 0.2-0.65 s. A hit of 3 m/s or more into the
  wall gives a burst of min(64, 8 + 3 × impact) sparks; scraping faster than 3 m/s gives a stream.
  `wallEvents()` counts new contact steps from `car.wallHits`, so bursts are right at any frame rate (checked at
  30, 60 and 144 fps). The player's car has a pool of 160; the training fleet shares one pool of 240 with at most
  40 new sparks a frame; ghosts make none. `scene.js` scales sparks with the quality level (high 100 %,
  medium 65 %, low 30 %).
- `camera.js`: the chase camera gets a short "trauma" shake on hits (impact / 22, fading at 1.5 per second;
  at most 16 cm sideways and 1.3° of roll) and a light rumble while scraping above 8 m/s. It is applied on top of
  the smoothed pose, so it never feeds back, and it is off when the system asks for reduced motion.
- Cost: 0.03-0.04 ms a frame for the fleet's sparks with 80 training cars.

### 4. Player ghost

- `src/game/replay.js` (no DOM): records poses, not inputs, every 2nd physics step (30 Hz), plus the steps on
  both sides of a landing or wall hit, respawns (never interpolated across) and the finish. 8 channels
  (position 1 cm, angles 1 mrad, wheel angle, wheel speed), predicted and stored as differences: exactly 9 bytes a
  sample, about 21 KB per minute of racing. It replays within 2.5 cm of the run at every physics step (0.8 cm at
  the samples). `unpackGhost` refuses anything that doesn't match the track layout, laps or physics, and never throws.
- `playMode.js` records every human run (Drive and Race the AI ghost) on its own race clock (physics steps since
  GO). A new personal best saves its ghost, which races from the next restart (a ghost still racing is not
  swapped mid-race). It is drawn only (light blue, no collision), fades near the player's car and the camera,
  and disappears after its finish. G / Y toggles it; the menu option "Race my best-run ghost" is the same setting.
- Storage keys (`storage.js`): best times moved to `trackrush.records.v3` and are tagged with `PHYSICS_VERSION`
  (v2 times are not read: they may have been set by riding the walls); `trackrush.ghost.<track id>` holds one
  ghost per track; `trackrush.settings` holds `{ghost: true|false}`. The network key stays
  `trackrush.network.v2`. All reads are validated, junk is ignored. If the browser refuses to store a ghost, the
  old one is removed and the finish panel says so. Nine five-minute ghosts take about 0.9 MB of the usual ~5 MB.

### 5. Medal times

- `tools/medals.mjs` (`npm run medals`, about 8-10 s; `-- --check` compares only) drives exactly the race the
  player gets in Drive with a deterministic look-ahead autopilot over 50 settings (sideways grip it plans corners
  for, 14-40 m/s², × how far ahead it aims) and writes `src/tracks/medals.js`. The author time is the fastest
  finish; gold, silver and bronze are author × 1.06, 1.2 and 1.5, rounded up to a whole second.
  `medalTimes()` returns nothing unless the physics version, layout and laps match, so stale medals are never shown.
- Author times: Rookie Oval 2:04.083, Hairpin Valley 3:47.967, Ramp Rally 2:54.867, Banked Speedway 2:04.133,
  Technical Trial 3:46.583, Grand Marathon 2:32.133, Coastal GP 3:09.600, Mountain Pass 1:49.583, Canyon Run 4:17.950.
- Menu: a medal disc on each card (from the stored best time; nothing else is stored) and the selected track's
  four times next to the title. HUD: the next medal to aim for, fixed for the run, crossed out once missed and
  ticked when won. Finish panel: the medal earned (NEW if better than before) and the next one.

### 6. Gamepad

`src/game/input.js` (the class keeps its name, `Keyboard`, so `main.js` is unchanged) also polls gamepads with
the standard mapping, once per frame just before the frame's update. Left stick steers (dead zone 0.12, full
lock at 0.96 of travel, curve exponent 1.5, so half travel ≈ 0.30 steer), RT / LT are analogue throttle and
brake / reverse, A handbrake, B respawn, Back restart, Y ghost, Start menu, d-pad steers like the arrow keys.
Pad buttons are codes next to the key codes (`consume('KeyR', 'PadBack')`). With keyboard and pad both in use,
each control takes the stronger input; with no pad (or an idle one) the output is exactly the old keyboard
output (checked over thousands of steps against the old `input.js`). The menu and the training dashboard have a
pad highlight (A presses, B back); the race HUD shows pad button names while the pad is the last input used.
A pad without the standard mapping still works, with a note that some buttons may differ.

### Review findings fixed in v3

Both reviewers found no major problems. Their minor findings:

- **A car pinned nose-in against a wall could stay stuck** (Node review). Steering away at full throttle took
  up to 17.5 s at 85° and more than 20 s beyond; at half throttle (easy with an analogue trigger) 60° already
  took 17 s. The v3 wall friction held the car once its own drive pushed it into the wall. Fixed with
  `CAR.wallSlide` (the friction fades out below 5 m/s of sliding). Now, at full throttle with full lock away, every
  angle from 50° to 87.5° comes off in 0.2-1.8 s; at half throttle 50-60° take 0.3-1.3 s and 65-77.5° 3.8-16 s,
  and 80° or more still needs reversing (there the tyres can't push the car sideways; v2 was the same from 70°).
  After a real hit, steering away at full throttle takes 0-0.5 s up to 60° and 2.2 s head-on (before: 1.2-1.3 s
  at 60°, head-on needed reversing). Nothing else moved: the autopilot comparisons, the AI replays, the medal times and every
  coasting hit cost are identical, because the fade only acts below 5 m/s along the wall. One visible
  consequence: a car held nose-in at full throttle without steering now creeps along the wall instead of
  stopping, so the no-steering car finishes all 9 tracks (slowly) instead of 4. `npm test` has a new check
  (a car pressed nose-in at 45-85° steers off at full throttle within 3 s on every track; worst 1.62 s).
- **G (or Y) before any ghost existed turned ghosts off for good** without saying so (both reviews). Now it only
  shows "No ghost yet: set a best time first" (or, for a best time whose ghost couldn't be kept, "No ghost: beat
  your best to save one") and leaves the setting alone; if ghosts are off when a best run is saved, the finish
  panel says how to show it.
- **The training view's camera sometimes shook when the leader changed** to a car that hadn't hit anything
  (browser review: 18 false shakes in 2006 leader changes, some at full strength). The chase camera's contact
  bookkeeping now restarts when the shown car changes: 0 false shakes in 1980 leader changes, 793 real ones kept.
- **After Stop + Start at Max, the dashboard showed the previous session** for 1-4 s until the worker's first
  numbers arrived (browser review). The new session's numbers, network and "Viewing" line are now drawn at once:
  0 stale samples.
- A comment in `input.js` said half stick travel gives 0.35 steer; it is 0.30.

### How v3 was verified

- `npm test`: 44 checks, all pass (12-28 s; the Hairpin Valley training check takes a random number of
  generations). New in v3: walls cost speed (30° at 180 km/h loses at least half of it within 0.5 s; measured
  99 %), no sticking nose-in, a clean Hairpin Valley lap beats never braking, a Max-speed session handed to the
  worker and back three times ends in exactly the same state as one that never moved, a recorded ghost replays
  within 1.8 cm and 19 kinds of broken saved data are ignored, every track has medal times and the Rookie Oval
  author run still drives exactly 7445 steps. The reviewers broke the code on purpose four ways (trainer
  hand-over, ghost respawn, ghost clock, wall friction) and each was caught by the intended check.
- `npm run bench` ends with "CHECK THE NUMBERS ABOVE" on the machine used for v3: its slowest track runs 80 AI
  cars at about 32× real time against a target of 40× (average 36-40×, 1.3 µs per physics step). The v2 code
  measures the same on that machine, so the machine is slower than in earlier runs; v3 itself costs no speed.
  Its wall-hit table and sanity checks (0 non-finite states, 0 cars outside the walls) are fine.
- Node review: 77,760 wall shots at 8-100 m/s on all tracks (0 escapes, 0 NaN), 360,000 random-control steps,
  a fake-DOM harness driving the real training screen and worker hand-over through 88-451 random clicks (final
  state identical to a session that never moved), ghost replays on 5 tracks within 1.5 cm, medal regeneration
  byte-identical, gamepad edge cases (unplugging mid-press, two pads, junk values).
- Browser (headless Chromium, software WebGL): every mode played through with injected autopilots and scripted
  key presses and gamepads: Drive with personal bests, ghost saving, racing and toggling on Rookie Oval and
  Mountain Pass; medals on the menu, HUD and finish panel; sparks and shake at the right place (and none from
  ghosts); Watch AI; Race the AI ghost; training at 1×, Fast and Max with every hand-over path (speed changes,
  Pause, Save, Watch, menu, Stop + Start, multi-track, Load network); a full race on the gamepad alone; layouts at
  1920x1080, 1280x720 and 800x600; reduced motion and `?gfx=low`. No console errors or warnings. Re-run after
  the review fixes: the few checks those scripts mark as failing are bugs in the scripts themselves (text read
  after CSS capitalises it, the HUD or dashboard read before the next frame has drawn it, a few seconds of
  real-time play being only a handful of frames in software WebGL, a rounding limit, a HUD line "overlapping"
  the box it sits in); each was re-checked against the game's own state and is fine.
- Not verified: how anything feels or looks in motion on a real GPU and screen, frame pacing on real hardware,
  and real gamepads (only a scripted standard-mapping pad; non-standard mappings, e.g. some pads in Firefox on
  Linux, are untested).

## v2 (2026-10-15)

After playing v1, the owner asked for a better engine, more realistic physics, more varied and longer maps,
less bouncing, no glitching in corners, 3 extra maps and higher-quality assets. v2 did all of that (physics v2,
smooth track frame, jumps, 9 redesigned tracks with sprints, new visuals, AI v2 with 18 inputs, HUD and menu
updates, fixed 60 Hz physics with interpolation). It was built in separate physics, tracks, visuals and AI
passes, then checked by three independent reviewers (physics feel, browser visuals, code integration). Their
findings were fixed as listed below, and a second round of reviewers then checked those fixes (one more issue
found and fixed: the post-finish swerve).

### Review findings fixed in v2

- **Keyboard fishtail** (major): quick left-right key steering at 200+ km/h could build up a pendulum and spin the car.
  Fixed with a speed-sensitive steering lock and ESC-style yaw control. Keyboard-bot lane keeping: 0 of 36 runs fishtail
  (16 of 36 before); a keyboard bot drives all 9 tracks with 0 wall contacts and 0 spins.
- **Sprint finish wall** (major): sprints ended 10 m after the finish line, so every finish crashed into the end barrier.
  Now there are 250 m of straight run-off and the car brakes to a stop after about 170 m. After the finish the car
  steers along its own line, so a finish while scraping a barrier no longer swerves into the opposite one.
- **Air steering** (major): holding a key in the air spun the car on landing (up to 169°). Air steering is now a small
  correction; holding a key for a whole jump lands the car at most about 28° off line, with no spins.
- Minor: no more invisible walls above the barriers in mid-air; rotation into a wall is removed over a few sub-steps
  (no hitch while scraping); `hitWall` no longer flickers while scraping; respawns and sprint starts no longer put the
  camera under a gate; Max-speed multi-track training no longer rebuilds the 3D track it doesn't draw; continuing
  training from a network trained on other tracks no longer hides new progress; the graphics governor also reacts to
  very slow machines and `low` quality really draws less (thinning scenery evenly); dusk tracks are brighter; the ghost car is no longer X-ray;
  training cars stacked on the grid no longer flicker; the menu, Max overlay and watch panel fit small windows;
  the training screen follows the track picked on the menu; the drift tip in the help text is corrected; descriptions of Coastal GP and Canyon Run match their scenery.

## v2.1: the AI may use the walls (2026-10-18)

The owner asked: "make the ai be able to crash into the wall to preserve speed". Training now has a **Walls** setting
(`walls` in `src/ai/trainer.js`, `--walls` in `tools/headlessTrain.mjs`, a select on the training screen):

- `ride` (new default): a car that hits or scrapes a wall keeps driving; the stall, backwards, too-slow and time
  rules still remove cars that get stuck. The AI learns to carry speed into corners and slide along the outside wall.
- `crash`: the old rule, a wall touch puts the car out, so the AI learns clean, braking lines.

Saved network files record the rule (`settings.walls`); files saved before it existed count as `crash`, and a saved
fitness only counts as "best ever" when the tracks, laps and wall rule all match.

Measured then (physics v2; see v3 above for the current numbers), 80 cars and 100 generations per track, `ride`
vs `crash`: Hairpin Valley lap 1:05.5 vs 1:29.5, Technical Trial 1:07.7 vs 1:27.6, Canyon Run 1:18.4 vs 1:33.8,
Mountain Pass 1:39.6 vs 1:59.6. The `ride` AI kept full throttle about 99.5 % of the time and never braked,
because v2 walls cost so little speed that even a car held at full throttle with no steering finished almost every
track. Two options were measured for an AI that still brakes: a fitness cost per second of wall contact in `ride`
(cost 8/s brought braking back, 22.7 % of steps on Hairpin Valley, at a 1:14.1 lap), or costlier walls for everyone.
The owner chose costlier walls (v3, improvement 1).

Also in v2.1: the training screen and menu show the wall rule a saved network was trained with and warn when
continuing it under the other rule (its old best fitness doesn't carry over); `headlessTrain` rejects an unknown
`--walls` value; the training view no longer draws cars stacked inside each other (a trained `ride` pack drives the
same line along the walls), so fewer cars may be drawn than "Cars alive" counts.

## How it was verified (v2, still true)

- `npm test`: every track builds and the autopilot finishes it with 0 wall-contact steps
  (Rookie Oval 2:37.500 … Canyon Run 5:03.083); a 30° wall hit at 50 m/s rebounds at most 1.00 m/s;
  1008 wall shots at 300-360 km/h, 0 escapes; 54,000 random-control steps, 0 NaN;
  AI inputs in range and mirror-symmetric; training learns Rookie Oval (generation 1-3) and Hairpin Valley
  (`crash`, typically generation 8-60; it is random); a saved network drives the identical lap after loading;
  v1 network files are refused.
- Physics numbers (`npm run bench` and review scripts): 0-100 km/h 2.70 s, top speed 277 km/h, 100-0 km/h in 30.7 m,
  skidpad 1.6-1.7 g; 80 AI cars simulate at roughly 40-50× real time in Node.
- Browser (headless Chromium with software WebGL, via Playwright): every track driven start to finish by an injected
  autopilot, Watch AI on every track, ghost race, training at 1×, Fast and Max (including multi-track Max), and
  1920×1080, 1280×720 and 800×600 layouts. No console errors or warnings.

**Not verified:** how the car *feels* on a real keyboard or gamepad at 60+ fps, and frame rate on a real GPU.
The headless browser renders in software, so its frame rates say nothing.

## Known limitations

- **v4 was tuned with autopilots only**: the car balance, nitro strength, points and refill rates come from
  autopilot runs; no human has driven the four cars, the nitro or the points yet.
- **Medal times come from a simple nitro autopilot** (centre line, nitro whenever the steering is nearly
  straight), so a good player with a real racing line and better nitro timing can beat gold and even the author
  time. They have not been tried by a human player yet.
- **Some old Racer best times earn one medal less**: the Racer's medal times are 0.9-3.3 s faster than in v3,
  because the autopilot that sets them now uses nitro.
- **Jumps can be overshot with nitro**: at each car's top speed with nitro, Seaside Stunts flights reach 180-247 m
  and land 168-244 m past the lip, while the landing slopes end 58-80 m past it. Landings are still clean (no
  bounce, no NaN, never stuck), but some carry into the next corner (for example the Drifter, 240 → 41 km/h in one
  wall hit). From a normal run-up (120 m out) take-offs are 150-199 km/h, close to the 145-187 km/h without nitro.
- **No headlights at night**: Night Highway is lit by its lamps and the glowing barrier stripes only.
- **Storage was measured in Chromium only** (5.24 M characters a site; 48 ghosts at bronze pace about 1.67 M).
  A browser that counts stored bytes as UTF-8 would need 26.3 KB a minute for a format 2 ghost (21.9 KB for
  format 1); Firefox and Safari were not tried. Clearing site data loses everything; there is no export.
- The Drifter slides more, so it also scores drift points in normal fast cornering; scores are kept per car, so
  this only matters when comparing cars.
- One wall touch costs the combo and the clean lap and clean run bonuses, often 10,000-15,000 points in all. That
  is on purpose (clean driving pays), but it may feel harsh.
- Close calls measure the gap to the wall from the track's centre-line frame, so on tight curves they are approximate.
- A drift that starts, or a jump that takes off, on road already driven (more than 15 m behind the furthest point
  reached) scores nothing, even if it carries on onto new road.
- Car specs are not tagged in saved data, only `PHYSICS_VERSION` is: changing the Kestrel, Thunder or Drifter in
  `cars.js` keeps their old best times and ghosts (bump `PHYSICS_VERSION`, or add a per-car tag).
- The AI only drives the Racer and never uses nitro; its speed input is scaled by the Racer's `CAR.maxSpeed`.
  Every car has the Racer's collision capsule.
- Thunder and Racer have the same Rookie Oval medal times by chance (both author runs take 7,312 steps).
- Watch the AI shows the Racer's best time as BEST, with no car named. Key hints show on touch phones (there are no
  touch controls). At phone width (390 px) every car's description line is cut short (the full text is in the
  tooltip). At 800x600 the sticky menu action bar is see-through.
- The menu unpacks each ghost of the picked car on every redraw; fine for 12 tracks, it would need a cache for
  many more.
- New scenery, car models and nitro flames were only seen in software rendering; sea glare can look blocky
  (half-resolution bloom).
- Tight hairpins (16 m radius) are taken at about 55-65 km/h; the grip is realistic for a sports car, so they are slow corners.
- Long held drifts are hard: handbrake slides last about 1-2 s before the car grips up again (the Drifter holds
  them longest, about 1.6 s with a keyboard). Above about 100 km/h the speed-sensitive steering lock also stays on
  during a handbrake slide; lifting it while stability control is off (one line after the `wf` smoothstep in the
  steering block of `src/physics/car.js`) gives longer fast slides but more spins after long handbrake pulls in
  hairpins. Decide this on a real keyboard.
- Walls cost real speed since v3 (a 5° touch at 150 km/h about 16-18 km/h, 15° at 200 km/h half the speed, 30° at
  180 km/h stops the car; grinding settles at about 90 km/h, about 115 km/h with nitro held), but they still pay on
  twisty tracks for a driver who never brakes: a stop against a hairpin wall costs only about 0.7 s. A
  fixed-target autopilot that touches walls is still 1.5-5.6 % faster than the best clean one on 8 of 9 tracks
  (Hairpin Valley: clean wins by 0.8 %), and the `ride` AI never brakes on Hairpin Valley (0 %, wall contact
  11-13 %). If that should change, the measured lever is a fitness cost per second of wall contact in `ride`
  training (`src/ai/trainer.js`, see v2.1); making brief grazes cost much more would also hurt players. The points
  now give players a reason to stay off the walls.
- A car pinned nose-in against a wall at 80° or more (a near head-on stop) can't be driven off at part throttle;
  full throttle with the wheels turned away takes up to about 2 s, reversing 0.2-0.3 s, Enter respawns.
- While scraping nose-first, a corner of the car body can overlap the barrier by up to about 0.4-0.5 m, because the
  collision capsule is shorter than the drawn body.
- `wallLatchSteps` 10 keeps `hitWall` on for up to 0.17 s after the last real contact while the car stays within
  12 cm of the wall; that slightly raises `ride`'s "touched a wall" counts (no effect on `crash`).
- Tracks cannot cross themselves (no bridges/loops): walls are tested on the ground plane.
- Training uses 1 lap from a standing start by default, so a network trained on a single track can scrape walls on
  flying laps 2-3 when watched. Training on several tracks, or with 3 laps, helps.
- The menu's "AI best" times come from training runs (1 lap by default), not full 3-lap races.
- Changing physics constants in `src/physics/car.js` or a car in `cars.js` makes medal times and the car stats
  stale (and, for the Racer, trained networks drive worse): run `npm run cars`, `npm run medals` and retrain. Bump
  `PHYSICS_VERSION` when saved best times and ghosts should no longer count.
- Saved data: v3 best times and ghosts are read as the Racer's; best times saved by v1 and v2 are ignored (new
  storage key, physics tag); v1 networks are refused, v2 networks load but should be retrained.
- Max on the background thread was measured in headless Chromium with software rendering only. Right after
  switching to Max the page can stall for about a second there while the renderer finishes old 3D frames; on a real
  GPU this should be short, but it was not measured.
- The first switch to each theme bakes an environment map; fast on a real GPU, but not measured there.

## Ideas for future work (none were requested)

Roughly in order of value:

1. **Tune the feel with a real keyboard and gamepad**: the `CAR` constants at the top of `src/physics/car.js`
   (steering `steerRefAccel` / `steerExtraFast`, stability control `escGain`, grip `mu`, `handbrake` /
   `handbrakeFast`, the wall and nitro constants), the other cars in `src/physics/cars.js`, the points in `SCORE`
   (`src/game/score.js`), the key ramp `STEER_KEYS` and the stick / trigger curve `PAD` in `src/game/input.js`.
   Then `npm run cars` and `npm run medals`.
2. **Sound**: engine note from `car.rpm`, tyre squeal from `car.slip`, a nitro whoosh from `car.boost`, wall
   crunches and scrapes from `car.wallImpact` / `car.wallScrape`, checkpoint and score beeps (Web Audio, no assets
   needed).
3. **AI training with the other cars** (and with nitro): give the trainer a car spec, scale the speed input by
   that car's top speed, and keep a network per car. Nitro would need a third output, so new network files.
4. **Night headlights** for Night Highway (two spot lights or a projected texture on the road; watch the cost at
   low quality).
5. **Touch controls** for phones and tablets (the menu already fits 390x844 and 844x390).
6. **Export and import** of best times and ghosts as a file, like networks, so they survive clearing site data
   and can be shared.
7. **A braking `ride` AI**, if wanted: the wall-contact fitness cost measured in v2.1 (`src/ai/trainer.js`).
8. **Coastal GP on the seaside theme** now that it exists (it still uses dusk).
9. **Track editor** in the browser that writes the same `[x, z, height, bank, width]` format (then `npm run medals`).
10. **A per-car tag in saved data** (for example a hash of the spec), so changing a car retires its old times
    without touching the others.
11. **Bridges / loops**: would need 3D-aware track location in `src/physics/collision.js` (search by height as well as x/z).

## Conventions to keep

- Physics, race, track, replay, scoring and AI code must stay free of DOM and rendering code, so it runs in Node
  (`npm test`, headless training, `npm run medals`, `npm run cars`, the training worker).
- Three.js is imported by relative path from `vendor/` everywhere. The bloom add-ons in `vendor/addons/` import `"three"`,
  which the import map in `index.html` resolves; only browser code (`src/game/scene.js`) may use them, never Node code.
- Coordinates: forward = `(sin yaw, cos yaw)` on x/z, left = `(cos yaw, -sin yaw)`, positive yaw change = left turn, positive steer = left.
- Physics runs at a fixed 60 Hz everywhere; the AI is trained and replayed at the same step, and ghosts are recorded
  and replayed on the race clock (physics steps since GO).
- Built-in tracks are edited in `tools/generateTracks.mjs`, then `npm run tracks` regenerates `trackData.js` and checks
  the design rules; then `npm run medals` regenerates the medal times.
- The Racer must stay the v3 car: `npm test` compares its state with a stored hash (`RACER_V3_HASH` in
  `tools/selfTest.mjs`). If the Racer is changed on purpose, update the hash and bump `PHYSICS_VERSION`.
- After changing a car in `src/physics/cars.js`, run `npm run cars` and paste its `stats:` lines, then `npm run medals`.
- If the AI's inputs change meaning, bump `SENSOR_VERSION` in `src/ai/sensors.js` so old network files are refused.
- If the physics changes, run `npm run medals`, and bump `PHYSICS_VERSION` in `src/physics/car.js` when old best
  times and ghosts should stop counting.
- If the points change so that old best scores are no longer comparable, bump `SCORE_RULES` in `src/game/score.js`
  (old scores are then ignored) and run `npm run medals` (the medal times are tagged with it).
- UI: use the tokens at the top of `css/style.css` (colours, `--fs-*` sizes, `--s*` spacing, `--skew`) rather than
  new values; red / green only for losses / gains, the accent for the one thing that matters on a screen, no
  gradients or glows (the burning nitro gauge is the exception), `font-variant-numeric: tabular-nums` on numbers
  that change. A new track gets its menu minimap automatically.
- Run `npm test` before committing.
