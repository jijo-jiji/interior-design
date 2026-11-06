import React from 'react';
import { Sun, Moon, Compass, RefreshCw, ChevronDown, Users, Factory, CloudOff, Tags } from 'lucide-react';
import type { CameraView } from '../canvas/SceneCanvas';
import type { RoomView } from '../canvas/floorPlan';
import { SegmentedControl } from './ui';

interface HeaderProps {
  cameraView: CameraView;
  onSelectCameraView: (view: CameraView) => void;
  /** Only for a room read off a floor plan. */
  hasFloorPlan: boolean;
  roomView: RoomView;
  onSelectRoomView: (view: RoomView) => void;
  lightingMood: 'day' | 'evening';
  onToggleMood: () => void;
  quoteId: string;
  clientName: string;
  onSync: () => void;
  isSyncing: boolean;
  isOffline: boolean;
  onOpenPipeline: () => void;
  onOpenPriceList: () => void;
}

const VIEW_OPTIONS: { value: CameraView; label: string; title: string }[] = [
  { value: 'orbit', label: '3D', title: '3D view (drag to look around)' },
  { value: 'top', label: 'Plan', title: 'Plan: from above, with sizes' },
  { value: 'front', label: 'Elevation', title: 'Elevation: the main wall straight on, with heights' },
];

const ROOM_OPTIONS: { value: RoomView; label: string; title: string }[] = [
  { value: 'kitchen', label: 'Kitchen', title: 'The kitchen alone' },
  { value: 'room', label: 'Room', title: 'The kitchen and the walls around it, from the floor plan' },
  { value: 'house', label: 'House', title: 'The whole floor plan, with its walls raised' },
];

/** Secondary actions show their words from 1440px; below that, icon only
 *  (named for screen readers and in a tooltip). */
const actionClass =
  'flex min-h-10 items-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 text-[13px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-surface-muted';
const wideLabel = 'hidden min-[1440px]:inline';

export const Header: React.FC<HeaderProps> = ({
  cameraView,
  onSelectCameraView,
  hasFloorPlan,
  roomView,
  onSelectRoomView,
  lightingMood,
  onToggleMood,
  quoteId,
  clientName,
  onSync,
  isSyncing,
  isOffline,
  onOpenPipeline,
  onOpenPriceList,
}) => {
  return (
    <header className="z-30 flex items-center gap-3 border-b border-line bg-surface-muted px-4 py-2">
      {/* ── Brand and client ──────────────────────────────────────────── */}
      <div className="flex min-w-0 shrink items-center gap-3">
        <div className="flex shrink-0 items-baseline gap-1.5 leading-none">
          <span className="text-[15px] font-bold tracking-tight text-ink">SS Love</span>
          <span className="text-[13px] font-medium text-ink-muted">Studio</span>
        </div>

        <button
          type="button"
          onClick={onOpenPipeline}
          aria-label={`Client: ${clientName || 'none chosen'}. Open another client`}
          title="Open another client"
          className="flex min-h-10 min-w-0 cursor-pointer items-center gap-2 rounded-xl border border-line bg-surface px-3 py-1.5 text-[13px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-surface-muted"
        >
          <Users className="h-4 w-4 shrink-0 text-clay" aria-hidden />
          <span className="max-w-[12rem] truncate">{clientName || 'Choose a client'}</span>
          {quoteId && (
            <span className="hidden shrink-0 font-mono text-xs text-ink-muted min-[1440px]:inline">
              {quoteId}
            </span>
          )}
          <ChevronDown className="h-4 w-4 shrink-0 text-ink-muted" aria-hidden />
        </button>

        {isOffline && (
          <span
            className="flex shrink-0 items-center gap-1.5 rounded-lg bg-clay-tint px-2 py-1 text-xs font-medium text-clay-ink"
            title="Can't reach the office server. Showing sample data; saving is off."
          >
            <CloudOff className="h-3.5 w-3.5" aria-hidden />
            Offline
          </span>
        )}
      </div>

      {/* ── View ──────────────────────────────────────────────────────── */}
      <div className="mx-auto flex shrink-0 items-center gap-2">
        <SegmentedControl label="View" options={VIEW_OPTIONS} value={cameraView} onChange={onSelectCameraView} />
        {hasFloorPlan && (
          <SegmentedControl label="Show" options={ROOM_OPTIONS} value={roomView} onChange={onSelectRoomView} />
        )}
        <button
          type="button"
          onClick={onToggleMood}
          aria-pressed={lightingMood === 'evening'}
          aria-label={lightingMood === 'day' ? 'Switch to evening light' : 'Switch to daylight'}
          title={lightingMood === 'day' ? 'Switch to evening light' : 'Switch to daylight'}
          className={actionClass}
        >
          {lightingMood === 'day' ? (
            <Sun className="h-4 w-4 text-clay" aria-hidden />
          ) : (
            <Moon className="h-4 w-4 text-ink-soft" aria-hidden />
          )}
          <span className={wideLabel}>{lightingMood === 'day' ? 'Daylight' : 'Evening'}</span>
        </button>
      </div>

      {/* ── Handover ──────────────────────────────────────────────────── */}
      <div className="flex shrink-0 items-center gap-2">
        <button
          type="button"
          onClick={onOpenPriceList}
          aria-label="Price list: prices, sizes and rules"
          title="Price list: prices, sizes and rules"
          className={`${actionClass} cursor-pointer`}
        >
          <Tags className="h-4 w-4 text-clay" aria-hidden />
          <span className={wideLabel}>Price list</span>
        </button>
        <a
          href={`/portal/?id=${quoteId}`}
          target="_blank"
          rel="noreferrer"
          aria-label="Client's 3D page (opens in a new tab)"
          title="Client's 3D page (opens in a new tab)"
          className={actionClass}
        >
          <Compass className="h-4 w-4 text-clay" aria-hidden />
          <span className={wideLabel}>Client page</span>
        </a>
        <a
          href={`/studio/factory.html?id=${quoteId}`}
          target="_blank"
          rel="noreferrer"
          aria-label="Factory sheet (opens in a new tab)"
          title="Factory sheet (opens in a new tab)"
          className={actionClass}
        >
          <Factory className="h-4 w-4 text-clay" aria-hidden />
          <span className={wideLabel}>Factory sheet</span>
        </a>
        <button
          type="button"
          onClick={onSync}
          disabled={isSyncing}
          aria-label="Refresh clients from the office"
          title="Refresh clients from the office"
          className={`${actionClass} cursor-pointer text-ink-muted disabled:opacity-50`}
        >
          <RefreshCw className={`h-4 w-4 ${isSyncing ? 'animate-spin' : ''}`} aria-hidden />
        </button>
      </div>
    </header>
  );
};
