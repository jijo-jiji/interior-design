import React, { useEffect, useRef, useState } from 'react';
import {
  Sparkles,
  Layers,
  ArrowLeft,
  ArrowRight,
  Trash2,
  FileText,
  Download,
  CheckCircle2,
  ChevronRight,
  ChevronLeft,
  Receipt,
  AlertTriangle,
} from 'lucide-react';
import confetti from 'canvas-confetti';
import type { CabinetFinish, DoorStyle, CabinetData } from '../canvas/CabinetMesh';
import type { QuoteTotals } from '../pricing';
import { formatMyr } from '../pricing';
import { ActionButton, LinkButton, SectionLabel, SegmentedControl } from './ui';

export type SaveState = 'idle' | 'saving' | 'saved' | 'error';

interface JoineryInspectorProps {
  finish: CabinetFinish;
  onSelectFinish: (finish: CabinetFinish) => void;
  doorStyle: DoorStyle;
  onSelectDoorStyle: (style: DoorStyle) => void;
  selectedCabinet: CabinetData | null;
  onNudgeCabinet: (direction: -1 | 1) => void;
  onDeleteCabinet: (id: string) => void;
  cabinetCount: number;
  totals: QuoteTotals;
  styleMultipliers: Record<string, number>;
  benchtopMaterial: string | null;
  onSelectBenchtop: (material: string | null) => void;
  /** Length of base/corner run the benchtop covers. */
  benchtopMetres: number;
  benchtopRates: Record<string, number>;
  benchtopNames: Record<string, string>;
  quoteId: string;
  onSaveRevisions: () => void;
  saveState: SaveState;
  saveError: string | null;
  isCollapsed: boolean;
  onToggleCollapse: () => void;
}

type InspectorTab = 'finishes' | 'module' | 'commercial';

/** Material swatches describe the physical finish, not the UI chrome. */
const FINISHES: { value: CabinetFinish; name: string; blurb: string; swatch: string }[] = [
  {
    value: 'japandi',
    name: 'Japandi Natural',
    blurb: 'French white oak & champagne gold',
    swatch: '#C8B39B',
  },
  {
    value: 'nordic',
    name: 'Warm Nordic',
    blurb: 'Bleached birch & brushed brass',
    swatch: '#EAE1D5',
  },
  {
    value: 'minimalist',
    name: 'Modern Minimalist',
    blurb: 'Matte cashmere & graphite',
    swatch: '#F0EAE1',
  },
  {
    value: 'industrial',
    name: 'Smoked Charcoal Oak',
    blurb: 'Dark smoked timber & steel',
    swatch: '#4A4038',
  },
];

const DOOR_OPTIONS: { value: DoorStyle; label: string }[] = [
  { value: 'slab', label: 'Slab J-Pull' },
  { value: 'shaker', label: 'Slim Shaker' },
  { value: 'fluted', label: 'Fluted Reed' },
];

const TABS: { value: InspectorTab; label: string; icon: React.ReactNode }[] = [
  { value: 'finishes', label: 'Finishes', icon: <Sparkles className="h-3.5 w-3.5" /> },
  { value: 'module', label: 'Module', icon: <Layers className="h-3.5 w-3.5" /> },
  { value: 'commercial', label: 'Pricing', icon: <Receipt className="h-3.5 w-3.5" /> },
];

