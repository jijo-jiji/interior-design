"""Prototype: the front wall's four corners from a single photo, by depth.

Depth Anything V2 Small gives a relative inverse depth for every pixel. In
inverse depth, every flat surface in the room is a flat patch over the image
(d = a*u + b*v + c), whatever the unknown scale and shift. So:

  1. fit flat patches (RANSAC): front wall, side walls, ceiling, floor;
  2. the front wall is the patch in the middle of the photo;
  3. where it meets each neighbour is a straight line in the photo, exactly:
     (a1-a2)*u + (b1-b2)*v + (c1-c2) = 0;
  4. the corners are where those lines cross.

    python depth_corners.py MODEL.onnx OUT_DIR PHOTO [PHOTO ...]

MODEL.onnx is Depth Anything V2 Small (Apache 2.0), not kept in the repo:
onnx/model.onnx from huggingface.co/onnx-community/depth-anything-v2-small
(99.1 MB; sha256 afb6a5c28f3b6bf1618c6e43f02073ef9dfdc70e937502d51603e57b0a1df10c).
Needs onnxruntime, numpy and Pillow. Writes a picture per photo to OUT_DIR:
the depth, and the flat patches found with the corners (red) and, for a
synthetic photo, the true wall (white).

Prototype only (PC). On synthetic angled photos the corners land 4-40 px
from the truth; a head-on render with a plain wall confuses the depth model.
Real photos decide whether it goes into the app.

A PHOTO with a .json beside it (from make_synthetic.py) is scored against
its true corners.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw

MEAN = np.array([0.485, 0.456, 0.406], np.float32)
STD = np.array([0.229, 0.224, 0.225], np.float32)
rng = np.random.default_rng(7)


def inverse_depth(session, photo: Image.Image) -> np.ndarray:
    w, h = photo.size
    s = 518 / min(w, h)
    W, H = int(round(w * s / 14)) * 14, int(round(h * s / 14)) * 14
    x = np.asarray(photo.convert("RGB").resize((W, H), Image.BICUBIC), np.float32) / 255
    x = ((x - MEAN) / STD).transpose(2, 0, 1)[None].astype(np.float32)
    return session.run(None, {"pixel_values": x})[0][0]


def fit_plane(u, v, d):
    a = np.stack([u, v, np.ones_like(u)], 1)
    coef, *_ = np.linalg.lstsq(a, d, rcond=None)
    return coef


def planes(disp: np.ndarray, max_planes=6, tau=0.012, iters=600):
    """Sequential RANSAC over (u, v, d), u and v as fractions of the photo,
    d scaled to 0..1. Returns [(coef, mask)] largest first."""
    h, w = disp.shape
    lo, hi = np.percentile(disp, [1, 99])
    d = np.clip((disp - lo) / (hi - lo), 0, 1)
    vv, uu = np.mgrid[0:h, 0:w]
    u, v = (uu + 0.5) / w, (vv + 0.5) / h
    free = np.ones_like(d, bool)
    found = []
    for _ in range(max_planes):
        idx = np.flatnonzero(free)
        if idx.size < 0.03 * d.size:
            break
        best, best_n = None, 0
        for _ in range(iters):
            pick = rng.choice(idx, 3, replace=False)
            try:
                coef = np.linalg.solve(
                    np.stack([u.flat[pick], v.flat[pick], np.ones(3)], 1), d.flat[pick])
            except np.linalg.LinAlgError:
                continue
            res = np.abs(u.flat[idx] * coef[0] + v.flat[idx] * coef[1] + coef[2] - d.flat[idx])
            n = int((res < tau).sum())
            if n > best_n:
                best, best_n = coef, n
        if best is None or best_n < 0.03 * d.size:
            break
        res = np.abs(u * best[0] + v * best[1] + best[2] - d)
        inl = free & (res < tau)
        coef = fit_plane(u[inl], v[inl], d[inl])
        res = np.abs(u * coef[0] + v * coef[1] + coef[2] - d)
        inl = free & (res < tau)
        found.append((coef, inl))
        free &= ~inl
    return found, (u, v, d)


def line_between(p, q):
    """The line where patches p and q meet: A*u + B*v + C = 0 (fractions)."""
    return p - q


def cross(l1, l2):
    """Where two lines meet, as (u, v) fractions, or None if parallel."""
    m = np.array([[l1[0], l1[1]], [l2[0], l2[1]]])
    if abs(np.linalg.det(m)) < 1e-9:
        return None
    return np.linalg.solve(m, [-l1[2], -l2[2]])


def fit_line(points, along_y: bool, tol=2.0, iters=300):
    """Robust line through edge points: x = m*y + b if along_y, else y = m*x + b.
    Returned as A*x + B*y + C = 0."""
    pts = np.asarray(points, float)
    if len(pts) < 8:
        return None
    s, t = (pts[:, 1], pts[:, 0]) if along_y else (pts[:, 0], pts[:, 1])
    best, best_n = None, 0
    for _ in range(iters):
        i, j = rng.choice(len(pts), 2, replace=False)
        if s[i] == s[j]:
            continue
        m = (t[j] - t[i]) / (s[j] - s[i]); b = t[i] - m * s[i]
        n = int((np.abs(m * s + b - t) < tol).sum())
        if n > best_n:
            best, best_n = (m, b), n
    m, b = best
    inl = np.abs(m * s + b - t) < tol
    m, b = np.polyfit(s[inl], t[inl], 1)
    # t = m*s + b  ->  as A*x + B*y + C = 0
    return np.array([-1.0, m, b]) if along_y else np.array([m, -1.0, b])


def wall_edges(front: np.ndarray, cx: int, cy: int, gap=6, margin=2):
    """The front wall's edge points, walking out from its middle along every
    row and column, across small gaps (a window frame, a light switch)."""
    h, w = front.shape
    left, right, top, bottom = [], [], [], []

    def walk(line, start, step):
        last, misses, i = start, 0, start
        while 0 <= i + step < len(line):
            i += step
            if line[i]:
                last, misses = i, 0
            else:
                misses += 1
                if misses > gap:
                    break
        return last

    for y in range(h):
        if front[y, max(0, cx - 3):cx + 4].any():
            l, r = walk(front[y], cx, -1), walk(front[y], cx, 1)
            if l > margin: left.append((l, y))
            if r < w - 1 - margin: right.append((r, y))
    for x in range(w):
        if front[max(0, cy - 3):cy + 4, x].any():
            t, b = walk(front[:, x], cy, -1), walk(front[:, x], cy, 1)
            if t > margin: top.append((x, t))
            if b < h - 1 - margin: bottom.append((x, b))
    return left, right, top, bottom


def corners_from_depth(disp: np.ndarray, tau=0.012):
    """Corners from the front wall's own outline: fit the flat patches on a
    small copy, label the full-size depth by them, and fit a straight line
    to each side of the front wall's region."""
    h, w = disp.shape
    small = np.asarray(Image.fromarray(disp).resize((160, int(160 * h / w))))
    found, _ = planes(small, tau=tau)
    lo, hi = np.percentile(small, [1, 99])
    d = np.clip((disp - lo) / (hi - lo), 0, 1)
    vv, uu = np.mgrid[0:h, 0:w]
    u, v = (uu + 0.5) / w, (vv + 0.5) / h
    res = np.stack([np.abs(u * c[0] + v * c[1] + c[2] - d) for c, _ in found])
    label = res.argmin(0)
    label[res.min(0) > 2.5 * tau] = -1
    mid = (np.abs(u - 0.5) < 0.15) & (np.abs(v - 0.5) < 0.15)
    front_i = int(np.bincount(label[mid & (label >= 0)], minlength=len(found)).argmax())
    front = label == front_i
    cx, cy = int(uu[front & mid].mean()), int(vv[front & mid].mean())
    left, right, top, bottom = wall_edges(front, cx, cy)
    lines = {
        "left": fit_line(left, True), "right": fit_line(right, True),
        "top": fit_line(top, False), "bottom": fit_line(bottom, False),
    }
    found_full = [(c, label == i) for i, (c, _) in enumerate(found)]
    if any(l is None for l in lines.values()):
        return None, found_full, front_i, {k: v for k, v in lines.items() if v is not None}
    order = [("top", "left"), ("top", "right"), ("bottom", "right"), ("bottom", "left")]
    pts = []
    for a, b in order:
        p = cross(lines[a], lines[b])
        if p is None:
            return None, found_full, front_i, lines
        pts.append((p[0] / w, p[1] / h))
    return pts, found_full, front_i, lines


