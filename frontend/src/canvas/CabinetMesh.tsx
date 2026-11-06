import React, { useEffect, useMemo } from 'react';
import { NO_PICTURE } from './picture';
import * as THREE from 'three';
import type { ThreeEvent } from '@react-three/fiber';
import type { CabinetData } from '../layout/model';
import { buildCabinet, disposeCabinet } from './cabinetBuilder';
import type { CabinetFinish, DoorStyle } from './cabinetBuilder';
import { WORKTOP_KINDS, placement } from './placement';

export type { CabinetData } from '../layout/model';
export type { CabinetFinish, DoorStyle } from './cabinetBuilder';

interface CabinetMeshProps {
  cabinet: CabinetData;
  isSelected: boolean;
  finish: CabinetFinish;
  doorStyle: DoorStyle;
  /** Room height in metres (rangehood chimneys run up to it). */
  ceiling: number;
  onSelect: (id: string) => void;
}

export const CabinetMesh: React.FC<CabinetMeshProps> = ({
  cabinet,
  isSelected,
  finish,
  doorStyle,
  ceiling,
  onSelect,
}) => {
  const { kind, width, height, depth, isWallMounted, mount, hood } = cabinet;
  const object = useMemo(
    () => buildCabinet({ kind, w: width, h: height, d: depth, isWall: isWallMounted, mount, hood }, finish, doorStyle, ceiling),
    [kind, width, height, depth, isWallMounted, mount, hood, finish, doorStyle, ceiling],
  );
  useEffect(() => () => disposeCabinet(object), [object]);

  // Outline around the cabinet and its worktop when selected.
  const outline = useMemo(() => {
    if (!isSelected) return null;
    const top = WORKTOP_KINDS.has(kind) && !isWallMounted ? 0.04 : 0;
    const box = new THREE.BoxGeometry(width + 0.014, height + top + 0.012, depth + 0.03);
    const edges = new THREE.EdgesGeometry(box);
    box.dispose();
    return { edges, y: top / 2 };
  }, [isSelected, kind, isWallMounted, width, height, depth]);
  useEffect(() => () => outline?.edges.dispose(), [outline]);

  const { position, rotationY } = placement(cabinet);

  return (
    <group
      position={position}
      rotation={[0, rotationY, 0]}
      onClick={(e: ThreeEvent<MouseEvent>) => {
        e.stopPropagation();
        onSelect(cabinet.id);
      }}
    >
      <primitive object={object} />
      {outline && (
        <lineSegments geometry={outline.edges} position={[0, outline.y, 0.01]} userData={NO_PICTURE}>
          <lineBasicMaterial color="#A25F41" />
        </lineSegments>
      )}
    </group>
  );
};
