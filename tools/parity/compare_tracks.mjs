// Compares the Godot port's built tracks (tools/parity/dump_tracks.gd output)
// with the browser game's (web/src/tracks/trackBuilder.js), number for number.
//   node tools/parity/compare_tracks.mjs <gd_built.json>   (run from the repo root or anywhere)
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const web = new URL('../../web/', import.meta.url);
const { TRACKS } = await import(new URL('src/tracks/trackData.js', web));
const { buildTrack, getGates, raceLength } = await import(new URL('src/tracks/trackBuilder.js', web));
const gd = JSON.parse(readFileSync(process.argv[2], 'utf8'));
let bad = 0, numbers = 0, maxErr = 0;
const cmp = (a, b, path) => {
  if (ArrayBuffer.isView(a)) a = Array.from(a);
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) { if (bad++ < 10) console.log('length', path, a.length, b?.length); return; }
    a.forEach((x, i) => cmp(x, b[i], `${path}[${i}]`)); return;
  }
  if (a && typeof a === 'object') { for (const k of Object.keys(a)) cmp(a[k], b?.[k], `${path}.${k}`); return; }
  if (typeof a === 'number') {
    numbers++;
    if (a !== b) { maxErr = Math.max(maxErr, Math.abs(a - b)); if (bad++ < 10) console.log('value', path, a, b); }
    return;
  }
  if (a !== b) { if (bad++ < 10) console.log('value', path, a, b); }
};
TRACKS.forEach((def, i) => {
  const t = buildTrack(def), g = t.grid;
  const js = {
    id: t.id, name: t.name, theme: t.theme, closed: t.closed, laps: t.laps, N: t.N, count: t.count, segLen: t.segLen, length: t.length,
    segCount: t.segCount, startIdx: t.startIdx, finishIdx: t.finishIdx, startLine: t.startLine, cpSamples: t.cpSamples, kickers: t.kickers,
    px: t.px, py: t.py, pz: t.pz, tx: t.tx, tz: t.tz, nx: t.nx, nz: t.nz, hw: t.hw, bank: t.bank,
    gates: getGates(t, t.laps), raceLength: raceLength(t, t.laps),
    grid: { cell: g.cell, minX: g.minX, minZ: g.minZ, cols: g.cols, rows: g.rows, segs: g.segs, inward: g.inward, segD: g.segD, cellStart: g.cellStart, cellSegs: g.cellSegs },
  };
  cmp(js, gd[i], t.id);
});
console.log(`${TRACKS.length} tracks, ${numbers} numbers compared: ${bad} differ${bad ? ` (largest ${maxErr})` : ' (all identical)'}`);
process.exit(bad ? 1 : 0);
