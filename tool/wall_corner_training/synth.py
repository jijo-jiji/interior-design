"""Synthetic rooms and kitchens for training the wall-corner model.

Each sample is what the app's two models would say about a photo of a room
(a depth map and a label map), rendered exactly from a random 3D room, plus
the answer: where the front wall's four corners are in the photo, even when
cabinets hide them. There are no textures or lighting: the corner model never
sees the photo itself, only depth and labels, so there is nothing
photographic to fake. What does need faking is the two models' mistakes, and
`degrade` does that.

World: x across the front wall (0..W), y down (0 = ceiling, H = floor), z
towards the front wall, which is the plane z = 0; the camera stands at z < 0.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

WALL, FLOOR, CEILING, WINDOW, CABINET, DOOR, OTHER = range(7)
NUM_CLASSES = 7
CHANNELS = 1 + NUM_CLASSES + 3  # depth, one-hot labels, u, v, log(aspect)
# The answer: 4 corners as marked (bottom ones on the visible floor line),
# then the true bottom-right and bottom-left corners (see `sample`).
POINTS = 6

# ADE20K ids (the segmentation model's 32 classes) to the classes above.
ADE_TO_CLASS = {1: WALL, 4: FLOOR, 6: CEILING, 9: WINDOW, 19: WINDOW, 11: CABINET, 15: DOOR}


@dataclass
class Scene:
    W: float
    H: float
    D: float
    room_lo: np.ndarray
    room_hi: np.ndarray
    lo: np.ndarray  # (K, 3) boxes
    hi: np.ndarray
    label: np.ndarray  # (K,)
    offset: np.ndarray  # (K,) extra depth behind the surface (see-through glass)
    kitchen: bool
    # Where the floor visibly meets the cabinets at each end of the front
    # wall, bottom-right then bottom-left (the true corners where nothing
    # stands there): what a salesperson marks as the wall's bottom corners.
    floor_bottom: np.ndarray  # (2, 3)


@dataclass
class Camera:
    pos: np.ndarray
    R: np.ndarray  # world -> camera
    f: float  # pixels
    w: float
    h: float


def _rotation(yaw: float, pitch: float, roll: float) -> np.ndarray:
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    cr, sr = math.cos(roll), math.sin(roll)
    ry = np.array([[cy, 0, -sy], [0, 1, 0], [sy, 0, cy]])
    rx = np.array([[1, 0, 0], [0, cp, sp], [0, -sp, cp]])
    rz = np.array([[cr, sr, 0], [-sr, cr, 0], [0, 0, 1]])
    return rz @ rx @ ry


def _wallbox(side: str, W: float, a0, a1, y0, y1, d0, d1):
    """A box against a wall: a along the wall, y down, d out from the wall."""
    if side == "front":
        return (a0, y0, -d1), (a1, y1, -d0)
    if side == "left":
        return (d0, y0, -a1), (d1, y1, -a0)
    return (W - d1, y0, -a1), (W - d0, y1, -a0)


def _kitchen_run(rng, add, side, W, H, a0, a1, st):
    """Cabinets along one wall from a0 to a1. Returns how far the cabinets
    stand out from the wall at floor level at each end (0 for a gap): where
    the floor visibly meets them."""
    bh, bd, wb, wh, wd = st["base_h"], st["base_d"], st["wall_bottom"], st["wall_h"], st["wall_d"]
    x = a0
    first = True
    depths = []
    while x < a1 - 0.25:
        w = min(rng.uniform(0.4, 1.1), a1 - x)
        last = x + w >= a1 - 0.25
        if last:
            w = a1 - x
        r = rng.random()
        if (first or last) and r < 0.30:
            kind = "tall"
        elif r < 0.62:
            kind = "both"
        elif r < 0.80:
            kind = "base"
        elif r < 0.90:
            kind = "hood"
        elif r < 0.95:
            kind = "tall"
        else:
            kind = "gap"
        depths.append(0.0)
        if kind == "tall":
            th = H if rng.random() < 0.3 else min(H, rng.choice([wb + wh, rng.uniform(1.7, 2.3)]))
            depths[-1] = rng.uniform(0.55, 0.78)
            add(*_wallbox(side, W, x, x + w, H - th, H, 0, depths[-1]), st["tall_label"]())
        if kind in ("both", "base", "hood"):
            depths[-1] = bd
            add(*_wallbox(side, W, x, x + w, H - bh, H, 0, bd), CABINET if rng.random() < 0.85 else OTHER)
            add(*_wallbox(side, W, x, x + w, H - bh - 0.04, H - bh, 0, bd + 0.02), st["counter_label"])
        if kind == "both":
            add(*_wallbox(side, W, x, x + w, H - wb - wh, H - wb, 0, wd), CABINET)
        if kind == "base" and rng.random() < 0.5:
            sill = bh + rng.uniform(0.08, 0.3)
            top = min(H - 0.15, rng.uniform(1.9, 2.3))
            m = rng.uniform(0.02, 0.15) * w
            _window(rng, add, side, W, H, x + m, x + w - m, sill, top)
        if kind == "hood":
            canopy = rng.uniform(1.55, 1.8)
            add(*_wallbox(side, W, x + 0.03, x + w - 0.03, H - canopy - rng.uniform(0.08, 0.5), H - canopy,
                          0, rng.uniform(0.35, 0.5)), OTHER if rng.random() < 0.6 else CABINET)
            if rng.random() < 0.6:  # the chimney up to the ceiling
                c = x + w / 2
                add(*_wallbox(side, W, c - 0.15, c + 0.15, 0, H - canopy, 0, 0.3), OTHER if rng.random() < 0.6 else WALL)
        if kind == "gap" and side == "front" and rng.random() < 0.3 and w > 0.7:
            _door(rng, add, side, W, H, x + 0.02, x + min(w, 0.95))
        x += w
        first = False
    if st["soffit"] and wb + wh < H - 0.05:
        add(*_wallbox(side, W, a0, a1, 0, H - wb - wh, 0, rng.uniform(wd, 0.62)), WALL if rng.random() < 0.85 else CEILING)
    for _ in range(rng.integers(0, 5)):  # things on the worktop
        cw, ch, cd = rng.uniform(0.1, 0.4), rng.uniform(0.1, 0.45), rng.uniform(0.1, 0.3)
        cx = rng.uniform(a0, max(a0 + 0.01, a1 - cw))
        dd = rng.uniform(0.02, max(0.03, bd - cd))
        add(*_wallbox(side, W, cx, cx + cw, H - bh - 0.04 - ch, H - bh - 0.04, dd, dd + cd), OTHER)
    return (depths[0], depths[-1]) if depths else (0.0, 0.0)


def _window(rng, add, side, W, H, a0, a1, sill, top):
    """A window on a wall, from sill to top above the floor."""
    r = rng.random()
    offset = 0.0 if r < 0.5 else (rng.uniform(0.05, 0.2) if r < 0.85 else rng.uniform(1.0, 5.0))
    lo, hi = _wallbox(side, W, a0, a1, H - top, H - sill, 0, 0.02)
    add(lo, hi, WINDOW, offset)
    if rng.random() < 0.3:  # curtains or blinds, a little proud of the wall
        e = rng.uniform(0.0, 0.2)
        add(*_wallbox(side, W, a0 - e, a1 + e, H - top - rng.uniform(0, 0.15), H - sill + rng.uniform(0, 0.3),
                      0.03, rng.uniform(0.06, 0.12)), WINDOW)


def _door(rng, add, side, W, H, a0, a1):
    r = rng.random()
    if r < 0.7:  # a closed door
        add(*_wallbox(side, W, a0, a1, H - rng.uniform(1.98, 2.12), H, 0, 0.03), DOOR)
    else:  # an open doorway into the next room
        add(*_wallbox(side, W, a0, a1, H - rng.uniform(1.98, 2.12), H, 0, 0.02),
            rng.choice([DOOR, OTHER, WALL]), rng.uniform(1.0, 4.0))


def random_scene(rng: np.random.Generator) -> Scene:
    kitchen = rng.random() < 0.75
    W = rng.uniform(2.2, 5.5) if kitchen else rng.uniform(2.5, 6.5)
    H = rng.uniform(2.35, 3.1)
    D = rng.uniform(2.8, 7.0)
    boxes: list[tuple] = []

    def add(lo, hi, label, offset=0.0):
        lo, hi = np.minimum(lo, hi), np.maximum(lo, hi)
        if np.all(hi - lo > 1e-4):
            boxes.append((lo, hi, int(label), float(offset)))

    # How far the kitchen's cabinets stand out at floor level: from the
    # front wall at its left and right ends, and from each side wall where
    # it meets the front wall.
    front_left = front_right = side_left = side_right = 0.0

    # A side where the wall ends at an outside corner instead of meeting a
    # side wall: the room carries on behind and beside it.
    e_left = e_right = gap = 0.0
    open_left, open_right = rng.random() < 0.12, rng.random() < 0.12
    if open_left or open_right:
        gap = rng.uniform(0.6, 3.5)
        e_left = rng.uniform(0.9, 3.0) if open_left else 0.0
        e_right = rng.uniform(0.9, 3.0) if open_right else 0.0
        add((0, 0, 0), (W, H, gap), WALL)  # the wall's mass; its front face is the front wall

    if kitchen:
        to_ceiling = rng.random() < 0.3
        wall_bottom = rng.uniform(1.35, 1.55)
        st = {
            "base_h": rng.uniform(0.85, 0.95),
            "base_d": rng.uniform(0.55, 0.65),
            "wall_bottom": wall_bottom,
            "wall_h": (H - wall_bottom) if to_ceiling else min(H - wall_bottom, rng.uniform(0.6, 0.95)),
            "wall_d": rng.uniform(0.30, 0.38),
            "counter_label": int(rng.choice([CABINET, OTHER, WALL], p=[0.5, 0.4, 0.1])),
            "soffit": rng.random() < 0.3,
        }
        tall_choice = rng.random()
        st["tall_label"] = lambda: (CABINET if tall_choice < 0.5 else int(rng.choice([CABINET, OTHER, WALL], p=[0.3, 0.55, 0.15])))
        a0 = 0.0 if rng.random() < 0.7 else rng.uniform(0, 0.3 * W)
        a1 = W if rng.random() < 0.7 else rng.uniform(0.7 * W, W)
        start, end = _kitchen_run(rng, add, "front", W, H, a0, a1, st)
        front_left = start if a0 == 0.0 else 0.0
        front_right = end if a1 == W else 0.0
        for side, is_open in (("left", open_left), ("right", open_right)):
            if not is_open and rng.random() < 0.45:
                depth, _ = _kitchen_run(rng, add, side, W, H, 0.0, rng.uniform(1.0, min(D - 1.0, 3.5)), st)
                if side == "left":
                    side_left = depth
                else:
                    side_right = depth
        if rng.random() < 0.2:  # an island or a table in the middle
            iw, idp = rng.uniform(0.9, 2.2), rng.uniform(0.6, 1.1)
            ix, iz = rng.uniform(0.2, 0.8) * W, -rng.uniform(1.3, max(1.4, D - 1.0))
            add((ix - iw / 2, H - rng.uniform(0.75, 0.95), iz - idp / 2), (ix + iw / 2, H, iz + idp / 2),
                rng.choice([CABINET, OTHER]))
    else:
        for _ in range(rng.integers(0, 4)):
            ww = rng.uniform(0.6, 2.0)
            x0 = rng.uniform(0.05, max(0.06, W - ww - 0.05))
            floor_length = rng.random() < 0.2
            _window(rng, add, "front", W, H, x0, x0 + ww, 0.05 if floor_length else rng.uniform(0.6, 1.1),
                    min(H - 0.1, rng.uniform(1.9, 2.4)))
        if rng.random() < 0.35:
            dw = rng.uniform(0.75, 0.95)
            x0 = rng.uniform(0.05, max(0.06, W - dw - 0.05))
            _door(rng, add, "front", W, H, x0, x0 + dw)
        for _ in range(rng.integers(0, 4)):  # cupboards and sofas against the front wall
            fw = rng.uniform(0.6, 2.2)
            x0 = rng.uniform(0, max(0.01, W - fw))
            tall = rng.random() < 0.4
            add(*_wallbox("front", W, x0, x0 + fw, H - (rng.uniform(1.6, 2.3) if tall else rng.uniform(0.4, 0.95)), H,
                          rng.uniform(0, 0.1), rng.uniform(0.4, 1.0)), CABINET if (tall and rng.random() < 0.5) else OTHER)

    for side, is_open in (("left", open_left), ("right", open_right)):
        if is_open:
            continue
        if rng.random() < 0.25:
            a = rng.uniform(0.8, max(0.9, D - 1.2))
            _window(rng, add, side, W, H, a, a + rng.uniform(0.6, 1.6), rng.uniform(0.6, 1.1), min(H - 0.1, rng.uniform(1.9, 2.4)))
        if rng.random() < 0.25:
            a = rng.uniform(0.3, max(0.4, D - 1.2))
            _door(rng, add, side, W, H, a, a + rng.uniform(0.75, 0.95))
    for _ in range(rng.integers(0, 3) if rng.random() < 0.4 else 0):  # furniture out in the room
        fw, fd, fh = rng.uniform(0.4, 1.8), rng.uniform(0.4, 1.2), rng.uniform(0.4, 1.0)
        fx, fz = rng.uniform(0, max(0.01, W - fw)), -rng.uniform(1.0, max(1.1, D - 0.6))
        add((fx, H - fh, fz - fd), (fx + fw, H, fz), OTHER)

    if not boxes:
        add((0, 0, -1e-3), (1e-3, 1e-3, 0), WALL)
    lo = np.array([b[0] for b in boxes], float)
    hi = np.array([b[1] for b in boxes], float)
    floor_bottom = np.array([[W - side_right, H, -front_right], [side_left, H, -front_left]], float)
    return Scene(W, H, D, np.array([-e_left, 0.0, -D]), np.array([W + e_right, H, gap]), lo, hi,
                 np.array([b[2] for b in boxes]), np.array([b[3] for b in boxes]), kitchen, floor_bottom)


def project(cam: Camera, points: np.ndarray) -> np.ndarray | None:
    """World points to fractions of the photo, or None if any is behind the camera."""
    p = (points - cam.pos) @ cam.R.T
    if np.any(p[:, 2] < 0.15):
        return None
    return np.stack([(cam.f * p[:, 0] / p[:, 2] + cam.w / 2) / cam.w,
                     (cam.f * p[:, 1] / p[:, 2] + cam.h / 2) / cam.h], 1)


def wall_corners(scene: Scene, cam: Camera) -> np.ndarray | None:
    """The front wall's corners: top-left, top-right, bottom-right, bottom-left."""
    W, H = scene.W, scene.H
    return project(cam, np.array([[0, 0, 0], [W, 0, 0], [W, H, 0], [0, H, 0]], float))


