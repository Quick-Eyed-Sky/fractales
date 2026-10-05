#!/usr/bin/env python3
"""Draws the Fractales app icon from real fractal renders.

    python3 tools/make_icon.py            # writes icon/*.png and source/AppIcon.icns
    python3 tools/make_icon.py galaxie    # same, with another variant as the app icon

Needs numpy and Pillow (python3 -m pip install numpy pillow). The colouring is the
app's own: palette position = fract(sqrt(smooth count) * density + offset), with the
palettes of source/FractalModel.swift. The shape follows Apple's macOS icon grid:
a 824-pixel rounded square (superellipse) centred on a 1024 canvas, with a soft shadow.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 1024          # canvas
TILE = 824           # the rounded square inside it
SS = 2               # supersampling for the fractal and the edge

PALETTES = {  # same stops as source/FractalModel.swift
    "classique": [(0, 0, 7, 100), (0.16, 32, 107, 203), (0.42, 237, 255, 255),
                  (0.6425, 255, 170, 0), (0.8575, 0, 2, 0)],
    "feu": [(0, 10, 0, 0), (0.25, 140, 10, 0), (0.5, 255, 120, 0),
            (0.7, 255, 230, 90), (0.85, 255, 255, 230)],
    "aurore": [(0, 20, 0, 50), (0.25, 160, 20, 160), (0.5, 40, 220, 120),
               (0.75, 30, 200, 255), (0.9, 10, 20, 90)],
}

# name: centre, half-height, iterations, Julia constant or None, palette, density, offset, inside colour
VARIANTS = {
    # A close-up of the seahorse valley: one of the spirals the infinite voyage dives into.
    "spirale": dict(cx=-0.74505, cy=0.11271, half=0.00105, iters=3000, julia=None,
                    palette="classique", density=0.9, offset=0.55, inside=(0, 0, 0)),
    # The whole Mandelbrot set, glowing: recognisable even at 16 pixels.
    "galaxie": dict(cx=-0.6, cy=0.0, half=1.36, iters=400, julia=None,
                    palette="feu", density=0.32, offset=0.0, inside=(8, 4, 20)),
    # A Julia set full of spirals, in the Aurora palette.
    "julia": dict(cx=0.0, cy=0.0, half=1.05, iters=600, julia=(-0.7269, 0.1889),
                  palette="aurore", density=0.45, offset=0.1, inside=(6, 0, 24)),
}
DEFAULT = "spirale"


def palette_lut(stops, n=1024):
    s = sorted(stops)
    pos = np.array([p[0] for p in s] + [s[0][0] + 1.0])
    rgb = np.array([p[1:] for p in s] + [s[0][1:]], dtype=float)
    t = np.arange(n) / n
    t = np.where(t < pos[0], t + 1.0, t)
    return np.stack([np.interp(t, pos, rgb[:, c]) for c in range(3)], axis=1)


def smooth_counts(cx, cy, half, iters, julia, n):
    ys, xs = np.mgrid[0:n, 0:n]
    x = cx + (xs + 0.5 - n / 2) / (n / 2) * half
    y = cy - (ys + 0.5 - n / 2) / (n / 2) * half
    z = x + 1j * y
    c = complex(*julia) if julia else z.copy()
    if not julia:
        z = np.zeros_like(z)
    out = np.full(z.shape, -1.0)
    alive = np.ones(z.shape, bool)
    for i in range(iters):
        zi = z[alive]
        ci = c[alive] if not julia else c
        zi = zi * zi + ci
        z[alive] = zi
        esc = np.abs(zi) > 256.0
        if esc.any():
            idx = np.flatnonzero(alive)[esc]
            out.flat[idx] = i + 1 - np.log2(np.log(np.abs(zi[esc])))
            alive.flat[idx] = False
        if not alive.any():
            break
    return out


def render(v, n):
    counts = smooth_counts(v["cx"], v["cy"], v["half"], v["iters"], v["julia"], n)
    lut = palette_lut(PALETTES[v["palette"]])
    t = np.mod(np.sqrt(np.maximum(counts, 0)) * v["density"] + v["offset"], 1.0)
    img = lut[(t * len(lut)).astype(int) % len(lut)]
    img[counts < 0] = v["inside"]
    return img


def squircle_mask(n, radius=0.225):
    """Apple's rounded square: corners of 22.5 % of the side."""
    u = np.abs((np.arange(n) + 0.5) / n * 2 - 1)
    r = radius * 2
    dx = np.maximum(u[None, :] - (1 - r), 0)
    dy = np.maximum(u[:, None] - (1 - r), 0)
    return (dx * dx + dy * dy <= r * r).astype(float)


def make_icon(name):
    v = VARIANTS[name]
    n = TILE * SS
    rgb = render(v, n)
    # A gentle light from the top and a darker bottom give the tile some depth.
    shade = np.linspace(1.08, 0.86, n)[:, None, None]
    rgb = np.clip(rgb * shade, 0, 255)
    alpha = squircle_mask(n) * 255
    tile = Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")
    tile = tile.resize((TILE, TILE), Image.LANCZOS)

    # A thin light rim along the edge, as on Apple's own icons.
    inner = Image.fromarray((squircle_mask(n) * 255).astype(np.uint8)).resize((TILE, TILE), Image.LANCZOS)
    rim = np.array(inner, float) - np.array(inner.filter(ImageFilter.MinFilter(5)), float)
    t = np.array(tile, float)
    t[..., :3] = np.clip(t[..., :3] + rim[..., None] * 0.18, 0, 255)
    tile = Image.fromarray(t.astype(np.uint8), "RGBA")

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    off = (SIZE - TILE) // 2
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    a = Image.new("L", (SIZE, SIZE), 0)
    a.paste(tile.getchannel("A"), (off, off + 10))
    shadow.putalpha(a.point(lambda p: p * 0.45).filter(ImageFilter.GaussianBlur(14)))
    canvas = Image.alpha_composite(canvas, shadow)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer.paste(tile, (off, off))
    return Image.alpha_composite(canvas, layer)


def main():
    choice = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if choice not in VARIANTS:
        sys.exit(f"Variante inconnue : {choice}. Au choix : {', '.join(VARIANTS)}")
    os.makedirs(os.path.join(ROOT, "icon"), exist_ok=True)
    icons = {}
    for name in VARIANTS:
        print(f"Dessin de la variante « {name} »…")
        icons[name] = make_icon(name)
        icons[name].save(os.path.join(ROOT, "icon", f"{name}.png"))
    icns = os.path.join(ROOT, "source", "AppIcon.icns")
    icons[choice].save(icns, sizes=[(16, 16), (32, 32), (64, 64), (128, 128),
                                    (256, 256), (512, 512), (1024, 1024)])
    print(f"Icône de l'appli : {choice} → {icns}")


if __name__ == "__main__":
    main()