def corners_from_patch_lines(disp: np.ndarray):
    """First attempt, kept for comparison: corners from where fitted patches
    meet. Fragile when a patch is fitted badly (a wall close to the camera)."""
    found, (u, v, d) = planes(disp)
    h, w = disp.shape
    # The front wall: the patch covering most of the middle of the photo.
    mid = (np.abs(u - 0.5) < 0.15) & (np.abs(v - 0.5) < 0.15)
    front_i = max(range(len(found)), key=lambda i: (found[i][1] & mid).sum())
    front, front_mask = found[front_i]
    fu, fv = u[front_mask].mean(), v[front_mask].mean()

    # Each neighbour patch, by which side of the front wall it lies on.
    sides = {}
    for i, (coef, mask) in enumerate(found):
        if i == front_i or mask.sum() < 0.01 * mask.size:
            continue
        cu, cv = u[mask].mean() - fu, v[mask].mean() - fv
        side = ("left" if cu < 0 else "right") if abs(cu) > abs(cv) else ("top" if cv < 0 else "bottom")
        line = line_between(front, coef)
        # Keep the neighbour whose meeting line is nearest the front wall's
        # middle on that side (a far wall's ghost line would be further out).
        dist = abs(line[0] * fu + line[1] * fv + line[2]) / np.hypot(line[0], line[1])
        if side not in sides or dist < sides[side][1]:
            sides[side] = (line, dist, mask)
    if len(sides) < 4:
        return None, found, front_i, sides
    order = [("top", "left"), ("top", "right"), ("bottom", "right"), ("bottom", "left")]
    pts = [cross(sides[a][0], sides[b][0]) for a, b in order]
    if any(p is None for p in pts):
        return None, found, front_i, sides
    return pts, found, front_i, sides


