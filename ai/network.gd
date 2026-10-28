class_name NeuralNetwork
extends RefCounted
## network.gd: a port of web/src/ai/network.js.
## ------------------------------------------------------------------
## A tiny fully-connected feed-forward neural network (multi-layer
## perceptron) with tanh activations. No training by back-propagation:
## weights are evolved by the genetic algorithm in genetic.gd.
##
## Numbers: weights, biases and activations are 32-bit floats
## (PackedFloat32Array, the JS Float32Arrays); sums are 64-bit, as in the JS,
## so a network computes the same outputs as the browser game.
##
## The last activations of every layer are kept in `acts`, which is what the
## live network diagram (ui/network_view.gd) draws.
##
##   var net := NeuralNetwork.new(PackedInt32Array([18, 12, 2]))   # random weights
##   var out := net.forward(inputs)          # PackedFloat32Array of the outputs (a copy)
##   net.to_json() / NeuralNetwork.from_json(d)   # the web game's JSON format:
##       {sizes: [18, 12, 2], weights: [[o * nIn + i ...] per layer], biases: [[...] per layer]}
##
## Random numbers come from NeuralNetwork.rng (seed it for repeatable runs;
## the JS uses Math.random, which can't be seeded, so runs are only
## repeatable within the Godot port).

## Shared random number generator of the AI (networks, mutation, the genetic algorithm).
static var rng: RandomNumberGenerator = _new_rng()

var sizes: PackedInt32Array = PackedInt32Array()
## weights[l][o * in_size + i] connects layer l input i -> output o
var weights: Array[PackedFloat32Array] = []
var biases: Array[PackedFloat32Array] = []
## activations of every layer after the last forward()
var acts: Array[PackedFloat32Array] = []


static func _new_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


## p_sizes: layer sizes, e.g. [18, 12, 2]. data: optional {weights: [...], biases: [...]}
## (arrays of numbers per layer, Arrays or PackedFloat32Arrays) to copy instead of random weights.
func _init(p_sizes: PackedInt32Array = PackedInt32Array(), data: Variant = null) -> void:
	sizes = p_sizes.duplicate()
	for l in sizes.size() - 1:
		var n_in: int = sizes[l]
		var n_out: int = sizes[l + 1]
		var w := PackedFloat32Array()
		var b := PackedFloat32Array()
		w.resize(n_in * n_out)
		b.resize(n_out)
		if data != null:
			var dw: Variant = data.weights[l]
			var db: Variant = data.biases[l]
			for k in mini(w.size(), (dw as Variant).size()):
				w[k] = float(dw[k])
			for k in mini(b.size(), (db as Variant).size()):
				b[k] = float(db[k])
		else:
			var scale: float = 1.0 / sqrt(float(n_in))
			for k in w.size():
				w[k] = gaussian() * scale * 1.5
			for k in b.size():
				b[k] = gaussian() * 0.2
		weights.append(w)
		biases.append(b)
	for n in sizes:
		var a := PackedFloat32Array()
		a.resize(n)
		acts.append(a)


## Run the network on `inputs` (copied into acts[0] as 32-bit floats, like the JS
## acts[0].set(inputs)). Returns the output activations: the live acts[-1] array (packed
## arrays are shared, not copied), overwritten by the next forward(), as in the JS.
func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
	var inp: PackedFloat32Array = acts[0]
	for i in mini(inp.size(), inputs.size()):
		inp[i] = inputs[i]
	for l in weights.size():
		var w: PackedFloat32Array = weights[l]
		var b: PackedFloat32Array = biases[l]
		var out: PackedFloat32Array = acts[l + 1]
		var n_in: int = inp.size()
		for o in out.size():
			var s: float = b[o]
			var off: int = o * n_in
			for i in n_in:
				s += w[off + i] * inp[i]
			out[o] = tanh(s)
		inp = out
	return inp


## The output activations of the last forward() (shared with acts).
func outputs() -> PackedFloat32Array:
	return acts[acts.size() - 1]


func clone() -> NeuralNetwork:
	return NeuralNetwork.new(sizes, {weights = weights, biases = biases})


## Mutate in place: each weight/bias has `rate` chance of a gaussian nudge,
## and a small chance of being replaced entirely. Values stay within -5..5.
func mutate(rate: float, amount: float = 0.5) -> NeuralNetwork:
	for l in weights.size():
		weights[l] = _mutated(weights[l], rate, amount)
	for l in biases.size():
		biases[l] = _mutated(biases[l], rate, amount)
	return self


static func _mutated(src: PackedFloat32Array, rate: float, amount: float) -> PackedFloat32Array:
	var arr: PackedFloat32Array = src.duplicate()
	for k in arr.size():
		if rng.randf() < rate:
			if rng.randf() < 0.1:
				arr[k] = gaussian()
			else:
				arr[k] += gaussian() * amount
			if arr[k] > 5.0:
				arr[k] = 5.0
			elif arr[k] < -5.0:
				arr[k] = -5.0
	return arr


