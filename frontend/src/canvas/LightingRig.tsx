import React, { useEffect } from 'react';
import * as THREE from 'three';
import { useThree } from '@react-three/fiber';
import { ContactShadows } from '@react-three/drei';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';

/** Soft studio reflections (generated, nothing downloaded), as in the sales
 *  app: without them steel, glass and stone render flat and dark. */
const StudioEnvironment: React.FC<{ intensity: number }> = ({ intensity }) => {
  const { gl, scene } = useThree();
  useEffect(() => {
    const pmrem = new THREE.PMREMGenerator(gl);
    const room = new RoomEnvironment();
    const env = pmrem.fromScene(room, 0.04).texture;
    // three.js scene settings are set by assignment; this is the intended API.
    // oxlint-disable-next-line react/immutability
    scene.environment = env;
    room.dispose();
    pmrem.dispose();
    return () => {
      scene.environment = null;
      env.dispose();
    };
  }, [gl, scene]);
  useEffect(() => {
    // oxlint-disable-next-line react/immutability
    scene.environmentIntensity = intensity;
  }, [scene, intensity]);
  return null;
};

interface LightingRigProps {
  mood: 'day' | 'evening';
}

export const LightingRig: React.FC<LightingRigProps> = ({ mood }) => {
  const isDay = mood === 'day';

  return (
    <>
      <StudioEnvironment intensity={isDay ? 0.55 : 0.3} />

      {/* ── Soft Ambient Fill ────────────────────────────────────────── */}
      <ambientLight
        color={isDay ? '#FBF9F7' : '#D4C4B2'}
        intensity={isDay ? 0.45 : 0.25}
      />

      {/* ── Sky/Ground Hemisphere Bounce ─────────────────────────────── */}
      <hemisphereLight
        args={[
          isDay ? '#ECF8F8' : '#6A5F58',
          isDay ? '#E7D8C9' : '#1E1A17',
          isDay ? 0.6 : 0.4,
        ]}
      />

      {/* ── Primary Directional Light (Window Sunlight / Spot) ──────── */}
      <directionalLight
        position={isDay ? [3.8, 5.2, 3.5] : [2.5, 4.5, 2.5]}
        intensity={isDay ? 1.6 : 1.1}
        color={isDay ? '#FFF7F0' : '#FFD9B3'}
        castShadow
        shadow-mapSize-width={2048}
        shadow-mapSize-height={2048}
        shadow-camera-near={0.5}
        shadow-camera-far={25}
        shadow-camera-left={-5}
        shadow-camera-right={5}
        shadow-camera-top={5}
        shadow-camera-bottom={-5}
        shadow-bias={-0.00015}
        shadow-radius={4}
      />

      {/* ── Soft Warm Interior Spotlight ─────────────────────────────── */}
      <spotLight
        position={[1.5, 3.8, 1.8]}
        target-position={[1.5, 0.8, 0.3]}
        angle={Math.PI / 4}
        penumbra={0.8}
        intensity={isDay ? 0.8 : 2.2}
        color={isDay ? '#FFF0E0' : '#FFA85C'}
        castShadow={false}
      />

      {/* ── Contact Shadows for Grounding Furniture onto Floor ──────── */}
      <ContactShadows
        position={[1.8, 0.002, 1.2]}
        opacity={isDay ? 0.6 : 0.75}
        scale={12}
        blur={2.0}
        far={2.0}
        color="#2C2724"
      />
    </>
  );
};
