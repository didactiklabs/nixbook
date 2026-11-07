#!/usr/bin/env python3
"""Draw the Cyberpunk 2077 theme's wallpapers (<variant>-wallpaper.svg,
1920x1080) from the variants' palettes in modules/common/themes.json, after
the game's UI art (Anna Kuźmińska's "Cyberpunk 2077 – UI Art and UI Art
Concepts"): its presentation pages, HUD and in-world screens. No text (the
package rasterises them with resvg, without fonts: generated-assets.nix):
numbers are drawn as thin strokes, "text" as rows of dashes.

  yellow  the presentation page: a lemon yellow field between black bands
          with notched edges, olive outlined data boxes, a hot red section
          header fed by a line bending at 45°, cyan chapter tabs, the city
          faint behind
  red     the HUD / ripperdoc screen: a brain-scan panel in HUD red with an
          RGB split, MRI slices, health bars on a teal rail, rulers, a
          crosshair grid, data columns
  cyan    the environment screens: a wall of terminal panels in cyan line
          art — radar, wireframe box, waveform, dot matrix, gauges, data

Seeded: rerunning gives the same pictures. Run after changing the palettes:
  python3 generate.py
"""
import json
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1920, 1080


def palettes():
    with open(os.path.join(HERE, "../../modules/common/themes.json"), encoding="utf-8") as f:
        registry = json.load(f)
    theme = next(t for t in registry["themes"] if t["id"] == "cyberpunk")
    return {v["id"]: v["palette"] for v in theme["variants"]}


