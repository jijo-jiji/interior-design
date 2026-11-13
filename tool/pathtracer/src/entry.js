import { WebGLPathTracer, GradientEquirectTexture, DenoiseMaterial } from 'three-gpu-pathtracer';
import { FullScreenQuad } from 'three/examples/jsm/postprocessing/Pass.js';

// The path tracer reads scene properties that three added after r160
// (environment and background rotation, intensities, blurriness). Give the
// scene the defaults, so it runs on the three the 3D page ships.
const T = window.THREE;
const defaults = {
  environmentRotation: () => new T.Euler(),
  backgroundRotation: () => new T.Euler(),
  environmentIntensity: () => 1,
  backgroundIntensity: () => 1,
  backgroundBlurriness: () => 0,
};
for (const [key, make] of Object.entries(defaults)) {
  if (!(key in T.Scene.prototype)) {
    const shared = make();
    Object.defineProperty(T.Scene.prototype, key, {
      configurable: true,
      get() { return Object.prototype.hasOwnProperty.call(this, '_' + key) ? this['_' + key] : shared; },
      set(v) { this['_' + key] = v; },
    });
  }
}

window.PathTracerLib = { WebGLPathTracer, GradientEquirectTexture, DenoiseMaterial, FullScreenQuad };
