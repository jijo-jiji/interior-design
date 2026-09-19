import React, { useRef, useEffect } from 'react';
import { Canvas, useThree } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import * as THREE from 'three';
import { RoomShell } from './RoomShell';
import { LightingRig } from './LightingRig';
import { CabinetMesh } from './CabinetMesh';
import type { CabinetData, CabinetFinish, DoorStyle } from './CabinetMesh';

export type CameraView = 'orbit' | 'top' | 'front';

interface SceneCanvasProps {
  wallWidthMm: number;
  wallHeightMm: number;
  roomShape: string;
  cabinets: CabinetData[];
  selectedCabinetId: string | null;
  finish: CabinetFinish;
  doorStyle: DoorStyle;
  mood: 'day' | 'evening';
  cameraView: CameraView;
  onSelectCabinet: (id: string | null) => void;
}

// Controller to smoothly animate camera between view angles
const CameraViewController: React.FC<{
  view: CameraView;
  targetX: number;
  wallWidthM: number;
}> = ({ view, targetX, wallWidthM }) => {
  const { camera, size } = useThree();
  const controlsRef = useRef<any>(null);

  useEffect(() => {
    const target = new THREE.Vector3(targetX, 0.85, 0.4);

    // Distance at which `spanM` of wall fills the frame, so plan and elevation
    // show the whole run instead of a close-up of its middle.
    const perspective = camera as THREE.PerspectiveCamera;
    const aspect = perspective.aspect || size.width / Math.max(1, size.height);
    const vFov = ((perspective.fov ?? 42) * Math.PI) / 180;
    const fitDistance = (spanM: number) =>
      Math.max(2.4, spanM / (2 * Math.tan(vFov / 2) * Math.max(0.5, aspect)));

    let destPos: THREE.Vector3;
    if (view === 'top') {
      destPos = new THREE.Vector3(targetX, 0.85 + fitDistance(wallWidthM * 1.15), 0.41);
    } else if (view === 'front') {
      destPos = new THREE.Vector3(targetX, 1.15, 0.4 + fitDistance(wallWidthM * 1.1));
    } else {
      // 3D Orbit default: intimate eye-level view showing both base and wall joinery
      destPos = new THREE.Vector3(targetX + 0.35, 1.45, 3.2);
    }

    // Looking straight down makes the default up vector parallel to the view
    // direction, which leaves the plan at an arbitrary rotation. Point "up"
    // along the room's depth axis instead so plan view lands square.
    camera.up.set(0, view === 'top' ? 0 : 1, view === 'top' ? -1 : 0);
    if (controlsRef.current) controlsRef.current.update();

    // Smooth transition
    let progress = 0;
    const startPos = camera.position.clone();
    const interval = setInterval(() => {
      progress += 0.08;
      if (progress >= 1) {
        camera.position.copy(destPos);
        camera.lookAt(target);
        if (controlsRef.current) {
          controlsRef.current.target.copy(target);
          controlsRef.current.update();
        }
        clearInterval(interval);
      } else {
        camera.position.lerpVectors(startPos, destPos, progress);
        camera.lookAt(target);
      }
    }, 16);

    return () => clearInterval(interval);
  }, [view, targetX, wallWidthM, camera, size.width, size.height]);

  return (
    <OrbitControls
      ref={controlsRef}
      makeDefault
      target={[targetX, 0.95, 0.35]}
      // The plan view sits directly overhead; the 30° floor applies to the
      // other views, where it stops the camera dropping through the ceiling.
      minPolarAngle={view === 'top' ? 0 : Math.PI / 6}
      maxPolarAngle={Math.PI / 2 + 0.02}
      minDistance={1.2}
      // Wide rooms need to pull back further than the old fixed 7m ceiling.
      maxDistance={Math.max(7, wallWidthM * 2.2)}
      dampingFactor={0.08}
    />
  );
};

export const SceneCanvas: React.FC<SceneCanvasProps> = ({
  wallWidthMm,
  wallHeightMm,
  roomShape,
  cabinets,
  selectedCabinetId,
  finish,
  doorStyle,
  mood,
  cameraView,
  onSelectCabinet,
}) => {
  const wallWidthM = wallWidthMm / 1000;
  
  // Calculate average center of all cabinets
  const cabinetCenterX = cabinets.length > 0
    ? cabinets.reduce((sum, c) => sum + (c.x + c.width / 2), 0) / cabinets.length
    : wallWidthM / 2;

  return (
    <div className="w-full h-full relative cursor-grab active:cursor-grabbing">
      <Canvas
        shadows
        camera={{ position: [cabinetCenterX + 0.35, 1.45, 3.2], fov: 42 }}
        // Deselect only when the click hits no module. A DOM handler on the
        // wrapper would also fire for clicks on a cabinet — R3F's
        // stopPropagation cannot stop the native event bubbling out of the
        // canvas — which made modules impossible to select.
        onPointerMissed={() => onSelectCabinet(null)}
        gl={{
          antialias: true,
          toneMapping: THREE.ACESFilmicToneMapping,
          toneMappingExposure: 1.08,
        }}
      >
        {/* Harmonious Studio Background matching Earthy Palette */}
        <color attach="background" args={[mood === 'day' ? '#FAF7F2' : '#201D1A']} />

        {/* Architectural Environment & Lighting */}
        <LightingRig mood={mood} />

        {/* Room Shell (Plank Flooring, Lime-Wash Walls, Skirting) */}
        <RoomShell
          widthMm={wallWidthMm}
          heightMm={wallHeightMm}
          shape={roomShape}
        />

        {/* Dynamic Cabinet Joinery Modules */}
        <group position={[0, 0, 0]}>
          {cabinets.map((cab) => (
            <CabinetMesh
              key={cab.id}
              cabinet={cab}
              isSelected={cab.id === selectedCabinetId}
              finish={finish}
              doorStyle={doorStyle}
              onSelect={(id) => onSelectCabinet(id)}
            />
          ))}
        </group>

        {/* Camera View Controls */}
        <CameraViewController
          view={cameraView}
          targetX={cabinetCenterX}
          wallWidthM={wallWidthM}
        />
      </Canvas>
    </div>
  );
};
