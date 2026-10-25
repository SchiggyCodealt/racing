/**
 * scene.js
 * ------------------------------------------------------------------
 * Renderer, sky, light, fog, environment map and post-processing:
 * everything that is not the track or a car.
 *
 *   - PBR rendering with ACES filmic tone mapping.
 *   - A procedural sky (gradient, sun, drifting clouds) that is also baked
 *     into a PMREM environment map, so paint, glass and metal reflect it.
 *   - One shadow-casting sun whose shadow box follows the camera focus,
 *     snapped to shadow-map texels so shadows do not shimmer.
 *   - Optional subtle bloom on emissive lights (UnrealBloomPass at quarter
 *     resolution). A small governor steps the quality down (high -> medium
 *     -> low) if the frame rate stays under ~55 fps, or at once if several
 *     frames in a row take longer than 250 ms. 'low' also draws less: no
 *     grass tufts, 40 % of the scenery without shadows, 0.85 render scale,
 *     30 % of the wall sparks (medium 65 %).
 *   - Seven themes (setTheme): meadow, desert, alpine, canyon, dusk, night
 *     (moonlit, starry sky, lit lamps, glowing barrier stripes, a city on
 *     the horizon) and seaside (sea, beach, palms, a lighthouse, boats).
 *
 * Quality can be forced with ?gfx=high|medium|low in the URL (this also
 * switches the automatic governor off).
 */
import * as THREE from '../../vendor/three.module.min.js';
import { EffectComposer } from '../../vendor/addons/postprocessing/EffectComposer.js';
import { RenderPass } from '../../vendor/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from '../../vendor/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from '../../vendor/addons/postprocessing/OutputPass.js';
import { setSparkQuality } from './carMesh.js';

const DEG = Math.PI / 180;

/**
 * Look of each theme. Colours are sRGB hex. Used by World.setTheme (sky,
 * light, fog, bloom) and by trackMesh.js (terrain, scenery, track props).
 * Optional extras: sky.stars (0-1, night sky), glow (emissive stripes along
 * the barriers in accent[0]), skyline (lit city blocks on the horizon), sea
 * ({level, water, deep, sand, shallow}: the water `level` m below the
 * lowest ground beside the road, on the seaward side of the track, with a
 * beach, a lighthouse and boats; trackMesh.js picks the coast side per track).
 */
