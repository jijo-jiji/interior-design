import React, { useMemo } from 'react';
import * as THREE from 'three';
import { createCabinetWoodTexture, createCalacattaMarbleTexture } from './materials';

export type DoorStyle = 'slab' | 'shaker' | 'fluted';
export type CabinetFinish = 'japandi' | 'nordic' | 'minimalist' | 'industrial';

export interface CabinetData {
  id: string;
  type: 'base_800' | 'base_600' | 'wall_600' | 'tall_600';
  x: number; // in meters along wall
  width: number;
  height: number;
  depth: number;
  isWallMounted?: boolean;
}

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
  const isWall = type === 'wall_600';
  const isTall = type === 'tall_600';
  const isBase = !isWall && !isTall;

  // Elevation placement
  const elevation = isWall ? 1.48 : 0;
  const toeKickHeight = isWall ? 0 : 0.15;
  const carcaseHeight = isWall ? height : (isTall ? height - toeKickHeight : 0.72);
  const benchtopThickness = isWall || isTall ? 0 : 0.02;

  // Materials based on finish
  const { woodMap, carcaseColor, handleColor, roughness } = useMemo(() => {
    switch (finish) {
      case 'japandi':
        return {
          woodMap: createCabinetWoodTexture('#D4C0A8', 'rgba(160, 135, 110, 0.25)'),
          carcaseColor: '#C8B39B',
          handleColor: '#D4B982', // Champagne gold
          roughness: 0.35,
        };
      case 'nordic':
        return {
          woodMap: createCabinetWoodTexture('#EAE1D5', 'rgba(180, 160, 140, 0.2)'),
          carcaseColor: '#EEE4E1',
          handleColor: '#C8A97E', // Soft brass
          roughness: 0.4,
        };
      case 'minimalist':
        return {
          woodMap: createCabinetWoodTexture('#F0EAE1', 'rgba(215, 205, 195, 0.15)'),
          carcaseColor: '#EEE4E1',
          handleColor: '#2C2724', // Matte graphite
          roughness: 0.55,
        };
      case 'industrial':
        return {
          woodMap: createCabinetWoodTexture('#4A4038', 'rgba(30, 25, 20, 0.35)'),
          carcaseColor: '#3C342E',
          handleColor: '#1A1816', // Dark steel
          roughness: 0.45,
        };
      default:
        return {
          woodMap: createCabinetWoodTexture('#D4C0A8', 'rgba(160, 135, 110, 0.25)'),
          carcaseColor: '#C8B39B',
          handleColor: '#D4B982',
          roughness: 0.35,
        };
    }
  }, [finish]);

  // Calacatta Marble Benchtop Texture
  const marbleTexture = useMemo(() => createCalacattaMarbleTexture(), []);

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
