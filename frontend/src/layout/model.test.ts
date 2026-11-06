import { describe, expect, it } from 'vitest';
import { fromEntry, kindOf, newModule, readingOrder, toEntry } from './model.ts';

const WALL = 3.6; // metres

describe('positions from the sales app', () => {
  it('reads x_mm as the centre measured from the centre of the wall', () => {
    // A 600 mm cabinet whose centre is 1.5 m left of the wall's centre:
    // its left edge is 0.0 m... 0.3 m from the left end of a 3.6 m wall.
    const cab = fromEntry({ id: 'B-01', cabinet_type: 'base_600', x_mm: -1500 }, 0, WALL);
    expect(cab.x).toBeCloseTo(0.0, 6);
    const right = fromEntry({ id: 'B-02', cabinet_type: 'base_800', x_mm: 1400 }, 1, WALL);
    expect(right.x).toBeCloseTo(1.8 + 1.4 - 0.4, 6); // centre 3.2 m → left edge 2.8 m
  });

  it('round-trips through a studio save without moving anything', () => {
    const entries = [
      { id: 'a', cabinet_type: 'base_600', x_mm: -900 },
      { id: 'b', cabinet_type: 'wall_600', x_mm: 300 },
      { id: 'c', cabinet_type: 'base_drawer_450', kind: 'drawer', generated: true, width_mm: 450, height_mm: 850, depth_mm: 600, mount_mm: 0, x_mm: 1275 },
      { id: 'd', cabinet_type: 'base_600', kind: 'base', run: 'return', generated: true, width_mm: 600, height_mm: 850, depth_mm: 600, mount_mm: 0, offset_mm: 1200 },
    ];
    for (const [i, e] of entries.entries()) {
      const saved = toEntry(fromEntry(e, i, WALL), WALL);
      if (e.run === 'return') expect(saved.offset_mm).toBe(e.offset_mm);
      else expect(saved.x_mm).toBe(e.x_mm);
    }
  });

  it('prefers the studio\'s own left edge when the record has one', () => {
    // An earlier studio save wrote the left edge into x_mm too; `x` wins.
    const cab = fromEntry({ id: 'x', type: 'base_600', x: 1.25, x_mm: 1250 }, 0, WALL);
    expect(cab.x).toBe(1.25);
  });

  it('places return-wall cabinets by their distance from the main wall', () => {
    const cab = fromEntry({ id: 'r', cabinet_type: 'base_600', run: 'return', offset_mm: 1200, width_mm: 600 }, 0, WALL);
    expect(cab.run).toBe('return');
    expect(cab.x).toBeCloseTo(0.9, 6); // centre 1.2 m → near edge 0.9 m
  });
});

describe('generated layouts', () => {
  it('knows every kind the generator and the appliance list produce', () => {
    expect(kindOf('base_drawer_600')).toBe('drawer');
    expect(kindOf('base_sink_900')).toBe('sink');
    expect(kindOf('base_hob_600')).toBe('hob');
    expect(kindOf('wall_450')).toBe('wall');
    expect(kindOf('filler_base')).toBe('filler');
    expect(kindOf('cooktop_600')).toBe('hob');
    expect(kindOf('oven_tower_600')).toBe('oven');
    expect(kindOf('fridge_recess_700')).toBe('fridge');
    expect(kindOf('rangehood_900')).toBe('hood');
    expect(kindOf('anything', 'corner')).toBe('corner');
  });

  it('hangs every wall cabinet, not just the 600', () => {
    const cab = fromEntry({ id: 'w', cabinet_type: 'wall_450', width_mm: 450, height_mm: 700, depth_mm: 320 }, 0, WALL);
    expect(cab.isWallMounted).toBe(true);
    expect(cab.mount).toBeCloseTo(1.4, 6);
    expect(cab.label).toBe('Wall 450');
  });

  it('keeps the generator flag and kind when saving', () => {
    const saved = toEntry(
      fromEntry({ id: 'g', cabinet_type: 'base_sink_900', kind: 'sink', generated: true, width_mm: 900, x_mm: 0 }, 0, WALL),
      WALL,
    );
    expect(saved.generated).toBe(true);
    expect(saved.kind).toBe('sink');
    expect(saved.width_mm).toBe(900);
  });
});

describe('studio modules', () => {
  it('a cooktop added in the studio has no hood of its own', () => {
    expect(newModule('cooktop_600', 1).hood).toBe(false);
    expect(newModule('rangehood_900', 1).isWallMounted).toBe(true);
  });

  it('lists floor units left to right, then wall units, then the side wall', () => {
    const cabs = [
      fromEntry({ id: 'r', cabinet_type: 'base_600', run: 'return', offset_mm: 1500 }, 0, WALL),
      fromEntry({ id: 'w', cabinet_type: 'wall_600', x_mm: -1500 }, 1, WALL),
      fromEntry({ id: 'b2', cabinet_type: 'base_600', x_mm: 300 }, 2, WALL),
      fromEntry({ id: 'b1', cabinet_type: 'base_600', x_mm: -1500 }, 3, WALL),
    ];
    expect([...cabs].sort(readingOrder).map((c) => c.id)).toEqual(['b1', 'b2', 'w', 'r']);
  });
});
