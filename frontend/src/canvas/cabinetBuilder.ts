/* ─────────────────────────────────────────────────────────────────────────────
   Cabinet geometry, ported from the sales app's 3D page (assets/3d/index.html:
   STYLE_FINISHES, buildCabinetParts and friends) so the studio draws exactly
   the kitchen the client was shown: plinth, carcass, fronts with 3 mm reveals,
   handles by style, worktop, sink, hob, appliances and corner units.

   A cabinet object is centred on its bounding box (w × h × d), back against
   the wall at local z = −d/2, front facing +z. Keep the numbers here in step
   with the sales app.
   ──────────────────────────────────────────────────────────────────────────── */
import * as THREE from 'three';
import type { CabinetKind } from '../layout/model';
import { BENCHTOP_LOOKS, STYLE_FINISHES } from './finishes';
import type { CabinetFinish, FinishSpec, FrontFinish } from './finishes';
import { STONE_TILE, WOOD_TILE, finishSet, microSet, onTexturesChanged } from './finishTextures';

/** Door face. Handles come from the finish, as in the sales app. */
export type DoorStyle = 'slab' | 'shaker' | 'fluted';

export { STYLE_FINISHES };
export type { CabinetFinish, FinishSpec, FrontFinish };

const PLINTH_H = 0.1;
const PLINTH_SET = 0.06;
const FRONT_T = 0.018;
const GAP = 0.003;
const TOP_T = 0.04;
const TOP_OVER = 0.02;
const ARM_D = 0.6;
const TALL_KINDS = new Set<CabinetKind>(['tall', 'oven', 'fridge']);

export interface CabinetSpec {
  kind: CabinetKind;
  w: number;
  h: number;
  d: number;
  isWall: boolean;
  /** Height of the underside above the floor (wall units, hood). */
  mount: number;
  hood?: boolean;
}

// ── Textures and materials (one set per finish, shared by every cabinet) ─────

function seededRandom(seed: number) {
  let s = seed;
  return () => (s = (s * 16807) % 2147483647) / 2147483647;
}

function canvasTexture(size: number, draw: (g: CanvasRenderingContext2D, n: number) => void) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  draw(c.getContext('2d')!, size);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

let woodTex: THREE.CanvasTexture | null = null;
let stoneTex: THREE.CanvasTexture | null = null;

function woodTexture() {
  woodTex ??= canvasTexture(512, (g, n) => {
    const r = seededRandom(7);
    g.fillStyle = '#ebebeb';
    g.fillRect(0, 0, n, n);
    for (let i = 0; i < 170; i++) {
      const x = r() * n, phase = r() * 6.28, amp = 2 + r() * 6;
      const shade = Math.round(175 + r() * 70);
      g.strokeStyle = `rgba(${shade},${shade},${shade},${0.25 + r() * 0.35})`;
      g.lineWidth = 0.6 + r() * 2.4;
      g.beginPath();
      for (let y = -8; y <= n + 8; y += 16) {
        const xx = x + Math.sin(y * 0.012 + phase) * amp;
        if (y < 0) g.moveTo(xx, y);
        else g.lineTo(xx, y);
      }
      g.stroke();
    }
  });
  return woodTex;
}

function stoneTexture() {
  stoneTex ??= canvasTexture(512, (g, n) => {
    const r = seededRandom(11);
    g.fillStyle = '#f2f2f2';
    g.fillRect(0, 0, n, n);
    for (let i = 0; i < 3500; i++) {
      const v = Math.round(150 + r() * 90);
      g.fillStyle = `rgba(${v},${v},${v},0.12)`;
      g.fillRect(r() * n, r() * n, 1.4, 1.4);
    }
    for (let i = 0; i < 5; i++) {
      const pts = [[r() * n, -20], [r() * n, n * 0.35], [r() * n, n * 0.7], [r() * n, n + 20]];
      for (const [width, alpha] of [[10, 0.035], [4, 0.06], [1.2, 0.1]]) {
        g.strokeStyle = `rgba(140,140,140,${alpha})`;
        g.lineWidth = width;
        g.beginPath();
        g.moveTo(pts[0][0], pts[0][1]);
        g.bezierCurveTo(pts[1][0], pts[1][1], pts[2][0], pts[2][1], pts[3][0], pts[3][1]);
        g.stroke();
      }
    }
  });
  return stoneTex;
}

