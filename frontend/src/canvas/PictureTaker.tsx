import { useEffect } from 'react';
import type { MutableRefObject } from 'react';
import * as THREE from 'three';
import { useThree } from '@react-three/fiber';
import { pictureSize } from './picture.ts';
import type { PictureFn } from './picture.ts';

/** Lives inside the canvas and fills [takeRef] with a function that renders
 *  the current view once, larger than it is on screen, and returns it as a
 *  PNG data URL. The on-screen canvas is put back as it was. */
export const PictureTaker = ({ takeRef }: { takeRef: MutableRefObject<PictureFn | null> }) => {
  const { gl, scene, camera, size, invalidate } = useThree();

  useEffect(() => {
    takeRef.current = () => {
      const { width, height } = pictureSize(size.width, size.height);
      const previousRatio = gl.getPixelRatio();
      const perspective = camera instanceof THREE.PerspectiveCamera ? camera : null;
      const previousAspect = perspective?.aspect;
      const hidden: THREE.Object3D[] = [];
      scene.traverse((o) => {
        if (o.userData.noPicture && o.visible) hidden.push(o);
      });
      try {
        hidden.forEach((o) => (o.visible = false));
        gl.setPixelRatio(1);
        gl.setSize(width, height, false);
        if (perspective) {
          perspective.aspect = width / height;
          perspective.updateProjectionMatrix();
        }
        gl.render(scene, camera);
        return gl.domElement.toDataURL('image/png');
      } catch (err) {
        console.error('Taking the picture failed:', err);
        return null;
      } finally {
        hidden.forEach((o) => (o.visible = true));
        gl.setPixelRatio(previousRatio);
        gl.setSize(size.width, size.height, false);
        if (perspective && previousAspect !== undefined) {
          perspective.aspect = previousAspect;
          perspective.updateProjectionMatrix();
        }
        invalidate();
      }
    };
    return () => {
      takeRef.current = null;
    };
  }, [gl, scene, camera, size, invalidate, takeRef]);

  return null;
};
