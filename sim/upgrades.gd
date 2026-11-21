class_name Upgrades
extends RefCounted
## upgrades.gd: car upgrades (v6.11.0; v6.16.0: ten levels; v6.21.0: the weight part): five parts
## per car, ten levels each, bought in order with the career's money on the car page (or with the
## terminal's `upgrade`).
## ------------------------------------------------------------------
## An upgraded car is its stock spec (sim/cars.gd) with a few numbers scaled, so everything that
## takes a CarSpec (sim/car.gd, the autopilots, FleetSim through Trainer.spec_data) drives it with
## no change of its own. Levels 1-3 add `step` × the stock value each to what the part changes
## (as in v6.11-6.15, bit for bit); levels 4-10 add less and less (LEVEL_GAIN: 0.8, 0.7 ... 0.2 ×
## step), so level 10 is 6.5 × step over stock:
##   engine  the torque curve (+5 % a level: more power everywhere, so quicker acceleration and,
##           where drag holds the car back, a little more top speed; level 10 +32.5 %)
##   tyres   the asphalt grip (mu, +4 % a level); the grip on dirt and snow stays where it was (the
##           car's shares are divided by the same factor), so each part does one thing
##   nitro   a bigger tank (nitro_time, +10 % a level: the push is the same, it lasts longer) and a
##           faster refill (nitro_refill, +10 % a level: the style score's points refill more of the
##           tank)
##   loose   the grip on dirt and snow (the car's dirt_grip and snow_grip shares, +5 % a level, but
##           never above its asphalt grip: the Dune, which keeps 97 % on dirt, gains 3 % there)
##   weight  (v6.21) a lighter car: the mass and the yaw inertia, -3 % a level (level 10 -19.5 %).
##           Nothing else is touched, and the physics does the rest: the same engine, brakes, nitro
##           and wings move less car, so it pulls harder above the speed where the tyres stop
##           slipping, stops shorter, gains more from the nitro and corners faster at speed (the
##           downforce is a bigger share of its weight); it is also pushed about more by a heavier
##           car (sim/car_contact.gd shares a contact by mass)
##   super   (v6.34) the supercharger: five levels, opened by engine level 5, +6 % power a level on
##           top of the engine's (level 5 +30 %: the torque curve × (1 + engine) × (1 + super)).
##           Its levels are fitted, not just bought: the car page runs a trial (sim/tune_trial.gd,
##           ui/trial_screen.gd) and a miss pays half the price back and fits nothing
##   aero    (v6.35) the aero tune: five levels, opened by weight level 5, -6 % drag a level (level 5
##           -30 %) and the top gear longer by the cube root of that (the speed where the power
##           meets the drag rises by it), so the higher top speed is reachable; fitted with the
##           same trial
##   brakes  (v6.36) five levels, open from the start and bought like the first five: +8 % brake
##           force a level (level 5 +40 %), the same front/rear bias. The tyres still cap what each
##           axle can take, so a car whose brakes already lock its rear gains less than 40 %
##   susp    (v6.37) the suspension: five levels, open from the start and bought like the brakes.
##           -6 % nose dive a level (brakeDive: while the car slows, less weight moves onto the
##           front wheels, so the rear stays planted when it lands braking; under power nothing
##           changes), hard landings cost 10 % a level less speed and take a 10 % harder hit before
##           they cost any. Level 5 keeps the Drifter and the Dune from spinning on crooked landings
##           with everything else at its top
##   wing    (v6.38) the wing: five levels, open from the start and bought like the brakes. Each adds
##           downforce worth 5 % of the stock car's weight at 180 km/h (its step, WING_KMH; level 5:
##           25 %, on top of the car's own), 70 % of it on the rear wheels (WING_FRONT: a rear wing
##           keeps the tail planted, so a keyboard driver's car doesn't weave more at speed), and 2 %
##           of its stock drag (WING_DRAG). More grip the faster the corner, a little less top speed. The car page sets
##           how much of it a car uses on each track (SaveData's setups: `wing` 0..5; with_setup())
##   ntune   (v6.40) the nitro tune: five levels, opened by nitro level 5 and fitted with the trial like
##           the supercharger: +12 % nitro push a level (level 5 +60 %: nitro_force and nitro_power,
##           so the push is stronger at every speed). The tank lasts as long (the nitro part makes it
##           bigger) and the push still fades out at the same speed (nitro_top; most cars reach their
##           rev limit in top gear first), so it is harder acceleration while it burns, not more top speed
## Never changed: max_speed (it scales the AI's speed input, so a network sees the same range in an
## upgraded car), the steering and the stability control: an upgraded car keeps its character. Levels 0, 0, 0, 0, 0 are the stock car itself (Cars.spec(id), the same object), so
## stock runs stay bit for bit what they were.
## Medal times and the AI opponents are always the stock cars' (data/medals.json, data/opponents):
## upgrades make medals and AI wins easier, on purpose; rewards are still paid once.
##
## Prices: level k of a part costs the car's base price × LEVEL_SHARE[k - 1] × the part's `cost`
## (a five-level part, v6.34: TRIAL_SHARE[k - 1], what levels 6-10 of a ten-level part cost),
## rounded to $50 (the base price is the car's shop price; a car that costs nothing, the Racer,
## counts as FREE_CAR_BASE). Levels 1-3 cost what they did; from level 4 the price climbs steeply
## (levels 8-10 of a part cost about 11 × levels 1-3 together: a late-career goal). Every part of
## every car costs total_all() (see the README).
## Data-driven: PARTS and LEVEL_SHARE are the whole table; MEASURED is what tools/upgrades.gd
## measured with the real physics for the car picker's bars (`tools/upgrades.gd --check` measures
## again and compares; the tests check each level's gain is in range).
##
##   Upgrades.ids() -> ["engine", "tyres", "nitro", "loose", "weight", "supercharger", "aero", "brakes", "suspension", "wing", "nitrotune"];  Upgrades.part(id) -> {...} or {}
##   Upgrades.index_of(id) -> 0..10 (-1 unknown);  Upgrades.part_id(word) -> id for a part name
##       or alias ("tires", "grip", "dirt", "lighter", "supercharger" ...), "" unknown
##   Upgrades.max_level(id) -> 10 (5 for the supercharger, the aero tune, the brakes, the suspension, the wing and the nitro tune);  Upgrades.needs(id) ->
##       {part, level} or {} (the supercharger: engine 5; the aero tune: weight 5; the nitro tune: nitro 5);  Upgrades.is_open(id, levels) -> the needed part is there
##   Upgrades.has_trial(id) -> its levels are fitted with a trial (a miss: half back)
##   Upgrades.stock() -> PackedInt32Array [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];  Upgrades.is_stock(levels)
##   Upgrades.clean(v) -> PackedInt32Array of 10 levels 0..max_level from anything (junk: 0; over
##       the top: the part's top; a shorter list from an older version (four before v6.21, five
##       before v6.34, six before v6.35, seven before v6.36, eight before v6.37, nine before v6.38, ten
##       before v6.40): the missing parts stock)
##   Upgrades.changes(car_id, levels) -> the CarSpec fields that differ (JS names)
##   Upgrades.spec(car_id, levels) -> CarSpec (cached; stock levels: Cars.spec(car_id))
##   Upgrades.player_spec(car_id) -> the car with the levels the save file holds
##   Upgrades.with_setup(levels, setup) / race_levels(car_id, track_id) -> (v6.38) the levels raced with
##       on a track: the wing turned down to the track's setup
##   Upgrades.price(car_id, part, level) -> $ for that level (1..MAX_LEVEL), 0 otherwise
##   Upgrades.car_total(car_id) / total_all() -> $ for every level of every part
##   Upgrades.code(levels) -> "E2 T1 N0 L3 W0" ("E5 T1 N5 L3 W5 S2 A1 B3 U1 D2 X1" with a supercharger,
##       an aero tune, brakes, suspension, a wing and a nitro tune); Upgrades.text(levels) -> "engine 2, tyres 1, ..." (those two only when fitted)
##   Upgrades.stats(car_id, levels) -> the car's stats (sim/cars.gd) with the measured upgrades
##   Upgrades.bars(car_id, levels) -> Cars.stat_bars of those stats (the car picker)
##   Upgrades.effect(part, level) -> "+10 % power", "-6 % weight" (the page's and the terminal's words)

