import React, { useEffect, useRef, useState } from 'react';
import { ChevronDown, Maximize, Plus, Undo2 } from 'lucide-react';
import type { ModuleType } from '../layout/model';
import { formatMyr } from '../pricing';

interface StudioToolbarProps {
  onAddModule: (type: ModuleType) => void;
  onUndo: () => void;
  canUndo: boolean;
  onDeleteSelected: () => void;
  onNudgeSelected: (dir: -1 | 1) => void;
  hasSelected: boolean;
  /** Shortcuts are off while a drawer or dialog owns the screen. */
  hotkeysEnabled: boolean;
  onFit: () => void;
  total: number;
  onShowPrice: () => void;
}

const CABINETS: { type: ModuleType; label: string; hotkey: string }[] = [
  { type: 'base_800', label: 'Base 800', hotkey: '1' },
  { type: 'base_600', label: 'Base 600', hotkey: '2' },
  { type: 'wall_600', label: 'Wall 600', hotkey: '3' },
  { type: 'tall_600', label: 'Tall 600', hotkey: '4' },
];

/** Priced as joinery: the cabinetry, cutouts and services for each unit. */
const APPLIANCES: { type: ModuleType; label: string; hotkey: string }[] = [
  { type: 'sink_600', label: 'Sink', hotkey: '5' },
  { type: 'cooktop_600', label: 'Cooktop', hotkey: '6' },
  { type: 'dishwasher_600', label: 'Dishwasher', hotkey: '7' },
  { type: 'oven_tower_600', label: 'Oven tower', hotkey: '8' },
  { type: 'fridge_recess_700', label: 'Fridge recess', hotkey: '9' },
  { type: 'rangehood_900', label: 'Rangehood', hotkey: '0' },
];

const ALL = [...CABINETS, ...APPLIANCES];

const Key: React.FC<{ k: string }> = ({ k }) => (
  <kbd
    aria-hidden
    className="flex h-5 min-w-5 items-center justify-center rounded bg-surface-sunken px-1 font-mono text-xs font-semibold text-ink-soft"
  >
    {k}
  </kbd>
);

const buttonClass =
  'flex min-h-10 cursor-pointer items-center gap-2 rounded-xl border border-line bg-surface px-3 py-1.5 text-[13px] font-medium whitespace-nowrap text-ink transition-colors hover:border-line-strong hover:bg-surface-muted';

