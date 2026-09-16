import React from 'react';
import { Sun, Moon, Box, Compass, ExternalLink, RefreshCw, ChevronDown, FolderKanban } from 'lucide-react';
import type { CameraView } from '../canvas/SceneCanvas';

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
  onOpenPipeline: () => void;
}

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
  onOpenPipeline,
}) => {
  return (
    <header className="h-16 px-6 glass-panel flex items-center justify-between z-30 border-b border-[#E5DDD3] bg-[#FAF7F2]/90 backdrop-blur-xl">
      {/* ── Left: Atelier Branding & Project Selector Pill ───────────── */}
      <div className="flex items-center gap-4">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-[#E6BEAE] flex items-center justify-center text-[#2C2724] shadow-xs">
            <Box className="w-5 h-5 stroke-[1.8]" />
          </div>
          <div>
            <span className="font-bold text-xs tracking-wider uppercase text-[#2C2724] block">
              Atelier Architekt
            </span>
            <span className="text-[10px] text-[#8C725C] tracking-wide font-mono">
              3D JOINERY WORKBENCH
            </span>
          </div>
        </div>

        {/* Project Selector Trigger */}
        <button
          onClick={onOpenPipeline}
          className="flex items-center gap-2 px-3.5 py-1.5 rounded-xl bg-white border border-[#DDD5CA] hover:border-[#B2967D] hover:bg-[#FAF7F2] text-xs font-semibold text-[#2C2724] shadow-xs transition-all"
          title="Switch Project"
        >
          <FolderKanban className="w-3.5 h-3.5 text-[#B2967D]" />
          <span>{clientName || 'Select Project'}</span>
          {quoteId && <span className="text-[11px] font-mono text-[#8C725C]">({quoteId})</span>}
          <ChevronDown className="w-3.5 h-3.5 text-[#8C725C] ml-0.5 opacity-70" />
        </button>
      </div>

      {/* ── Center: Architectural Layout & Camera View Independent Pill Controls ── */}
      <div className="flex items-center gap-4">
        {/* Layout Shape Selector */}
        <div className="flex items-center gap-1.5">
          <button
            onClick={() => onSelectShape('singleWall')}
            className={`px-3.5 py-1.5 text-xs rounded-xl transition-all font-semibold whitespace-nowrap border cursor-pointer ${
              roomShape === 'singleWall'
                ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                : 'bg-white text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724] shadow-2xs'
            }`}
          >
            Single Wall
          </button>
          <button
            onClick={() => onSelectShape('lShape')}
            className={`px-3.5 py-1.5 text-xs rounded-xl transition-all font-semibold whitespace-nowrap border cursor-pointer ${
              roomShape === 'lShape'
                ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                : 'bg-white text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724] shadow-2xs'
            }`}
          >
            L-Shape Corner
          </button>
          <button
            onClick={() => onSelectShape('galley')}
            className={`px-3.5 py-1.5 text-xs rounded-xl transition-all font-semibold whitespace-nowrap border cursor-pointer ${
              roomShape === 'galley'
                ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                : 'bg-white text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724] shadow-2xs'
            }`}
          >
            Galley Suite
          </button>
        </div>

        {/* Divider */}
        <div className="h-5 w-[1px] bg-[#DDD5CA]" />

        {/* Camera Views Selector */}
        <div className="flex items-center gap-1.5">
          <button
            onClick={() => onSelectCameraView('orbit')}
            className={`px-3.5 py-1.5 text-xs rounded-xl transition-all font-semibold whitespace-nowrap border cursor-pointer ${
              cameraView === 'orbit'
                ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                : 'bg-white text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724] shadow-2xs'
            }`}
          >
            3D Orbit
          </button>
          <button
            onClick={() => onSelectCameraView('top')}
            className={`px-3.5 py-1.5 text-xs rounded-xl transition-all font-semibold whitespace-nowrap border cursor-pointer ${
              cameraView === 'top'
                ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                : 'bg-white text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724] shadow-2xs'
            }`}
          >
            Plan View
          </button>
          <button
            onClick={() => onSelectCameraView('front')}
            className={`px-3.5 py-1.5 text-xs rounded-xl transition-all font-semibold whitespace-nowrap border cursor-pointer ${
              cameraView === 'front'
                ? 'bg-[#2C2724] text-[#FAF7F2] border-[#2C2724] shadow-xs'
                : 'bg-white text-[#7A6A5C] border-[#DDD5CA] hover:border-[#B2967D] hover:text-[#2C2724] shadow-2xs'
            }`}
          >
            Elevation
          </button>
        </div>

        {/* Ambient Mood Toggle */}
        <button
          onClick={onToggleMood}
          className="px-3.5 py-1.5 rounded-xl bg-white border border-[#DDD5CA] text-[#7A6A5C] hover:text-[#2C2724] hover:border-[#B2967D] shadow-2xs transition-all flex items-center gap-2 text-xs font-semibold cursor-pointer"
          title="Toggle Daylight / Evening Mood"
        >
          {lightingMood === 'day' ? (
            <>
              <Sun className="w-4 h-4 text-[#C5A059]" />
              <span className="text-[#2C2724]">Daylight</span>
            </>
          ) : (
            <>
              <Moon className="w-4 h-4 text-[#8C725C]" />
              <span className="text-[#2C2724]">Evening</span>
            </>
          )}
        </button>
      </div>

      {/* ── Right: Shareable Client Portal & Factory Handover ─────────── */}
      <div className="flex items-center gap-3">
        <a
          href={`/portal/?id=${quoteId}`}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-white border border-[#E5DDD3] hover:border-[#B2967D] text-xs font-semibold text-[#2C2724] shadow-2xs transition-all"
        >
          <Compass className="w-3.5 h-3.5 text-[#B2967D]" />
          <span>Client 3D Portal</span>
          <ExternalLink className="w-3 h-3 opacity-50 ml-0.5" />
        </a>

        <a
          href={`/studio/factory.html?id=${quoteId}`}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-white border border-[#DDD5CA] hover:border-[#B2967D] text-xs font-semibold text-[#2C2724] shadow-2xs transition-all"
        >
          <span>Factory CNC</span>
          <ExternalLink className="w-3 h-3 opacity-50 ml-0.5" />
        </a>

        <button
          onClick={onSync}
          className="p-2 rounded-xl bg-white border border-[#E5DDD3] text-[#8C725C] hover:text-[#2C2724] hover:border-[#B2967D] shadow-2xs transition-all"
          title="Sync Pipeline"
        >
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>
    </header>
  );
};
