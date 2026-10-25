# three.js add-ons

Files copied unchanged (plus a one-line provenance header) from the npm package
`three@0.160.0`, folder `examples/jsm/`, keeping the same relative layout.
MIT licence, see `LICENSE` in this folder.

They import the bare specifier `"three"`, which the import map in `index.html` maps to
`./vendor/three.module.min.js` (the same file the game imports by relative path).
They are only used by the browser renderer (`src/game/scene.js`, bloom post-processing);
Node code (physics, AI, tracks, tools) must never import them.
