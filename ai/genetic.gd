class_name Population
extends RefCounted
## genetic.gd: a port of web/src/ai/genetic.js.
## ------------------------------------------------------------------
## Neuroevolution: a population of networks is scored by driving, then the
## next generation is bred from the best ones.
##
##   - Elitism: the top few networks survive unchanged (we never lose the best).
##   - Tournament selection picks parents (fitter cars win more often).
##   - Crossover mixes two parents neuron by neuron.
##   - Mutation nudges random weights, controlled by `mutation_rate`.
##   - A couple of brand-new random networks keep diversity up.
##
## Random numbers come from NeuralNetwork.rng.
##
##   var pop := Population.new({size = 80, sizes = [18, 12, 2], mutation_rate = 0.1,
##                              seed = net (optional), seed_fitness = 1234.0 (optional)})
##   pop.genomes[i].fitness = ...; var stats := pop.evolve()   # {best, avg}
##   pop.best_ever   # {net, fitness} or null


## One member of the population.
class Genome:
	var net: NeuralNetwork
	var fitness: float = 0.0

	func _init(p_net: NeuralNetwork, p_fitness: float = 0.0) -> void:
		net = p_net
		fitness = p_fitness


## The best network so far (a copy) and its fitness.
class Best:
	var net: NeuralNetwork
	var fitness: float = 0.0

	func _init(p_net: NeuralNetwork, p_fitness: float) -> void:
		net = p_net
		fitness = p_fitness


var sizes: PackedInt32Array = PackedInt32Array()
var mutation_rate: float = 0.1
## (v6.15) output neurons that start silent in every new random network (NeuralNetwork.silence_output:
## weights and bias 0); the trainer names the nitro output, so new drivers start without nitro and
## mutation brings it in where it pays. Drawn after the random weights: the random sequence is the same.
var silent_outputs: PackedInt32Array = PackedInt32Array()
var genomes: Array[Genome] = []
## Best or null
var best_ever: Best = null


## cfg: {size, sizes, mutation_rate, seed: NeuralNetwork (optional), seed_fitness: float
## (optional: the seed's score, when it is comparable with this run's scores), silent_outputs
## (optional, v6.15: see the variable)}.
func _init(cfg: Dictionary = {}) -> void:
	sizes = PackedInt32Array(cfg.get("sizes", []))
	mutation_rate = float(cfg.get("mutation_rate", 0.1))
	silent_outputs = PackedInt32Array(cfg.get("silent_outputs", []))
	var size: int = int(cfg.get("size", 0))
	var seed: NeuralNetwork = cfg.get("seed")
	for k in size:
		var net: NeuralNetwork
		if seed != null:
			# Continue from a saved network: keep it, plus mutated copies of it.
			net = seed.clone()
			if k > 0:
				net.mutate(mutation_rate if k < size * 0.5 else mutation_rate * 2.0)
		else:
			net = _random_net()
		genomes.append(Genome.new(net))
	# Without a comparable score the seed is not the best yet: the first generation decides.
	var sf: Variant = cfg.get("seed_fitness")
	if seed != null and (sf is float or sf is int) and is_finite(float(sf)):
		best_ever = Best.new(seed.clone(), float(sf))


func size() -> int:
	return genomes.size()


## A new random network (with the silent outputs silenced).
func _random_net() -> NeuralNetwork:
	var net := NeuralNetwork.new(sizes)
	for o in silent_outputs:
		net.silence_output(o)
	return net


## A deep copy (every network cloned); draws no random numbers.
func copy() -> Population:
	var p := Population.new({sizes = sizes, mutation_rate = mutation_rate, silent_outputs = silent_outputs})
	for g in genomes:
		p.genomes.append(Genome.new(g.net.clone(), g.fitness))
	if best_ever != null:
		p.best_ever = Best.new(best_ever.net.clone(), best_ever.fitness)
	return p


## Breed the next generation from the current fitness values. Returns {best, avg}.
func evolve() -> Dictionary:
	var sorted: Array[Genome] = genomes.duplicate()
	# (JS Array.sort is stable: equal fitness keeps the population order)
	_stable_sort(sorted)
	var best: Genome = sorted[0]
	var total: float = 0.0
	for g in sorted:
		total += g.fitness
	var avg: float = total / sorted.size()
	if best_ever == null or best.fitness >= best_ever.fitness:
		best_ever = Best.new(best.net.clone(), best.fitness)

	var n: int = genomes.size()
	var rate: float = mutation_rate
	var elite_count: int = maxi(1, JsMath.roundi(n * 0.05))
	var random_count: int = maxi(1, JsMath.roundi(n * 0.03)) if n >= 20 else 0
	var next: Array[Genome] = []
	for k in elite_count:
		next.append(Genome.new(sorted[k].net.clone()))
	for k in random_count:
		next.append(Genome.new(_random_net()))
	while next.size() < n:
		var a: Genome = _tournament(sorted)
		var child: NeuralNetwork
		if NeuralNetwork.rng.randf() < 0.7:
			child = NeuralNetwork.crossover(a.net, _tournament(sorted).net)
		else:
			child = a.net.clone()
		child.mutate(rate)
		next.append(Genome.new(child))
	genomes = next
	return {best = best.fitness, avg = avg}


## Every genome's weights and biases in one flat array, network after network
## (NeuralNetwork.params() layout): what FleetSim.set_networks() takes.
func all_params() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for g in genomes:
		g.net.append_params(out)
	return out


static func _stable_sort(arr: Array[Genome]) -> void:
	# insertion sort by fitness, best first (stable; populations are small)
	for i in range(1, arr.size()):
		var g: Genome = arr[i]
		var j: int = i - 1
		while j >= 0 and arr[j].fitness < g.fitness:
			arr[j + 1] = arr[j]
			j -= 1
		arr[j + 1] = g


static func _tournament(pool: Array[Genome], k: int = 3) -> Genome:
	var best: Genome = null
	for i in k:
		var g: Genome = pool[NeuralNetwork.rng.randi_range(0, pool.size() - 1)]
		if best == null or g.fitness > best.fitness:
			best = g
	return best
