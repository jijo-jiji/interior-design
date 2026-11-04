import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { SceneCanvas } from './canvas/SceneCanvas';
import type { CameraView } from './canvas/SceneCanvas';
import { readFloorPlan } from './canvas/floorPlan';
import type { FloorPlan, RoomView } from './canvas/floorPlan';
import type { CabinetFinish, DoorStyle } from './canvas/cabinetBuilder';
import type { WallOpening } from './canvas/RoomShell';
import { Header } from './components/Header';
import { ProjectPipelineDrawer } from './components/ProjectPipelineDrawer';
import type { ProjectItem } from './components/ProjectPipelineDrawer';
import { JoineryInspector } from './components/JoineryInspector';
import type { InspectorTab, SaveState } from './components/JoineryInspector';
import { StudioToolbar } from './components/StudioToolbar';
import type { CabinetData, ModuleType } from './layout/model';
import { fromEntry, newModule, toEntry } from './layout/model';
import { FALLBACK_CATALOG, benchtopLinearMetres, priceLayout } from './pricing';
import type { Catalog } from './pricing';

const DEMO_PROJECT_ID = 'QT-992AC14B';
const NUDGE_M = 0.05;
const DEFAULT_WALL_DEPTH_MM = 150;

/** Sample layout shown until the office server answers. */
const DEMO_CABINETS: CabinetData[] = [
  { ...newModule('base_800', 0.2), id: 'cab-1' },
  { ...newModule('sink_600', 1.0), id: 'cab-2' },
  { ...newModule('base_600', 1.6), id: 'cab-3' },
  { ...newModule('wall_600', 1.0), id: 'cab-4' },
];

/** First gap on the same level of the main wall that fits [width]. */
const findFreeX = (existing: CabinetData[], width: number, wallWidthM: number, wallMounted: boolean): number => {
  const row = existing
    .filter((c) => c.run === 'main' && c.isWallMounted === wallMounted)
    .sort((a, b) => a.x - b.x);
  let cursor = 0;
  for (const cab of row) {
    if (cab.x - cursor >= width) return cursor;
    cursor = Math.max(cursor, cab.x + cab.width);
  }
  return Math.max(0, Math.min(cursor, wallWidthM - width));
};

