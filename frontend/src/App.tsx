import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { SceneCanvas } from './canvas/SceneCanvas';
import type { CameraView } from './canvas/SceneCanvas';
import type { CabinetData, CabinetFinish, CabinetType, DoorStyle } from './canvas/CabinetMesh';
import { Header } from './components/Header';
import { ProjectPipelineDrawer } from './components/ProjectPipelineDrawer';
import type { ProjectItem } from './components/ProjectPipelineDrawer';
import { JoineryInspector } from './components/JoineryInspector';
import type { SaveState } from './components/JoineryInspector';
import { JoineryModuleDock } from './components/JoineryModuleDock';
import type { ModuleType } from './components/JoineryModuleDock';
import { FALLBACK_CATALOG, benchtopLinearMetres, priceLayout } from './pricing';
import type { Catalog } from './pricing';

const DEMO_PROJECT_ID = 'QT-992AC14B';
const MIN_X = 0.05;
const NUDGE_M = 0.05;

const MODULE_SIZES: Record<ModuleType, { width: number; height: number; depth: number }> = {
  base_800: { width: 0.8, height: 0.85, depth: 0.6 },
  base_600: { width: 0.6, height: 0.85, depth: 0.6 },
  wall_600: { width: 0.6, height: 0.72, depth: 0.35 },
  tall_600: { width: 0.6, height: 2.1, depth: 0.6 },
  // Appliance modules — sizes match CABINET_SPECS in assets/3d/index.html.
  sink_600: { width: 0.6, height: 0.85, depth: 0.6 },
  cooktop_600: { width: 0.6, height: 0.85, depth: 0.6 },
  dishwasher_600: { width: 0.6, height: 0.85, depth: 0.6 },
  oven_tower_600: { width: 0.6, height: 2.1, depth: 0.6 },
  fridge_recess_700: { width: 0.7, height: 2.1, depth: 0.65 },
  rangehood_900: { width: 0.9, height: 0.45, depth: 0.5 },
};

/** Modules that hang on the wall rather than stand on the floor. */
const WALL_MOUNTED_TYPES: string[] = ['wall_600', 'rangehood_900'];

/** First gap on the rail that fits `width`, else hard against the last module. */
const findFreeX = (
  existing: CabinetData[],
  width: number,
  wallWidthM: number,
  wallMounted: boolean,
): number => {
  const row = existing
    .filter((c) => Boolean(c.isWallMounted) === wallMounted)
    .sort((a, b) => a.x - b.x);

  let cursor = MIN_X;
  for (const cab of row) {
    if (cab.x - cursor >= width) return cursor;
    cursor = Math.max(cursor, cab.x + cab.width);
  }
  return Math.max(MIN_X, Math.min(cursor, wallWidthM - width));
};

