/**
 * genetic.js
 * ------------------------------------------------------------------
 * Neuroevolution: a population of networks is scored by driving, then the
 * next generation is bred from the best ones.
 *
 *   - Elitism: the top few networks survive unchanged (we never lose the best).
 *   - Tournament selection picks parents (fitter cars win more often).
 *   - Crossover mixes two parents neuron by neuron.
 *   - Mutation nudges random weights, controlled by `mutationRate`.
 *   - A couple of brand-new random networks keep diversity up.
 */
import { NeuralNetwork } from './network.js';

export class Population {
  /**
   * @param {object} cfg {size, sizes: layer sizes, mutationRate, seed?: NeuralNetwork,
   *                     seedFitness?: the seed's score, when it is comparable with this run's scores}
   */
  constructor(cfg) {
    this.cfg = { ...cfg };
    this.bestEver = null;       // {net, fitness}
    this.genomes = [];
    const { size, sizes, seed } = cfg;
    for (let k = 0; k < size; k++) {
      let net;
      if (seed) {
        // Continue from a saved network: keep it, plus mutated copies of it.
        net = seed.clone();
        if (k > 0) net.mutate(k < size * 0.5 ? cfg.mutationRate : cfg.mutationRate * 2);
      } else {
        net = new NeuralNetwork(sizes);
      }
      this.genomes.push({ net, fitness: 0 });
    }
    // Without a comparable score the seed is not the best yet: the first generation decides.
    if (seed && Number.isFinite(cfg.seedFitness)) this.bestEver = { net: seed.clone(), fitness: cfg.seedFitness };
  }

  get size() {
    return this.genomes.length;
  }

  /** Breed the next generation from the current fitness values. Returns stats. */
  evolve() {
    const sorted = this.genomes.slice().sort((a, b) => b.fitness - a.fitness);
    const best = sorted[0];
    const avg = sorted.reduce((s, g) => s + g.fitness, 0) / sorted.length;
    if (!this.bestEver || best.fitness >= this.bestEver.fitness) {
      this.bestEver = { net: best.net.clone(), fitness: best.fitness };
    }

    const n = this.genomes.length;
    const rate = this.cfg.mutationRate;
    const eliteCount = Math.max(1, Math.round(n * 0.05));
    const randomCount = n >= 20 ? Math.max(1, Math.round(n * 0.03)) : 0;
    const next = [];
    for (let k = 0; k < eliteCount; k++) next.push({ net: sorted[k].net.clone(), fitness: 0 });
    for (let k = 0; k < randomCount; k++) next.push({ net: new NeuralNetwork(this.cfg.sizes), fitness: 0 });
    while (next.length < n) {
      const a = tournament(sorted);
      let child;
      if (Math.random() < 0.7) child = NeuralNetwork.crossover(a.net, tournament(sorted).net);
      else child = a.net.clone();
      child.mutate(rate);
      next.push({ net: child, fitness: 0 });
    }
    this.genomes = next;
    return { best: best.fitness, avg };
  }

  /**
   * The population as plain data (for Trainer.exportState): every genome's weights and
   * biases in one Float32Array, network after network (see netParams), their fitness,
   * and the best network so far.
   */
  exportState() {
    const per = paramCount(this.cfg.sizes);
    const params = new Float32Array(per * this.genomes.length);
    this.genomes.forEach((g, k) => netParams(g.net, params, k * per));
    return {
      sizes: this.cfg.sizes.slice(),
      mutationRate: this.cfg.mutationRate,
      params,
      fitness: Float64Array.from(this.genomes, (g) => g.fitness),
      bestEver: this.bestEver && { params: netParams(this.bestEver.net), fitness: this.bestEver.fitness },
    };
  }

  /** A population saved by exportState(), exactly (it draws no random numbers). */
  static fromState(s) {
    const pop = new Population({ size: 0, sizes: s.sizes, mutationRate: s.mutationRate });
    const per = paramCount(s.sizes);
    for (let k = 0; k < s.fitness.length; k++) {
      pop.genomes.push({ net: netFromParams(s.sizes, s.params, k * per), fitness: s.fitness[k] });
    }
    pop.cfg.size = pop.genomes.length;
    if (s.bestEver) pop.bestEver = { net: netFromParams(s.sizes, s.bestEver.params), fitness: s.bestEver.fitness };
    return pop;
  }
}

/** Number of weights and biases in a network with these layer sizes. */
export function paramCount(sizes) {
  let n = 0;
  for (let l = 0; l < sizes.length - 1; l++) n += sizes[l] * sizes[l + 1] + sizes[l + 1];
  return n;
}

/**
 * A network's weights and biases as one flat array (per layer: weights, then biases),
 * written into `out` at `offset`. Compact to send to or from a Web Worker.
 */
export function netParams(net, out = new Float32Array(paramCount(net.sizes)), offset = 0) {
  let o = offset;
  for (let l = 0; l < net.weights.length; l++) {
    out.set(net.weights[l], o);
    o += net.weights[l].length;
    out.set(net.biases[l], o);
    o += net.biases[l].length;
  }
  return out;
}

/** The network stored by netParams() (exactly the same: both are 32-bit floats). */
export function netFromParams(sizes, params, offset = 0) {
  const weights = [], biases = [];
  let o = offset;
  for (let l = 0; l < sizes.length - 1; l++) {
    const nw = sizes[l] * sizes[l + 1], nb = sizes[l + 1];
    weights.push(params.subarray(o, o + nw));
    biases.push(params.subarray(o + nw, o + nw + nb));
    o += nw + nb;
  }
  return new NeuralNetwork(sizes, { weights, biases });
}

function tournament(pool, k = 3) {
  let best = null;
  for (let i = 0; i < k; i++) {
    const g = pool[(Math.random() * pool.length) | 0];
    if (!best || g.fitness > best.fitness) best = g;
  }
  return best;
}
