import React, { useMemo } from 'react';
import * as THREE from 'three';
import { createCabinetWoodTexture, createCalacattaMarbleTexture } from './materials';

export type DoorStyle = 'slab' | 'shaker' | 'fluted';
export type CabinetFinish = 'japandi' | 'nordic' | 'minimalist' | 'industrial';

/** `corner_900` only ever arrives from mobile traces; the studio cannot spawn it. */
export type CabinetType =
  | 'base_800'
  | 'base_600'
  | 'wall_600'
  | 'tall_600'
  | 'corner_900'
  | 'sink_600'
  | 'cooktop_600'
  | 'dishwasher_600'
  | 'oven_tower_600'
  | 'fridge_recess_700'
  | 'rangehood_900';

/** Modules that hang on the wall rather than stand on the floor. */
const WALL_MOUNTED: string[] = ['wall_600', 'rangehood_900'];
/** Full-height modules: no benchtop over them. */
const FULL_HEIGHT: string[] = ['tall_600', 'oven_tower_600', 'fridge_recess_700'];
/** Appliance fronts read as steel, not timber. */
const APPLIANCE_FRONTS: string[] = [
  'dishwasher_600', 'oven_tower_600', 'fridge_recess_700', 'rangehood_900',
];

export interface CabinetData {
  id: string;
  type: CabinetType;
  x: number; // in meters along wall
  width: number;
  height: number;
  depth: number;
  isWallMounted?: boolean;
}

interface FinishSpec {
  base: string;
  grain: string;
  carcaseColor: string;
  handleColor: string;
  roughness: number;
}

const FINISH_SPECS: Record<CabinetFinish, FinishSpec> = {
  japandi: {
    base: '#D4C0A8',
    grain: 'rgba(160, 135, 110, 0.25)',
    carcaseColor: '#C8B39B',
    handleColor: '#D4B982', // Champagne gold
    roughness: 0.35,
  },
  nordic: {
    base: '#EAE1D5',
    grain: 'rgba(180, 160, 140, 0.2)',
    carcaseColor: '#EEE4E1',
    handleColor: '#C8A97E', // Soft brass
    roughness: 0.4,
  },
  minimalist: {
    base: '#F0EAE1',
    grain: 'rgba(215, 205, 195, 0.15)',
    carcaseColor: '#EEE4E1',
    handleColor: '#2C2724', // Matte graphite
    roughness: 0.55,
  },
  industrial: {
    base: '#4A4038',
    grain: 'rgba(30, 25, 20, 0.35)',
    carcaseColor: '#3C342E',
    handleColor: '#1A1816', // Dark steel
    roughness: 0.45,
  },
};

// Each texture is a 1024² canvas. Building one per cabinet made every added
// module noticeably slower, so they are generated once and shared.
const woodTextureCache = new Map<CabinetFinish, THREE.CanvasTexture>();
let marbleTextureCache: THREE.CanvasTexture | null = null;

const getWoodTexture = (finish: CabinetFinish): THREE.CanvasTexture => {
  const cached = woodTextureCache.get(finish);
  if (cached) return cached;
  const spec = FINISH_SPECS[finish] ?? FINISH_SPECS.japandi;
  const texture = createCabinetWoodTexture(spec.base, spec.grain);
  woodTextureCache.set(finish, texture);
  return texture;
};

const getMarbleTexture = (): THREE.CanvasTexture => {
  marbleTextureCache ??= createCalacattaMarbleTexture();
  return marbleTextureCache;
};

interface CabinetMeshProps {
  cabinet: CabinetData;
  isSelected: boolean;
  finish: CabinetFinish;
  doorStyle: DoorStyle;
  onSelect: (id: string) => void;
}

