/**
 * main.js — entry point.
 * ------------------------------------------------------------------
 * Builds the tracks, creates the 3D world and runs the main loop.
 * The app is a small state machine of "modes":
 *   menu       track select, the camera orbits the selected track
 *   PlayMode   drive / race the AI ghost / watch the AI   (game/playMode.js)
 *   TrainMode  neuroevolution training dashboard           (game/trainMode.js)
 */
import { TRACKS } from './tracks/trackData.js';
import { buildTrack } from './tracks/trackBuilder.js';
import { World } from './game/scene.js';
import { buildTrackMesh } from './game/trackMesh.js';
import { Keyboard } from './game/input.js';
import { PlayMode } from './game/playMode.js';
import { TrainMode } from './game/trainMode.js';
import { loadSavedNetwork, saveNetwork, downloadJSON, pickJSONFile } from './game/storage.js';
import { parseNetworkFile, networkFile } from './ai/trainer.js';
import { HUD } from './ui/hud.js';
import { Menu } from './ui/menu.js';

const app = {
  world: new World(document.getElementById('view')),
  input: new Keyboard(),
  hud: new HUD(),
  tracks: TRACKS.map(buildTrack),
  selectedTrack: 0,
  network: null, // {net: NeuralNetwork, meta: saved file contents}
  mode: null,
  currentTrack: null,
  trackMeshes: null,
  orbitAngle: 0,

  setMode(mode) {
    // drop focus from the button that was clicked, so Space/Enter in a race don't press it
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    if (this.mode && this.mode.exit) this.mode.exit();
    this.mode = mode;
    menu.show(mode === menuMode);
    if (mode.enter) mode.enter();
    this.input.clearPressed();
  },

  showMenu() {
    this.setMode(menuMode);
  },

  /** Swap the 3D track (cached while it stays the same). Returns its mesh handle. */
  showTrack(track) {
    if (this.currentTrack === track) return this.trackMeshes;
    if (this.trackMeshes) {
      this.world.scene.remove(this.trackMeshes.group);
      this.trackMeshes.dispose();
    }
    // Sky, light and fog follow the track's theme; the track mesh themes itself.
    this.world.setTheme(track.def?.theme ?? 'meadow');
    this.trackMeshes = buildTrackMesh(track);
    this.world.applyDetail(this.trackMeshes.group); // scenery density for the graphics quality
    this.world.scene.add(this.trackMeshes.group);
    // The chase camera uses this to stay above the road and inside the walls.
    this.world.camera.userData.track = track;
    this.currentTrack = track;
    return this.trackMeshes;
  },

  /** Slow orbit around the current track (menu background). */
  orbit(dt) {
    const t = this.currentTrack;
    if (!t) return;
    this.orbitAngle += dt * 0.08;
    let cx = 0, cy = 0, cz = 0, r = 0;
    for (let i = 0; i < t.count; i += 8) { cx += t.px[i]; cy += t.py[i]; cz += t.pz[i]; }
    const n = Math.ceil(t.count / 8);
    cx /= n; cy /= n; cz /= n;
    for (let i = 0; i < t.count; i += 8) r = Math.max(r, Math.hypot(t.px[i] - cx, t.pz[i] - cz));
    const cam = this.world.camera;
    const d = r * 1.25 + 60;
    cam.position.set(cx + Math.cos(this.orbitAngle) * d, d * 0.55, cz + Math.sin(this.orbitAngle) * d);
    cam.lookAt(cx, 0, cz);
    if (cam.fov !== 60) { cam.fov = 60; cam.updateProjectionMatrix(); }
    this.world.focusShadows(cx, cy, cz);
  },
};

// Load the AI network remembered from the last session, if any.
try {
  const saved = loadSavedNetwork();
  if (saved) app.network = parseNetworkFile(saved);
} catch (e) {
  console.warn('Saved network could not be read:', e);
}

const trainMode = new TrainMode(app);

const menuMode = {
  enter() {
    // the background shows the highlighted track (training or Watch best may have left another one)
    app.showTrack(app.tracks[app.selectedTrack]);
  },
  update(dt) {
    menu.handleKeys(app.input);
    app.orbit(dt);
    app.world.render();
  },
};

const play = (driver, ghost) => {
  if (driver === 'ai' || ghost) {
    if (!app.network) return;
  }
  app.setMode(new PlayMode(app, {
    track: app.tracks[app.selectedTrack],
    driver,
    ghost,
    net: app.network?.net.clone(),
  }));
};

const menu = new Menu(app, {
  drive: () => play('human', false),
  ghost: () => play('human', true),
  watch: () => play('ai', false),
  train: () => app.setMode(trainMode),
  loadNet: async () => {
    try {
      const data = await pickJSONFile();
      app.network = parseNetworkFile(data);
      saveNetwork(data.network ? data : networkFile(app.network.net));
      menu.render();
    } catch (err) {
      alert(`Could not load network: ${err.message}`);
    }
  },
  saveNet: () => {
    if (!app.network) return;
    const data = app.network.meta?.network ? app.network.meta : networkFile(app.network.net);
    downloadJSON(data, `ai-driver-gen${data.generation ?? 0}.json`);
  },
});

app.showTrack(app.tracks[0]);
app.showMenu();

// ---- main loop ----------------------------------------------------------------
let last = performance.now();
function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  app.mode.update(dt);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// Handy for debugging from the browser console.
window.app = app;