const MAX_LEVEL: int = 10
## What a part adds at level k (index 0..10), in units of its `step` over stock: one step each for
## levels 1-3 (as before v6.16), then less and less (+0.8, +0.7, +0.6, +0.5, +0.4, +0.3, +0.2).
const LEVEL_GAIN: Array[float] = [0.0, 1.0, 2.0, 3.0, 3.8, 4.5, 5.1, 5.6, 6.0, 6.3, 6.5]
## Price of level k (1..10) as a share of the car's base price, × the part's cost (1-3 as before v6.16).
## From level 3 each level's price rises by 0.05 × the base more than the one before.
const LEVEL_SHARE: Array[float] = [0.1, 0.2, 0.35, 0.55, 0.8, 1.1, 1.45, 1.85, 2.3, 2.8]
## (v6.34) Price of level k (1..5) of a five-level part (the supercharger): what levels 6-10 of a
## ten-level part cost.
const TRIAL_SHARE: Array[float] = [1.1, 1.45, 1.85, 2.3, 2.8]
## The base price of a car that costs nothing in the shop (the Racer: between the Kestrel and the Drifter).
const FREE_CAR_BASE: int = 12000
## (v6.37) What each suspension level takes off a hard landing's speed loss and adds to the hit a
## landing takes before it costs speed (level 5: half the loss, from a 1.5 × harder hit).
const SUSP_LANDING: float = 0.1
## (v6.38) The wing: each level's downforce as a share of the stock car's weight (its `step`) at this
## speed, and its drag as a share of the stock drag.
const WING_KMH: float = 180.0
const WING_DRAG: float = 0.02
## (v6.38) The share of the wing's downforce on the front axle (the car's own keeps its aeroFront): with
## the car's own split the fully upgraded Thunder weaved 1.5° more than stock under the keyboard at
## 240 km/h; with most of it at the back, no car weaves more than 0.2° beyond its stock self.
const WING_FRONT: float = 0.3
## Prices are rounded to this many dollars.
const ROUND: int = 50

## The parts, in the picker's order. step: the share of the stock value each level adds; cost:
## × the car's base price share; alias: other words the terminal takes; what: what it does (one
## line), effect: the picker's "+5 % power" per level ("%d" = the level's percentage).
## (v6.34) Optional: max (levels, default MAX_LEVEL; a five-level part adds `step` a level),
## needs ([part, level] that opens it), trial (fitted with the trial), extra (left out of code()
## and text() while stock, so the strings of older runs stay as they were).
## over: what the trial's question measures the effect against ("on top of the engine's").
## (v6.36) share: the five levels' price shares in place of TRIAL_SHARE (the brakes, open from the
## start, cost about what a ten-level part's first five do).
## The order is the save file's (a car's `up` list) and the keys' (1-9, 0 for the tenth, minus for the eleventh): new parts go at the end.
const PARTS: Array[Dictionary] = [
	{id = "engine", name = "Engine", short = "E", step = 0.05, cost = 1.25, alias = ["power", "motor"],
		what = "more power: quicker acceleration and a little more top speed", effect = "+%d %% power"},
	{id = "tyres", name = "Tyres", short = "T", step = 0.04, cost = 1.0, alias = ["tyre", "tires", "tire"],
		what = "more grip on asphalt: faster corners", effect = "+%d %% asphalt grip"},
	{id = "nitro", name = "Nitro", short = "N", step = 0.1, cost = 0.6, alias = ["tank", "boost"],
		what = "a bigger nitro tank that refills faster", effect = "+%d %% tank and refill"},
	{id = "loose", name = "Loose grip", short = "L", step = 0.05, cost = 0.75, alias = ["grip", "dirt", "snow", "rally"],
		what = "more grip on dirt and snow (never above the car's asphalt grip)", effect = "+%d %% dirt and snow grip"},
	{id = "weight", name = "Weight", short = "W", step = 0.03, cost = 1.1, alias = ["lighter", "light", "mass", "diet", "wheight"],
		what = "a lighter car: it pulls harder at speed, stops shorter and gets more from the nitro", effect = "-%d %% weight"},
	{id = "supercharger", name = "Supercharger", chip = "Super", short = "S", step = 0.06, cost = 1.25, max = 5, needs = ["engine", 5], trial = true, extra = true,
		alias = ["super", "supercharging", "charger", "blower", "sc"],
		what = "forced induction: much more power on top of the engine's, for quicker acceleration everywhere", effect = "+%d %% power",
		over = "on top of the engine's"},
	{id = "aero", name = "Aero tune", chip = "Aero", short = "A", step = 0.06, cost = 1.1, max = 5, needs = ["weight", 5], trial = true, extra = true,
		alias = ["aerotune", "aero-tune", "drag", "aerodynamics", "aearo", "streamline", "cd"],
		what = "a slipperier body: less drag and a longer top gear, for a higher top speed", effect = "-%d %% drag",
		over = "over the stock car"},
	{id = "brakes", name = "Brakes", short = "B", step = 0.08, cost = 0.8, max = 5, extra = true, share = [0.15, 0.3, 0.55, 0.85, 1.25],
		alias = ["brake", "braking", "stopping", "pads", "discs"],
		what = "stronger brakes: a shorter stop from any speed (the tyres still set the limit)", effect = "+%d %% brake force"},
	{id = "suspension", name = "Suspension", chip = "Susp", short = "U", step = 0.06, cost = 0.75, max = 5, extra = true, share = [0.15, 0.3, 0.55, 0.85, 1.25],
		alias = ["susp", "springs", "dampers", "shocks", "suspention", "suspencion", "ride", "landing", "landings"],
		what = "stiffer springs: less nose dive under braking, so the rear keeps its grip; hard landings cost less speed and spin the car less", effect = "-%d %% nose dive, softer landings"},
	{id = "wing", name = "Wing", short = "D", step = 0.05, cost = 0.9, max = 5, extra = true, share = [0.15, 0.3, 0.55, 0.85, 1.25],
		alias = ["wings", "downforce", "spoiler", "aerowing", "df"],
		what = "a downforce wing: more grip the faster the corner, a little more drag (turn it down for a track on the car page)",
		effect = "+%d %% of the weight in downforce at 180 km/h"},
	{id = "nitrotune", name = "Nitro tune", chip = "Nitro+", short = "X", step = 0.12, cost = 0.6, max = 5, needs = ["nitro", 5], trial = true, extra = true,
		alias = ["nitro-tune", "nitrotuning", "ntune", "nos", "nitrous", "nitrotunne", "nt"],
		what = "a stronger nitro push: harder acceleration while it burns, from a tank that lasts as long", effect = "+%d %% nitro push",
		over = "over the stock push"},
]