# ------------------------------------------------------------------ helpers
def f(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


def rect(x, y, w, h, fill, opacity=1.0, extra=""):
    return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" fill="{fill}" opacity="{opacity:.2f}"{extra}/>'


def line(x1, y1, x2, y2, stroke, width=1.0, opacity=1.0, extra=""):
    return (f'<line x1="{f(x1)}" y1="{f(y1)}" x2="{f(x2)}" y2="{f(y2)}" stroke="{stroke}" '
            f'stroke-width="{width}" opacity="{opacity:.2f}"{extra}/>')


def poly(points, fill="none", stroke="none", width=1.0, opacity=1.0, closed=True):
    pts = " ".join(f"{f(x)},{f(y)}" for x, y in points)
    tag = "polygon" if closed else "polyline"
    return (f'<{tag} points="{pts}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" '
            f'stroke-linejoin="miter" opacity="{opacity:.2f}"/>')


def circle(cx, cy, r, stroke="none", width=1.0, fill="none", opacity=1.0, extra=""):
    return (f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" fill="{fill}" stroke="{stroke}" '
            f'stroke-width="{width}" opacity="{opacity:.2f}"{extra}/>')


def chamfer(x, y, w, h, c, corners="tl br"):
    """Corner points of a box with the given corners cut by c."""
    tl, tr, br, bl = ("tl" in corners), ("tr" in corners), ("br" in corners), ("bl" in corners)
    pts = []
    pts += [(x, y + c), (x + c, y)] if tl else [(x, y)]
    pts += [(x + w - c, y), (x + w, y + c)] if tr else [(x + w, y)]
    pts += [(x + w, y + h - c), (x + w - c, y + h)] if br else [(x + w, y + h)]
    pts += [(x + c, y + h), (x, y + h - c)] if bl else [(x, y + h)]
    return pts


def panel(x, y, w, h, stroke, c=12, width=1.0, opacity=1.0, fill="none", corners="tl br"):
    return poly(chamfer(x, y, w, h, c, corners), fill=fill, stroke=stroke, width=width, opacity=opacity)


# Thin-stroke numerals (the game's light numbers: "4 505 3", "032 43 24"),
# on a unit box 0..1 x 0..1 (width is 0.56 of the height).
DIGITS = {
    "0": [[(0, 0.1), (0.1, 0), (1, 0), (1, 0.9), (0.9, 1), (0, 1), (0, 0.1)]],
    "1": [[(0.35, 0.15), (0.6, 0), (0.6, 1)]],
    "2": [[(0, 0.1), (0.1, 0), (1, 0), (1, 0.48), (0, 0.6), (0, 1), (1, 1)]],
    "3": [[(0, 0), (1, 0), (1, 1), (0, 1)], [(0.25, 0.5), (1, 0.5)]],
    "4": [[(0.75, 1), (0.75, 0), (0, 0.68), (1, 0.68)]],
    "5": [[(1, 0), (0, 0), (0, 0.45), (0.9, 0.45), (1, 0.55), (1, 1), (0, 1)]],
    "6": [[(1, 0), (0.1, 0), (0, 0.1), (0, 1), (1, 1), (1, 0.5), (0, 0.5)]],
    "7": [[(0, 0), (1, 0), (1, 0.12), (0.35, 1)]],
    "8": [[(0, 0), (1, 0), (1, 1), (0, 1), (0, 0)], [(0, 0.48), (1, 0.48)]],
    "9": [[(1, 0.5), (0, 0.5), (0, 0), (1, 0), (1, 0.9), (0.9, 1), (0, 1)]],
}


def numerals(text, x, y, h, stroke, width=1.5, opacity=1.0, gap=0.42):
    w = h * 0.56
    out = []
    cx = x
    for ch in text:
        if ch in DIGITS:
            for path in DIGITS[ch]:
                out.append(poly([(cx + px * w, y + py * h) for px, py in path], stroke=stroke, width=width,
                                opacity=opacity, closed=False))
            cx += w + h * gap
        else:
            cx += w * 0.9
    return "\n".join(out)


def fake_text(rnd, x, y, w, rows, colour, size=4.0, gap=7.0, opacity=0.8, ragged=True):
    """Rows of dashes standing for small caps text."""
    out = []
    for r in range(rows):
        cx = x
        end = x + (w * (0.45 + rnd.random() * 0.55) if ragged else w)
        while cx < end:
            word = rnd.randint(3, 11) * size * 0.9
            word = min(word, end - cx)
            if word > 2:
                out.append(rect(cx, y + r * gap, word, size * 0.55, colour, opacity))
            cx += word + size * 1.1
    return "\n".join(out)


def tag(rnd, x, y, colour, w=None, fill="none"):
    """A section tag: a chamfered outline (top right cut) around a short label."""
    w = w or rnd.randint(70, 120)
    out = [poly(chamfer(x, y, w, 22, 7, "tr"), fill=fill, stroke=colour, width=1.2, opacity=0.9)]
    out.append(fake_text(rnd, x + 9, y + 7, w - 26, 2, colour, size=3.6, gap=5.5, opacity=0.95, ragged=False))
    out.append(fake_text(rnd, x, y + 26, w * 0.8, 1, colour, size=2.6, gap=4, opacity=0.5))
    return "\n".join(out)


def barcode(rnd, x, y, h, colour, n=24, opacity=0.85):
    out = []
    for _ in range(n):
        w = rnd.choice([1, 1, 2, 3])
        out.append(rect(x, y, w, h, colour, opacity))
        x += w + rnd.choice([1, 2, 2, 3])
    return "\n".join(out)


def ruler(x, y, length, colour, vertical=True, step=8, opacity=0.6, flip=False):
    out = []
    for k in range(int(length // step) + 1):
        long = k % 5 == 0
        n = 9 if long else 4
        d = -n if flip else n
        if vertical:
            out.append(line(x, y + k * step, x + d, y + k * step, colour, 1, opacity))
        else:
            out.append(line(x + k * step, y, x + k * step, y + d, colour, 1, opacity))
    return "\n".join(out)


def brackets(x, y, w, h, colour, size=18, width=2.0, opacity=0.9):
    out = []
    for (cx, cy, sx, sy) in [(x, y, 1, 1), (x + w, y, -1, 1), (x, y + h, 1, -1), (x + w, y + h, -1, -1)]:
        out.append(poly([(cx, cy + size * sy), (cx, cy), (cx + size * sx, cy)], stroke=colour, width=width,
                        opacity=opacity, closed=False))
    return "\n".join(out)


def notched_band(y0, y1, colour, rnd, edge_down, teeth=9):
    """A black band whose inner edge carries notches and little triangles,
    the jagged edge of the presentation's pages."""
    out = [rect(0, y0, W, y1 - y0, colour)]
    edge = y1 if edge_down else y0
    s = 1 if edge_down else -1
    x = rnd.randint(20, 120)
    for _ in range(teeth):
        w = rnd.randint(40, 140)
        d = rnd.choice([6, 8, 12, 16])
        out.append(poly([(x, edge), (x + w, edge), (x + w - d, edge + d * s), (x + d, edge + d * s)], fill=colour))
        x += w + rnd.randint(90, 260)
        if x > W:
            break
    for _ in range(6):
        tx = rnd.randint(40, W - 40)
        out.append(poly([(tx - 5, edge), (tx + 5, edge), (tx, edge + 7 * s)], fill=colour))
    return "\n".join(out)


def grain(opacity, seed):
    return (f'<filter id="grain{seed}" x="0" y="0" width="100%" height="100%">'
            f'<feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="{seed}"/>'
            f'<feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1.6 -0.75"/></filter>'
            f'<rect width="{W}" height="{H}" filter="url(#grain{seed})" opacity="{opacity:.2f}"/>')


def svg_open():
    return [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">']


# ------------------------------------------------------------------- yellow
def yellow(p):
    rnd = random.Random(2077)
    ink = p["background"]
    olive = p["outline"]
    red = p["tertiary"]
    cyan = p["secondary"]
    out = svg_open()
    out.append(rect(0, 0, W, H, p["primary"]))
    # Faint vertical streaks in the yellow.
    for _ in range(70):
        x = rnd.randint(0, W)
        out.append(rect(x, 0, rnd.choice([1, 2, 3, 6, 12]), H, rnd.choice(["#ffffff", "#c8c000"]), 0.05 + rnd.random() * 0.07))
    # The city, faint: a paler skyline above the bottom band.
    x = -10
    while x < W:
        bw = rnd.randint(40, 120)
        bh = rnd.randint(60, 300)
        out.append(rect(x, 980 - bh, bw, bh, "#fffb7a", 0.35))
        x += bw + rnd.randint(-8, 10)
    # Two long diagonals (darker yellow).
    out.append(line(560, 0, 1640, 1080, "#b8b200", 1.2, 0.55))
    out.append(line(1080, 0, 1920, 840, "#b8b200", 1.2, 0.4))

    # Olive outlined data boxes, top left: slashed boxes and a number box.
    bx, by = 70, 150
    for r in range(3):
        for c in range(2):
            x0, y0 = bx + c * 132, by + r * 56
            out.append(rect(x0, y0, 118, 40, "none", 1, f' stroke="{olive}" stroke-width="1.2"'))
            if (r + c) % 2 == 0:
                out.append(line(x0, y0 + 40, x0 + 118, y0, olive, 1.2))
            else:
                out.append(fake_text(rnd, x0 + 12, y0 + 17, 70, 1, olive, size=7, opacity=0.9, ragged=False))
    out.append(rect(bx, by + 178, 300, 64, "none", 1, f' stroke="{olive}" stroke-width="1.2"'))
    out.append(rect(bx + 14, by + 196, 18, 18, "none", 1, f' stroke="{olive}" stroke-width="1.2"'))
    out.append(numerals("4 505 3", bx + 50, by + 192, 36, olive, 1.6))
    # Outline triangles.
    for k in range(3):
        tx = 76 + k * 64
        out.append(poly([(tx, 520), (tx + 40, 541), (tx, 562)], stroke=ink, width=1.2, opacity=0.6))

    # The section header: a line from the left bending at 45° into a hot
    # red tab with a chamfered corner.
    hy, hx, hw, hh = 470, 1010, 910, 92
    out.append(poly([(0, hy + hh + 66), (hx - 64, hy + hh + 66), (hx, hy + hh + 2)], stroke=red, width=3, closed=False))
    out.append(poly(chamfer(hx, hy, hw + 20, hh, 18, "tl"), fill=red))
    out.append(numerals("2077", hx + 46, hy + 26, 40, "#ffffff", 4.5))
    out.append(fake_text(rnd, hx + 250, hy + 40, 420, 1, "#ffffff", size=14, opacity=0.95, ragged=False))
    # Body copy under it (dark dashes) and a photo-like block with a cut corner.
    out.append(fake_text(rnd, 1240, 640, 560, 4, ink, size=8, gap=26, opacity=0.8))
    out.append(poly(chamfer(1490, 200, 300, 220, 34, "tl br"), fill=ink, opacity=0.9))
    out.append(poly(chamfer(1500, 210, 280, 200, 28, "tl br"), stroke=p["primary"], width=1, opacity=0.4))
    for k in range(5):
        out.append(rect(1510, 236 + k * 32, 120 + rnd.randint(0, 140), 3, cyan, 0.6))
    # Faint outlined boxes down the right (the pages' right column).
    for k in range(6):
        out.append(rect(1680, 600 + k * 52, 170, 38, "none", 1, f' stroke="#d8d000" stroke-width="1.2"'))
        if k % 2:
            out.append(line(1680, 638 + k * 52, 1850, 600 + k * 52, "#d8d000", 1.2))

    # Chapter tabs: cyan blocks with a notch on top, one active in black.
    tx = 90
    for k in range(4):
        tw = 230
        fill = ink if k == 0 else cyan
        pts = [(tx, 872), (tx + tw - 26, 872), (tx + tw - 18, 864), (tx + tw, 864), (tx + tw, 930), (tx, 930)]
        out.append(poly(pts, fill=fill))
        out.append(fake_text(rnd, tx + 22, 895, 110, 1, p["primary"] if k == 0 else ink, size=10, opacity=0.95, ragged=False))
        tx += tw + 14
    out.append(fake_text(rnd, 90, 942, 260, 1, cyan, size=4, opacity=0.9))

    # Black bands with notched inner edges, top and bottom.
    out.append(notched_band(0, 40, ink, rnd, True))
    out.append(notched_band(1012, H, ink, rnd, False, teeth=7))
    out.append(barcode(rnd, 1480, 1040, 16, p["primary"], 30, 0.8))
    for k in range(3):
        out.append(rect(60 + k * 14, 1044, 6, 6, [cyan, p["primary"], red][k]))
    out.append(fake_text(rnd, 1720, 1046, 160, 1, p["primary"], size=4, opacity=0.8))

    out.append(grain(0.10, 7))
    out.append("</svg>")
    return "\n".join(out)


# ---------------------------------------------------------------------- red
def contour_blob(rnd, cx, cy, rx, ry, rings, stroke, width, opacity, wobble=0.08, seed=0):
    """Concentric noisy rings: a scan slice."""
    r2 = random.Random(seed)
    phases = [r2.random() * 6.28 for _ in range(4)]
    out = []
    for k in range(rings):
        s = 1 - k / rings
        pts = []
        for i in range(73):
            a = i / 72 * 2 * math.pi
            n = 1 + wobble * (math.sin(3 * a + phases[0] + k * 0.7) * 0.6 + math.sin(7 * a + phases[1] - k) * 0.4
                              + math.sin(13 * a + phases[2] + k * 1.3) * 0.25)
            pts.append((cx + math.cos(a) * rx * s * n, cy + math.sin(a) * ry * s * n))
        out.append(poly(pts, stroke=stroke, width=width, opacity=opacity * (0.55 + 0.45 * s)))
    return "\n".join(out)


def red(p):
    rnd = random.Random(1337)
    red_ = p["primary"]
    dark = p["primaryContainer"]
    teal = p["rail"]
    yellow_ = p["tertiary"]
    out = svg_open()
    out.append(rect(0, 0, W, H, p["background"]))
    # Faint grid.
    for x in range(0, W, 48):
        out.append(line(x, 0, x, H, red_, 1, 0.035))
    for y in range(0, H, 48):
        out.append(line(0, y, W, y, red_, 1, 0.035))

    # The scan panel, centre right.
    px, py, pw, ph = 760, 90, 860, 880
    out.append(panel(px, py, pw, ph, red_, c=26, width=1.2, opacity=0.7, fill=p["surface1"]))
    out.append(rect(px + 30, py + 34, 34, 44, dark))
    out.append(numerals("1", px + 38, py + 42, 28, red_, 2))
    out.append(fake_text(rnd, px + 90, py + 42, 300, 1, red_, size=9, opacity=0.9, ragged=False))
    out.append(numerals("032 43 24 1121 22", px + 420, py + 36, 26, red_, 1.3, 0.7))
    out.append(ruler(px + 40, py + 120, 640, red_, opacity=0.55))
    out.append(ruler(px + pw - 40, py + 120, 640, red_, opacity=0.55, flip=True))
    for k in range(9):
        y = py + 140 + k * 72
        out.append(line(px + 60, y, px + pw - 60, y, red_, 1, 0.12, ' stroke-dasharray="2 6"'))
    # The scan itself: an RGB-split stack of contour rings.
    cx, cy = px + pw * 0.52, py + 400
    out.append(contour_blob(rnd, cx - 9, cy + 3, 250, 290, 16, "#3a6bff", 1.4, 0.45, seed=5))
    out.append(contour_blob(rnd, cx + 8, cy - 2, 250, 290, 16, p["glitch"], 1.4, 0.45, seed=5))
    out.append(contour_blob(rnd, cx, cy, 250, 290, 16, red_, 1.8, 0.95, seed=5))
    out.append(circle(cx, cy, 330, red_, 1, opacity=0.25, extra=' stroke-dasharray="3 9"'))
    # Slices of RGB tear across the scan.
    for _ in range(9):
        y = cy + rnd.randint(-300, 300)
        out.append(rect(cx - rnd.randint(120, 320), y, rnd.randint(140, 520), rnd.choice([2, 3, 6]),
                        rnd.choice([p["glitch"], red_, "#3a6bff"]), 0.25 + rnd.random() * 0.3))
    # Bottom of the panel: a crosshair box, a grid with circles, a data block.
    bx, by = px + 40, py + ph - 200
    out.append(rect(bx, by, 150, 150, "none", 0.8, f' stroke="{red_}" stroke-width="1.2"'))
    out.append(line(bx, by, bx + 150, by + 150, red_, 1, 0.8))
    out.append(line(bx + 150, by, bx, by + 150, red_, 1, 0.8))
    out.append(circle(bx + 75, by + 75, 26, red_, 1.5))
    for (dx, dy) in [(-46, 0), (46, 0), (0, -46), (0, 46)]:
        out.append(circle(bx + 75 + dx, by + 75 + dy, 10, red_, 1.2, opacity=0.8))
    gx = bx + 180
    out.append(rect(gx, by, 300, 150, "none", 0.6, f' stroke="{red_}" stroke-width="1"'))
    for k in range(1, 6):
        out.append(line(gx + k * 50, by, gx + k * 50, by + 150, red_, 1, 0.25))
    for k in range(1, 3):
        out.append(line(gx, by + k * 50, gx + 300, by + k * 50, red_, 1, 0.25))
    for (i, j) in [(3, 0), (2, 1), (3, 1), (4, 1), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2)]:
        out.append(circle(gx + i * 50, by + 25 + j * 50, 9, red_, 1.4))
    out.append(poly(chamfer(px + pw - 230, by + 10, 190, 140, 14, "tr"), fill=dark, opacity=0.9))
    out.append(fake_text(rnd, px + pw - 215, by + 34, 150, 9, red_, size=5, gap=11, opacity=0.9))
    out.append(barcode(rnd, px + 520, py + ph - 48, 18, red_, 26))

    # MRI slices, top left.
    out.append(tag(rnd, 70, 70, teal))
    for i in range(3):
        for j in range(2):
            out.append(contour_blob(rnd, 120 + i * 110, 170 + j * 120, 38, 46, 6, red_, 1.2, 0.9, 0.12, seed=i * 3 + j))
    # Health bars on the teal rail.
    out.append(tag(rnd, 70, 430, teal, 130))
    for k, hp in enumerate([1.0, 0.62, 0.18]):
        y = 500 + k * 90
        out.append(circle(92, y + 20, 15, red_, 2))
        out.append(fake_text(rnd, 70, y - 14, 40, 3, red_, size=3, gap=5, opacity=0.7))
        out.append(poly(chamfer(124, y, 44, 44, 9, "bl"), stroke=teal, width=1.6))
        out.append(numerals(str(17 + k * 9), 132, y + 12, 20, teal, 1.6))
        out.append(fake_text(rnd, 180, y - 10, 90, 1, red_, size=6, opacity=0.9, ragged=False))
        out.append(rect(180, y + 2, 440, 3, teal))
        out.append(rect(180, y + 12, 440 * hp, 18, red_))
        if hp < 1:
            out.append(rect(180 + 440 * hp, y + 12, 440 * (1 - hp), 18, dark))
            for hx in range(int(180 + 440 * hp) + 4, int(180 + 440 * hp + min(90, 440 * (1 - hp))), 7):
                out.append(line(hx, y + 30, hx + 8, y + 12, red_, 1.2, 0.7))
        out.append(numerals("100", 640, y + 10, 20, red_, 2.4))
    # Map pins / buff icons, bottom left: a row of small glyphs.
    for k in range(6):
        gx2, gy2 = 90 + k * 80, 840
        shape = k % 3
        if shape == 0:
            out.append(poly([(gx2, gy2 + 26), (gx2 + 14, gy2), (gx2 + 28, gy2 + 26)], stroke=red_, width=2))
        elif shape == 1:
            out.append(poly([(gx2 + 14, gy2), (gx2 + 28, gy2 + 14), (gx2 + 14, gy2 + 28), (gx2, gy2 + 14)], stroke=red_, width=2))
            out.append(circle(gx2 + 14, gy2 + 14, 4, fill=red_))
        else:
            out.append(circle(gx2 + 14, gy2 + 14, 13, red_, 2))
            out.append(line(gx2 + 5, gy2 + 5, gx2 + 23, gy2 + 23, red_, 2))
    out.append(fake_text(rnd, 70, 900, 420, 4, red_, size=5, gap=12, opacity=0.6))
    # Quest marker in yellow.
    out.append(rect(70, 980, 12, 12, yellow_))
    out.append(fake_text(rnd, 92, 982, 200, 1, yellow_, size=7, opacity=0.95, ragged=False))
    # Data columns on the right edge.
    for c in range(2):
        out.append(fake_text(rnd, 1660 + c * 120, 120, 100, 60, red_, size=3.4, gap=9, opacity=0.4))
    out.append(ruler(1900, 120, 820, red_, opacity=0.5, flip=True))
    out.append(brackets(30, 30, W - 60, H - 60, red_, 26, 2, 0.8))

    # Scanlines and grain.
    out.append('<pattern id="scan" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="4" height="1" fill="#000" opacity="0.35"/></pattern>')
    out.append(rect(0, 0, W, H, "url(#scan)"))
    out.append(grain(0.08, 11))
    out.append("</svg>")
    return "\n".join(out)


# --------------------------------------------------------------------- cyan
def cyan(p):
    rnd = random.Random(404)
    c_ = p["primary"]
    deep = p["primaryContainer"]
    red_ = p["secondary"]
    out = svg_open()
    out.append(f'<defs><radialGradient id="vig" cx="0.5" cy="0.45" r="0.75"><stop offset="0" stop-color="{p["surface2"]}"/>'
               f'<stop offset="1" stop-color="{p["background"]}"/></radialGradient></defs>')
    out.append(rect(0, 0, W, H, "url(#vig)"))
    # Dotted grid.
    out.append(f'<pattern id="dots" width="24" height="24" patternUnits="userSpaceOnUse"><rect width="1.5" height="1.5" fill="{c_}" opacity="0.18"/></pattern>')
    out.append(rect(0, 0, W, H, "url(#dots)"))

    out.append(tag(rnd, 80, 64, c_, 150))

    def frame(x, y, w, h, cut=10):
        return panel(x, y, w, h, c_, c=cut, width=1.1, opacity=0.75)

    # Radar, top left.
    rx, ry, rr = 260, 330, 140
    for k, r in enumerate([rr, rr * 0.72, rr * 0.44, rr * 0.16]):
        out.append(circle(rx, ry, r, c_, 1.3 if k == 0 else 1, opacity=0.9 if k == 0 else 0.55))
    for i in range(72):
        a = i / 72 * 2 * math.pi
        l = 12 if i % 6 == 0 else 5
        out.append(line(rx + math.cos(a) * rr, ry + math.sin(a) * rr, rx + math.cos(a) * (rr + l), ry + math.sin(a) * (rr + l), c_, 1, 0.8))
    out.append(line(rx - rr, ry, rx + rr, ry, c_, 1, 0.4))
    out.append(line(rx, ry - rr, rx, ry + rr, c_, 1, 0.4))
    out.append(f'<path d="M{rx},{ry} L{f(rx + rr)},{ry} A{rr},{rr} 0 0,0 {f(rx + rr * math.cos(-0.7))},{f(ry + rr * math.sin(-0.7))} Z" fill="{c_}" opacity="0.18"/>')
    for _ in range(5):
        a, d = rnd.random() * 6.28, rnd.random() * rr * 0.9
        out.append(rect(rx + math.cos(a) * d - 3, ry + math.sin(a) * d - 3, 6, 6, c_ if rnd.random() < 0.7 else red_))
    out.append(poly(chamfer(rx - 70, ry + rr + 40, 140, 70, 10, "bl br"), stroke=c_, width=1.2, opacity=0.8))
    out.append(numerals("002", rx - 40, ry + rr + 52, 26, c_, 2))
    out.append(fake_text(rnd, rx - 50, ry + rr + 88, 100, 1, c_, size=4, opacity=0.8, ragged=False))

    # Wireframe box, top centre.
    out.append(frame(560, 150, 420, 300))
    out.append(fake_text(rnd, 580, 166, 200, 1, c_, size=5, opacity=0.8, ragged=False))
    bx, by = 770, 310
    for k, s in enumerate([1.0, 0.82, 0.64]):
        out.append(poly([(bx, by - 90 * s), (bx + 150 * s, by), (bx, by + 90 * s), (bx - 150 * s, by)], stroke=c_, width=1.2, opacity=0.9 - k * 0.2))
    for s in [1.0, 0.64]:
        out.append(line(bx - 150 * s, by, bx - 150 * s, by + 40, c_, 1, 0.5))
        out.append(line(bx + 150 * s, by, bx + 150 * s, by + 40, c_, 1, 0.5))
    out.append(poly([(bx - 150, by + 40), (bx, by + 130), (bx + 150, by + 40)], stroke=c_, width=1, opacity=0.5, closed=False))
    out.append(line(bx, by - 90, bx, by + 130, c_, 1, 0.3, ' stroke-dasharray="3 5"'))

    # Data panel with a highlighted chip, top right.
    out.append(frame(1020, 150, 300, 300))
    out.append(fake_text(rnd, 1040, 172, 260, 22, c_, size=3.6, gap=11, opacity=0.65))
    out.append(rect(1180, 400, 120, 24, c_))
    out.append(fake_text(rnd, 1192, 409, 90, 1, p["background"], size=5, opacity=1, ragged=False))
    # Tall column of text, far right.
    out.append(frame(1360, 120, 210, 520, 8))
    out.append(fake_text(rnd, 1378, 140, 180, 44, c_, size=3.2, gap=11, opacity=0.55))
    out.append(rect(1580, 120, 4, 520, deep))
    out.append(rect(1580, 160, 4, 120, c_))

    # Dot matrix and lightning, middle.
    out.append(frame(560, 500, 260, 220))
    for i in range(6):
        for j in range(5):
            on = rnd.random() < 0.55
            out.append(rect(590 + i * 34, 530 + j * 34, 22, 22, c_ if on else "none", 0.9 if on else 0.5,
                            "" if on else f' stroke="{c_}" stroke-width="1"'))
    out.append(frame(850, 500, 140, 220))
    out.append(poly([(930, 540), (890, 615), (918, 615), (902, 690), (955, 595), (925, 595), (945, 540)], fill=c_, opacity=0.9))
    # Gauges (two circles with arcs), middle right.
    out.append(frame(1020, 500, 300, 220))
    for k in range(2):
        gx, gy = 1100 + k * 140, 590
        out.append(circle(gx, gy, 40, c_, 1, opacity=0.5))
        end = 0.3 + 0.55 * (k + 1) / 2
        a1 = -math.pi / 2 + end * 2 * math.pi
        large = 1 if end > 0.5 else 0
        out.append(f'<path d="M{gx},{gy - 40} A40,40 0 {large},1 {f(gx + 40 * math.cos(a1))},{f(gy + 40 * math.sin(a1))}" fill="none" stroke="{c_}" stroke-width="4"/>')
        out.append(circle(gx, gy, 8, fill=c_))
    out.append(fake_text(rnd, 1040, 670, 260, 2, c_, size=4, gap=12, opacity=0.7))

    # Waveform, wide along the bottom.
    wx, wy, ww, wh = 560, 760, 1010, 210
    out.append(frame(wx, wy, ww, wh, 12))
    for k in range(1, 4):
        out.append(line(wx + 20, wy + k * wh / 4, wx + ww - 20, wy + k * wh / 4, c_, 1, 0.15))
    for seed, op, col in [(1, 0.95, c_), (2, 0.45, c_), (3, 0.6, red_)]:
        r2 = random.Random(seed)
        pts = []
        for i in range(70):
            x = wx + 30 + i * (ww - 60) / 69
            amp = (0.15 + 0.85 * abs(math.sin(i / 9 + seed))) * (wh / 2 - 26)
            pts.append((x, wy + wh / 2 + (r2.random() * 2 - 1) * amp))
        out.append(poly(pts, stroke=col, width=1.4, opacity=op, closed=False))
    out.append(rect(wx + ww - 140, wy + wh - 30, 110, 16, c_))
    out.append(ruler(wx + 30, wy + wh - 8, ww - 60, c_, vertical=False, step=10, opacity=0.5, flip=True))

    # Left column: data tables.
    for k in range(3):
        y = 610 + k * 130
        out.append(frame(80, y, 400, 110, 8))
        out.append(rect(96, y + 16, 60, 78, deep))
        out.append(fake_text(rnd, 104, y + 24, 44, 6, c_, size=3, gap=11, opacity=0.9, ragged=False))
        out.append(fake_text(rnd, 172, y + 20, 290, 7, c_, size=3.4, gap=11, opacity=0.6))
    # The red warning chip and a barcode.
    out.append(poly(chamfer(1610, 820, 220, 60, 10, "tl"), fill=red_, opacity=0.9))
    out.append(fake_text(rnd, 1630, 846, 160, 1, p["background"], size=8, opacity=1, ragged=False))
    out.append(barcode(rnd, 1610, 900, 30, c_, 34))
    out.append(fake_text(rnd, 1610, 950, 220, 2, c_, size=4, gap=10, opacity=0.6))
    out.append(brackets(40, 40, W - 80, H - 80, c_, 22, 1.6, 0.7))

    out.append('<pattern id="scan" width="3" height="3" patternUnits="userSpaceOnUse"><rect width="3" height="1" fill="#000" opacity="0.3"/></pattern>')
    out.append(rect(0, 0, W, H, "url(#scan)"))
    out.append(grain(0.06, 3))
    out.append("</svg>")
    return "\n".join(out)


DRAW = {"yellow": yellow, "red": red, "cyan": cyan}


def main():
    for vid, p in palettes().items():
        with open(os.path.join(HERE, f"{vid}-wallpaper.svg"), "w", encoding="utf-8") as fh:
            fh.write(DRAW[vid](p) + "\n")


if __name__ == "__main__":
    main()
