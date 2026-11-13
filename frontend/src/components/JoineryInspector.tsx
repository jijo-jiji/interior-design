import React, { useEffect, useRef } from 'react';
import {
  Ruler,
  Palette,
  LayoutList,
  Receipt,
  ArrowLeft,
  ArrowRight,
  Trash2,
  FileText,
  Download,
  CheckCircle2,
  ChevronRight,
  ChevronLeft,
  AlertTriangle,
} from 'lucide-react';
import confetti from 'canvas-confetti';
import type { CabinetFinish, DoorStyle } from '../canvas/cabinetBuilder';
import type { CabinetData } from '../layout/model';
import { positionLabel, readingOrder } from '../layout/model';
import type { QuoteTotals } from '../pricing';
import { formatMyr } from '../pricing';
import { ActionButton, LinkButton, SectionLabel, SegmentedControl } from './ui';

export type SaveState = 'idle' | 'saving' | 'saved' | 'error';
export type InspectorTab = 'room' | 'finish' | 'cabinets' | 'price';

interface JoineryInspectorProps {
  tab: InspectorTab;
  onSelectTab: (tab: InspectorTab) => void;
  // Room
  roomShape: string;
  onSelectShape: (shape: string) => void;
  wallWidthMm: number;
  onChangeWallWidth: (mm: number) => void;
  wallHeightMm: number;
  onChangeWallHeight: (mm: number) => void;
  returnMm: number;
  onChangeReturn: (mm: number) => void;
  // Finish
  finish: CabinetFinish;
  onSelectFinish: (finish: CabinetFinish) => void;
  styleNames: Record<string, string>;
  styleMultipliers: Record<string, number>;
  doorStyle: DoorStyle;
  onSelectDoorStyle: (style: DoorStyle) => void;
  benchtopMaterial: string | null;
  onSelectBenchtop: (material: string | null) => void;
  benchtopMetres: number;
  benchtopRates: Record<string, number>;
  benchtopNames: Record<string, string>;
  // Cabinets
  cabinets: CabinetData[];
  selectedCabinetId: string | null;
  onSelectCabinet: (id: string) => void;
  onNudgeCabinet: (direction: -1 | 1) => void;
  onDeleteCabinet: (id: string) => void;
  // Price
  totals: QuoteTotals;
  quoteId: string;
  onSaveRevisions: () => void;
  saveState: SaveState;
  saveError: string | null;
  isCollapsed: boolean;
  onToggleCollapse: () => void;
}

/** Same finishes and colours as the sales app's 3D view. */
const FINISHES: { value: CabinetFinish; blurb: string; swatch: string }[] = [
  { value: 'japandi', blurb: 'Light oak, warm white wall units, brass bar handles', swatch: '#E2C49C' },
  { value: 'minimalist', blurb: 'Matte charcoal, handleless', swatch: '#40454E' },
  { value: 'nordic', blurb: 'Soft sage, birch tall units, nickel knobs', swatch: '#A7B5A0' },
  { value: 'industrial', blurb: 'Dark walnut, graphite wall units, black steel', swatch: '#7A5A44' },
];

const DOOR_OPTIONS: { value: DoorStyle; label: string }[] = [
  { value: 'slab', label: 'Flat' },
  { value: 'shaker', label: 'Shaker' },
  { value: 'fluted', label: 'Fluted' },
];

const SHAPE_OPTIONS = [
  { value: 'singleWall', label: 'One wall' },
  { value: 'lShape', label: 'L-shape' },
  { value: 'galley', label: 'Galley' },
];

const TABS: { value: InspectorTab; label: string; icon: React.ReactNode }[] = [
  { value: 'room', label: 'Room', icon: <Ruler className="h-4 w-4" aria-hidden /> },
  { value: 'finish', label: 'Finish', icon: <Palette className="h-4 w-4" aria-hidden /> },
  { value: 'cabinets', label: 'Cabinets', icon: <LayoutList className="h-4 w-4" aria-hidden /> },
  { value: 'price', label: 'Price', icon: <Receipt className="h-4 w-4" aria-hidden /> },
];

const RANGES = {
  width: { min: 1200, max: 9000 },
  height: { min: 2000, max: 3600 },
  ret: { min: 900, max: 6000 },
};

