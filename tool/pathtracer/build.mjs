import * as esbuild from 'esbuild';
import path from 'path';
const shim = path.resolve('src/three_shim.js');
await esbuild.build({
  entryPoints: ['src/entry.js'],
  bundle: true,
  format: 'iife',
  minify: true,
  target: ['es2020'],
  outfile: '../../assets/3d/pathtracer.min.js',
  plugins: [{
    name: 'three-global',
    setup(b) { b.onResolve({ filter: /^three$/ }, () => ({ path: shim })); },
  }],
  logLevel: 'info',
});
