#!/usr/bin/env python3
"""Generates the finish textures the 3D page uses: assets/3d/textures/.

These are ORIGINAL, procedurally made stand-ins (no photographs, no licensed
images): seamless wood veneers, stones, terrazzo and a plank floor, each with
the maps a physically based material needs. They exist so the render looks
like real materials until SS Love's designer supplies photographs of the
actual finishes; see assets/3d/textures/README.md for how to swap them in.

    python tool/gen_finish_textures.py            # writes the textures + manifest.json
    python tool/gen_finish_textures.py --preview DIR   # also a contact sheet in DIR

Needs numpy and Pillow. Deterministic: the same seeds give the same files.
Conventions the page relies on:
  * every texture tiles seamlessly;
  * wood grain runs along the image's vertical axis (a door's height);
  * *_albedo are sRGB colour; *_normal are tangent-space normals (OpenGL, +Y up);
    *_rough are linear roughness in the green channel (greyscale).
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "3d", "textures")
SIZE = 1024      # albedo
SMALL = 512      # normal and roughness maps: relief and gloss need less detail


# ── Tileable noise ───────────────────────────────────────────────────────────


def fnoise(shape, beta=1.0, fx=1.0, fy=1.0, lo=0.0, hi=None, seed=0):
    """Seamless noise with a 1/f^beta spectrum, zero mean, unit deviation.

    fx and fy weight the horizontal and vertical frequencies: the larger a
    weight, the faster that direction's detail dies away, so a large fy makes
    features long in the vertical direction (grain) and a large fx makes them
    long in the horizontal one. lo and hi cut the band, in cycles per tile
    (before the weights)."""
    rng = np.random.default_rng(seed)
    h, w = shape
    ky = np.fft.fftfreq(h)[:, None] * h
    kx = np.fft.rfftfreq(w)[None, :] * w
    f = np.sqrt((kx * fx) ** 2 + (ky * fy) ** 2)
    f[0, 0] = 1.0
    spec = (rng.normal(size=f.shape) + 1j * rng.normal(size=f.shape)) / f ** beta
    spec[0, 0] = 0
    radius = np.sqrt(kx ** 2 + ky ** 2)
    if lo:
        spec[radius < lo] = 0
    if hi:
        spec[radius > hi] = 0
    n = np.fft.irfft2(spec, s=shape)
    return (n - n.mean()) / (n.std() + 1e-9)


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return a * (1 - t) + b * t


def rgb(r, g, b):
    return np.array([r, g, b], dtype=np.float64) / 255.0


def grid(size):
    v, u = np.mgrid[0:size, 0:size] / float(size)
    return u, v


# ── Maps from a height field ─────────────────────────────────────────────────


def normal_from_height(height, strength=1.0):
    """Tangent-space normal map (OpenGL convention) from a seamless height
    field, by central differences."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nx, ny = -dx * strength, dy * strength  # +Y up: image rows run down
    nz = np.ones_like(nx)
    length = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    n = np.stack([nx / length, ny / length, nz / length], axis=-1)
    return n * 0.5 + 0.5


def resample(img, size):
    """Smaller copy of an HxW or HxWx3 float image (box average), keeping its
    shape: [size] is the width."""
    h, w = img.shape[:2]
    f = w // size
    if f <= 1:
        return img
    nh = h // f
    img = img[:nh * f, :size * f]
    if img.ndim == 2:
        return img.reshape(nh, f, size, f).mean(axis=(1, 3))
    return img.reshape(nh, f, size, f, img.shape[2]).mean(axis=(1, 3))


def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255.0 + 0.5).astype(np.uint8))


# ── Woods ────────────────────────────────────────────────────────────────────


