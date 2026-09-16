import React, { useState } from 'react';
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
} from 'lucide-react';
import confetti from 'canvas-confetti';
import type { CabinetFinish, DoorStyle, CabinetData } from '../canvas/CabinetMesh';

interface JoineryInspectorProps {
  finish: CabinetFinish;
  onSelectFinish: (finish: CabinetFinish) => void;
  doorStyle: DoorStyle;
  onSelectDoorStyle: (style: DoorStyle) => void;
  selectedCabinet: CabinetData | null;
  onNudgeCabinet: (direction: -1 | 1) => void;
  onDeleteCabinet: (id: string) => void;
  cabinets: CabinetData[];
  quoteId: string;
  onSaveRevisions: () => void;
  isSaving: boolean;
}

type InspectorTab = 'finishes' | 'module' | 'commercial';

export const JoineryInspector: React.FC<JoineryInspectorProps> = ({
  finish,
  onSelectFinish,
  doorStyle,
  onSelectDoorStyle,
  selectedCabinet,
  onNudgeCabinet,
  onDeleteCabinet,
  cabinets,
  quoteId,
  onSaveRevisions,
  isSaving,
}) => {
  const [activeTab, setActiveTab] = useState<InspectorTab>('finishes');
  const [isCollapsed, setIsCollapsed] = useState(false);

  // If user selects a cabinet, automatically switch to 'module' tab if they want
  // but keep tab control flexible
  const baseCabinetPrices: Record<string, number> = {
    base_800: 420,
    base_600: 340,
    wall_600: 280,
    tall_600: 620,
  };

  const finishMultiplier: Record<CabinetFinish, number> = {
    japandi: 1.0,
    minimalist: 1.08,
    nordic: 1.12,
    industrial: 1.18,
  };

  const doorStyleMultiplier: Record<DoorStyle, number> = {
    slab: 1.0,
    shaker: 1.06,
    fluted: 1.14,
  };

  let materialSubtotal = cabinets.reduce((sum, cab) => {
    return sum + (baseCabinetPrices[cab.type] || 380);
  }, 0);

  materialSubtotal = materialSubtotal * finishMultiplier[finish] * doorStyleMultiplier[doorStyle];

  const baseWidthMeters = cabinets
    .filter((c) => c.type === 'base_800' || c.type === 'base_600')
    .reduce((sum, c) => sum + c.width, 0);
  const benchtopCost = baseWidthMeters * 450;

  const totalBeforeGst = materialSubtotal + benchtopCost;
  const gst = totalBeforeGst * 0.1;
  const grandTotal = totalBeforeGst + gst;

  const handleSaveWithCelebration = () => {
    onSaveRevisions();
    confetti({
      particleCount: 65,
      spread: 55,
      origin: { y: 0.85 },
      colors: ['#E6BEAE', '#E7D8C9', '#B2967D', '#2C2724'],
    });
  };

  return (
    <aside
      className={`fixed right-6 top-20 z-20 transition-all duration-300 flex items-start ${
        isCollapsed ? 'translate-x-[calc(100%-14px)]' : 'translate-x-0'
      }`}
    >
      {/* ── Collapse/Expand Tab ────────────────────────────────────── */}
      <button
        onClick={() => setIsCollapsed(!isCollapsed)}
        className="mt-6 -ml-3 z-30 w-6 h-12 rounded-l-xl bg-white/90 border border-r-0 border-[#DDD5CA] flex items-center justify-center text-[#7A6A5C] hover:text-[#2C2724] shadow-md transition-all cursor-pointer"
        title={isCollapsed ? 'Expand Studio Panel' : 'Collapse Studio Panel'}
      >
        {isCollapsed ? <ChevronLeft className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
      </button>

      {/* ── Floating Architectural Glass Card ──────────────────────── */}
      <div className="w-88 max-h-[calc(100vh-6.5rem)] glass-panel rounded-2xl shadow-xl border border-[#DDD5CA] flex flex-col overflow-hidden bg-[#FAF7F2]/95 backdrop-blur-2xl">
        {/* Navigation Tabs Header */}
        <div className="p-3 border-b border-[#DDD5CA] bg-white/70">
          <div className="flex items-center gap-1.5">
            <button
              onClick={() => setActiveTab('finishes')}
              className={`flex-1 py-1.5 rounded-xl text-xs font-semibold transition-all flex items-center justify-center gap-1.5 cursor-pointer border ${
                activeTab === 'finishes'
                  ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                  : 'bg-white/80 text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724]'
              }`}
            >
              <Sparkles className="w-3.5 h-3.5" />
              <span>Finishes</span>
            </button>

            <button
              onClick={() => setActiveTab('module')}
              className={`flex-1 py-1.5 rounded-xl text-xs font-semibold transition-all flex items-center justify-center gap-1.5 relative cursor-pointer border ${
                activeTab === 'module'
                  ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                  : 'bg-white/80 text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724]'
              }`}
            >
              <Layers className="w-3.5 h-3.5" />
              <span>Module</span>
              {selectedCabinet && (
                <span className="w-1.5 h-1.5 rounded-full bg-[#E6BEAE]" />
              )}
            </button>

            <button
              onClick={() => setActiveTab('commercial')}
              className={`flex-1 py-1.5 rounded-xl text-xs font-semibold transition-all flex items-center justify-center gap-1.5 cursor-pointer border ${
                activeTab === 'commercial'
                  ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                  : 'bg-white/80 text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724]'
              }`}
            >
              <Receipt className="w-3.5 h-3.5" />
              <span>Pricing</span>
            </button>
          </div>
        </div>

        {/* Tab Body Content */}
        <div className="flex-1 overflow-y-auto p-5 space-y-5">
          {/* ── TAB 1: FINISHES & DOORS ──────────────────────────────── */}
          {activeTab === 'finishes' && (
            <div className="space-y-5">
              <div>
                <span className="text-xs uppercase tracking-wider font-semibold text-[#8C725C] block mb-3">
                  Architectural Materials
                </span>
                <div className="space-y-2.5">
                  {/* Japandi Natural */}
                  <button
                    onClick={() => onSelectFinish('japandi')}
                    className={`w-full p-3.5 rounded-xl border text-left transition-all flex items-center justify-between ${
                      finish === 'japandi'
                        ? 'bg-white border-[#B2967D] shadow-sm ring-1 ring-[#B2967D]'
                        : 'bg-white/60 border-[#E5DDD3] hover:bg-white hover:border-[#B2967D]'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <span className="w-6 h-6 rounded-full bg-[#C8B39B] border border-black/10 shadow-inner flex-shrink-0" />
                      <div>
                        <h4 className="text-xs font-semibold text-[#2C2724]">Japandi Natural</h4>
                        <p className="text-[11px] text-[#8C725C]">French White Oak & Champagne Gold</p>
                      </div>
                    </div>
                    <span className="text-[11px] font-mono text-[#8C725C]">1.00×</span>
                  </button>

                  {/* Warm Nordic */}
                  <button
                    onClick={() => onSelectFinish('nordic')}
                    className={`w-full p-3.5 rounded-xl border text-left transition-all flex items-center justify-between ${
                      finish === 'nordic'
                        ? 'bg-white border-[#B2967D] shadow-sm ring-1 ring-[#B2967D]'
                        : 'bg-white/60 border-[#E5DDD3] hover:bg-white hover:border-[#B2967D]'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <span className="w-6 h-6 rounded-full bg-[#EEE4E1] border border-black/10 shadow-inner flex-shrink-0" />
                      <div>
                        <h4 className="text-xs font-semibold text-[#2C2724]">Warm Nordic</h4>
                        <p className="text-[11px] text-[#8C725C]">Bleached Birch & Brushed Brass</p>
                      </div>
                    </div>
                    <span className="text-[11px] font-mono text-[#8C725C]">1.12×</span>
                  </button>

                  {/* Modern Minimalist */}
                  <button
                    onClick={() => onSelectFinish('minimalist')}
                    className={`w-full p-3.5 rounded-xl border text-left transition-all flex items-center justify-between ${
                      finish === 'minimalist'
                        ? 'bg-white border-[#B2967D] shadow-sm ring-1 ring-[#B2967D]'
                        : 'bg-white/60 border-[#E5DDD3] hover:bg-white hover:border-[#B2967D]'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <span className="w-6 h-6 rounded-full bg-[#F0EAE1] border border-black/10 shadow-inner flex-shrink-0" />
                      <div>
                        <h4 className="text-xs font-semibold text-[#2C2724]">Modern Minimalist</h4>
                        <p className="text-[11px] text-[#8C725C]">Matte Cashmere & Graphite</p>
                      </div>
                    </div>
                    <span className="text-[11px] font-mono text-[#8C725C]">1.08×</span>
                  </button>

                  {/* Smoked Oak */}
                  <button
                    onClick={() => onSelectFinish('industrial')}
                    className={`w-full p-3.5 rounded-xl border text-left transition-all flex items-center justify-between ${
                      finish === 'industrial'
                        ? 'bg-white border-[#B2967D] shadow-sm ring-1 ring-[#B2967D]'
                        : 'bg-white/60 border-[#E5DDD3] hover:bg-white hover:border-[#B2967D]'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <span className="w-6 h-6 rounded-full bg-[#4A4038] border border-black/10 shadow-inner flex-shrink-0" />
                      <div>
                        <h4 className="text-xs font-semibold text-[#2C2724]">Smoked Charcoal Oak</h4>
                        <p className="text-[11px] text-[#8C725C]">Dark Smoked Timber & Steel</p>
                      </div>
                    </div>
                    <span className="text-[11px] font-mono text-[#8C725C]">1.18×</span>
                  </button>
                </div>
              </div>

              <div>
                <span className="text-xs uppercase tracking-wider font-semibold text-[#8C725C] block mb-2.5">
                  Door Face Profile
                </span>
                <div className="grid grid-cols-3 gap-1.5">
                  <button
                    onClick={() => onSelectDoorStyle('slab')}
                    className={`py-2 rounded-xl text-xs font-semibold transition-all cursor-pointer border text-center ${
                      doorStyle === 'slab'
                        ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                        : 'bg-white text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724]'
                    }`}
                  >
                    Slab J-Pull
                  </button>
                  <button
                    onClick={() => onSelectDoorStyle('shaker')}
                    className={`py-2 rounded-xl text-xs font-semibold transition-all cursor-pointer border text-center ${
                      doorStyle === 'shaker'
                        ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                        : 'bg-white text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724]'
                    }`}
                  >
                    Slim Shaker
                  </button>
                  <button
                    onClick={() => onSelectDoorStyle('fluted')}
                    className={`py-2 rounded-xl text-xs font-semibold transition-all cursor-pointer border text-center ${
                      doorStyle === 'fluted'
                        ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                        : 'bg-white text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724]'
                    }`}
                  >
                    Fluted Reed
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* ── TAB 2: ACTIVE MODULE INSPECTOR ───────────────────────── */}
          {activeTab === 'module' && (
            <div className="space-y-5">
              <span className="text-xs uppercase tracking-wider font-semibold text-[#8C725C] block mb-2">
                Joinery Specification
              </span>

              {selectedCabinet ? (
                <div className="bg-white rounded-xl p-4 border border-[#E5DDD3] shadow-xs space-y-4">
                  <div className="flex items-center justify-between pb-3 border-b border-[#E5DDD3]">
                    <div>
                      <h4 className="text-sm font-semibold uppercase text-[#2C2724]">
                        {selectedCabinet.type.replace('_', ' ')}
                      </h4>
                      <p className="text-xs text-[#8C725C]">Module #{selectedCabinet.id.slice(-6)}</p>
                    </div>
                    <span className="px-2.5 py-1 rounded-full bg-[#E7D8C9] text-xs font-mono font-semibold text-[#2C2724]">
                      {(selectedCabinet.width * 1000).toFixed(0)}mm
                    </span>
                  </div>

                  {/* Dimensions Breakdown */}
                  <div className="grid grid-cols-3 gap-2 text-center py-2 bg-[#FAF7F2] rounded-lg border border-[#E5DDD3]">
                    <div>
                      <span className="text-[10px] text-[#8C725C] uppercase block">Width</span>
                      <span className="text-xs font-mono font-bold text-[#2C2724]">
                        {(selectedCabinet.width * 1000).toFixed(0)}mm
                      </span>
                    </div>
                    <div>
                      <span className="text-[10px] text-[#8C725C] uppercase block">Height</span>
                      <span className="text-xs font-mono font-bold text-[#2C2724]">
                        {(selectedCabinet.height * 1000).toFixed(0)}mm
                      </span>
                    </div>
                    <div>
                      <span className="text-[10px] text-[#8C725C] uppercase block">Depth</span>
                      <span className="text-xs font-mono font-bold text-[#2C2724]">
                        {(selectedCabinet.depth * 1000).toFixed(0)}mm
                      </span>
                    </div>
                  </div>

                  {/* Nudge & Actions */}
                  <div className="space-y-2 pt-2">
                    <span className="text-xs text-[#8C725C] block">Nudge Along Wall Rail</span>
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => onNudgeCabinet(-1)}
                        className="flex-1 py-2 rounded-lg bg-[#FAF7F2] border border-[#E5DDD3] text-[#2C2724] hover:bg-[#E7D8C9] font-mono text-xs font-semibold flex items-center justify-center gap-1 transition-all"
                      >
                        <ArrowLeft className="w-3.5 h-3.5" />
                        <span>-50mm</span>
                      </button>

                      <button
                        onClick={() => onNudgeCabinet(1)}
                        className="flex-1 py-2 rounded-lg bg-[#FAF7F2] border border-[#E5DDD3] text-[#2C2724] hover:bg-[#E7D8C9] font-mono text-xs font-semibold flex items-center justify-center gap-1 transition-all"
                      >
                        <span>+50mm</span>
                        <ArrowRight className="w-3.5 h-3.5" />
                      </button>

                      <button
                        onClick={() => onDeleteCabinet(selectedCabinet.id)}
                        className="p-2 rounded-lg bg-red-50 border border-red-200 text-red-600 hover:bg-red-100 transition-all"
                        title="Delete Module"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                </div>
              ) : (
                <div className="p-6 rounded-xl border border-dashed border-[#E5DDD3] bg-white/50 text-center space-y-2">
                  <Layers className="w-6 h-6 text-[#B2967D] mx-auto opacity-50" />
                  <p className="text-xs text-[#8C725C]">No cabinet selected in 3D scene.</p>
                  <p className="text-[11px] text-[#B2967D]">
                    Click any module in 3D or press 1–4 on your keyboard to spawn new joinery.
                  </p>
                </div>
              )}
            </div>
          )}

          {/* ── TAB 3: PRICING & PRODUCTION HANDOVER ─────────────────── */}
          {activeTab === 'commercial' && (
            <div className="space-y-5">
              <span className="text-xs uppercase tracking-wider font-semibold text-[#8C725C] block mb-2">
                Commercial Summary & Export
              </span>

              <div className="bg-white rounded-xl p-4 border border-[#E5DDD3] space-y-3 shadow-xs">
                <div className="flex justify-between text-xs text-[#8C725C]">
                  <span>Joinery Subtotal ({cabinets.length} units)</span>
                  <span className="font-mono font-medium">${materialSubtotal.toFixed(2)}</span>
                </div>
                <div className="flex justify-between text-xs text-[#8C725C]">
                  <span>20mm Calacatta Quartz Stone</span>
                  <span className="font-mono font-medium">${benchtopCost.toFixed(2)}</span>
                </div>
                <div className="flex justify-between text-xs text-[#8C725C]">
                  <span>GST (10%)</span>
                  <span className="font-mono font-medium">${gst.toFixed(2)}</span>
                </div>

                <div className="pt-3 border-t border-[#E5DDD3] flex justify-between items-baseline">
                  <span className="font-bold text-sm text-[#2C2724]">Total AUD</span>
                  <span className="font-mono font-bold text-xl text-[#2C2724]">
                    ${grandTotal.toFixed(2)}
                  </span>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="space-y-2.5 pt-2">
                <button
                  onClick={handleSaveWithCelebration}
                  disabled={isSaving}
                  className="w-full py-3 px-4 rounded-xl bg-[#2C2724] text-[#FAF7F2] text-xs font-semibold hover:bg-[#1E1A17] active:scale-[0.98] transition-all flex items-center justify-center gap-2 shadow-md"
                >
                  <CheckCircle2 className="w-4 h-4 text-[#E6BEAE]" />
                  <span>{isSaving ? 'Locking Studio BOQ...' : 'Save & Lock Studio BOQ'}</span>
                </button>

                <a
                  href={`/quote/pdf/${quoteId}`}
                  target="_blank"
                  rel="noreferrer"
                  className="w-full py-2.5 px-3 rounded-xl bg-white border border-[#E5DDD3] text-[#2C2724] text-xs font-semibold hover:bg-[#FAF7F2] transition-all flex items-center justify-center gap-2 shadow-xs"
                >
                  <FileText className="w-4 h-4 text-[#8C725C]" />
                  <span>Download Signed PDF Proposal</span>
                </a>

                <div className="grid grid-cols-2 gap-2">
                  <a
                    href={`/api/export/${quoteId}/dxf`}
                    download
                    className="py-2 px-3 rounded-lg bg-white border border-[#E5DDD3] text-[#8C725C] hover:text-[#2C2724] text-xs font-medium hover:bg-[#FAF7F2] transition-all flex items-center justify-center gap-1.5 shadow-2xs"
                  >
                    <Download className="w-3.5 h-3.5" />
                    <span>AutoCAD DXF</span>
                  </a>

                  <a
                    href={`/api/export/${quoteId}/cutlist`}
                    download
                    className="py-2 px-3 rounded-lg bg-white border border-[#E5DDD3] text-[#8C725C] hover:text-[#2C2724] text-xs font-medium hover:bg-[#FAF7F2] transition-all flex items-center justify-center gap-1.5 shadow-2xs"
                  >
                    <Download className="w-3.5 h-3.5" />
                    <span>Cutlist CSV</span>
                  </a>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </aside>
  );
};
