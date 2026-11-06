import type { Catalog, CatalogModule, Family, ServedCatalog } from './pricing.ts';
import { SERVER_ONLY_KEYS, rulePrice } from './pricing.ts';

/* ─────────────────────────────────────────────────────────────────────────────
   The price-list editor's logic, kept apart from the screen so it can be
   tested without a browser: editing a copy, what is sent to the office, what
   comes back, and how a refusal is put in words the designer can act on.
   ──────────────────────────────────────────────────────────────────────────── */

/** A copy of [catalog] with [edit] applied; the original is never touched. */
export function withEdit(catalog: Catalog, edit: (draft: Catalog) => void): Catalog {
  const draft = structuredClone(catalog);
  edit(draft);
  return draft;
}

/** The catalogue without what the server adds to its answer or stamps on save. */
function canonical(catalog: Catalog): Record<string, unknown> {
  const doc: Record<string, unknown> = { ...catalog };
  for (const key of SERVER_ONLY_KEYS) delete doc[key];
  delete doc.updated_at;
  return doc;
}

/** Whether two catalogues hold the same prices and rules. */
export function sameCatalog(a: Catalog, b: Catalog): boolean {
  return JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
}

/** The body of `PUT /api/catalog`: the whole catalogue and the version the
 *  edit started from, so the office can tell if someone saved in between. */
export function toSavePayload(catalog: Catalog, baseVersion: number): Record<string, unknown> {
  return { ...canonical(catalog), base_version: baseVersion };
}

// ─── Typed numbers ───────────────────────────────────────────────────────────

/** A number typed by hand ("1,250.50", " 40 ", "RM 340"); null if there isn't one. */
export function parseNumber(text: string): number | null {
  const cleaned = text.replace(/[,\sA-Za-z]/g, '');
  if (cleaned === '' || cleaned === '-' || cleaned === '.') return null;
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : null;
}

/** "300, 400 450" → [300, 400, 450]; null if nothing usable (or a bad entry). */
export function parseWidthList(text: string): number[] | null {
  const parts = text.split(/[,;\s]+/).filter(Boolean);
  if (parts.length === 0) return null;
  const out: number[] = [];
  for (const part of parts) {
    const n = Number(part);
    if (!Number.isFinite(n) || n <= 0) return null;
    out.push(n);
  }
  return out;
}

export const formatWidthList = (widths: number[]) => widths.join(', ');

// ─── Adding a module ─────────────────────────────────────────────────────────

/** Families a salesperson can add by width: priced by rule, with a prefix such
 *  as `wall_` that a width can follow (`wall_450`). Appliances and the trim
 *  pieces the generator makes are not. */
export function addableFamilies(catalog: Catalog): Family[] {
  return catalog.families.filter(
    (f) => !f.appliance && f.price !== null && f.kind !== 'filler' && f.prefixes[0]?.endsWith('_'),
  );
}

/** The type id a new module gets: the family's prefix and its width. */
export const moduleTypeFor = (family: Family, widthMm: number) => `${family.prefixes[0]}${widthMm}`;

const sentenceCase = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** "base_drawer_" + 450 → "Base drawer 450". */
export function moduleLabelFor(family: Family, widthMm: number): string {
  return sentenceCase(`${family.prefixes[0].replace(/_+$/, '').replace(/_/g, ' ')} ${widthMm}`);
}

/** A new module of [family] and [widthMm]: sized like the catalogue's other
 *  modules of its kind, and priced as the family's rule says. */
export function newCatalogModule(catalog: Catalog, family: Family, widthMm: number): CatalogModule {
  const l = catalog.layout;
  const sizes =
    family.group === 'wall'
      ? { height_mm: l.wall_height_mm, depth_mm: l.wall_depth_mm, mount_mm: l.wall_mount_mm }
      : family.group === 'tall'
        ? { height_mm: l.tall_height_mm, depth_mm: l.tall_depth_mm, mount_mm: 0 }
        : { height_mm: l.base_height_mm, depth_mm: family.group === 'corner' ? widthMm : l.base_depth_mm, mount_mm: 0 };
  return {
    type: moduleTypeFor(family, widthMm),
    label: moduleLabelFor(family, widthMm),
    section: 'cabinet',
    width_mm: widthMm,
    ...sizes,
    price: family.price ? Math.round(rulePrice(family.price, widthMm)) : 0,
  };
}

/** Why a module of [family] and [widthMm] can't be added, or null if it can. */
export function whyNotAddable(catalog: Catalog, family: Family, widthMm: number | null): string | null {
  if (widthMm === null || !Number.isInteger(widthMm) || widthMm < 100 || widthMm > 3000) {
    return 'Enter a width between 100 and 3000 mm.';
  }
  const type = moduleTypeFor(family, widthMm);
  if (catalog.modules.some((m) => m.type === type)) return `${type} is already in the list.`;
  return null;
}

/** "Calacatta Quartz" → "calacatta_quartz": the id a new benchtop gets. */
export const slug = (name: string) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');