interface Materials {
  base: THREE.MeshStandardMaterial;
  wall: THREE.MeshStandardMaterial;
  tall: THREE.MeshStandardMaterial;
  top: THREE.MeshPhysicalMaterial;
  handle: THREE.MeshStandardMaterial;
  plinth: THREE.MeshStandardMaterial;
  reveal: THREE.MeshStandardMaterial;
  steel: THREE.MeshStandardMaterial;
  basin: THREE.MeshStandardMaterial;
  glass: THREE.MeshStandardMaterial;
  burner: THREE.MeshStandardMaterial;
  led: THREE.MeshBasicMaterial;
}

const materialCache = new Map<string, Materials>();
/** What each cached set of materials is dressed for, to dress it again when a
 *  texture arrives. */
const dressing = new Map<Materials, { fin: FinishSpec; benchtop: string | null }>();
let shared: Pick<Materials, 'reveal' | 'steel' | 'basin' | 'glass' | 'burner' | 'led'> | null = null;

/** A front: a real finish's own colours, relief and gloss, or a flat colour
 *  with a faint micro texture (painted, laminate). Until a texture has decoded
 *  a wood front shows the grain the page draws itself. */
function setFront(mat: THREE.MeshStandardMaterial, f: FrontFinish) {
  const set = f.tex ? finishSet(f.tex) : null;
  if (set) {
    mat.color.setHex(0xffffff);
    mat.map = set.map;
    mat.normalMap = set.normalMap;
    mat.normalScale.set(0.8, 0.8);
    mat.roughnessMap = set.roughnessMap;
    mat.roughness = set.roughnessMap ? 1 : f.roughness;
  } else {
    const micro = f.wood ? null : microSet();
    mat.color.setHex(f.color);
    mat.map = f.wood ? woodTexture() : null;
    mat.normalMap = micro ? micro.normalMap : null;
    mat.normalScale.set(0.08, 0.08);
    mat.roughnessMap = micro ? micro.roughnessMap : null;
    mat.roughness = micro?.roughnessMap ? Math.min(1, f.roughness / 0.62) : f.roughness;
  }
  mat.needsUpdate = true;
}

/** The worktop: the style's own, or the benchtop chosen. */
function setTop(top: THREE.MeshPhysicalMaterial, fin: FinishSpec, benchtop: string | null) {
  const look = benchtop ? BENCHTOP_LOOKS[benchtop] : undefined;
  const spec = look ?? fin.top;
  const set = spec.tex ? finishSet(spec.tex) : null;
  if (set) {
    top.color.setHex(0xffffff);
    top.map = set.map;
    top.normalMap = set.normalMap;
    top.normalScale.set(0.7, 0.7);
    top.roughnessMap = set.roughnessMap;
    // The roughness map holds the real gloss; polished stone also gets a clear coat.
    top.roughness = set.roughnessMap ? 1 : spec.roughness;
    top.clearcoat = spec.roughness < 0.3 ? 0.35 : 0.08;
  } else {
    const micro = look ? microSet() : null;
    top.color.setHex(spec.color);
    top.map = look ? null : stoneTexture();
    top.normalMap = micro ? micro.normalMap : null;
    top.normalScale.set(0.06, 0.06);
    top.roughnessMap = micro ? micro.roughnessMap : null;
    top.roughness = micro?.roughnessMap ? Math.min(1, spec.roughness / 0.62) : spec.roughness;
    top.clearcoat = look ? 0 : 0.3;
  }
  top.needsUpdate = true;
}

function dress(m: Materials, fin: FinishSpec, benchtop: string | null) {
  setFront(m.base, fin.base);
  setFront(m.wall, fin.wall);
  setFront(m.tall, fin.tall);
  setTop(m.top, fin, benchtop);
}