def wood(seed, early, late, *, rings=9.0, ring_wander=0.55, contrast=1.0, pores=0.5,
         flecks=0.0, figure=0.5, tone=0.05, pore_color=0.45, relief=1.0, sheen=0.62):
    """A flat-sawn veneer, grain along the vertical axis.

    Returns (albedo HxWx3, height HxW, roughness HxW)."""
    n = SIZE
    u, v = grid(n)
    shape = (n, n)

    # Growth rings: dense, nearly straight lines of constant phase that drift
    # slowly along the grain, and arch (cathedral figure) where the log's
    # centre line passes. Amplitudes are in rings, so they scale with density.
    wander = fnoise(shape, 1.7, fx=1.0, fy=10.0, lo=1, hi=3, seed=seed + 1)
    arch = np.sin(2 * np.pi * (v + 0.15 * np.sin(2 * np.pi * u))) * np.cos(2 * np.pi * u)
    phase = rings * u + ring_wander * rings * 0.09 * wander + figure * rings * 0.12 * arch
    t = phase % 1.0
    # Earlywood fades into a narrower, darker band of latewood, then steps back.
    late_w = smooth(t, 0.45, 0.96) ** 1.6 * (1 - smooth(t, 0.96, 1.0))
    late_w *= contrast

    # Fine grain: long thin streaks that break the rings up.
    streak = fnoise(shape, 0.9, fx=1.0, fy=30.0, lo=6, hi=170, seed=seed + 2)
    fine = fnoise(shape, 0.5, fx=1.0, fy=18.0, lo=40, hi=250, seed=seed + 3)
    grain = 0.11 * streak + 0.045 * fine

    # Pores: small dark dashes along the grain, denser in the earlywood.
    p = fnoise(shape, 0.3, fx=1.0, fy=7.0, lo=60, hi=300, seed=seed + 4)
    pore_mask = smooth(p, 1.15 - 0.5 * (1 - late_w), 2.3) * pores

    # Medullary ray flecks: short bright and dark dashes ACROSS the grain.
    fl = fnoise(shape, 0.2, fx=6.0, fy=1.0, lo=50, hi=260, seed=seed + 5)
    fleck_mask = smooth(fl, 1.9, 3.0) * flecks

    # Slow tone drift across and along the boards.
    cloud = fnoise(shape, 1.8, fx=1.0, fy=3.0, lo=1, hi=5, seed=seed + 6)

    col = mix(early, late, np.clip(late_w * 0.55 + 0.5 * grain + 0.25 * cloud * tone * 8, 0, 1))
    col = col * (1 - pore_mask[..., None] * pore_color)
    col = col * (1 + 0.05 * cloud[..., None] * tone * 10)
    col = col * (1 - 0.06 * fleck_mask[..., None]) + 0.07 * fleck_mask[..., None]

    height = (-pore_mask * 0.9 - late_w * 0.12 + grain * 0.5) * relief
    rough = np.clip(sheen + 0.28 * pore_mask + 0.05 * streak - 0.03 * late_w, 0.2, 1.0)
    return np.clip(col, 0, 1), height, rough


# ── Stones ───────────────────────────────────────────────────────────────────


def veins(shape, seed, scale=1.0, sharp=0.965, bundles=2, bold=1.0):
    """Marble-style veins: long lines running diagonally that meander and vary
    in thickness, with finer veins branching in between. 0..1.

    Built from the phase of a tilted wave (veins sit where it is a whole
    number), pushed about by noise: lines can wander but never close into
    loops. The wave's direction uses whole numbers so the tile is seamless."""
    n = shape[0]
    u, v = grid(n)
    out = np.zeros(shape)
    layers = [(bundles, 0.18, 0.030 * bold, 1.0), (bundles * 3 + 1, 0.14, 0.010, 0.55), (bundles * 8 + 1, 0.11, 0.0045, 0.35)]
    for i, (k, amp, w0, weight) in enumerate(layers):
        drift = fnoise(shape, 1.4, lo=1, hi=2 + i, seed=seed + 10 + i)
        thick = 0.3 + 1.5 * smooth(fnoise(shape, 1.4, lo=1, hi=5, seed=seed + 20 + i), -0.7, 1.3)
        m = max(1, int(round(k * 0.6)))
        phase = k * u + m * v + amp * drift * scale
        d = np.abs(phase - np.round(phase))
        width = w0 * thick
        core = np.exp(-(d / width) ** 2)
        halo = np.exp(-(d / (width * 5)) ** 2) * 0.22
        out = np.maximum(out, (core + halo * (i == 0)) * weight)
    return np.clip(out, 0, 1)