## Measured with the real physics by tools/upgrades.gd (tools/car_stats.gd's measurements of the
## upgraded specs): per car, the engine's levels 1-10 {top, accel100, accel200}, the tyres'
## levels 1-10 {grip, gripFast}, (v6.21) the weight's levels 1-10 {top, accel100, accel200,
## brake100, grip, gripFast} and (v6.34) the supercharger's levels 1-5, measured on engine level 5
## {top, accel100, accel200}, (v6.35) the aero tune's, measured on weight level 5, and (v6.36) the
## brakes' levels 1-5 {brake100, brake200}, (v6.37) the suspension's {brake100} and (v6.38) the wing's
## {top, accel100, accel200, brake100, grip, gripFast}; the car page's bars use them. Filled by the tool;
## tests check it.
const MEASURED: Dictionary = {
	racer = {
		engine = [{top = 282.7, accel100 = 2.57, accel200 = 9.23}, {top = 286.2, accel100 = 2.47, accel200 = 8.77}, {top = 289.5, accel100 = 2.37, accel200 = 8.33}, {top = 292, accel100 = 2.28, accel200 = 8.03}, {top = 294.2, accel100 = 2.25, accel200 = 7.8}, {top = 295.9, accel100 = 2.22, accel200 = 7.6}, {top = 297.2, accel100 = 2.18, accel200 = 7.45}, {top = 297.2, accel100 = 2.17, accel200 = 7.35}, {top = 297.2, accel100 = 2.15, accel200 = 7.27}, {top = 297.2, accel100 = 2.13, accel200 = 7.22}],
		tyres = [{grip = 1.75, gripFast = 1.64}, {grip = 1.82, gripFast = 1.7}, {grip = 1.89, gripFast = 1.73}, {grip = 1.97, gripFast = 1.79}, {grip = 2.01, gripFast = 1.83}, {grip = 2.05, gripFast = 1.83}, {grip = 2.09, gripFast = 1.83}, {grip = 2.09, gripFast = 1.83}, {grip = 2.13, gripFast = 1.83}, {grip = 2.13, gripFast = 1.83}],
		weight = [{top = 277.8, accel100 = 2.62, accel200 = 9.5, brake100 = 30.1, grip = 1.68, gripFast = 1.58}, {top = 278, accel100 = 2.55, accel200 = 9.22, brake100 = 29.5, grip = 1.68, gripFast = 1.58}, {top = 278.1, accel100 = 2.47, accel200 = 8.93, brake100 = 28.9, grip = 1.69, gripFast = 1.58}, {top = 278.2, accel100 = 2.4, accel200 = 8.7, brake100 = 28.4, grip = 1.69, gripFast = 1.58}, {top = 278.3, accel100 = 2.35, accel200 = 8.52, brake100 = 28, grip = 1.69, gripFast = 1.58}, {top = 278.4, accel100 = 2.32, accel200 = 8.35, brake100 = 27.7, grip = 1.69, gripFast = 1.58}, {top = 278.4, accel100 = 2.28, accel200 = 8.22, brake100 = 27.4, grip = 1.69, gripFast = 1.58}, {top = 278.5, accel100 = 2.27, accel200 = 8.12, brake100 = 27.2, grip = 1.69, gripFast = 1.58}, {top = 278.5, accel100 = 2.25, accel200 = 8.03, brake100 = 27, grip = 1.69, gripFast = 1.58}, {top = 278.5, accel100 = 2.23, accel200 = 7.98, brake100 = 26.9, grip = 1.69, gripFast = 1.61}],
		supercharger = [{top = 297.2, accel100 = 2.17, accel200 = 7.35}, {top = 297.3, accel100 = 2.12, accel200 = 6.98}, {top = 297.3, accel100 = 2.08, accel200 = 6.68}, {top = 297.3, accel100 = 2.07, accel200 = 6.43}, {top = 297.3, accel100 = 2.05, accel200 = 6.2}],
		aero = [{top = 283.9, accel100 = 2.35, accel200 = 8.42}, {top = 290, accel100 = 2.35, accel200 = 8.32}, {top = 296.7, accel100 = 2.35, accel200 = 8.22}, {top = 304.1, accel100 = 2.35, accel200 = 8.12}, {top = 312.3, accel100 = 2.35, accel200 = 8.03}],
		brakes = [{brake100 = 29.4, brake200 = 113.2}, {brake100 = 28.2, brake200 = 108.1}, {brake100 = 27.2, brake200 = 104.3}, {brake100 = 26.3, brake200 = 100.9}, {brake100 = 25.5, brake200 = 97.7}],
		suspension = [{brake100 = 30.5}, {brake100 = 30.3}, {brake100 = 30.2}, {brake100 = 30.2}, {brake100 = 30.2}],
		wing = [{top = 275.3, accel100 = 2.7, accel200 = 9.83, brake100 = 30.6, grip = 1.68, gripFast = 1.61}, {top = 273, accel100 = 2.7, accel200 = 9.88, brake100 = 30.6, grip = 1.68, gripFast = 1.61}, {top = 270.7, accel100 = 2.7, accel200 = 9.93, brake100 = 30.5, grip = 1.72, gripFast = 1.64}, {top = 268.5, accel100 = 2.7, accel200 = 9.98, brake100 = 30.4, grip = 1.72, gripFast = 1.67}, {top = 266.3, accel100 = 2.7, accel200 = 10.05, brake100 = 30.4, grip = 1.75, gripFast = 1.7}],
	},
	kestrel = {
		engine = [{top = 233, accel100 = 2.35, accel200 = 10.52}, {top = 235.6, accel100 = 2.27, accel200 = 9.87}, {top = 237.7, accel100 = 2.2, accel200 = 9.3}, {top = 239.4, accel100 = 2.15, accel200 = 8.9}, {top = 240.8, accel100 = 2.12, accel200 = 8.58}, {top = 241.9, accel100 = 2.08, accel200 = 8.33}, {top = 242.9, accel100 = 2.07, accel200 = 8.15}, {top = 243.6, accel100 = 2.05, accel200 = 8.02}, {top = 244.2, accel100 = 2.03, accel200 = 7.9}, {top = 244.5, accel100 = 2.03, accel200 = 7.83}],
		tyres = [{grip = 1.85, gripFast = 1.65}, {grip = 1.93, gripFast = 1.68}, {grip = 2, gripFast = 1.71}, {grip = 2.04, gripFast = 1.72}, {grip = 2.09, gripFast = 1.72}, {grip = 2.13, gripFast = 1.72}, {grip = 2.17, gripFast = 1.72}, {grip = 2.21, gripFast = 1.72}, {grip = 2.21, gripFast = 1.72}, {grip = 2.25, gripFast = 1.72}],
		weight = [{top = 230.3, accel100 = 2.38, accel200 = 10.98, brake100 = 27.2, grip = 1.78, gripFast = 1.6}, {top = 230.4, accel100 = 2.33, accel200 = 10.67, brake100 = 26.7, grip = 1.78, gripFast = 1.6}, {top = 230.4, accel100 = 2.28, accel200 = 10.35, brake100 = 26.2, grip = 1.78, gripFast = 1.6}, {top = 230.5, accel100 = 2.23, accel200 = 10.1, brake100 = 25.8, grip = 1.78, gripFast = 1.6}, {top = 230.5, accel100 = 2.2, accel200 = 9.88, brake100 = 25.5, grip = 1.78, gripFast = 1.6}, {top = 230.6, accel100 = 2.17, accel200 = 9.68, brake100 = 25.2, grip = 1.75, gripFast = 1.6}, {top = 230.6, accel100 = 2.15, accel200 = 9.53, brake100 = 24.9, grip = 1.75, gripFast = 1.57}, {top = 230.6, accel100 = 2.13, accel200 = 9.42, brake100 = 24.7, grip = 1.75, gripFast = 1.57}, {top = 230.6, accel100 = 2.12, accel200 = 9.32, brake100 = 24.5, grip = 1.75, gripFast = 1.57}, {top = 230.7, accel100 = 2.1, accel200 = 9.27, brake100 = 24.4, grip = 1.75, gripFast = 1.57}],
		supercharger = [{top = 243.6, accel100 = 2.05, accel200 = 8.02}, {top = 245.5, accel100 = 2, accel200 = 7.55}, {top = 245.5, accel100 = 1.97, accel200 = 7.15}, {top = 245.5, accel100 = 1.93, accel200 = 6.8}, {top = 245.5, accel100 = 1.92, accel200 = 6.52}],
		aero = [{top = 235.3, accel100 = 2.2, accel200 = 9.58}, {top = 240.5, accel100 = 2.2, accel200 = 9.32}, {top = 246.2, accel100 = 2.2, accel200 = 9.08}, {top = 252.4, accel100 = 2.18, accel200 = 8.87}, {top = 259.4, accel100 = 2.18, accel200 = 8.67}],
		brakes = [{brake100 = 26.7, brake200 = 104.9}, {brake100 = 25.7, brake200 = 101.3}, {brake100 = 24.9, brake200 = 98}, {brake100 = 24.1, brake200 = 94.9}, {brake100 = 23.5, brake200 = 92.1}],
		suspension = [{brake100 = 27.4}, {brake100 = 27.1}, {brake100 = 26.8}, {brake100 = 26.5}, {brake100 = 26.2}],
		wing = [{top = 229, accel100 = 2.45, accel200 = 11.43, brake100 = 27.6, grip = 1.78, gripFast = 1.6}, {top = 227.7, accel100 = 2.45, accel200 = 11.6, brake100 = 27.5, grip = 1.78, gripFast = 1.62}, {top = 226.5, accel100 = 2.45, accel200 = 11.77, brake100 = 27.3, grip = 1.82, gripFast = 1.65}, {top = 225.3, accel100 = 2.45, accel200 = 11.93, brake100 = 27.2, grip = 1.82, gripFast = 1.68}, {top = 224.1, accel100 = 2.45, accel200 = 12.12, brake100 = 27.1, grip = 1.82, gripFast = 1.68}],
	},
	thunder = {
		engine = [{top = 318.7, accel100 = 2.58, accel200 = 7.8}, {top = 323.8, accel100 = 2.52, accel200 = 7.48}, {top = 327.9, accel100 = 2.47, accel200 = 7.18}, {top = 331.1, accel100 = 2.43, accel200 = 6.98}, {top = 333.8, accel100 = 2.42, accel200 = 6.82}, {top = 334.9, accel100 = 2.38, accel200 = 6.67}, {top = 334.9, accel100 = 2.37, accel200 = 6.57}, {top = 334.9, accel100 = 2.35, accel200 = 6.48}, {top = 334.9, accel100 = 2.35, accel200 = 6.42}, {top = 334.9, accel100 = 2.33, accel200 = 6.38}],
		tyres = [{grip = 1.53, gripFast = 1.62}, {grip = 1.62, gripFast = 1.68}, {grip = 1.69, gripFast = 1.74}, {grip = 1.72, gripFast = 1.77}, {grip = 1.76, gripFast = 1.84}, {grip = 1.83, gripFast = 1.87}, {grip = 1.83, gripFast = 1.9}, {grip = 1.86, gripFast = 1.94}, {grip = 1.9, gripFast = 1.94}, {grip = 1.9, gripFast = 1.94}],
		weight = [{top = 312.9, accel100 = 2.62, accel200 = 7.98, brake100 = 33, grip = 1.47, gripFast = 1.56}, {top = 313, accel100 = 2.57, accel200 = 7.77, brake100 = 32.3, grip = 1.47, gripFast = 1.56}, {top = 313.1, accel100 = 2.52, accel200 = 7.57, brake100 = 31.6, grip = 1.47, gripFast = 1.56}, {top = 313.3, accel100 = 2.48, accel200 = 7.4, brake100 = 31.1, grip = 1.5, gripFast = 1.59}, {top = 313.4, accel100 = 2.47, accel200 = 7.27, brake100 = 30.6, grip = 1.5, gripFast = 1.59}, {top = 313.4, accel100 = 2.45, accel200 = 7.15, brake100 = 30.2, grip = 1.5, gripFast = 1.59}, {top = 313.5, accel100 = 2.43, accel200 = 7.05, brake100 = 29.9, grip = 1.5, gripFast = 1.59}, {top = 313.6, accel100 = 2.42, accel200 = 6.97, brake100 = 29.6, grip = 1.5, gripFast = 1.59}, {top = 313.6, accel100 = 2.4, accel200 = 6.92, brake100 = 29.4, grip = 1.5, gripFast = 1.62}, {top = 313.6, accel100 = 2.4, accel200 = 6.88, brake100 = 29.3, grip = 1.5, gripFast = 1.62}],
		supercharger = [{top = 334.9, accel100 = 2.35, accel200 = 6.48}, {top = 334.9, accel100 = 2.32, accel200 = 6.22}, {top = 334.9, accel100 = 2.3, accel200 = 6}, {top = 334.9, accel100 = 2.3, accel200 = 5.82}, {top = 335, accel100 = 2.3, accel200 = 5.65}],
		aero = [{top = 319.5, accel100 = 2.47, accel200 = 7.22}, {top = 326.1, accel100 = 2.47, accel200 = 7.17}, {top = 333.3, accel100 = 2.47, accel200 = 7.12}, {top = 341.3, accel100 = 2.47, accel200 = 7.07}, {top = 350, accel100 = 2.45, accel200 = 7.03}],
		brakes = [{brake100 = 32.1, brake200 = 124.7}, {brake100 = 30.8, brake200 = 117.8}, {brake100 = 29.7, brake200 = 112.2}, {brake100 = 28.7, brake200 = 107.5}, {brake100 = 28.1, brake200 = 103.9}],
		suspension = [{brake100 = 33.6}, {brake100 = 33.6}, {brake100 = 33.6}, {brake100 = 33.6}, {brake100 = 33.6}],
		wing = [{top = 309.8, accel100 = 2.68, accel200 = 8.23, brake100 = 33.7, grip = 1.47, gripFast = 1.56}, {top = 306.9, accel100 = 2.68, accel200 = 8.27, brake100 = 33.7, grip = 1.5, gripFast = 1.59}, {top = 304.1, accel100 = 2.68, accel200 = 8.28, brake100 = 33.6, grip = 1.5, gripFast = 1.59}, {top = 301.4, accel100 = 2.7, accel200 = 8.32, brake100 = 33.6, grip = 1.5, gripFast = 1.62}, {top = 298.8, accel100 = 2.7, accel200 = 8.33, brake100 = 33.5, grip = 1.53, gripFast = 1.64}],
	},
	drifter = {
		engine = [{top = 268.5, accel100 = 2.45, accel200 = 8.77}, {top = 272.3, accel100 = 2.38, accel200 = 8.35}, {top = 275.7, accel100 = 2.35, accel200 = 7.98}, {top = 278.3, accel100 = 2.32, accel200 = 7.73}, {top = 280.5, accel100 = 2.28, accel200 = 7.52}, {top = 282.3, accel100 = 2.27, accel200 = 7.35}, {top = 283.8, accel100 = 2.25, accel200 = 7.22}, {top = 285, accel100 = 2.23, accel200 = 7.12}, {top = 285.5, accel100 = 2.22, accel200 = 7.05}, {top = 285.5, accel100 = 2.22, accel200 = 7}],
		tyres = [{grip = 1.68, gripFast = 1.58}, {grip = 1.75, gripFast = 1.61}, {grip = 1.82, gripFast = 1.67}, {grip = 1.86, gripFast = 1.7}, {grip = 1.93, gripFast = 1.76}, {grip = 1.97, gripFast = 1.76}, {grip = 2.01, gripFast = 1.79}, {grip = 2.01, gripFast = 1.82}, {grip = 2.05, gripFast = 1.82}, {grip = 2.05, gripFast = 1.82}],
		weight = [{top = 264.4, accel100 = 2.47, accel200 = 9, brake100 = 32.5, grip = 1.59, gripFast = 1.52}, {top = 264.5, accel100 = 2.43, accel200 = 8.77, brake100 = 31.9, grip = 1.59, gripFast = 1.52}, {top = 264.6, accel100 = 2.4, accel200 = 8.53, brake100 = 31.4, grip = 1.59, gripFast = 1.52}, {top = 264.6, accel100 = 2.37, accel200 = 8.37, brake100 = 30.9, grip = 1.59, gripFast = 1.52}, {top = 264.7, accel100 = 2.35, accel200 = 8.2, brake100 = 30.5, grip = 1.59, gripFast = 1.52}, {top = 264.8, accel100 = 2.32, accel200 = 8.07, brake100 = 30.1, grip = 1.59, gripFast = 1.52}, {top = 264.8, accel100 = 2.32, accel200 = 7.95, brake100 = 29.8, grip = 1.59, gripFast = 1.52}, {top = 264.9, accel100 = 2.3, accel200 = 7.87, brake100 = 29.5, grip = 1.6, gripFast = 1.52}, {top = 264.9, accel100 = 2.28, accel200 = 7.8, brake100 = 29.4, grip = 1.6, gripFast = 1.52}, {top = 264.9, accel100 = 2.28, accel200 = 7.75, brake100 = 29.2, grip = 1.6, gripFast = 1.52}],
		supercharger = [{top = 284.9, accel100 = 2.23, accel200 = 7.13}, {top = 285.5, accel100 = 2.18, accel200 = 6.78}, {top = 285.5, accel100 = 2.17, accel200 = 6.52}, {top = 285.5, accel100 = 2.15, accel200 = 6.27}, {top = 285.5, accel100 = 2.15, accel200 = 6.07}],
		aero = [{top = 270.1, accel100 = 2.35, accel200 = 8.08}, {top = 276, accel100 = 2.33, accel200 = 7.98}, {top = 282.5, accel100 = 2.33, accel200 = 7.87}, {top = 289.6, accel100 = 2.33, accel200 = 7.77}, {top = 297.5, accel100 = 2.33, accel200 = 7.68}],
		brakes = [{brake100 = 31.8, brake200 = 121.6}, {brake100 = 30.6, brake200 = 117.3}, {brake100 = 29.5, brake200 = 113.3}, {brake100 = 28.6, brake200 = 109.7}, {brake100 = 27.6, brake200 = 106.3}],
		suspension = [{brake100 = 32.6}, {brake100 = 32.2}, {brake100 = 31.8}, {brake100 = 31.4}, {brake100 = 31}],
		wing = [{top = 262.3, accel100 = 2.5, accel200 = 9.28, brake100 = 32.9, grip = 1.62, gripFast = 1.52}, {top = 260.3, accel100 = 2.5, accel200 = 9.33, brake100 = 32.7, grip = 1.62, gripFast = 1.55}, {top = 258.4, accel100 = 2.5, accel200 = 9.38, brake100 = 32.6, grip = 1.65, gripFast = 1.58}, {top = 256.6, accel100 = 2.5, accel200 = 9.45, brake100 = 32.4, grip = 1.65, gripFast = 1.61}, {top = 254.8, accel100 = 2.5, accel200 = 9.5, brake100 = 32.3, grip = 1.65, gripFast = 1.64}],
	},
	dune = {
		engine = [{top = 225.8, accel100 = 2.78, accel200 = 11.73}, {top = 228.9, accel100 = 2.72, accel200 = 10.95}, {top = 231.6, accel100 = 2.67, accel200 = 10.28}, {top = 233.7, accel100 = 2.62, accel200 = 9.83}, {top = 235.4, accel100 = 2.58, accel200 = 9.47}, {top = 236.9, accel100 = 2.55, accel200 = 9.18}, {top = 238.1, accel100 = 2.52, accel200 = 8.97}, {top = 238.5, accel100 = 2.5, accel200 = 8.8}, {top = 238.5, accel100 = 2.48, accel200 = 8.68}, {top = 238.5, accel100 = 2.48, accel200 = 8.62}],
		tyres = [{grip = 1.78, gripFast = 1.48}, {grip = 1.85, gripFast = 1.56}, {grip = 1.92, gripFast = 1.58}, {grip = 1.96, gripFast = 1.58}, {grip = 2, gripFast = 1.58}, {grip = 2.08, gripFast = 1.59}, {grip = 2.08, gripFast = 1.61}, {grip = 2.12, gripFast = 1.61}, {grip = 2.16, gripFast = 1.61}, {grip = 2.16, gripFast = 1.61}],
		weight = [{top = 222.5, accel100 = 2.82, accel200 = 12.35, brake100 = 31.2, grip = 1.71, gripFast = 1.43}, {top = 222.6, accel100 = 2.78, accel200 = 12.02, brake100 = 30.6, grip = 1.71, gripFast = 1.43}, {top = 222.7, accel100 = 2.73, accel200 = 11.68, brake100 = 30.1, grip = 1.71, gripFast = 1.43}, {top = 222.7, accel100 = 2.7, accel200 = 11.42, brake100 = 29.7, grip = 1.71, gripFast = 1.43}, {top = 222.8, accel100 = 2.67, accel200 = 11.18, brake100 = 29.3, grip = 1.71, gripFast = 1.43}, {top = 222.8, accel100 = 2.63, accel200 = 10.98, brake100 = 28.9, grip = 1.71, gripFast = 1.43}, {top = 222.8, accel100 = 2.62, accel200 = 10.82, brake100 = 28.6, grip = 1.71, gripFast = 1.43}, {top = 222.9, accel100 = 2.6, accel200 = 10.7, brake100 = 28.4, grip = 1.71, gripFast = 1.43}, {top = 222.9, accel100 = 2.58, accel200 = 10.6, brake100 = 28.2, grip = 1.72, gripFast = 1.43}, {top = 222.9, accel100 = 2.58, accel200 = 10.53, brake100 = 28.1, grip = 1.72, gripFast = 1.43}],
		supercharger = [{top = 238.5, accel100 = 2.5, accel200 = 8.82}, {top = 238.5, accel100 = 2.43, accel200 = 8.28}, {top = 238.5, accel100 = 2.38, accel200 = 7.83}, {top = 238.5, accel100 = 2.33, accel200 = 7.43}, {top = 238.5, accel100 = 2.28, accel200 = 7.1}],
		aero = [{top = 227.4, accel100 = 2.67, accel200 = 10.75}, {top = 232.4, accel100 = 2.65, accel200 = 10.38}, {top = 237.8, accel100 = 2.65, accel200 = 10.05}, {top = 243.9, accel100 = 2.65, accel200 = 9.78}, {top = 250.6, accel100 = 2.65, accel200 = 9.53}],
		brakes = [{brake100 = 30.6, brake200 = 117.2}, {brake100 = 29.5, brake200 = 113.4}, {brake100 = 28.5, brake200 = 109.9}, {brake100 = 27.7, brake200 = 106.7}, {brake100 = 26.8, brake200 = 103.6}],
		suspension = [{brake100 = 31.3}, {brake100 = 30.8}, {brake100 = 30.4}, {brake100 = 29.9}, {brake100 = 29.5}],
		wing = [{top = 221, accel100 = 2.87, accel200 = 12.92, brake100 = 31.5, grip = 1.71, gripFast = 1.45}, {top = 219.5, accel100 = 2.87, accel200 = 13.17, brake100 = 31.4, grip = 1.74, gripFast = 1.48}, {top = 218.1, accel100 = 2.87, accel200 = 13.45, brake100 = 31.2, grip = 1.74, gripFast = 1.5}, {top = 216.7, accel100 = 2.87, accel200 = 13.75, brake100 = 31.1, grip = 1.74, gripFast = 1.53}, {top = 215.3, accel100 = 2.87, accel200 = 14.07, brake100 = 30.9, grip = 1.77, gripFast = 1.55}],
	},
	vortex = {
		engine = [{top = 328.5, accel100 = 2.45, accel200 = 5.92}, {top = 335.3, accel100 = 2.33, accel200 = 5.63}, {top = 342, accel100 = 2.25, accel200 = 5.4}, {top = 347.1, accel100 = 2.22, accel200 = 5.27}, {top = 350.8, accel100 = 2.2, accel200 = 5.17}, {top = 353.9, accel100 = 2.18, accel200 = 5.08}, {top = 356.4, accel100 = 2.17, accel200 = 5.02}, {top = 358.4, accel100 = 2.15, accel200 = 4.97}, {top = 359.9, accel100 = 2.15, accel200 = 4.93}, {top = 360.9, accel100 = 2.13, accel200 = 4.92}],
		tyres = [{grip = 1.75, gripFast = 1.85}, {grip = 1.82, gripFast = 1.92}, {grip = 1.9, gripFast = 1.98}, {grip = 1.98, gripFast = 2.08}, {grip = 2.02, gripFast = 2.12}, {grip = 2.06, gripFast = 2.16}, {grip = 2.1, gripFast = 2.2}, {grip = 2.14, gripFast = 2.24}, {grip = 2.14, gripFast = 2.24}, {grip = 2.18, gripFast = 2.29}],
		weight = [{top = 321.5, accel100 = 2.5, accel200 = 6.05, brake100 = 28.2, grip = 1.68, gripFast = 1.78}, {top = 321.7, accel100 = 2.42, accel200 = 5.87, brake100 = 27.6, grip = 1.69, gripFast = 1.78}, {top = 321.8, accel100 = 2.35, accel200 = 5.68, brake100 = 27.1, grip = 1.69, gripFast = 1.78}, {top = 321.9, accel100 = 2.28, accel200 = 5.55, brake100 = 26.6, grip = 1.69, gripFast = 1.82}, {top = 322, accel100 = 2.25, accel200 = 5.43, brake100 = 26.2, grip = 1.69, gripFast = 1.82}, {top = 322, accel100 = 2.22, accel200 = 5.35, brake100 = 25.9, grip = 1.69, gripFast = 1.82}, {top = 322.1, accel100 = 2.2, accel200 = 5.28, brake100 = 25.6, grip = 1.69, gripFast = 1.85}, {top = 322.2, accel100 = 2.2, accel200 = 5.25, brake100 = 25.4, grip = 1.69, gripFast = 1.85}, {top = 322.2, accel100 = 2.18, accel200 = 5.2, brake100 = 25.2, grip = 1.69, gripFast = 1.85}, {top = 322.2, accel100 = 2.18, accel200 = 5.18, brake100 = 25.1, grip = 1.69, gripFast = 1.85}],
		supercharger = [{top = 358.3, accel100 = 2.15, accel200 = 4.97}, {top = 365.4, accel100 = 2.12, accel200 = 4.82}, {top = 372.3, accel100 = 2.08, accel200 = 4.67}, {top = 378.8, accel100 = 2.03, accel200 = 4.55}, {top = 384.2, accel100 = 2, accel200 = 4.43}],
		aero = [{top = 328.3, accel100 = 2.25, accel200 = 5.4}, {top = 335.2, accel100 = 2.25, accel200 = 5.38}, {top = 342.6, accel100 = 2.23, accel200 = 5.35}, {top = 350.8, accel100 = 2.23, accel200 = 5.32}, {top = 359.9, accel100 = 2.23, accel200 = 5.3}],
		brakes = [{brake100 = 27.5, brake200 = 104.4}, {brake100 = 26.4, brake200 = 99.1}, {brake100 = 25.5, brake200 = 94.6}, {brake100 = 24.7, brake200 = 90.9}, {brake100 = 24.6, brake200 = 88.5}],
		suspension = [{brake100 = 28.8}, {brake100 = 28.8}, {brake100 = 28.8}, {brake100 = 28.8}, {brake100 = 28.8}],
		wing = [{top = 320.3, accel100 = 2.57, accel200 = 6.23, brake100 = 28.8, grip = 1.68, gripFast = 1.78}, {top = 320.3, accel100 = 2.57, accel200 = 6.25, brake100 = 28.8, grip = 1.68, gripFast = 1.81}, {top = 320.3, accel100 = 2.57, accel200 = 6.27, brake100 = 28.8, grip = 1.72, gripFast = 1.85}, {top = 319, accel100 = 2.57, accel200 = 6.27, brake100 = 28.8, grip = 1.72, gripFast = 1.88}, {top = 316.6, accel100 = 2.57, accel200 = 6.28, brake100 = 28.8, grip = 1.72, gripFast = 1.92}],
	},
	apex = {
		engine = [{top = 288.5, accel100 = 2.58, accel200 = 6.12}, {top = 292.9, accel100 = 2.58, accel200 = 5.95}, {top = 297, accel100 = 2.58, accel200 = 5.82}, {top = 299.7, accel100 = 2.58, accel200 = 5.72}, {top = 302, accel100 = 2.58, accel200 = 5.63}, {top = 303.8, accel100 = 2.58, accel200 = 5.57}, {top = 305.4, accel100 = 2.58, accel200 = 5.52}, {top = 306.6, accel100 = 2.58, accel200 = 5.48}, {top = 307.5, accel100 = 2.58, accel200 = 5.47}, {top = 308, accel100 = 2.58, accel200 = 5.45}],
		tyres = [{grip = 2.14, gripFast = 2.42}, {grip = 2.23, gripFast = 2.42}, {grip = 2.36, gripFast = 2.42}, {grip = 2.41, gripFast = 2.42}, {grip = 2.51, gripFast = 2.42}, {grip = 2.56, gripFast = 2.43}, {grip = 2.62, gripFast = 2.43}, {grip = 2.67, gripFast = 2.43}, {grip = 2.72, gripFast = 2.43}, {grip = 2.72, gripFast = 2.43}],
		weight = [{top = 284, accel100 = 2.58, accel200 = 6.2, brake100 = 20.6, grip = 2.05, gripFast = 2.42}, {top = 284.1, accel100 = 2.58, accel200 = 6.12, brake100 = 20.5, grip = 2.06, gripFast = 2.42}, {top = 284.1, accel100 = 2.58, accel200 = 6.02, brake100 = 20.5, grip = 2.06, gripFast = 2.42}, {top = 284.2, accel100 = 2.57, accel200 = 5.95, brake100 = 20.4, grip = 2.1, gripFast = 2.43}, {top = 284.2, accel100 = 2.57, accel200 = 5.88, brake100 = 20.3, grip = 2.1, gripFast = 2.43}, {top = 284.3, accel100 = 2.57, accel200 = 5.82, brake100 = 20.3, grip = 2.1, gripFast = 2.47}, {top = 284.3, accel100 = 2.57, accel200 = 5.78, brake100 = 20.2, grip = 2.1, gripFast = 2.47}, {top = 284.3, accel100 = 2.57, accel200 = 5.73, brake100 = 20.2, grip = 2.1, gripFast = 2.47}, {top = 284.3, accel100 = 2.57, accel200 = 5.72, brake100 = 20.2, grip = 2.15, gripFast = 2.47}, {top = 284.3, accel100 = 2.57, accel200 = 5.68, brake100 = 20.2, grip = 2.15, gripFast = 2.47}],
		supercharger = [{top = 306.5, accel100 = 2.58, accel200 = 5.48}, {top = 309.8, accel100 = 2.58, accel200 = 5.37}, {top = 309.8, accel100 = 2.58, accel200 = 5.27}, {top = 309.8, accel100 = 2.58, accel200 = 5.2}, {top = 309.9, accel100 = 2.58, accel200 = 5.13}],
		aero = [{top = 289.8, accel100 = 2.57, accel200 = 5.83}, {top = 295.9, accel100 = 2.57, accel200 = 5.77}, {top = 302.6, accel100 = 2.57, accel200 = 5.72}, {top = 309.9, accel100 = 2.55, accel200 = 5.67}, {top = 317.7, accel100 = 2.55, accel200 = 5.63}],
		brakes = [{brake100 = 20.7, brake200 = 68.1}, {brake100 = 20.7, brake200 = 66.5}, {brake100 = 20.7, brake200 = 65.6}, {brake100 = 20.7, brake200 = 65}, {brake100 = 20.7, brake200 = 64.9}],
		suspension = [{brake100 = 20.7}, {brake100 = 20.6}, {brake100 = 20.6}, {brake100 = 20.6}, {brake100 = 20.6}],
		wing = [{top = 281.6, accel100 = 2.58, accel200 = 6.32, brake100 = 20.5, grip = 2.05, gripFast = 2.42}, {top = 279, accel100 = 2.57, accel200 = 6.32, brake100 = 20.4, grip = 2.1, gripFast = 2.37}, {top = 276.4, accel100 = 2.55, accel200 = 6.33, brake100 = 20.3, grip = 2.1, gripFast = 2.37}, {top = 274, accel100 = 2.53, accel200 = 6.33, brake100 = 20.2, grip = 2.14, gripFast = 2.37}, {top = 271.6, accel100 = 2.53, accel200 = 6.35, brake100 = 20.1, grip = 2.14, gripFast = 2.33}],
	},
	quadra = {
		engine = [{top = 248.5, accel100 = 2.42, accel200 = 8.45}, {top = 251.9, accel100 = 2.37, accel200 = 8.02}, {top = 255.1, accel100 = 2.32, accel200 = 7.65}, {top = 257.5, accel100 = 2.28, accel200 = 7.38}, {top = 259.6, accel100 = 2.25, accel200 = 7.17}, {top = 261.3, accel100 = 2.23, accel200 = 7}, {top = 261.6, accel100 = 2.22, accel200 = 6.88}, {top = 261.6, accel100 = 2.22, accel200 = 6.78}, {top = 261.6, accel100 = 2.2, accel200 = 6.72}, {top = 261.6, accel100 = 2.2, accel200 = 6.68}],
		tyres = [{grip = 1.68, gripFast = 1.58}, {grip = 1.75, gripFast = 1.64}, {grip = 1.83, gripFast = 1.7}, {grip = 1.86, gripFast = 1.73}, {grip = 1.9, gripFast = 1.75}, {grip = 1.98, gripFast = 1.75}, {grip = 1.98, gripFast = 1.75}, {grip = 2.02, gripFast = 1.76}, {grip = 2.06, gripFast = 1.76}, {grip = 2.06, gripFast = 1.76}],
		weight = [{top = 245, accel100 = 2.43, accel200 = 8.72, brake100 = 30.7, grip = 1.62, gripFast = 1.52}, {top = 245.1, accel100 = 2.4, accel200 = 8.5, brake100 = 30.1, grip = 1.62, gripFast = 1.52}, {top = 245.2, accel100 = 2.37, accel200 = 8.28, brake100 = 29.5, grip = 1.62, gripFast = 1.52}, {top = 245.2, accel100 = 2.33, accel200 = 8.1, brake100 = 29, grip = 1.62, gripFast = 1.52}, {top = 245.3, accel100 = 2.32, accel200 = 7.95, brake100 = 28.6, grip = 1.62, gripFast = 1.55}, {top = 245.3, accel100 = 2.28, accel200 = 7.82, brake100 = 28.2, grip = 1.62, gripFast = 1.55}, {top = 245.3, accel100 = 2.27, accel200 = 7.72, brake100 = 27.9, grip = 1.62, gripFast = 1.55}, {top = 245.4, accel100 = 2.25, accel200 = 7.62, brake100 = 27.7, grip = 1.62, gripFast = 1.55}, {top = 245.4, accel100 = 2.25, accel200 = 7.55, brake100 = 27.5, grip = 1.62, gripFast = 1.55}, {top = 245.4, accel100 = 2.23, accel200 = 7.52, brake100 = 27.4, grip = 1.62, gripFast = 1.55}],
		supercharger = [{top = 261.6, accel100 = 2.22, accel200 = 6.8}, {top = 261.6, accel100 = 2.18, accel200 = 6.5}, {top = 261.6, accel100 = 2.17, accel200 = 6.25}, {top = 261.6, accel100 = 2.17, accel200 = 6.03}, {top = 261.7, accel100 = 2.15, accel200 = 5.83}],
		aero = [{top = 250.3, accel100 = 2.32, accel200 = 7.78}, {top = 255.7, accel100 = 2.3, accel200 = 7.63}, {top = 261.7, accel100 = 2.3, accel200 = 7.5}, {top = 268.2, accel100 = 2.3, accel200 = 7.37}, {top = 275.5, accel100 = 2.3, accel200 = 7.25}],
		brakes = [{brake100 = 30, brake200 = 112.4}, {brake100 = 28.9, brake200 = 108.5}, {brake100 = 27.9, brake200 = 104.8}, {brake100 = 27, brake200 = 101.5}, {brake100 = 26.2, brake200 = 98.4}],
		suspension = [{brake100 = 30.8}, {brake100 = 30.4}, {brake100 = 30}, {brake100 = 29.6}, {brake100 = 29.2}],
		wing = [{top = 243, accel100 = 2.47, accel200 = 9, brake100 = 31.1, grip = 1.62, gripFast = 1.55}, {top = 241.2, accel100 = 2.47, accel200 = 9.08, brake100 = 30.9, grip = 1.62, gripFast = 1.58}, {top = 239.4, accel100 = 2.47, accel200 = 9.17, brake100 = 30.8, grip = 1.62, gripFast = 1.58}, {top = 237.7, accel100 = 2.47, accel200 = 9.25, brake100 = 30.6, grip = 1.65, gripFast = 1.6}, {top = 236, accel100 = 2.47, accel200 = 9.32, brake100 = 30.5, grip = 1.65, gripFast = 1.63}],
	},
	sarthe = {
		engine = [{top = 342.4, accel100 = 2.38, accel200 = 5.52}, {top = 348.7, accel100 = 2.28, accel200 = 5.25}, {top = 354.8, accel100 = 2.18, accel200 = 5.02}, {top = 359.5, accel100 = 2.12, accel200 = 4.85}, {top = 362.9, accel100 = 2.05, accel200 = 4.72}, {top = 365.7, accel100 = 2.02, accel200 = 4.62}, {top = 368, accel100 = 1.98, accel200 = 4.53}, {top = 369.8, accel100 = 1.98, accel200 = 4.47}, {top = 371.1, accel100 = 1.97, accel200 = 4.43}, {top = 371.9, accel100 = 1.97, accel200 = 4.42}],
		tyres = [{grip = 1.94, gripFast = 2.48}, {grip = 2.02, gripFast = 2.63}, {grip = 2.14, gripFast = 2.74}, {grip = 2.18, gripFast = 2.85}, {grip = 2.27, gripFast = 2.91}, {grip = 2.32, gripFast = 2.91}, {grip = 2.37, gripFast = 2.91}, {grip = 2.37, gripFast = 2.91}, {grip = 2.42, gripFast = 2.91}, {grip = 2.42, gripFast = 2.91}],
		weight = [{top = 336, accel100 = 2.43, accel200 = 5.65, brake100 = 23.3, grip = 1.86, gripFast = 2.38}, {top = 336.1, accel100 = 2.35, accel200 = 5.47, brake100 = 22.9, grip = 1.86, gripFast = 2.43}, {top = 336.2, accel100 = 2.28, accel200 = 5.3, brake100 = 22.6, grip = 1.86, gripFast = 2.48}, {top = 336.3, accel100 = 2.22, accel200 = 5.17, brake100 = 22.5, grip = 1.87, gripFast = 2.48}, {top = 336.4, accel100 = 2.17, accel200 = 5.05, brake100 = 22.4, grip = 1.9, gripFast = 2.53}, {top = 336.5, accel100 = 2.13, accel200 = 4.95, brake100 = 22.4, grip = 1.9, gripFast = 2.59}, {top = 336.5, accel100 = 2.1, accel200 = 4.87, brake100 = 22.3, grip = 1.9, gripFast = 2.64}, {top = 336.6, accel100 = 2.07, accel200 = 4.8, brake100 = 22.3, grip = 1.9, gripFast = 2.64}, {top = 336.6, accel100 = 2.05, accel200 = 4.75, brake100 = 22.2, grip = 1.91, gripFast = 2.64}, {top = 336.6, accel100 = 2.03, accel200 = 4.73, brake100 = 22.2, grip = 1.91, gripFast = 2.64}],
		supercharger = [{top = 369.6, accel100 = 1.98, accel200 = 4.48}, {top = 376, accel100 = 1.93, accel200 = 4.3}, {top = 377, accel100 = 1.9, accel200 = 4.15}, {top = 377, accel100 = 1.87, accel200 = 4.02}, {top = 377, accel100 = 1.83, accel200 = 3.9}],
		aero = [{top = 342.8, accel100 = 2.17, accel200 = 5.03}, {top = 349.7, accel100 = 2.17, accel200 = 5}, {top = 357, accel100 = 2.17, accel200 = 4.98}, {top = 365, accel100 = 2.17, accel200 = 4.97}, {top = 373.8, accel100 = 2.17, accel200 = 4.93}],
		brakes = [{brake100 = 22.9, brake200 = 82.7}, {brake100 = 22.7, brake200 = 79.4}, {brake100 = 22.7, brake200 = 76.9}, {brake100 = 22.7, brake200 = 75.2}, {brake100 = 22.7, brake200 = 73.9}],
		suspension = [{brake100 = 23.5}, {brake100 = 23.3}, {brake100 = 23.2}, {brake100 = 23}, {brake100 = 22.9}],
		wing = [{top = 332.5, accel100 = 2.5, accel200 = 5.83, brake100 = 23.6, grip = 1.86, gripFast = 2.38}, {top = 329.1, accel100 = 2.5, accel200 = 5.83, brake100 = 23.5, grip = 1.86, gripFast = 2.43}, {top = 325.8, accel100 = 2.5, accel200 = 5.85, brake100 = 23.4, grip = 1.9, gripFast = 2.53}, {top = 322.6, accel100 = 2.5, accel200 = 5.87, brake100 = 23.3, grip = 1.9, gripFast = 2.58}, {top = 319.5, accel100 = 2.5, accel200 = 5.87, brake100 = 23.2, grip = 1.9, gripFast = 2.63}],
	},
}