// Textures decode in the background: when one arrives, every set of materials
// takes it.
onTexturesChanged(() => {
  for (const [m, { fin, benchtop }] of dressing) dress(m, fin, benchtop);
});

function materialsFor(finish: CabinetFinish, benchtop: string | null): Materials {
  const key = `${finish}|${benchtop ?? ''}`;
  const cached = materialCache.get(key);
  if (cached) return cached;
  const fin = STYLE_FINISHES[finish] ?? STYLE_FINISHES.japandi;
  const std = (o: THREE.MeshStandardMaterialParameters) => new THREE.MeshStandardMaterial(o);
  shared ??= {
    reveal: std({ color: 0x14120f, roughness: 1 }),
    steel: std({ color: 0xcfd2d6, metalness: 0.9, roughness: 0.28 }),
    basin: std({ color: 0xd3d6da, metalness: 0.55, roughness: 0.38, side: THREE.BackSide }),
    glass: std({ color: 0x0b0b0d, metalness: 0.2, roughness: 0.06 }),
    burner: std({ color: 0x55575b, metalness: 0.4, roughness: 0.55 }),
    led: new THREE.MeshBasicMaterial({ color: 0xfff0d2 }),
  };
  const m: Materials = {
    base: std({ metalness: 0.02 }),
    wall: std({ metalness: 0.02 }),
    tall: std({ metalness: 0.02 }),
    top: new THREE.MeshPhysicalMaterial({ metalness: 0, clearcoat: 0.3, clearcoatRoughness: 0.14 }),
    handle: std({ color: fin.handle.color, metalness: fin.handle.metalness, roughness: fin.handle.roughness }),
    plinth: std({ color: fin.plinth, roughness: 0.9 }),
    ...shared,
  };
  dress(m, fin, benchtop);
  dressing.set(m, { fin, benchtop });
  materialCache.set(key, m);
  return m;
}

/** Box with UVs in metres / tile so grain keeps its scale on every panel. */
let uvSeed = 0;
function boxGeo(w: number, h: number, d: number, tile?: number) {
  const g = new THREE.BoxGeometry(w, h, d);
  if (!tile) return g;
  const uv = g.attributes.uv as THREE.BufferAttribute;
  const offset = (uvSeed++ * 0.6180339) % 1;
  const dims = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];
  for (let f = 0; f < 6; f++) {
    for (let k = 0; k < 4; k++) {
      const i = f * 4 + k;
      uv.setXY(i, (uv.getX(i) * dims[f][0]) / tile + offset, (uv.getY(i) * dims[f][1]) / tile);
    }
  }
  return g;
}

type Add = (geo: THREE.BufferGeometry, mat: THREE.Material, x: number, y: number, z: number, cast?: boolean) => THREE.Mesh;

interface HandleOpts {
  side?: 'left' | 'right';
  at?: 'top' | 'bottom';
  long?: boolean;
  drawer?: boolean;
  appliance?: 'oven' | 'fridge';
}

// ── Builder ──────────────────────────────────────────────────────────────────

/**
 * Builds one cabinet. [ceiling] is the room height (m), used to run a
 * rangehood chimney up to it.
 */
