// Exact number transfer between node and Godot for the parity tools.
// Godot's JSON parser is not correctly rounded for 17-digit numbers (about 40% of random
// doubles come back one ulp off), so every non-integer number travels as "#<16 hex digits>"
// (its IEEE-754 bits); tools/parity/hex_json.gd decodes and encodes the same format.
const view = new DataView(new ArrayBuffer(8));

export function toHex(v) {
  view.setFloat64(0, v);
  return '#' + view.getBigUint64(0).toString(16).padStart(16, '0');
}

export function fromHex(s) {
  view.setBigUint64(0, BigInt('0x' + s.slice(1)));
  return view.getFloat64(0);
}

export function stringifyHex(obj) {
  return JSON.stringify(obj, (k, v) => {
    if (typeof v === 'number' && !Number.isInteger(v)) return toHex(v);
    if (ArrayBuffer.isView(v)) return Array.from(v, (x) => (Number.isInteger(x) ? x : toHex(x)));
    return v;
  });
}

export function parseHex(text) {
  return JSON.parse(text, (k, v) => (typeof v === 'string' && /^#[0-9a-f]{16}$/.test(v) ? fromHex(v) : v));
}
