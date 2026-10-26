// Dumps the web game's medal times (web/src/tracks/medals.js MEDALS) as JSON, for
// `tools/medals.gd -- --js=<file>`:   node tools/parity/dump_medals.mjs <out.json>
import { writeFileSync } from 'node:fs';
const { MEDALS } = await import(new URL('../../web/src/tracks/medals.js', import.meta.url));
writeFileSync(process.argv[2], JSON.stringify(MEDALS));
console.log(`${Object.keys(MEDALS).length} tracks`);
