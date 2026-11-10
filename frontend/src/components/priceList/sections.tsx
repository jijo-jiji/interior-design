import React, { useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import {
  addableFamilies,
  newCatalogModule,
  parseNumber,
  slug,
  whyNotAddable,
} from '../../catalogEditor.ts';
import { formatMyr, rulePrice } from '../../pricing.ts';
import type { Catalog, CatalogModule, Family, Layout, LayoutRules, WallWork } from '../../pricing.ts';
import { ActionButton, SectionLabel } from '../ui';
import { Checkbox, NumberField, Row, TextField, WidthListField } from './fields';

/** What a section gets: the draft, and a way to change it (on a copy). */
export interface SectionProps {
  catalog: Catalog;
  edit: (change: (draft: Catalog) => void) => void;
}

const th = 'px-2 py-2 text-left text-xs font-semibold text-ink-soft';
const td = 'px-2 py-1.5 align-middle';
const table = 'w-full min-w-[44rem] border-collapse text-[13px]';
const card = 'rounded-xl border border-line bg-surface p-4';

const Intro: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <p className="mb-3 max-w-2xl text-[13px] text-ink-soft">{children}</p>
);

// ─── Modules ─────────────────────────────────────────────────────────────────

export const ModulesSection: React.FC<SectionProps> = ({ catalog, edit }) => {
  const addable = addableFamilies(catalog);
  const [familyId, setFamilyId] = useState(addable[0]?.id ?? '');
  const [widthText, setWidthText] = useState('');
  const family: Family | undefined = addable.find((f) => f.id === familyId) ?? addable[0];
  const why = family ? whyNotAddable(catalog, family, parseNumber(widthText)) : 'Nothing can be added.';

  const rows = (section: CatalogModule['section']) =>
    catalog.modules.map((m, index) => ({ m, index })).filter(({ m }) => m.section === section);

  const setField = <K extends keyof CatalogModule>(index: number, key: K, value: CatalogModule[K]) =>
    edit((d) => {
      d.modules[index][key] = value;
    });

  // A plain function, not a component: a component defined here would be a new
  // type on every keystroke and the field being typed in would lose focus.
  const renderTable = (title: string, section: CatalogModule['section'], removable: boolean) => (
    <div className="overflow-x-auto">
      <table className={table}>
        <caption className="pb-1 text-left">
          <SectionLabel>{title}</SectionLabel>
        </caption>
        <thead>
          <tr className="border-b border-line">
            <th scope="col" className={th}>Name</th>
            <th scope="col" className={th}>Code</th>
            <th scope="col" className={`${th} text-right`}>Width</th>
            <th scope="col" className={`${th} text-right`}>Height</th>
            <th scope="col" className={`${th} text-right`}>Depth</th>
            <th scope="col" className={`${th} text-right`}>Hung at</th>
            <th scope="col" className={`${th} text-right`}>Price (RM)</th>
            {removable && <td className={th} />}
          </tr>
        </thead>
        <tbody>
          {rows(section).map(({ m, index }) => (
            <tr key={m.type} className="border-b border-line last:border-b-0">
              <td className={td}>
                <TextField label={`Name of ${m.type}`} value={m.label} onChange={(v) => setField(index, 'label', v)} className="w-40" />
              </td>
              <td className={`${td} font-mono text-xs text-ink-muted`}>{m.type}</td>
              {(['width_mm', 'height_mm', 'depth_mm', 'mount_mm'] as const).map((key) => (
                <td key={key} className={`${td} text-right`}>
                  <NumberField
                    label={`${{ width_mm: 'Width', height_mm: 'Height', depth_mm: 'Depth', mount_mm: 'Height from the floor' }[key]} of ${m.label} (mm)`}
                    value={m[key]}
                    min={key === 'mount_mm' ? 0 : 1}
                    max={5000}
                    className="w-20"
                    onChange={(v) => setField(index, key, v)}
                  />
                </td>
              ))}
              <td className={`${td} text-right`}>
                <NumberField
                  label={`Price of ${m.label} (RM)`}
                  value={m.price}
                  min={0}
                  className="w-24"
                  onChange={(v) => setField(index, 'price', v)}
                />
              </td>
              {removable && (
                <td className={td}>
                  <button
                    type="button"
                    aria-label={`Remove ${m.label}`}
                    title={`Remove ${m.label}`}
                    onClick={() =>
                      edit((d) => {
                        d.modules.splice(index, 1);
                      })
                    }
                    className="flex h-9 w-9 cursor-pointer items-center justify-center rounded-lg text-ink-muted transition-colors hover:bg-danger-tint hover:text-danger"
                  >
                    <Trash2 className="h-4 w-4" aria-hidden />
                  </button>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );

  return (
    <div className="space-y-6">
      <Intro>
        The modules the sales app offers when adding cabinets, with their sizes (mm) and prices before the finish
        multiplier. Anything not listed here is priced by its width under “Price by width”.
      </Intro>

      <div className={card}>
        {renderTable('Cabinets', 'cabinet', true)}
        {family && (
          <form
            className="mt-4 flex flex-wrap items-end gap-3 border-t border-line pt-4"
            onSubmit={(e) => {
              e.preventDefault();
              if (why) return;
              const width = parseNumber(widthText)!;
              edit((d) => {
                const added = newCatalogModule(d, d.families.find((f) => f.id === family.id)!, width);
                // Keep cabinets together, after the last cabinet.
                const lastCabinet = d.modules.map((m) => m.section).lastIndexOf('cabinet');
                d.modules.splice(lastCabinet + 1, 0, added);
              });
              setWidthText('');
            }}
          >
            <label className="text-xs font-medium text-ink-soft">
              Add a cabinet of kind
              <select
                value={family.id}
                onChange={(e) => setFamilyId(e.target.value)}
                className="mt-1 block h-9 rounded-lg border border-line bg-surface px-2 text-[13px] text-ink"
              >
                {addable.map((f) => (
                  <option key={f.id} value={f.id}>
                    {f.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-xs font-medium text-ink-soft">
              Width (mm)
              <input
                type="text"
                inputMode="numeric"
                value={widthText}
                onChange={(e) => setWidthText(e.target.value)}
                className="mt-1 block h-9 w-24 rounded-lg border border-line bg-surface px-2 text-right text-[13px] text-ink"
              />
            </label>
            <ActionButton type="submit" variant="secondary" disabled={why !== null} icon={<Plus className="h-4 w-4" aria-hidden />}>
              Add
            </ActionButton>
            <p className="basis-full text-xs text-ink-muted" aria-live="polite">
              {widthText.trim() === ''
                ? `The code is made from the kind and width, and it is priced like the others of that kind. ${
                    family.group === 'wall' ? 'Wall cabinets are hung at the wall-cabinet height under “Layout”.' : ''
                  }`
                : (why ?? `Adds ${family.prefixes[0]}${parseNumber(widthText)} to the list.`)}
            </p>
          </form>
        )}
      </div>

      <div className={card}>
        {renderTable('Appliances', 'appliance', false)}
        <p className="mt-3 text-xs text-ink-muted">
          These are the cabinetry, cut-outs and services around an appliance; the appliance itself is quoted
          separately. A new kind of appliance needs the 3D view extended first, so only the existing ones are listed.
        </p>
      </div>
    </div>
  );
};

// ─── Price by width ──────────────────────────────────────────────────────────

const WORKTOP_WORDS: Record<Family['benchtop'], string> = {
  width: 'Along its width',
  fixed: 'A set length',
  none: 'None',
};

const previewWidths = (family: Family) => (family.kind === 'filler' ? [50, 100, 150] : [300, 600, 900]);

export const FamiliesSection: React.FC<SectionProps> = ({ catalog, edit }) => {
  const indexed = catalog.families.map((f, index) => ({ f, index }));
  const byRule = indexed.filter(({ f }) => f.price !== null);
  const fixed = indexed.filter(({ f }) => f.price === null);

  return (
    <div className="space-y-6">
      <Intro>
        How a cabinet that is not in the Modules list is priced: a price at a reference width, then so much more (or
        less) for each 100 mm wider (or narrower). The examples show what that works out to.
      </Intro>

      <div className={`${card} overflow-x-auto`}>
        <table className={table}>
          <caption className="pb-1 text-left">
            <SectionLabel>Priced by width</SectionLabel>
          </caption>
          <thead>
            <tr className="border-b border-line">
              <th scope="col" className={th}>Kind</th>
              <th scope="col" className={`${th} text-right`}>Reference width</th>
              <th scope="col" className={`${th} text-right`}>Price there (RM)</th>
              <th scope="col" className={`${th} text-right`}>Each 100 mm more (RM)</th>
              <th scope="col" className={th}>Examples</th>
              <th scope="col" className={th}>Worktop</th>
              <th scope="col" className={th}>Installation</th>
            </tr>
          </thead>
          <tbody>
            {byRule.map(({ f, index }) => (
              <tr key={f.id} className="border-b border-line last:border-b-0">
                <th scope="row" className={`${td} text-left font-medium text-ink`}>
                  {f.label}
                  <span className="block font-mono text-xs font-normal text-ink-muted">{f.prefixes.join(', ')}</span>
                </th>
                <td className={`${td} text-right`}>
                  <NumberField
                    label={`Reference width for ${f.label} (mm)`}
                    value={f.price!.ref_width_mm}
                    min={0}
                    className="w-20"
                    onChange={(v) => edit((d) => void (d.families[index].price!.ref_width_mm = v))}
                  />
                </td>
                <td className={`${td} text-right`}>
                  <NumberField
                    label={`Price of ${f.label} at the reference width (RM)`}
                    value={f.price!.at_ref}
                    min={0}
                    className="w-24"
                    onChange={(v) => edit((d) => void (d.families[index].price!.at_ref = v))}
                  />
                </td>
                <td className={`${td} text-right`}>
                  <NumberField
                    label={`Price of each extra 100 mm of ${f.label} (RM)`}
                    value={f.price!.per_100mm}
                    className="w-20"
                    onChange={(v) => edit((d) => void (d.families[index].price!.per_100mm = v))}
                  />
                </td>
                <td className={`${td} text-xs text-ink-soft`}>
                  {previewWidths(f).map((w) => (
                    <span key={w} className="mr-3 whitespace-nowrap">
                      {w} mm <strong className="font-semibold text-ink">{formatMyr(rulePrice(f.price!, w))}</strong>
                    </span>
                  ))}
                </td>
                <td className={td}>
                  {f.benchtop === 'fixed' ? (
                    <NumberField
                      label={`Worktop length of ${f.label} (m)`}
                      value={f.benchtop_m}
                      min={0}
                      unit="m"
                      className="w-16"
                      onChange={(v) => edit((d) => void (d.families[index].benchtop_m = v))}
                    />
                  ) : (
                    <span className="text-xs text-ink-soft">{WORKTOP_WORDS[f.benchtop]}</span>
                  )}
                </td>
                <td className={td}>
                  <Checkbox
                    label="Charged"
                    checked={f.labour}
                    onChange={(v) => edit((d) => void (d.families[index].labour = v))}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {fixed.length > 0 && (
        <div className={`${card} overflow-x-auto`}>
          <table className={table}>
            <caption className="pb-1 text-left">
              <SectionLabel>Fixed price (set in Modules)</SectionLabel>
            </caption>
            <thead>
              <tr className="border-b border-line">
                <th scope="col" className={th}>Kind</th>
                <th scope="col" className={th}>Worktop</th>
                <th scope="col" className={th}>Installation</th>
              </tr>
            </thead>
            <tbody>
              {fixed.map(({ f, index }) => (
                <tr key={f.id} className="border-b border-line last:border-b-0">
                  <th scope="row" className={`${td} text-left font-medium text-ink`}>{f.label}</th>
                  <td className={`${td} text-xs text-ink-soft`}>{WORKTOP_WORDS[f.benchtop]}</td>
                  <td className={td}>
                    <Checkbox
                      label="Charged"
                      checked={f.labour}
                      onChange={(v) => edit((d) => void (d.families[index].labour = v))}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};

// ─── Finishes and benchtops ──────────────────────────────────────────────────

export const FinishesSection: React.FC<SectionProps> = ({ catalog, edit }) => {
  const [name, setName] = useState('');
  const [rateText, setRateText] = useState('');
  const key = slug(name);
  const rate = parseNumber(rateText);
  const why =
    key === ''
      ? 'Enter a name for the benchtop.'
      : key in catalog.benchtop_options
        ? `There is already a benchtop called “${catalog.benchtop_options[key].name}”.`
        : rate === null || rate < 0
          ? 'Enter the price per metre.'
          : null;

  return (
    <div className="space-y-6">
      <div className={`${card} overflow-x-auto`}>
        <Intro>
          Each finish multiplies the price of every cabinet: 1.00 is the list price, 1.08 is 8% more.
        </Intro>
        <table className={table}>
          <caption className="sr-only">Finishes</caption>
          <thead>
            <tr className="border-b border-line">
              <th scope="col" className={th}>Finish</th>
              <th scope="col" className={th}>Name shown</th>
              <th scope="col" className={`${th} text-right`}>Multiplier</th>
              <th scope="col" className={th}>Effect</th>
            </tr>
          </thead>
          <tbody>
            {Object.entries(catalog.style_options).map(([k, s]) => (
              <tr key={k} className="border-b border-line last:border-b-0">
                <th scope="row" className={`${td} text-left font-mono text-xs font-normal text-ink-muted`}>{k}</th>
                <td className={td}>
                  <TextField
                    label={`Name of the ${k} finish`}
                    value={s.name}
                    className="w-56"
                    onChange={(v) => edit((d) => void (d.style_options[k].name = v))}
                  />
                </td>
                <td className={`${td} text-right`}>
                  <NumberField
                    label={`Multiplier for ${s.name}`}
                    value={s.multiplier}
                    min={0.01}
                    max={10}
                    className="w-20"
                    onChange={(v) => edit((d) => void (d.style_options[k].multiplier = v))}
                  />
                </td>
                <td className={`${td} text-xs text-ink-soft`}>
                  {s.multiplier === 1
                    ? 'List price'
                    : `${s.multiplier > 1 ? '+' : '−'}${Math.round(Math.abs(s.multiplier - 1) * 1000) / 10}% on cabinets`}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="mt-3 text-xs text-ink-muted">
          The look of each finish in 3D is part of the app, so finishes can be renamed and re-priced here but not added.
        </p>
      </div>

      <div className={`${card} overflow-x-auto`}>
        <table className={table}>
          <caption className="pb-1 text-left">
            <SectionLabel>Benchtops</SectionLabel>
          </caption>
          <thead>
            <tr className="border-b border-line">
              <th scope="col" className={th}>Name</th>
              <th scope="col" className={`${th} text-right`}>Per metre (RM)</th>
              <td className={th} />
            </tr>
          </thead>
          <tbody>
            {Object.entries(catalog.benchtop_options).map(([k, b]) => (
              <tr key={k} className="border-b border-line last:border-b-0">
                <td className={td}>
                  <TextField
                    label={`Name of benchtop ${k}`}
                    value={b.name}
                    className="w-72"
                    onChange={(v) => edit((d) => void (d.benchtop_options[k].name = v))}
                  />
                </td>
                <td className={`${td} text-right`}>
                  <NumberField
                    label={`Price per metre of ${b.name} (RM)`}
                    value={b.rate_per_m}
                    min={0}
                    className="w-24"
                    onChange={(v) => edit((d) => void (d.benchtop_options[k].rate_per_m = v))}
                  />
                </td>
                <td className={td}>
                  <button
                    type="button"
                    aria-label={`Remove ${b.name}`}
                    title={`Remove ${b.name}`}
                    onClick={() => edit((d) => void delete d.benchtop_options[k])}
                    className="flex h-9 w-9 cursor-pointer items-center justify-center rounded-lg text-ink-muted transition-colors hover:bg-danger-tint hover:text-danger"
                  >
                    <Trash2 className="h-4 w-4" aria-hidden />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <form
          className="mt-4 flex flex-wrap items-end gap-3 border-t border-line pt-4"
          onSubmit={(e) => {
            e.preventDefault();
            if (why) return;
            edit((d) => void (d.benchtop_options[key] = { name: name.trim(), rate_per_m: rate! }));
            setName('');
            setRateText('');
          }}
        >
          <label className="text-xs font-medium text-ink-soft">
            Add a benchtop
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="mt-1 block h-9 w-72 rounded-lg border border-line bg-surface px-2 text-[13px] text-ink"
            />
          </label>
          <label className="text-xs font-medium text-ink-soft">
            Per metre (RM)
            <input
              type="text"
              inputMode="decimal"
              value={rateText}
              onChange={(e) => setRateText(e.target.value)}
              className="mt-1 block h-9 w-24 rounded-lg border border-line bg-surface px-2 text-right text-[13px] text-ink"
            />
          </label>
          <ActionButton type="submit" disabled={why !== null} icon={<Plus className="h-4 w-4" aria-hidden />}>
            Add
          </ActionButton>
          {name.trim() !== '' && why && <p className="basis-full text-xs text-ink-muted" aria-live="polite">{why}</p>}
        </form>
      </div>
    </div>
  );
};

// ─── Installation and tax ────────────────────────────────────────────────────

export const ChargesSection: React.FC<SectionProps> = ({ catalog, edit }) => (
  <div className={card}>
    <Row label="Installation per module" hint="Charged once for every cabinet or appliance that carries installation (see “Price by width”).">
      <NumberField
        label="Installation per module (RM)"
        value={catalog.labour_rate_per_cabinet}
        min={0}
        unit="RM"
        onChange={(v) => edit((d) => void (d.labour_rate_per_cabinet = v))}
      />
    </Row>
    <Row label="Price for a module that is not listed" hint="Used when a type is in neither the Modules list nor a kind with a width rule.">
      <NumberField
        label="Price for a module that is not listed (RM)"
        value={catalog.unknown_module_price}
        min={0}
        unit="RM"
        onChange={(v) => edit((d) => void (d.unknown_module_price = v))}
      />
    </Row>
    <Row label="Deducted for a window" hint="Taken off the quote for each window (less material).">
      <NumberField
        label="Deducted for each window (RM)"
        value={-(catalog.obstacle_allowances.window ?? 0)}
        unit="RM"
        onChange={(v) => edit((d) => void (d.obstacle_allowances.window = -v))}
      />
    </Row>
    <Row label="Deducted for a door" hint="Taken off the quote for each door.">
      <NumberField
        label="Deducted for each door (RM)"
        value={-(catalog.obstacle_allowances.door ?? 0)}
        unit="RM"
        onChange={(v) => edit((d) => void (d.obstacle_allowances.door = -v))}
      />
    </Row>
    <Row label="Tax name" hint="Printed on the quote, e.g. SST.">
      <TextField
        label="Tax name"
        value={catalog.tax.label}
        className="w-28"
        onChange={(v) => edit((d) => void (d.tax.label = v))}
      />
    </Row>
    <Row label="Tax rate" hint="Check this with SS Love's accountant before real quotes go out.">
      <NumberField
        label="Tax rate (%)"
        value={Math.round(catalog.tax.rate * 10000) / 100}
        min={0}
        max={50}
        unit="%"
        onChange={(v) => edit((d) => void (d.tax.rate = Math.round(v * 100) / 10000))}
      />
    </Row>
  </div>
);

// ─── Wall work ───────────────────────────────────────────────────────────────

const OPENING_NAMES: Record<string, string> = {
  hidden_door: 'Hidden door',
  door: 'Door',
  window: 'Window',
};
const FINISH_NAMES: Record<string, string> = { paint: 'Paint', tiles: 'Tiles', panels: 'Panels' };

export const WallWorkSection: React.FC<SectionProps> = ({ catalog, edit }) => {
  const work = catalog.wall_work;
  if (!work) {
    return (
      <div className={card}>
        <Intro>This price list has no wall work yet. Reload it from the office server to start from the sample prices.</Intro>
      </div>
    );
  }
  const change = (fn: (w: WallWork) => void) =>
    edit((d) => {
      if (d.wall_work) fn(d.wall_work);
    });
  return (
    <div className="space-y-4">
      <Intro>
        What the sales app can quote for the wall itself: an opening cut into a solid wall (one price each, whatever its
        width) and a finish over the wall (per square metre of wall, less its doors and windows). None of it takes the
        cabinet finish multiplier.
      </Intro>
      <div className={card}>
        <Checkbox
          label="These are sample prices"
          hint="Untick once SS Love's own prices are in. The sales app says “sample price” while it is ticked."
          checked={work.is_placeholder}
          onChange={(v) => change((w) => void (w.is_placeholder = v))}
        />
      </div>
      <div className={`${card} overflow-x-auto`}>
        <table className={table}>
          <caption className="pb-1 text-left">
            <SectionLabel>Openings cut into a wall</SectionLabel>
          </caption>
          <thead>
            <tr className="border-b border-line">
              <th scope="col" className={th}>Opening</th>
              <th scope="col" className={th}>Name on the quote</th>
              <th scope="col" className={`${th} text-right`}>Price (RM)</th>
              <th scope="col" className={`${th} text-right`}>Usual width</th>
              <th scope="col" className={`${th} text-right`}>Height</th>
              <th scope="col" className={`${th} text-right`}>Sill</th>
              <th scope="col" className={th}>Widths offered (mm)</th>
            </tr>
          </thead>
          <tbody>
            {Object.entries(work.openings).map(([key, item]) => {
              const what = OPENING_NAMES[key] ?? key;
              return (
                <tr key={key} className="border-b border-line last:border-b-0">
                  <td className={`${td} font-medium`}>{what}</td>
                  <td className={td}>
                    <TextField label={`Name on the quote for a ${what.toLowerCase()}`} value={item.name} onChange={(v) => change((w) => void (w.openings[key].name = v))} className="w-64" />
                  </td>
                  <td className={`${td} text-right`}>
                    <NumberField label={`Price of a ${what.toLowerCase()} (RM)`} value={item.price} min={0} onChange={(v) => change((w) => void (w.openings[key].price = v))} />
                  </td>
                  {(['width_mm', 'height_mm', 'sill_mm'] as const).map((field) => (
                    <td key={field} className={`${td} text-right`}>
                      <NumberField
                        label={`${{ width_mm: 'Usual width', height_mm: 'Height', sill_mm: 'Height of the bottom edge from the floor' }[field]} of a ${what.toLowerCase()} (mm)`}
                        value={item[field]}
                        min={field === 'sill_mm' ? 0 : 1}
                        max={5000}
                        onChange={(v) => change((w) => void (w.openings[key][field] = v))}
                      />
                    </td>
                  ))}
                  <td className={td}>
                    <WidthListField label={`Widths offered for a ${what.toLowerCase()} (mm)`} value={item.widths_mm} onChange={(v) => change((w) => void (w.openings[key].widths_mm = v))} />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className={`${card} overflow-x-auto`}>
        <table className={table}>
          <caption className="pb-1 text-left">
            <SectionLabel>Wall finishes</SectionLabel>
          </caption>
          <thead>
            <tr className="border-b border-line">
              <th scope="col" className={th}>Finish</th>
              <th scope="col" className={th}>Name on the quote</th>
              <th scope="col" className={`${th} text-right`}>Rate (RM per m²)</th>
              <th scope="col" className={`${th} text-right`}>A 3.6 × 2.7 m wall</th>
            </tr>
          </thead>
          <tbody>
            {Object.entries(work.finishes).map(([key, item]) => {
              const what = FINISH_NAMES[key] ?? key;
              return (
                <tr key={key} className="border-b border-line last:border-b-0">
                  <td className={`${td} font-medium`}>{what}</td>
                  <td className={td}>
                    <TextField label={`Name on the quote for ${what.toLowerCase()}`} value={item.name} onChange={(v) => change((w) => void (w.finishes[key].name = v))} className="w-64" />
                  </td>
                  <td className={`${td} text-right`}>
                    <NumberField label={`Rate for ${what.toLowerCase()} (RM per square metre)`} value={item.rate_per_m2} min={0} onChange={(v) => change((w) => void (w.finishes[key].rate_per_m2 = v))} />
                  </td>
                  <td className={`${td} text-right text-ink-soft`}>{formatMyr(Math.round(item.rate_per_m2 * 9.72 * 100) / 100)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
};

// ─── Layout ──────────────────────────────────────────────────────────────────

const WIDTH_LISTS: [keyof Layout, string][] = [
  ['base_door_widths_mm', 'Base cabinets (doors)'],
  ['drawer_widths_mm', 'Drawer cabinets'],
  ['sink_widths_mm', 'Sink cabinets'],
  ['hob_widths_mm', 'Hob cabinets'],
  ['wall_widths_mm', 'Wall cabinets'],
];

const SIZES: [keyof Layout, string][] = [
  ['tall_width_mm', 'Tall unit width'],
  ['corner_size_mm', 'Corner unit size'],
  ['base_height_mm', 'Base cabinet height'],
  ['base_depth_mm', 'Base cabinet depth'],
  ['counter_height_mm', 'Worktop height from the floor'],
  ['wall_height_mm', 'Wall cabinet height'],
  ['wall_depth_mm', 'Wall cabinet depth'],
  ['wall_mount_mm', 'Wall cabinets hung at'],
  ['tall_height_mm', 'Tall unit height'],
  ['tall_depth_mm', 'Tall unit depth'],
];

const RULES: [keyof LayoutRules, string, string][] = [
  ['min_sink_to_hob_mm', 'Worktop between sink and hob', 'At least this much, so there is room to work.'],
  ['min_hob_side_counter_mm', 'Worktop beside the hob', 'On each side; the hob is never at the end of a run.'],
  ['min_sink_to_tall_mm', 'Worktop between sink and a tall unit', 'Somewhere to put things down and drain.'],
  ['min_filler_mm', 'Smallest filler', 'A smaller gap is not filled with a panel.'],
  ['max_filler_mm', 'Largest filler', 'A bigger gap gets another cabinet instead.'],
  ['scribe_tolerance_mm', 'Gap closed by scribing', 'Up to this much is cut to fit on site, with no filler.'],
  ['door_clearance_mm', 'Space kept beside a door', ''],
  ['window_clearance_mm', 'Space kept beside a window', 'For wall cabinets.'],
  ['max_sink_shift_from_window_mm', 'How far the sink may move off the window', 'To make the run fit.'],
];

export const LayoutSection: React.FC<SectionProps> = ({ catalog, edit }) => (
  <div className="space-y-6">
    <Intro>
      What the app uses when it suggests a layout for a room. These are the designer's rules of thumb; changing them
      changes the suggestions, not the prices.
    </Intro>

    <div className={card}>
      <SectionLabel className="mb-1">Widths it may use (mm)</SectionLabel>
      {WIDTH_LISTS.map(([key, label]) => (
        <Row key={key} label={label}>
          <WidthListField
            label={label}
            value={catalog.layout[key] as number[]}
            onChange={(v) => edit((d) => void ((d.layout[key] as number[]) = v))}
          />
        </Row>
      ))}
    </div>

    <div className={card}>
      <SectionLabel className="mb-1">Sizes (mm)</SectionLabel>
      {SIZES.map(([key, label]) => (
        <Row key={key} label={label}>
          <NumberField
            label={`${label} (mm)`}
            value={catalog.layout[key] as number}
            min={1}
            max={5000}
            unit="mm"
            onChange={(v) => edit((d) => void ((d.layout[key] as number) = v))}
          />
        </Row>
      ))}
    </div>

    <div className={card}>
      <SectionLabel className="mb-1">Design rules (mm)</SectionLabel>
      {RULES.map(([key, label, hint]) => (
        <Row key={key} label={label} hint={hint || undefined}>
          <NumberField
            label={`${label} (mm)`}
            value={catalog.layout.rules[key]}
            min={0}
            max={5000}
            unit="mm"
            onChange={(v) => edit((d) => void (d.layout.rules[key] = v))}
          />
        </Row>
      ))}
    </div>
  </div>
);