const MmField: React.FC<{
  label: string;
  value: number;
  range: { min: number; max: number };
  onChange: (mm: number) => void;
}> = ({ label, value, range, onChange }) => (
  <label className="block">
    <span className="mb-1 block text-[13px] font-medium text-ink-soft">{label}</span>
    <span className="relative block">
      <input
        type="number"
        inputMode="numeric"
        min={range.min}
        max={range.max}
        step={50}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        onBlur={(e) => onChange(Math.min(range.max, Math.max(range.min, Number(e.target.value) || range.min)))}
        className="min-h-10 w-full rounded-xl border border-line-strong bg-surface py-2 pr-10 pl-3 text-[14px] text-ink tabular-nums focus:border-clay focus:outline-none"
      />
      <span className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-xs text-ink-muted">mm</span>
    </span>
  </label>
);

export const JoineryInspector: React.FC<JoineryInspectorProps> = (props) => {
  const {
    tab,
    onSelectTab,
    roomShape,
    onSelectShape,
    wallWidthMm,
    onChangeWallWidth,
    wallHeightMm,
    onChangeWallHeight,
    returnMm,
    onChangeReturn,
    finish,
    onSelectFinish,
    styleNames,
    styleMultipliers,
    doorStyle,
    onSelectDoorStyle,
    benchtopMaterial,
    onSelectBenchtop,
    benchtopMetres,
    benchtopRates,
    benchtopNames,
    cabinets,
    selectedCabinetId,
    onSelectCabinet,
    onNudgeCabinet,
    onDeleteCabinet,
    totals,
    quoteId,
    onSaveRevisions,
    saveState,
    saveError,
    isCollapsed,
    onToggleCollapse,
  } = props;
  const previousSaveState = useRef<SaveState>(saveState);

  // A small celebration once the office has actually accepted the revision
  // (skipped for people who prefer reduced motion).
  useEffect(() => {
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (saveState === 'saved' && previousSaveState.current !== 'saved' && !reduce) {
      confetti({ particleCount: 60, spread: 55, origin: { y: 0.85 }, colors: ['#E6BEAE', '#E7D8C9', '#A25F41', '#2C2724'] });
    }
    previousSaveState.current = saveState;
  }, [saveState]);

  const ordered = [...cabinets].sort(readingOrder);
  const selected = cabinets.find((c) => c.id === selectedCabinetId) ?? null;

  return (
    <aside
      aria-label="Design panel"
      className={`relative z-20 flex h-full shrink-0 border-l border-line bg-surface-muted transition-[width] duration-200 ${
        isCollapsed ? 'w-0' : 'w-[20rem] min-[1440px]:w-[22rem]'
      }`}
    >
      <button
        type="button"
        onClick={onToggleCollapse}
        aria-expanded={!isCollapsed}
        aria-label={isCollapsed ? 'Show the design panel' : 'Hide the design panel'}
        title={isCollapsed ? 'Show the design panel' : 'Hide the design panel'}
        className="absolute top-3 -left-10 z-30 flex h-10 w-10 cursor-pointer items-center justify-center rounded-l-xl border border-r-0 border-line bg-surface-muted text-ink-muted hover:text-ink"
      >
        {isCollapsed ? <ChevronLeft className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
      </button>

      {!isCollapsed && (
        <div className="flex min-w-0 flex-1 flex-col">
          <div role="tablist" aria-label="Design panel" className="grid grid-cols-4 gap-1 border-b border-line p-2">
            {TABS.map((t) => {
              const active = t.value === tab;
              return (
                <button
                  key={t.value}
                  type="button"
                  role="tab"
                  id={`tab-${t.value}`}
                  aria-selected={active}
                  aria-controls={`panel-${t.value}`}
                  onClick={() => onSelectTab(t.value)}
                  className={`flex min-h-10 cursor-pointer flex-col items-center justify-center gap-0.5 rounded-lg text-xs font-semibold transition-colors ${
                    active ? 'bg-espresso text-surface-muted' : 'text-ink-muted hover:bg-surface hover:text-ink'
                  }`}
                >
                  {t.icon}
                  {t.label}
                </button>
              );
            })}
          </div>

          <div
            role="tabpanel"
            id={`panel-${tab}`}
            aria-labelledby={`tab-${tab}`}
            className="min-h-0 flex-1 space-y-6 overflow-y-auto p-4"
          >
            {tab === 'room' && (
              <>
                <section className="space-y-2">
                  <SectionLabel>Room shape</SectionLabel>
                  <SegmentedControl label="Room shape" options={SHAPE_OPTIONS} value={roomShape} onChange={onSelectShape} className="w-full justify-between" />
                </section>
                <section className="space-y-3">
                  <SectionLabel>Sizes</SectionLabel>
                  <MmField label="Main wall width" value={wallWidthMm} range={RANGES.width} onChange={onChangeWallWidth} />
                  <MmField label="Ceiling height" value={wallHeightMm} range={RANGES.height} onChange={onChangeWallHeight} />
                  {roomShape === 'lShape' && (
                    <MmField label="Side wall length" value={returnMm} range={RANGES.ret} onChange={onChangeReturn} />
                  )}
                  <p className="text-xs text-ink-muted">
                    Windows and doors come from the sales app's measurements and show on the main wall.
                  </p>
                </section>
              </>
            )}

            {tab === 'finish' && (
              <>
                <section className="space-y-2">
                  <SectionLabel>Finish</SectionLabel>
                  <div className="space-y-2">
                    {FINISHES.map((item) => {
                      const active = finish === item.value;
                      return (
                        <button
                          key={item.value}
                          type="button"
                          aria-pressed={active}
                          onClick={() => onSelectFinish(item.value)}
                          className={`flex w-full cursor-pointer items-center gap-3 rounded-xl border p-3 text-left transition-colors ${
                            active ? 'border-clay bg-surface ring-1 ring-clay' : 'border-line bg-surface hover:border-line-strong'
                          }`}
                        >
                          <span aria-hidden className="h-7 w-7 shrink-0 rounded-full border border-line" style={{ background: item.swatch }} />
                          <span className="min-w-0 flex-1">
                            <span className="block text-[14px] font-semibold text-ink">{styleNames[item.value] ?? item.value}</span>
                            <span className="block text-xs text-ink-muted">{item.blurb}</span>
                          </span>
                          <span className="text-xs text-ink-muted tabular-nums">
                            ×{(styleMultipliers[item.value] ?? 1).toFixed(2)}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </section>

                <section className="space-y-2">
                  <SectionLabel>Door style</SectionLabel>
                  <SegmentedControl label="Door style" options={DOOR_OPTIONS} value={doorStyle} onChange={onSelectDoorStyle} className="w-full justify-between" />
                  <p className="text-xs text-ink-muted">For the picture only: the quote doesn't price door styles.</p>
                </section>

                <section className="space-y-2">
                  <SectionLabel>Benchtop</SectionLabel>
                  <p className="text-xs text-ink-muted">
                    {benchtopMetres > 0
                      ? `${benchtopMetres.toFixed(2)} m of worktop`
                      : 'Add base cabinets to measure the worktop.'}
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
                          className={`flex w-full cursor-pointer items-center gap-3 rounded-xl border p-3 text-left transition-colors ${
                            active ? 'border-clay bg-surface ring-1 ring-clay' : 'border-line bg-surface hover:border-line-strong'
                          }`}
                        >
                          <span className="min-w-0 flex-1">
                            <span className="block text-[14px] font-semibold text-ink">{benchtopNames[key] ?? key}</span>
                            <span className="block text-xs text-ink-muted">{formatMyr(rate)} per metre</span>
                          </span>
                          <span className="text-[13px] font-semibold text-ink tabular-nums">
                            {benchtopMetres > 0 ? `+${formatMyr(rate * benchtopMetres)}` : '—'}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                  {benchtopMaterial && (
                    <ActionButton variant="ghost" onClick={() => onSelectBenchtop(null)}>
                      No benchtop in this quote
                    </ActionButton>
                  )}
                </section>
              </>
            )}

            {tab === 'cabinets' && (
              <>
                {selected && (
                  <section className="space-y-3 rounded-xl border border-line bg-surface p-3" aria-label="Selected cabinet">
                    <div>
                      <p className="text-[15px] font-semibold text-ink">{selected.label}</p>
                      <p className="text-xs text-ink-muted">{positionLabel(selected)}</p>
                    </div>
                    <dl className="grid grid-cols-3 gap-2 text-center">
                      {[
                        ['Width', selected.width],
                        ['Height', selected.height],
                        ['Depth', selected.depth],
                      ].map(([label, v]) => (
                        <div key={label as string} className="rounded-lg bg-surface-muted py-1.5">
                          <dt className="text-xs text-ink-muted">{label}</dt>
                          <dd className="text-[13px] font-semibold text-ink tabular-nums">{Math.round((v as number) * 1000)} mm</dd>
                        </div>
                      ))}
                    </dl>
                    <div className="flex gap-2">
                      <ActionButton onClick={() => onNudgeCabinet(-1)} icon={<ArrowLeft className="h-4 w-4" aria-hidden />} className="flex-1" title="Move 50 mm (← key)">
                        50 mm
                      </ActionButton>
                      <ActionButton onClick={() => onNudgeCabinet(1)} icon={<ArrowRight className="h-4 w-4" aria-hidden />} className="flex-1" title="Move 50 mm (→ key)">
                        50 mm
                      </ActionButton>
                      <ActionButton
                        variant="danger"
                        onClick={() => onDeleteCabinet(selected.id)}
                        aria-label={`Remove ${selected.label}`}
                        title={`Remove ${selected.label} (Delete key)`}
                        icon={<Trash2 className="h-4 w-4" aria-hidden />}
                      />
                    </div>
                  </section>
                )}

                <section className="space-y-2">
                  <SectionLabel>All cabinets ({cabinets.length})</SectionLabel>
                  {ordered.length === 0 ? (
                    <p className="text-[13px] text-ink-muted">No cabinets yet. Add one from the bar above the view.</p>
                  ) : (
                    <ul className="space-y-1">
                      {ordered.map((c) => {
                        const active = c.id === selectedCabinetId;
                        return (
                          <li key={c.id}>
                            <button
                              type="button"
                              aria-pressed={active}
                              onClick={() => onSelectCabinet(c.id)}
                              className={`flex min-h-10 w-full cursor-pointer items-center justify-between gap-2 rounded-lg px-3 text-left text-[13px] transition-colors ${
                                active ? 'bg-espresso text-surface-muted' : 'text-ink hover:bg-surface'
                              }`}
                            >
                              <span className="font-medium">{c.label}</span>
                              <span className={`text-xs ${active ? 'opacity-90' : 'text-ink-muted'}`}>
                                {c.run === 'return' ? 'Side wall' : c.isWallMounted ? 'Wall' : 'Floor'} ·{' '}
                                {Math.round(c.x * 1000)} mm
                              </span>
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  )}
                </section>
              </>
            )}

            {tab === 'price' && (
              <section className="space-y-3">
                <SectionLabel>Price</SectionLabel>
                <div className="rounded-xl border border-line bg-surface p-3">
                  <ul className="space-y-2">
                    {totals.lineItems.map((line) => (
                      <li key={line.description} className="flex justify-between gap-3 text-[13px]">
                        <span className="min-w-0 text-ink">
                          {line.description}
                          {line.qty > 1 && (
                            <span className="block text-xs text-ink-muted">
                              {line.qty} × {formatMyr(line.unit_price)}
                            </span>
                          )}
                        </span>
                        <span className="shrink-0 text-ink tabular-nums">{formatMyr(line.total)}</span>
                      </li>
                    ))}
                    {totals.lineItems.length === 0 && <li className="text-[13px] text-ink-muted">No cabinets yet.</li>}
                  </ul>
                  <dl className="mt-3 space-y-1 border-t border-line pt-3 text-[13px]">
                    <div className="flex justify-between">
                      <dt className="text-ink-soft">Subtotal</dt>
                      <dd className="text-ink tabular-nums">{formatMyr(totals.subtotal)}</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-ink-soft">SST</dt>
                      <dd className="text-ink tabular-nums">{formatMyr(totals.gst)}</dd>
                    </div>
                    <div className="flex items-baseline justify-between pt-1">
                      <dt className="font-semibold text-ink">Total incl. SST</dt>
                      <dd className="text-[17px] font-bold text-ink tabular-nums">{formatMyr(totals.total)}</dd>
                    </div>
                  </dl>
                </div>

                <ActionButton
                  variant="primary"
                  className="w-full"
                  onClick={onSaveRevisions}
                  disabled={saveState === 'saving'}
                  icon={<CheckCircle2 className="h-4 w-4" aria-hidden />}
                >
                  {saveState === 'saving' ? 'Saving…' : 'Save changes'}
                </ActionButton>
                <p role="status" className="min-h-5 text-xs">
                  {saveState === 'saved' && <span className="text-sage">Saved to {quoteId}. The sales app sees it on its next refresh.</span>}
                  {saveState === 'error' && (
                    <span className="flex items-start gap-1.5 text-danger">
                      <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
                      {saveError ?? "Couldn't save. Try again."}
                    </span>
                  )}
                </p>

                <LinkButton href={`/pdf/${quoteId}`} target="_blank" rel="noreferrer" className="w-full" icon={<FileText className="h-4 w-4" aria-hidden />}>
                  Open PDF proposal
                </LinkButton>
                <div className="grid grid-cols-2 gap-2">
                  <LinkButton href={`/api/export/${quoteId}/dxf`} icon={<Download className="h-4 w-4" aria-hidden />}>
                    CAD (DXF)
                  </LinkButton>
                  <LinkButton href={`/api/export/${quoteId}/cutlist`} icon={<Download className="h-4 w-4" aria-hidden />}>
                    Cut list
                  </LinkButton>
                </div>
              </section>
            )}
          </div>
        </div>
      )}
    </aside>
  );
};
