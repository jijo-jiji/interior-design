/* ─────────────────────────────────────────────────────────────────────────────
   The studio's cabinet model, and the conversion to and from the records the
   sales app and the backend store.

   Conventions (all distances in metres inside the studio):
   - Main run: `x` is the cabinet's left edge, measured from the left end of
     the main wall. The sales app and the backend's DXF export store `x_mm` as
     the cabinet's CENTRE measured from the wall's CENTRE, so both are written.
   - Return run (L-shape, against the left wall): `x` is the edge nearest the
     main wall, measured out along the return wall. Stored as `offset_mm`, the
     cabinet's centre from the main wall.
   - `mount` is the height of the cabinet's underside above the floor.
   ──────────────────────────────────────────────────────────────────────────── */

export type CabinetKind =
  | 'base'
  | 'drawer'
  | 'sink'
  | 'hob'
  | 'tall'
  | 'corner'
  | 'wall'
  | 'filler'
  | 'dishwasher'
  | 'oven'
  | 'fridge'
  | 'hood';

export type Run = 'main' | 'return';

export interface CabinetData {
  id: string;
  /** Catalogue key (e.g. `base_600`) or a generated code (e.g. `base_drawer_450`). */
  type: string;
  kind: CabinetKind;
  label: string;
  run: Run;
  x: number;
  width: number;
  height: number;
  depth: number;
  mount: number;
  isWallMounted: boolean;
  /** Laid out by the sales app's generator (keeps its exact sizes and kind). */
  generated?: boolean;
  /** False for a cooktop placed on its own: the rangehood is a separate module. */
  hood?: boolean;
}

/** Modules the studio can add. Sizes match CABINET_SPECS in assets/3d/index.html. */
export const MODULE_SPECS = {
  base_800: { width: 0.8, height: 0.85, depth: 0.6, mount: 0, label: 'Base 800' },
  base_600: { width: 0.6, height: 0.85, depth: 0.6, mount: 0, label: 'Base 600' },
  wall_600: { width: 0.6, height: 0.7, depth: 0.32, mount: 1.4, label: 'Wall 600' },
  tall_600: { width: 0.6, height: 2.1, depth: 0.6, mount: 0, label: 'Tall 600' },
  corner_900: { width: 0.9, height: 0.85, depth: 0.9, mount: 0, label: 'Corner 900' },
  sink_600: { width: 0.6, height: 0.85, depth: 0.6, mount: 0, label: 'Sink 600' },
  cooktop_600: { width: 0.6, height: 0.85, depth: 0.6, mount: 0, label: 'Cooktop 600' },
  dishwasher_600: { width: 0.6, height: 0.85, depth: 0.6, mount: 0, label: 'Dishwasher' },
  oven_tower_600: { width: 0.6, height: 2.1, depth: 0.6, mount: 0, label: 'Oven tower' },
  fridge_recess_700: { width: 0.7, height: 2.1, depth: 0.65, mount: 0, label: 'Fridge recess' },
  rangehood_900: { width: 0.9, height: 0.45, depth: 0.5, mount: 1.55, label: 'Rangehood' },
} as const;

export type ModuleType = keyof typeof MODULE_SPECS;

export const isModuleType = (type: string): type is ModuleType => type in MODULE_SPECS;

/** How a cabinet is drawn, from its stored kind or else its type code. */
export function kindOf(type: string, storedKind?: unknown): CabinetKind {
  const known: CabinetKind[] = [
    'base', 'drawer', 'sink', 'hob', 'tall', 'corner', 'wall', 'filler',
    'dishwasher', 'oven', 'fridge', 'hood',
  ];
  if (typeof storedKind === 'string' && (known as string[]).includes(storedKind)) {
    return storedKind as CabinetKind;
  }
  const rules: [string, CabinetKind][] = [
    ['base_drawer', 'drawer'],
    ['base_sink', 'sink'],
    ['sink', 'sink'],
    ['base_hob', 'hob'],
    ['cooktop', 'hob'],
    ['dishwasher', 'dishwasher'],
    ['oven', 'oven'],
    ['fridge', 'fridge'],
    ['rangehood', 'hood'],
    ['wall', 'wall'],
    ['tall', 'tall'],
    ['corner', 'corner'],
    ['filler', 'filler'],
  ];
  return rules.find(([prefix]) => type.startsWith(prefix))?.[1] ?? 'base';
}

const KIND_NAMES: Record<CabinetKind, string> = {
  base: 'Base',
  drawer: 'Drawers',
  sink: 'Sink',
  hob: 'Cooktop',
  tall: 'Tall',
  corner: 'Corner',
  wall: 'Wall',
  filler: 'Filler',
  dishwasher: 'Dishwasher',
  oven: 'Oven tower',
  fridge: 'Fridge recess',
  hood: 'Rangehood',
};

