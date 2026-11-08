"""Synthetic wall photos with known answers, for testing the camera route.

Renders a room seen through a pinhole camera: the front wall (the one to
measure) with a window and a door, the side walls, ceiling and floor around
it. Each photo comes with its ground truth: where the wall's and openings'
corners are in the photo, in pixels, and their true sizes in mm. The lens
goes into the JPEG's EXIF data the way a phone writes it, so the app can read
it.

    python tool/wall_benchmark/make_synthetic.py OUT_DIR

Writes OUT_DIR/<name>.jpg and OUT_DIR/<name>.json for each view.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

W, H = 4000.0, 2700.0  # the front wall, mm
ROOM_DEPTH = 5000.0
PHOTO = (1920, 1080)
FOCAL_35MM = 26  # a typical phone main camera

# Openings on the front wall: x from the left, y down from the ceiling, mm.
WINDOW = {"type": "window", "left": 1500.0, "from_floor": 1000.0, "width": 1200.0, "height": 1000.0}
DOOR = {"type": "door", "left": 3000.0, "from_floor": 0.0, "width": 800.0, "height": 2100.0}

# Each keeps the camera inside the room and all four wall corners in frame,
# as the camera screen asks.
VIEWS = {
    "head-on": {"yaw": 0.0, "pitch": 3.0, "distance": 3600.0},
    "from-left-25": {"yaw": 25.0, "pitch": 6.0, "distance": 4500.0},
    "from-right-20-high": {"yaw": -20.0, "pitch": 12.0, "distance": 4500.0},
}


def focal_px() -> float:
    diag = math.hypot(*PHOTO)
    return FOCAL_35MM * diag / 43.2666


class Camera:
    def __init__(self, yaw: float, pitch: float, distance: float):
        y, p = math.radians(yaw), math.radians(pitch)
        ry = [[math.cos(y), 0, -math.sin(y)], [0, 1, 0], [math.sin(y), 0, math.cos(y)]]
        rx = [[1, 0, 0], [0, math.cos(p), math.sin(p)], [0, -math.sin(p), math.cos(p)]]
        self.r = [[sum(rx[i][k] * ry[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
        centre = (W / 2, H / 2, 0.0)
        self.c = [centre[i] - distance * self.r[2][i] for i in range(3)]
        self.f = focal_px()

    def to_cam(self, p):
        d = [p[i] - self.c[i] for i in range(3)]
        return [sum(self.r[i][k] * d[k] for k in range(3)) for i in range(3)]

    def project_cam(self, q):
        return (self.f * q[0] / q[2] + PHOTO[0] / 2, self.f * q[1] / q[2] + PHOTO[1] / 2)

    def project(self, p):
        return self.project_cam(self.to_cam(p))

    def polygon(self, points):
        """Projects a 3D polygon, clipped in front of the camera."""
        near = 50.0
        cam = [self.to_cam(p) for p in points]
        out = []
        for i, a in enumerate(cam):
            b = cam[(i + 1) % len(cam)]
            if a[2] >= near:
                out.append(a)
            if (a[2] >= near) != (b[2] >= near):
                t = (near - a[2]) / (b[2] - a[2])
                out.append([a[k] + t * (b[k] - a[k]) for k in range(3)])
        return [self.project_cam(q) for q in out]


def opening_corners(o):
    top = H - o["from_floor"] - o["height"]
    x0, x1 = o["left"], o["left"] + o["width"]
    return [(x0, top, 0.0), (x1, top, 0.0), (x1, top + o["height"], 0.0), (x0, top + o["height"], 0.0)]


def render(name: str, view: dict, out: Path) -> None:
    cam = Camera(**view)
    img = Image.new("RGB", PHOTO, (40, 40, 40))
    d = ImageDraw.Draw(img)
    z = -ROOM_DEPTH
    surfaces = [
        ((236, 233, 228), [(0, 0, z), (W, 0, z), (W, 0, 0), (0, 0, 0)]),  # ceiling
        ((150, 120, 92), [(0, H, z), (W, H, z), (W, H, 0), (0, H, 0)]),  # floor
        ((205, 200, 192), [(0, 0, z), (0, 0, 0), (0, H, 0), (0, H, z)]),  # left wall
        ((214, 209, 201), [(W, 0, 0), (W, 0, z), (W, H, z), (W, H, 0)]),  # right wall
        ((226, 221, 212), [(0, 0, 0), (W, 0, 0), (W, H, 0), (0, H, 0)]),  # front wall
    ]
    for colour, poly in surfaces:
        pts = cam.polygon(poly)
        if len(pts) >= 3:
            d.polygon(pts, fill=colour)
    # Skirting along the front wall, and the window and door.
    d.polygon(cam.polygon([(0, H - 100, 0), (W, H - 100, 0), (W, H, 0), (0, H, 0)]), fill=(245, 243, 238))
    d.polygon(cam.polygon(opening_corners(WINDOW)), fill=(170, 200, 225), outline=(90, 90, 90))
    mid = WINDOW["left"] + WINDOW["width"] / 2
    top = H - WINDOW["from_floor"] - WINDOW["height"]
    d.line([cam.project((mid, top, 0)), cam.project((mid, top + WINDOW["height"], 0))], fill=(90, 90, 90), width=3)
    d.polygon(cam.polygon(opening_corners(DOOR)), fill=(120, 86, 60), outline=(70, 50, 35))
    # A little blur, as a real photo has.
    img = img.filter(ImageFilter.GaussianBlur(0.8))

    exif = Image.Exif()
    exif[0x010F] = "Synthetic"  # Make
    exif.get_ifd(0x8769)[0xA405] = FOCAL_35MM  # FocalLengthIn35mmFilm
    jpg = out / f"{name}.jpg"
    img.save(jpg, quality=92, exif=exif.tobytes())

    truth = {
        "photo_px": list(PHOTO),
        "focal_35mm": FOCAL_35MM,
        "focal_px": round(cam.f, 1),
        "view": view,
        "wall_mm": [W, H],
        "wall_corners_px": [list(map(lambda v: round(v, 1), cam.project(p)))
                            for p in [(0, 0, 0), (W, 0, 0), (W, H, 0), (0, H, 0)]],
        "openings": [
            {**o, "corners_px": [list(map(lambda v: round(v, 1), cam.project(p))) for p in opening_corners(o)]}
            for o in (WINDOW, DOOR)
        ],
    }
    (out / f"{name}.json").write_text(json.dumps(truth, indent=2))
    print(name, truth["wall_corners_px"])


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "synthetic")
    out.mkdir(parents=True, exist_ok=True)
    for name, view in VIEWS.items():
        render(name, view, out)
