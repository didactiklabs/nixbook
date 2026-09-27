#!/usr/bin/env python3
"""Generate the Persona-style panel textures (original artwork in the spirit
of the series' art direction — no Atlus assets). Output: <variant>-panel.svg.

Only plain shapes + linear/radial gradients are used (no <pattern>, <mask> or
filters) so Qt's SVG renderer draws them exactly; coordinates are rounded to
keep the files small. Textures are drawn *over* the frame's base color, so
they are mostly translucent. Each variant is drawn in three aspect ratios —
<variant>-panel.svg (3:2, popups), <variant>-tall.svg (1:2, sidebars) and
<variant>-wide.svg (4:1, OSD / search bar) — so PersonaTexture can use one
cached raster per shape instead of re-rendering per panel size.
Run: python3 generate.py
"""
import math
import random

W, H = 480, 320


def f(x):
    return f"{x:.1f}".rstrip("0").rstrip(".")


def svg(body, defs=""):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
        f'preserveAspectRatio="xMidYMid slice">'
        + (f"<defs>{defs}</defs>" if defs else "")
        + body
        + "</svg>\n"
    )


def rays(cx, cy, n, color, opacity, r=900, phase=0.0):
    out = []
    for i in range(n):
        a0 = phase + (2 * math.pi) * i / n
        a1 = a0 + math.pi / n
        p = [(cx, cy), (cx + r * math.cos(a0), cy + r * math.sin(a0)), (cx + r * math.cos(a1), cy + r * math.sin(a1))]
        out.append("M" + " L".join(f"{f(x)} {f(y)}" for x, y in p) + "Z")
    return f'<path d="{"".join(out)}" fill="{color}" opacity="{opacity}"/>'


def halftone(color, opacity, step, rmax, weight):
    """Dot grid whose radius follows weight(x, y) in [0, 1]."""
    out = []
    for gy in range(0, H + step, step):
        for gx in range(0, W + step, step):
            x = gx + (step / 2 if (gy // step) % 2 else 0)
            r = round(rmax * weight(x, gy) * 2) / 2  # half-pixel radii
            if r >= 0.5:
                out.append(f"M{round(x - r)} {gy}a{f(r)} {f(r)} 0 1 0 {f(2 * r)} 0a{f(r)} {f(r)} 0 1 0 {f(-2 * r)} 0")
    return f'<path d="{"".join(out)}" fill="{color}" opacity="{opacity}"/>'


def p5():
    body = rays(-40, H + 40, 22, "#e60012", 0.22, phase=-1.2)
    body += halftone("#ffffff", 0.10, 13, 4.2, lambda x, y: max(0.0, (x / W + (H - y) / H) / 2 - 0.35) * 1.6)
    # Sharp slashes: a white blade and a red one crossing the top-right.
    body += f'<path d="M{W * 0.62} -10 L{W + 10} -10 L{W + 10} {H * 0.22} L{W * 0.78} {H * 0.08}Z" fill="#ffffff" opacity="0.13"/>'
    body += f'<path d="M{W * 0.70} -10 L{W + 10} -10 L{W + 10} {H * 0.12}Z" fill="#e60012" opacity="0.55"/>'
    body += f'<path d="M-10 {H * 0.86} L{W * 0.34} {H * 0.74} L{W * 0.30} {H * 0.80} L-10 {H + 10}Z" fill="#ffffff" opacity="0.08"/>'
    return svg(body)


def p3r():
    defs = (
        '<linearGradient id="beam" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#3fd4ff" stop-opacity="0.35"/>'
        '<stop offset="1" stop-color="#3fd4ff" stop-opacity="0"/></linearGradient>'
        '<radialGradient id="glow" cx="0.85" cy="0.1" r="0.7">'
        '<stop offset="0" stop-color="#1450d8" stop-opacity="0.55"/>'
        '<stop offset="1" stop-color="#1450d8" stop-opacity="0"/></radialGradient>'
    )
    body = f'<rect width="{W}" height="{H}" fill="url(#glow)"/>'
    for i, (x, w) in enumerate([(W * 0.55, 34), (W * 0.68, 14), (W * 0.78, 52), (W * 0.93, 18)]):
        body += f'<path d="M{f(x)} -10 L{f(x + w)} -10 L{f(x + w - 150)} {H + 10} L{f(x - 150)} {H + 10}Z" fill="url(#beam)" opacity="{0.8 - i * 0.12:.2f}"/>'
    random.seed(3)
    bubbles = []
    for _ in range(26):
        x, y, r = random.uniform(0, W), random.uniform(H * 0.35, H), random.uniform(2, 9)
        bubbles.append(f"M{f(x - r)} {f(y)}a{f(r)} {f(r)} 0 1 0 {f(2 * r)} 0a{f(r)} {f(r)} 0 1 0 {f(-2 * r)} 0")
    body += f'<path d="{"".join(bubbles)}" fill="none" stroke="#9fe8ff" stroke-width="1.2" opacity="0.28"/>'
    for k in range(3):
        y0 = H * (0.62 + k * 0.1)
        d = f"M-10 {f(y0)}" + "".join(
            f" Q{f(x + 30)} {f(y0 + (10 if (x // 60) % 2 else -10))} {f(x + 60)} {f(y0)}" for x in range(-10, W + 60, 60)
        )
        body += f'<path d="{d}" fill="none" stroke="#3fd4ff" stroke-width="1.5" opacity="{0.22 - k * 0.05:.2f}"/>'
    return svg(body, defs)


def p4():
    defs = (
        '<radialGradient id="tq" cx="0.1" cy="0.95" r="0.8">'
        '<stop offset="0" stop-color="#1fd6c8" stop-opacity="0.35"/>'
        '<stop offset="1" stop-color="#1fd6c8" stop-opacity="0"/></radialGradient>'
    )
    body = f'<rect width="{W}" height="{H}" fill="url(#tq)"/>'
    # Yellow TV-style diagonal band across the top-right.
    stripes = []
    for i in range(9):
        x = W * 0.48 + i * 34
        stripes.append(f"M{f(x)} -10 L{f(x + 17)} -10 L{f(x - 63)} {f(H * 0.3)} L{f(x - 80)} {f(H * 0.3)}Z")
    body += f'<path d="{"".join(stripes)}" fill="#ffe11a" opacity="0.30"/>'
    body += f'<path d="M{W * 0.40} {H * 0.3} L{W + 10} {H * 0.3} L{W + 10} {H * 0.3 + 3} L{W * 0.40 - 1} {H * 0.3 + 3}Z" fill="#ffe11a" opacity="0.6"/>'
    # Scanlines
    lines = "".join(f"M0 {y}h{W}" for y in range(0, H, 4))
    body += f'<path d="{lines}" stroke="#ffffff" stroke-width="1" opacity="0.035"/>'
    body += halftone("#ffe11a", 0.12, 14, 4.0, lambda x, y: max(0.0, (y / H + (W - x) / W) / 2 - 0.45) * 1.8)
    return svg(body, defs)


SHAPES = {"panel": (480, 320), "tall": (320, 640), "wide": (640, 160)}

for shape, (W, H) in SHAPES.items():
    for name, fn in [("p5", p5), ("p3r", p3r), ("p4", p4)]:
        with open(f"{name}-{shape}.svg", "w") as fh:
            fh.write(fn())