export const CabinetMesh: React.FC<CabinetMeshProps> = ({
  cabinet,
  isSelected,
  finish,
  doorStyle,
  onSelect,
}) => {
  const { width, height, depth, x, type } = cabinet;
  const isWall = WALL_MOUNTED.includes(type);
  const isTall = FULL_HEIGHT.includes(type);
  const isBase = !isWall && !isTall;
  const isAppliance = APPLIANCE_FRONTS.includes(type);

  // Elevation placement
  const elevation = isWall ? 1.48 : 0;
  const toeKickHeight = isWall ? 0 : 0.15;
  const carcaseHeight = isWall ? height : (isTall ? height - toeKickHeight : 0.72);
  const benchtopThickness = isWall || isTall ? 0 : 0.02;

  // Materials based on finish (textures are shared across every module)
  const spec = FINISH_SPECS[finish] ?? FINISH_SPECS.japandi;
  // Integrated appliances show a brushed steel front whatever the joinery finish.
  const carcaseColor = isAppliance ? '#C3C7CA' : spec.carcaseColor;
  const handleColor = isAppliance ? '#8A9095' : spec.handleColor;
  const roughness = isAppliance ? 0.3 : spec.roughness;
  const woodMap = useMemo(() => getWoodTexture(finish), [finish]);
  const marbleTexture = useMemo(() => getMarbleTexture(), []);

  // Center X relative to wall start
  const posX = x + width / 2;
  const posY = elevation + toeKickHeight + carcaseHeight / 2;
  const posZ = depth / 2;

  const isDoubleDoor = type === 'base_800';

  return (
    <group
      position={[posX, 0, posZ]}
      onClick={(e) => {
        e.stopPropagation();
        onSelect(cabinet.id);
      }}
    >
      {/* ── 150mm Recessed Toe-Kick Plinth (Base & Tall units) ──────── */}
      {!isWall && (
        <mesh
          position={[0, toeKickHeight / 2, -0.025]}
          castShadow
          receiveShadow
        >
          <boxGeometry args={[width, toeKickHeight, depth - 0.05]} />
          <meshStandardMaterial color="#2C2724" roughness={0.8} />
        </mesh>
      )}

      {/* ── Main Carcase Box ────────────────────────────────────────── */}
      <mesh
        position={[0, posY, 0]}
        castShadow
        receiveShadow
      >
        <boxGeometry args={[width - 0.004, carcaseHeight, depth]} />
        <meshStandardMaterial
          map={woodMap}
          color={carcaseColor}
          roughness={roughness}
          metalness={0.03}
        />
      </mesh>

      {/* ── Doors / Drawer Fronts ───────────────────────────────────── */}
      <group position={[0, posY, depth / 2 + 0.01]}>
        {isDoubleDoor ? (
          // Two side-by-side doors for 800mm base
          <>
            {/* Left Door */}
            <mesh position={[-width / 4 + 0.002, 0, 0]} castShadow receiveShadow>
              <boxGeometry args={[width / 2 - 0.006, carcaseHeight - 0.008, 0.018]} />
              <meshStandardMaterial map={woodMap} color={carcaseColor} roughness={roughness} />
            </mesh>
            {/* Right Door */}
            <mesh position={[width / 4 - 0.002, 0, 0]} castShadow receiveShadow>
              <boxGeometry args={[width / 2 - 0.006, carcaseHeight - 0.008, 0.018]} />
              <meshStandardMaterial map={woodMap} color={carcaseColor} roughness={roughness} />
            </mesh>
          </>
        ) : (
          // Single Door / Drawer front
          <mesh position={[0, 0, 0]} castShadow receiveShadow>
            <boxGeometry args={[width - 0.006, carcaseHeight - 0.008, 0.018]} />
            <meshStandardMaterial map={woodMap} color={carcaseColor} roughness={roughness} />
          </mesh>
        )}

        {/* Shaker Recessed Inset (if shaker style) */}
        {doorStyle === 'shaker' && (
          <mesh position={[0, 0, 0.008]}>
            <boxGeometry args={[width - 0.08, carcaseHeight - 0.08, 0.004]} />
            <meshStandardMaterial
              color={carcaseColor}
              roughness={roughness + 0.1}
            />
          </mesh>
        )}

        {/* Fluted Vertical Slats (if fluted style) */}
        {doorStyle === 'fluted' && (
          <group position={[0, 0, 0.01]}>
            {Array.from({ length: Math.floor(width / 0.03) }).map((_, i) => (
              <mesh
                key={i}
                position={[-width / 2 + 0.015 + i * 0.03, 0, 0]}
              >
                <boxGeometry args={[0.016, carcaseHeight - 0.01, 0.006]} />
                <meshStandardMaterial color={carcaseColor} roughness={roughness} />
              </mesh>
            ))}
          </group>
        )}

        {/* Contemporary Metal Bar Pull Handle(s) */}
        {doorStyle !== 'slab' ? (
          // Handle on door
          isDoubleDoor ? (
            <>
              <mesh position={[-0.03, 0.15, 0.016]} castShadow>
                <boxGeometry args={[0.015, 0.12, 0.016]} />
                <meshStandardMaterial color={handleColor} metalness={0.85} roughness={0.25} />
              </mesh>
              <mesh position={[0.03, 0.15, 0.016]} castShadow>
                <boxGeometry args={[0.015, 0.12, 0.016]} />
                <meshStandardMaterial color={handleColor} metalness={0.85} roughness={0.25} />
              </mesh>
            </>
          ) : (
            <mesh position={[width * 0.35, 0.15, 0.016]} castShadow>
              <boxGeometry args={[0.015, 0.12, 0.016]} />
              <meshStandardMaterial color={handleColor} metalness={0.85} roughness={0.25} />
            </mesh>
          )
        ) : (
          // J-Pull / Gola Recessed Finger Channel (Sleek minimalist look)
          <mesh position={[0, carcaseHeight / 2 - 0.015, -0.005]}>
            <boxGeometry args={[width - 0.01, 0.025, 0.015]} />
            <meshStandardMaterial color="#2C2724" roughness={0.7} />
          </mesh>
        )}
      </group>

      {/* ── 20mm Calacatta Gold Engineered Stone Benchtop (Base units) ── */}
      {isBase && (
        <mesh
          position={[0, toeKickHeight + carcaseHeight + benchtopThickness / 2, 0.01]}
          castShadow
          receiveShadow
        >
          {/* Overhangs 20mm past door */}
          <boxGeometry args={[width, benchtopThickness, depth + 0.02]} />
          <meshStandardMaterial
            map={marbleTexture}
            roughness={0.18}
            metalness={0.05}
            color="#FAF8F5"
          />
        </mesh>
      )}

      {/* ── Elegant Architectural Selection Halo (Crisp Outline) ─────── */}
      {isSelected && (
        <group position={[0, posY, 0]}>
          {/* Crisp glowing chamfer wireframe enclosing the cabinet module */}
          <lineSegments>
            <edgesGeometry
              args={[
                new THREE.BoxGeometry(
                  width + 0.012,
                  carcaseHeight + (isBase ? benchtopThickness + 0.01 : 0.01),
                  depth + 0.02
                ),
              ]}
            />
            <lineBasicMaterial color="#B2967D" linewidth={2} />
          </lineSegments>

          {/* Minimalist Floor Footprint Ring */}
          <mesh
            rotation={[-Math.PI / 2, 0, 0]}
            position={[0, -posY + 0.002, 0]}
          >
            <planeGeometry args={[width + 0.04, depth + 0.04]} />
            <meshBasicMaterial
              color="#B2967D"
              transparent
              opacity={0.18}
              side={THREE.DoubleSide}
            />
          </mesh>
        </group>
      )}
    </group>
  );
};

