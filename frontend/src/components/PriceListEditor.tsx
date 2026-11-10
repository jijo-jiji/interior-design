import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { History, Tags, X } from 'lucide-react';
import {
  describeProblem,
  loadCatalog,
  loadVersions,
  sameCatalog,
  saveCatalog,
  withEdit,
} from '../catalogEditor.ts';
import type { SaveOutcome, VersionInfo } from '../catalogEditor.ts';
import type { Catalog, ServedCatalog } from '../pricing.ts';
import { Checkbox, TextField } from './priceList/fields';
import { ChargesSection, FamiliesSection, FinishesSection, LayoutSection, ModulesSection, WallWorkSection } from './priceList/sections';
import { ActionButton, SegmentedControl } from './ui';

type Section = 'modules' | 'width' | 'finishes' | 'wall' | 'charges' | 'layout';

const SECTIONS: { value: Section; label: string; title: string }[] = [
  { value: 'modules', label: 'Modules', title: 'Cabinets and appliances: sizes and prices' },
  { value: 'width', label: 'Price by width', title: 'How other widths are priced' },
  { value: 'finishes', label: 'Finishes & benchtops', title: 'Finish multipliers and benchtop rates' },
  { value: 'wall', label: 'Wall work', title: 'Openings cut into a wall, and wall finishes' },
  { value: 'charges', label: 'Installation & tax', title: 'Installation, deductions and tax' },
  { value: 'layout', label: 'Layout rules', title: 'Sizes and rules the layout suggestions follow' },
];

interface PriceListEditorProps {
  /** The price list the studio is using now. */
  catalog: ServedCatalog;
  onClose: () => void;
  /** Called with each saved version so the studio prices with it at once. */
  onSaved: (catalog: Catalog) => void;
}

