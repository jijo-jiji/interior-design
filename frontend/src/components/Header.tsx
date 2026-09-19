import React from 'react';
import {
  Sun,
  Moon,
  Box,
  Compass,
  RefreshCw,
  ChevronDown,
  FolderKanban,
  Factory,
  CloudOff,
} from 'lucide-react';
import type { CameraView } from '../canvas/SceneCanvas';
import { SegmentedControl } from './ui';

interface HeaderProps {
  roomShape: string;
  onSelectShape: (shape: string) => void;
  cameraView: CameraView;
  onSelectCameraView: (view: CameraView) => void;
  lightingMood: 'day' | 'evening';
  onToggleMood: () => void;
  quoteId: string;
  clientName: string;
  onSync: () => void;
  isSyncing: boolean;
  isOffline: boolean;
  onOpenPipeline: () => void;
}

const SHAPE_OPTIONS = [
  { value: 'singleWall', label: 'Single Wall' },
  { value: 'lShape', label: 'L-Shape' },
  { value: 'galley', label: 'Galley' },
];

const VIEW_OPTIONS: { value: CameraView; label: string }[] = [
  { value: 'orbit', label: '3D Orbit' },
  { value: 'top', label: 'Plan' },
  { value: 'front', label: 'Elevation' },
];

export const Header: React.FC<HeaderProps> = ({
  roomShape,
  onSelectShape,
  cameraView,
  onSelectCameraView,
  lightingMood,
  onToggleMood,
  quoteId,
  clientName,
  onSync,
  isSyncing,
  isOffline,
  onOpenPipeline,
}) => {
  return (
    <header className="z-30 flex flex-wrap items-center justify-between gap-x-6 gap-y-2 border-b border-line bg-surface-muted px-4 py-2.5">
      {/* ── Identity & active project ─────────────────────────────────── */}
      <div className="flex min-w-0 items-center gap-3">
        <div className="flex items-center gap-2.5">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-clay-soft text-espresso">
            <Box className="h-5 w-5" strokeWidth={1.8} />
          </span>
          <span className="hidden min-w-0 leading-tight sm:block">
            <span className="block truncate text-[13px] font-semibold tracking-wide text-ink">
              Atelier Architekt
            </span>
            <span className="block truncate font-mono text-[10px] uppercase tracking-wider text-ink-muted">
              Joinery Workbench
            </span>
          </span>
        </div>

        <button
          type="button"
          onClick={onOpenPipeline}
          title="Switch project"
          className="flex min-w-0 cursor-pointer items-center gap-2 rounded-xl border border-line bg-surface px-3 py-1.5 text-[13px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-surface-muted"
        >
          <FolderKanban className="h-4 w-4 shrink-0 text-clay" />
          <span className="max-w-[10rem] truncate">{clientName || 'Select project'}</span>
          {quoteId && (
            <span className="hidden shrink-0 font-mono text-[11px] text-ink-muted lg:inline">
              {quoteId}
            </span>
          )}
          <ChevronDown className="h-4 w-4 shrink-0 text-ink-muted" />
        </button>

        {isOffline && (
          <span
            className="flex shrink-0 items-center gap-1.5 rounded-lg bg-clay-tint px-2 py-1 text-[11px] font-medium text-clay"
            title="The studio could not reach the backend. Showing demo data; saving is unavailable."
          >
            <CloudOff className="h-3.5 w-3.5" />
            <span className="hidden md:inline">Backend offline</span>
          </span>
        )}
      </div>

      {/* ── Layout, camera & lighting ─────────────────────────────────── */}
      <div className="flex flex-wrap items-center gap-2">
        <SegmentedControl
          label="Room layout"
          options={SHAPE_OPTIONS}
          value={roomShape}
          onChange={onSelectShape}
        />
        <SegmentedControl
          label="Camera view"
          options={VIEW_OPTIONS}
          value={cameraView}
          onChange={onSelectCameraView}
        />
        <button
          type="button"
          onClick={onToggleMood}
          aria-pressed={lightingMood === 'evening'}
          title="Toggle daylight / evening lighting"
          className="flex cursor-pointer items-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 text-[13px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-surface-muted"
        >
          {lightingMood === 'day' ? (
            <Sun className="h-4 w-4 text-clay" />
          ) : (
            <Moon className="h-4 w-4 text-ink-soft" />
          )}
          <span className="hidden sm:inline">{lightingMood === 'day' ? 'Daylight' : 'Evening'}</span>
        </button>
      </div>

      {/* ── Handover links ────────────────────────────────────────────── */}
      {/* ml-auto keeps this group on the right even when the header wraps. */}
      <div className="ml-auto flex items-center gap-2">
        <a
          href={`/portal/?id=${quoteId}`}
          target="_blank"
          rel="noreferrer"
          aria-label="Open the client 3D portal in a new tab"
          className="flex items-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 text-[13px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-surface-muted"
        >
          <Compass className="h-4 w-4 text-clay" />
          <span className="hidden lg:inline">Client portal</span>
        </a>

        <a
          href={`/studio/factory.html?id=${quoteId}`}
          target="_blank"
          rel="noreferrer"
          aria-label="Open the factory CNC handover sheet in a new tab"
          className="flex items-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 text-[13px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-surface-muted"
        >
          <Factory className="h-4 w-4 text-clay" />
          <span className="hidden lg:inline">Factory CNC</span>
        </a>

        <button
          type="button"
          onClick={onSync}
          disabled={isSyncing}
          aria-label="Refresh the consultation pipeline"
          title="Refresh the consultation pipeline"
          className="cursor-pointer rounded-xl border border-line bg-surface p-2 text-ink-muted transition-colors hover:border-line-strong hover:text-ink disabled:opacity-50"
        >
          <RefreshCw className={`h-4 w-4 ${isSyncing ? 'animate-spin' : ''}`} />
        </button>
      </div>
    </header>
  );
};