def random_camera(rng: np.random.Generator, scene: Scene):
    """A phone held by someone photographing the front wall. (camera, corners) or None."""
    W, H, D = scene.W, scene.H, scene.D
    aspect = float(rng.choice([4 / 3, 16 / 9, 3 / 2, 3 / 4, 1.0], p=[0.5, 0.18, 0.14, 0.13, 0.05]))
    r = rng.random()
    f35 = rng.uniform(23, 29) if r < 0.72 else (rng.uniform(13, 18) if r < 0.86 else rng.uniform(30, 40))
    h_px = 1000.0
    w_px = h_px * aspect
    f = f35 * math.hypot(w_px, h_px) / 43.2666
    for _ in range(30):
        pos = np.array([rng.uniform(0.12, 0.88) * W, H - rng.uniform(1.1, 1.7), min(-1.0, -rng.uniform(0.45, 0.97) * D)])
        # Not standing inside the furniture.
        if np.any(np.all((pos > scene.lo - 0.25) & (pos < scene.hi + 0.25), axis=1)):
            continue
        target = np.array([W / 2 + rng.normal(0, 0.12 * W), H - rng.uniform(0.9, 1.6), 0.0])
        v = target - pos
        yaw = math.atan2(v[0], v[2]) + rng.normal(0, math.radians(4))
        pitch = -math.atan2(v[1], math.hypot(v[0], v[2])) + rng.normal(0, math.radians(3))
        roll = float(np.clip(rng.normal(0, math.radians(1.3)), -math.radians(4), math.radians(4)))
        cam = Camera(pos, _rotation(yaw, pitch, roll), f, w_px, h_px)
        c = wall_corners(scene, cam)
        if c is None or np.any(c < -0.35) or np.any(c > 1.35):
            continue
        if np.all((c > -0.02) & (c < 1.02), axis=1).sum() < 2:
            continue
        x, y = c[:, 0], c[:, 1]
        if 0.5 * abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))) < 0.12:
            continue
        return cam, c
    return None


