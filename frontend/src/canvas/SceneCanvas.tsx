import React, { useLayoutEffect, useMemo, useRef } from 'react';
import { Canvas, useThree } from '@react-three/fiber';
import { Html, OrbitControls, OrthographicCamera, PerspectiveCamera } from '@react-three/drei';
import type { OrbitControls as OrbitControlsImpl } from 'three-stdlib';
import * as THREE from 'three';
import { RoomShell } from './RoomShell';
import { LightingRig } from './LightingRig';
import { CabinetMesh } from './CabinetMesh';
import type { CabinetData, CabinetFinish, DoorStyle } from './CabinetMesh';
import { viewExtent } from './floorPlan';
import type { FloorPlan, RoomView } from './floorPlan';

export type CameraView = 'orbit' | 'top' | 'front';

interface SceneCanvasProps {
  wallWidthMm: number;
  wallHeightMm: number;
  returnMm: number;
  roomShape: string;
  cabinets: CabinetData[];
  selectedCabinetId: string | null;
  finish: CabinetFinish;
  doorStyle: DoorStyle;
  mood: 'day' | 'evening';
  cameraView: CameraView;
  /** Changes whenever the view should be re-framed (e.g. "Fit to screen"). */
  fitKey: number;
  onSelectCabinet: (id: string | null) => void;
  /** The floor plan the room was read from, and how much of it to show. */
  floorPlan?: FloorPlan | null;
  roomView?: RoomView;
}

/** The part of the room that has to be on screen. */
interface Bounds {
  minX: number;
  maxX: number;
  /** 0 for the kitchen alone (the main wall's face); less with the plan. */
  minZ: number;
  maxZ: number;
  height: number;
  /** Front of the deepest floor cabinet on the main wall. */
  baseFront: number;
  /** Front of the deepest cabinet on the side wall. */
  sideFront: number;
}

function roomBounds(
  wallW: number,
  wallH: number,
  shape: string,
  returnM: number,
  cabinets: CabinetData[],
  plan: FloorPlan | null,
  roomView: RoomView,
): Bounds {
  const main = cabinets.filter((c) => c.run === 'main' && !c.isWallMounted);
  const side = cabinets.filter((c) => c.run === 'return');
  const baseFront = Math.max(0.6, ...main.map((c) => c.depth));
  const sideFront = Math.max(0, ...side.map((c) => c.depth));
  const sideReach = Math.max(0, ...side.map((c) => c.x + c.width));
  const maxZ = Math.max(baseFront + 0.4, shape === 'lShape' ? Math.max(returnM, sideReach) : 0);
  const kitchen = { minX: shape === 'lShape' ? -0.15 : 0, maxX: wallW, minZ: 0, maxZ, height: wallH, baseFront, sideFront };
  // Room and House frame the plan around the kitchen too.
  const e = plan ? viewExtent(plan, roomView) : null;
  if (!e) return kitchen;
  return {
    ...kitchen,
    minX: Math.min(kitchen.minX, e[0]),
    minZ: Math.min(0, e[1]),
    maxX: Math.max(kitchen.maxX, e[2]),
    maxZ: Math.max(kitchen.maxZ, e[3]),
  };
}

/** Plan view frame: the room plus the dimension lines outside it. */
function planFrame(b: Bounds) {
  const minX = b.minX - (b.minX < 0 ? 0.9 : 0.2);
  const minZ = b.minZ - 0.85;
  return { cx: (minX + b.maxX) / 2, cz: (minZ + b.maxZ) / 2, spanX: b.maxX - minX, spanZ: b.maxZ - minZ };
}

const DIM_COLOR = '#6E6052';

/**
 * Plan = straight down, Elevation = straight at the main wall, both
 * orthographic (true drawings, no perspective) and fitted with room for the
 * dimension lines. 3D = a three-quarter view that fits the whole room.
 */
