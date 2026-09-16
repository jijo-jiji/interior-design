import * as THREE from 'three';

// ─── Procedural Canvas PBR Texture Generators ───────────────────────────────

/**
 * Generates continuous wide-plank oak flooring texture.
 * Planks run horizontally with micro-bevel seams, subtle wood grain, and warm earthy tones.
 */
export function createPlankOakTexture(): { map: THREE.CanvasTexture; bumpMap: THREE.CanvasTexture } {
  const canvas = document.createElement('canvas');
  canvas.width = 1024;
  canvas.height = 1024;
  const ctx = canvas.getContext('2d')!;

  // Base warm natural oak background
  ctx.fillStyle = '#C8B39B';
  ctx.fillRect(0, 0, 1024, 1024);

  const numPlanks = 6;
  const plankHeight = 1024 / numPlanks;

  for (let p = 0; p < numPlanks; p++) {
    const y = p * plankHeight;
    // Slight tone variation per plank
    const toneVariation = (Math.sin(p * 2.3) * 8);
    const r = Math.min(255, Math.max(0, 204 + toneVariation));
    const g = Math.min(255, Math.max(0, 182 + toneVariation));
    const b = Math.min(255, Math.max(0, 158 + toneVariation));

    ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
    ctx.fillRect(0, y, 1024, plankHeight);

    // Wood grain lines
    ctx.save();
    ctx.strokeStyle = `rgba(160, 135, 110, 0.15)`;
    ctx.lineWidth = 1.5;
    for (let i = 0; i < 40; i++) {
      const lineY = y + (i / 40) * plankHeight + (Math.sin(i * 0.8) * 4);
      ctx.beginPath();
      ctx.moveTo(0, lineY);
      ctx.bezierCurveTo(300, lineY + (Math.sin(i * 1.5) * 6), 700, lineY - (Math.cos(i * 1.2) * 5), 1024, lineY);
      ctx.stroke();
    }
    ctx.restore();

    // Dark micro-bevel seam between planks
    ctx.fillStyle = 'rgba(44, 39, 36, 0.35)';
    ctx.fillRect(0, y, 1024, 2);
    // Subtle highlight edge on top of plank
    ctx.fillStyle = 'rgba(255, 255, 255, 0.25)';
    ctx.fillRect(0, y + 2, 1024, 1);
  }

  const map = new THREE.CanvasTexture(canvas);
  map.wrapS = THREE.RepeatWrapping;
  map.wrapT = THREE.RepeatWrapping;
  map.repeat.set(2, 2);

  // Bump map for realistic plank bevels
  const bumpCanvas = document.createElement('canvas');
  bumpCanvas.width = 1024;
  bumpCanvas.height = 1024;
  const bCtx = bumpCanvas.getContext('2d')!;
  bCtx.fillStyle = '#808080';
  bCtx.fillRect(0, 0, 1024, 1024);

  for (let p = 0; p < numPlanks; p++) {
    const y = p * plankHeight;
    bCtx.fillStyle = '#000000';
    bCtx.fillRect(0, y, 1024, 3);
    bCtx.fillStyle = '#c0c0c0';
    bCtx.fillRect(0, y + 3, 1024, 2);
  }
  const bumpMap = new THREE.CanvasTexture(bumpCanvas);
  bumpMap.wrapS = THREE.RepeatWrapping;
  bumpMap.wrapT = THREE.RepeatWrapping;
  bumpMap.repeat.set(2, 2);

  return { map, bumpMap };
}

/**
 * Generates Calacatta Gold / Engineered Quartz marble texture.
 */
