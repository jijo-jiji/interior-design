/* ─────────────────────────────────────────────────────────────────────────────
   Commercial pricing.

   The same rules as the office server (backend/catalog.py) and the sales app
   (lib/features/viewer/models/cpq_engine.dart), reading the same catalogue
   (GET /api/catalog), so the figure in the studio, on the tablet and on the
   PDF the client signs is one figure. test/fixtures/pricing_cases.json holds
   the cases all three must agree on.

   unit price = module price                     if the type is a fixed module
              = at_ref + (width - ref_width) / 100 * per_100mm   if its family has a rule
              = unknown_module_price             otherwise
   then x the finish multiplier, rounded to the sen.
   ──────────────────────────────────────────────────────────────────────────── */

export interface StyleOption {
  name: string;
  multiplier: number;
}

export interface BenchtopOption {
  name: string;
  rate_per_m: number;
}

export interface CatalogModule {
  type: string;
  label: string;
  section: 'cabinet' | 'appliance';
  width_mm: number;
  height_mm: number;
  depth_mm: number;
  mount_mm: number;
  price: number;
}

export interface PriceRule {
  at_ref: number;
  ref_width_mm: number;
  per_100mm: number;
}

export interface Family {
  id: string;
  label: string;
  prefixes: string[];
  group: 'base' | 'wall' | 'tall' | 'corner';
  /** How the 3D view draws it. */
  kind:
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
  benchtop: 'width' | 'fixed' | 'none';
  benchtop_m: number;
  labour: boolean;
  appliance: boolean;
  price: PriceRule | null;
}

export interface LayoutRules {
  min_sink_to_hob_mm: number;
  min_hob_side_counter_mm: number;
  min_sink_to_tall_mm: number;
  min_filler_mm: number;
  max_filler_mm: number;
  scribe_tolerance_mm: number;
  door_clearance_mm: number;
  window_clearance_mm: number;
  max_sink_shift_from_window_mm: number;
}

export interface Layout {
  base_door_widths_mm: number[];
  drawer_widths_mm: number[];
  sink_widths_mm: number[];
  hob_widths_mm: number[];
  tall_width_mm: number;
  wall_widths_mm: number[];
  corner_size_mm: number;
  base_height_mm: number;
  base_depth_mm: number;
  counter_height_mm: number;
  wall_height_mm: number;
  wall_depth_mm: number;
  wall_mount_mm: number;
  tall_height_mm: number;
  tall_depth_mm: number;
  rules: LayoutRules;
}

/** The catalogue document, as the office server stores it. */
export interface Catalog {
  schema_version: 1;
  version: number;
  updated_at?: string | null;
  name: string;
  /** True while the numbers are samples. */
  is_placeholder: boolean;
  currency: string;
  currency_symbol: string;
  tax: { label: string; rate: number };
  labour_rate_per_cabinet: number;
  unknown_module_price: number;
  obstacle_allowances: Record<string, number>;
  style_options: Record<string, StyleOption>;
  benchtop_options: Record<string, BenchtopOption>;
  modules: CatalogModule[];
  families: Family[];
  layout: Layout;
}

/** Keys the server adds to its answer (flat maps for older clients, and
 *  whether saving needs the admin key): never sent back when saving. */
export const SERVER_ONLY_KEYS = [
  'cabinets',
  'styles',
  'style_names',
  'benchtops',
  'benchtop_names',
  'gst_rate',
  'requires_admin_key',
] as const;

export interface ServedCatalog extends Catalog {
  requires_admin_key?: boolean;
}

/** The longest-prefix family of a module type, if any. */
export function familyFor(catalog: Catalog, type: string): Family | undefined {
  let best: Family | undefined;
  let bestLength = -1;
  for (const family of catalog.families) {
    for (const prefix of family.prefixes) {
      if (type.startsWith(prefix) && prefix.length > bestLength) {
        best = family;
        bestLength = prefix.length;
      }
    }
  }
  return best;
}

/** The list price of one module, before the finish multiplier. */
export function unitPrice(catalog: Catalog, type: string, widthMm?: number): number {
  const fixed = catalog.modules.find((m) => m.type === type);
  if (fixed) return fixed.price;
  const rule = familyFor(catalog, type)?.price;
  if (rule) {
    const width = widthMm ? widthMm : rule.ref_width_mm;
    return Math.max(0, rule.at_ref + ((width - rule.ref_width_mm) / 100) * rule.per_100mm);
  }
  return catalog.unknown_module_price;
}