## What the weight part's measurements hold (MEASURED.weight; stats() scales these; (v6.38) the wing's too).
const WEIGHT_KEYS: Array[String] = ["top", "accel100", "accel200", "brake100", "grip", "gripFast"]
## (v6.34) What the measurements of a part another one opens hold (MEASURED.supercharger, measured on
## engine level 5; v6.35: MEASURED.aero, measured on weight level 5).
const TRIAL_KEYS: Array[String] = ["top", "accel100", "accel200"]

static var _specs: Dictionary = {}
static var _mutex: Mutex = Mutex.new()
static var _index: Dictionary = _make_index()


static func _make_index() -> Dictionary:
	var out: Dictionary = {}
	for i in PARTS.size():
		out[String(PARTS[i].id)] = i
	return out


static func ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for p: Dictionary in PARTS:
		out.append(String(p.id))
	return out


static func part(id: String) -> Dictionary:
	var i: int = index_of(id)
	return PARTS[i] if i >= 0 else {}


static func index_of(id: String) -> int:
	return int(_index.get(id, -1))


## The part id for a word the player typed: an id, a name or an alias, any case ("" unknown).
static func part_id(word: String) -> String:
	var w: String = word.strip_edges().to_lower()
	for p: Dictionary in PARTS:
		if w == String(p.id) or w == String(p.name).to_lower() or w == String(p.name).to_lower().replace(" ", "") or (p.alias as Array).has(w):
			return String(p.id)
	return ""


