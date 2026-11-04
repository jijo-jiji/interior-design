import React, { useEffect, useState } from 'react';
import { X, Search, Sliders, CheckCircle2, Clock, FolderKanban } from 'lucide-react';
import { formatMyr } from '../pricing';
import { SectionLabel } from './ui';

export interface ProjectItem {
  id: string;
  quote_id?: string;
  client_name: string;
  salesperson_id?: string;
  total_price: number;
  subtotal?: number;
  status?: string;
  deposit_paid?: number;
  style?: string;
  style_archetype?: string;
  created_at?: string;
  wall: {
    width_mm: number;
    height_mm: number;
    depth_mm: number;
    shape: string;
    return_mm?: number;
  };
  cabinets?: any[];
  placed_cabinets?: any[];
  obstacles?: any[];
  benchtop_material?: string | null;
}

interface ProjectPipelineDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  projects: ProjectItem[];
  activeProjectId: string;
  onSelectProject: (proj: ProjectItem) => void;
  wallWidthMm: number;
  wallHeightMm: number;
  onChangeWallWidth: (w: number) => void;
  onChangeWallHeight: (h: number) => void;
}

const WALL_WIDTH_RANGE = { min: 1200, max: 8000 };
const WALL_HEIGHT_RANGE = { min: 2000, max: 3600 };

const clamp = (value: number, { min, max }: { min: number; max: number }) =>
  Math.min(max, Math.max(min, value));

const formatDate = (iso?: string) => {
  if (!iso) return null;
  const date = new Date(iso);
  return Number.isNaN(date.getTime())
    ? null
    : date.toLocaleDateString('en-MY', { day: 'numeric', month: 'short', year: '2-digit' });
};

