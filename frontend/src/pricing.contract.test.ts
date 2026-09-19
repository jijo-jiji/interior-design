import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Explicit extension: this spec is typechecked under the nodenext project.
import { FALLBACK_CATALOG, benchtopLinearMetres, priceLayout } from './pricing.ts';

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
    const metres = benchtopLinearMetres([
      { type: 'base_800', width: 0.8 },
      { type: 'wall_600', width: 0.6 },
      { type: 'tall_600', width: 0.6 },
      { type: 'corner_900', width: 0.9 },
    ]);

    expect(metres).toBeCloseTo(2.6, 3);
  });
});

describe('fallback catalog', () => {
  it('mirrors the backend defaults the contract was built from', () => {
    expect(FALLBACK_CATALOG.cabinets.base_800).toBe(420);
    expect(FALLBACK_CATALOG.labour_rate_per_cabinet).toBe(120);
    expect(FALLBACK_CATALOG.benchtops.quartz_calacatta).toBe(380);
    // Malaysian SST. The field keeps its `gst` name for the stored records.
    expect(FALLBACK_CATALOG.gst_rate).toBe(0.08);
  });
});
