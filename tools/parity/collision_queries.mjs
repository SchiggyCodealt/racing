// Random locate / raycast / collideCapsule queries on every track, answered by the
// browser game's collision.js: writes {queries, answers} for tools/parity/check_collision.gd.
//   node tools/parity/collision_queries.mjs <out.json>
import { writeFileSync } from 'node:fs';
import { stringifyHex } from './hexjson.mjs';
const web = new URL('../../web/', import.meta.url);
const { TRACKS } = await import(new URL('src/tracks/trackData.js', web));
const { buildTrack } = await import(new URL('src/tracks/trackBuilder.js', web));
const { locate, raycast, collideCapsule } = await import(new URL('src/physics/collision.js', web));
let seed = 99;
const rnd = () => ((seed = (seed * 1103515245 + 12345) >>> 0) / 4294967296);
const out = [];
for (const def of TRACKS) {
  const t = buildTrack(def);
  for (let q = 0; q < 400; q++) {
    const i = Math.floor(rnd() * t.count);
    const lat = (rnd() * 2.4 - 1.2) * t.hw[i], along = rnd() * 2 - 1;
    const x = t.px[i] + t.nx[i] * lat + t.tx[i] * along, z = t.pz[i] + t.nz[i] * lat + t.tz[i] * along;
    const hint = i + Math.floor(rnd() * 9) - 4;
    const loc = { ...locate(t, x, z, hint, {}) };
    const a = rnd() * Math.PI * 2;
    const dx = Math.sin(a), dz = Math.cos(a);
    const ray = raycast(t.grid, x, z, dx, dz, 100);
    const yaw = rnd() * Math.PI * 2, R = 1.03, core = 1.2;
    const fx = Math.sin(yaw), fz = Math.cos(yaw);
    const c = {};
    const hit = collideCapsule(t.grid, x - fx * core, z - fz * core, x + fx * core, z + fz * core, R, c);
    out.push({ track: t.id, x, z, hint, dx, dz, fx, fz, R, core, loc, ray, hit, c: hit ? { ...c } : null });
  }
}
writeFileSync(process.argv[2], stringifyHex(out));
console.log(`${out.length} queries`);
