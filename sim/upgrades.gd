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
## Never changed: max_speed (it scales the AI's speed input, so a network sees the same range in an
## upgraded car), the brakes, the steering and the stability control: an upgraded car keeps its
## character. Levels 0, 0, 0, 0, 0 are the stock car itself (Cars.spec(id), the same object), so
## stock runs stay bit for bit what they were.
## Medal times and the AI opponents are always the stock cars' (data/medals.json, data/opponents):
## upgrades make medals and AI wins easier, on purpose; rewards are still paid once.
##
## Prices: level k of a part costs the car's base price × LEVEL_SHARE[k - 1] × the part's `cost`,
## rounded to $50 (the base price is the car's shop price; a car that costs nothing, the Racer,
## counts as FREE_CAR_BASE). Levels 1-3 cost what they did; from level 4 the price climbs steeply
## (levels 8-10 of a part cost about 11 × levels 1-3 together: a late-career goal). Every part of
## every car costs total_all() (see the README).
## Data-driven: PARTS and LEVEL_SHARE are the whole table; MEASURED is what tools/upgrades.gd
## measured with the real physics for the car picker's bars (`tools/upgrades.gd --check` measures
## again and compares; the tests check each level's gain is in range).
##
##   Upgrades.ids() -> ["engine", "tyres", "nitro", "loose", "weight"];  Upgrades.part(id) -> {...} or {}
##   Upgrades.index_of(id) -> 0..4 (-1 unknown);  Upgrades.part_id(word) -> id for a part name
##       or alias ("tires", "grip", "dirt", "lighter" ...), "" unknown
##   Upgrades.stock() -> PackedInt32Array [0, 0, 0, 0, 0];  Upgrades.is_stock(levels)
##   Upgrades.clean(v) -> PackedInt32Array of 5 levels 0..MAX_LEVEL from anything (junk: 0; over
##       the top: MAX_LEVEL; a list of four from before v6.21: the weight stock)
##   Upgrades.changes(car_id, levels) -> the CarSpec fields that differ (JS names)
##   Upgrades.spec(car_id, levels) -> CarSpec (cached; stock levels: Cars.spec(car_id))
##   Upgrades.player_spec(car_id) -> the car with the levels the save file holds
##   Upgrades.price(car_id, part, level) -> $ for that level (1..MAX_LEVEL), 0 otherwise
##   Upgrades.car_total(car_id) / total_all() -> $ for every level of every part
##   Upgrades.code(levels) -> "E2 T1 N0 L3 W0";  Upgrades.text(levels) -> "engine 2, tyres 1, ..."
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
## The base price of a car that costs nothing in the shop (the Racer: between the Kestrel and the Drifter).
const FREE_CAR_BASE: int = 12000
## Prices are rounded to this many dollars.
const ROUND: int = 50

## The parts, in the picker's order. step: the share of the stock value each level adds; cost:
## × the car's base price share; alias: other words the terminal takes; what: what it does (one
## line), effect: the picker's "+5 % power" per level ("%d" = the level's percentage).
## The order is the save file's (a car's `up` list) and the keys' (1-5): new parts go at the end.
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
]