def quartz(seed, base, *, speckle=0.05, vein_color=None, vein_amount=0.0, vein_scale=1.0,
           cloud=0.008, gold=None, sharp=0.965, bundles=2, bold=1.0):
    """Engineered quartz / marble: a pale body, a fine speckle and veining."""
    n = SIZE
    shape = (n, n)
    c = fnoise(shape, 1.7, lo=1, hi=6, seed=seed) * cloud
    col = np.tile(base, (n, n, 1)) * (1 + c[..., None])
    rng = np.random.default_rng(seed + 3)
    specks = rng.random(shape)
    dark = smooth(specks, 0.985, 1.0) * speckle * 9
    light = smooth(1 - specks, 0.988, 1.0) * speckle * 4
    col = col * (1 - dark[..., None]) + light[..., None] * 0.5
    if vein_color is not None and vein_amount > 0:
        vv = veins(shape, seed + 40, scale=vein_scale, sharp=sharp, bundles=bundles, bold=bold)
        col = mix(col, np.tile(vein_color, (n, n, 1)), np.clip(vv * vein_amount, 0, 1))
        if gold is not None:
            gv = veins(shape, seed + 60, scale=1.4, sharp=0.985, bundles=bundles)
            col = mix(col, np.tile(gold, (n, n, 1)), np.clip(gv * vein_amount * 0.6, 0, 1))
    height = np.zeros(shape)
    rough = np.clip(0.16 + 0.05 * fnoise(shape, 1.0, lo=4, hi=60, seed=seed + 7), 0.08, 0.5)
    return np.clip(col, 0, 1), height, rough


def granite(seed, base, *, fleck_colors, density=0.06):
    """Dark granite: a near-black body with crystalline flecks."""
    n = SIZE
    shape = (n, n)
    c = fnoise(shape, 1.5, lo=2, hi=40, seed=seed) * 0.018
    col = np.tile(base, (n, n, 1)) * (1 + c[..., None])
    rng = np.random.default_rng(seed + 2)
    for i, (color, amount) in enumerate(fleck_colors):
        f = fnoise(shape, 0.0, lo=80, hi=400, seed=seed + 10 + i)
        m = smooth(f, 1.55 + 0.25 * i, 2.7) * amount * density * 16
        col = mix(col, np.tile(color, (n, n, 1)), np.clip(m, 0, 1))
    height = np.zeros(shape)
    rough = np.clip(0.18 + 0.06 * fnoise(shape, 1.0, lo=30, hi=120, seed=seed + 9), 0.1, 0.4)
    return np.clip(col, 0, 1), height, rough


def slate(seed, base):
    """Honed dark slate: soft cloudy tone, fine cleft lines, a little relief."""
    n = SIZE
    shape = (n, n)
    cloud = fnoise(shape, 1.9, lo=1, hi=7, seed=seed) * 0.02
    cleft = fnoise(shape, 0.9, fx=1.0, fy=2.0, lo=20, hi=160, seed=seed + 1)
    fine = fnoise(shape, 0.4, lo=60, hi=300, seed=seed + 2)
    tone = 1 + cloud + 0.05 * cleft + 0.06 * fine
    col = np.tile(base, (n, n, 1)) * tone[..., None]
    # faint lighter mineral streaks
    streak = smooth(fnoise(shape, 1.3, fx=1.0, fy=5.0, lo=3, hi=20, seed=seed + 3), 1.2, 2.6)
    col = mix(col, col * 1.2, streak * 0.35)
    height = 0.55 * cleft + 0.25 * fine + 0.6 * cloud * 3
    rough = np.clip(0.52 + 0.12 * cleft - 0.05 * cloud * 3, 0.25, 0.9)
    return np.clip(col, 0, 1), height, rough


