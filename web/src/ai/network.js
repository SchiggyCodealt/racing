/**
 * network.js
 * ------------------------------------------------------------------
 * A tiny fully-connected feed-forward neural network (multi-layer
 * perceptron) with tanh activations. No training by back-propagation:
 * weights are evolved by the genetic algorithm in genetic.js.
 *
 * The last activations of every layer are kept in `this.acts`, which is
 * what the live network diagram draws.
 */
export class NeuralNetwork {
  /**
   * @param {number[]} sizes  layer sizes, e.g. [11, 12, 2]
   * @param {object} [data]   optional {weights: number[][], biases: number[][]}
   */
  constructor(sizes, data = null) {
    this.sizes = sizes.slice();
    this.weights = []; // weights[l][o * inSize + i] connects layer l input i -> output o
    this.biases = [];
    for (let l = 0; l < sizes.length - 1; l++) {
      const nIn = sizes[l], nOut = sizes[l + 1];
      const w = new Float32Array(nIn * nOut);
      const b = new Float32Array(nOut);
      if (data) {
        w.set(data.weights[l]);
        b.set(data.biases[l]);
      } else {
        const scale = 1 / Math.sqrt(nIn);
        for (let k = 0; k < w.length; k++) w[k] = gaussian() * scale * 1.5;
        for (let k = 0; k < b.length; k++) b[k] = gaussian() * 0.2;
      }
      this.weights.push(w);
      this.biases.push(b);
    }
    this.acts = sizes.map((n) => new Float32Array(n));
  }

  /** Run the network. Returns the output activations (a live array, don't keep it). */
  forward(inputs) {
    const acts = this.acts;
    acts[0].set(inputs);
    for (let l = 0; l < this.weights.length; l++) {
      const inp = acts[l], out = acts[l + 1];
      const w = this.weights[l], b = this.biases[l];
      const nIn = inp.length;
      for (let o = 0; o < out.length; o++) {
        let s = b[o];
        const off = o * nIn;
        for (let i = 0; i < nIn; i++) s += w[off + i] * inp[i];
        out[o] = Math.tanh(s);
      }
    }
    return acts[acts.length - 1];
  }

  clone() {
    return new NeuralNetwork(this.sizes, { weights: this.weights, biases: this.biases });
  }

  /**
   * Mutate in place: each weight/bias has `rate` chance of a gaussian nudge,
   * and a small chance of being replaced entirely.
   */
  mutate(rate, amount = 0.5) {
    const m = (arr) => {
      for (let k = 0; k < arr.length; k++) {
        if (Math.random() < rate) {
          if (Math.random() < 0.1) arr[k] = gaussian();
          else arr[k] += gaussian() * amount;
          if (arr[k] > 5) arr[k] = 5;
          else if (arr[k] < -5) arr[k] = -5;
        }
      }
    };
    this.weights.forEach(m);
    this.biases.forEach(m);
    return this;
  }

  /** Uniform crossover: each neuron (its incoming weights + bias) comes from one parent. */
  static crossover(a, b) {
    const child = a.clone();
    for (let l = 0; l < child.weights.length; l++) {
      const nIn = child.sizes[l];
      for (let o = 0; o < child.biases[l].length; o++) {
        if (Math.random() < 0.5) {
          child.biases[l][o] = b.biases[l][o];
          for (let i = 0; i < nIn; i++) child.weights[l][o * nIn + i] = b.weights[l][o * nIn + i];
        }
      }
    }
    return child;
  }

  sameShape(other) {
    return other && other.sizes.length === this.sizes.length && other.sizes.every((s, i) => s === this.sizes[i]);
  }

  toJSON() {
    return {
      sizes: this.sizes,
      weights: this.weights.map((w) => Array.from(w, round)),
      biases: this.biases.map((b) => Array.from(b, round)),
    };
  }

  static fromJSON(obj) {
    if (!obj || !Array.isArray(obj.sizes) || !Array.isArray(obj.weights)) throw new Error('Not a network file');
    return new NeuralNetwork(obj.sizes, obj);
  }
}

/** Shortest decimal that reads back as the same 32-bit float, so a saved network drives exactly like the original. */
function round(v) {
  return Number(v.toPrecision(9));
}

/** Standard normal random number (Box-Muller). */
export function gaussian() {
  let u = 0, v = 0;
  while (u === 0) u = Math.random();
  while (v === 0) v = Math.random();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}
