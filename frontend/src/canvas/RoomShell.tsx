import React, { useMemo } from 'react';
import { createPlankOakTexture, createPlasterWallTexture } from './materials';

interface RoomShellProps {
  widthMm: number;
  heightMm: number;
  shape: string;
  returnMm?: number;
  aisleMm?: number;
}

export const RoomShell: React.FC<RoomShellProps> = ({
  widthMm,
  heightMm,
  shape,
  returnMm = 2400,
  aisleMm = 1800,
}) => {
  const wallWidth = widthMm / 1000;
  const wallHeight = heightMm / 1000;
  const returnLength = returnMm / 1000;
  const aisleDist = aisleMm / 1000;

  // Flooring PBR textures
  const { map: floorMap, bumpMap: floorBump } = useMemo(() => createPlankOakTexture(), []);
  const wallMap = useMemo(() => createPlasterWallTexture(), []);

  // Architectural dimensions
  const floorWidth = Math.max(20, wallWidth + 12);
  const floorLength = Math.max(20, returnLength + 12);
  const backWallWidth = Math.max(18, wallWidth + 12);

  // Set seamless texture repeats
  floorMap.repeat.set(5, 5);
  floorBump.repeat.set(5, 5);
  wallMap.repeat.set(6, 3);

  return (
    <group position={[0, 0, 0]}>
      {/* ── Continuous Wide-Plank Oak Floor ───────────────────────────── */}
      <mesh
        rotation={[-Math.PI / 2, 0, 0]}
        position={[wallWidth / 2, 0, floorLength / 2 - 4]}
        receiveShadow
      >
        <planeGeometry args={[floorWidth, floorLength]} />
        <meshStandardMaterial
          map={floorMap}
          bumpMap={floorBump}
          bumpScale={0.008}
          roughness={0.42}
          metalness={0.04}
          color="#D4C0A8"
        />
      </mesh>

      {/* ── Main Back Wall (Continuous Architectural Backdrop) ──────── */}
      <mesh
        position={[wallWidth / 2, wallHeight / 2 + 0.5, -0.075]}
        receiveShadow
        castShadow
      >
        <boxGeometry args={[backWallWidth, wallHeight + 1.0, 0.15]} />
        <meshStandardMaterial
          map={wallMap}
          roughness={0.88}
          metalness={0.01}
          color="#EEE4E1"
        />
      </mesh>

      {/* ── Architectural 100mm Skirting Baseboard (Back Wall) ───────── */}
      <mesh
        position={[wallWidth / 2, 0.05, 0.005]}
        castShadow
        receiveShadow
      >
        <boxGeometry args={[backWallWidth, 0.1, 0.015]} />
        <meshStandardMaterial
          roughness={0.5}
          metalness={0.05}
          color="#E5DDD3"
        />
      </mesh>

      {/* ── Return Wall (L-Shape) ─────────────────────────────────────── */}
      {shape === 'lShape' && (
        <group position={[0, 0, 0]}>
          <mesh
            position={[-0.075, wallHeight / 2, returnLength / 2]}
            receiveShadow
            castShadow
          >
            <boxGeometry args={[0.15, wallHeight, returnLength]} />
            <meshStandardMaterial
              map={wallMap}
              roughness={0.88}
              metalness={0.01}
              color="#EEE4E1"
            />
          </mesh>

          {/* Return Wall Baseboard */}
          <mesh
            position={[0.005, 0.05, returnLength / 2]}
            castShadow
            receiveShadow
          >
            <boxGeometry args={[0.015, 0.1, returnLength]} />
            <meshStandardMaterial
              roughness={0.5}
              metalness={0.05}
              color="#E5DDD3"
            />
          </mesh>

          {/* Architectural Window with Timber Frame */}
          <group position={[0.005, wallHeight * 0.6, returnLength * 0.5]}>
            {/* Window Glass */}
            <mesh position={[0, 0, 0]}>
              <boxGeometry args={[0.01, wallHeight * 0.45, returnLength * 0.35]} />
              <meshStandardMaterial
                color="#ECF8F8"
                roughness={0.15}
                metalness={0.1}
              />
            </mesh>
            {/* Window Timber Frame Trim */}
            <mesh position={[0.004, 0, 0]}>
              <boxGeometry args={[0.015, wallHeight * 0.47, returnLength * 0.37]} />
              <meshStandardMaterial color="#B2967D" roughness={0.4} />
            </mesh>
          </group>
        </group>
      )}

      {/* ── Galley Parallel Wall ──────────────────────────────────────── */}
      {shape === 'galley' && (
        <group position={[0, 0, aisleDist]}>
          <mesh
            position={[wallWidth / 2, wallHeight / 2, 0.075]}
            receiveShadow
            castShadow
          >
            <boxGeometry args={[wallWidth, wallHeight, 0.15]} />
            <meshStandardMaterial
              map={wallMap}
              roughness={0.88}
              metalness={0.01}
              color="#EEE4E1"
            />
          </mesh>

          <mesh
            position={[wallWidth / 2, 0.05, -0.005]}
            castShadow
            receiveShadow
          >
            <boxGeometry args={[wallWidth, 0.1, 0.015]} />
            <meshStandardMaterial
              roughness={0.5}
              metalness={0.05}
              color="#E5DDD3"
            />
          </mesh>
        </group>
      )}
    </group>
  );
};