export const ProjectPipelineDrawer: React.FC<ProjectPipelineDrawerProps> = ({
  isOpen,
  onClose,
  projects,
  activeProjectId,
  onSelectProject,
  wallWidthMm,
  wallHeightMm,
  onChangeWallWidth,
  onChangeWallHeight,
}) => {
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    if (!isOpen) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const query = searchQuery.trim().toLowerCase();
  const filteredProjects = projects.filter((p) => {
    if (!query) return true;
    const haystack = [
      p.client_name ?? '',
      p.quote_id ?? p.id ?? '',
      p.style_archetype ?? p.style ?? '',
    ]
      .join(' ')
      .toLowerCase();
    return haystack.includes(query);
  });

  return (
    <div className="fixed inset-0 z-40 flex" role="dialog" aria-modal="true" aria-label="Consultation pipeline">
      <div className="fixed inset-0 bg-espresso/25 backdrop-blur-[2px]" onClick={onClose} />

      <div className="relative z-50 flex h-full w-[23rem] max-w-[88vw] flex-col border-r border-line bg-surface-muted shadow-2xl">
        {/* ── Header ────────────────────────────────────────────────── */}
        <div className="flex items-center justify-between gap-2 border-b border-line bg-surface px-4 py-3">
          <div className="flex min-w-0 items-center gap-2">
            <FolderKanban className="h-4 w-4 shrink-0 text-clay" />
            <h2 className="truncate text-[13px] font-semibold uppercase tracking-wide text-ink">
              Consultation pipeline
            </h2>
            <span className="shrink-0 rounded-full bg-sand px-2 py-0.5 font-mono text-[11px] text-ink">
              {projects.length}
            </span>
          </div>

          <button
            type="button"
            onClick={onClose}
            aria-label="Close the pipeline drawer"
            className="cursor-pointer rounded-lg p-1.5 text-ink-muted transition-colors hover:bg-surface-sunken hover:text-ink"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* ── Search ────────────────────────────────────────────────── */}
        <div className="border-b border-line px-4 py-3">
          <div className="relative">
            <Search className="absolute top-2.5 left-3 h-4 w-4 text-ink-muted" />
            <input
              type="search"
              placeholder="Filter by client, quote ID or style"
              aria-label="Filter consultations"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full rounded-xl border border-line bg-surface py-2 pr-3 pl-9 text-[13px] text-ink placeholder-ink-muted focus:border-clay focus:outline-none"
            />
          </div>
        </div>

        {/* ── Deal cards ────────────────────────────────────────────── */}
        <div className="min-h-0 flex-1 space-y-2 overflow-y-auto p-3">
          {filteredProjects.length === 0 && (
            <p className="px-1 py-6 text-center text-[13px] text-ink-muted">
              {projects.length === 0
                ? 'No consultations yet. Quotes sent from the mobile app appear here.'
                : `No consultation matches “${searchQuery.trim()}”.`}
            </p>
          )}

          {filteredProjects.map((p) => {
            const projId = p.quote_id || p.id;
            const isSelected = projId === activeProjectId;
            const isPriority =
              (p.deposit_paid ?? 0) > 0 ||
              p.status === 'deposit_paid' ||
              p.status === 'priority_locked';
            const moduleCount = (p.cabinets || p.placed_cabinets || []).length;
            const styleName = p.style_archetype || p.style || 'japandi';
            const created = formatDate(p.created_at);

            return (
              <button
                key={projId}
                type="button"
                aria-current={isSelected}
                onClick={() => {
                  onSelectProject(p);
                  onClose();
                }}
                className={`w-full cursor-pointer rounded-xl border p-3 text-left transition-colors ${
                  isSelected
                    ? 'border-clay bg-surface ring-1 ring-clay'
                    : 'border-line bg-surface hover:border-line-strong'
                }`}
              >
                <div className="mb-1.5 flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <h3 className="truncate text-[13px] font-semibold text-ink">
                      {p.client_name || 'Walk-in consultation'}
                    </h3>
                    <p className="truncate text-xs text-ink-muted">
                      <span className="capitalize">{styleName}</span> · {moduleCount} module
                      {moduleCount === 1 ? '' : 's'}
                      {created && ` · ${created}`}
                    </p>
                  </div>
                  <span className="shrink-0 font-mono text-[13px] font-semibold text-ink">
                    {formatMyr(p.total_price || p.subtotal || 0)}
                  </span>
                </div>

                <div className="flex items-center justify-between gap-2 border-t border-line pt-1.5">
                  <span className="truncate font-mono text-[11px] text-ink-muted">{projId}</span>
                  <span
                    className={`inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium ${
                      isPriority ? 'bg-sage-tint text-sage' : 'bg-surface-sunken text-ink-muted'
                    }`}
                  >
                    {isPriority ? (
                      <>
                        <CheckCircle2 className="h-3 w-3" />
                        Priority locked
                      </>
                    ) : (
                      <>
                        <Clock className="h-3 w-3" />
                        Estimate
                      </>
                    )}
                  </span>
                </div>
              </button>
            );
          })}
        </div>

        {/* ── Room bounds ───────────────────────────────────────────── */}
        <div className="border-t border-line bg-surface px-4 py-3">
          <SectionLabel className="mb-2 flex items-center gap-1.5">
            <Sliders className="h-3.5 w-3.5" />
            Room architectural bounds
          </SectionLabel>

          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className="mb-1 block text-[11px] uppercase tracking-wide text-ink-muted">
                Wall width (mm)
              </span>
              <input
                type="number"
                step={100}
                min={WALL_WIDTH_RANGE.min}
                max={WALL_WIDTH_RANGE.max}
                value={wallWidthMm}
                onChange={(e) => onChangeWallWidth(Number(e.target.value))}
                onBlur={(e) => onChangeWallWidth(clamp(Number(e.target.value), WALL_WIDTH_RANGE))}
                className="w-full rounded-lg border border-line bg-surface px-3 py-1.5 font-mono text-[13px] text-ink focus:border-clay focus:outline-none"
              />
            </label>

            <label className="block">
              <span className="mb-1 block text-[11px] uppercase tracking-wide text-ink-muted">
                Ceiling height (mm)
              </span>
              <input
                type="number"
                step={50}
                min={WALL_HEIGHT_RANGE.min}
                max={WALL_HEIGHT_RANGE.max}
                value={wallHeightMm}
                onChange={(e) => onChangeWallHeight(Number(e.target.value))}
                onBlur={(e) => onChangeWallHeight(clamp(Number(e.target.value), WALL_HEIGHT_RANGE))}
                className="w-full rounded-lg border border-line bg-surface px-3 py-1.5 font-mono text-[13px] text-ink focus:border-clay focus:outline-none"
              />
            </label>
          </div>
        </div>
      </div>
    </div>
  );
};
