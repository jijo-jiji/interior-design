import React, { useEffect } from 'react';
import { Plus, Undo2 } from 'lucide-react';

export type ModuleType =
  | 'base_800'
  | 'base_600'
  | 'wall_600'
  | 'tall_600'
  | 'sink_600'
  | 'cooktop_600'
  | 'dishwasher_600'
  | 'oven_tower_600'
  | 'fridge_recess_700'
  | 'rangehood_900';

interface JoineryModuleDockProps {
  onAddModule: (type: ModuleType) => void;
  onUndo: () => void;
  canUndo: boolean;
  onDeleteSelected: () => void;
  onNudgeSelected: (dir: -1 | 1) => void;
  hasSelected: boolean;
  /** Hotkeys are suspended while a drawer or modal owns the screen. */
  hotkeysEnabled: boolean;
}

const MODULES: { type: ModuleType; label: string; hotkey: string }[] = [
  { type: 'base_800', label: 'Base 800', hotkey: '1' },
  { type: 'base_600', label: 'Base 600', hotkey: '2' },
  { type: 'wall_600', label: 'Wall 600', hotkey: '3' },
  { type: 'tall_600', label: 'Tall 600', hotkey: '4' },
];

/** Appliance modules: the cabinetry, cutouts and services for each unit. */
const APPLIANCES: { type: ModuleType; label: string; hotkey: string }[] = [
  { type: 'sink_600', label: 'Sink', hotkey: '5' },
  { type: 'cooktop_600', label: 'Cooktop', hotkey: '6' },
  { type: 'dishwasher_600', label: 'Dishwasher', hotkey: '7' },
  { type: 'oven_tower_600', label: 'Oven', hotkey: '8' },
  { type: 'fridge_recess_700', label: 'Fridge', hotkey: '9' },
  { type: 'rangehood_900', label: 'Rangehood', hotkey: '0' },
];

const ALL_MODULES = [...MODULES, ...APPLIANCES];

export const JoineryModuleDock: React.FC<JoineryModuleDockProps> = ({
  onAddModule,
  onUndo,
  canUndo,
  onDeleteSelected,
  onNudgeSelected,
  hasSelected,
  hotkeysEnabled,
}) => {
  useEffect(() => {
    if (!hotkeysEnabled) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (target && (['INPUT', 'TEXTAREA'].includes(target.tagName) || target.isContentEditable)) {
        return;
      }

      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        onUndo();
        return;
      }

      // Bare keys only — Ctrl+1 etc. belong to the browser.
      if (e.metaKey || e.ctrlKey || e.altKey) return;

      const module = ALL_MODULES.find((m) => m.hotkey === e.key);
      if (module) {
        onAddModule(module.type);
        return;
      }

      if (!hasSelected) return;

      if (e.key === 'Delete' || e.key === 'Backspace') {
        e.preventDefault();
        onDeleteSelected();
      }
      if (e.key === 'ArrowLeft') {
        e.preventDefault();
        onNudgeSelected(-1);
      }
      if (e.key === 'ArrowRight') {
        e.preventDefault();
        onNudgeSelected(1);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onAddModule, onUndo, onDeleteSelected, onNudgeSelected, hasSelected, hotkeysEnabled]);

  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-5 z-20 flex justify-center px-4">
      <div className="floating-panel pointer-events-auto flex max-w-full flex-wrap items-center justify-center gap-2 rounded-2xl border border-line px-3 py-2">
        <span className="flex items-center gap-1.5 px-1 text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-muted">
          <Plus className="h-3.5 w-3.5 text-clay" />
          Joinery
        </span>

        {MODULES.map((module) => (
          <button
            key={module.type}
            type="button"
            onClick={() => onAddModule(module.type)}
            title={`Add ${module.label} — shortcut ${module.hotkey}`}
            className="flex cursor-pointer items-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 text-[13px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-surface-muted active:scale-95"
          >
            <span
              aria-hidden
              className="flex h-4.5 w-4.5 items-center justify-center rounded bg-surface-sunken font-mono text-[10px] font-bold text-ink"
            >
              {module.hotkey}
            </span>
            {module.label}
          </button>
        ))}

        {/* Appliances price like joinery — cabinetry, cutouts and services. */}
        <span className="flex items-center gap-1.5 border-l border-line pl-3 text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-muted">
          Appliances
        </span>

        {APPLIANCES.map((module) => (
          <button
            key={module.type}
            type="button"
            onClick={() => onAddModule(module.type)}
            title={`Add ${module.label} — shortcut ${module.hotkey}`}
            className="flex cursor-pointer items-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 text-[13px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-surface-muted active:scale-95"
          >
            <span
              aria-hidden
              className="flex h-4.5 w-4.5 items-center justify-center rounded bg-surface-sunken font-mono text-[10px] font-bold text-ink"
            >
              {module.hotkey}
            </span>
            {module.label}
          </button>
        ))}

        <div className="ml-1 border-l border-line pl-2">
          <button
            type="button"
            onClick={onUndo}
            disabled={!canUndo}
            aria-label="Undo last layout change"
            title="Undo (Ctrl+Z)"
            className={`flex items-center justify-center rounded-xl border p-2 transition-colors ${
              canUndo
                ? 'cursor-pointer border-line bg-surface text-ink hover:border-line-strong hover:bg-surface-muted active:scale-95'
                : 'cursor-not-allowed border-transparent text-ink-muted opacity-40'
            }`}
          >
            <Undo2 className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
};