## Measured with the real physics by tools/upgrades.gd (tools/car_stats.gd's measurements of the
## upgraded specs): per car, the engine's levels 1-10 {top, accel100, accel200}, the tyres'
## levels 1-10 {grip, gripFast} and (v6.21) the weight's levels 1-10 {top, accel100, accel200,
## brake100, grip, gripFast}; the car page's bars use them. Filled by the tool; tests check it.
const MEASURED: Dictionary = {
	racer = {
		engine = [{top = 282.7, accel100 = 2.57, accel200 = 9.23}, {top = 286.2, accel100 = 2.47, accel200 = 8.77}, {top = 289.5, accel100 = 2.37, accel200 = 8.33}, {top = 292, accel100 = 2.28, accel200 = 8.03}, {top = 294.2, accel100 = 2.25, accel200 = 7.8}, {top = 295.9, accel100 = 2.22, accel200 = 7.6}, {top = 297.2, accel100 = 2.18, accel200 = 7.45}, {top = 297.2, accel100 = 2.17, accel200 = 7.35}, {top = 297.2, accel100 = 2.15, accel200 = 7.27}, {top = 297.2, accel100 = 2.13, accel200 = 7.22}],
		tyres = [{grip = 1.75, gripFast = 1.64}, {grip = 1.82, gripFast = 1.7}, {grip = 1.89, gripFast = 1.73}, {grip = 1.97, gripFast = 1.79}, {grip = 2.01, gripFast = 1.83}, {grip = 2.05, gripFast = 1.83}, {grip = 2.09, gripFast = 1.83}, {grip = 2.09, gripFast = 1.83}, {grip = 2.13, gripFast = 1.83}, {grip = 2.13, gripFast = 1.83}],
		weight = [{top = 277.8, accel100 = 2.62, accel200 = 9.5, brake100 = 30.1, grip = 1.68, gripFast = 1.58}, {top = 278, accel100 = 2.55, accel200 = 9.22, brake100 = 29.5, grip = 1.68, gripFast = 1.58}, {top = 278.1, accel100 = 2.47, accel200 = 8.93, brake100 = 28.9, grip = 1.69, gripFast = 1.58}, {top = 278.2, accel100 = 2.4, accel200 = 8.7, brake100 = 28.4, grip = 1.69, gripFast = 1.58}, {top = 278.3, accel100 = 2.35, accel200 = 8.52, brake100 = 28, grip = 1.69, gripFast = 1.58}, {top = 278.4, accel100 = 2.32, accel200 = 8.35, brake100 = 27.7, grip = 1.69, gripFast = 1.58}, {top = 278.4, accel100 = 2.28, accel200 = 8.22, brake100 = 27.4, grip = 1.69, gripFast = 1.58}, {top = 278.5, accel100 = 2.27, accel200 = 8.12, brake100 = 27.2, grip = 1.69, gripFast = 1.58}, {top = 278.5, accel100 = 2.25, accel200 = 8.03, brake100 = 27, grip = 1.69, gripFast = 1.58}, {top = 278.5, accel100 = 2.23, accel200 = 7.98, brake100 = 26.9, grip = 1.69, gripFast = 1.61}],
	},
	kestrel = {
		engine = [{top = 233, accel100 = 2.35, accel200 = 10.52}, {top = 235.6, accel100 = 2.27, accel200 = 9.87}, {top = 237.7, accel100 = 2.2, accel200 = 9.3}, {top = 239.4, accel100 = 2.15, accel200 = 8.9}, {top = 240.8, accel100 = 2.12, accel200 = 8.58}, {top = 241.9, accel100 = 2.08, accel200 = 8.33}, {top = 242.9, accel100 = 2.07, accel200 = 8.15}, {top = 243.6, accel100 = 2.05, accel200 = 8.02}, {top = 244.2, accel100 = 2.03, accel200 = 7.9}, {top = 244.5, accel100 = 2.03, accel200 = 7.83}],
		tyres = [{grip = 1.85, gripFast = 1.65}, {grip = 1.93, gripFast = 1.68}, {grip = 2, gripFast = 1.71}, {grip = 2.04, gripFast = 1.72}, {grip = 2.09, gripFast = 1.72}, {grip = 2.13, gripFast = 1.72}, {grip = 2.17, gripFast = 1.72}, {grip = 2.21, gripFast = 1.72}, {grip = 2.21, gripFast = 1.72}, {grip = 2.25, gripFast = 1.72}],
		weight = [{top = 230.3, accel100 = 2.38, accel200 = 10.98, brake100 = 27.2, grip = 1.78, gripFast = 1.6}, {top = 230.4, accel100 = 2.33, accel200 = 10.67, brake100 = 26.7, grip = 1.78, gripFast = 1.6}, {top = 230.4, accel100 = 2.28, accel200 = 10.35, brake100 = 26.2, grip = 1.78, gripFast = 1.6}, {top = 230.5, accel100 = 2.23, accel200 = 10.1, brake100 = 25.8, grip = 1.78, gripFast = 1.6}, {top = 230.5, accel100 = 2.2, accel200 = 9.88, brake100 = 25.5, grip = 1.78, gripFast = 1.6}, {top = 230.6, accel100 = 2.17, accel200 = 9.68, brake100 = 25.2, grip = 1.75, gripFast = 1.6}, {top = 230.6, accel100 = 2.15, accel200 = 9.53, brake100 = 24.9, grip = 1.75, gripFast = 1.57}, {top = 230.6, accel100 = 2.13, accel200 = 9.42, brake100 = 24.7, grip = 1.75, gripFast = 1.57}, {top = 230.6, accel100 = 2.12, accel200 = 9.32, brake100 = 24.5, grip = 1.75, gripFast = 1.57}, {top = 230.7, accel100 = 2.1, accel200 = 9.27, brake100 = 24.4, grip = 1.75, gripFast = 1.57}],
	},
	thunder = {
		engine = [{top = 318.7, accel100 = 2.58, accel200 = 7.8}, {top = 323.8, accel100 = 2.52, accel200 = 7.48}, {top = 327.9, accel100 = 2.47, accel200 = 7.18}, {top = 331.1, accel100 = 2.43, accel200 = 6.98}, {top = 333.8, accel100 = 2.42, accel200 = 6.82}, {top = 334.9, accel100 = 2.38, accel200 = 6.67}, {top = 334.9, accel100 = 2.37, accel200 = 6.57}, {top = 334.9, accel100 = 2.35, accel200 = 6.48}, {top = 334.9, accel100 = 2.35, accel200 = 6.42}, {top = 334.9, accel100 = 2.33, accel200 = 6.38}],
		tyres = [{grip = 1.53, gripFast = 1.62}, {grip = 1.62, gripFast = 1.68}, {grip = 1.69, gripFast = 1.74}, {grip = 1.72, gripFast = 1.77}, {grip = 1.76, gripFast = 1.84}, {grip = 1.83, gripFast = 1.87}, {grip = 1.83, gripFast = 1.9}, {grip = 1.86, gripFast = 1.94}, {grip = 1.9, gripFast = 1.94}, {grip = 1.9, gripFast = 1.94}],
		weight = [{top = 312.9, accel100 = 2.62, accel200 = 7.98, brake100 = 33, grip = 1.47, gripFast = 1.56}, {top = 313, accel100 = 2.57, accel200 = 7.77, brake100 = 32.3, grip = 1.47, gripFast = 1.56}, {top = 313.1, accel100 = 2.52, accel200 = 7.57, brake100 = 31.6, grip = 1.47, gripFast = 1.56}, {top = 313.3, accel100 = 2.48, accel200 = 7.4, brake100 = 31.1, grip = 1.5, gripFast = 1.59}, {top = 313.4, accel100 = 2.47, accel200 = 7.27, brake100 = 30.6, grip = 1.5, gripFast = 1.59}, {top = 313.4, accel100 = 2.45, accel200 = 7.15, brake100 = 30.2, grip = 1.5, gripFast = 1.59}, {top = 313.5, accel100 = 2.43, accel200 = 7.05, brake100 = 29.9, grip = 1.5, gripFast = 1.59}, {top = 313.6, accel100 = 2.42, accel200 = 6.97, brake100 = 29.6, grip = 1.5, gripFast = 1.59}, {top = 313.6, accel100 = 2.4, accel200 = 6.92, brake100 = 29.4, grip = 1.5, gripFast = 1.62}, {top = 313.6, accel100 = 2.4, accel200 = 6.88, brake100 = 29.3, grip = 1.5, gripFast = 1.62}],
	},
	drifter = {
		engine = [{top = 268.5, accel100 = 2.45, accel200 = 8.77}, {top = 272.3, accel100 = 2.38, accel200 = 8.35}, {top = 275.7, accel100 = 2.35, accel200 = 7.98}, {top = 278.3, accel100 = 2.32, accel200 = 7.73}, {top = 280.5, accel100 = 2.28, accel200 = 7.52}, {top = 282.3, accel100 = 2.27, accel200 = 7.35}, {top = 283.8, accel100 = 2.25, accel200 = 7.22}, {top = 285, accel100 = 2.23, accel200 = 7.12}, {top = 285.5, accel100 = 2.22, accel200 = 7.05}, {top = 285.5, accel100 = 2.22, accel200 = 7}],
		tyres = [{grip = 1.68, gripFast = 1.58}, {grip = 1.75, gripFast = 1.61}, {grip = 1.82, gripFast = 1.67}, {grip = 1.86, gripFast = 1.7}, {grip = 1.93, gripFast = 1.76}, {grip = 1.97, gripFast = 1.76}, {grip = 2.01, gripFast = 1.79}, {grip = 2.01, gripFast = 1.82}, {grip = 2.05, gripFast = 1.82}, {grip = 2.05, gripFast = 1.82}],
		weight = [{top = 264.4, accel100 = 2.47, accel200 = 9, brake100 = 32.5, grip = 1.59, gripFast = 1.52}, {top = 264.5, accel100 = 2.43, accel200 = 8.77, brake100 = 31.9, grip = 1.59, gripFast = 1.52}, {top = 264.6, accel100 = 2.4, accel200 = 8.53, brake100 = 31.4, grip = 1.59, gripFast = 1.52}, {top = 264.6, accel100 = 2.37, accel200 = 8.37, brake100 = 30.9, grip = 1.59, gripFast = 1.52}, {top = 264.7, accel100 = 2.35, accel200 = 8.2, brake100 = 30.5, grip = 1.59, gripFast = 1.52}, {top = 264.8, accel100 = 2.32, accel200 = 8.07, brake100 = 30.1, grip = 1.59, gripFast = 1.52}, {top = 264.8, accel100 = 2.32, accel200 = 7.95, brake100 = 29.8, grip = 1.59, gripFast = 1.52}, {top = 264.9, accel100 = 2.3, accel200 = 7.87, brake100 = 29.5, grip = 1.6, gripFast = 1.52}, {top = 264.9, accel100 = 2.28, accel200 = 7.8, brake100 = 29.4, grip = 1.6, gripFast = 1.52}, {top = 264.9, accel100 = 2.28, accel200 = 7.75, brake100 = 29.2, grip = 1.6, gripFast = 1.52}],
	},
	dune = {
		engine = [{top = 225.8, accel100 = 2.78, accel200 = 11.73}, {top = 228.9, accel100 = 2.72, accel200 = 10.95}, {top = 231.6, accel100 = 2.67, accel200 = 10.28}, {top = 233.7, accel100 = 2.62, accel200 = 9.83}, {top = 235.4, accel100 = 2.58, accel200 = 9.47}, {top = 236.9, accel100 = 2.55, accel200 = 9.18}, {top = 238.1, accel100 = 2.52, accel200 = 8.97}, {top = 238.5, accel100 = 2.5, accel200 = 8.8}, {top = 238.5, accel100 = 2.48, accel200 = 8.68}, {top = 238.5, accel100 = 2.48, accel200 = 8.62}],
		tyres = [{grip = 1.78, gripFast = 1.48}, {grip = 1.85, gripFast = 1.56}, {grip = 1.92, gripFast = 1.58}, {grip = 1.96, gripFast = 1.58}, {grip = 2, gripFast = 1.58}, {grip = 2.08, gripFast = 1.59}, {grip = 2.08, gripFast = 1.61}, {grip = 2.12, gripFast = 1.61}, {grip = 2.16, gripFast = 1.61}, {grip = 2.16, gripFast = 1.61}],
		weight = [{top = 222.5, accel100 = 2.82, accel200 = 12.35, brake100 = 31.2, grip = 1.71, gripFast = 1.43}, {top = 222.6, accel100 = 2.78, accel200 = 12.02, brake100 = 30.6, grip = 1.71, gripFast = 1.43}, {top = 222.7, accel100 = 2.73, accel200 = 11.68, brake100 = 30.1, grip = 1.71, gripFast = 1.43}, {top = 222.7, accel100 = 2.7, accel200 = 11.42, brake100 = 29.7, grip = 1.71, gripFast = 1.43}, {top = 222.8, accel100 = 2.67, accel200 = 11.18, brake100 = 29.3, grip = 1.71, gripFast = 1.43}, {top = 222.8, accel100 = 2.63, accel200 = 10.98, brake100 = 28.9, grip = 1.71, gripFast = 1.43}, {top = 222.8, accel100 = 2.62, accel200 = 10.82, brake100 = 28.6, grip = 1.71, gripFast = 1.43}, {top = 222.9, accel100 = 2.6, accel200 = 10.7, brake100 = 28.4, grip = 1.71, gripFast = 1.43}, {top = 222.9, accel100 = 2.58, accel200 = 10.6, brake100 = 28.2, grip = 1.72, gripFast = 1.43}, {top = 222.9, accel100 = 2.58, accel200 = 10.53, brake100 = 28.1, grip = 1.72, gripFast = 1.43}],
	},
	vortex = {
		engine = [{top = 328.5, accel100 = 2.45, accel200 = 5.92}, {top = 335.3, accel100 = 2.33, accel200 = 5.63}, {top = 342, accel100 = 2.25, accel200 = 5.4}, {top = 347.1, accel100 = 2.22, accel200 = 5.27}, {top = 350.8, accel100 = 2.2, accel200 = 5.17}, {top = 353.9, accel100 = 2.18, accel200 = 5.08}, {top = 356.4, accel100 = 2.17, accel200 = 5.02}, {top = 358.4, accel100 = 2.15, accel200 = 4.97}, {top = 359.9, accel100 = 2.15, accel200 = 4.93}, {top = 360.9, accel100 = 2.13, accel200 = 4.92}],
		tyres = [{grip = 1.75, gripFast = 1.85}, {grip = 1.82, gripFast = 1.92}, {grip = 1.9, gripFast = 1.98}, {grip = 1.98, gripFast = 2.08}, {grip = 2.02, gripFast = 2.12}, {grip = 2.06, gripFast = 2.16}, {grip = 2.1, gripFast = 2.2}, {grip = 2.14, gripFast = 2.24}, {grip = 2.14, gripFast = 2.24}, {grip = 2.18, gripFast = 2.29}],
		weight = [{top = 321.5, accel100 = 2.5, accel200 = 6.05, brake100 = 28.2, grip = 1.68, gripFast = 1.78}, {top = 321.7, accel100 = 2.42, accel200 = 5.87, brake100 = 27.6, grip = 1.69, gripFast = 1.78}, {top = 321.8, accel100 = 2.35, accel200 = 5.68, brake100 = 27.1, grip = 1.69, gripFast = 1.78}, {top = 321.9, accel100 = 2.28, accel200 = 5.55, brake100 = 26.6, grip = 1.69, gripFast = 1.82}, {top = 322, accel100 = 2.25, accel200 = 5.43, brake100 = 26.2, grip = 1.69, gripFast = 1.82}, {top = 322, accel100 = 2.22, accel200 = 5.35, brake100 = 25.9, grip = 1.69, gripFast = 1.82}, {top = 322.1, accel100 = 2.2, accel200 = 5.28, brake100 = 25.6, grip = 1.69, gripFast = 1.85}, {top = 322.2, accel100 = 2.2, accel200 = 5.25, brake100 = 25.4, grip = 1.69, gripFast = 1.85}, {top = 322.2, accel100 = 2.18, accel200 = 5.2, brake100 = 25.2, grip = 1.69, gripFast = 1.85}, {top = 322.2, accel100 = 2.18, accel200 = 5.18, brake100 = 25.1, grip = 1.69, gripFast = 1.85}],
	},
	apex = {
		engine = [{top = 288.5, accel100 = 2.58, accel200 = 6.12}, {top = 292.9, accel100 = 2.58, accel200 = 5.95}, {top = 297, accel100 = 2.58, accel200 = 5.82}, {top = 299.7, accel100 = 2.58, accel200 = 5.72}, {top = 302, accel100 = 2.58, accel200 = 5.63}, {top = 303.8, accel100 = 2.58, accel200 = 5.57}, {top = 305.4, accel100 = 2.58, accel200 = 5.52}, {top = 306.6, accel100 = 2.58, accel200 = 5.48}, {top = 307.5, accel100 = 2.58, accel200 = 5.47}, {top = 308, accel100 = 2.58, accel200 = 5.45}],
		tyres = [{grip = 2.14, gripFast = 2.42}, {grip = 2.23, gripFast = 2.42}, {grip = 2.36, gripFast = 2.42}, {grip = 2.41, gripFast = 2.42}, {grip = 2.51, gripFast = 2.42}, {grip = 2.56, gripFast = 2.43}, {grip = 2.62, gripFast = 2.43}, {grip = 2.67, gripFast = 2.43}, {grip = 2.72, gripFast = 2.43}, {grip = 2.72, gripFast = 2.43}],
		weight = [{top = 284, accel100 = 2.58, accel200 = 6.2, brake100 = 20.6, grip = 2.05, gripFast = 2.42}, {top = 284.1, accel100 = 2.58, accel200 = 6.12, brake100 = 20.5, grip = 2.06, gripFast = 2.42}, {top = 284.1, accel100 = 2.58, accel200 = 6.02, brake100 = 20.5, grip = 2.06, gripFast = 2.42}, {top = 284.2, accel100 = 2.57, accel200 = 5.95, brake100 = 20.4, grip = 2.1, gripFast = 2.43}, {top = 284.2, accel100 = 2.57, accel200 = 5.88, brake100 = 20.3, grip = 2.1, gripFast = 2.43}, {top = 284.3, accel100 = 2.57, accel200 = 5.82, brake100 = 20.3, grip = 2.1, gripFast = 2.47}, {top = 284.3, accel100 = 2.57, accel200 = 5.78, brake100 = 20.2, grip = 2.1, gripFast = 2.47}, {top = 284.3, accel100 = 2.57, accel200 = 5.73, brake100 = 20.2, grip = 2.1, gripFast = 2.47}, {top = 284.3, accel100 = 2.57, accel200 = 5.72, brake100 = 20.2, grip = 2.15, gripFast = 2.47}, {top = 284.3, accel100 = 2.57, accel200 = 5.68, brake100 = 20.2, grip = 2.15, gripFast = 2.47}],
	},
}

