/**
 * fitnessChart.js
 * ------------------------------------------------------------------
 * Line chart of best and average fitness per generation (canvas).
 * v5: the menu's type and colours (best in the accent, average in grey).
 */

const FONT = '12px Barlow, system-ui, sans-serif';
const C = { label: '#6f7278', grid: 'rgba(255,255,255,0.07)', best: '#ffc83d', avg: '#a7a9ae' };
export class FitnessChart {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
  }

  draw(history) {
    const ctx = this.ctx;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const W = this.canvas.clientWidth, H = this.canvas.clientHeight;
    if (this.canvas.width !== Math.round(W * dpr)) {
      this.canvas.width = Math.round(W * dpr);
      this.canvas.height = Math.round(H * dpr);
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);

    const padL = 40, padR = 10, padT = 18, padB = 20;
    const pw = W - padL - padR, ph = H - padT - padB;
    ctx.font = FONT;

    if (!history.length) {
      ctx.fillStyle = C.label;
      ctx.textAlign = 'center';
      ctx.fillText('Fitness per generation appears here', W / 2, H / 2);
      return;
    }

    const maxY = niceMax(Math.max(...history.map((h) => h.best)));
    const g0 = history[0].gen, g1 = Math.max(history[history.length - 1].gen, g0 + 1);
    const X = (g) => padL + ((g - g0) / (g1 - g0)) * pw;
    const Y = (v) => padT + ph - (Math.max(0, v) / maxY) * ph;

    // grid + y labels
    ctx.strokeStyle = C.grid;
    ctx.fillStyle = C.label;
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    for (let k = 0; k <= 4; k++) {
      const v = (maxY * k) / 4;
      ctx.beginPath();
      ctx.moveTo(padL, Y(v));
      ctx.lineTo(W - padR, Y(v));
      ctx.stroke();
      ctx.fillText(Math.round(v), padL - 4, Y(v));
    }
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.fillText(`gen ${g0}`, padL + 14, H - padB + 5);
    ctx.fillText(`gen ${g1}`, W - padR - 18, H - padB + 5);

    const line = (key, color, width) => {
      ctx.strokeStyle = color;
      ctx.lineWidth = width;
      ctx.beginPath();
      history.forEach((h, i) => (i ? ctx.lineTo(X(h.gen), Y(h[key])) : ctx.moveTo(X(h.gen), Y(h[key]))));
      ctx.stroke();
    };
    line('avg', C.avg, 1.5);
    line('best', C.best, 2);

    // legend
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = C.best;
    ctx.fillRect(padL, 6, 10, 3);
    ctx.fillText('best', padL + 14, 8);
    ctx.fillStyle = C.avg;
    ctx.fillRect(padL + 50, 6, 10, 3);
    ctx.fillText('average', padL + 64, 8);
  }
}

function niceMax(v) {
  if (v <= 0) return 1;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 2, 2.5, 5, 10]) if (m * p >= v) return m * p;
  return 10 * p;
}
