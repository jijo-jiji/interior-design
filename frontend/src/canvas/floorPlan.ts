/* ─────────────────────────────────────────────────────────────────────────────
   The floor plan a room was read from, for the Room and House views.

   The sales app reads the plan's walls and rooms by rule (no AI; see
   lib/features/floorplan/plan_geometry.dart) and stores them with the quote,
   in mm from the kitchen's corner: x along the main wall, z into the room.
   That is the studio's own frame (the main wall's inside face is z = 0, the
   side wall's is x = 0), so the numbers only need turning into metres.
   ──────────────────────────────────────────────────────────────────────────── */

export type RoomView = 'kitchen' | 'room' | 'house';

/** [x, z, width, depth] in mm, from the kitchen's corner. */
export type PlanRect = [number, number, number, number];

export interface FloorPlan {
  /** The plan's picture: a server address, or a data URL. */
  image?: string;
  imageCenterMm: [number, number];
  imageSizeMm: [number, number];
  /** The picture's turn about the vertical axis (three.js rotation.y). */
  imageRotationDeg: number;
  kitchenMm: PlanRect;
  wallThicknessMm: number;
  walls: PlanRect[];
  rooms: { name: string; rectMm: PlanRect }[];
}

const isRect = (v: unknown): v is PlanRect =>
  Array.isArray(v) && v.length === 4 && v.every((n) => typeof n === 'number' && Number.isFinite(n));

const isPair = (v: unknown): v is [number, number] =>
  Array.isArray(v) && v.length === 2 && v.every((n) => typeof n === 'number' && Number.isFinite(n));

/** A project's `floor_plan`, or null if it has none or it's malformed. */
export function readFloorPlan(raw: unknown): FloorPlan | null {
  if (!raw || typeof raw !== 'object') return null;
  const p = raw as Record<string, unknown>;
  if (!isRect(p.kitchen_mm) || !isPair(p.image_center_mm) || !isPair(p.image_size_mm)) return null;
  return {
    image: typeof p.image === 'string' ? p.image : undefined,
    imageCenterMm: p.image_center_mm,
    imageSizeMm: p.image_size_mm,
    imageRotationDeg: typeof p.image_rotation_deg === 'number' ? p.image_rotation_deg : 0,
    kitchenMm: p.kitchen_mm,
    wallThicknessMm: typeof p.wall_thickness_mm === 'number' ? p.wall_thickness_mm : 150,
    walls: Array.isArray(p.walls) ? p.walls.filter(isRect) : [],
    rooms: Array.isArray(p.rooms)
      ? p.rooms.flatMap((r) => {
          const room = r as Record<string, unknown>;
          return typeof room.name === 'string' && isRect(room.rect_mm) ? [{ name: room.name, rectMm: room.rect_mm }] : [];
        })
      : [],
  };
}

/** A wall to raise, in metres: centre on the floor, and size. */
export interface WallBox {
  x: number;
  z: number;
  width: number;
  depth: number;
}

/** What two rectangles share, or null. */
function overlap([x, z, w, d]: PlanRect, [bx, bz, bw, bd]: PlanRect): PlanRect | null {
  const x0 = Math.max(x, bx);
  const z0 = Math.max(z, bz);
  const x1 = Math.min(x + w, bx + bw);
  const z1 = Math.min(z + d, bz + bd);
  return x1 > x0 && z1 > z0 ? [x0, z0, x1 - x0, z1 - z0] : null;
}

/** What's left of `a` once `b` is cut out of it: up to four rectangles. */
function cutOut(a: PlanRect, b: PlanRect): PlanRect[] {
  const o = overlap(a, b);
  if (!o) return [a];
  const [x, z, w, d] = a;
  const [ox, oz, ow, od] = o;
  const left: PlanRect[] = [];
  if (ox > x) left.push([x, z, ox - x, d]);
  if (ox + ow < x + w) left.push([ox + ow, z, x + w - ox - ow, d]);
  if (oz > z) left.push([ox, z, ow, oz - z]);
  if (oz + od < z + d) left.push([ox, oz + od, ow, z + d - oz - od]);
  return left;
}

/**
 * The plan's walls to raise for a view. The room shell draws the kitchen's
 * own main wall and, for an L, its side wall (with their windows and
 * doors), so those stretches are cut out of the plan's walls; the rest of a
 * long wall, like the house's outside wall running on past the kitchen,
 * stays. The shell leaves the corner between them open, so the plan fills
 * it. Room shows the kitchen's own room, its walls a wall's thickness
 * round; House shows every wall.
 */
export function wallsFor(plan: FloorPlan, view: RoomView, mainMm: number, returnMm: number): WallBox[] {
  if (view === 'kitchen') return [];
  const t = plan.wallThicknessMm;
  const [kx, kz, kw, kd] = plan.kitchenMm;
  // Generous across the thickness: the plan's walls are measured to the pixel.
  const own: PlanRect[] = [[0, -t * 1.6, mainMm, t * 2.2]];
  if (returnMm > 0) own.push([-t * 1.6, 0, t * 2.2, returnMm]);
  const room: PlanRect = [kx - t * 2, kz - t * 2, kw + t * 4, kd + t * 4];

  return plan.walls
    .filter(([, , w, d]) => w > 0 && d > 0)
    .flatMap((r) => own.reduce<PlanRect[]>((pieces, o) => pieces.flatMap((p) => cutOut(p, o)), [r]))
    .flatMap((p) => {
      const shown = view === 'house' ? p : overlap(p, room);
      return shown ? [shown] : [];
    })
    .filter(([, , w, d]) => w >= 30 && d >= 30) // slivers left by the cutting
    .map(([x, z, w, d]) => ({ x: (x + w / 2) / 1000, z: (z + d / 2) / 1000, width: w / 1000, depth: d / 1000 }));
}

/** What a view has to fit on screen, in metres: [minX, minZ, maxX, maxZ]. */
export function viewExtent(plan: FloorPlan, view: RoomView): [number, number, number, number] | null {
  if (view === 'kitchen') return null;
  if (view === 'room') {
    const [x, z, w, d] = plan.kitchenMm;
    const m = 1500;
    return [(x - m) / 1000, (z - m) / 1000, (x + w + m) / 1000, (z + d + m) / 1000];
  }
  const turned = Math.abs(plan.imageRotationDeg % 180) === 90;
  const [iw, ih] = plan.imageSizeMm;
  const w = turned ? ih : iw;
  const d = turned ? iw : ih;
  const [cx, cz] = plan.imageCenterMm;
  return [(cx - w / 2) / 1000, (cz - d / 2) / 1000, (cx + w / 2) / 1000, (cz + d / 2) / 1000];
}
