/* ─────────────────────────────────────────────────────────────────────────────
   Commercial pricing.

   The studio used to price layouts with its own hard-coded table (plus an
   invented benchtop line and a door-style multiplier, minus installation
   labour), so the figure on screen disagreed with the quote the client signed.
   Everything here mirrors `create_quote` in backend/main.py and takes its rates
   from GET /api/catalog, so the studio and the PDF agree.
   ──────────────────────────────────────────────────────────────────────────── */

export interface Catalog {
  cabinets: Record<string, number>;
  styles: Record<string, number>;
  style_names: Record<string, string>;
  labour_rate_per_cabinet: number;
  gst_rate: number;
  obstacle_allowances: Record<string, number>;
  benchtops: Record<string, number>;
  benchtop_names: Record<string, string>;
}

/** A corner unit carries benchtop along both wings (900mm each). */
const CORNER_BENCHTOP_METRES = 1.8;

/** Which modules carry benchtop over them. Mirrored in backend/main.py and
 *  lib/features/viewer/models/cpq_engine.dart — drift fails the contract test. */
const BENCHTOP_TYPE_PREFIXES = ['base', 'corner', 'sink', 'cooktop', 'dishwasher'];

/** Appliance modules are described as such on the quote, not as "Cabinet —". */
const APPLIANCE_TYPE_PREFIXES = ['sink', 'cooktop', 'dishwasher', 'oven', 'fridge', 'rangehood'];

/** Used only until /api/catalog answers (or if the backend is unreachable). */
export const FALLBACK_CATALOG: Catalog = {
  cabinets: {
    base_800: 420,
    base_600: 340,
    wall_600: 280,
    tall_600: 620,
    corner_900: 580,
    // Appliance modules: cabinetry, cutouts and services for each unit.
    sink_600: 480,
    cooktop_600: 520,
    dishwasher_600: 360,
    oven_tower_600: 1450,
    fridge_recess_700: 390,
    rangehood_900: 690,
  },
  styles: { japandi: 1.0, minimalist: 1.08, nordic: 1.12, industrial: 1.18 },
  style_names: {
    japandi: 'Japandi Natural',
    minimalist: 'Modern Minimalist',
    nordic: 'Warm Nordic',
    industrial: 'Industrial Luxe',
  },
  labour_rate_per_cabinet: 120,
  gst_rate: 0.08,
  obstacle_allowances: { window: -50, door: -80 },
  benchtops: { quartz_calacatta: 380, granite_black: 480, laminate_matte: 160 },
  benchtop_names: {
    quartz_calacatta: 'Calacatta Engineered Quartz',
    granite_black: 'Nero Absolute Granite',
    laminate_matte: 'Ultra-Matte Mineral Laminate',
  },
};

/** Backend fallback for a cabinet type that is not in the catalog. */
const UNKNOWN_CABINET_PRICE = 300;

export interface QuoteLine {
  description: string;
  qty: number;
  unit_price: number;
  total: number;
}

export interface QuoteTotals {
  lineItems: QuoteLine[];
  subtotal: number;
  gst: number;
  total: number;
}

export interface PricedCabinet {
  type: string;
  /** Width in metres — only needed to measure the benchtop run. */
  width?: number;
}

export interface PricedObstacle {
  type: string;
}

const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

const titleCase = (s: string) =>
  s
    .replace(/_/g, ' ')
    .split(' ')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(' ');

/** Benchtop runs over base units (their own width) and corners (both wings). */
export function benchtopLinearMetres(cabinets: PricedCabinet[]): number {
  let metres = 0;
  for (const cab of cabinets) {
    if (cab.type.startsWith('corner')) {
      metres += CORNER_BENCHTOP_METRES;
    } else if (BENCHTOP_TYPE_PREFIXES.some((prefix) => cab.type.startsWith(prefix))) {
      metres += cab.width ?? 0;
    }
  }
  return Math.round(metres * 1000) / 1000;
}

export function priceLayout(
  cabinets: PricedCabinet[],
  obstacles: PricedObstacle[],
  style: string,
  catalog: Catalog,
  benchtopMaterial?: string | null,
): QuoteTotals {
  const lineItems: QuoteLine[] = [];
  const multiplier = catalog.styles[style] ?? 1.0;
  const styleLabel = catalog.style_names[style] ?? 'Japandi Natural';

  // One line per cabinet type, in first-seen order (matches Counter semantics).
  const counts = new Map<string, number>();
  for (const cab of cabinets) {
    counts.set(cab.type, (counts.get(cab.type) ?? 0) + 1);
  }

  for (const [type, qty] of counts) {
    const unit = round2((catalog.cabinets[type] ?? UNKNOWN_CABINET_PRICE) * multiplier);
    const kind = APPLIANCE_TYPE_PREFIXES.some((p) => type.startsWith(p))
      ? 'Appliance'
      : 'Cabinet';
    lineItems.push({
      description: `${kind} — ${titleCase(type)} (${styleLabel})`,
      qty,
      unit_price: unit,
      total: round2(unit * qty),
    });
  }

  if (cabinets.length > 0) {
    lineItems.push({
      description: 'Installation Labour',
      qty: cabinets.length,
      unit_price: catalog.labour_rate_per_cabinet,
      total: round2(catalog.labour_rate_per_cabinet * cabinets.length),
    });
  }

  // Benchtop, priced per linear metre of run and without the style multiplier.
  const benchtopRate = benchtopMaterial ? catalog.benchtops[benchtopMaterial] : undefined;
  const metres = benchtopLinearMetres(cabinets);
  if (benchtopRate && metres > 0) {
    const benchtopTotal = round2(benchtopRate * metres);
    const label = catalog.benchtop_names[benchtopMaterial!] ?? 'Benchtop';
    lineItems.push({
      description: `Benchtop — ${label} (${metres.toFixed(2)} lm @ RM${benchtopRate.toFixed(0)}/m)`,
      qty: 1,
      unit_price: benchtopTotal,
      total: benchtopTotal,
    });
  }

  for (const obstacle of obstacles) {
    const allowance = catalog.obstacle_allowances[obstacle.type] ?? 0;
    if (allowance !== 0) {
      lineItems.push({
        description: `${titleCase(obstacle.type)} cutout allowance`,
        qty: 1,
        unit_price: allowance,
        total: allowance,
      });
    }
  }

  const subtotal = round2(lineItems.reduce((sum, li) => sum + li.total, 0));
  const gst = round2(subtotal * catalog.gst_rate);

  return { lineItems, subtotal, gst, total: round2(subtotal + gst) };
}

/** Malaysian ringgit, e.g. RM1,234.00. */
export const formatMyr = (value: number) =>
  value.toLocaleString('en-MY', { style: 'currency', currency: 'MYR' });
