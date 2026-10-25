/**
 * networkView.js
 * ------------------------------------------------------------------
 * Live diagram of a neural network on a <canvas>:
 *   - nodes in columns, one per layer, labelled on the input/output side
 *   - connections blue (positive) / red (negative), thicker = stronger,
 *     brighter when the signal flowing through them is strong
 *   - nodes glow warm (positive) or cool (negative) with their activation
 * v5: labels in the menu's type and greys.
 */

const FONT = 'Barlow, system-ui, sans-serif';
import { INPUT_LABELS, OUTPUT_LABELS } from '../ai/sensors.js';

export class NetworkView {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
  }

  _fit() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    if (this.canvas.width !== Math.round(w * dpr) || this.canvas.height !== Math.round(h * dpr)) {
      this.canvas.width = Math.round(w * dpr);
      this.canvas.height = Math.round(h * dpr);
    }
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return [w, h];
  }

  draw(net) {
    const ctx = this.ctx;
    const [W, H] = this._fit();
    ctx.clearRect(0, 0, W, H);
    if (!net || W < 10) return;

    const sizes = net.sizes;
    const top = 14, bottom = 14;
    // input labels: smaller type when the rows are close (a short panel), and only
    // every other label when even that would overprint
    const rowIn = Math.min(26, (H - top - bottom) / Math.max(1, sizes[0]));
    const inFont = `${Math.max(8, Math.min(12, Math.round(rowIn)))}px ${FONT}`;
    const everyOther = rowIn < 7;
    ctx.font = inFont;
    let labelW = 0;
    for (const l of INPUT_LABELS) labelW = Math.max(labelW, ctx.measureText(`${l} -0.00`).width);
    const left = labelW + 18, right = 80;
    const L = sizes.length;
    const xs = sizes.map((_, l) => left + ((W - left - right) * l) / (L - 1));
    const ys = sizes.map((n) => {
      const gap = Math.min(26, (H - top - bottom) / Math.max(1, n));
      const total = gap * (n - 1);
      return Array.from({ length: n }, (_, i) => H / 2 - total / 2 + i * gap);
    });
    const maxN = Math.max(...sizes);
    const r = Math.max(3, Math.min(8, ((H - top - bottom) / maxN) * 0.36));

    // connections
    for (let l = 0; l < L - 1; l++) {
      const w = net.weights[l], nIn = sizes[l], src = net.acts[l];
      for (let o = 0; o < sizes[l + 1]; o++) {
        for (let i = 0; i < nIn; i++) {
          const wt = w[o * nIn + i];
          const mag = Math.min(1, Math.abs(wt) / 2);
          const flow = 0.25 + 0.75 * Math.min(1, Math.abs(src[i] * wt));
          ctx.strokeStyle = wt >= 0 ? `rgba(70,160,255,${0.08 + 0.6 * mag * flow})` : `rgba(255,85,85,${0.08 + 0.6 * mag * flow})`;
          ctx.lineWidth = 0.3 + 2.6 * mag;
          ctx.beginPath();
          ctx.moveTo(xs[l], ys[l][i]);
          ctx.lineTo(xs[l + 1], ys[l + 1][o]);
          ctx.stroke();
        }
      }
    }

    // nodes
    ctx.font = `12px ${FONT}`;
    ctx.textBaseline = 'middle';
    for (let l = 0; l < L; l++) {
      for (let i = 0; i < sizes[l]; i++) {
        const a = net.acts[l][i];
        const x = xs[l], y = ys[l][i];
        ctx.fillStyle = activationColor(a);
        ctx.strokeStyle = 'rgba(255,255,255,0.75)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        if (l === 0) {
          if (everyOther && i % 2) continue;
          ctx.font = inFont;
          ctx.fillStyle = '#a7a9ae';
          ctx.textAlign = 'right';
          ctx.fillText(`${INPUT_LABELS[i] ?? 'in ' + i} ${a.toFixed(2)}`, x - r - 4, y);
          ctx.font = `12px ${FONT}`;
        } else if (l === L - 1) {
          ctx.textAlign = 'left';
          ctx.fillStyle = '#f2f2ef';
          const name = OUTPUT_LABELS[i] ?? 'out ' + i;
          const hint = i === 0 ? (a > 0.05 ? ' left' : a < -0.05 ? ' right' : '') : a < 0 ? ' brake' : ' gas';
          ctx.fillText(name, x + r + 5, y - 7);
          ctx.fillStyle = '#a7a9ae';
          ctx.fillText(`${a.toFixed(2)}${hint}`, x + r + 5, y + 7);
        }
      }
    }
  }
}

function activationColor(a) {
  const t = Math.min(1, Math.abs(a));
  const base = [37, 39, 44];
  const hot = a >= 0 ? [255, 196, 61] : [92, 170, 255];
  const c = base.map((b, k) => Math.round(b + (hot[k] - b) * t));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}
