# The path tracer bundle

`assets/3d/pathtracer.min.js` is [three-gpu-pathtracer](https://github.com/gkjohnson/three-gpu-pathtracer)
0.0.23 (with three-mesh-bvh 0.7.6), bundled as one classic script. The 3D page
uses it for the **true-lighting render** (`renderPictures` with
`engine: 'path'`): it follows light paths on the graphics chip, so light really
bounces between surfaces.

- It uses the page's own `THREE` (r160, `assets/3d/three.min.js`), not a copy:
  `src/three_shim.js` stands in for `import 'three'`.
- r160 lacks a few scene properties the library reads (environment and
  background rotation, intensities); `src/entry.js` gives the scene defaults.
- `src/entry.js` exports `window.PathTracerLib` (`WebGLPathTracer`,
  `GradientEquirectTexture`, `DenoiseMaterial`, `FullScreenQuad`).
- The app puts the script in the page next to three.js
  (`ViewerScreen._loadHtml`); without it, or on a device without WebGL 2 float
  render targets, the page falls back on the sky-averaged render.

## Rebuilding it

Only needed to change the library version or the exports. Needs Node 18+.

```bash
cd tool/pathtracer
npm install
npm run build
```

The output goes straight to `assets/3d/pathtracer.min.js` (about 200 KB).
Licences of what is inside are in `assets/3d/pathtracer.LICENSE.txt`.