export function buildCabinet(
  spec: CabinetSpec,
  finish: CabinetFinish,
  doorStyle: DoorStyle,
  ceiling: number,
  /** The benchtop chosen (a key of the catalogue's benchtop options), if any. */
  benchtop: string | null = null,
): THREE.Group {
  const group = new THREE.Group();
  const M = materialsFor(finish, benchtop);
  const handleKind = (STYLE_FINISHES[finish] ?? STYLE_FINISHES.japandi).handle.kind;
  const add: Add = (geo, mat, x, y, z, cast = true) => {
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.set(x, y, z);
    mesh.castShadow = cast;
    mesh.receiveShadow = true;
    group.add(mesh);
    return mesh;
  };
  const { w, h, d, kind, isWall } = spec;
  const fm = isWall ? M.wall : TALL_KINDS.has(kind) ? M.tall : M.base;
  const bottom = -h / 2;
  const front = d / 2;
  const topY = h / 2 + TOP_T / 2;

  const addHandle = (x0: number, x1: number, y0: number, y1: number, z: number, o: HandleOpts) => {
    const cx = (x0 + x1) / 2;
    if (handleKind === 'groove') {
      const gy = o.drawer || o.at === 'top' ? y1 - 0.006 : y0 + 0.006;
      add(boxGeo(x1 - x0, 0.012, 0.003), M.handle, cx, gy, z + 0.0015, false);
      return;
    }
    const knob = () => {
      const g = new THREE.CylinderGeometry(0.014, 0.016, 0.024, 16);
      g.rotateX(Math.PI / 2);
      return g;
    };
    if (o.drawer) {
      const y = y1 - Math.min(0.05, (y1 - y0) / 2);
      if (handleKind === 'bar') add(boxGeo(Math.min(0.32, (x1 - x0) * 0.5), 0.012, 0.014), M.handle, cx, y, z + 0.016);
      else add(knob(), M.handle, cx, y, z + 0.012);
      return;
    }
    const ex = o.side === 'right' ? x1 - 0.04 : x0 + 0.04;
    if (handleKind === 'bar') {
      const len = o.long ? Math.min(0.5, (y1 - y0) * 0.45) : Math.min(0.16, (y1 - y0) * 0.4);
      const y = o.at === 'top' ? y1 - 0.06 - len / 2 : y0 + 0.06 + len / 2;
      add(boxGeo(0.012, len, 0.014), M.handle, ex, y, z + 0.016);
    } else {
      add(knob(), M.handle, ex, o.at === 'top' ? y1 - 0.07 : y0 + 0.07, z + 0.012);
    }
  };

  // Shaker frames or fluting on a door front (the studio's door-style choice).
  const decorateFront = (cx: number, cy: number, fw: number, fh: number, z: number) => {
    if (doorStyle === 'shaker') {
      const rail = Math.min(0.06, fw * 0.16, fh * 0.16);
      add(boxGeo(fw, rail, 0.006), fm, cx, cy + fh / 2 - rail / 2, z + 0.003, false);
      add(boxGeo(fw, rail, 0.006), fm, cx, cy - fh / 2 + rail / 2, z + 0.003, false);
      add(boxGeo(rail, fh - 2 * rail, 0.006), fm, cx - fw / 2 + rail / 2, cy, z + 0.003, false);
      add(boxGeo(rail, fh - 2 * rail, 0.006), fm, cx + fw / 2 - rail / 2, cy, z + 0.003, false);
    } else if (doorStyle === 'fluted') {
      const n = Math.max(2, Math.floor(fw / 0.03));
      const pitch = fw / n;
      for (let i = 0; i < n; i++) {
        add(boxGeo(pitch * 0.55, fh - 0.01, 0.005), fm, cx - fw / 2 + pitch * (i + 0.5), cy, z + 0.0025, false);
      }
    }
  };

  const applianceFront = (o: HandleOpts, cx: number, cy: number, fw: number, fh: number) => {
    add(boxGeo(fw, fh, FRONT_T), M.steel, cx, cy, front - FRONT_T / 2);
    const bar = (bw: number, bh: number, x: number, y: number) => {
      add(boxGeo(bw, bh, 0.016), M.steel, x, y, front + 0.028);
      const along = bw > bh;
      for (const s of [-1, 1]) {
        add(boxGeo(0.012, 0.012, 0.022), M.steel,
          along ? x + s * (bw / 2 - 0.02) : x, along ? y : y + s * (bh / 2 - 0.02), front + 0.011);
      }
    };
    if (o.appliance === 'oven') {
      const strip = Math.min(0.07, fh * 0.18);
      add(boxGeo(fw - 0.06, fh - strip - 0.06, 0.004), M.glass, cx, cy - strip / 2 - 0.01, front + 0.002, false);
      bar(fw * 0.72, 0.016, cx, cy + fh / 2 - strip - 0.004);
    } else {
      const len = Math.min(0.5, fh * 0.55);
      const y = o.at === 'top' ? cy + fh / 2 - len / 2 - 0.05 : cy - fh / 2 + len / 2 + 0.05;
      bar(0.016, len, cx + fw / 2 - 0.06, y);
    }
  };

  // ── Special shapes ──
  if (kind === 'hood') {
    add(boxGeo(w, 0.06, d), M.steel, 0, bottom + 0.03, 0);
    add(boxGeo(w * 0.86, 0.1, d * 0.8), M.steel, 0, bottom + 0.11, -d * 0.1);
    const chimneyBottom = bottom + 0.16;
    const chimneyH = Math.max(0.1, ceiling - spec.mount - h / 2 - chimneyBottom);
    add(boxGeo(0.28, chimneyH, 0.26), M.steel, 0, chimneyBottom + chimneyH / 2, -d / 2 + 0.13);
    add(boxGeo(w * 0.5, 0.004, 0.06), M.led, 0, bottom - 0.002, 0.05, false);
    return group;
  }

  if (kind === 'filler') {
    if (isWall) {
      add(boxGeo(w, h, d, WOOD_TILE), fm, 0, 0, 0);
    } else {
      add(boxGeo(w, PLINTH_H, d - PLINTH_SET), M.plinth, 0, bottom + PLINTH_H / 2, -PLINTH_SET / 2);
      add(boxGeo(w, h - PLINTH_H, d, WOOD_TILE), fm, 0, bottom + PLINTH_H + (h - PLINTH_H) / 2, 0);
      add(boxGeo(w, TOP_T, d + TOP_OVER, STONE_TILE), M.top, 0, topY, TOP_OVER / 2);
    }
    return group;
  }

  if (kind === 'corner') {
    const y0 = bottom + PLINTH_H;
    const bodyH = h / 2 - y0;
    const midY = y0 + bodyH / 2;
    const armD = Math.min(ARM_D, d);
    const notch = w - armD;
    const zA = -d / 2 + armD / 2;
    const xB = -w / 2 + armD / 2;
    add(boxGeo(w, PLINTH_H, armD - PLINTH_SET), M.plinth, 0, bottom + PLINTH_H / 2, zA - PLINTH_SET / 2);
    add(boxGeo(armD - PLINTH_SET, PLINTH_H, notch), M.plinth, xB - PLINTH_SET / 2, bottom + PLINTH_H / 2, d / 2 - notch / 2);
    add(boxGeo(w, bodyH, armD - FRONT_T, WOOD_TILE), M.base, 0, midY, zA - FRONT_T / 2);
    add(boxGeo(armD - FRONT_T, bodyH, notch, WOOD_TILE), M.base, xB - FRONT_T / 2, midY, d / 2 - notch / 2);
    const faceZ = -d / 2 + armD;
    const faceX = -w / 2 + armD;
    add(boxGeo(notch - GAP, bodyH - GAP, FRONT_T, WOOD_TILE), M.base, faceX + notch / 2, midY, faceZ - FRONT_T / 2);
    add(boxGeo(FRONT_T, bodyH - GAP, notch - GAP, WOOD_TILE), M.base, faceX - FRONT_T / 2, midY, faceZ + notch / 2);
    addHandle(faceX, faceX + notch, y0, h / 2, faceZ, { side: 'right', at: 'top' });
    add(boxGeo(w, TOP_T, armD + TOP_OVER, STONE_TILE), M.top, 0, topY, -d / 2 + (armD + TOP_OVER) / 2);
    add(boxGeo(armD + TOP_OVER, TOP_T, d - armD - TOP_OVER, STONE_TILE), M.top,
      -w / 2 + (armD + TOP_OVER) / 2, topY, (d / 2 + (-d / 2 + armD + TOP_OVER)) / 2);
    return group;
  }

  // ── Standard carcass ──
  const y0 = isWall ? bottom : bottom + PLINTH_H;
  const bodyH = h / 2 - y0;
  const midY = y0 + bodyH / 2;
  if (!isWall) add(boxGeo(w, PLINTH_H, d - PLINTH_SET), M.plinth, 0, bottom + PLINTH_H / 2, -PLINTH_SET / 2);

  const carcD = d - FRONT_T;
  const carcZ = -FRONT_T / 2;
  if (kind === 'sink') {
    const p = 0.018;
    add(boxGeo(p, bodyH, carcD, WOOD_TILE), fm, -w / 2 + p / 2, midY, carcZ);
    add(boxGeo(p, bodyH, carcD, WOOD_TILE), fm, w / 2 - p / 2, midY, carcZ);
    add(boxGeo(w - 2 * p, bodyH, p), fm, 0, midY, -d / 2 + p / 2);
    add(boxGeo(w - 2 * p, p, carcD), fm, 0, y0 + p / 2, carcZ);
  } else {
    add(boxGeo(w, bodyH, carcD, WOOD_TILE), fm, 0, midY, carcZ);
  }
  add(new THREE.PlaneGeometry(w - 0.004, bodyH - 0.004), M.reveal, 0, midY, front - FRONT_T + 0.0008, false);

  const x0 = -w / 2, x1 = w / 2, yTop = h / 2;
  const pair = w >= 0.5;
  type Front = [number, number, number, number, HandleOpts];
  const doors = (ya: number, yb: number, at: 'top' | 'bottom', long: boolean): Front[] =>
    pair
      ? [[x0, 0, ya, yb, { side: 'right', at, long }], [0, x1, ya, yb, { side: 'left', at, long }]]
      : [[x0, x1, ya, yb, { side: 'right', at, long }]];
  let fronts: Front[];
  if (kind === 'drawer' || kind === 'hob') {
    const hs = [0.22, 0.36, 0.42].map((f) => f * bodyH);
    fronts = [
      [x0, x1, yTop - hs[0], yTop, { drawer: true }],
      [x0, x1, yTop - hs[0] - hs[1], yTop - hs[0], { drawer: true }],
      [x0, x1, y0, yTop - hs[0] - hs[1], { drawer: true }],
    ];
  } else if (kind === 'tall') {
    const split = y0 + bodyH * 0.6;
    fronts = [...doors(y0, split, 'top', true), ...doors(split, yTop, 'bottom', false)];
  } else if (kind === 'dishwasher') {
    fronts = [[x0, x1, y0, yTop, { drawer: true }]];
  } else if (kind === 'oven') {
    const ovenB = bottom + 0.8, ovenT = ovenB + 0.6, microT = ovenT + 0.4;
    fronts = [
      [x0, x1, y0, ovenB, { drawer: true }],
      [x0, x1, ovenB, ovenT, { appliance: 'oven' }],
      [x0, x1, ovenT, microT, { appliance: 'oven' }],
      ...doors(microT, yTop, 'bottom', false),
    ];
  } else if (kind === 'fridge') {
    const fridgeT = bottom + 1.8;
    const freezerT = y0 + (fridgeT - y0) * 0.36;
    fronts = [
      [x0, x1, y0, freezerT, { appliance: 'fridge', at: 'top' }],
      [x0, x1, freezerT, fridgeT, { appliance: 'fridge', at: 'bottom' }],
      ...doors(fridgeT, yTop, 'bottom', false),
    ];
  } else {
    fronts = doors(y0, yTop, isWall ? 'bottom' : 'top', false);
  }
  for (const [a, b, ya, yb, o] of fronts) {
    const cx = (a + b) / 2, cy = (ya + yb) / 2, fw = b - a - GAP, fh = yb - ya - GAP;
    if (o.appliance) {
      applianceFront(o, cx, cy, fw, fh);
      continue;
    }
    add(boxGeo(fw, fh, FRONT_T, WOOD_TILE), fm, cx, cy, front - FRONT_T / 2);
    decorateFront(cx, cy, fw, fh, front);
    addHandle(a + GAP / 2, b - GAP / 2, ya + GAP / 2, yb - GAP / 2, front + (doorStyle === 'slab' ? 0 : 0.006), o);
  }

  if (!isWall && !TALL_KINDS.has(kind)) {
    if (kind === 'sink') buildSinkTop(spec, add, M);
    else add(boxGeo(w, TOP_T, d + TOP_OVER, STONE_TILE), M.top, 0, topY, TOP_OVER / 2);
    if (kind === 'hob') buildHob(spec, add, M, ceiling);
  }
  if (isWall) add(boxGeo(w - 0.04, 0.006, 0.016), M.led, 0, bottom - 0.003, front - 0.05, false);
  return group;
}