def render(scene: Scene, cam: Camera, n: int = 128):
    """Inverse depth and labels, n × n over the whole photo (squeezed square)."""
    a = (np.arange(n) + 0.5) / n
    uu, vv = np.meshgrid(a, a)
    dc = np.stack([(uu - 0.5) * cam.w / cam.f, (vv - 0.5) * cam.h / cam.f, np.ones_like(uu)], -1).reshape(-1, 3)
    dw = dc @ cam.R  # camera -> world
    dw = np.where(np.abs(dw) < 1e-9, 1e-9, dw)
    inv = 1.0 / dw
    o = cam.pos
    far = np.maximum((scene.room_lo - o) * inv, (scene.room_hi - o) * inv)
    t = far.min(1)
    axis = far.argmin(1)
    label = np.where(axis == 1, np.where(dw[:, 1] < 0, CEILING, FLOOR), WALL)
    offset = np.zeros_like(t)
    # Each box is tested only against the pixels inside its outline on the
    # photo (all of them if it reaches behind the camera): the same answer,
    # several times faster, as most boxes cover a small part of the photo.
    inv, t, label, offset = (a.reshape(n, n, -1) for a in (inv, t, label, offset))
    for lo, hi, lab, off in zip(scene.lo, scene.hi, scene.label, scene.offset):
        rows, cols = _box_window(lo, hi, cam, n)
        if rows is None:
            continue
        sub = inv[rows, cols]
        t1, t2 = (lo - o) * sub, (hi - o) * sub
        near = np.minimum(t1, t2).max(-1, keepdims=True)
        hit = (near < np.maximum(t1, t2).min(-1, keepdims=True)) & (near > 1e-4) & (near < t[rows, cols])
        t[rows, cols] = np.where(hit, near, t[rows, cols])
        label[rows, cols] = np.where(hit, lab, label[rows, cols])
        offset[rows, cols] = np.where(hit, off, offset[rows, cols])
    return (1.0 / (t + offset)).reshape(n, n).astype(np.float32), label.reshape(n, n).astype(np.uint8)