const formatStamp = (iso?: string | null) => {
  if (!iso) return null;
  const date = new Date(iso);
  return Number.isNaN(date.getTime())
    ? null
    : date.toLocaleString('en-MY', { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit' });
};

/** The designer's price list: every price, size, multiplier, rate and rule the
 *  quotes and the sales app are built from. Saving makes a new version; the
 *  older ones are kept, so a quote can always be traced to the prices it used. */
export const PriceListEditor: React.FC<PriceListEditorProps> = ({ catalog, onClose, onSaved }) => {
  /** The version being edited from (what the office has). */
  const [live, setLive] = useState<Catalog>(catalog);
  const [draft, setDraft] = useState<Catalog>(() => structuredClone(catalog));
  const [section, setSection] = useState<Section>('modules');
  const [adminKey, setAdminKey] = useState('');
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<SaveOutcome | null>(null);
  const [askDiscard, setAskDiscard] = useState(false);
  const [versions, setVersions] = useState<VersionInfo[]>([]);
  const [copyOf, setCopyOf] = useState<number | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const titleRef = useRef<HTMLHeadingElement>(null);
  const requiresKey = Boolean(catalog.requires_admin_key);

  const dirty = useMemo(() => !sameCatalog(draft, live), [draft, live]);

  const edit = useCallback((change: (d: Catalog) => void) => {
    setDraft((d) => withEdit(d, change));
    setOutcome(null);
  }, []);

  // Focus moves into the dialog, and back to what opened it on close.
  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    titleRef.current?.focus();
    return () => opener?.focus?.();
  }, []);

  useEffect(() => {
    let cancelled = false;
    loadVersions()
      .then((list) => !cancelled && setVersions(list))
      .catch(() => !cancelled && setVersions([]));
    return () => {
      cancelled = true;
    };
  }, [live.version]);

  const requestClose = useCallback(() => {
    if (dirty) setAskDiscard(true);
    else onClose();
  }, [dirty, onClose]);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [requestClose]);

  const discard = () => {
    setDraft(structuredClone(live));
    setCopyOf(null);
    setOutcome(null);
    setAskDiscard(false);
  };

  const save = async () => {
    setBusy(true);
    setOutcome(null);
    const result = await saveCatalog(draft, live.version, adminKey);
    setBusy(false);
    setOutcome(result);
    if (result.kind === 'saved') {
      setLive(result.catalog);
      setDraft(structuredClone(result.catalog));
      setCopyOf(null);
      onSaved(result.catalog);
    }
  };

  /** After a conflict: take the newer price list the office has. */
  const takeTheirs = async () => {
    try {
      const theirs = await loadCatalog();
      setLive(theirs);
      setDraft(structuredClone(theirs));
      setCopyOf(null);
      setOutcome(null);
      setLoadError(null);
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : "Couldn't load it.");
    }
  };

  /** Start the draft from an older version; saving makes it the newest. */
  const startFrom = async (version: number) => {
    try {
      const old = await loadCatalog(version);
      setDraft({ ...old, version: live.version });
      setCopyOf(version);
      setOutcome(null);
      setLoadError(null);
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : "Couldn't load that version.");
    }
  };

  const savedAt = formatStamp(live.updated_at);
  const nextVersion = live.version + 1;

  return (
    <div className="fixed inset-0 z-50 flex items-stretch justify-center p-3 sm:p-6" role="dialog" aria-modal="true" aria-labelledby="price-list-title">
      <div className="fixed inset-0 bg-espresso/40 backdrop-blur-[2px]" onClick={requestClose} aria-hidden />

      <div className="relative flex h-full w-full max-w-6xl flex-col overflow-hidden rounded-2xl border border-line bg-surface-muted shadow-2xl">
        {/* ── Title ─────────────────────────────────────────────────── */}
        <div className="flex flex-wrap items-center gap-3 border-b border-line bg-surface px-5 py-3">
          <Tags className="h-5 w-5 shrink-0 text-clay" aria-hidden />
          <div className="min-w-0">
            <h2 id="price-list-title" ref={titleRef} tabIndex={-1} className="text-[16px] font-semibold text-ink outline-none">
              Price list
            </h2>
            <p className="text-xs text-ink-muted">
              Version {live.version}
              {savedAt ? ` · saved ${savedAt}` : ''}
              {copyOf !== null ? ` · editing a copy of version ${copyOf}` : ''}
            </p>
          </div>
          <span
            className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${
              draft.is_placeholder ? 'bg-clay-tint text-clay-ink' : 'bg-sage-tint text-sage'
            }`}
          >
            {draft.is_placeholder ? 'Sample prices' : 'Confirmed prices'}
          </span>

          <div className="ml-auto flex items-center gap-2">
            {versions.length > 1 && (
              <label className="flex items-center gap-1.5 text-xs text-ink-soft">
                <History className="h-4 w-4 text-ink-muted" aria-hidden />
                <span className="sr-only">Start from an earlier version</span>
                <select
                  aria-label="Start from an earlier version"
                  value=""
                  onChange={(e) => e.target.value && startFrom(Number(e.target.value))}
                  className="h-9 rounded-lg border border-line bg-surface px-2 text-[13px] text-ink"
                >
                  <option value="">Earlier versions…</option>
                  {[...versions].reverse().map((v) => (
                    <option key={v.version} value={v.version}>
                      Version {v.version}
                      {v.version === live.version ? ' (current)' : ''}
                      {v.updated_at ? ` · ${formatStamp(v.updated_at)}` : ''}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <button
              type="button"
              onClick={requestClose}
              aria-label="Close the price list"
              title="Close"
              className="flex h-10 w-10 cursor-pointer items-center justify-center rounded-lg text-ink-muted transition-colors hover:bg-surface-sunken hover:text-ink"
            >
              <X className="h-4 w-4" aria-hidden />
            </button>
          </div>
        </div>

        {/* ── Name and whether the numbers are confirmed ───────────── */}
        <div className="flex flex-wrap items-center gap-x-6 gap-y-2 border-b border-line bg-surface px-5 py-2.5">
          <label className="flex items-center gap-2 text-xs font-medium text-ink-soft">
            Name
            <TextField label="Name of this price list" value={draft.name} onChange={(v) => edit((d) => void (d.name = v))} className="w-64" />
          </label>
          <Checkbox
            label="These are SS Love's confirmed prices"
            hint="Leave this off while the figures are samples."
            checked={!draft.is_placeholder}
            onChange={(v) => edit((d) => void (d.is_placeholder = !v))}
          />
        </div>

        {/* ── Sections ──────────────────────────────────────────────── */}
        <div className="border-b border-line px-5 py-2.5">
          <SegmentedControl label="Part of the price list" options={SECTIONS} value={section} onChange={setSection} className="flex-wrap" />
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
          {section === 'modules' && <ModulesSection catalog={draft} edit={edit} />}
          {section === 'width' && <FamiliesSection catalog={draft} edit={edit} />}
          {section === 'finishes' && <FinishesSection catalog={draft} edit={edit} />}
          {section === 'wall' && <WallWorkSection catalog={draft} edit={edit} />}
          {section === 'charges' && <ChargesSection catalog={draft} edit={edit} />}
          {section === 'layout' && <LayoutSection catalog={draft} edit={edit} />}
        </div>

        {/* ── Save ──────────────────────────────────────────────────── */}
        <div className="space-y-2 border-t border-line bg-surface px-5 py-3">
          {outcome?.kind === 'invalid' && (
            <div role="alert" className="rounded-lg bg-danger-tint px-3 py-2 text-[13px] text-danger">
              <p className="font-medium">The office couldn't accept these values. Nothing was saved.</p>
              <ul className="mt-1 list-disc pl-5">
                {outcome.problems.map((p, i) => (
                  <li key={i}>{describeProblem(p, draft)}</li>
                ))}
              </ul>
            </div>
          )}
          {outcome?.kind === 'conflict' && (
            <div role="alert" className="flex flex-wrap items-center gap-3 rounded-lg bg-danger-tint px-3 py-2 text-[13px] text-danger">
              <p className="font-medium">{outcome.message} Nothing was saved.</p>
              <ActionButton variant="secondary" onClick={takeTheirs}>
                Load the newer price list (drops your changes)
              </ActionButton>
            </div>
          )}
          {outcome?.kind === 'locked' && (
            <p role="alert" className="rounded-lg bg-danger-tint px-3 py-2 text-[13px] text-danger">
              Saving needs the office key, and it was missing or wrong. Enter it below and save again.
            </p>
          )}
          {outcome?.kind === 'failed' && (
            <p role="alert" className="rounded-lg bg-danger-tint px-3 py-2 text-[13px] text-danger">
              {outcome.message}
            </p>
          )}
          {loadError && (
            <p role="alert" className="rounded-lg bg-danger-tint px-3 py-2 text-[13px] text-danger">
              {loadError}
            </p>
          )}
          <p className="sr-only" aria-live="polite">
            {outcome?.kind === 'saved' ? `Saved as version ${outcome.catalog.version}.` : ''}
          </p>

          {askDiscard && (
            <div role="alertdialog" aria-label="Unsaved changes" className="flex flex-wrap items-center gap-3 rounded-lg bg-clay-tint px-3 py-2 text-[13px] text-clay-ink">
              <p className="font-medium">You have changes that are not saved.</p>
              <ActionButton variant="secondary" onClick={() => setAskDiscard(false)}>
                Keep editing
              </ActionButton>
              <ActionButton variant="danger" onClick={onClose}>
                Close without saving
              </ActionButton>
            </div>
          )}

          <div className="flex flex-wrap items-center gap-3">
            {(requiresKey || outcome?.kind === 'locked') && (
              <label className="flex items-center gap-2 text-xs font-medium text-ink-soft">
                Office key
                <input
                  type="password"
                  autoComplete="off"
                  value={adminKey}
                  onChange={(e) => setAdminKey(e.target.value)}
                  aria-invalid={outcome?.kind === 'locked' || undefined}
                  className="h-9 w-44 rounded-lg border border-line bg-surface px-2 text-[13px] text-ink"
                />
              </label>
            )}
            <p className="text-xs text-ink-muted">
              {outcome?.kind === 'saved'
                ? `Saved as version ${outcome.catalog.version}. The sales app picks it up next time it connects.`
                : dirty
                  ? `Saving makes version ${nextVersion}. Version ${live.version} is kept.`
                  : 'No changes yet.'}
            </p>
            <div className="ml-auto flex items-center gap-2">
              <ActionButton variant="ghost" onClick={discard} disabled={!dirty || busy}>
                Discard changes
              </ActionButton>
              <ActionButton variant="primary" onClick={save} disabled={!dirty || busy}>
                {busy ? 'Saving…' : `Save as version ${nextVersion}`}
              </ActionButton>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