function buildSinkTop(spec: CabinetSpec, add: Add, M: Materials) {
  const { w, h, d } = spec;
  const topY = h / 2 + TOP_T / 2;
  const topD = d + TOP_OVER;
  const topZ0 = -d / 2;
  const bw = Math.min(w - 0.16, 0.72);
  const bd = 0.4;
  const bh = 0.18;
  const bz = 0.03;
  const side = (w - bw) / 2;
  add(boxGeo(side, TOP_T, topD, STONE_TILE), M.top, -w / 2 + side / 2, topY, TOP_OVER / 2);
  add(boxGeo(side, TOP_T, topD, STONE_TILE), M.top, w / 2 - side / 2, topY, TOP_OVER / 2);
  const backD = bz - bd / 2 - topZ0;
  add(boxGeo(bw, TOP_T, backD, STONE_TILE), M.top, 0, topY, topZ0 + backD / 2);
  const frontD = d / 2 + TOP_OVER - (bz + bd / 2);
  add(boxGeo(bw, TOP_T, frontD, STONE_TILE), M.top, 0, topY, bz + bd / 2 + frontD / 2);
  add(new THREE.BoxGeometry(bw, bh, bd), M.basin, 0, h / 2 + TOP_T - bh / 2, bz, false);
  const tz = bz - bd / 2 - 0.05;
  const base = h / 2 + TOP_T;
  add(new THREE.CylinderGeometry(0.022, 0.025, 0.04, 20), M.steel, 0, base + 0.02, tz);
  add(new THREE.CylinderGeometry(0.013, 0.013, 0.26, 16), M.steel, 0, base + 0.04 + 0.13, tz);
  const spout = new THREE.TorusGeometry(0.075, 0.013, 10, 24, Math.PI);
  spout.rotateY(-Math.PI / 2);
  add(spout, M.steel, 0, base + 0.3, tz + 0.075);
  add(new THREE.CylinderGeometry(0.014, 0.014, 0.03, 16), M.steel, 0, base + 0.285, tz + 0.15);
}