const ViewRig: React.FC<{ view: CameraView; bounds: Bounds; fitKey: number }> = ({ view, bounds, fitKey }) => {
  const size = useThree((s) => s.size);
  const controls = useRef<OrbitControlsImpl>(null);
  const persp = useRef<THREE.PerspectiveCamera>(null);
  const ortho = useRef<THREE.OrthographicCamera>(null);
  const { minX, maxX, minZ, maxZ, height } = bounds;
  const cx = (minX + maxX) / 2;
  const spanX = maxX - minX;
  const spanZ = maxZ - minZ;
  // What the view looks at. Passed to the controls as a prop too: switching
  // between 3D and Plan swaps camera type, which recreates the controls.
  const target = useMemo<[number, number, number]>(() => {
    if (view === 'top') {
      const f = planFrame(bounds);
      return [f.cx, 0, f.cz];
    }
    if (view === 'front') return [cx, height / 2 - 0.2, 0];
    // With the plan around the kitchen, look at the middle of it all.
    if (minZ < 0) return [cx, 0.5, (minZ + maxZ) / 2];
    return [cx, Math.min(1.0, height / 2), Math.min(maxZ, 1.2) / 2];
  }, [view, cx, minZ, maxZ, height, bounds]);

  // Ortho views re-fit when the canvas resizes; the 3D view keeps whatever
  // angle the designer orbited to until asked (view change or Fit).
  const sizeKey = view === 'orbit' ? 0 : size.width * 10000 + size.height;

  useLayoutEffect(() => {
    const ctl = controls.current;
    const t = new THREE.Vector3(...target);
    if (view === 'orbit') {
      const cam = persp.current;
      if (!cam) return;
      const radius = 0.5 * Math.hypot(spanX, height, spanZ);
      const vFov = THREE.MathUtils.degToRad(cam.fov);
      const hFov = 2 * Math.atan(Math.tan(vFov / 2) * (size.width / Math.max(1, size.height)));
      const dist = (radius / Math.sin(Math.min(vFov, hFov) / 2)) * 0.82;
      // With the plan around the kitchen (minZ < 0), look down more steeply
      // (about 50°) so the near walls don't hide the rooms behind them.
      const dir =
        minZ < 0
          ? new THREE.Vector3(0.3, 1.25, 1).normalize()
          : new THREE.Vector3(maxZ > 1.5 ? 0.55 : 0.32, 0.42, 1).normalize();
      cam.up.set(0, 1, 0);
      cam.position.copy(t).addScaledVector(dir, dist);
      cam.lookAt(t);
      cam.updateProjectionMatrix();
    } else {
      const cam = ortho.current;
      if (!cam) return;
      const margin = 0.9; // metres around the room for dimensions
      if (view === 'top') {
        cam.up.set(0, 0, -1);
        const f = planFrame(bounds);
        cam.position.set(f.cx, height + 6, f.cz);
        cam.zoom = Math.min(size.width / (f.spanX + 0.6), size.height / (f.spanZ + 0.6));
      } else {
        cam.up.set(0, 1, 0);
        cam.position.set(cx, height / 2 - 0.2, maxZ + 12);
        cam.zoom = Math.min(size.width / (spanX + 2 * margin), size.height / (height + 2 * margin));
      }
      cam.lookAt(t);
      cam.updateProjectionMatrix();
    }
    if (ctl) {
      ctl.target.copy(t);
      ctl.update();
    }
  }, [view, fitKey, sizeKey, target, bounds, cx, spanX, spanZ, minZ, maxZ, height, size.width, size.height]);

  return (
    <>
      {view === 'orbit' ? (
        <PerspectiveCamera ref={persp} makeDefault fov={42} near={0.05} far={200} />
      ) : (
        <OrthographicCamera ref={ortho} makeDefault near={0.05} far={200} />
      )}
      <OrbitControls
        ref={controls}
        makeDefault
        target={target}
        enableRotate={view === 'orbit'}
        screenSpacePanning
        minPolarAngle={0}
        maxPolarAngle={Math.PI / 2 - 0.02}
        minDistance={0.8}
        maxDistance={Math.max(10, spanX * 3)}
        minZoom={10}
        maxZoom={2000}
        dampingFactor={0.08}
      />
    </>
  );
};

