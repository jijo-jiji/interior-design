import React, { useState } from 'react';
import { X, Search, Sliders, CheckCircle2, Clock, FolderKanban } from 'lucide-react';

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

  const filteredProjects = projects.filter((p) => {
    const q = searchQuery.toLowerCase();
    const name = (p.client_name || '').toLowerCase();
    const qid = (p.quote_id || p.id || '').toLowerCase();
    const style = (p.style_archetype || p.style || '').toLowerCase();
    return name.includes(q) || qid.includes(q) || style.includes(q);
  });

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-40 flex">
      {/* ── Backdrop Scrim ─────────────────────────────────────────── */}
      <div
        className="fixed inset-0 bg-black/20 backdrop-blur-xs transition-opacity"
        onClick={onClose}
      />

      {/* ── Slide-Over Glass Panel ─────────────────────────────────── */}
      <div className="relative w-88 max-w-[85vw] h-full glass-panel shadow-2xl border-r border-[#E5DDD3] flex flex-col z-50 bg-[#FAF7F2]/95 backdrop-blur-2xl">
        {/* Header */}
        <div className="p-4 border-b border-[#E5DDD3] flex items-center justify-between bg-white/70">
          <div className="flex items-center gap-2">
            <FolderKanban className="w-4 h-4 text-[#B2967D]" />
            <h3 className="text-xs uppercase tracking-wider font-bold text-[#2C2724]">
              Consultation Pipeline
            </h3>
            <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-[#E7D8C9] text-[#2C2724]">
              {projects.length}
            </span>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-[#8C725C] hover:text-[#2C2724] hover:bg-[#E7D8C9]/50 transition-all cursor-pointer"
            title="Close Drawer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Search */}
        <div className="p-4 border-b border-[#E5DDD3]">
          <div className="relative">
            <Search className="w-4 h-4 absolute left-3 top-2.5 text-[#8C725C]" />
            <input
              type="text"
              placeholder="Filter by client, quote ID, or style..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-xs rounded-xl bg-white border border-[#DDD5CA] text-[#2C2724] placeholder-[#B2967D] focus:outline-none focus:border-[#B2967D] shadow-xs"
            />
          </div>
        </div>

        {/* Project Deal Cards List */}
        <div className="flex-1 overflow-y-auto p-4 space-y-2.5">
          {filteredProjects.map((p) => {
            const projId = p.quote_id || p.id;
            const isSelected = projId === activeProjectId;
            const isPriority = (p.deposit_paid && p.deposit_paid > 0) || p.status === 'deposit_paid' || p.status === 'priority_locked';
            const cabCount = (p.cabinets || p.placed_cabinets || []).length;
            const styleName = p.style_archetype || p.style || 'Japandi';

            return (
              <div
                key={projId}
                onClick={() => {
                  onSelectProject(p);
                  onClose();
                }}
                className={`p-3.5 rounded-xl border transition-all cursor-pointer ${
                  isSelected
                    ? 'bg-white border-[#B2967D] shadow-sm ring-1 ring-[#B2967D]'
                    : 'bg-white/60 border-[#DDD5CA] hover:bg-white hover:border-[#B2967D]'
                }`}
              >
                <div className="flex items-start justify-between mb-1.5">
                  <div>
                    <h4 className="text-xs font-bold text-[#2C2724]">
                      {p.client_name || 'Walk-in Consultation'}
                    </h4>
                    <span className="text-[10px] text-[#8C725C] capitalize">
                      {styleName} · {cabCount} modules
                    </span>
                  </div>
                  <span className="text-xs font-bold text-[#2C2724] font-mono">
                    ${(p.total_price || p.subtotal || 0).toLocaleString('en-US', { minimumFractionDigits: 2 })}
                  </span>
                </div>

                <div className="flex items-center justify-between text-[11px] pt-1.5 border-t border-[#E5DDD3]/50">
                  <span className="font-mono text-[#8C725C]">{projId}</span>
                  <span
                    className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold ${
                      isPriority
                        ? 'bg-[#ECF8F8] text-[#3D6B69]'
                        : 'bg-[#FAF7F2] text-[#8C725C]'
                    }`}
                  >
                    {isPriority ? (
                      <>
                        <CheckCircle2 className="w-3 h-3 text-[#3D6B69]" />
                        Priority Locked
                      </>
                    ) : (
                      <>
                        <Clock className="w-3 h-3 text-[#8C725C]" />
                        Estimate
                      </>
                    )}
                  </span>
                </div>
              </div>
            );
          })}
        </div>

        {/* Room Geometry Controls */}
        <div className="p-4 border-t border-[#E5DDD3] bg-white/60">
          <div className="flex items-center gap-1.5 mb-3 text-[#8C725C] text-xs font-semibold uppercase tracking-wider">
            <Sliders className="w-3.5 h-3.5" />
            <span>Room Architectural Bounds</span>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-[10px] uppercase tracking-wider text-[#8C725C] block mb-1">
                Wall Width (mm)
              </label>
              <input
                type="number"
                step="100"
                min="1200"
                max="8000"
                value={wallWidthMm}
                onChange={(e) => onChangeWallWidth(Number(e.target.value))}
                className="w-full px-3 py-1.5 text-xs rounded-lg bg-white border border-[#E5DDD3] text-[#2C2724] font-mono focus:outline-none focus:border-[#B2967D]"
              />
            </div>
            <div>
              <label className="text-[10px] uppercase tracking-wider text-[#8C725C] block mb-1">
                Ceiling Height (mm)
              </label>
              <input
                type="number"
                step="50"
                min="2000"
                max="3600"
                value={wallHeightMm}
                onChange={(e) => onChangeWallHeight(Number(e.target.value))}
                className="w-full px-3 py-1.5 text-xs rounded-lg bg-white border border-[#E5DDD3] text-[#2C2724] font-mono focus:outline-none focus:border-[#B2967D]"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