static func stock() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(PARTS.size())
	return out


static func is_stock(levels: PackedInt32Array) -> bool:
	for l in levels:
		if l != 0:
			return false
	return true


## A level for every part (0..its top) from an array (a save file's list: numbers; anything else reads as 0).
## (Files from v6.11-6.15 hold 0..3, which read the same; lists of four from before v6.21 leave the
## weight stock.)
static func clean(v: Variant) -> PackedInt32Array:
	var out: PackedInt32Array = stock()
	if v is Array or v is PackedInt32Array or v is PackedFloat64Array or v is PackedInt64Array:
		var a: Array = Array(v)
		for i in mini(a.size(), PARTS.size()):
			var x: Variant = a[i]
			if (x is int or x is float) and is_finite(float(x)):
				out[i] = clampi(int(x), 0, int(PARTS[i].get("max", MAX_LEVEL)))
	return out


## (v6.34) How many levels part `part` (an id or an index) has: MAX_LEVEL, 5 for the supercharger.
static func max_level(part: Variant) -> int:
	var i: int = part if part is int else index_of(String(part))
	return int(PARTS[i].get("max", MAX_LEVEL)) if i >= 0 and i < PARTS.size() else 0


## (v6.34) What opens part `part_id`: {part, level} (the supercharger: engine 5), {} for a part
## that is always open.
static func needs(part_id: String) -> Dictionary:
	var n: Variant = part(part_id).get("needs")
	return {part = String(n[0]), level = int(n[1])} if n is Array else {}


