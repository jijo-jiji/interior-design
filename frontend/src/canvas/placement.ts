import type { CabinetData } from '../layout/model';
import type { CabinetSpec } from './cabinetBuilder';

export const WORKTOP_KINDS = new Set(['base', 'drawer', 'sink', 'hob', 'corner', 'filler', 'dishwasher']);

export const specOf = (cab: CabinetData): CabinetSpec => ({
  kind: cab.kind,
  w: cab.width,
  h: cab.height,
  d: cab.depth,
  isWall: cab.isWallMounted,
  mount: cab.mount,
  hood: cab.hood,
});

/**
 * Where a cabinet sits in the room. The main wall's face is z = 0, running
 * from x = 0 (left end) to the wall width; the side wall of an L-shape is
 * x = 0, running out along +z. Cabinets on it are turned to face the room.
 */
export function placement(cab: CabinetData): { position: [number, number, number]; rotationY: number } {
  const y = cab.mount + cab.height / 2;
  if (cab.run === 'return') {
    return { position: [cab.depth / 2, y, cab.x + cab.width / 2], rotationY: Math.PI / 2 };
  }
  return { position: [cab.x + cab.width / 2, y, cab.depth / 2], rotationY: 0 };
}

