import React, { useEffect, useLayoutEffect, useMemo } from 'react';
import * as THREE from 'three';
import { createPlankOakTexture, createPlasterWallTexture } from './materials';
import { finishSet, useTextureVersion } from './finishTextures';
import { wallsFor } from './floorPlan';
import type { FloorPlan, RoomView } from './floorPlan';

/** A window or door measured on the main wall by the sales app. */
export interface WallOpening {
  type: string;
  distance_from_left_mm?: number;
  distance_from_floor_mm?: number;
  width_mm?: number;
  height_mm?: number;
}

interface RoomShellProps {
  widthMm: number;
  heightMm: number;
  shape: string;
  returnMm?: number;
  aisleMm?: number;
  openings?: WallOpening[];
  /** The floor plan the room was read from, for the Room and House views. */
  floorPlan?: FloorPlan | null;
  roomView?: RoomView;
}

/** The floor plan's picture, laid on the floor at true size. */
const PlanSheet: React.FC<{ plan: FloorPlan }> = ({ plan }) => {
  const texture = useMemo(() => {
    if (!plan.image) return null;
    const t = new THREE.TextureLoader().load(plan.image);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
  }, [plan.image]);
  useEffect(() => () => texture?.dispose(), [texture]);
  if (!texture) return null;
  const [cx, cz] = plan.imageCenterMm;
  const [w, h] = plan.imageSizeMm;
  return (
    <group position={[cx / 1000, 0.004, cz / 1000]} rotation={[0, (plan.imageRotationDeg * Math.PI) / 180, 0]}>
      <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
        <planeGeometry args={[w / 1000, h / 1000]} />
        <meshStandardMaterial map={texture} roughness={0.95} />
      </mesh>
    </group>
  );
};

/** Windows and doors where they were measured, so the designer works around
 *  the real wall (the studio used to ignore them). */
const Opening: React.FC<{ o: WallOpening }> = ({ o }) => {
  const w = (o.width_mm ?? 900) / 1000;
  const h = (o.height_mm ?? (o.type === 'door' ? 2100 : 1000)) / 1000;
  const x = (o.distance_from_left_mm ?? 0) / 1000 + w / 2;
  const y = (o.distance_from_floor_mm ?? (o.type === 'door' ? 0 : 1000)) / 1000 + h / 2;
  const t = 0.05; // frame
  const isDoor = o.type === 'door';
  return (
    <group position={[x, y, 0.004]}>
      <mesh>
        <planeGeometry args={[w - 2 * t, h - (isDoor ? t : 2 * t)]} />
        <meshStandardMaterial
          color={isDoor ? '#B79C82' : '#CFE3EA'}
          roughness={isDoor ? 0.6 : 0.15}
          metalness={isDoor ? 0 : 0.1}
        />
      </mesh>
      {[
        [0, h / 2 - t / 2, w, t],
        ...(isDoor ? [] : [[0, -h / 2 + t / 2, w, t]]),
        [-w / 2 + t / 2, 0, t, h],
        [w / 2 - t / 2, 0, t, h],
      ].map(([fx, fy, fw, fh], i) => (
        <mesh key={i} position={[fx, fy, 0.01]}>
          <boxGeometry args={[fw, fh, 0.03]} />
          <meshStandardMaterial color="#F4F1EC" roughness={0.5} />
        </mesh>
      ))}
    </group>
  );
};

export const RoomShell: React.FC<RoomShellProps> = ({
  widthMm,
  heightMm,
  shape,
  returnMm = 2400,
  aisleMm = 1800,
  openings = [],
  floorPlan = null,
  roomView = 'kitchen',
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
  // In Kitchen view the main wall runs on as a backdrop; with the plan's
  // other walls showing it stops where the kitchen does.
  const showPlan = roomView !== 'kitchen' && floorPlan != null;
  const backWallWidth = showPlan ? wallWidth : Math.max(18, wallWidth + 12);
  // The backdrop also rises past the ceiling; among the plan's walls it
  // stands as tall as they do.
  const backWallRise = showPlan ? 0 : 1.0;
  const planWalls = useMemo(
    () => (showPlan ? wallsFor(floorPlan!, roomView, widthMm, shape === 'lShape' ? returnMm : 0) : []),
    [showPlan, floorPlan, roomView, widthMm, shape, returnMm],
  );

  // The floor's real planks, once they have decoded (the drawn ones stand in
  // until then); the textures are shared, so their repeat is set here.
  const textureVersion = useTextureVersion();
  // oxlint-disable-next-line react-hooks/exhaustive-deps
  const floorSet = useMemo(() => finishSet('floor_oak'), [textureVersion]);
  useLayoutEffect(() => {
    if (!floorSet) return;
    for (const t of [floorSet.map, floorSet.normalMap, floorSet.roughnessMap]) {
      t?.repeat.set(floorWidth / floorSet.tile, floorLength / floorSet.tile);
    }
  }, [floorSet, floorWidth, floorLength]);

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
        {floorSet ? (
          <meshStandardMaterial
            key="floor-textured"
            map={floorSet.map}
            normalMap={floorSet.normalMap}
            normalScale={[0.6, 0.6]}
            roughnessMap={floorSet.roughnessMap}
            roughness={floorSet.roughnessMap ? 1 : 0.42}
            metalness={0.02}
          />
        ) : (
          <meshStandardMaterial
            key="floor-drawn"
            map={floorMap}
            bumpMap={floorBump}
            bumpScale={0.008}
            roughness={0.42}
            metalness={0.04}
            color="#D4C0A8"
          />
        )}
      </mesh>

      {/* ── Main Back Wall (Continuous Architectural Backdrop) ──────── */}
      <mesh
        position={[wallWidth / 2, (wallHeight + backWallRise) / 2, -0.075]}
        receiveShadow
        castShadow
      >
        <boxGeometry args={[backWallWidth, wallHeight + backWallRise, 0.15]} />
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

      {openings.map((o, i) => (
        <Opening key={i} o={o} />
      ))}

      {/* ── The floor plan around the kitchen (Room / House) ─────────── */}
      {roomView === 'house' && floorPlan && <PlanSheet plan={floorPlan} />}
      {planWalls.map((w, i) => (
        <mesh key={i} position={[w.x, wallHeight / 2, w.z]} castShadow receiveShadow>
          <boxGeometry args={[w.width, wallHeight, w.depth]} />
          <meshStandardMaterial map={wallMap} roughness={0.88} metalness={0.01} color="#EAE2DA" />
        </mesh>
      ))}

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
