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
const CameraViewController: React.FC<{ view: CameraView; targetX: number }> = ({ view, targetX }) => {
  const { camera } = useThree();
  const controlsRef = useRef<any>(null);

  useEffect(() => {
    const target = new THREE.Vector3(targetX, 0.85, 0.4);

    let destPos: THREE.Vector3;
    if (view === 'top') {
      destPos = new THREE.Vector3(targetX, 4.0, 0.41);
    } else if (view === 'front') {
      destPos = new THREE.Vector3(targetX, 1.15, 3.2);
    } else {
      // 3D Orbit default: intimate eye-level view showing both base and wall joinery
      destPos = new THREE.Vector3(targetX + 0.35, 1.45, 3.2);
    }

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
  }, [view, targetX, camera]);

  return (
    <OrbitControls
      ref={controlsRef}
      makeDefault
      target={[targetX, 0.95, 0.35]}
      minPolarAngle={Math.PI / 6}
      maxPolarAngle={Math.PI / 2 + 0.02}
      minDistance={1.2}
      maxDistance={7.0}
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
    <div
      className="w-full h-full relative cursor-grab active:cursor-grabbing"
      onClick={() => onSelectCabinet(null)}
    >
      <Canvas
        shadows
        camera={{ position: [cabinetCenterX + 0.35, 1.45, 3.2], fov: 42 }}
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
        <CameraViewController view={cameraView} targetX={cabinetCenterX} />
      </Canvas>
    </div>
  );
};
