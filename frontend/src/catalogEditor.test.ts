import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import {
  addableFamilies,
  describeProblem,
  formatWidthList,
  loadCatalog,
  moduleTypeFor,
  newCatalogModule,
  parseNumber,
  parseWidthList,
  sameCatalog,
  saveCatalog,
  slug,
  toSavePayload,
  whyNotAddable,
  withEdit,
} from './catalogEditor.ts';
import type { Catalog, ServedCatalog } from './pricing.ts';
import { unitPrice } from './pricing.ts';

const SAMPLE = JSON.parse(
  readFileSync(new URL('../../assets/catalog/default_catalog.json', import.meta.url), 'utf-8'),
) as Catalog;

/** What GET /api/catalog sends: the catalogue plus the flat maps for older clients. */
const served = (): ServedCatalog =>
  ({
    ...structuredClone(SAMPLE),
    updated_at: '2026-01-01T00:00:00Z',
    cabinets: { base_800: 420 },
    styles: { japandi: 1 },
    style_names: { japandi: 'Japandi Natural' },
    benchtops: {},
    benchtop_names: {},
    gst_rate: 0.08,
    requires_admin_key: false,
  }) as unknown as ServedCatalog;

const reply = (status: number, body: unknown) => async () =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

describe('editing a copy', () => {
  it('never changes the catalogue it started from', () => {
    const edited = withEdit(SAMPLE, (d) => {
      d.modules[0].price = 999;
      d.labour_rate_per_cabinet = 1;
    });
    expect(edited.modules[0].price).toBe(999);
    expect(SAMPLE.modules[0].price).toBe(420);
    expect(SAMPLE.labour_rate_per_cabinet).toBe(120);
  });

  it('tells a changed catalogue from an unchanged one, ignoring what the server adds', () => {
    expect(sameCatalog(served(), SAMPLE)).toBe(true);
    expect(sameCatalog(withEdit(SAMPLE, (d) => (d.tax.rate = 0.06)), SAMPLE)).toBe(false);
    // Edited and put back: not a change.
    const back = withEdit(withEdit(SAMPLE, (d) => (d.modules[1].price = 1)), (d) => (d.modules[1].price = 340));
    expect(sameCatalog(back, SAMPLE)).toBe(true);
  });
});

describe('what is sent to the office', () => {
  it('is the whole catalogue and the version it started from, without the flat maps', () => {
    const payload = toSavePayload(served(), 4);
    expect(payload.base_version).toBe(4);
    expect(payload.modules).toEqual(SAMPLE.modules);
    expect(payload.layout).toEqual(SAMPLE.layout);
    for (const key of ['cabinets', 'styles', 'style_names', 'benchtops', 'benchtop_names', 'gst_rate', 'requires_admin_key']) {
      expect(payload).not.toHaveProperty(key);
    }
  });
});

describe('typed numbers', () => {
  it.each([
    ['420', 420],
    [' 1,250.50 ', 1250.5],
    ['RM 340', 340],
    ['-50', -50],
    ['0.08', 0.08],
  ])('reads %j as %d', (text, n) => expect(parseNumber(text)).toBe(n));

  it.each(['', '  ', '-', '.', 'abc', '1.2.3'])('reads %j as nothing', (text) => expect(parseNumber(text)).toBeNull());

  it('reads a list of widths', () => {
    expect(parseWidthList('300, 400 450;600')).toEqual([300, 400, 450, 600]);
    expect(formatWidthList([300, 400])).toBe('300, 400');
    expect(parseWidthList('')).toBeNull();
    expect(parseWidthList('300, wide')).toBeNull();
    expect(parseWidthList('300, -5')).toBeNull();
    expect(parseWidthList('0')).toBeNull();
  });
});

describe('adding a module', () => {
  const family = (id: string) => SAMPLE.families.find((f) => f.id === id)!;

  it('offers the families priced by width, not appliances or filler trim', () => {
    expect(addableFamilies(SAMPLE).map((f) => f.id)).toEqual([
      'base',
      'drawer',
      'sink_unit',
      'hob_unit',
      'wall',
      'tall',
      'corner',
    ]);
  });

  it('names the type from the family and the width', () => {
    expect(moduleTypeFor(family('wall'), 450)).toBe('wall_450');
    expect(moduleTypeFor(family('drawer'), 900)).toBe('base_drawer_900');
  });

  it.each([
    ['wall', 450, 'wall_450', 'Wall 450', { height_mm: 700, depth_mm: 320, mount_mm: 1400, price: 220 }],
    ['tall', 700, 'tall_700', 'Tall 700', { height_mm: 2100, depth_mm: 600, mount_mm: 0, price: 660 }],
    ['base', 300, 'base_300', 'Base 300', { height_mm: 850, depth_mm: 600, mount_mm: 0, price: 220 }],
    ['drawer', 450, 'base_drawer_450', 'Base drawer 450', { height_mm: 850, depth_mm: 600, mount_mm: 0, price: 280 }],
    ['corner', 1000, 'corner_1000', 'Corner 1000', { height_mm: 850, depth_mm: 1000, mount_mm: 0, price: 620 }],
  ])('sizes and prices a new %s module like the rest of the list', (id, width, type, label, rest) => {
    expect(newCatalogModule(SAMPLE, family(id), width)).toEqual({
      type,
      label,
      section: 'cabinet',
      width_mm: width,
      ...rest,
    });
  });

  it('prices the new module exactly as the family rule would have priced it unlisted', () => {
    const wall450 = newCatalogModule(SAMPLE, family('wall'), 450);
    expect(wall450.price).toBe(unitPrice(SAMPLE, wall450.type, 450));
  });

  it('refuses a width that is nonsense or already in the list', () => {
    expect(whyNotAddable(SAMPLE, family('base'), 450)).toBeNull();
    expect(whyNotAddable(SAMPLE, family('base'), 600)).toMatch(/already in the list/);
    expect(whyNotAddable(SAMPLE, family('base'), null)).toMatch(/between 100 and 3000/);
    expect(whyNotAddable(SAMPLE, family('base'), 12.5)).toMatch(/between 100 and 3000/);
    expect(whyNotAddable(SAMPLE, family('base'), 90)).toMatch(/between 100 and 3000/);
  });

  it('makes an id for a new benchtop from its name', () => {
    expect(slug('Calacatta Quartz')).toBe('calacatta_quartz');
    expect(slug('  Black "Galaxy" granite! ')).toBe('black_galaxy_granite');
    expect(slug('!!!')).toBe('');
  });
});