## What the weight part's measurements hold (MEASURED.weight; stats() scales these).
const WEIGHT_KEYS: Array[String] = ["top", "accel100", "accel200", "brake100", "grip", "gripFast"]

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


## Five levels 0..MAX_LEVEL from an array (a save file's list: numbers; anything else reads as 0).
## (Files from v6.11-6.15 hold 0..3, which read the same; lists of four from before v6.21 leave the
## weight stock.)
static func clean(v: Variant) -> PackedInt32Array:
	var out: PackedInt32Array = stock()
	if v is Array or v is PackedInt32Array or v is PackedFloat64Array or v is PackedInt64Array:
		var a: Array = Array(v)
		for i in mini(a.size(), PARTS.size()):
			var x: Variant = a[i]
			if (x is int or x is float) and is_finite(float(x)):
				out[i] = clampi(int(x), 0, MAX_LEVEL)
	return out


## The share of the stock value part `i` adds at `level` (0.15 for the engine at level 3, 0.325
## at level 10). Levels 1-3 are step × 1, 2, 3 exactly, as before v6.16.
static func gain(i: int, level: int) -> float:
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
	if e > 0.0:
		var tq: Array = []
		for p: Variant in s.torque:
			tq.append([float(p[0]), float(p[1]) * (1.0 + e)])
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
	return out