/** A dimension line from a to b with end ticks, and its label in mm. */
interface Dim {
  a: THREE.Vector3;
  b: THREE.Vector3;
  /** Direction of the end ticks. */
  tick: THREE.Vector3;
  label: string;
}

const mm = (m: number) => Math.round(m * 1000).toLocaleString('en-MY');

function planDims(b: Bounds, cabinets: CabinetData[], shape: string, returnM: number): Dim[] {
  // Drawn outside the room, as on an architect's plan: main-wall sizes
  // behind the main wall, side-wall sizes beyond the side wall.
  const y = b.height + 0.05; // above everything, seen from overhead
  const dims: Dim[] = [];
  const tickZ = new THREE.Vector3(0, 0, 0.08);
  const floor = cabinets.filter((c) => c.run === 'main' && !c.isWallMounted).sort((p, q) => p.x - q.x);
  for (const c of floor) {
    dims.push({ a: new THREE.Vector3(c.x, y, -0.35), b: new THREE.Vector3(c.x + c.width, y, -0.35), tick: tickZ, label: mm(c.width) });
  }
  dims.push({ a: new THREE.Vector3(0, y, -0.7), b: new THREE.Vector3(b.maxX, y, -0.7), tick: tickZ, label: `Wall ${mm(b.maxX)}` });
  if (shape === 'lShape') {
    const tickX = new THREE.Vector3(0.08, 0, 0);
    for (const c of cabinets.filter((k) => k.run === 'return' && !k.isWallMounted).sort((p, q) => p.x - q.x)) {
      dims.push({ a: new THREE.Vector3(-0.5, y, c.x), b: new THREE.Vector3(-0.5, y, c.x + c.width), tick: tickX, label: mm(c.width) });
    }
    dims.push({ a: new THREE.Vector3(-0.85, y, 0), b: new THREE.Vector3(-0.85, y, returnM), tick: tickX, label: `Side wall ${mm(returnM)}` });
  }
  return dims;
}

function elevationDims(b: Bounds, cabinets: CabinetData[]): Dim[] {
  const z = b.maxZ + 1;
  const dims: Dim[] = [];
  const tickY = new THREE.Vector3(0, 0.08, 0);
  const tickX = new THREE.Vector3(0.08, 0, 0);
  const main = cabinets.filter((c) => c.run === 'main');
  for (const c of main.filter((k) => !k.isWallMounted).sort((p, q) => p.x - q.x)) {
    dims.push({ a: new THREE.Vector3(c.x, -0.22, z), b: new THREE.Vector3(c.x + c.width, -0.22, z), tick: tickY, label: mm(c.width) });
  }
  dims.push({ a: new THREE.Vector3(0, -0.55, z), b: new THREE.Vector3(b.maxX, -0.55, z), tick: tickY, label: `Wall ${mm(b.maxX)}` });
  const right = b.maxX + 0.3;
  const hasWorktop = main.some((c) => !c.isWallMounted && !['tall', 'oven', 'fridge'].includes(c.kind));
  if (hasWorktop) {
    dims.push({ a: new THREE.Vector3(right, 0, z), b: new THREE.Vector3(right, 0.89, z), tick: tickX, label: 'Worktop 890' });
  }
  const wallUnit = main.find((c) => c.kind === 'wall');
  if (wallUnit) {
    dims.push({ a: new THREE.Vector3(right + 0.45, 0, z), b: new THREE.Vector3(right + 0.45, wallUnit.mount, z), tick: tickX, label: `Under wall units ${mm(wallUnit.mount)}` });
  }
  dims.push({ a: new THREE.Vector3(right + 0.9, 0, z), b: new THREE.Vector3(right + 0.9, b.height, z), tick: tickX, label: `Ceiling ${mm(b.height)}` });
  return dims;
}

