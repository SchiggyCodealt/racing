/**
 * storage.js
 * ------------------------------------------------------------------
 * Everything saved in the browser (localStorage): best times + splits and
 * the ghost of the best run per track and car (v4; before v4 there was one
 * car and one of each per track), the best score per track and car (v4),
 * a few settings (ghost on / off, the chosen car) and the latest trained AI
 * network. Also file download / upload helpers for network JSON files.
 * Bad or foreign data in localStorage is ignored, never thrown.
 */
import { PHYSICS_VERSION } from '../physics/car.js';
import { CAR_IDS, DEFAULT_CAR } from '../physics/cars.js';
import { SCORE_RULES } from './score.js';

// v2: new track layouts (the same ids now name different tracks) and a new
// network input layout, so v1 records and networks are deliberately not read.
// v3: physics v3 (walls cost far more speed), so v2 best times are not
// comparable and are not read either; records are also tagged with
// PHYSICS_VERSION from now on, so a later physics change only needs a bump
// there. Networks keep the v2 key (their inputs didn't change).
// v4: best times per track and car, {trackId: {carId: {time, splits, date, physics}}}. Until the first v4
// record is saved, the v3 records ({trackId: {time, splits, date, physics}}, all set with the racer, the
// only car before v4) are read as the racer's; that first save copies them in. The v3 key is left as it is.
const RECORDS_KEY = 'trackrush.records.v4';
const RECORDS_V3_KEY = 'trackrush.records.v3';
const NETWORK_KEY = 'trackrush.network.v2';
// + track id + '.' + car id (v4); the ghost carries its own format / physics / car tags (replay.js).
// A v3 ghost sits at GHOST_KEY + track id (the racer's, no car tag): it is read as the racer's ghost
// until a new racer ghost for that track replaces it.
const GHOST_KEY = 'trackrush.ghost.';
const SETTINGS_KEY = 'trackrush.settings';
// v4: best scores (score.js), {trackId: {carId: {score, date, rules, physics}}}; an entry made under other
// scoring rules (SCORE_RULES) or physics is not read
const SCORES_KEY = 'trackrush.scores.v1';
// defaults; a stored value of another type is ignored. car (v4): the car picked on the menu, a car id
// from src/physics/cars.js (getCar() turns an unknown one into the racer)
const SETTINGS = { ghost: true, car: DEFAULT_CAR };

function read(key, fallback) {
  try {
    const v = localStorage.getItem(key);
    return v ? JSON.parse(v) : fallback;
  } catch {
    return fallback;
  }
}

function write(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}

function remove(key) {
  try {
    localStorage.removeItem(key);
  } catch { /* nothing to do */ }
}

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/** Every track's best times by car: the v4 records, or (none saved yet, or unreadable) the v3 ones as the racer's. */
function allRecords() {
  const all = read(RECORDS_KEY, null);
  if (isObject(all)) return all;
  const v3 = read(RECORDS_V3_KEY, null), out = {};
  if (isObject(v3)) for (const [id, r] of Object.entries(v3)) if (isObject(r)) out[id] = { [DEFAULT_CAR]: r };
  return out;
}

/** The entry of track `trackId` and car `carId` in `all`, or undefined (own keys only). */
function entryOf(all, trackId, carId) {
  const t = Object.hasOwn(all, trackId) ? all[trackId] : null;
  return isObject(t) && Object.hasOwn(t, carId) ? t[carId] : undefined;
}

/**
 * {time, splits[], date} on a track with a car (default: the racer), or null
 * (also for a record set under other physics). A split that isn't a number reads as null.
 */
export function getRecord(trackId, carId = DEFAULT_CAR) {
  const r = entryOf(allRecords(), trackId, carId);
  if (!isObject(r) || r.physics !== PHYSICS_VERSION || !(r.time > 0) || !Number.isFinite(r.time)) return null;
  const splits = Array.isArray(r.splits) ? r.splits.map((s) => (Number.isFinite(s) ? s : null)) : [];
  return { time: r.time, splits, date: r.date };
}