def terrazzo(seed, matrix, chips, *, count=1500, size=(0.006, 0.022)):
    """Light terrazzo: coloured marble chips in a pale cement matrix."""
    n = SIZE
    rng = np.random.default_rng(seed)
    base = Image.new("RGB", (n, n), tuple((matrix * 255).astype(int)))
    cloud = fnoise((n, n), 1.7, lo=1, hi=8, seed=seed + 1) * 0.02
    a = np.asarray(base).astype(np.float64) / 255.0 * (1 + cloud[..., None])
    base = to_img(a)
    d = ImageDraw.Draw(base)
    palette = [(np.array(c) / 255.0, w) for c, w in chips]
    weights = np.array([w for _, w in palette], dtype=float)
    weights /= weights.sum()
    for _ in range(count):
        color, _w = palette[rng.choice(len(palette), p=weights)]
        # a lot of small chips, a few large: log-uniform size
        r = np.exp(rng.uniform(np.log(size[0]), np.log(size[1]))) * n / 0.8 / 2
        cx, cy = rng.uniform(0, n, 2)
        k = rng.integers(5, 8)
        angles = np.sort(rng.uniform(0, 2 * np.pi, k))
        radii = r * rng.uniform(0.55, 1.15, k)
        shade = rng.uniform(0.9, 1.08)
        fill = tuple(np.clip(color * shade * 255, 0, 255).astype(int))
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                pts = [(cx + ox + rr * np.cos(a_), cy + oy + rr * np.sin(a_)) for rr, a_ in zip(radii, angles)]
                if max(p[0] for p in pts) < 0 or min(p[0] for p in pts) > n or max(p[1] for p in pts) < 0 or min(p[1] for p in pts) > n:
                    continue
                d.polygon(pts, fill=fill)
    col = np.asarray(base).astype(np.float64) / 255.0
    fine = fnoise((n, n), 0.4, lo=80, hi=400, seed=seed + 2) * 0.018
    col = col * (1 + fine[..., None])
    height = np.zeros((n, n))
    rough = np.clip(0.34 + 0.07 * fnoise((n, n), 1.0, lo=10, hi=100, seed=seed + 3), 0.15, 0.7)
    return np.clip(col, 0, 1), height, rough


# ── Floor ────────────────────────────────────────────────────────────────────


def floor_planks(seed, early, late, *, planks=16, plank_len=(0.30, 0.55), pool=8):
    """Wide-plank oak floor, planks running along the image's horizontal axis,
    covering about 2.4 m of floor: staggered ends, a different tone per plank."""
    n = 2048
    rng = np.random.default_rng(seed)
    out = np.zeros((n, n, 3))
    height = np.zeros((n, n))
    rough = np.zeros((n, n))
    row_h = n // planks
    # A few different boards, grain turned to run along the plank.
    boards = []
    for i in range(pool):
        col, hgt, rgh = wood(seed * 10 + i, early, late, rings=float(rng.uniform(34, 54)), ring_wander=0.3,
                             contrast=float(rng.uniform(0.8, 1.1)), pores=0.25, figure=0.35, relief=0.8,
                             sheen=0.5, tone=0.04)
        boards.append(tuple(np.tile(np.rot90(a)[:row_h, :], (1, 2) if a.ndim == 2 else (1, 2, 1)) for a in (col, hgt, rgh)))
    for row in range(planks):
        x = -int(rng.uniform(0, 1) * n * 0.5)
        while x < n:
            ln = int(n * rng.uniform(*plank_len))
            col, hgt, rgh = boards[int(rng.integers(0, pool))]
            tone = rng.uniform(0.93, 1.07)
            hue = rng.uniform(-0.012, 0.012)
            col = col * tone * np.array([1 + hue, 1, 1 - hue])
            start = max(x, 0)
            length = min(ln + min(x, 0), n - start)
            if length > 0:
                take = np.arange(start, start + length)
                off = int(rng.integers(0, col.shape[1] - length))
                ys = row * row_h
                out[ys:ys + row_h, take] = col[:, off:off + length]
                height[ys:ys + row_h, take] = hgt[:, off:off + length]
                rough[ys:ys + row_h, take] = rgh[:, off:off + length]
                # the seam where this board ends
                seam = take[:3]
                out[ys:ys + row_h, seam] *= 0.55
                height[ys:ys + row_h, seam] -= 1.4
            x += ln
        out[row * row_h:row * row_h + 3, :] *= 0.55
        height[row * row_h:row * row_h + 3, :] -= 1.4
    return np.clip(out, 0, 1), height, np.clip(rough, 0.2, 1.0)


