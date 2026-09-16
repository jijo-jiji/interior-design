import React, { useState, useEffect, useCallback } from 'react';
import { SceneCanvas } from './canvas/SceneCanvas';
import type { CameraView } from './canvas/SceneCanvas';
import type { CabinetData, CabinetFinish, DoorStyle } from './canvas/CabinetMesh';
import { Header } from './components/Header';
import { ProjectPipelineDrawer } from './components/ProjectPipelineDrawer';
import type { ProjectItem } from './components/ProjectPipelineDrawer';
import { JoineryInspector } from './components/JoineryInspector';
import { JoineryModuleDock } from './components/JoineryModuleDock';

export const App: React.FC = () => {
  // ─── Projects & Selection State ───────────────────────────────────────────
  const [projects, setProjects] = useState<ProjectItem[]>([]);
  const [activeProjectId, setActiveProjectId] = useState<string>('QT-992AC14B');
  const [clientName, setClientName] = useState<string>('Marcus Aurelius');
  const [isPipelineOpen, setIsPipelineOpen] = useState<boolean>(false);

  // Room Architecture
  const [wallWidthMm, setWallWidthMm] = useState<number>(3600);
  const [wallHeightMm, setWallHeightMm] = useState<number>(2400);
  const [roomShape, setRoomShape] = useState<string>('lShape');

  // Aesthetics & Themes
  const [finish, setFinish] = useState<CabinetFinish>('japandi');
  const [doorStyle, setDoorStyle] = useState<DoorStyle>('slab');
  const [lightingMood, setLightingMood] = useState<'day' | 'evening'>('day');
  const [cameraView, setCameraView] = useState<CameraView>('orbit');

  // Joinery Modules
  const [cabinets, setCabinets] = useState<CabinetData[]>([
    { id: 'cab-1', type: 'base_800', x: 0.2, width: 0.8, height: 0.85, depth: 0.6 },
    { id: 'cab-2', type: 'base_600', x: 1.0, width: 0.6, height: 0.85, depth: 0.6 },
    { id: 'cab-3', type: 'base_600', x: 1.6, width: 0.6, height: 0.85, depth: 0.6 },
    { id: 'cab-4', type: 'wall_600', x: 1.0, width: 0.6, height: 0.72, depth: 0.35, isWallMounted: true },
  ]);

  const [selectedCabinetId, setSelectedCabinetId] = useState<string | null>('cab-1');
  const [undoStack, setUndoStack] = useState<CabinetData[][]>([]);
  const [isSaving, setIsSaving] = useState<boolean>(false);

  // ─── Fetch Projects on Mount ──────────────────────────────────────────────
  const fetchProjects = useCallback(async () => {
    try {
      const res = await fetch('/api/projects');
      if (res.ok) {
        const data = await res.json();
        setProjects(data);

        // Find Marcus Aurelius or initial
        const initial = data.find((p: any) => p.id === 'QT-992AC14B') || data[0];
        if (initial) {
          loadProject(initial);
        }
      }
    } catch (err) {
      console.warn('Could not fetch projects from backend, using default initial data.', err);
    }
  }, []);

  useEffect(() => {
    fetchProjects();
  }, [fetchProjects]);

  const loadProject = (proj: ProjectItem) => {
    const projId = proj.quote_id || proj.id || 'QT-992AC14B';
    setActiveProjectId(projId);
    setClientName(proj.client_name || 'Client Consultation');

    if (proj.wall) {
      setWallWidthMm(proj.wall.width_mm || 3600);
      setWallHeightMm(proj.wall.height_mm || 2400);
      setRoomShape(proj.wall.shape || 'singleWall');
    }

    const styleKey = proj.style_archetype || proj.style;
    if (styleKey && ['japandi', 'nordic', 'minimalist', 'industrial'].includes(styleKey)) {
      setFinish(styleKey as CabinetFinish);
    }

    const rawCabs = proj.cabinets || proj.placed_cabinets || [];
    if (rawCabs.length > 0) {
      const mapped: CabinetData[] = rawCabs.map((c: any, idx: number) => {
        const cabType = c.type || c.cabinet_type || 'base_600';
        const width = c.width || (c.width_mm ? c.width_mm / 1000 : (cabType === 'base_800' ? 0.8 : 0.6));
        const height = c.height || (c.height_mm ? c.height_mm / 1000 : (cabType === 'tall_600' ? 2.1 : (cabType === 'wall_600' ? 0.72 : 0.85)));
        const depth = c.depth || (c.depth_mm ? c.depth_mm / 1000 : (cabType === 'wall_600' ? 0.35 : 0.6));

        let posX = 0.2 + idx * 0.7;
        if (typeof c.x === 'number') {
          posX = c.x;
        } else if (typeof c.x_mm === 'number') {
          posX = c.x_mm < 0 ? (c.x_mm + 1800) / 1000 : c.x_mm / 1000;
        } else if (typeof c.distance_from_left_mm === 'number') {
          posX = c.distance_from_left_mm / 1000;
        }

        return {
          id: c.id || `cab-${idx + 1}`,
          type: cabType,
          x: Math.max(0.05, Math.round(posX * 1000) / 1000),
          width,
          height,
          depth,
          isWallMounted: cabType === 'wall_600',
        };
      });
      setCabinets(mapped);
      setSelectedCabinetId(mapped[0]?.id || null);
    }
  };

  // ─── Module Manipulation ──────────────────────────────────────────────────
  const recordHistory = () => {
    setUndoStack((prev) => [...prev.slice(-15), JSON.parse(JSON.stringify(cabinets))]);
  };

  const handleAddModule = (type: 'base_800' | 'base_600' | 'wall_600' | 'tall_600') => {
    recordHistory();

    const width = type === 'base_800' ? 0.8 : 0.6;
    const height = type === 'tall_600' ? 2.1 : (type === 'wall_600' ? 0.72 : 0.85);
    const depth = type === 'wall_600' ? 0.35 : 0.6;

    let nextX = 0.2;
    if (cabinets.length > 0) {
      const rightmost = cabinets.reduce((max, c) => (c.x + c.width > max ? c.x + c.width : max), 0);
      nextX = rightmost;
    }

    const wallMaxX = (wallWidthMm / 1000) - width;
    if (nextX > wallMaxX) {
      nextX = 0.2;
    }

    const newCabinet: CabinetData = {
      id: `cab-${Date.now()}`,
      type,
      x: nextX,
      width,
      height,
      depth,
      isWallMounted: type === 'wall_600',
    };

    setCabinets((prev) => [...prev, newCabinet]);
    setSelectedCabinetId(newCabinet.id);
  };

  const handleNudgeCabinet = (direction: -1 | 1) => {
    if (!selectedCabinetId) return;
    recordHistory();

    setCabinets((prev) =>
      prev.map((c) => {
        if (c.id === selectedCabinetId) {
          const delta = direction * 0.05; // 50mm
          const maxX = (wallWidthMm / 1000) - c.width;
          const newX = Math.max(0.05, Math.min(maxX, c.x + delta));
          return { ...c, x: newX };
        }
        return c;
      })
    );
  };

  const handleDeleteCabinet = (id: string) => {
    recordHistory();
    setCabinets((prev) => prev.filter((c) => c.id !== id));
    if (selectedCabinetId === id) {
      setSelectedCabinetId(null);
    }
  };

  const handleUndo = () => {
    if (undoStack.length === 0) return;
    const last = undoStack[undoStack.length - 1];
    setUndoStack((prev) => prev.slice(0, -1));
    setCabinets(last);
  };

  // ─── Save Revisions to Backend ────────────────────────────────────────────
  const handleSaveRevisions = async () => {
    setIsSaving(true);
    try {
      const payload = {
        cabinets: cabinets.map((c) => ({
          id: c.id,
          type: c.type,
          cabinet_type: c.type,
          x: c.x,
          width: c.width,
          height: c.height,
          depth: c.depth,
          width_mm: Math.round(c.width * 1000),
          height_mm: Math.round(c.height * 1000),
          depth_mm: Math.round(c.depth * 1000),
          x_mm: Math.round(c.x * 1000),
          distance_from_left_mm: Math.round(c.x * 1000),
        })),
        placed_cabinets: cabinets.map((c) => ({
          id: c.id,
          cabinet_type: c.type,
          label: c.type.replace('_', ' ').toUpperCase(),
          width_mm: Math.round(c.width * 1000),
          height_mm: Math.round(c.height * 1000),
          depth_mm: Math.round(c.depth * 1000),
          x_mm: Math.round(c.x * 1000),
          y_mm: 0.0,
          z_mm: 0.0,
          wall_index: 0,
        })),
        style: finish,
        style_archetype: finish,
        wall: {
          width_mm: wallWidthMm,
          height_mm: wallHeightMm,
          depth_mm: 600,
          shape: roomShape,
          return_mm: 2400,
        },
      };

      const res = await fetch(`/api/projects/${activeProjectId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (res.ok) {
        fetchProjects();
      }
    } catch (err) {
      console.error('Failed to save project revisions:', err);
    } finally {
      setIsSaving(false);
    }
  };

  const selectedCabinet = cabinets.find((c) => c.id === selectedCabinetId) || null;

  return (
    <div className="w-full h-full flex flex-col overflow-hidden bg-[#FAF7F2] select-none relative">
      {/* ── Top Architectural Navigation ─────────────────────────────── */}
      <Header
        roomShape={roomShape}
        onSelectShape={(s) => setRoomShape(s)}
        cameraView={cameraView}
        onSelectCameraView={(v) => setCameraView(v)}
        lightingMood={lightingMood}
        onToggleMood={() => setLightingMood((m) => (m === 'day' ? 'evening' : 'day'))}
        quoteId={activeProjectId}
        clientName={clientName}
        onSync={fetchProjects}
        onOpenPipeline={() => setIsPipelineOpen(true)}
      />

      {/* ── Slide-Over Consultation Pipeline Drawer ───────────────────── */}
      <ProjectPipelineDrawer
        isOpen={isPipelineOpen}
        onClose={() => setIsPipelineOpen(false)}
        projects={projects}
        activeProjectId={activeProjectId}
        onSelectProject={loadProject}
        wallWidthMm={wallWidthMm}
        wallHeightMm={wallHeightMm}
        onChangeWallWidth={setWallWidthMm}
        onChangeWallHeight={setWallHeightMm}
      />

      {/* ── Full-Screen Expansive 3D Architectural Canvas ─────────────── */}
      <div className="flex-1 w-full h-full relative">
        <SceneCanvas
          wallWidthMm={wallWidthMm}
          wallHeightMm={wallHeightMm}
          roomShape={roomShape}
          cabinets={cabinets}
          selectedCabinetId={selectedCabinetId}
          finish={finish}
          doorStyle={doorStyle}
          mood={lightingMood}
          cameraView={cameraView}
          onSelectCabinet={setSelectedCabinetId}
        />

        {/* Floating Joinery Spawner Dock (Bottom Center) */}
        <JoineryModuleDock
          onAddModule={handleAddModule}
          onUndo={handleUndo}
          canUndo={undoStack.length > 0}
          onDeleteSelected={() => selectedCabinetId && handleDeleteCabinet(selectedCabinetId)}
          onNudgeSelected={handleNudgeCabinet}
          hasSelected={selectedCabinetId !== null}
        />

        {/* Floating Architectural Finishes & BOQ Inspector (Right) */}
        <JoineryInspector
          finish={finish}
          onSelectFinish={setFinish}
          doorStyle={doorStyle}
          onSelectDoorStyle={setDoorStyle}
          selectedCabinet={selectedCabinet}
          onNudgeCabinet={handleNudgeCabinet}
          onDeleteCabinet={handleDeleteCabinet}
          cabinets={cabinets}
          quoteId={activeProjectId}
          onSaveRevisions={handleSaveRevisions}
          isSaving={isSaving}
        />
      </div>
    </div>
  );
};

export default App;