export function createCalacattaMarbleTexture(): THREE.CanvasTexture {
  const canvas = document.createElement('canvas');
  canvas.width = 1024;
  canvas.height = 1024;
  const ctx = canvas.getContext('2d')!;

  // Soft warm alabaster base
  ctx.fillStyle = '#F8F6F2';
  ctx.fillRect(0, 0, 1024, 1024);

  // Subtle cloudiness
  for (let i = 0; i < 60; i++) {
    const x = Math.random() * 1024;
    const y = Math.random() * 1024;
    const rad = 80 + Math.random() * 140;
    const grad = ctx.createRadialGradient(x, y, 0, x, y, rad);
    grad.addColorStop(0, 'rgba(238, 228, 225, 0.3)');
    grad.addColorStop(1, 'rgba(238, 228, 225, 0)');
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(x, y, rad, 0, Math.PI * 2);
    ctx.fill();
  }

  // Organic golden and taupe veins
  const veinColors = [
    'rgba(212, 185, 142, 0.45)', // Champagne gold
    'rgba(178, 150, 125, 0.35)', // Earthy taupe
    'rgba(140, 134, 127, 0.25)', // Muted slate-warm grey
  ];

  for (let v = 0; v < 7; v++) {
    ctx.save();
    ctx.strokeStyle = veinColors[v % veinColors.length];
    ctx.lineWidth = 2 + (v % 3);
    ctx.beginPath();
    let cx = Math.random() * 200;
    let cy = (v * 160) + Math.random() * 80;
    ctx.moveTo(cx, cy);

    while (cx < 1024) {
      cx += 120 + Math.random() * 100;
      cy += (Math.random() - 0.45) * 120;
      ctx.lineTo(cx, cy);
    }
    ctx.stroke();

    // Soft feathered secondary branch
    ctx.lineWidth = 0.8;
    ctx.stroke();
    ctx.restore();
  }

  const map = new THREE.CanvasTexture(canvas);
  map.wrapS = THREE.RepeatWrapping;
  map.wrapT = THREE.RepeatWrapping;
  return map;
}

/**
 * Vertical Wood Grain for cabinet facades (Oak, Smoked Walnut, Nordic).
 */
export function createCabinetWoodTexture(baseHex: string, grainHex: string): THREE.CanvasTexture {
  const canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = 512;
  const ctx = canvas.getContext('2d')!;

  ctx.fillStyle = baseHex;
  ctx.fillRect(0, 0, 512, 512);

  ctx.strokeStyle = grainHex;
  ctx.lineWidth = 1;
  for (let i = 0; i < 180; i++) {
    const x = Math.random() * 512;
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.bezierCurveTo(x + (Math.sin(i) * 5), 180, x - (Math.cos(i) * 6), 340, x, 512);
    ctx.stroke();
  }

  const map = new THREE.CanvasTexture(canvas);
  map.wrapS = THREE.RepeatWrapping;
  map.wrapT = THREE.RepeatWrapping;
  return map;
}

/**
 * Earthy lime-wash plaster wall texture with subtle micro-grain and no circular artifacts.
 */
export function createPlasterWallTexture(): THREE.CanvasTexture {
  const canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = 512;
  const ctx = canvas.getContext('2d')!;

  // Soft earthy linen/bone base
  ctx.fillStyle = '#EEE5E0';
  ctx.fillRect(0, 0, 512, 512);

  // Organic micro-textured wash using soft horizontal sweeps
  const imgData = ctx.getImageData(0, 0, 512, 512);
  const data = imgData.data;

  for (let y = 0; y < 512; y++) {
    for (let x = 0; x < 512; x++) {
      const idx = (y * 512 + x) * 4;
      // Fine organic grain variation
      const noise = (Math.random() - 0.5) * 12;
      const subtleWash = Math.sin(x * 0.02) * Math.cos(y * 0.03) * 6;
      const val = noise + subtleWash;

      data[idx] = Math.min(255, Math.max(0, data[idx] + val));
      data[idx + 1] = Math.min(255, Math.max(0, data[idx + 1] + val * 0.95));
      data[idx + 2] = Math.min(255, Math.max(0, data[idx + 2] + val * 0.9));
    }
  }
  ctx.putImageData(imgData, 0, 0);

  const map = new THREE.CanvasTexture(canvas);
  map.wrapS = THREE.RepeatWrapping;
  map.wrapT = THREE.RepeatWrapping;
  map.repeat.set(4, 2);
  return map;
}
