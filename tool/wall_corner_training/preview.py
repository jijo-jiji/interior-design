"""A sheet of synthetic samples, to check the generator by eye.

    python tool/wall_corner_training/preview.py OUT.png [SEED]

Each sample: labels (left) and depth (right) as the corner model sees them,
with the true front-wall corners drawn in red.
"""
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
import synth  # noqa: E402

COLOURS = np.array([(230, 210, 120), (90, 170, 90), (120, 160, 230), (60, 220, 230),
                    (200, 110, 60), (200, 60, 160), (110, 110, 110)], np.uint8)


def tile(x: np.ndarray, corners: np.ndarray, size: int = 256) -> Image.Image:
    """One sample as labels | depth, with the corners as marked (red) and,
    if given, the true bottom corners hidden behind cabinets (yellow)."""
    label = x[1:1 + synth.NUM_CLASSES].argmax(0)
    lab = Image.fromarray(COLOURS[label]).resize((size, size), Image.NEAREST)
    dep = Image.fromarray((x[0] * 255).astype(np.uint8)).resize((size, size), Image.BILINEAR).convert("RGB")
    out = Image.new("RGB", (size * 2, size))
    out.paste(lab, (0, 0))
    out.paste(dep, (size, 0))
    d = ImageDraw.Draw(out)
    points = corners.reshape(-1, 2) * size
    for ox in (0, size):
        pts = [(ox + px, py) for px, py in points[:4]]
        d.line(pts + [pts[0]], fill=(255, 30, 30), width=2)
        for px, py in points[4:]:
            d.ellipse((ox + px - 3, py - 3, ox + px + 3, py + 3), outline=(255, 220, 0), width=2)
    return out


if __name__ == "__main__":
    out = sys.argv[1]
    rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 0)
    t = time.time()
    samples = [synth.sample(rng) for _ in range(24)]
    print(f"{(time.time() - t) / 24 * 1000:.0f} ms per sample; kitchens: {sum(s[2] for s in samples)}/24")
    sheet = Image.new("RGB", (4 * 516, 6 * 260), "white")
    for i, (x, y, _) in enumerate(samples):
        sheet.paste(tile(x, y), ((i % 4) * 516, (i // 4) * 260))
    sheet.save(out)