/** Save a time on a track with a car (one of cars.js) if it beats the best. Returns true when it is a new record. */
export function submitRecord(trackId, carId, time, splits) {
  if (!CAR_IDS.includes(carId) || !(time > 0) || !Number.isFinite(time)) return false;
  const prev = getRecord(trackId, carId);
  if (prev && prev.time <= time) return false;
  const all = allRecords();
  const t = Object.hasOwn(all, trackId) && isObject(all[trackId]) ? all[trackId] : (all[trackId] = {});
  t[carId] = { time, splits, physics: PHYSICS_VERSION, date: new Date().toISOString() };
  write(RECORDS_KEY, all);
  return true;
}

const ghostKey = (trackId, carId) => `${GHOST_KEY}${trackId}.${carId}`;

/**
 * The saved ghost of the best run on a track with a car (default: the racer;
 * for the racer a v3 ghost too), unchecked (replay.js unpackGhost checks and
 * decodes it, the car tag included), or null.
 */
export function loadGhost(trackId, carId = DEFAULT_CAR) {
  const g = read(ghostKey(trackId, carId), null);
  return g == null && carId === DEFAULT_CAR ? read(GHOST_KEY + trackId, null) : g;
}

/**
 * Save the ghost of a track and car (packGhost output; a racer ghost also
 * replaces the track's v3 ghost). When the browser refuses (storage full),
 * the old ghost it replaces is removed first and the save tried once more.
 * Returns false when that fails too (storage full or off): no ghost is then
 * left for that track and car, so a ghost never stands for a best time it
 * didn't drive.
 */
export function saveGhost(trackId, carId, data) {
  const key = ghostKey(trackId, carId), legacy = carId === DEFAULT_CAR ? GHOST_KEY + trackId : null;
  if (!write(key, data)) {
    remove(key); // make room: the ghosts this one replaces go first
    if (legacy) remove(legacy);
    if (!write(key, data)) return false;
  }
  if (legacy) remove(legacy);
  return true;
}

/** A remembered setting (see SETTINGS for the names and defaults). */
export function getSetting(name) {
  const s = read(SETTINGS_KEY, null);
  const v = isObject(s) ? s[name] : undefined;
  return typeof v === typeof SETTINGS[name] ? v : SETTINGS[name];
}

export function setSetting(name, value) {
  const s = read(SETTINGS_KEY, null);
  const all = isObject(s) ? s : {};
  all[name] = value;
  write(SETTINGS_KEY, all);
}

function allScores() {
  const all = read(SCORES_KEY, null);
  return isObject(all) ? all : {};
}

/** The best score (score.js) on a track with a car: {score, date}, or null (also for one made under other rules or physics). */
export function getBestScore(trackId, carId) {
  const t = allScores()[trackId];
  const e = isObject(t) ? t[carId] : null;
  if (!isObject(e) || e.rules !== SCORE_RULES || e.physics !== PHYSICS_VERSION || !Number.isFinite(e.score) || !(e.score > 0)) return null;
  return { score: e.score, date: e.date };
}

/** Save a race's score on a track with a car if it beats the best. Returns true when it is a new best (scores of 0 never are). */
export function submitScore(trackId, carId, score) {
  if (!Number.isFinite(score) || !(score > 0)) return false;
  const prev = getBestScore(trackId, carId);
  if (prev && prev.score >= score) return false;
  const all = allScores();
  const t = isObject(all[trackId]) ? all[trackId] : (all[trackId] = {});
  t[carId] = { score, date: new Date().toISOString(), rules: SCORE_RULES, physics: PHYSICS_VERSION };
  write(SCORES_KEY, all);
  return true;
}

export function loadSavedNetwork() {
  return read(NETWORK_KEY, null);
}

export function saveNetwork(data) {
  return write(NETWORK_KEY, data);
}

export function downloadJSON(data, filename) {
  const blob = new Blob([JSON.stringify(data, null, 1)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Opens a file picker and resolves with the parsed JSON of the chosen file. */
export function pickJSONFile() {
  return new Promise((resolve, reject) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json,application/json';
    input.onchange = () => {
      const file = input.files?.[0];
      if (!file) return reject(new Error('No file chosen'));
      file.text().then((t) => resolve(JSON.parse(t))).catch(reject);
    };
    input.click();
  });
}
