extends RefCounted
## ai_link.gd
## ------------------------------------------------------------------
## The game's one door to the AI (ai/: NeuralNetwork, Sensors, Trainer). The scripts are
## loaded by path when first needed instead of being named in the game's code, so a build
## without them (or with one that fails to load) still runs: the menu then says the AI is not
## ready and Race / Watch / Train / Load network show that note instead of crashing.
##
##   AiLink.ready()                     -> true when the AI scripts load
##   AiLink.not_ready_text()            the note for the player when they don't
##   AiLink.parse_network_file(data)    -> {net, meta} or {error}   (Trainer.parse_network_file)
##   AiLink.network_file(net, meta)     -> the web file format       (Trainer.network_file)
##   AiLink.saved_wall_rule(meta)       -> "ride" | "crash" | ""
##   AiLink.network_car(meta)           -> the car id a network file was trained with (none: "racer")
##   AiLink.driver(net)                 -> a Sensors.AIDriver: drive(track, car, race) -> Car.Controls, rays
##   AiLink.sensor_range(), AiLink.labels() -> {inputs, outputs}
## A network handed around the game is {net: NeuralNetwork, meta: Dictionary} (the parsed file).
## Every car has its own (SaveData.load_network(car)): the network a car's AI drives with. Its
## file's "car" says which car it was trained with, which can be another one (a loaded file).

const NETWORK_PATH := "res://ai/network.gd"
const SENSORS_PATH := "res://ai/sensors.gd"
const TRAINER_PATH := "res://ai/trainer.gd"

static var _scripts: Dictionary = {}
static var _tried := false


## Load the AI scripts once. False when any of them is missing or doesn't compile.
static func ready() -> bool:
	if not _tried:
		_tried = true
		for p: String in [NETWORK_PATH, SENSORS_PATH, TRAINER_PATH]:
			if not ResourceLoader.exists(p):
				_scripts.clear()
				break
			var s: Variant = load(p)
			if not (s is GDScript) or not (s as GDScript).can_instantiate():
				_scripts.clear()
				break
			_scripts[p] = s
	return _scripts.size() == 3


static func not_ready_text() -> String:
	return "AI not ready: the AI driver (ai/) is not part of this build or failed to load."


static func _trainer() -> GDScript:
	return _scripts.get(TRAINER_PATH) if ready() else null


static func _sensors() -> GDScript:
	return _scripts.get(SENSORS_PATH) if ready() else null


## Parse a network file (Dictionary, or JSON text): {net, meta} or {error: message for the player}.
static func parse_network_file(data: Variant) -> Dictionary:
	if not ready():
		return {"error": not_ready_text()}
	var r: Variant = _trainer().call("parse_network_file", data)
	return r if r is Dictionary else {"error": "Not a network file"}


## A loaded network as a file (the web format), keeping the training info of `meta`.
static func network_file(net: Object, meta: Dictionary = {}) -> Dictionary:
	return _trainer().call("network_file", net, meta) if ready() else {}


## The wall rule a network file was trained with ("ride" | "crash"), or "".
static func saved_wall_rule(meta: Variant) -> String:
	return str(_trainer().call("saved_wall_rule", meta)) if ready() else ""


## The car (sim/cars.gd id) a network file was trained with: its "car"; files without one (older
## ones, the browser version's, bare networks) are Racer networks.
static func network_car(meta: Variant) -> String:
	return str(_trainer().call("network_car", meta)) if ready() else Cars.DEFAULT_CAR


## A driver for one AI car (Watch the AI, the AI ghost): drive(track, car, race) every step.
static func driver(net: Object) -> Object:
	if not ready():
		return null
	var cls: Variant = _sensors().get("AIDriver")
	return (cls as Variant).new(net) if cls != null else null


static func sensor_range() -> float:
	return float(_sensors().get("SENSOR_RANGE")) if ready() else 100.0


## The network's input and output names (sensors.gd INPUT_LABELS / OUTPUT_LABELS).
static func labels() -> Dictionary:
	if not ready():
		return {}
	return {"inputs": Array(_sensors().get("INPUT_LABELS")), "outputs": Array(_sensors().get("OUTPUT_LABELS"))}


## A copy of a network (each mode drives its own; NeuralNetwork.clone).
static func clone_net(net: Object) -> Object:
	return net.call("clone") if net != null else null


## The menu's summary of car `car_id`'s network {net, meta} (UiData.ai_status's fields), or null.
## trained_car is the car the network was trained with (another one than car_id for a file
## trained with another car).
static func status_of(network: Dictionary, car_id: String = Cars.DEFAULT_CAR) -> Variant:
	if network.is_empty() or not ready():
		return null
	var meta: Dictionary = network.get("meta", {})
	var sizes: Array = []
	for n: int in network.net.get("sizes"):
		sizes.append(n)
	var on: Variant = meta.get("trainedOn")
	var best: Variant = meta.get("bestTimes")
	return {
		"generation": int(meta.generation) if (meta.get("generation") is float or meta.get("generation") is int) else "?",
		"fitness": float(meta.fitness) if (meta.get("fitness") is float or meta.get("fitness") is int) else 0.0,
		"sizes": sizes,
		"trained_on": on if on is Array else [],
		"walls": saved_wall_rule(meta),
		"best_times": best if best is Dictionary else {},
		"car": car_id,
		"trained_car": network_car(meta),
	}