## Car `car_id` with `levels` (5 ints: engine, tyres, nitro, loose, weight). Stock levels give the stock
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


## What car `car_id` counts as when pricing its upgrades.
static func base_price(car_id: String) -> int:
	var p: int = int(Cars.get_car(car_id).get("price", 0)) if Cars.has_car(car_id) else 0
	return p if p > 0 else FREE_CAR_BASE


## The price of level `level` (1..MAX_LEVEL) of part `part_id` for car `car_id`; 0 otherwise.
static func price(car_id: String, part_id: String, level: int) -> int:
	var i: int = index_of(part_id)
	if i < 0 or level < 1 or level > MAX_LEVEL or not Cars.has_car(car_id):
		return 0
	var v: float = base_price(car_id) * LEVEL_SHARE[level - 1] * float(PARTS[i].cost)
	return roundi(v / ROUND) * ROUND


## Every level of every part of car `car_id`.
static func car_total(car_id: String) -> int:
	var out: int = 0
	for p: String in ids():
		for k in range(1, MAX_LEVEL + 1):
			out += price(car_id, p, k)
	return out


## Every level of every part of every car.
static func total_all() -> int:
	var out: int = 0
	for id: String in Cars.ids():
		out += car_total(id)
	return out


## "E2 T1 N0 L3 W0" (records, the terminal).
static func code(levels: PackedInt32Array) -> String:
	var lv: PackedInt32Array = clean(levels)
	var parts: PackedStringArray = []
	for i in PARTS.size():
		parts.append("%s%d" % [PARTS[i].short, lv[i]])
	return " ".join(parts)


## "engine 2, tyres 1, nitro 0, loose grip 3, weight 0", or "stock".
static func text(levels: PackedInt32Array) -> String:
	var lv: PackedInt32Array = clean(levels)
	if is_stock(lv):
		return "stock"
	var parts: PackedStringArray = []
	for i in PARTS.size():
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
	return out


## The car picker's bars of car `car_id` with `levels` (Cars.stat_bars of stats()).
static func bars(car_id: String, levels: PackedInt32Array) -> Dictionary:
	return Cars.stat_bars(stats(car_id, levels), spec(car_id, levels))
