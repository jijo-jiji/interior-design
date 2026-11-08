/* ─────────────────────────────────────────────────────────────────────────────
   What each style is made of: the colours, the texture sets (ids in
   assets/3d/textures/manifest.json), handles and plinth. Plain data, kept in
   step with the sales app's 3D page (assets/3d/index.html: STYLE_FINISHES and
   BENCHTOP_LOOKS); a test compares them.
   ──────────────────────────────────────────────────────────────────────────── */

export type CabinetFinish = 'japandi' | 'nordic' | 'minimalist' | 'industrial';

export interface FrontFinish {
  color: number;
  wood: boolean;
  roughness: number;
  /** Id of a texture set (assets/3d/textures/manifest.json); none: painted. */
  tex?: string;
}
export interface FinishSpec {
  base: FrontFinish;
  wall: FrontFinish;
  tall: FrontFinish;
  top: { color: number; roughness: number; tex?: string };
  handle: { kind: 'bar' | 'knob' | 'groove'; color: number; metalness: number; roughness: number };
  plinth: number;
}

export const STYLE_FINISHES: Record<CabinetFinish, FinishSpec> = {
  japandi: {
    base: { color: 0xe2c49c, wood: true, tex: 'oak_light', roughness: 0.62 },
    wall: { color: 0xf1ece3, wood: false, roughness: 0.55 },
    tall: { color: 0xe2c49c, wood: true, tex: 'oak_light', roughness: 0.62 },
    top: { color: 0xf6f2ec, tex: 'quartz_warm', roughness: 0.22 },
    handle: { kind: 'bar', color: 0xc9a24f, metalness: 0.9, roughness: 0.32 },
    plinth: 0x3b3027,
  },
  minimalist: {
    base: { color: 0x40454e, wood: false, roughness: 0.78 },
    wall: { color: 0xf4f4f1, wood: false, roughness: 0.6 },
    tall: { color: 0x40454e, wood: false, roughness: 0.78 },
    top: { color: 0xfafaf8, tex: 'quartz_snow', roughness: 0.18 },
    handle: { kind: 'groove', color: 0x121316, metalness: 0.2, roughness: 0.7 },
    plinth: 0x1d1f23,
  },
  nordic: {
    base: { color: 0xa7b5a0, wood: false, roughness: 0.66 },
    wall: { color: 0xf3f2ed, wood: false, roughness: 0.6 },
    tall: { color: 0xead6b4, wood: true, tex: 'birch', roughness: 0.6 },
    top: { color: 0xebe6dc, tex: 'terrazzo', roughness: 0.3 },
    handle: { kind: 'knob', color: 0xb7bcc2, metalness: 0.85, roughness: 0.35 },
    plinth: 0x4a4f48,
  },
  industrial: {
    base: { color: 0x7a5a44, wood: true, tex: 'walnut', roughness: 0.55 },
    wall: { color: 0x36383e, wood: false, roughness: 0.5 },
    tall: { color: 0x7a5a44, wood: true, tex: 'walnut', roughness: 0.55 },
    top: { color: 0x55575d, tex: 'slate_dark', roughness: 0.36 },
    handle: { kind: 'bar', color: 0x1b1b1d, metalness: 0.6, roughness: 0.45 },
    plinth: 0x18191c,
  },
};

/** Worktop looks chosen as a benchtop (the keys of the catalogue's benchtop
 *  options); any other benchtop keeps the style's own worktop. */
export const BENCHTOP_LOOKS: Record<string, { tex: string | null; color: number; roughness: number }> = {
  quartz_calacatta: { tex: 'calacatta', color: 0xffffff, roughness: 0.18 },
  granite_black: { tex: 'granite_black', color: 0xffffff, roughness: 0.2 },
  laminate_matte: { tex: null, color: 0xd9d5cc, roughness: 0.72 },
};
