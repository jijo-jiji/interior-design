import React, { useEffect, useState } from 'react';
import { X, Search, Users } from 'lucide-react';
import { formatMyr } from '../pricing';
import { STATUS_LABELS, statusOf } from '../layout/status';
import type { ProjectStatus } from '../layout/status';

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
  /** The floor plan the room was read from (see canvas/floorPlan.ts). */
  floor_plan?: unknown;
  /** The wall's finish from the sales app's wall card (see pricing.ts). */
  wall_finish?: unknown;
}

interface ProjectPipelineDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  projects: ProjectItem[];
  activeProjectId: string;
  onSelectProject: (proj: ProjectItem) => void;
}

const STATUS_STYLES: Record<ProjectStatus, string> = {
  draft: 'bg-surface-sunken text-ink-soft',
  quote: 'bg-clay-tint text-clay-ink',
  deposit: 'bg-sage-tint text-sage',
};

const FILTERS: { value: ProjectStatus | 'all'; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'draft', label: 'Drafts' },
  { value: 'quote', label: 'Quotes sent' },
  { value: 'deposit', label: 'Deposit paid' },
];

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
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [filter, setFilter] = useState<ProjectStatus | 'all'>('all');

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
    if (filter !== 'all' && statusOf(p) !== filter) return false;
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
    <div className="fixed inset-0 z-40 flex" role="dialog" aria-modal="true" aria-label="Clients">
      <div className="fixed inset-0 bg-espresso/25 backdrop-blur-[2px]" onClick={onClose} />

      <div className="relative z-50 flex h-full w-[23rem] max-w-[88vw] flex-col border-r border-line bg-surface-muted shadow-2xl">
        {/* ── Header ────────────────────────────────────────────────── */}
        <div className="flex items-center justify-between gap-2 border-b border-line bg-surface px-4 py-3">
          <div className="flex min-w-0 items-center gap-2">
            <Users className="h-4 w-4 shrink-0 text-clay" aria-hidden />
            <h2 className="truncate text-[15px] font-semibold text-ink">Clients</h2>
            <span className="shrink-0 rounded-full bg-sand px-2 py-0.5 text-xs font-medium text-ink">
              {projects.length}
            </span>
          </div>

          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="flex h-10 w-10 cursor-pointer items-center justify-center rounded-lg text-ink-muted transition-colors hover:bg-surface-sunken hover:text-ink"
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
              placeholder="Search name, quote number or style"
              aria-label="Search clients"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="min-h-10 w-full rounded-xl border border-line-strong bg-surface py-2 pr-3 pl-9 text-[14px] text-ink placeholder-ink-muted focus:border-clay focus:outline-none"
            />
          </div>
          <div role="group" aria-label="Show" className="mt-2 flex flex-wrap gap-1">
            {FILTERS.map((f) => (
              <button
                key={f.value}
                type="button"
                aria-pressed={filter === f.value}
                onClick={() => setFilter(f.value)}
                className={`min-h-8 cursor-pointer rounded-full px-3 text-xs font-medium ${
                  filter === f.value ? 'bg-espresso text-surface-muted' : 'bg-surface text-ink-soft hover:bg-surface-sunken'
                }`}
              >
                {f.label}
              </button>
            ))}
          </div>
        </div>

        {/* ── Deal cards ────────────────────────────────────────────── */}
        <div className="min-h-0 flex-1 space-y-2 overflow-y-auto p-3">
          {filteredProjects.length === 0 && (
            <p className="px-1 py-6 text-center text-[13px] text-ink-muted">
              {projects.length === 0
                ? 'No clients yet. Quotes sent from the sales app appear here.'
                : 'No client matches.'}
            </p>
          )}

          {filteredProjects.map((p) => {
            const projId = p.quote_id || p.id;
            const isSelected = projId === activeProjectId;
            const status = statusOf(p);
            const moduleCount = (p.cabinets || p.placed_cabinets || []).filter(
              (c: { kind?: string }) => c?.kind !== 'filler',
            ).length;
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
                      {p.client_name || 'Unnamed client'}
                    </h3>
                    <p className="truncate text-xs text-ink-muted">
                      <span className="capitalize">{styleName}</span> · {moduleCount} cabinet
                      {moduleCount === 1 ? '' : 's'}
                      {created && ` · ${created}`}
                    </p>
                  </div>
                  <span className="shrink-0 text-[13px] font-semibold text-ink tabular-nums">
                    {formatMyr(p.total_price || p.subtotal || 0)}
                  </span>
                </div>

                <div className="flex items-center justify-between gap-2 border-t border-line pt-1.5">
                  <span className="truncate font-mono text-xs text-ink-muted">{projId}</span>
                  <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[status]}`}>
                    {STATUS_LABELS[status]}
                  </span>
                </div>
              </button>
            );
          })}
        </div>

      </div>
    </div>
  );
};