describe('saving', () => {
  it('sends the key only when there is one, and returns the saved version', async () => {
    const seen: RequestInit[] = [];
    const fetchImpl = async (_url: string, init?: RequestInit) => {
      seen.push(init!);
      return new Response(JSON.stringify({ catalog: { ...SAMPLE, version: 5 } }), { status: 200 });
    };

    const open = await saveCatalog(SAMPLE, 4, '', fetchImpl);
    const locked = await saveCatalog(SAMPLE, 4, 's3cret', fetchImpl);

    expect(open).toEqual({ kind: 'saved', catalog: { ...SAMPLE, version: 5 } });
    expect(locked.kind).toBe('saved');
    expect((seen[0].headers as Record<string, string>)['X-Admin-Key']).toBeUndefined();
    expect((seen[1].headers as Record<string, string>)['X-Admin-Key']).toBe('s3cret');
    expect(seen[0].method).toBe('PUT');
    expect(JSON.parse(seen[0].body as string).base_version).toBe(4);
  });

  it('says so when someone else saved first', async () => {
    const out = await saveCatalog(SAMPLE, 1, '', reply(409, { detail: 'Catalogue is now at version 2.' }));
    expect(out).toEqual({ kind: 'conflict', message: 'Catalogue is now at version 2.' });
  });

  it('lists each value the office refused', async () => {
    const problems = [{ where: 'style_options.japandi.multiplier', message: 'must be greater than 0' }];
    expect(await saveCatalog(SAMPLE, 1, '', reply(422, { detail: problems }))).toEqual({
      kind: 'invalid',
      problems,
    });
  });

  it('asks for the office key on a 401', async () => {
    expect(await saveCatalog(SAMPLE, 1, '', reply(401, { detail: 'nope' }))).toEqual({ kind: 'locked' });
  });

  it('does not pretend to have saved when the office is unreachable or errors', async () => {
    const down = async () => {
      throw new TypeError('Failed to fetch');
    };
    expect((await saveCatalog(SAMPLE, 1, '', down)).kind).toBe('failed');
    const out = await saveCatalog(SAMPLE, 1, '', reply(500, 'boom'));
    expect(out.kind).toBe('failed');
  });

  it('loads the current catalogue, or an earlier version', async () => {
    const urls: string[] = [];
    const fetchImpl = async (url: string) => {
      urls.push(url);
      return new Response(JSON.stringify(SAMPLE), { status: 200 });
    };
    await loadCatalog(undefined, fetchImpl);
    await loadCatalog(3, fetchImpl);
    expect(urls).toEqual(['/api/catalog', '/api/catalog?version=3']);
    await expect(loadCatalog(9, reply(404, {}))).rejects.toThrow(/404/);
  });
});

describe('describing a refusal', () => {
  it.each([
    ['modules.1.price', 'must be 0 or more', 'Module “Base 600” · price: must be 0 or more'],
    ['families.0.price.per_100mm', 'must be 0 or more', 'Price by width “Base unit” · price per 100 mm: must be 0 or more'],
    ['style_options.japandi.multiplier', 'must be greater than 0', 'Finish “Japandi Natural” · multiplier: must be greater than 0'],
    ['benchtop_options.granite_black.rate_per_m', 'must be 0 or more', 'Benchtop “Nero Absolute Granite” · rate per metre: must be 0 or more'],
    ['layout.rules.min_filler_mm', 'is larger than the maximum', 'Layout · min filler (mm): is larger than the maximum'],
    ['tax.rate', 'must be less than 0.5', 'Tax · rate: must be less than 0.5'],
    ['labour_rate_per_cabinet', 'must be 0 or more', 'installation per module: must be 0 or more'],
    ['wall_work.openings.hidden_door.price', 'must be 0 or more', 'Opening “hidden door” · price: must be 0 or more'],
    ['wall_work.finishes.tiles.rate_per_m2', 'must be 0 or more', 'Wall finish “tiles” · rate per square metre: must be 0 or more'],
  ])('%s', (where, message, expected) => {
    expect(describeProblem({ where, message }, SAMPLE)).toBe(expected);
  });
});