## Uniform crossover: each neuron (its incoming weights + bias) comes from one parent.
static func crossover(a: NeuralNetwork, b: NeuralNetwork) -> NeuralNetwork:
	var child: NeuralNetwork = a.clone()
	for l in child.weights.size():
		var n_in: int = child.sizes[l]
		var cw: PackedFloat32Array = child.weights[l] # (shared: writes go into the child)
		var cb: PackedFloat32Array = child.biases[l]
		var bw: PackedFloat32Array = b.weights[l]
		var bb: PackedFloat32Array = b.biases[l]
		for o in cb.size():
			if rng.randf() < 0.5:
				cb[o] = bb[o]
				for i in n_in:
					cw[o * n_in + i] = bw[o * n_in + i]
	return child


func same_shape(other: NeuralNetwork) -> bool:
	return other != null and other.sizes == sizes


## Number of weights and biases.
func param_count() -> int:
	return NeuralNetwork.params_for(sizes)


static func params_for(p_sizes: PackedInt32Array) -> int:
	var n: int = 0
	for l in p_sizes.size() - 1:
		n += p_sizes[l] * p_sizes[l + 1] + p_sizes[l + 1]
	return n


## All weights and biases in one flat array (per layer: weights, then biases), the
## JS netParams() layout, appended to `out`.
func append_params(out: PackedFloat32Array) -> void:
	for l in weights.size():
		out.append_array(weights[l])
		out.append_array(biases[l])


func params() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	append_params(out)
	return out


## The network stored by params() at `offset` (JS netFromParams).
static func from_params(p_sizes: PackedInt32Array, p: PackedFloat32Array, offset: int = 0) -> NeuralNetwork:
	var w: Array = []
	var b: Array = []
	var o: int = offset
	for l in p_sizes.size() - 1:
		var nw: int = p_sizes[l] * p_sizes[l + 1]
		var nb: int = p_sizes[l + 1]
		w.append(p.slice(o, o + nw))
		b.append(p.slice(o + nw, o + nw + nb))
		o += nw + nb
	return NeuralNetwork.new(p_sizes, {weights = w, biases = b})


## The web game's JSON form: {sizes, weights, biases}, each value the shortest decimal
## that reads back as the same 32-bit float (JS Number(v.toPrecision(9))).
func to_json() -> Dictionary:
	var w: Array = []
	var b: Array = []
	for l in weights.size():
		w.append(_rounded(weights[l]))
		b.append(_rounded(biases[l]))
	return {sizes = Array(sizes), weights = w, biases = b}


static func _rounded(a: PackedFloat32Array) -> Array:
	var out: Array = []
	out.resize(a.size())
	for k in a.size():
		out[k] = round9(a[k])
	return out


## JS Number(v.toPrecision(9)): v rounded to 9 significant digits.
static func round9(v: float) -> float:
	if v == 0.0 or not is_finite(v):
		return v
	var av: float = absf(v)
	var e: int = int(floor(log(av) / log(10.0)))
	# (the log quotient can be one off next to a power of ten)
	if av >= pow(10.0, e + 1):
		e += 1
	elif av < pow(10.0, e):
		e -= 1
	var decimals: int = 8 - e
	if decimals < 0 or decimals > 32:
		return v # (outside what a network holds; String.num can't round there)
	var r: float = String.num(v, decimals).to_float() # printf "%.*f": correctly rounded
	return r if r != 0.0 else v


## Network from the web game's JSON form (or a Dictionary holding one). Fails with an
## empty result (null) when it is not a network.
static func from_json(obj: Variant) -> NeuralNetwork:
	if not (obj is Dictionary):
		return null
	var d: Dictionary = obj
	if not (d.get("sizes") is Array) or not (d.get("weights") is Array) or not (d.get("biases") is Array):
		return null
	var s := PackedInt32Array()
	for v: Variant in d.sizes:
		if not (v is float or v is int) or int(v) < 1 or int(v) > 4096:
			return null
		s.append(int(v))
	if s.size() < 2 or (d.weights as Array).size() != s.size() - 1 or (d.biases as Array).size() != s.size() - 1:
		return null
	for l in s.size() - 1:
		var w: Variant = d.weights[l]
		var b: Variant = d.biases[l]
		if not (w is Array or w is PackedFloat32Array or w is PackedFloat64Array) or not (b is Array or b is PackedFloat32Array or b is PackedFloat64Array):
			return null
		if (w as Variant).size() != s[l] * s[l + 1] or (b as Variant).size() != s[l + 1]:
			return null
		for x: Variant in w:
			if not (x is float or x is int):
				return null
		for x: Variant in b:
			if not (x is float or x is int):
				return null
	return NeuralNetwork.new(s, d)


## Standard normal random number (Box-Muller), from NeuralNetwork.rng.
static func gaussian() -> float:
	var u: float = 0.0
	var v: float = 0.0
	while u == 0.0:
		u = rng.randf()
	while v == 0.0:
		v = rng.randf()
	return sqrt(-2.0 * log(u)) * cos(2.0 * PI * v)