// ─── Saving ──────────────────────────────────────────────────────────────────

export interface Problem {
  where: string;
  message: string;
}

export type SaveOutcome =
  | { kind: 'saved'; catalog: Catalog }
  /** Someone else saved a newer version while this one was being edited. */
  | { kind: 'conflict'; message: string }
  /** The office refused some values; each problem says where. */
  | { kind: 'invalid'; problems: Problem[] }
  /** Saving needs the office key, and it was missing or wrong. */
  | { kind: 'locked' }
  | { kind: 'failed'; message: string };

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

/** Loads the current catalogue (or an earlier [version]) from the office. */
export async function loadCatalog(version?: number, fetchImpl: Fetch = fetch): Promise<ServedCatalog> {
  const res = await fetchImpl(version === undefined ? '/api/catalog' : `/api/catalog?version=${version}`);
  if (!res.ok) throw new Error(`The office answered ${res.status}.`);
  return (await res.json()) as ServedCatalog;
}

export interface VersionInfo {
  version: number;
  updated_at: string | null;
  name: string;
  is_placeholder: boolean;
}

export async function loadVersions(fetchImpl: Fetch = fetch): Promise<VersionInfo[]> {
  const res = await fetchImpl('/api/catalog/versions');
  if (!res.ok) throw new Error(`The office answered ${res.status}.`);
  return ((await res.json()) as { versions: VersionInfo[] }).versions;
}

/** Saves [catalog] as the next version. [baseVersion] is the one it started from. */
export async function saveCatalog(
  catalog: Catalog,
  baseVersion: number,
  adminKey: string,
  fetchImpl: Fetch = fetch,
): Promise<SaveOutcome> {
  let res: Response;
  try {
    res = await fetchImpl('/api/catalog', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...(adminKey ? { 'X-Admin-Key': adminKey } : {}) },
      body: JSON.stringify(toSavePayload(catalog, baseVersion)),
    });
  } catch {
    return { kind: 'failed', message: "Can't reach the office server. Nothing was saved." };
  }

  if (res.ok) {
    const body = (await res.json()) as { catalog: Catalog };
    return { kind: 'saved', catalog: body.catalog };
  }
  let detail: unknown;
  try {
    detail = ((await res.json()) as { detail?: unknown }).detail;
  } catch {
    detail = undefined; // not JSON (a proxy error page, say)
  }
  if (res.status === 409) {
    return {
      kind: 'conflict',
      message: typeof detail === 'string' ? detail : 'Someone else saved a newer price list while you were editing.',
    };
  }
  if (res.status === 401) return { kind: 'locked' };
  if (res.status === 422 && Array.isArray(detail)) {
    return { kind: 'invalid', problems: detail as Problem[] };
  }
  return { kind: 'failed', message: `The office refused the price list (${res.status}). Nothing was saved.` };
}

// ─── Words for a refusal ─────────────────────────────────────────────────────

const FIELD_WORDS: Record<string, string> = {
  rate_per_m: 'rate per metre',
  at_ref: 'price at the reference width',
  per_100mm: 'price per 100 mm',
  ref_width_mm: 'reference width',
  labour_rate_per_cabinet: 'installation per module',
  unknown_module_price: 'price for an unlisted module',
};

const plainField = (field: string) =>
  FIELD_WORDS[field] ?? field.replace(/_mm$/, ' (mm)').replace(/_/g, ' ');

/** "modules.2.price" → "Base 600 · price", so the designer knows which cell. */
export function describeProblem(problem: Problem, catalog: Catalog): string {
  const path = problem.where.split('.').filter(Boolean);
  const [head, key, ...rest] = path;
  let place = problem.where || 'The price list';
  if (head === 'modules' && key !== undefined) {
    const m = catalog.modules[Number(key)];
    place = [m ? `Module “${m.label}”` : 'A module', ...rest.map(plainField)].join(' · ');
  } else if (head === 'families' && key !== undefined) {
    const f = catalog.families[Number(key)];
    place = [f ? `Price by width “${f.label}”` : 'A price rule', ...rest.filter((p) => p !== 'price').map(plainField)].join(' · ');
  } else if (head === 'style_options' && key !== undefined) {
    place = [`Finish “${catalog.style_options[key]?.name ?? key}”`, ...rest.map(plainField)].join(' · ');
  } else if (head === 'benchtop_options' && key !== undefined) {
    place = [`Benchtop “${catalog.benchtop_options[key]?.name ?? key}”`, ...rest.map(plainField)].join(' · ');
  } else if (head === 'layout') {
    place = ['Layout', ...path.slice(1).filter((p) => p !== 'rules').map(plainField)].join(' · ');
  } else if (head === 'tax') {
    place = ['Tax', ...path.slice(1).map(plainField)].join(' · ');
  } else if (path.length > 0) {
    place = path.map(plainField).join(' · ');
  }
  return `${place}: ${problem.message}`;
}
