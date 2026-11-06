import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Explicit extension: this spec is typechecked under the nodenext project.
import { benchtopLinearMetres, priceLayout, unitPrice } from './pricing.ts';
import type { Catalog } from './pricing.ts';

/* ─────────────────────────────────────────────────────────────────────────────
   Studio half of the pricing contract.

   Three engines price the same layout: this one, the mobile CPQEngine and the
   backend. The client signs whatever the backend prints, so a studio that
   quotes something else is quoting a number nobody will honour. All three read
   the figures in test/fixtures/pricing_cases.json.
   ──────────────────────────────────────────────────────────────────────────── */

interface PricingCase {
  name: string;
  style_archetype: string;
  benchtop_material: string | null;
  obstacles: { type: string }[];
  placed_cabinets: { cabinet_type: string; width_mm: number }[];
  expected: { subtotal: number; gst: number; total_price: number };
}

// The sample catalogue: the same file the server seeds from and the sales app
// embeds, so all three engines price from one set of numbers.
const FALLBACK_CATALOG = JSON.parse(
  readFileSync(new URL('../../assets/catalog/default_catalog.json', import.meta.url), 'utf-8'),
) as Catalog;

const fixture = JSON.parse(
  readFileSync(new URL('../../test/fixtures/pricing_cases.json', import.meta.url), 'utf-8'),
) as { cases: PricingCase[] };

describe('Pricing contract — studio matches the backend quote', () => {
  it.each(fixture.cases)('$name', (testCase) => {
    const totals = priceLayout(
      // The studio holds widths in metres; the fixture speaks millimetres.
      testCase.placed_cabinets.map((c) => ({
        type: c.cabinet_type,
        width: c.width_mm / 1000,
      })),
      testCase.obstacles,
      testCase.style_archetype,
      FALLBACK_CATALOG,
      testCase.benchtop_material,
    );

    expect(totals.subtotal).toBeCloseTo(testCase.expected.subtotal, 2);
    expect(totals.gst).toBeCloseTo(testCase.expected.gst, 2);
    // A mismatch here means the estimator and the signed PDF disagree.
    expect(totals.total).toBeCloseTo(testCase.expected.total_price, 2);
  });
});

describe('benchtop run measurement', () => {
  it('counts base widths and both wings of a corner, ignoring wall and tall units', () => {
    const metres = benchtopLinearMetres(
      [
        { type: 'base_800', width: 0.8 },
        { type: 'wall_600', width: 0.6 },
        { type: 'tall_600', width: 0.6 },
        { type: 'corner_900', width: 0.9 },
      ],
      FALLBACK_CATALOG,
    );

    expect(metres).toBeCloseTo(2.6, 3);
  });
});

describe('sample catalogue', () => {
  it('holds the figures the contract was built from', () => {
    expect(unitPrice(FALLBACK_CATALOG, 'base_800')).toBe(420);
    expect(FALLBACK_CATALOG.labour_rate_per_cabinet).toBe(120);
    expect(FALLBACK_CATALOG.benchtop_options.quartz_calacatta.rate_per_m).toBe(380);
    // Malaysian SST. The wire field keeps its `gst` name for the stored records.
    expect(FALLBACK_CATALOG.tax).toEqual({ label: 'SST', rate: 0.08 });
    expect(FALLBACK_CATALOG.is_placeholder).toBe(true);
  });
});

describe('unit price (same figures as the server and sales app tests)', () => {
  it.each([
    ['base_800', 800, 420],
    ['base_600', 600, 340],
    ['sink_600', 600, 480],
    ['base_450', 450, 280],
    ['base_drawer_900', 900, 460],
    ['base_sink_800', 800, 560],
    ['base_hob_600', 600, 520],
    ['wall_900', 900, 400],
    ['wall_450', 450, 220],
    ['tall_700', 700, 660],
    ['filler_base', 100, 40],
    ['filler_wall', 75, 30],
    ['island_1200', 1200, 300],
  ])('%s at %i mm costs %d', (type, width, price) => {
    expect(unitPrice(FALLBACK_CATALOG, type, width)).toBeCloseTo(price, 9);
  });

  it('prices a changed catalogue, not a built-in table', () => {
    const edited: Catalog = structuredClone(FALLBACK_CATALOG);
    edited.modules[0].price = 500;
    edited.families.find((f) => f.id === 'base')!.price!.per_100mm = 50;
    expect(unitPrice(edited, 'base_800', 800)).toBe(500);
    expect(unitPrice(edited, 'base_450', 450)).toBeCloseTo(340 - 75, 9);
  });
});