export const JoineryInspector: React.FC<JoineryInspectorProps> = ({
  finish,
  onSelectFinish,
  doorStyle,
  onSelectDoorStyle,
  selectedCabinet,
  onNudgeCabinet,
  onDeleteCabinet,
  cabinetCount,
  totals,
  styleMultipliers,
  benchtopMaterial,
  onSelectBenchtop,
  benchtopMetres,
  benchtopRates,
  benchtopNames,
  quoteId,
  onSaveRevisions,
  saveState,
  saveError,
  isCollapsed,
  onToggleCollapse,
}) => {
  const [activeTab, setActiveTab] = useState<InspectorTab>('finishes');
  const previousSaveState = useRef<SaveState>(saveState);

  // Celebrate only once the backend has actually accepted the revision.
  useEffect(() => {
    if (saveState === 'saved' && previousSaveState.current !== 'saved') {
      confetti({
        particleCount: 65,
        spread: 55,
        origin: { y: 0.85 },
        colors: ['#E6BEAE', '#E7D8C9', '#A25F41', '#2C2724'],
      });
    }
    previousSaveState.current = saveState;
  }, [saveState]);

  return (
    <aside
      className={`relative z-20 flex h-full shrink-0 border-l border-line bg-surface-muted transition-[width] duration-200 ${
        isCollapsed ? 'w-0' : 'w-[22rem]'
      }`}
    >
      {/* ── Collapse handle ───────────────────────────────────────────── */}
      <button
        type="button"
        onClick={onToggleCollapse}
        aria-expanded={!isCollapsed}
        aria-label={isCollapsed ? 'Expand the studio panel' : 'Collapse the studio panel'}
        title={isCollapsed ? 'Expand the studio panel' : 'Collapse the studio panel'}
        className="absolute top-4 -left-3.5 z-30 flex h-12 w-7 cursor-pointer items-center justify-center rounded-l-xl border border-r-0 border-line bg-surface text-ink-muted shadow-md transition-colors hover:text-ink"
      >
        {isCollapsed ? <ChevronLeft className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
      </button>

      {!isCollapsed && (
        <div className="flex h-full w-full min-w-0 flex-col">
          {/* ── Tabs ──────────────────────────────────────────────────── */}
          <div className="border-b border-line bg-surface px-3 py-2.5">
            <div role="tablist" aria-label="Inspector sections" className="flex items-center gap-1">
              {TABS.map((tab) => {
                const active = activeTab === tab.value;
                return (
                  <button
                    key={tab.value}
                    type="button"
                    role="tab"
                    aria-selected={active}
                    onClick={() => setActiveTab(tab.value)}
                    className={`flex flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-lg border px-2 py-1.5 text-[13px] font-medium transition-colors ${
                      active
                        ? 'border-espresso bg-espresso text-surface-muted'
                        : 'border-line bg-surface text-ink-muted hover:border-line-strong hover:text-ink'
                    }`}
                  >
                    {tab.icon}
                    <span>{tab.label}</span>
                    {tab.value === 'module' && selectedCabinet && (
                      <span
                        className={`h-1.5 w-1.5 rounded-full ${active ? 'bg-clay-soft' : 'bg-clay'}`}
                      />
                    )}
                  </button>
                );
              })}
            </div>
          </div>

          {/* ── Panel body ────────────────────────────────────────────── */}
          <div className="min-h-0 flex-1 space-y-6 overflow-y-auto p-4">
            {/* ── Finishes ────────────────────────────────────────────── */}
            {activeTab === 'finishes' && (
              <>
                <section className="space-y-3">
                  <SectionLabel>Architectural materials</SectionLabel>
                  <div className="space-y-2">
                    {FINISHES.map((item) => {
                      const active = finish === item.value;
                      const multiplier = styleMultipliers[item.value] ?? 1;
                      return (
                        <button
                          key={item.value}
                          type="button"
                          aria-pressed={active}
                          onClick={() => onSelectFinish(item.value)}
                          className={`flex w-full cursor-pointer items-center justify-between gap-3 rounded-xl border p-3 text-left transition-colors ${
                            active
                              ? 'border-clay bg-surface ring-1 ring-clay'
                              : 'border-line bg-surface hover:border-line-strong'
                          }`}
                        >
                          <span className="flex min-w-0 items-center gap-3">
                            <span
                              aria-hidden
                              className="h-7 w-7 shrink-0 rounded-full border border-black/10 shadow-inner"
                              style={{ backgroundColor: item.swatch }}
                            />
                            <span className="min-w-0">
                              <span className="block truncate text-[13px] font-semibold text-ink">
                                {item.name}
                              </span>
                              <span className="block truncate text-xs text-ink-muted">
                                {item.blurb}
                              </span>
                            </span>
                          </span>
                          <span className="shrink-0 font-mono text-xs text-ink-muted">
                            {multiplier.toFixed(2)}×
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </section>

                <section className="space-y-2">
                  <SectionLabel>Door face profile</SectionLabel>
                  <SegmentedControl
                    label="Door face profile"
                    size="sm"
                    className="w-full [&>button]:flex-1 [&>button]:justify-center"
                    options={DOOR_OPTIONS}
                    value={doorStyle}
                    onChange={onSelectDoorStyle}
                  />
                  <p className="text-xs text-ink-muted">
                    Visual profile only — the quotation does not price door faces separately.
                  </p>
                </section>

                {/* ── Benchtop ──────────────────────────────────────────── */}
                <section className="space-y-2">
                  <SectionLabel>Benchtop</SectionLabel>
                  <p className="text-xs text-ink-muted">
                    {benchtopMetres > 0
                      ? `${benchtopMetres.toFixed(2)} linear metres of base run measured`
                      : 'Place base joinery to measure the run.'}
                  </p>

                  <div className="space-y-2">
                    {Object.entries(benchtopRates).map(([key, rate]) => {
                      const active = benchtopMaterial === key;
                      return (
                        <button
                          key={key}
                          type="button"
                          aria-pressed={active}
                          onClick={() => onSelectBenchtop(key)}
                          className={`flex w-full cursor-pointer items-center justify-between gap-3 rounded-xl border p-3 text-left transition-colors ${
                            active
                              ? 'border-clay bg-surface ring-1 ring-clay'
                              : 'border-line bg-surface hover:border-line-strong'
                          }`}
                        >
                          <span className="min-w-0">
                            <span className="block truncate text-[13px] font-semibold text-ink">
                              {benchtopNames[key] ?? key}
                            </span>
                            <span className="block text-xs text-ink-muted">
                              {formatMyr(rate)} per linear metre
                            </span>
                          </span>
                          <span className="shrink-0 font-mono text-xs text-ink">
                            {benchtopMetres > 0 ? `+${formatMyr(rate * benchtopMetres)}` : '—'}
                          </span>
                        </button>
                      );
                    })}
                  </div>

                  {benchtopMaterial && (
                    <ActionButton
                      variant="ghost"
                      className="w-full"
                      onClick={() => onSelectBenchtop(null)}
                    >
                      Remove benchtop from quote
                    </ActionButton>
                  )}
                </section>
              </>
            )}

            {/* ── Selected module ─────────────────────────────────────── */}
            {activeTab === 'module' && (
              <section className="space-y-3">
                <SectionLabel>Joinery specification</SectionLabel>

                {selectedCabinet ? (
                  <div className="space-y-4 rounded-xl border border-line bg-surface p-4">
                    <div className="flex items-start justify-between gap-2 border-b border-line pb-3">
                      <div className="min-w-0">
                        <h4 className="truncate text-sm font-semibold uppercase text-ink">
                          {selectedCabinet.type.replace(/_/g, ' ')}
                        </h4>
                        <p className="truncate font-mono text-xs text-ink-muted">
                          {selectedCabinet.id}
                        </p>
                      </div>
                      <span className="shrink-0 rounded-full bg-sand px-2.5 py-1 font-mono text-xs font-semibold text-ink">
                        {(selectedCabinet.x * 1000).toFixed(0)}mm from left
                      </span>
                    </div>

                    <dl className="grid grid-cols-3 gap-2 rounded-lg border border-line bg-surface-muted py-2.5 text-center">
                      {[
                        { label: 'Width', value: selectedCabinet.width },
                        { label: 'Height', value: selectedCabinet.height },
                        { label: 'Depth', value: selectedCabinet.depth },
                      ].map((dim) => (
                        <div key={dim.label}>
                          <dt className="text-[11px] uppercase tracking-wide text-ink-muted">
                            {dim.label}
                          </dt>
                          <dd className="font-mono text-[13px] font-semibold text-ink">
                            {(dim.value * 1000).toFixed(0)}mm
                          </dd>
                        </div>
                      ))}
                    </dl>

                    <div className="space-y-2">
                      <SectionLabel>Nudge along wall rail</SectionLabel>
                      <div className="flex items-center gap-2">
                        <ActionButton
                          className="flex-1 font-mono"
                          icon={<ArrowLeft className="h-4 w-4" />}
                          onClick={() => onNudgeCabinet(-1)}
                          aria-label="Move module 50 millimetres left"
                        >
                          50mm
                        </ActionButton>
                        <ActionButton
                          className="flex-1 font-mono"
                          onClick={() => onNudgeCabinet(1)}
                          aria-label="Move module 50 millimetres right"
                        >
                          50mm
                          <ArrowRight className="h-4 w-4" />
                        </ActionButton>
                        <ActionButton
                          variant="danger"
                          onClick={() => onDeleteCabinet(selectedCabinet.id)}
                          aria-label="Delete this module"
                          title="Delete module"
                        >
                          <Trash2 className="h-4 w-4" />
                        </ActionButton>
                      </div>
                    </div>
                  </div>
                ) : (
                  <div className="space-y-2 rounded-xl border border-dashed border-line bg-surface p-6 text-center">
                    <Layers className="mx-auto h-6 w-6 text-clay" />
                    <p className="text-[13px] text-ink-soft">No module selected.</p>
                    <p className="text-xs text-ink-muted">
                      Click a module in the 3D scene, or press 1–4 to add one.
                    </p>
                  </div>
                )}
              </section>
            )}

            {/* ── Commercial ──────────────────────────────────────────── */}
            {activeTab === 'commercial' && (
              <section className="space-y-4">
                <SectionLabel>Commercial summary</SectionLabel>

                <div className="rounded-xl border border-line bg-surface p-4">
                  <dl className="space-y-2">
                    {totals.lineItems.map((line) => (
                      <div key={line.description} className="flex justify-between gap-3 text-[13px]">
                        <dt className="min-w-0 text-ink-soft">
                          <span className="block truncate">{line.description}</span>
                          {line.qty > 1 && (
                            <span className="font-mono text-xs text-ink-muted">
                              {line.qty} × {formatMyr(line.unit_price)}
                            </span>
                          )}
                        </dt>
                        <dd className="shrink-0 font-mono text-ink">{formatMyr(line.total)}</dd>
                      </div>
                    ))}

                    {totals.lineItems.length === 0 && (
                      <p className="text-[13px] text-ink-muted">
                        No modules placed — add joinery to price this room.
                      </p>
                    )}

                    <div className="flex justify-between gap-3 border-t border-line pt-2 text-[13px]">
                      <dt className="text-ink-soft">Subtotal</dt>
                      <dd className="font-mono text-ink">{formatMyr(totals.subtotal)}</dd>
                    </div>
                    <div className="flex justify-between gap-3 text-[13px]">
                      <dt className="text-ink-soft">SST (8%)</dt>
                      <dd className="font-mono text-ink">{formatMyr(totals.gst)}</dd>
                    </div>
                  </dl>

                  <div className="mt-3 flex items-baseline justify-between border-t border-line pt-3">
                    <span className="text-sm font-semibold text-ink">Total incl. SST</span>
                    <span className="font-mono text-xl font-bold text-ink">
                      {formatMyr(totals.total)}
                    </span>
                  </div>
                  <p className="mt-1 text-xs text-ink-muted">
                    {cabinetCount} module{cabinetCount === 1 ? '' : 's'} · rates from the live
                    catalogue
                  </p>
                </div>

                <div className="space-y-2">
                  <ActionButton
                    variant="primary"
                    className="w-full py-2.5"
                    onClick={onSaveRevisions}
                    disabled={saveState === 'saving'}
                    icon={<CheckCircle2 className="h-4 w-4 text-clay-soft" />}
                  >
                    {saveState === 'saving' ? 'Saving revision…' : 'Save & lock studio BOQ'}
                  </ActionButton>

                  {saveState === 'saved' && (
                    <p className="flex items-center gap-1.5 text-xs text-sage">
                      <CheckCircle2 className="h-3.5 w-3.5" />
                      Revision saved to the consultation record.
                    </p>
                  )}
                  {saveState === 'error' && (
                    <p className="flex items-start gap-1.5 text-xs text-danger">
                      <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                      <span>{saveError ?? 'Could not save this revision.'}</span>
                    </p>
                  )}

                  <LinkButton
                    href={`/pdf/${quoteId}`}
                    target="_blank"
                    rel="noreferrer"
                    className="w-full"
                    icon={<FileText className="h-4 w-4 text-ink-muted" />}
                  >
                    Signed PDF proposal
                  </LinkButton>

                  <div className="grid grid-cols-2 gap-2">
                    <LinkButton
                      href={`/api/export/${quoteId}/dxf`}
                      download
                      icon={<Download className="h-4 w-4 text-ink-muted" />}
                    >
                      DXF
                    </LinkButton>
                    <LinkButton
                      href={`/api/export/${quoteId}/cutlist`}
                      download
                      icon={<Download className="h-4 w-4 text-ink-muted" />}
                    >
                      Cutlist
                    </LinkButton>
                  </div>
                </div>
              </section>
            )}
          </div>
        </div>
      )}
    </aside>
  );
};