def _box_window(lo, hi, cam: Camera, n: int):
    """The rows and columns (slices) of the n × n photo a box can cover:
    its 8 corners' outline plus a pixel, or the whole photo if any corner is
    behind the camera. (None, None) if it's off the photo."""
    corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
    pc = (corners - cam.pos) @ cam.R.T  # world -> camera
    if (pc[:, 2] <= 1e-3).any():
        return slice(0, n), slice(0, n)
    u = (pc[:, 0] / pc[:, 2] * cam.f / cam.w + 0.5) * n - 0.5
    v = (pc[:, 1] / pc[:, 2] * cam.f / cam.h + 0.5) * n - 0.5
    c0, c1 = max(0, int(np.floor(u.min())) - 1), min(n, int(np.ceil(u.max())) + 2)
    r0, r1 = max(0, int(np.floor(v.min())) - 1), min(n, int(np.ceil(v.max())) + 2)
    if c0 >= c1 or r0 >= r1:
        return None, None
    return slice(r0, r1), slice(c0, c1)


def normalise(d: np.ndarray) -> np.ndarray:
    """Depth to 0..1 between its 1st and 99th percentiles, as the app does."""
    lo, hi = np.percentile(d, [1, 99])
    return np.clip((d - lo) / max(hi - lo, 1e-9), 0, 1).astype(np.float32)