## (v6.34) Part `part_id` can be bought with these levels (the part it needs is at its level).
static func is_open(part_id: String, levels: PackedInt32Array) -> bool:
	var n: Dictionary = needs(part_id)
	return n.is_empty() or clean(levels)[index_of(String(n.part))] >= int(n.level)


## (v6.34) Part `part_id`'s levels are fitted with the trial (a miss pays half back).
static func has_trial(part_id: String) -> bool:
	return bool(part(part_id).get("trial", false))


## (v6.36) The parts with five levels, in words: "the supercharger, the aero tune, the brakes, the suspension, the wing and the nitro tune".
static func five_level_text() -> String:
	var names: PackedStringArray = []
	for p: Dictionary in PARTS:
		if int(p.get("max", MAX_LEVEL)) != MAX_LEVEL:
			names.append("the " + String(p.name).to_lower())
	if names.size() < 2:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


## The share of the stock value part `i` adds at `level` (0.15 for the engine at level 3, 0.325
## at level 10). Levels 1-3 are step × 1, 2, 3 exactly, as before v6.16. A five-level part (v6.34)
## adds `step` a level (the supercharger: 0.3 at level 5).
static func gain(i: int, level: int) -> float:
	var top: int = max_level(i)
	if top != MAX_LEVEL:
		return float(PARTS[i].step) * clampi(level, 0, top)
	return float(PARTS[i].step) * LEVEL_GAIN[clampi(level, 0, MAX_LEVEL)]