export const App: React.FC = () => {
  // ─── Client ────────────────────────────────────────────────────────────────
  const [projects, setProjects] = useState<ProjectItem[]>([]);
  const [activeProjectId, setActiveProjectId] = useState<string>(DEMO_PROJECT_ID);
  const [clientName, setClientName] = useState<string>('Sample client');
  const [isPipelineOpen, setIsPipelineOpen] = useState<boolean>(false);
  const [isSyncing, setIsSyncing] = useState<boolean>(false);
  const [isOffline, setIsOffline] = useState<boolean>(false);
  const hasLoadedInitialProject = useRef(false);

  // ─── Room ──────────────────────────────────────────────────────────────────
  /** The wall as stored, so saving keeps fields the studio doesn't edit
   *  (thickness, how it was measured…). */
  const [wallRecord, setWallRecord] = useState<Record<string, unknown>>({});
  const [wallWidthMm, setWallWidthMm] = useState<number>(3600);
  const [wallHeightMm, setWallHeightMm] = useState<number>(2400);
  const [returnMm, setReturnMm] = useState<number>(2400);
  const [roomShape, setRoomShape] = useState<string>('singleWall');
  const [openings, setOpenings] = useState<WallOpening[]>([]);
  const [benchtopMaterial, setBenchtopMaterial] = useState<string | null>(null);

  // ─── Look and view ─────────────────────────────────────────────────────────
  const [finish, setFinish] = useState<CabinetFinish>('japandi');
  const [doorStyle, setDoorStyle] = useState<DoorStyle>('slab');
  const [lightingMood, setLightingMood] = useState<'day' | 'evening'>('day');
  const [cameraView, setCameraView] = useState<CameraView>('orbit');
  // The floor plan the room was read from (sales app), for Room / House.
  const [floorPlan, setFloorPlan] = useState<FloorPlan | null>(null);
  const [roomView, setRoomView] = useState<RoomView>('kitchen');
  const [fitKey, setFitKey] = useState(0);
  const [inspectorTab, setInspectorTab] = useState<InspectorTab>('cabinets');
  const [isInspectorCollapsed, setIsInspectorCollapsed] = useState<boolean>(false);

  // ─── Cabinets ──────────────────────────────────────────────────────────────
  const [cabinets, setCabinets] = useState<CabinetData[]>(DEMO_CABINETS);
  const [selectedCabinetId, setSelectedCabinetId] = useState<string | null>(null);
  const [undoStack, setUndoStack] = useState<CabinetData[][]>([]);

  // ─── Pricing and saving ────────────────────────────────────────────────────
  const [catalog, setCatalog] = useState<Catalog>(FALLBACK_CATALOG);
  const [saveState, setSaveState] = useState<SaveState>('idle');
  const [saveError, setSaveError] = useState<string | null>(null);

  // ─── Opening a client ──────────────────────────────────────────────────────
  const loadProject = useCallback((proj: ProjectItem) => {
    const projId = proj.quote_id || proj.id;
    if (projId) setActiveProjectId(projId);
    setClientName(proj.client_name || 'Unnamed client');
    setSaveState('idle');
    setSaveError(null);
    setUndoStack([]);

    const wall = (proj.wall ?? {}) as Record<string, unknown>;
    const widthMm = Number(wall.width_mm) || 3600;
    setWallRecord(wall);
    setWallWidthMm(widthMm);
    setWallHeightMm(Number(wall.height_mm) || 2400);
    setReturnMm(Number(wall.return_mm) || 2400);
    setOpenings(Array.isArray(proj.obstacles) ? proj.obstacles : []);
    setFloorPlan(readFloorPlan(proj.floor_plan));
    setRoomView('kitchen');
    setBenchtopMaterial(proj.benchtop_material ?? null);

    const styleKey = proj.style_archetype || proj.style;
    if (styleKey && ['japandi', 'nordic', 'minimalist', 'industrial'].includes(styleKey)) {
      setFinish(styleKey as CabinetFinish);
    }

    const raw = (proj.cabinets || proj.placed_cabinets || []) as Record<string, unknown>[];
    const mapped = raw.map((c, i) => fromEntry(c, i, widthMm / 1000));
    // A side-wall cabinet means an L-shape even if the record didn't say so.
    const shape = String(wall.shape || (mapped.some((c) => c.run === 'return') ? 'lShape' : 'singleWall'));
    setRoomShape(shape);
    setCabinets(mapped);
    setSelectedCabinetId(null);
    setFitKey((k) => k + 1);
  }, []);

  // ─── Office server ─────────────────────────────────────────────────────────
  const fetchProjects = useCallback(async () => {
    try {
      const res = await fetch('/api/projects');
      if (!res.ok) throw new Error(`Client list request failed (${res.status})`);
      const data: ProjectItem[] = await res.json();
      setProjects(data);
      setIsOffline(false);
      // Only the first refresh opens a client; later ones leave the open work alone.
      if (!hasLoadedInitialProject.current) {
        const initial = data.find((p) => (p.quote_id || p.id) === DEMO_PROJECT_ID) || data[0];
        if (initial) {
          hasLoadedInitialProject.current = true;
          loadProject(initial);
        }
      }
    } catch (err) {
      console.warn("Can't reach the office server; showing sample data.", err);
      setIsOffline(true);
    }
  }, [loadProject]);

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
        if (!res.ok) throw new Error(`Catalogue request failed (${res.status})`);
        const data = await res.json();
        if (!cancelled) setCatalog({ ...FALLBACK_CATALOG, ...data });
      } catch (err) {
        console.warn("Can't load the price list; using built-in rates.", err);
        if (!cancelled) setIsOffline(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // ─── Editing cabinets ──────────────────────────────────────────────────────
  // Updaters stay pure (StrictMode runs them twice), so history and adding
  // read the live layout through refs.
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

  const selectCabinet = useCallback((id: string | null) => {
    setSelectedCabinetId(id);
    if (id) {
      setInspectorTab('cabinets');
      setIsInspectorCollapsed(false);
    }
  }, []);

  const handleAddModule = useCallback(
    (type: ModuleType) => {
      recordHistory();
      const probe = newModule(type, 0);
      const x = findFreeX(cabinetsRef.current, probe.width, wallWidthMm / 1000, probe.isWallMounted);
      const cab = { ...probe, x };
      setCabinets((prev) => [...prev, cab]);
      selectCabinet(cab.id);
    },
    [recordHistory, selectCabinet, wallWidthMm],
  );

  const handleNudgeCabinet = useCallback(
    (direction: -1 | 1) => {
      if (!selectedCabinetId) return;
      recordHistory();
      setCabinets((prev) =>
        prev.map((c) => {
          if (c.id !== selectedCabinetId) return c;
          const runLength = c.run === 'return' ? returnMm / 1000 : wallWidthMm / 1000;
          const maxX = Math.max(0, runLength - c.width);
          return { ...c, x: Math.max(0, Math.min(maxX, Math.round((c.x + direction * NUDGE_M) * 1000) / 1000)) };
        }),
      );
    },
    [recordHistory, selectedCabinetId, wallWidthMm, returnMm],
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

  // Shrinking a wall must not leave cabinets hanging past it.
  const clampRun = (run: 'main' | 'return', lengthM: number) =>
    setCabinets((prev) =>
      prev.map((c) => {
        if (c.run !== run) return c;
        const maxX = Math.max(0, lengthM - c.width);
        return c.x > maxX ? { ...c, x: maxX } : c;
      }),
    );
  const handleChangeWallWidth = useCallback((mm: number) => {
    setWallWidthMm(mm);
    clampRun('main', mm / 1000);
  }, []);
  const handleChangeReturn = useCallback((mm: number) => {
    setReturnMm(mm);
    clampRun('return', mm / 1000);
  }, []);

  // ─── Price (same formula as the backend quote) ─────────────────────────────
  const totals = useMemo(
    () => priceLayout(cabinets, openings, finish, catalog, benchtopMaterial),
    [cabinets, openings, finish, catalog, benchtopMaterial],
  );
  const benchtopMetres = useMemo(() => benchtopLinearMetres(cabinets), [cabinets]);

  const handleSaveRevisions = useCallback(async () => {
    setSaveState('saving');
    setSaveError(null);
    const wallM = wallWidthMm / 1000;
    const payload = {
      // Positions in the sales app's convention too, so the tablet, the PDF
      // and the CAD export all see the same layout.
      cabinets: cabinets.map((c) => toEntry(c, wallM)),
      style: finish,
      style_archetype: finish,
      benchtop_material: benchtopMaterial,
      wall: {
        ...wallRecord,
        depth_mm: wallRecord.depth_mm ?? DEFAULT_WALL_DEPTH_MM,
        width_mm: wallWidthMm,
        height_mm: wallHeightMm,
        shape: roomShape,
        return_mm: roomShape === 'lShape' ? returnMm : (wallRecord.return_mm ?? 0),
      },
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
            ? "This client isn't on the office server yet, so there's nothing to update."
            : `The office server refused the change (${res.status}).`,
        );
      }
      setSaveState('saved');
      fetchProjects();
    } catch (err) {
      console.error('Saving failed:', err);
      setSaveState('error');
      setSaveError(err instanceof Error ? err.message : "Couldn't save. Try again.");
    }
  }, [activeProjectId, benchtopMaterial, cabinets, fetchProjects, finish, returnMm, roomShape, totals, wallHeightMm, wallRecord, wallWidthMm]);

  const showPrice = useCallback(() => {
    setInspectorTab('price');
    setIsInspectorCollapsed(false);
  }, []);

  return (
    <div className="grid h-full w-full grid-rows-[auto_auto_1fr] overflow-hidden bg-canvas select-none">
      <Header
        cameraView={cameraView}
        onSelectCameraView={(v) => {
          setCameraView(v);
          setFitKey((k) => k + 1);
        }}
        hasFloorPlan={floorPlan != null}
        roomView={roomView}
        onSelectRoomView={(v) => {
          setRoomView(v);
          setFitKey((k) => k + 1);
        }}
        lightingMood={lightingMood}
        onToggleMood={() => setLightingMood((m) => (m === 'day' ? 'evening' : 'day'))}
        quoteId={activeProjectId}
        clientName={clientName}
        onSync={handleSync}
        isSyncing={isSyncing}
        isOffline={isOffline}
        onOpenPipeline={() => setIsPipelineOpen(true)}
      />

      <StudioToolbar
        onAddModule={handleAddModule}
        onUndo={handleUndo}
        canUndo={undoStack.length > 0}
        onDeleteSelected={() => selectedCabinetId && handleDeleteCabinet(selectedCabinetId)}
        onNudgeSelected={handleNudgeCabinet}
        hasSelected={selectedCabinetId !== null}
        hotkeysEnabled={!isPipelineOpen}
        onFit={() => setFitKey((k) => k + 1)}
        total={totals.total}
        onShowPrice={showPrice}
      />

      <ProjectPipelineDrawer
        isOpen={isPipelineOpen}
        onClose={() => setIsPipelineOpen(false)}
        projects={projects}
        activeProjectId={activeProjectId}
        onSelectProject={loadProject}
      />

      {/* View and panel share the row, so the panel never covers the model. */}
      <main className="flex min-h-0 min-w-0">
        <section className="relative min-h-0 min-w-0 flex-1" aria-label="Kitchen view">
          <SceneCanvas
            wallWidthMm={wallWidthMm}
            wallHeightMm={wallHeightMm}
            returnMm={returnMm}
            roomShape={roomShape}
            cabinets={cabinets}
            selectedCabinetId={selectedCabinetId}
            finish={finish}
            doorStyle={doorStyle}
            mood={lightingMood}
            cameraView={cameraView}
            fitKey={fitKey}
            onSelectCabinet={selectCabinet}
            floorPlan={floorPlan}
            roomView={roomView}
          />
          {cameraView !== 'orbit' && (
            <p className="pointer-events-none absolute bottom-3 left-3 rounded-lg bg-surface/90 px-2 py-1 text-xs text-ink-soft">
              {cameraView === 'top' ? 'Plan · wall units not shown' : 'Elevation · main wall'} · sizes in mm ·
              scroll to zoom, drag to move
            </p>
          )}
        </section>

        <JoineryInspector
          tab={inspectorTab}
          onSelectTab={setInspectorTab}
          roomShape={roomShape}
          onSelectShape={(s) => {
            setRoomShape(s);
            setFitKey((k) => k + 1);
          }}
          wallWidthMm={wallWidthMm}
          onChangeWallWidth={handleChangeWallWidth}
          wallHeightMm={wallHeightMm}
          onChangeWallHeight={setWallHeightMm}
          returnMm={returnMm}
          onChangeReturn={handleChangeReturn}
          finish={finish}
          onSelectFinish={setFinish}
          styleNames={catalog.style_names}
          styleMultipliers={catalog.styles}
          doorStyle={doorStyle}
          onSelectDoorStyle={setDoorStyle}
          benchtopMaterial={benchtopMaterial}
          onSelectBenchtop={setBenchtopMaterial}
          benchtopMetres={benchtopMetres}
          benchtopRates={catalog.benchtops}
          benchtopNames={catalog.benchtop_names}
          cabinets={cabinets}
          selectedCabinetId={selectedCabinetId}
          onSelectCabinet={selectCabinet}
          onNudgeCabinet={handleNudgeCabinet}
          onDeleteCabinet={handleDeleteCabinet}
          totals={totals}
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