def _blur(x: np.ndarray, sigma: float) -> np.ndarray:
    r = max(1, int(round(2.5 * sigma)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    for ax in (0, 1):
        p = np.pad(x, [(r, r) if a == ax else (0, 0) for a in (0, 1)], mode="edge")
        x = sum(k[i] * np.take(p, np.arange(i, i + x.shape[ax]), axis=ax) for i in range(2 * r + 1))
    return x


def _smooth_field(rng, n: int, cells: int = 4) -> np.ndarray:
    """A smooth random field, n × n, about unit size."""
    g = rng.normal(0, 1, (cells, cells))
    idx = np.linspace(0, cells - 1, n)
    i0 = np.clip(np.floor(idx).astype(int), 0, cells - 2)
    f = idx - i0
    rows = g[i0] * (1 - f)[:, None] + g[i0 + 1] * f[:, None]
    return rows[:, i0] * (1 - f)[None] + rows[:, i0 + 1] * f[None]


# What the segmentation model tends to call each thing when it gets it wrong.
_CONFUSED = {
    WALL: ([CABINET, OTHER, CEILING, DOOR, WINDOW], [0.35, 0.3, 0.15, 0.1, 0.1]),
    FLOOR: ([OTHER, CABINET, WALL], [0.7, 0.2, 0.1]),
    CEILING: ([WALL, OTHER], [0.8, 0.2]),
    WINDOW: ([WALL, OTHER, DOOR], [0.5, 0.3, 0.2]),
    CABINET: ([WALL, OTHER, DOOR], [0.5, 0.4, 0.1]),
    DOOR: ([WALL, CABINET, OTHER], [0.4, 0.3, 0.3]),
    OTHER: ([WALL, CABINET, FLOOR], [0.4, 0.4, 0.2]),
}


def degrade(rng: np.random.Generator, inv_depth: np.ndarray, label: np.ndarray):
    """The two models' kinds of mistake, on exact depth and labels."""
    n = label.shape[0]
    d = normalise(inv_depth)
    d = d ** rng.uniform(0.75, 1.35)  # the depth model's curve isn't exactly 1/z
    d = d + _smooth_field(rng, n) * rng.uniform(0, 0.035)
    d = _blur(d, rng.uniform(0.4, 1.8))  # its edges are soft
    d = d + rng.normal(0, rng.uniform(0, 0.006), d.shape)
    if rng.random() < 0.04:  # sometimes it's no help at all
        d = _blur(_smooth_field(rng, n) * 0.2 + 0.5, 3.0)
    d = normalise(d)

    lab = label.copy()
    yy, xx = np.mgrid[0:n, 0:n]
    for _ in range(rng.integers(0, 7)):  # patches called something else
        present = np.unique(lab)
        src = int(rng.choice(present))
        to, p = _CONFUSED[src]
        dst = int(rng.choice(to, p=p))
        cx, cy = rng.uniform(0, n, 2)
        rx, ry = rng.uniform(3, 45, 2)
        edge = 1 + 0.35 * _smooth_field(rng, n, 5)
        lab[(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 < edge) & (lab == src)] = dst
    if rng.random() < 0.5:  # labels come at a coarser grid and a pixel or two off
        m = int(rng.choice([48, 64, 96]))
        down = np.clip(((np.arange(m) + 0.5) / m * n).astype(int), 0, n - 1)
        up = np.clip(((np.arange(n) + 0.5) / n * m).astype(int), 0, m - 1)
        lab = lab[np.ix_(down, down)][np.ix_(up, up)]
    sx, sy = rng.integers(-2, 3, 2)
    lab = np.roll(np.roll(lab, sy, 0), sx, 1)
    salt = rng.random(lab.shape) < rng.uniform(0, 0.01)
    lab[salt] = OTHER
    if rng.random() < 0.04:  # sometimes the labels are no help at all
        lab[:] = WALL
    return d, lab


def to_input(depth01: np.ndarray, label: np.ndarray, aspect: float) -> np.ndarray:
    """The corner model's input: (CHANNELS, n, n) float32."""
    n = label.shape[0]
    x = np.zeros((CHANNELS, n, n), np.float32)
    x[0] = depth01
    for c in range(NUM_CLASSES):
        x[1 + c] = label == c
    a = (np.arange(n, dtype=np.float32) + 0.5) / n
    x[1 + NUM_CLASSES] = a[None, :]
    x[2 + NUM_CLASSES] = a[:, None]
    x[3 + NUM_CLASSES] = math.log(aspect)
    return x


def sample(rng: np.random.Generator, n: int = 128, noisy: bool = True):
    """One training example: (input, the answer as 12 fractions, is kitchen).

    The answer is POINTS points, x then y as fractions of the photo: the
    wall's corners as a salesperson marks them (top-left, top-right,
    bottom-right, bottom-left, the bottom ones where the floor visibly meets
    the cabinets), then the true bottom-right and bottom-left corners hidden
    behind them, which the app measures with.
    """
    while True:
        scene = random_scene(rng)
        got = random_camera(rng, scene)
        if got is None:
            continue
        cam, true_corners = got
        floor = project(cam, scene.floor_bottom)
        if floor is None:
            continue
        corners = np.concatenate([true_corners[:2], floor, true_corners[2:]])
        # A cabinet corner right beside the camera lands far off the photo or
        # twists the outline: nobody would mark a wall like that.
        if np.any(floor < -0.35) or np.any(floor > 1.35) or not _convex(corners[:4]):
            continue
        inv, lab = render(scene, cam, n)
        if (inv > 1 / 0.6).mean() > 0.1:  # nobody photographs a wall with a cupboard in their face
            continue
        if noisy:
            d, lab = degrade(rng, inv, lab)
        else:
            d = normalise(inv)
        return to_input(d, lab, cam.w / cam.h), corners.reshape(-1).astype(np.float32), scene.kitchen


def _convex(q: np.ndarray) -> bool:
    """Whether four points, in order, make a convex four-sided shape."""
    d = np.roll(q, -1, axis=0) - q
    cross = d[:, 0] * np.roll(d, -1, axis=0)[:, 1] - d[:, 1] * np.roll(d, -1, axis=0)[:, 0]
    return bool(np.all(cross > 1e-9) or np.all(cross < -1e-9))


def mirror(x: np.ndarray, corners: np.ndarray):
    """A sample flipped left to right: another room, just as likely, for free.
    The points swap sides (top-left becomes top-right, and so on)."""
    m = x[:, :, ::-1].copy()
    m[1 + NUM_CLASSES] = x[1 + NUM_CLASSES]  # the x-position map stays left to right
    tl, tr, br, bl, wall_br, wall_bl = corners.reshape(POINTS, 2)
    flip = lambda p: (1 - p[0], p[1])  # noqa: E731
    return m, np.array([flip(tr), flip(tl), flip(bl), flip(br), flip(wall_bl), flip(wall_br)],
                       np.float32).reshape(-1)


def ade_to_classes(ids: np.ndarray) -> np.ndarray:
    """The segmentation model's ids to this module's classes."""
    out = np.full(ids.shape, OTHER, np.uint8)
    for ade, cls in ADE_TO_CLASS.items():
        out[ids == ade] = cls
    return out
