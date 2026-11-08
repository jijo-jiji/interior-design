import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { BENCHTOP_LOOKS, STYLE_FINISHES } from './finishes.ts';
import type { CabinetFinish } from './finishes.ts';

const root = (path: string) => fileURLToPath(new URL(`../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(root(path), 'utf8');

interface Entry { albedo: string; normal?: string; roughness?: string; tile_m: number; kind: string }
const manifest = JSON.parse(read('assets/3d/textures/manifest.json')) as {
  textures: Record<string, Entry>;
  micro?: { normal: string; roughness?: string };
};
// The sales app's 3D page: the Studio draws the same finishes, so its table
// must match the page's.
const page = read('assets/3d/index.html');

/** `tex: 'id'` of a part ("base", "wall", "tall", "top") of a style in the page. */
function pageTex(style: string, part: string): string | undefined {
  const from = page.indexOf('const STYLE_FINISHES');
  const block = page.slice(page.indexOf(`  ${style}: {`, from));
  const line = block.slice(0, block.indexOf('\n  },')).split('\n').find((l) => l.trim().startsWith(`${part}:`));
  return line?.match(/tex:\s*'([^']+)'/)?.[1];
}

describe('the finish textures of the 3D view', () => {
  it('has every file the manifest names, in the sales app folder the Studio builds from', () => {
    const named = Object.values(manifest.textures).flatMap((t) => [t.albedo, t.normal, t.roughness]).filter(Boolean) as string[];
    if (manifest.micro) named.push(manifest.micro.normal, ...(manifest.micro.roughness ? [manifest.micro.roughness] : []));
    expect(named.length).toBeGreaterThan(20);
    for (const file of named) expect(existsSync(root(`assets/3d/textures/${file}`)), file).toBe(true);
  });

  it('gives every style a texture set the manifest has (or paint)', () => {
    for (const [name, fin] of Object.entries(STYLE_FINISHES)) {
      for (const part of ['base', 'wall', 'tall', 'top'] as const) {
        const tex = fin[part].tex;
        if (tex) expect(manifest.textures[tex], `${name}.${part} → ${tex}`).toBeDefined();
      }
    }
  });

  it('uses the same texture for each part of each style as the sales app', () => {
    for (const style of Object.keys(STYLE_FINISHES) as CabinetFinish[]) {
      for (const part of ['base', 'wall', 'tall', 'top'] as const) {
        expect(STYLE_FINISHES[style][part].tex, `${style}.${part}`).toBe(pageTex(style, part));
      }
    }
  });

  it('offers the same benchtop looks as the sales app, all of them real benchtops', () => {
    const pageKeys = [...page.matchAll(/^\s{2}(\w+): \{ tex: (?:'[^']+'|null), color/gm)].map((m) => m[1]);
    expect(Object.keys(BENCHTOP_LOOKS).sort()).toEqual(pageKeys.sort());
    const catalog = JSON.parse(read('assets/catalog/default_catalog.json')) as { benchtop_options: Record<string, unknown> };
    for (const [key, look] of Object.entries(BENCHTOP_LOOKS)) {
      expect(Object.keys(catalog.benchtop_options), key).toContain(key);
      if (look.tex) expect(manifest.textures[look.tex], key).toBeDefined();
      const pageLook = page.match(new RegExp(`${key}: \\{ tex: (?:'([^']+)'|null), color: (0x[0-9a-f]+), roughness: ([0-9.]+)`));
      expect(pageLook?.[1], key).toBe(look.tex ?? undefined);
      expect(Number(pageLook?.[2]), key).toBe(look.color);
      expect(Number(pageLook?.[3]), key).toBe(look.roughness);
    }
  });

  it('keeps one grain scale per kind, so every cabinet matches', () => {
    for (const kind of ['wood', 'stone']) {
      const sizes = new Set(Object.values(manifest.textures).filter((t) => t.kind === kind).map((t) => t.tile_m));
      expect([...sizes], kind).toHaveLength(1);
    }
  });
});