function buildHob(spec: CabinetSpec, add: Add, M: Materials, ceiling: number) {
  const { w, h, d } = spec;
  const pw = Math.min(w - 0.08, 0.6);
  const top = h / 2 + TOP_T;
  add(boxGeo(pw, 0.006, 0.5), M.glass, 0, top + 0.003, 0, false);
  const ring = () => {
    const g = new THREE.RingGeometry(0.045, 0.062, 28);
    g.rotateX(-Math.PI / 2);
    return g;
  };
  const xs = [-pw / 4, pw / 4];
  const zs = pw >= 0.55 ? [-0.11, 0.11] : [0];
  for (const x of xs) for (const z of zs) add(ring(), M.burner, x, top + 0.0065, z, false);
  if (spec.hood === false) return;
  const canopyW = Math.min(Math.max(w, 0.6), 0.9);
  const canopyBottom = 1.62;
  const chimneyH = Math.max(0.2, ceiling - canopyBottom - 0.07);
  add(boxGeo(canopyW, 0.07, 0.48), M.steel, 0, canopyBottom + 0.035 - h / 2, -d / 2 + 0.24);
  add(boxGeo(0.26, chimneyH, 0.24), M.steel, 0, canopyBottom + 0.07 + chimneyH / 2 - h / 2, -d / 2 + 0.12);
}

/** Frees a cabinet's geometry. Materials are shared and stay. */
export function disposeCabinet(group: THREE.Object3D) {
  group.traverse((child) => {
    if (child instanceof THREE.Mesh) child.geometry.dispose();
  });
}