export const THEMES = {
  meadow: {
    sky: { zenith: 0x2a66cc, horizon: 0xc7def0, below: 0x6d8a4f, clouds: 0.42, cloudLit: 0xffffff, cloudShade: 0x9fb2c8, haze: 0.5 },
    sun: { color: 0xfff0d8, intensity: 3.3, elevation: 54, azimuth: 35 },
    hemi: { sky: 0xd6ebff, ground: 0x5d6f3c, intensity: 0.3 },
    env: 1.0,
    fog: { color: 0xc4dbec, near: 320, far: 2900 },
    exposure: 1.0,
    bloom: { strength: 0.22, radius: 0.45, threshold: 1.15 },
    ground: { a: 0x4b7a30, b: 0x6a9541, dry: 0x8f9150, dirt: 0x86704f, rock: 0x86847b, snow: null, far: 0x648a45 },
    hills: 9, mountains: 150, mountainStyle: 'peaks',
    accent: [0x2f6df6, 0xf2f5fa], lamps: false,
    scenery: ['broadleaf', 'pine', 'bush', 'rock'],
    tuft: { color: 0x6f9f3f, tip: 0xa8c46a },
  },
  desert: {
    sky: { zenith: 0x3c7cc9, horizon: 0xf0dcc0, below: 0xc8a06a, clouds: 0.14, cloudLit: 0xfff6ea, cloudShade: 0xd2b9a0, haze: 0.9 },
    sun: { color: 0xffe1b0, intensity: 3.6, elevation: 46, azimuth: 120 },
    hemi: { sky: 0xffe9cc, ground: 0xa07a4c, intensity: 0.3 },
    env: 1.0,
    fog: { color: 0xe9d4b6, near: 180, far: 2300 },
    exposure: 0.95,
    bloom: { strength: 0.2, radius: 0.45, threshold: 1.3 },
    ground: { a: 0xd6b07a, b: 0xc89b62, dry: 0xb98d58, dirt: 0xa77a4f, rock: 0xa86b45, snow: null, far: 0xd3ab74 },
    hills: 7, mountains: 130, mountainStyle: 'mesa',
    accent: [0xe8742c, 0xf6efe4], lamps: false,
    scenery: ['saguaro', 'barrel', 'shrubDry', 'rockRed'],
    tuft: { color: 0xb59a5c, tip: 0xe0cc8a },
  },
  alpine: {
    sky: { zenith: 0x1b58bd, horizon: 0xd2e3f3, below: 0xdbe5ee, clouds: 0.36, cloudLit: 0xffffff, cloudShade: 0xa9b8cc, haze: 0.4 },
    sun: { color: 0xf1f5ff, intensity: 3.0, elevation: 34, azimuth: 205 },
    hemi: { sky: 0xdbe9ff, ground: 0x9aa4b0, intensity: 0.3 },
    env: 0.95,
    fog: { color: 0xcfe0ef, near: 380, far: 3300 },
    exposure: 0.88,
    bloom: { strength: 0.18, radius: 0.4, threshold: 1.7 },
    ground: { a: 0xe9eef4, b: 0xdfe6ee, dry: 0x8f9a7c, dirt: 0x7d7a74, rock: 0x7c7f86, snow: 0xf4f7fb, far: 0xe4ebf2 },
    hills: 12, mountains: 330, mountainStyle: 'peaks',
    accent: [0xd6262e, 0xf4f6f8], lamps: false,
    scenery: ['pineSnow', 'pine', 'rockGrey'],
    tuft: null,
  },
  canyon: {
    sky: { zenith: 0x3874c2, horizon: 0xeecaa6, below: 0xa65a38, clouds: 0.24, cloudLit: 0xfff1e4, cloudShade: 0xc9a58e, haze: 0.8 },
    sun: { color: 0xffd8a6, intensity: 3.5, elevation: 40, azimuth: 300 },
    hemi: { sky: 0xffe2c8, ground: 0x8c4a2e, intensity: 0.3 },
    env: 1.0,
    fog: { color: 0xe4bf9c, near: 220, far: 2500 },
    exposure: 0.95,
    bloom: { strength: 0.2, radius: 0.45, threshold: 1.3 },
    ground: { a: 0xb4643a, b: 0xc47a48, dry: 0xa98a5a, dirt: 0x8e4a2c, rock: 0x9a4a2c, snow: null, far: 0xb86a3e },
    hills: 10, mountains: 170, mountainStyle: 'mesa',
    accent: [0x1f9fb8, 0xf3ebe1], lamps: false,
    scenery: ['shrubDry', 'hoodoo', 'rockRed', 'juniper'],
    tuft: { color: 0x9f8a55, tip: 0xd2b878 },
  },
  dusk: {
    sky: { zenith: 0x1f2a63, horizon: 0xff9152, below: 0x3a2c38, clouds: 0.5, cloudLit: 0xffa070, cloudShade: 0x5b4b72, haze: 1.6 },
    sun: { color: 0xff9a55, intensity: 2.6, elevation: 15, azimuth: 250 },
    hemi: { sky: 0x7378c0, ground: 0x3c2a26, intensity: 0.95 },
    env: 1.2,
    fog: { color: 0xc07a68, near: 140, far: 2400 },
    exposure: 1.1,
    bloom: { strength: 0.55, radius: 0.55, threshold: 0.9 },
    ground: { a: 0x4a7332, b: 0x5d8338, dry: 0x7b7a46, dirt: 0x6b5842, rock: 0x6f6a66, snow: null, far: 0x4c6e34 },
    hills: 9, mountains: 120, mountainStyle: 'peaks',
    accent: [0x8a3cf0, 0xf2f2f6], lamps: true,
    scenery: ['broadleaf', 'pine', 'bush', 'rock'],
    tuft: { color: 0x58803a, tip: 0x93a95a },
  },
  night: {
    // the "sun" is the moon: cool, low light; most of the light comes from the lamps and stripes
    sky: { zenith: 0x040817, horizon: 0x1b2850, below: 0x0a1020, clouds: 0.22, cloudLit: 0x34405e, cloudShade: 0x0b1020, haze: 0.7, stars: 1 },
    sun: { color: 0xa9bcff, intensity: 0.95, elevation: 36, azimuth: 140 },
    hemi: { sky: 0x4a5f9a, ground: 0x1c2030, intensity: 1.1 },
    env: 2.4,
    fog: { color: 0x0b1224, near: 220, far: 2600 },
    exposure: 1.3,
    bloom: { strength: 0.5, radius: 0.5, threshold: 0.8 },
    ground: { a: 0x3d5233, b: 0x4a5e3a, dry: 0x5d5e44, dirt: 0x524638, rock: 0x5c5d63, snow: null, far: 0x2b3826 },
    hills: 6, mountains: 30, mountainStyle: 'peaks',
    accent: [0x16d0ff, 0xeef2f8], lamps: true, glow: true, skyline: true,
    scenery: ['pine', 'broadleaf', 'bush', 'rock'],
    tuft: { color: 0x40603a, tip: 0x6c8456 },
  },
  seaside: {
    sky: { zenith: 0x2470d4, horizon: 0xcde6f6, below: 0x2d6f8f, clouds: 0.3, cloudLit: 0xffffff, cloudShade: 0xa7bccf, haze: 0.6 },
    sun: { color: 0xfff1d8, intensity: 3.3, elevation: 48, azimuth: 205 },
    hemi: { sky: 0xd8ecff, ground: 0xb9a57c, intensity: 0.32 },
    env: 1.0,
    fog: { color: 0xc9e0ee, near: 380, far: 3400 },
    exposure: 1.0,
    bloom: { strength: 0.22, radius: 0.45, threshold: 1.15 },
    ground: { a: 0x6a9346, b: 0x7fa04c, dry: 0xb9a873, dirt: 0xa98f62, rock: 0x8e8a80, snow: null, far: 0x14465f },
    hills: 6, mountains: 120, mountainStyle: 'peaks',
    accent: [0x1d86d6, 0xf4f6f8], lamps: false,
    sea: { level: 1.6, water: 0x1b6a8c, deep: 0x123f5a, shallow: 0x58b8b4, sand: 0xe4d2a0 },
    scenery: ['palm', 'bushCoast', 'rock'],
    tuft: { color: 0x8aa456, tip: 0xd2c98a },
  },
};