## The CarSpec fields an upgraded car changes, with the JS names (CarSpec.make() takes them).
## Stock levels: {}.
static func changes(car_id: String, levels: PackedInt32Array) -> Dictionary:
	var lv: PackedInt32Array = clean(levels)
	var s: CarSpec = Cars.spec(car_id)
	var out: Dictionary = {}
	var e: float = gain(0, lv[0])
	var t: float = gain(1, lv[1])
	var n: float = gain(2, lv[2])
	var l: float = gain(3, lv[3])
	var w: float = gain(4, lv[4])
	var sc: float = gain(5, lv[5])
	var ae: float = gain(6, lv[6])
	var bk: float = gain(7, lv[7])
	var su: int = lv[8]
	var wg: int = lv[9]
	var nt: float = gain(10, lv[10])
	if e > 0.0 or sc > 0.0:
		# (v6.34) the supercharger multiplies what the engine part gives
		var tq: Array = []
		for p: Variant in s.torque:
			tq.append([float(p[0]), float(p[1]) * (1.0 + e) * (1.0 + sc)])
		out.torque = tq
	if t > 0.0:
		out.mu = s.mu * (1.0 + t)
	if t > 0.0 or l > 0.0:
		# the shares of the (upgraded) asphalt grip: the loose part raises them, never above 1
		# (as much grip as on asphalt), and the tyres' factor comes off again, so the grip on
		# dirt and snow is mu × share × (1 + l) whatever the tyres
		out.dirtGrip = minf(1.0, s.dirt_grip * (1.0 + l)) / (1.0 + t)
		out.snowGrip = minf(1.0, s.snow_grip * (1.0 + l)) / (1.0 + t)
	if n > 0.0:
		out.nitroTime = s.nitro_time * (1.0 + n)
		out.nitroRefill = s.nitro_refill * (1.0 + n)
	if w > 0.0:
		# the yaw inertia goes down with the mass, so the car turns in as it did (the tyres' forces
		# follow the weight on them)
		out.mass = s.mass * (1.0 - w)
		out.inertia = s.inertia * (1.0 - w)
	if ae > 0.0:
		# (v6.35) the aero tune: less drag, and a top gear longer by the cube root of it (the speed
		# where the power meets the drag), so the higher top speed isn't cut off by the rev limiter
		# ((v6.38) the wing's drag on top: the tune's gear stays)
		out.drag = s.drag * (1.0 - ae) * (1.0 + WING_DRAG * wg)
		var g: Array = Array(s.gears)
		g[g.size() - 1] = float(g[g.size() - 1]) * pow(1.0 - ae, 1.0 / 3.0)
		out.gears = g
	if bk > 0.0:
		# (v6.36) the brakes: more force at full pedal, the same bias (the tyres' grip still caps each axle)
		out.brakeForce = s.brake_force * (1.0 + bk)
	if su > 0:
		# (v6.37) the suspension: a lower centre of gravity (less weight transfer), and landings that
		# take a harder hit before they cost speed and then cost less of it
		out.brakeDive = s.brake_dive * (1.0 - gain(8, su))
		out.hardLanding = s.hard_landing * (1.0 + SUSP_LANDING * su)
		out.landingLoss = s.landing_loss * (1.0 - SUSP_LANDING * su)
	if wg > 0:
		# (v6.38) the wing: downforce worth step x level of the stock car's weight at WING_KMH, and a
		# little drag (with the aero tune: on top of it, above)
		var v: float = WING_KMH / 3.6
		var add: float = gain(9, wg) * s.mass * CarSpec.G / (v * v)
		out.downforce = s.downforce + add
		out.aeroFront = (s.downforce * s.aero_front + add * WING_FRONT) / (s.downforce + add)
		if ae <= 0.0:
			out.drag = s.drag * (1.0 + WING_DRAG * wg)
	if nt > 0.0:
		# (v6.40) the nitro tune: a stronger push at every speed (the force at low speed and the power
		# at speed); the tank lasts as long and the push still fades out at the same speed (nitroTop:
		# most cars reach their rev limit in top gear before it anyway)
		out.nitroForce = s.nitro_force * (1.0 + nt)
		out.nitroPower = s.nitro_power * (1.0 + nt)
	return out