/** "Base 800", "Drawers 450", "Filler 75". */
export function labelFor(type: string, kind: CabinetKind, widthM: number): string {
  if (isModuleType(type)) return MODULE_SPECS[type].label;
  return `${KIND_NAMES[kind]} ${Math.round(widthM * 1000)}`;
}

const num = (v: unknown): number | undefined =>
  typeof v === 'number' && Number.isFinite(v) ? v : undefined;

/** A stored cabinet (sales app, backend or an earlier studio save) → studio. */
export function fromEntry(c: Record<string, unknown>, index: number, wallWidthM: number): CabinetData {
  const type = String(c.cabinet_type ?? c.type ?? 'base_600');
  const kind = kindOf(type, c.kind);
  const spec = isModuleType(type) ? MODULE_SPECS[type] : undefined;
  const mm = (key: string) => {
    const v = num(c[key]);
    return v === undefined ? undefined : v / 1000;
  };

  const width = num(c.width) ?? mm('width_mm') ?? spec?.width ?? 0.6;
  const height = num(c.height) ?? mm('height_mm') ?? spec?.height ?? 0.85;
  const depth = num(c.depth) ?? mm('depth_mm') ?? spec?.depth ?? 0.6;
  const mount =
    mm('mount_mm') ??
    spec?.mount ??
    (kind === 'wall' ? MODULE_SPECS.wall_600.mount : kind === 'hood' ? MODULE_SPECS.rangehood_900.mount : 0);
  const run: Run = c.run === 'return' ? 'return' : 'main';

  let x: number;
  if (run === 'return') {
    // Centre from the main wall → the edge nearest it.
    x = (mm('offset_mm') ?? 0) - width / 2;
  } else if (num(c.x) !== undefined) {
    // Saved by the studio: already a left edge in metres.
    x = num(c.x)!;
  } else if (mm('x_mm') !== undefined) {
    // Sales app: centre measured from the centre of the wall.
    x = mm('x_mm')! + wallWidthM / 2 - width / 2;
  } else if (mm('distance_from_left_mm') !== undefined) {
    x = mm('distance_from_left_mm')!;
  } else {
    x = 0.05 + index * 0.65;
  }

  return {
    id: String(c.id ?? `cab-${index + 1}`),
    type,
    kind,
    label: typeof c.label === 'string' && c.label ? c.label : labelFor(type, kind, width),
    run,
    x: Math.max(0, Math.round(x * 1000) / 1000),
    width,
    height,
    depth,
    mount,
    isWallMounted: mount > 0 || kind === 'wall' || kind === 'hood',
    generated: c.generated === true ? true : undefined,
    hood: c.hood === false || type === 'cooktop_600' ? false : undefined,
  };
}

const round = (m: number) => Math.round(m * 1000);

/** Studio → the record the sales app, the backend and its exports read. */
export function toEntry(cab: CabinetData, wallWidthM: number): Record<string, unknown> {
  const position =
    cab.run === 'return'
      ? { offset_mm: round(cab.x + cab.width / 2), wall_index: 1 }
      : {
          x_mm: round(cab.x + cab.width / 2 - wallWidthM / 2),
          distance_from_left_mm: round(cab.x),
          wall_index: 0,
        };
  return {
    id: cab.id,
    cabinet_type: cab.type,
    type: cab.type,
    label: cab.label,
    kind: cab.kind,
    run: cab.run,
    ...(cab.generated ? { generated: true } : {}),
    // Studio's own fields (metres), read back first when the studio reopens it.
    x: cab.x,
    width: cab.width,
    height: cab.height,
    depth: cab.depth,
    width_mm: round(cab.width),
    height_mm: round(cab.height),
    depth_mm: round(cab.depth),
    mount_mm: round(cab.mount),
    ...position,
  };
}

/** A new module from the toolbar, at [x] on the main run. */
export function newModule(type: ModuleType, x: number): CabinetData {
  const spec = MODULE_SPECS[type];
  const kind = kindOf(type);
  return {
    id: `cab-${Date.now()}`,
    type,
    kind,
    label: spec.label,
    run: 'main',
    x,
    width: spec.width,
    height: spec.height,
    depth: spec.depth,
    mount: spec.mount,
    isWallMounted: spec.mount > 0,
    hood: type === 'cooktop_600' ? false : undefined,
  };
}

/** Reading order: main-run floor units left to right, then wall units, then
 *  the return run. Used for the cabinet list. */
export function readingOrder(a: CabinetData, b: CabinetData): number {
  const rank = (c: CabinetData) => (c.run === 'return' ? 2 : 0) + (c.isWallMounted ? 1 : 0);
  return rank(a) - rank(b) || a.x - b.x;
}

/** "Main wall, 1,200 mm from the left" / "Side wall, 300 mm from the corner". */
export function positionLabel(cab: CabinetData): string {
  const mm = Math.round(cab.x * 1000).toLocaleString('en-MY');
  return cab.run === 'return'
    ? `Side wall, ${mm} mm from the corner`
    : `Main wall, ${mm} mm from the left`;
}