export const StudioToolbar: React.FC<StudioToolbarProps> = ({
  onAddModule,
  onUndo,
  canUndo,
  onDeleteSelected,
  onNudgeSelected,
  hasSelected,
  hotkeysEnabled,
  onFit,
  total,
  onShowPrice,
}) => {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const menuButtonRef = useRef<HTMLButtonElement>(null);

  // Keyboard shortcuts.
  useEffect(() => {
    if (!hotkeysEnabled) return;
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      if (t && (['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName) || t.isContentEditable)) return;
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        onUndo();
        return;
      }
      if (e.metaKey || e.ctrlKey || e.altKey) return; // Ctrl+1 etc. belong to the browser
      const item = ALL.find((m) => m.hotkey === e.key);
      if (item) {
        onAddModule(item.type);
        return;
      }
      if (!hasSelected) return;
      if (e.key === 'Delete' || e.key === 'Backspace') {
        e.preventDefault();
        onDeleteSelected();
      } else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        e.preventDefault();
        onNudgeSelected(e.key === 'ArrowLeft' ? -1 : 1);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onAddModule, onUndo, onDeleteSelected, onNudgeSelected, hasSelected, hotkeysEnabled]);

  // Appliance menu: closes on Escape (focus back to its button) or outside click.
  useEffect(() => {
    if (!menuOpen) return;
    const first = menuRef.current?.querySelector<HTMLButtonElement>('[role="menuitem"]');
    first?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setMenuOpen(false);
        menuButtonRef.current?.focus();
      }
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        const items = [...(menuRef.current?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]') ?? [])];
        const i = items.indexOf(document.activeElement as HTMLButtonElement);
        items[(i + (e.key === 'ArrowDown' ? 1 : items.length - 1)) % items.length]?.focus();
      }
    };
    const onDown = (e: PointerEvent) => {
      if (!menuRef.current?.contains(e.target as Node) && !menuButtonRef.current?.contains(e.target as Node)) {
        setMenuOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    window.addEventListener('pointerdown', onDown);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('pointerdown', onDown);
    };
  }, [menuOpen]);

  return (
    <div
      role="toolbar"
      aria-label="Add cabinets"
      className="z-20 flex items-center gap-2 border-b border-line bg-surface-muted px-4 py-2"
    >
      <span className="flex items-center gap-1 text-[13px] font-semibold text-ink-soft">
        <Plus className="h-4 w-4 text-clay" aria-hidden />
        Add
      </span>
      {CABINETS.map((m) => (
        <button
          key={m.type}
          type="button"
          onClick={() => onAddModule(m.type)}
          aria-keyshortcuts={m.hotkey}
          title={`Add ${m.label} (key ${m.hotkey})`}
          className={buttonClass}
        >
          <Key k={m.hotkey} />
          {m.label}
        </button>
      ))}

      <div className="relative">
        <button
          ref={menuButtonRef}
          type="button"
          aria-haspopup="menu"
          aria-expanded={menuOpen}
          onClick={() => setMenuOpen((v) => !v)}
          className={buttonClass}
        >
          Appliances
          <ChevronDown className="h-4 w-4 text-ink-muted" aria-hidden />
        </button>
        {menuOpen && (
          <div
            ref={menuRef}
            role="menu"
            aria-label="Appliances"
            className="floating-panel absolute top-full left-0 z-40 mt-1 w-60 rounded-xl border border-line p-1"
          >
            {APPLIANCES.map((m) => (
              <button
                key={m.type}
                type="button"
                role="menuitem"
                aria-keyshortcuts={m.hotkey}
                onClick={() => {
                  onAddModule(m.type);
                  setMenuOpen(false);
                }}
                className="flex min-h-10 w-full cursor-pointer items-center gap-2 rounded-lg px-2 text-left text-[13px] font-medium text-ink hover:bg-surface focus:bg-surface"
              >
                <Key k={m.hotkey} />
                {m.label}
              </button>
            ))}
            <p className="px-2 pt-1 pb-1.5 text-xs text-ink-muted">
              Price covers the cabinetry, cutouts and services, not the appliance.
            </p>
          </div>
        )}
      </div>

      <button
        type="button"
        onClick={onUndo}
        disabled={!canUndo}
        aria-label="Undo (Ctrl+Z)"
        title="Undo (Ctrl+Z)"
        className={`${buttonClass} disabled:cursor-not-allowed disabled:opacity-45`}
      >
        <Undo2 className="h-4 w-4" aria-hidden />
      </button>

      <button type="button" onClick={onFit} title="Show the whole kitchen" className={`${buttonClass} ml-auto`}>
        <Maximize className="h-4 w-4" aria-hidden />
        <span className="hidden min-[1366px]:inline">Fit to screen</span>
        <span className="sr-only min-[1366px]:hidden">Fit to screen</span>
      </button>

      {/* Always visible: the running total, opens the breakdown. */}
      <button
        type="button"
        onClick={onShowPrice}
        title="See the price breakdown"
        className="flex min-h-10 cursor-pointer items-baseline gap-2 rounded-xl bg-espresso px-3 py-1.5 whitespace-nowrap text-surface-muted hover:bg-espresso-deep"
      >
        <span className="text-xs font-medium opacity-90">Total incl. SST</span>
        <span className="text-[15px] font-semibold tabular-nums">{formatMyr(total)}</span>
      </button>
    </div>
  );
};