## Car `car_id` with `levels` (11 ints: engine, tyres, nitro, loose, weight, supercharger, aero, brakes, suspension, wing, nitro tune). Stock levels give the stock
## spec itself; others are made once and cached (a spec is read-only once a car uses it).
static func spec(car_id: String, levels: PackedInt32Array = PackedInt32Array()) -> CarSpec:
	var id: String = car_id if Cars.has_car(car_id) else Cars.DEFAULT_CAR
	var lv: PackedInt32Array = clean(levels)
	if is_stock(lv):
		return Cars.spec(id)
	var key: String = "%s:%s" % [id, ",".join(Array(lv).map(func(x: int) -> String: return str(x)))]
	_mutex.lock()
	var s: Variant = _specs.get(key)
	if s == null:
		var ch: Dictionary = changes(id, lv)
		ch.id = id
		s = CarSpec.make(ch, Cars.spec(id))
		_specs[key] = s
	_mutex.unlock()
	return s


## The player's car `car_id` with the levels bought for it (the save file's; stock when none).
static func player_spec(car_id: String) -> CarSpec:
	return spec(car_id, SaveData.get_upgrades(car_id))


## (v6.38) The levels a car races with on a track: `levels` with the track's setup (SaveData.get_setup:
## the wing at most `setup.wing`). A setup without a key leaves that part as bought.
static func with_setup(levels: PackedInt32Array, setup: Dictionary) -> PackedInt32Array:
	var lv: PackedInt32Array = clean(levels)
	var w: Variant = setup.get("wing")
	if w is int or w is float:
		lv[9] = clampi(int(w), 0, lv[9])
	return lv


## (v6.38) The levels car `car_id` races with on track `track_id`: the save file's, with its setup there.
static func race_levels(car_id: String, track_id: String) -> PackedInt32Array:
	return with_setup(SaveData.get_upgrades(car_id), SaveData.get_setup(car_id, track_id))


## What car `car_id` counts as when pricing its upgrades.
static func base_price(car_id: String) -> int:
	var p: int = int(Cars.get_car(car_id).get("price", 0)) if Cars.has_car(car_id) else 0
	return p if p > 0 else FREE_CAR_BASE


## The price of level `level` (1..MAX_LEVEL) of part `part_id` for car `car_id`; 0 otherwise.
static func price(car_id: String, part_id: String, level: int) -> int:
	var i: int = index_of(part_id)
	if i < 0 or level < 1 or level > max_level(i) or not Cars.has_car(car_id):
		return 0
	var share: float = LEVEL_SHARE[level - 1] if max_level(i) == MAX_LEVEL else TRIAL_SHARE[level - 1]
	if PARTS[i].has("share"):
		share = float(PARTS[i].share[level - 1])
	var v: float = base_price(car_id) * share * float(PARTS[i].cost)
	return roundi(v / ROUND) * ROUND


## Every level of every part of car `car_id`.
static func car_total(car_id: String) -> int:
	var out: int = 0
	for p: String in ids():
		for k in range(1, max_level(p) + 1):
			out += price(car_id, p, k)
	return out


## Every level of every part of every car.
static func total_all() -> int:
	var out: int = 0
	for id: String in Cars.ids():
		out += car_total(id)
	return out


## "E2 T1 N0 L3 W0" (records, the terminal; v6.34: "... S2" with a supercharger fitted).
static func code(levels: PackedInt32Array) -> String:
	var lv: PackedInt32Array = clean(levels)
	var parts: PackedStringArray = []
	for i in PARTS.size():
		if lv[i] > 0 or not bool(PARTS[i].get("extra", false)):
			parts.append("%s%d" % [PARTS[i].short, lv[i]])
	return " ".join(parts)


## "engine 2, tyres 1, nitro 0, loose grip 3, weight 0", or "stock".
static func text(levels: PackedInt32Array) -> String:
	var lv: PackedInt32Array = clean(levels)
	if is_stock(lv):
		return "stock"
	var parts: PackedStringArray = []
	for i in PARTS.size():
		if lv[i] > 0 or not bool(PARTS[i].get("extra", false)):
			parts.append("%s %d" % [String(PARTS[i].name).to_lower(), lv[i]])
	return ", ".join(parts)


## What `level` of part `part_id` adds over the stock car, in words ("+10 % power"; "stock" at 0).
static func effect(part_id: String, level: int) -> String:
	var i: int = index_of(part_id)
	if i < 0 or level <= 0:
		return "stock"
	return String(PARTS[i].effect) % roundi(gain(i, level) * 100.0)


## The car's stats (sim/cars.gd `stats`) with the measured effect of the engine and the tyres
## (MEASURED) and the nitro tank's length; the other numbers stay the stock car's. (v6.21) The
## weight part gives the mass, and what it was measured to do alone (MEASURED.weight) goes on top
## of the engine's and the tyres' numbers as the same share (a lighter car with a stronger engine
## is a little better still than each alone; the bars need no more than that).
static func stats(car_id: String, levels: PackedInt32Array) -> Dictionary:
	var stock_stats: Dictionary = Cars.get_car(car_id).stats
	var out: Dictionary = stock_stats.duplicate()
	var lv: PackedInt32Array = clean(levels)
	var m: Dictionary = MEASURED.get(car_id, {})
	if lv[0] > 0 and m.get("engine") is Array and (m.engine as Array).size() >= lv[0]:
		out.merge(m.engine[lv[0] - 1], true)
	if lv[1] > 0 and m.get("tyres") is Array and (m.tyres as Array).size() >= lv[1]:
		out.merge(m.tyres[lv[1] - 1], true)
	if lv[2] > 0:
		out.tankTime = float(out.tankTime) * (1.0 + gain(2, lv[2]))
	if lv[4] > 0:
		out.mass = roundf(float(stock_stats.mass) * (1.0 - gain(4, lv[4])))
		if m.get("weight") is Array and (m.weight as Array).size() >= lv[4]:
			var mw: Dictionary = m.weight[lv[4] - 1]
			for key: String in WEIGHT_KEYS:
				if mw.has(key) and float(stock_stats.get(key, 0.0)) > 0.0:
					out[key] = float(out[key]) * float(mw[key]) / float(stock_stats[key])
	if lv[9] > 0 and m.get("wing") is Array and (m.wing as Array).size() >= lv[9]:
		# (v6.38) the wing's measured share of each stat (grip at speed up, top speed down), on top
		var mg: Dictionary = m.wing[lv[9] - 1]
		for key: String in WEIGHT_KEYS:
			if mg.has(key) and float(stock_stats.get(key, 0.0)) > 0.0:
				out[key] = float(out[key]) * float(mg[key]) / float(stock_stats[key])
	for i: int in [7, 8]:
		# (v6.36) the brakes' and (v6.37) the suspension's measured stop as a share of the stock one (on
		# top of the weight's)
		var pid := String(PARTS[i].id)
		if lv[i] > 0 and m.get(pid) is Array and (m[pid] as Array).size() >= lv[i] and float(stock_stats.get("brake100", 0.0)) > 0.0:
			out.brake100 = float(out.brake100) * float(m[pid][lv[i] - 1].brake100) / float(stock_stats.brake100)
	# (v6.34-6.35) a part another one opens was measured on that part's level (the supercharger on
	# engine 5, the aero tune on weight 5): its share over that goes on top
	for i in PARTS.size():
		var nd: Array = PARTS[i].get("needs", [])
		var pid := String(PARTS[i].id)
		if lv[i] <= 0 or nd.is_empty() or not (m.get(pid) is Array) or (m[pid] as Array).size() < lv[i] or not (m.get(nd[0]) is Array) or \
				(m[nd[0]] as Array).size() < int(nd[1]):
			continue
		var base: Dictionary = m[nd[0]][int(nd[1]) - 1]
		var ms: Dictionary = m[pid][lv[i] - 1]
		for key: String in TRIAL_KEYS:
			if ms.has(key) and float(base.get(key, 0.0)) > 0.0:
				out[key] = float(out[key]) * float(ms[key]) / float(base[key])
	return out


## The car picker's bars of car `car_id` with `levels` (Cars.stat_bars of stats()).
static func bars(car_id: String, levels: PackedInt32Array) -> Dictionary:
	return Cars.stat_bars(stats(car_id, levels), spec(car_id, levels))