export function getTheme(name) {
  return THEMES[name] ?? THEMES.meadow;
}

/** Unit vector pointing at the sun for a theme. */
export function sunDirection(theme, out = new THREE.Vector3()) {
  const el = theme.sun.elevation * DEG, az = theme.sun.azimuth * DEG;
  return out.set(Math.cos(el) * Math.sin(az), Math.sin(el), Math.cos(el) * Math.cos(az));
}

// Quality levels: pixel ratio cap, bloom on/off, shadow map size, how much
// scenery is drawn (share of trees/rocks, grass tufts on/off, scenery shadows)
// and the share of wall sparks.
const QUALITY = {
  high: { pr: 1.5, bloom: true, shadow: 2048, scenery: 1, tufts: true, sceneryShadows: true, sparks: 1 },
  medium: { pr: 1.25, bloom: false, shadow: 2048, scenery: 0.75, tufts: true, sceneryShadows: true, sparks: 0.65 },
  low: { pr: 0.85, bloom: false, shadow: 1024, scenery: 0.4, tufts: false, sceneryShadows: false, sparks: 0.3 },
};
const QUALITY_ORDER = ['high', 'medium', 'low'];

export class World {
  constructor(container) {
    this.container = container;
    this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1;
    // Count draw calls over the whole frame (shadow + main + post passes).
    this.renderer.info.autoReset = false;
    container.appendChild(this.renderer.domElement);

    this.scene = new THREE.Scene();
    this.scene.fog = new THREE.Fog(0xc4dbec, 300, 2900);
    this.camera = new THREE.PerspectiveCamera(70, 1, 0.3, 6000);

    this.sky = createSky();
    this.scene.add(this.sky);

    this.hemi = new THREE.HemisphereLight(0xdff1ff, 0x5d7a3a, 0.3);
    this.scene.add(this.hemi);

    // Sun with a shadow box that follows whatever the camera looks at.
    this.sun = new THREE.DirectionalLight(0xfff3dd, 3);
    this.sun.castShadow = true;
    this.shadowHalf = 64;
    const sc = this.sun.shadow.camera;
    sc.left = -this.shadowHalf; sc.right = this.shadowHalf; sc.top = this.shadowHalf; sc.bottom = -this.shadowHalf;
    sc.near = 1; sc.far = 900;
    this.sun.shadow.bias = -0.0004;
    this.sun.shadow.normalBias = 0.125; // set per quality in applyQuality()
    this.sun.shadow.mapSize.set(2048, 2048);
    this.sunDir = new THREE.Vector3(0.5, 0.8, 0.3).normalize();
    this.scene.add(this.sun, this.sun.target);

    this.pmrem = new THREE.PMREMGenerator(this.renderer);
    this.envCache = new Map();

    // Post-processing (bloom). The MSAA render target keeps edges smooth.
    const rt = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, samples: 4 });
    this.composer = new EffectComposer(this.renderer, rt);
    this.composer.addPass(new RenderPass(this.scene, this.camera));
    this.bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.25, 0.45, 1.15);
    // Run the bloom chain at quarter resolution: it is a soft glow anyway.
    const bloomSetSize = this.bloom.setSize.bind(this.bloom);
    this.bloom.setSize = (w, h) => bloomSetSize(Math.max(2, Math.round(w / 2)), Math.max(2, Math.round(h / 2)));
    this.composer.addPass(this.bloom);
    this.composer.addPass(new OutputPass());

    // Quality and the frame-time governor.
    let forced = null;
    try { forced = new URLSearchParams(window.location.search).get('gfx'); } catch (e) { /* ignore */ }
    this.autoQuality = !QUALITY[forced];
    this.quality = QUALITY[forced] ? forced : 'high';
    this._frames = [];
    this._lastRender = 0;
    this.stats = { calls: 0, triangles: 0, quality: this.quality };

    this.themeName = null;
    this.setTheme('meadow');
    this.applyQuality();
    window.addEventListener('resize', () => this.resize());
  }

  /** Switch sky, light, fog, environment and bloom to a theme ('meadow' if unknown). */
  setTheme(name) {
    const key = THEMES[name] ? name : 'meadow';
    if (key === this.themeName) return;
    this.themeName = key;
    const th = THEMES[key];
    this.theme = th;
    sunDirection(th, this.sunDir);

    const u = this.sky.material.uniforms;
    u.zenith.value.setHex(th.sky.zenith);
    u.horizon.value.setHex(th.sky.horizon);
    u.below.value.setHex(th.fog.color);
    u.sunDir.value.copy(this.sunDir);
    u.sunColor.value.setHex(th.sun.color);
    u.cloudCover.value = th.sky.clouds;
    u.cloudLit.value.setHex(th.sky.cloudLit);
    u.cloudShade.value.setHex(th.sky.cloudShade);
    u.haze.value = th.sky.haze;
    u.stars.value = th.sky.stars ?? 0;

    this.scene.fog.color.setHex(th.fog.color);
    this.scene.fog.near = th.fog.near;
    this.scene.fog.far = th.fog.far;
    this.renderer.setClearColor(th.fog.color);

    this.sun.color.setHex(th.sun.color);
    this.sun.intensity = th.sun.intensity;
    this.hemi.color.setHex(th.hemi.sky);
    this.hemi.groundColor.setHex(th.hemi.ground);
    this.hemi.intensity = th.hemi.intensity;
    this.renderer.toneMappingExposure = th.exposure;

    this.bloom.strength = th.bloom.strength;
    this.bloom.radius = th.bloom.radius;
    this.bloom.threshold = th.bloom.threshold;

    this.scene.environment = this.environmentFor(key, th);
    if (this._focus) this.focusShadows(this._focus.x, this._focus.y, this._focus.z);
  }

  /** PMREM environment baked from the theme's sky (cached per theme). */
  environmentFor(key, th) {
    if (this.envCache.has(key)) return this.envCache.get(key).texture;
    const envScene = new THREE.Scene();
    const mat = createSkyMaterial(true);
    const u = mat.uniforms;
    u.zenith.value.setHex(th.sky.zenith).multiplyScalar(th.env);
    u.horizon.value.setHex(th.sky.horizon).multiplyScalar(th.env);
    u.below.value.setHex(th.sky.below).multiplyScalar(th.env * 0.55);
    u.sunDir.value.copy(sunDirection(th));
    u.sunColor.value.setHex(th.sun.color).multiplyScalar(th.env);
    u.haze.value = th.sky.haze;
    const mesh = new THREE.Mesh(new THREE.SphereGeometry(50, 48, 24), mat);
    envScene.add(mesh);
    const rt = this.pmrem.fromScene(envScene, 0.02, 0.1, 200);
    mesh.geometry.dispose();
    mat.dispose();
    this.envCache.set(key, rt);
    return rt.texture;
  }

  resize() {
    const w = this.container.clientWidth || 1;
    const h = this.container.clientHeight || 1;
    this.renderer.setSize(w, h);
    this.composer.setSize(w, h);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  /** 'high' | 'medium' | 'low'. Set autoQuality = false as well to pin it. */
  setQuality(level) {
    if (!QUALITY[level]) return;
    this.quality = level;
    this.applyQuality();
  }

  applyQuality() {
    const q = QUALITY[this.quality];
    const pr = Math.min(window.devicePixelRatio || 1, q.pr);
    this.renderer.setPixelRatio(pr);
    this.composer.setPixelRatio(pr);
    if (this.sun.shadow.mapSize.x !== q.shadow) {
      this.sun.shadow.mapSize.set(q.shadow, q.shadow);
      if (this.sun.shadow.map) { this.sun.shadow.map.dispose(); this.sun.shadow.map = null; }
    }
    // about two shadow texels: no acne bands on the curved car body
    this.sun.shadow.normalBias = Math.min(0.2, (2 * this.shadowHalf / q.shadow) * 2);
    this.bloomOn = q.bloom;
    setSparkQuality(q.sparks);
    this.stats.quality = this.quality;
    this.applyDetail(this.scene);
    this.resize();
  }

  /** Thin out scenery under `root` for the current quality (call after adding a new track mesh). */
  applyDetail(root) {
    const q = QUALITY[this.quality];
    root.traverse((o) => {
      const d = o.userData.detail;
      if (d === 'tuft') o.visible = q.tufts;
      else if (d === 'scenery') {
        o.count = Math.max(1, Math.round(o.userData.fullCount * q.scenery));
        o.castShadow = q.sceneryShadows;
      }
    });
  }

  /**
   * Keep the shadow-casting light centred on the focus point, pushed a bit
   * towards where the camera looks and snapped to whole shadow texels.
   */
  focusShadows(x, y, z) {
    this._focus = this._focus ?? new THREE.Vector3();
    this._focus.set(x, y, z);
    const fwd = this.camera.getWorldDirection(_v1);
    fwd.y = 0;
    if (fwd.lengthSq() > 1e-6) fwd.normalize();
    const half = this.shadowHalf;
    const c = _v2.set(x + fwd.x * half * 0.45, y, z + fwd.z * half * 0.45);

    // Light-space axes (right/up) to snap the centre to the texel grid.
    const d = this.sunDir;
    const right = _v3.set(0, 1, 0).cross(d);
    if (right.lengthSq() < 1e-6) right.set(1, 0, 0);
    right.normalize();
    const up = _v4.copy(d).cross(right).normalize();
    const texel = (2 * half) / this.sun.shadow.mapSize.x;
    const r = Math.round(c.dot(right) / texel) * texel - c.dot(right);
    const u = Math.round(c.dot(up) / texel) * texel - c.dot(up);
    c.addScaledVector(right, r).addScaledVector(up, u);

    this.sun.target.position.copy(c);
    this.sun.position.copy(c).addScaledVector(d, 400);
    this.sun.target.updateMatrixWorld();
    this.sun.updateMatrixWorld();
  }

  render() {
    const now = performance.now();
    this._govern(now);
    this.renderer.info.reset();
    this.sky.material.uniforms.time.value = now / 1000;
    if (this.bloomOn) this.composer.render();
    else this.renderer.render(this.scene, this.camera);
    this.stats.calls = this.renderer.info.render.calls;
    this.stats.triangles = this.renderer.info.render.triangles;
  }

  /** Step quality down when most frames over ~2 s were slower than ~55 fps. */
  _govern(now) {
    const gap = now - this._lastRender;
    this._lastRender = now;
    if (!this.autoQuality || document.hidden) return;
    if (gap > 250) {
      // One long gap is a pause (track loading, theme switch, "Max" training).
      // Several in a row mean the machine draws under 4 frames a second.
      this._frames.length = 0;
      this._slowRun = gap < 15000 ? (this._slowRun ?? 0) + 1 : 0;
      if (this._slowRun >= 5) { this._slowRun = 0; this._stepDown(); }
      return;
    }
    this._slowRun = 0;
    this._frames.push(gap);
    if (this._frames.length < 120) return;
    const slow = this._frames.filter((t) => t > 18.5).length;
    this._frames.length = 0;
    if (slow > 80) this._stepDown();
  }

  _stepDown() {
    const i = QUALITY_ORDER.indexOf(this.quality);
    if (i < QUALITY_ORDER.length - 1) {
      this.setQuality(QUALITY_ORDER[i + 1]);
      console.info(`Track Rush: graphics quality lowered to "${this.quality}" to keep the frame rate up.`);
    }
  }
}