export const App: React.FC = () => {
  // ─── Projects & selection ─────────────────────────────────────────────────
  const [projects, setProjects] = useState<ProjectItem[]>([]);
  const [activeProjectId, setActiveProjectId] = useState<string>(DEMO_PROJECT_ID);
  const [clientName, setClientName] = useState<string>('Marcus Aurelius');
  const [isPipelineOpen, setIsPipelineOpen] = useState<boolean>(false);
  const [isSyncing, setIsSyncing] = useState<boolean>(false);
  const [isOffline, setIsOffline] = useState<boolean>(false);
  const hasLoadedInitialProject = useRef(false);

  // Room architecture
  const [wallWidthMm, setWallWidthMm] = useState<number>(3600);
  const [wallHeightMm, setWallHeightMm] = useState<number>(2400);
  const [roomShape, setRoomShape] = useState<string>('lShape');
  const [obstacles, setObstacles] = useState<{ type: string }[]>([]);
  /** Chosen on the tablet during the consultation; the studio prices it too. */
  const [benchtopMaterial, setBenchtopMaterial] = useState<string | null>(null);

  // Aesthetics
  const [finish, setFinish] = useState<CabinetFinish>('japandi');
  const [doorStyle, setDoorStyle] = useState<DoorStyle>('slab');
  const [lightingMood, setLightingMood] = useState<'day' | 'evening'>('day');
  const [cameraView, setCameraView] = useState<CameraView>('orbit');
  const [isInspectorCollapsed, setIsInspectorCollapsed] = useState<boolean>(false);

  // Joinery modules
  const [cabinets, setCabinets] = useState<CabinetData[]>([
    { id: 'cab-1', type: 'base_800', x: 0.2, width: 0.8, height: 0.85, depth: 0.6 },
    { id: 'cab-2', type: 'base_600', x: 1.0, width: 0.6, height: 0.85, depth: 0.6 },
    { id: 'cab-3', type: 'base_600', x: 1.6, width: 0.6, height: 0.85, depth: 0.6 },
    { id: 'cab-4', type: 'wall_600', x: 1.0, width: 0.6, height: 0.72, depth: 0.35, isWallMounted: true },
  ]);

  const [selectedCabinetId, setSelectedCabinetId] = useState<string | null>('cab-1');
  const [undoStack, setUndoStack] = useState<CabinetData[][]>([]);

  // Commercial
  const [catalog, setCatalog] = useState<Catalog>(FALLBACK_CATALOG);
  const [saveState, setSaveState] = useState<SaveState>('idle');
  const [saveError, setSaveError] = useState<string | null>(null);

  // ─── Loading a consultation into the scene ────────────────────────────────
  const loadProject = useCallback((proj: ProjectItem) => {
    const projId = proj.quote_id || proj.id;
    if (projId) setActiveProjectId(projId);
    setClientName(proj.client_name || 'Client consultation');
    setSaveState('idle');
    setSaveError(null);
    setUndoStack([]);

    if (proj.wall) {
      setWallWidthMm(proj.wall.width_mm || 3600);
      setWallHeightMm(proj.wall.height_mm || 2400);
      setRoomShape(proj.wall.shape || 'singleWall');
    }

    setObstacles(Array.isArray(proj.obstacles) ? proj.obstacles : []);
    setBenchtopMaterial(proj.benchtop_material ?? null);

    const styleKey = proj.style_archetype || proj.style;
    if (styleKey && ['japandi', 'nordic', 'minimalist', 'industrial'].includes(styleKey)) {
      setFinish(styleKey as CabinetFinish);
    }

    const rawCabs = proj.cabinets || proj.placed_cabinets || [];
    const mapped: CabinetData[] = rawCabs.map((c: any, idx: number) => {
      const cabType: CabinetType = c.type || c.cabinet_type || 'base_600';
      const fallback = MODULE_SIZES[cabType as ModuleType];
      const width = c.width || (c.width_mm ? c.width_mm / 1000 : (fallback?.width ?? 0.6));
      const height = c.height || (c.height_mm ? c.height_mm / 1000 : (fallback?.height ?? 0.85));
      const depth = c.depth || (c.depth_mm ? c.depth_mm / 1000 : (fallback?.depth ?? 0.6));

      let posX = 0.2 + idx * 0.7;
      if (typeof c.x === 'number') {
        posX = c.x;
      } else if (typeof c.x_mm === 'number') {
        // Mobile traces measure from the wall centre; the studio measures from the left edge.
        posX = c.x_mm < 0 ? (c.x_mm + 1800) / 1000 : c.x_mm / 1000;
      } else if (typeof c.distance_from_left_mm === 'number') {
        posX = c.distance_from_left_mm / 1000;
      }

      return {
        id: c.id || `cab-${idx + 1}`,
        type: cabType,
        x: Math.max(MIN_X, Math.round(posX * 1000) / 1000),
        width,
        height,
        depth,
        isWallMounted: WALL_MOUNTED_TYPES.includes(cabType),
      };
    });

    // A consultation with no joinery must clear the scene, not inherit the
    // previous project's modules.
    setCabinets(mapped);
    setSelectedCabinetId(mapped[0]?.id ?? null);
  }, []);

  // ─── Backend data ─────────────────────────────────────────────────────────
  const fetchProjects = useCallback(async () => {
    try {
      const res = await fetch('/api/projects');
      if (!res.ok) throw new Error(`Pipeline request failed (${res.status})`);

      const data: ProjectItem[] = await res.json();
      setProjects(data);
      setIsOffline(false);

      // Only the very first sync picks a project. Later refreshes must leave
      // whatever the estimator is working on open.
      if (!hasLoadedInitialProject.current) {
        const initial = data.find((p) => (p.quote_id || p.id) === DEMO_PROJECT_ID) || data[0];
        if (initial) {
          hasLoadedInitialProject.current = true;
          loadProject(initial);
        }
      }
    } catch (err) {
      console.warn('Could not reach the backend; showing demo data.', err);
      setIsOffline(true);
    }
  }, [loadProject]);

  /** The spinner belongs to the click, not to the initial load. */
  const handleSync = useCallback(async () => {
    setIsSyncing(true);
    try {
      await fetchProjects();
    } finally {
      setIsSyncing(false);
    }
  }, [fetchProjects]);

  useEffect(() => {
    fetchProjects();
  }, [fetchProjects]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch('/api/catalog');
        if (!res.ok) throw new Error(`Catalog request failed (${res.status})`);
        const data = await res.json();
        if (cancelled) return;
        setCatalog({ ...FALLBACK_CATALOG, ...data });
      } catch (err) {
        console.warn('Could not load the pricing catalog; using built-in rates.', err);
        if (!cancelled) setIsOffline(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // ─── Module manipulation ──────────────────────────────────────────────────
  // Updaters stay pure (StrictMode runs them twice), so history and the add
  // handler read the live layout through a ref instead.
  const cabinetsRef = useRef(cabinets);
  const undoStackRef = useRef(undoStack);
  useEffect(() => {
    cabinetsRef.current = cabinets;
  }, [cabinets]);
  useEffect(() => {
    undoStackRef.current = undoStack;
  }, [undoStack]);

  const recordHistory = useCallback(() => {
    setUndoStack((prev) => [...prev.slice(-15), cabinetsRef.current]);
  }, []);

  const handleAddModule = useCallback(
    (type: ModuleType) => {
      recordHistory();
      const size = MODULE_SIZES[type];
      const isWallMounted = WALL_MOUNTED_TYPES.includes(type);
      const x = findFreeX(cabinetsRef.current, size.width, wallWidthMm / 1000, isWallMounted);

      const newCabinet: CabinetData = {
        id: `cab-${Date.now()}`,
        type,
        x,
        width: size.width,
        height: size.height,
        depth: size.depth,
        isWallMounted,
      };

      setCabinets((prev) => [...prev, newCabinet]);
      setSelectedCabinetId(newCabinet.id);
    },
    [recordHistory, wallWidthMm],
  );

  const handleNudgeCabinet = useCallback(
    (direction: -1 | 1) => {
      if (!selectedCabinetId) return;
      recordHistory();

      setCabinets((prev) =>
        prev.map((c) => {
          if (c.id !== selectedCabinetId) return c;
          const maxX = Math.max(MIN_X, wallWidthMm / 1000 - c.width);
          return { ...c, x: Math.max(MIN_X, Math.min(maxX, c.x + direction * NUDGE_M)) };
        }),
      );
    },
    [recordHistory, selectedCabinetId, wallWidthMm],
  );

  const handleDeleteCabinet = useCallback(
    (id: string) => {
      recordHistory();
      setCabinets((prev) => prev.filter((c) => c.id !== id));
      setSelectedCabinetId((current) => (current === id ? null : current));
    },
    [recordHistory],
  );

  const handleUndo = useCallback(() => {
    const stack = undoStackRef.current;
    if (stack.length === 0) return;
    setCabinets(stack[stack.length - 1]);
    setUndoStack(stack.slice(0, -1));
  }, []);

  // Shrinking the room must not leave joinery hanging past the wall.
  const handleChangeWallWidth = useCallback((next: number) => {
    setWallWidthMm(next);
    setCabinets((prev) =>
      prev.map((c) => {
        const maxX = Math.max(MIN_X, next / 1000 - c.width);
        return c.x > maxX ? { ...c, x: maxX } : c;
      }),
    );
  }, []);

  // ─── Commercial totals (same formula as the backend quote) ────────────────
  const totals = useMemo(
    () => priceLayout(cabinets, obstacles, finish, catalog, benchtopMaterial),
    [cabinets, obstacles, finish, catalog, benchtopMaterial],
  );

  const benchtopMetres = useMemo(() => benchtopLinearMetres(cabinets), [cabinets]);

  const handleSaveRevisions = useCallback(async () => {
    setSaveState('saving');
    setSaveError(null);

    const payload = {
      cabinets: cabinets.map((c) => ({
        id: c.id,
        type: c.type,
        cabinet_type: c.type,
        label: c.type.replace(/_/g, ' ').toUpperCase(),
        x: c.x,
        width: c.width,
        height: c.height,
        depth: c.depth,
        width_mm: Math.round(c.width * 1000),
        height_mm: Math.round(c.height * 1000),
        depth_mm: Math.round(c.depth * 1000),
        x_mm: Math.round(c.x * 1000),
        y_mm: 0,
        z_mm: 0,
        wall_index: 0,
        distance_from_left_mm: Math.round(c.x * 1000),
      })),
      style: finish,
      style_archetype: finish,
      benchtop_material: benchtopMaterial,
      wall: {
        width_mm: wallWidthMm,
        height_mm: wallHeightMm,
        depth_mm: 600,
        shape: roomShape,
        return_mm: 2400,
      },
      // Without these the stored record keeps the pre-revision price and the
      // pipeline card disagrees with the studio.
      line_items: totals.lineItems,
      subtotal: totals.subtotal,
      gst: totals.gst,
      total_price: totals.total,
    };

    try {
      const res = await fetch(`/api/projects/${activeProjectId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        throw new Error(
          res.status === 404
            ? 'This consultation is not in the backend yet, so there is nothing to update.'
            : `The backend rejected the revision (${res.status}).`,
        );
      }

      setSaveState('saved');
      fetchProjects();
    } catch (err) {
      console.error('Failed to save project revisions:', err);
      setSaveState('error');
      setSaveError(err instanceof Error ? err.message : 'Could not save this revision.');
    }
  }, [
    activeProjectId,
    benchtopMaterial,
    cabinets,
    fetchProjects,
    finish,
    roomShape,
    totals,
    wallHeightMm,
    wallWidthMm,
  ]);

  const selectedCabinet = cabinets.find((c) => c.id === selectedCabinetId) ?? null;

  return (
    <div className="grid h-full w-full grid-rows-[auto_1fr] overflow-hidden bg-canvas select-none">
      <Header
        roomShape={roomShape}
        onSelectShape={setRoomShape}
        cameraView={cameraView}
        onSelectCameraView={setCameraView}
        lightingMood={lightingMood}
        onToggleMood={() => setLightingMood((m) => (m === 'day' ? 'evening' : 'day'))}
        quoteId={activeProjectId}
        clientName={clientName}
        onSync={handleSync}
        isSyncing={isSyncing}
        isOffline={isOffline}
        onOpenPipeline={() => setIsPipelineOpen(true)}
      />

      <ProjectPipelineDrawer
        isOpen={isPipelineOpen}
        onClose={() => setIsPipelineOpen(false)}
        projects={projects}
        activeProjectId={activeProjectId}
        onSelectProject={loadProject}
        wallWidthMm={wallWidthMm}
        wallHeightMm={wallHeightMm}
        onChangeWallWidth={handleChangeWallWidth}
        onChangeWallHeight={setWallHeightMm}
      />

      {/* Canvas and inspector share the row, so the panel never covers the model. */}
      <main className="flex min-h-0 min-w-0">
        <section className="relative min-h-0 min-w-0 flex-1">
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

          <JoineryModuleDock
            onAddModule={handleAddModule}
            onUndo={handleUndo}
            canUndo={undoStack.length > 0}
            onDeleteSelected={() => selectedCabinetId && handleDeleteCabinet(selectedCabinetId)}
            onNudgeSelected={handleNudgeCabinet}
            hasSelected={selectedCabinetId !== null}
            hotkeysEnabled={!isPipelineOpen}
          />
        </section>

        <JoineryInspector
          finish={finish}
          onSelectFinish={setFinish}
          doorStyle={doorStyle}
          onSelectDoorStyle={setDoorStyle}
          selectedCabinet={selectedCabinet}
          onNudgeCabinet={handleNudgeCabinet}
          onDeleteCabinet={handleDeleteCabinet}
          cabinetCount={cabinets.length}
          totals={totals}
          styleMultipliers={catalog.styles}
          benchtopMaterial={benchtopMaterial}
          onSelectBenchtop={setBenchtopMaterial}
          benchtopMetres={benchtopMetres}
          benchtopRates={catalog.benchtops}
          benchtopNames={catalog.benchtop_names}
          quoteId={activeProjectId}
          onSaveRevisions={handleSaveRevisions}
          saveState={saveState}
          saveError={saveError}
          isCollapsed={isInspectorCollapsed}
          onToggleCollapse={() => setIsInspectorCollapsed((v) => !v)}
        />
      </main>
    </div>
  );
};

export default App;