const Dimensions: React.FC<{ dims: Dim[] }> = ({ dims }) => {
  const geometry = useMemo(() => {
    const pts: number[] = [];
    for (const { a, b, tick } of dims) {
      pts.push(a.x, a.y, a.z, b.x, b.y, b.z);
      for (const p of [a, b]) {
        pts.push(p.x - tick.x, p.y - tick.y, p.z - tick.z, p.x + tick.x, p.y + tick.y, p.z + tick.z);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    return g;
  }, [dims]);
  return (
    <group>
      <lineSegments geometry={geometry}>
        <lineBasicMaterial color={DIM_COLOR} />
      </lineSegments>
      {dims.map((d, i) => (
        <Html
          key={i}
          position={d.a.clone().add(d.b).multiplyScalar(0.5)}
          center
          zIndexRange={[10, 0]}
          style={{ pointerEvents: 'none' }}
        >
          <span className="dim-label">{d.label}</span>
        </Html>
      ))}
    </group>
  );
};

export const SceneCanvas: React.FC<SceneCanvasProps> = ({
  wallWidthMm,
  wallHeightMm,
  returnMm,
  roomShape,
  cabinets,
  selectedCabinetId,
  finish,
  doorStyle,
  mood,
  cameraView,
  fitKey,
  onSelectCabinet,
  floorPlan = null,
  roomView: chosenRoomView = 'kitchen',
}) => {
  // An elevation draws the kitchen's main wall straight on; the plan's walls
  // in front of the kitchen would stand in the way, so it shows the kitchen
  // alone.
  const roomView: RoomView = cameraView === 'front' ? 'kitchen' : chosenRoomView;
  const wallW = wallWidthMm / 1000;
  const wallH = wallHeightMm / 1000;
  const returnM = returnMm / 1000;
  const bounds = useMemo(
    () => roomBounds(wallW, wallH, roomShape, returnM, cabinets, floorPlan, roomView),
    [wallW, wallH, roomShape, returnM, cabinets, floorPlan, roomView],
  );
  // The dimension lines measure the kitchen, whatever the view frames.
  const kitchenBounds = useMemo(
    () => roomBounds(wallW, wallH, roomShape, returnM, cabinets, null, 'kitchen'),
    [wallW, wallH, roomShape, returnM, cabinets],
  );
  // Plan is a floor plan (wall units would hide the base units); an
  // elevation shows one wall (side-wall units would stand in front of it).
  const shown = useMemo(
    () =>
      cameraView === 'top'
        ? cabinets.filter((c) => !c.isWallMounted)
        : cameraView === 'front'
          ? cabinets.filter((c) => c.run === 'main')
          : cabinets,
    [cameraView, cabinets],
  );
  const dims = useMemo(
    () =>
      cameraView === 'top'
        ? planDims(kitchenBounds, cabinets, roomShape, returnM)
        : cameraView === 'front'
          ? elevationDims(kitchenBounds, cabinets)
          : [],
    [cameraView, kitchenBounds, cabinets, roomShape, returnM],
  );

  return (
    <div className="relative h-full w-full cursor-grab active:cursor-grabbing">
      <Canvas
        shadows
        // Deselect only when the click hits no cabinet.
        onPointerMissed={() => onSelectCabinet(null)}
        gl={{ antialias: true, toneMapping: THREE.ACESFilmicToneMapping, toneMappingExposure: 1.08 }}
      >
        <color attach="background" args={[mood === 'day' ? '#FAF7F2' : '#201D1A']} />
        <LightingRig mood={mood} />
        <RoomShell
          widthMm={wallWidthMm}
          heightMm={wallHeightMm}
          shape={roomShape}
          returnMm={returnMm}
          floorPlan={floorPlan}
          roomView={roomView}
        />
        {shown.map((cab) => (
          <CabinetMesh
            key={cab.id}
            cabinet={cab}
            isSelected={cab.id === selectedCabinetId}
            finish={finish}
            doorStyle={doorStyle}
            ceiling={wallH}
            onSelect={onSelectCabinet}
          />
        ))}
        {dims.length > 0 && <Dimensions dims={dims} />}
        <ViewRig view={cameraView} bounds={bounds} fitKey={fitKey} />
      </Canvas>
    </div>
  );
};