# ── Painted and matte laminate surfaces ──────────────────────────────────────


def micro(seed):
    """What a matte painted or laminate front looks like up close: an almost
    imperceptible orange-peel relief and uneven gloss. Used with a flat colour."""
    n = SMALL
    shape = (n, n)
    peel = fnoise(shape, 0.8, lo=30, hi=140, seed=seed) * 0.5 + 0.5 * fnoise(shape, 0.3, lo=100, hi=250, seed=seed + 1)
    rough = np.clip(0.62 + 0.03 * fnoise(shape, 1.0, lo=2, hi=60, seed=seed + 2) + 0.02 * peel, 0.35, 0.9)
    return peel, rough


# ── Tiles ────────────────────────────────────────────────────────────────────


def tile_maps(inside, edge, tint, *, grout=rgb(206, 204, 198), seed=0):
    """Colour, height and roughness for a glazed tile layout.

    [inside] is 1 inside a tile and 0 in the grout; [edge] is 0 at a tile's
    edge rising to 1 a few pixels in (the bevel)."""
    h, w = inside.shape
    var = fnoise((h, w), 0.2, lo=2, hi=40, seed=seed) * 0.006
    cell = np.tile(tint, (h, w, 1)) * (1 + var[..., None])
    # per-tile tone: smooth the id field by quantising low-frequency noise
    col = mix(np.tile(grout, (h, w, 1)), np.clip(cell, 0, 1), inside)
    # the glaze darkens very slightly toward the edges
    col = col * (1 - 0.035 * (1 - edge))[..., None]
    height = inside * (0.5 + 0.5 * edge) - 1.0
    rough = np.clip(0.12 + (1 - inside) * 0.7, 0.05, 1.0)
    return np.clip(col, 0, 1), height, rough


def subway(seed=0):
    """Subway tile, 150 x 75 mm with a 2 mm joint, laid in a half-brick bond;
    the tile is 0.6 m square (4 bricks across, 8 courses)."""
    n = SIZE
    px_w, px_h = n / 4.0, n / 8.0
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    row = np.floor(y / px_h)
    xx = (x + (row % 2) * px_w / 2.0) % px_w
    yy = y % px_h
    grout_px = 3.0
    dx = np.minimum(xx, px_w - xx)
    dy = np.minimum(yy, px_h - yy)
    d = np.minimum(dx, dy)
    inside = smooth(d, grout_px * 0.5, grout_px * 0.5 + 1.2)
    edge = smooth(d, grout_px, grout_px + 7.0)
    return tile_maps(inside, edge, rgb(243, 243, 241), seed=seed)


