import React, { useEffect } from 'react';
import { Plus, Undo2 } from 'lucide-react';

interface JoineryModuleDockProps {
  onAddModule: (type: 'base_800' | 'base_600' | 'wall_600' | 'tall_600') => void;
  onUndo: () => void;
  canUndo: boolean;
  onDeleteSelected: () => void;
  onNudgeSelected: (dir: -1 | 1) => void;
  hasSelected: boolean;
}

export const JoineryModuleDock: React.FC<JoineryModuleDockProps> = ({
  onAddModule,
  onUndo,
  canUndo,
  onDeleteSelected,
  onNudgeSelected,
  hasSelected,
}) => {
  // Global hotkeys listener
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Ignore when inside input/textarea
      if (['INPUT', 'TEXTAREA'].includes((e.target as HTMLElement)?.tagName)) {
        return;
      }

      if (e.key === '1') onAddModule('base_800');
      if (e.key === '2') onAddModule('base_600');
      if (e.key === '3') onAddModule('wall_600');
      if (e.key === '4') onAddModule('tall_600');

      if ((e.key === 'Delete' || e.key === 'Backspace') && hasSelected) {
        e.preventDefault();
        onDeleteSelected();
      }

      if (e.key === 'ArrowLeft' && hasSelected) {
        e.preventDefault();
        onNudgeSelected(-1);
      }
      if (e.key === 'ArrowRight' && hasSelected) {
        e.preventDefault();
        onNudgeSelected(1);
      }

      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        onUndo();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onAddModule, onUndo, onDeleteSelected, onNudgeSelected, hasSelected]);

  return (
    <div className="absolute bottom-6 left-1/2 -translate-x-1/2 z-20 flex items-center gap-2.5 glass-panel px-3 py-2 rounded-2xl shadow-xl border border-[#DDD5CA] bg-[#FAF7F2]/95 backdrop-blur-xl">
      <span className="text-[11px] uppercase tracking-wider font-semibold text-[#8C725C] px-2 flex items-center gap-1.5">
        <Plus className="w-3.5 h-3.5 text-[#B2967D]" />
        <span>Joinery</span>
      </span>

      {/* Base 800 */}
      <button
        onClick={() => onAddModule('base_800')}
        className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-white border border-[#DDD5CA] hover:bg-[#FAF7F2] hover:border-[#B2967D] text-xs font-semibold text-[#2C2724] transition-all shadow-2xs cursor-pointer active:scale-95"
        title="Shortcut: Press 1"
      >
        <span className="w-4 h-4 rounded bg-[#EAE2D8] text-[10px] font-mono font-bold flex items-center justify-center text-[#2C2724]">
          1
        </span>
        <span>Base 800</span>
      </button>

      {/* Base 600 */}
      <button
        onClick={() => onAddModule('base_600')}
        className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-white border border-[#DDD5CA] hover:bg-[#FAF7F2] hover:border-[#B2967D] text-xs font-semibold text-[#2C2724] transition-all shadow-2xs cursor-pointer active:scale-95"
        title="Shortcut: Press 2"
      >
        <span className="w-4 h-4 rounded bg-[#EAE2D8] text-[10px] font-mono font-bold flex items-center justify-center text-[#2C2724]">
          2
        </span>
        <span>Base 600</span>
      </button>

      {/* Wall 600 */}
      <button
        onClick={() => onAddModule('wall_600')}
        className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-white border border-[#DDD5CA] hover:bg-[#FAF7F2] hover:border-[#B2967D] text-xs font-semibold text-[#2C2724] transition-all shadow-2xs cursor-pointer active:scale-95"
        title="Shortcut: Press 3"
      >
        <span className="w-4 h-4 rounded bg-[#EAE2D8] text-[10px] font-mono font-bold flex items-center justify-center text-[#2C2724]">
          3
        </span>
        <span>Wall 600</span>
      </button>

      {/* Tall 600 */}
      <button
        onClick={() => onAddModule('tall_600')}
        className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-white border border-[#DDD5CA] hover:bg-[#FAF7F2] hover:border-[#B2967D] text-xs font-semibold text-[#2C2724] transition-all shadow-2xs cursor-pointer active:scale-95"
        title="Shortcut: Press 4"
      >
        <span className="w-4 h-4 rounded bg-[#EAE2D8] text-[10px] font-mono font-bold flex items-center justify-center text-[#2C2724]">
          4
        </span>
        <span>Tall 600</span>
      </button>

      {/* Undo Button */}
      <div className="border-l border-[#DDD5CA] pl-2.5 ml-1">
        <button
          onClick={onUndo}
          disabled={!canUndo}
          className={`p-2 rounded-xl border transition-all flex items-center justify-center ${
            canUndo
              ? 'bg-white border-[#DDD5CA] text-[#2C2724] hover:bg-[#FAF7F2] hover:border-[#B2967D] shadow-2xs cursor-pointer active:scale-95'
              : 'opacity-40 border-transparent text-[#8C725C] cursor-not-allowed'
          }`}
          title="Undo (Ctrl+Z)"
        >
          <Undo2 className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