export function benchtopMetresFor(catalog: Catalog, type: string, widthMm?: number): number {
  const family = familyFor(catalog, type);
  if (!family || family.benchtop === 'none') return 0;
  if (family.benchtop === 'fixed') return family.benchtop_m;
  const width = widthMm ? widthMm : (family.price?.ref_width_mm ?? 600);
  return width / 1000;
}

/** Style options as the flat maps the panels read. */
export const styleNames = (c: Catalog) =>
  Object.fromEntries(Object.entries(c.style_options).map(([k, v]) => [k, v.name]));
export const styleMultipliers = (c: Catalog) =>
  Object.fromEntries(Object.entries(c.style_options).map(([k, v]) => [k, v.multiplier]));
export const benchtopRates = (c: Catalog) =>
  Object.fromEntries(Object.entries(c.benchtop_options).map(([k, v]) => [k, v.rate_per_m]));
export const benchtopNames = (c: Catalog) =>
  Object.fromEntries(Object.entries(c.benchtop_options).map(([k, v]) => [k, v.name]));

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
  /** Width in metres. */
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

const mmOf = (cab: PricedCabinet): number | undefined =>
  cab.width === undefined ? undefined : Math.round(cab.width * 1000);

/** Benchtop over base units (their own width), corners (both wings), and
 *  whatever else the catalogue says carries a worktop. */
export function benchtopLinearMetres(cabinets: PricedCabinet[], catalog: Catalog): number {
  let metres = 0;
  for (const cab of cabinets) metres += benchtopMetresFor(catalog, cab.type, mmOf(cab));
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
  const option = catalog.style_options[style];
  const multiplier = option?.multiplier ?? 1.0;
  const styleLabel = option?.name ?? 'Japandi Natural';

  // One line per type and width, in first-seen order; each unit price is
  // rounded to the sen before it is multiplied (as the server does).
  const groups = new Map<string, { type: string; widthMm?: number; qty: number }>();
  for (const cab of cabinets) {
    const widthMm = mmOf(cab);
    const key = `${cab.type}|${widthMm ?? 0}`;
    const seen = groups.get(key);
    if (seen) seen.qty += 1;
    else groups.set(key, { type: cab.type, widthMm, qty: 1 });
  }

  for (const { type, widthMm, qty } of groups.values()) {
    const unit = round2(unitPrice(catalog, type, widthMm) * multiplier);
    const kind = familyFor(catalog, type)?.appliance ? 'Appliance' : 'Cabinet';
    // "Filler Base 75": a type with no size in its name shows its width.
    const name = titleCase(type) + (widthMm && !/\d/.test(type) ? ` ${widthMm}` : '');
    lineItems.push({
      description: `${kind} — ${name} (${styleLabel})`,
      qty,
      unit_price: unit,
      total: round2(unit * qty),
    });
  }

  const labourCount = cabinets.filter((c) => familyFor(catalog, c.type)?.labour ?? true).length;
  if (labourCount > 0) {
    lineItems.push({
      description: 'Installation Labour',
      qty: labourCount,
      unit_price: catalog.labour_rate_per_cabinet,
      total: round2(catalog.labour_rate_per_cabinet * labourCount),
    });
  }

  // Benchtop, priced per linear metre of run and without the style multiplier.
  const benchtop = benchtopMaterial ? catalog.benchtop_options[benchtopMaterial] : undefined;
  const metres = benchtopLinearMetres(cabinets, catalog);
  if (benchtop && benchtop.rate_per_m > 0 && metres > 0) {
    const benchtopTotal = round2(benchtop.rate_per_m * metres);
    lineItems.push({
      description: `Benchtop — ${benchtop.name} (${metres.toFixed(2)} lm @ ${catalog.currency_symbol}${benchtop.rate_per_m.toFixed(0)}/m)`,
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

  const subtotal = Math.max(0, round2(lineItems.reduce((sum, li) => sum + li.total, 0)));
  const gst = round2(subtotal * catalog.tax.rate);

  return { lineItems, subtotal, gst, total: round2(subtotal + gst) };
}

/** Malaysian ringgit, e.g. RM1,234.00. */
export const formatMyr = (value: number) =>
  value.toLocaleString('en-MY', { style: 'currency', currency: 'MYR' });