def homography(src, dst):
    a, b = [], []
    for (x, y), (p, q) in zip(src, dst):
        a.append([x, y, 1, 0, 0, 0, -p * x, -p * y]); b.append(p)
        a.append([0, 0, 0, x, y, 1, -q * x, -q * y]); b.append(q)
    return np.append(np.linalg.solve(np.array(a, float), np.array(b, float)), 1).reshape(3, 3)


def score(found_px, truth):
    true = np.array(truth["wall_corners_px"])
    err_px = np.hypot(*(np.array(found_px) - true).T)
    if "openings" not in truth:  # a real photo: corners marked by hand only
        return err_px, {}
    wall_w, wall_h = truth["wall_mm"]
    hm = homography(found_px, [(0, 0), (wall_w, 0), (wall_w, wall_h), (0, wall_h)])
    worst = {}
    for o in truth["openings"]:
        top = wall_h - o["from_floor"] - o["height"]
        exp = [(o["left"], top), (o["left"] + o["width"], top),
               (o["left"] + o["width"], top + o["height"]), (o["left"], top + o["height"])]
        e = 0
        for (x, y), (X, Y) in zip(o["corners_px"], exp):
            p = hm @ [x, y, 1]
            e = max(e, np.hypot(p[0] / p[2] - X, p[1] / p[2] - Y))
        worst[o["type"]] = e
    return err_px, worst


def draw(photo, disp, found, front_i, pts, truth, out):
    w, h = photo.size
    overlay = photo.convert("RGB").copy()
    colours = [(80, 200, 120), (230, 120, 60), (90, 140, 230), (220, 200, 60), (190, 90, 200), (60, 200, 210)]
    seg = np.zeros((*found[0][1].shape, 3), np.uint8)
    for i, (_, mask) in enumerate(found):
        seg[mask] = colours[i % len(colours)]
    seg_img = Image.fromarray(seg).resize((w, h), Image.NEAREST)
    overlay = Image.blend(overlay, seg_img, 0.35)
    dr = ImageDraw.Draw(overlay)
    if truth:
        t = [tuple(p) for p in truth["wall_corners_px"]]
        dr.line(t + [t[0]], fill=(255, 255, 255), width=3)
    if pts:
        p = [(x * w, y * h) for x, y in pts]
        dr.line(p + [p[0]], fill=(255, 40, 40), width=4)
        for x, y in p:
            dr.ellipse((x - 9, y - 9, x + 9, y + 9), outline=(255, 40, 40), width=3)
    dmin, dmax = np.percentile(disp, [1, 99])
    depth_img = Image.fromarray((np.clip((disp - dmin) / (dmax - dmin), 0, 1) * 255).astype(np.uint8)).resize((w, h))
    sheet = Image.new("RGB", (w * 2, h), "black")
    sheet.paste(depth_img.convert("RGB"), (0, 0))
    sheet.paste(overlay, (w, 0))
    sheet.thumbnail((1600, 1600))
    sheet.save(out)


def main():
    model, out_dir, photos = sys.argv[1], Path(sys.argv[2]), sys.argv[3:]
    out_dir.mkdir(parents=True, exist_ok=True)
    session = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
    for path in photos:
        photo = Image.open(path)
        t0 = time.time()
        disp = inverse_depth(session, photo)
        t1 = time.time()
        pts, found, front_i, sides = corners_from_depth(disp)
        t2 = time.time()
        truth_path = Path(path).with_suffix(".json")
        truth = json.loads(truth_path.read_text(encoding="utf-8")) if truth_path.exists() else None
        name = Path(path).stem
        line = f"{name:22s} depth {t1 - t0:4.1f}s, corners {t2 - t1:4.1f}s, {len(found)} patches, sides {sorted(sides)}"
        if pts and truth:
            w, h = photo.size
            px = [(x * w, y * h) for x, y in pts]
            err, worst = score(px, truth)
            line += (f"\n{'':22s} corner error px: " + ", ".join(f"{e:.0f}" for e in err)
                     + ("   openings off by: " + ", ".join(f"{k} {v:.0f} mm" for k, v in worst.items())
                        if worst else ""))
        elif not pts:
            line += "  -> no corners"
        print(line)
        draw(photo, disp, found, front_i, pts, truth, out_dir / f"{name}.png")


if __name__ == "__main__":
    main()
