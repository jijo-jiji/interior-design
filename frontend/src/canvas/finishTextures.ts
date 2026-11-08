/* ─────────────────────────────────────────────────────────────────────────────
   The finish textures of the 3D view: oak, birch and walnut veneers, quartz,
   Calacatta, granite, slate and terrazzo worktops, a plank floor, and a faint
   micro texture for painted fronts. They are the sales app's own files
   (assets/3d/textures/, made by tool/gen_finish_textures.py, or real photographs
   put there by the designer), built into the Studio, so both apps draw the
   same finishes and replacing the files changes both.

   Textures decode in the background. finishSet() answers null until a colour
   map has arrived, and the materials that asked are re-dressed through
   onTexturesChanged(); until then the old drawn textures stand in.
   ──────────────────────────────────────────────────────────────────────────── */
import { useSyncExternalStore } from 'react';
import * as THREE from 'three';
import manifestJson from '../../../assets/3d/textures/manifest.json';

interface TextureEntry {
  albedo: string;
  normal?: string;
  roughness?: string;
  /** Metres of surface per texture repeat. */
  tile_m: number;
  tile_h_m?: number;
  kind: string;
}
interface Manifest {
  textures: Record<string, TextureEntry>;
  micro?: { normal: string; roughness?: string; tile_m: number };
}

export const manifest = manifestJson as unknown as Manifest;

// Every file of the sales app's folder, as a URL the bundler gives it.
const urls = import.meta.glob('../../../assets/3d/textures/*.jpg', {
  eager: true,
  query: '?url',
  import: 'default',
}) as Record<string, string>;
const urlOf = (file: string): string | undefined => urls[`../../../assets/3d/textures/${file}`];

const tileOf = (kind: string, fallback: number) =>
  Object.values(manifest.textures).find((t) => t.kind === kind)?.tile_m ?? fallback;

/** Metres of front per grain repeat, and of worktop per stone repeat: one size
 *  per kind keeps every cabinet's grain the same scale. */
export const WOOD_TILE = tileOf('wood', 0.6);
export const STONE_TILE = tileOf('stone', 1.2);

export interface FinishSet {
  map: THREE.Texture;
  normalMap: THREE.Texture | null;
  roughnessMap: THREE.Texture | null;
  /** Metres per repeat across (and, for tiles that aren't square, down). */
  tile: number;
  tileH?: number;
  kind: string;
}

// ── Loading ──────────────────────────────────────────────────────────────────

const cache = new Map<string, THREE.Texture>();
const failed = new Set<string>();
let pending = 0;
let version = 0;
const listeners = new Set<() => void>();
const waiting: Array<() => void> = [];

const loader = new THREE.TextureLoader();

/** A texture from a file of the folder, loading in the background. Null if the
 *  file isn't there (or failed). A texture whose `.image` is undefined hasn't
 *  decoded yet. */
function fileMap(file: string | undefined, color: boolean): THREE.Texture | null {
  if (!file || failed.has(file)) return null;
  const cached = cache.get(file);
  if (cached) return cached;
  const url = urlOf(file);
  if (!url) return null;
  pending++;
  const settle = () => {
    pending--;
    version++;
    listeners.forEach((fn) => fn());
    if (pending === 0) waiting.splice(0).forEach((fn) => fn());
  };
  const tex = loader.load(
    url,
    () => settle(),
    undefined,
    () => {
      failed.add(file);
      cache.delete(file);
      settle();
    },
  );
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.anisotropy = 8;
  if (color) tex.colorSpace = THREE.SRGBColorSpace;
  cache.set(file, tex);
  return tex;
}

const decoded = (t: THREE.Texture | null): t is THREE.Texture => !!t && !!t.image;

/** The maps of a texture id, once its colour has decoded; null before that (or
 *  for an unknown id). Asking starts every map of the set loading. */
export function finishSet(id: string | undefined): FinishSet | null {
  const entry = id ? manifest.textures[id] : undefined;
  if (!entry) return null;
  const map = fileMap(entry.albedo, true);
  const normalMap = fileMap(entry.normal, false);
  const roughnessMap = fileMap(entry.roughness, false);
  if (!decoded(map)) return null;
  return {
    map,
    normalMap: decoded(normalMap) ? normalMap : null,
    roughnessMap: decoded(roughnessMap) ? roughnessMap : null,
    tile: entry.tile_m,
    tileH: entry.tile_h_m,
    kind: entry.kind,
  };
}

/** The close-up look of a matte painted or laminate front: faint relief and
 *  uneven gloss, used with a flat colour. */
export function microSet(): { normalMap: THREE.Texture; roughnessMap: THREE.Texture | null } | null {
  const m = manifest.micro;
  if (!m) return null;
  const normalMap = fileMap(m.normal, false);
  const roughnessMap = fileMap(m.roughness, false);
  if (!decoded(normalMap)) return null;
  return { normalMap, roughnessMap: decoded(roughnessMap) ? roughnessMap : null };
}

/** Runs [fn] now if nothing is decoding, else when everything asked for so far
 *  has. */
export function whenTexturesSettled(fn: () => void) {
  if (pending === 0) fn();
  else waiting.push(fn);
}

/** How many textures are still decoding. */
export const texturesPending = () => pending;

/** Called whenever a texture finishes decoding. Returns the way to stop. */
export function onTexturesChanged(fn: () => void): () => void {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
}

/** For React: re-renders when a texture arrives. */
export function useTextureVersion(): number {
  return useSyncExternalStore(
    (notify) => onTexturesChanged(notify),
    () => version,
  );
}