def hexagons(seed=0):
    """A hexagon mosaic, 12 across (about 50 mm each); the tile is 0.6 m wide
    and about 0.52 m high (six double rows of hexagons)."""
    w = SIZE
    h = int(round(w / 12.0 * 6 * np.sqrt(3)))
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    # lattice units: one hexagon is 1 wide (flat to flat), rows 0.5*sqrt(3) apart
    u = x / (w / 12.0)
    v = y / (h / (6 * np.sqrt(3)))
    def to_nearest(u, v, du, dv):
        # distance to the nearest of two interleaved lattices
        a = ((u - du) % 1.0) - 0.5, ((v - dv) % np.sqrt(3)) - np.sqrt(3) / 2
        return a
    ax, ay = to_nearest(u, v, 0.0, 0.0)
    bx, by = to_nearest(u, v, 0.5, np.sqrt(3) / 2)
    def hexdist(px, py):
        # hexagon with flat sides left and right: distance to the edge, in lattice units
        px, py = np.abs(px), np.abs(py)
        return 0.5 - np.maximum(px, px * 0.5 + py * np.sqrt(3) / 2)
    da, db = hexdist(ax, ay), hexdist(bx, by)
    d = np.maximum(da, db) * (w / 12.0)
    grout_px = 2.2
    inside = smooth(d, grout_px * 0.5, grout_px * 0.5 + 1.2)
    edge = smooth(d, grout_px, grout_px + 3.5)
    return tile_maps(inside, edge, rgb(240, 240, 237), seed=seed)


# ── The set ──────────────────────────────────────────────────────────────────

OAK_EARLY, OAK_LATE = rgb(232, 202, 158), rgb(196, 152, 104)
BIRCH_EARLY, BIRCH_LATE = rgb(240, 222, 188), rgb(222, 196, 156)
WALNUT_EARLY, WALNUT_LATE = rgb(106, 78, 60), rgb(56, 40, 32)


def build():
    """name -> (albedo, height, roughness, normal_strength, tile_m, kind)"""
    t = {}
    t["oak_light"] = (*wood(101, OAK_EARLY, OAK_LATE, rings=58, flecks=0.12, pores=0.34, figure=0.16, ring_wander=0.14, contrast=0.7, sheen=0.5), 1.2, 0.8, "wood")
    t["birch"] = (*wood(202, BIRCH_EARLY, BIRCH_LATE, rings=70, contrast=0.4, pores=0.2, figure=0.1,
                        ring_wander=0.1, tone=0.03, sheen=0.5), 0.8, 0.8, "wood")
    t["walnut"] = (*wood(303, WALNUT_EARLY, WALNUT_LATE, rings=46, contrast=0.7, pores=0.38, figure=0.2,
                         ring_wander=0.16, tone=0.06, pore_color=0.35, sheen=0.5), 1.4, 0.8, "wood")
    t["quartz_warm"] = (*quartz(11, rgb(246, 242, 234), speckle=0.05, vein_color=rgb(196, 192, 186),
                               vein_amount=0.30, vein_scale=0.8, bundles=1, bold=0.5), 0.0, 1.2, "stone")
    t["quartz_snow"] = (*quartz(12, rgb(250, 250, 248), speckle=0.045, cloud=0.015), 0.0, 1.2, "stone")
    t["calacatta"] = (*quartz(13, rgb(247, 245, 241), speckle=0.02, vein_color=rgb(128, 126, 134), vein_amount=0.9,
                             vein_scale=1.0, gold=rgb(198, 168, 118), cloud=0.01, sharp=0.9, bundles=2, bold=1.4), 0.0, 1.2, "stone")
    t["granite_black"] = (*granite(14, rgb(22, 22, 24), fleck_colors=[(rgb(96, 98, 104), 1.0), (rgb(160, 160, 166), 0.6),
                                                                        (rgb(70, 58, 52), 0.7)]), 0.0, 1.2, "stone")
    t["slate_dark"] = (*slate(15, rgb(74, 76, 82)), 1.8, 1.2, "stone")
    t["terrazzo"] = (*terrazzo(16, rgb(231, 226, 216),
                              [((70, 72, 74), 2), ((176, 120, 92), 2), ((148, 166, 140), 2), ((244, 240, 232), 3),
                               ((190, 176, 150), 3), ((36, 36, 38), 1)]), 0.0, 1.2, "stone")
    t["tile_subway"] = (*subway(21), 1.6, 0.6, "tile")
    t["tile_hex"] = (*hexagons(22), 1.6, 0.6, "tile")
    t["floor_oak"] = (*floor_planks(404, rgb(224, 192, 148), rgb(190, 150, 104)), 1.2, 2.4, "floor")
    return t


