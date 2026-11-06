import { describe, expect, it } from 'vitest';
import { readFloorPlan, viewExtent, wallsFor } from './floorPlan.ts';

// As the sales app sends it: a 3000 × 2400 kitchen in its corner, the plan
// 10 × 7 m around it, and three walls: the kitchen's main wall (already
// drawn by the room shell), one beside the kitchen, one across the house.
const RAW = {
  image: '/api/projects/QT-1/plan.png',
  image_center_mm: [4000, 2500],
  image_size_mm: [10000, 7000],
  image_rotation_deg: 0,
  kitchen_mm: [0, 0, 3000, 2400],
  wall_thickness_mm: 150,
  walls: [
    [-150, -150, 3300, 150], // the kitchen's main wall
    [3000, 0, 150, 2400], // the kitchen's far side wall
    [-6000, 4000, 4000, 150], // across the house
  ],
  rooms: [{ name: 'DAPUR', rect_mm: [0, 0, 3000, 2400] }],
};

describe('readFloorPlan', () => {
  it('reads what the sales app stores', () => {
    const plan = readFloorPlan(RAW)!;
    expect(plan.image).toBe('/api/projects/QT-1/plan.png');
    expect(plan.kitchenMm).toEqual([0, 0, 3000, 2400]);
    expect(plan.walls).toHaveLength(3);
    expect(plan.rooms[0].name).toBe('DAPUR');
  });

  it('a project without one, or a broken one, has none', () => {
    expect(readFloorPlan(undefined)).toBeNull();
    expect(readFloorPlan({ kitchen_mm: [0, 0] })).toBeNull();
    const plan = readFloorPlan({ ...RAW, walls: [[1, 2, 3], 'x', [0, 0, 1, 1]] })!;
    expect(plan.walls).toEqual([[0, 0, 1, 1]]);
  });
});

describe('wallsFor', () => {
  const plan = readFloorPlan(RAW)!;

  it('Kitchen shows none of the plan', () => {
    expect(wallsFor(plan, 'kitchen', 3000, 0)).toEqual([]);
  });

  it("Room shows the walls around the kitchen, not the kitchen's own main wall", () => {
    expect(wallsFor(plan, 'room', 3000, 0)).toEqual([
      // What's left of the plan's main wall: its two corners.
      { x: -0.075, z: -0.075, width: 0.15, depth: 0.15 },
      { x: 3.075, z: -0.075, width: 0.15, depth: 0.15 },
      { x: 3.075, z: 1.2, width: 0.15, depth: 2.4 },
    ]);
  });

  it('House shows every wall', () => {
    expect(wallsFor(plan, 'house', 3000, 0)).toHaveLength(4);
  });

  it("a wall running on past the kitchen keeps the parts beyond the kitchen's own walls", () => {
    // The house's outside wall, 10 m long, with the kitchen's main wall in it.
    const long = readFloorPlan({ ...RAW, walls: [[-4000, -150, 10000, 150]] })!;
    expect(wallsFor(long, 'house', 3000, 2400)).toEqual([
      { x: -2, z: -0.075, width: 4, depth: 0.15 },
      { x: 4.5, z: -0.075, width: 3, depth: 0.15 },
    ]);
    // Room keeps only the stretch round the kitchen's own room.
    expect(wallsFor(long, 'room', 3000, 2400)).toEqual([
      { x: -0.15, z: -0.075, width: 0.3, depth: 0.15 },
      { x: 3.15, z: -0.075, width: 0.3, depth: 0.15 },
    ]);
  });
});

describe('viewExtent', () => {
  const plan = readFloorPlan(RAW)!;

  it('Room frames the kitchen and 1.5 m around it', () => {
    expect(viewExtent(plan, 'room')).toEqual([-1.5, -1.5, 4.5, 3.9]);
  });

  it('House frames the whole plan, turned with it', () => {
    expect(viewExtent(plan, 'house')).toEqual([-1, -1, 9, 6]);
    const turned = readFloorPlan({ ...RAW, image_rotation_deg: 90 })!;
    expect(viewExtent(turned, 'house')).toEqual([0.5, -2.5, 7.5, 7.5]);
  });
});