const _v1 = new THREE.Vector3(), _v2 = new THREE.Vector3(), _v3 = new THREE.Vector3(), _v4 = new THREE.Vector3();

// ---- sky ---------------------------------------------------------------------

const SKY_VERT = /* glsl */`
  varying vec3 vDir;
  void main() {
    vDir = position;
  #ifdef ENV
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  #else
    // Camera-centred, drawn at the far plane after the opaque scene.
    vec4 p = projectionMatrix * vec4(mat3(viewMatrix) * position, 1.0);
    gl_Position = p.xyww;
  #endif
  }`;

const SKY_FRAG = /* glsl */`
  uniform vec3 zenith, horizon, below, sunDir, sunColor, cloudLit, cloudShade;
  uniform float cloudCover, haze, time, stars;
  varying vec3 vDir;

  float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
  float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
  }
  float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int k = 0; k < 5; k++) { v += a * noise(p); p = p * 2.03 + vec2(17.1, 9.2); a *= 0.5; }
    return v;
  }

  void main() {
    vec3 d = normalize(vDir);
    float h = d.y;
    vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.5));
    float sd = max(dot(d, sunDir), 0.0);
    // warm glow around the sun, stronger near the horizon
    col += sunColor * (pow(sd, 6.0) * 0.22 * haze * (1.0 - 0.6 * clamp(h, 0.0, 1.0)) + pow(sd, 48.0) * 0.35);
  #ifdef ENV
    col = mix(col, below, smoothstep(0.02, -0.12, h));
  #else
    col += sunColor * smoothstep(0.99955, 0.9998, sd) * 18.0;
    if (stars > 0.0 && h > 0.0) {
      // star field: one possible star per small cell of the sky dome, a few percent of them lit
      vec3 q = d * 300.0, cell = floor(q);
      float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
      float b = smoothstep(0.3, 0.05, length(fract(q) - 0.5)) * smoothstep(0.985, 1.0, r);
      col += vec3(0.85, 0.9, 1.0) * b * 2.2 * stars * smoothstep(0.02, 0.3, h);
    }
    if (h > 0.0 && cloudCover > 0.0) {
      vec2 uv = d.xz / (h + 0.1) * 0.9 + vec2(time * 0.006, time * 0.002);
      float n = fbm(uv);
      float c = smoothstep(1.0 - cloudCover, 1.0 - cloudCover + 0.28, n) * smoothstep(0.0, 0.18, h);
      float lit = clamp(0.5 - (fbm(uv + sunDir.xz * 0.06) - n) * 3.0, 0.0, 1.0);
      vec3 cc = mix(cloudShade, cloudLit, lit) * (1.0 + pow(sd, 6.0) * 0.6);
      col = mix(col, cc, c * 0.92);
    }
    col = mix(col, below, smoothstep(0.0, -0.04, h));
  #endif
    gl_FragColor = vec4(col, 1.0);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;

function createSkyMaterial(env = false) {
  return new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    fog: false,
    defines: env ? { ENV: '' } : {},
    uniforms: {
      zenith: { value: new THREE.Color(0x3d8bff) },
      horizon: { value: new THREE.Color(0xcfeaff) },
      below: { value: new THREE.Color(0x6d8a4f) },
      sunDir: { value: new THREE.Vector3(0, 1, 0) },
      sunColor: { value: new THREE.Color(0xffffff) },
      cloudLit: { value: new THREE.Color(0xffffff) },
      cloudShade: { value: new THREE.Color(0xaabbcc) },
      cloudCover: { value: 0.4 },
      haze: { value: 0.5 },
      time: { value: 0 },
      stars: { value: 0 },
    },
    vertexShader: SKY_VERT,
    fragmentShader: SKY_FRAG,
  });
}

function createSky() {
  const sky = new THREE.Mesh(new THREE.SphereGeometry(10, 32, 16), createSkyMaterial(false));
  sky.frustumCulled = false;
  sky.renderOrder = 1e6; // after the opaque scene: only visible sky pixels are shaded
  return sky;
}