def save_set(name, albedo, height, rough, strength, out_dir):
    files = {"albedo": f"{name}_albedo.jpg"}
    img = to_img(albedo)
    img.save(os.path.join(out_dir, files["albedo"]), quality=84, optimize=True, progressive=True)
    if np.any(height != 0):
        h_small = resample(height, SMALL) if height.shape[1] > SMALL else height
        nrm = normal_from_height(h_small, strength)
        files["normal"] = f"{name}_normal.jpg"
        to_img(nrm).save(os.path.join(out_dir, files["normal"]), quality=88, optimize=True)
    r_small = resample(rough, SMALL) if rough.shape[1] > SMALL else rough
    files["roughness"] = f"{name}_rough.jpg"
    to_img(r_small).convert("L").save(os.path.join(out_dir, files["roughness"]), quality=85, optimize=True)
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--preview", help="also write a contact sheet into this folder")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    manifest = {"textures": {}, "micro": {}}
    for name, (albedo, height, rough, strength, tile, kind) in build().items():
        files = save_set(name, albedo, height, rough, strength, args.out)
        manifest["textures"][name] = {**files, "tile_m": tile, "kind": kind}
        if albedo.shape[0] != albedo.shape[1]:
            manifest["textures"][name]["tile_h_m"] = round(tile * albedo.shape[0] / albedo.shape[1], 4)
        print(f"{name:14s} {sum(os.path.getsize(os.path.join(args.out, f)) for f in files.values()) / 1024:7.0f} KB")

    peel, rough = micro(901)
    nrm = normal_from_height(peel, 0.7)
    to_img(nrm).save(os.path.join(args.out, "micro_normal.jpg"), quality=88, optimize=True)
    to_img(rough).convert("L").save(os.path.join(args.out, "micro_rough.jpg"), quality=85, optimize=True)
    manifest["micro"] = {"normal": "micro_normal.jpg", "roughness": "micro_rough.jpg", "tile_m": 0.3}

    with open(os.path.join(args.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    total = sum(os.path.getsize(os.path.join(args.out, f)) for f in os.listdir(args.out))
    print(f"total {total / 1024 / 1024:.2f} MB")

    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        names = list(manifest["textures"])
        cols = 5
        cell = 360
        rows = (len(names) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, rows * cell), "white")
        for i, name in enumerate(names):
            im = Image.open(os.path.join(args.out, manifest["textures"][name]["albedo"])).convert("RGB").resize((cell, cell), Image.LANCZOS)
            sheet.paste(im, ((i % cols) * cell, (i // cols) * cell))
        sheet.save(os.path.join(args.preview, "contact.png"))
        # 100% crops, to judge fine detail
        crop = 420
        sheet2 = Image.new("RGB", (cols * crop, rows * crop), "white")
        for i, name in enumerate(names):
            im = Image.open(os.path.join(args.out, manifest["textures"][name]["albedo"])).convert("RGB")
            w, h = im.size
            sheet2.paste(im.crop((w // 2 - crop // 2, h // 2 - crop // 2, w // 2 + crop // 2, h // 2 + crop // 2)), ((i % cols) * crop, (i // cols) * crop))
        sheet2.save(os.path.join(args.preview, "crops.png"))


if __name__ == "__main__":
    sys.exit(main())
