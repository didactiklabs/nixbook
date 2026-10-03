#!/usr/bin/env python3
"""Generate the Chiikawa theme's art for each variant: a scattered pattern of
tiny stars, hearts and dots for the sidebars' background (<variant>-tall.svg)
and its default wallpaper (<variant>-wallpaper.svg, themes.json `wallpaper`),
with the three friends (friends.gif: Momonga, momonga.gif as is, with
Chiikawa and Usagi beside him, made by friends.py) standing on a hill.

Colours come from each variant's palette in modules/common/themes.json
(accent, stripe, blush, line, surfaces), so the art follows the theme's single
definition. qml.nix rasterises the SVGs to PNG with resvg, which reads the
GIF's first frame next to the SVG.
Run: python3 generate.py
"""
import json
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
THEMES = os.path.join(HERE, "..", "..", "modules", "common", "themes.json")
LINE = 5  # default outline width


def f(x):
    return f"{x:.1f}".rstrip("0").rstrip(".")


def ellipse(cx, cy, rx, ry, fill, stroke=None, rot=0, opacity=None, width=LINE):
    attrs = f'cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}" fill="{fill}"'
    if stroke:
        attrs += f' stroke="{stroke}" stroke-width="{width}"'
    if rot:
        attrs += f' transform="rotate({f(rot)} {f(cx)} {f(cy)})"'
    if opacity is not None:
        attrs += f' opacity="{opacity}"'
    return f"<ellipse {attrs}/>"


def path(d, fill="none", stroke=None, width=LINE, opacity=None):
    attrs = f'd="{d}" fill="{fill}"'
    if stroke:
        attrs += f' stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"'
    if opacity is not None:
        attrs += f' opacity="{opacity}"'
    return f"<path {attrs}/>"


def svg(w, h, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">'
        + "".join(body)
        + "</svg>\n"
    )


# -------------------------------------------------------------- character
# The characters: Momonga's animated GIF (momonga.gif) with his two friends
# beside him (friends.gif, friends.py), used by ChiikawaMascot for every
# variant; the wallpapers show its first frame.
CHARACTER = "friends.gif"
CHARACTER_SIZE = (460, 177)


# ---------------------------------------------------------------- pattern
def star(cx, cy, r, color, opacity):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append(f"{f(cx + rr * math.cos(a))} {f(cy + rr * math.sin(a))}")
    return path("M" + " L".join(pts) + "Z", fill=color, opacity=opacity)


def heart(cx, cy, r, color, opacity):
    d = (f"M{f(cx)} {f(cy + r * 0.9)} C{f(cx - r * 1.6)} {f(cy - r * 0.2)} {f(cx - r * 0.6)} {f(cy - r * 1.3)} {f(cx)} {f(cy - r * 0.4)} "
         f"C{f(cx + r * 0.6)} {f(cy - r * 1.3)} {f(cx + r * 1.6)} {f(cy - r * 0.2)} {f(cx)} {f(cy + r * 0.9)} Z")
    return path(d, fill=color, opacity=opacity)


def pattern(p, seed):
    """Sidebar background (1:2): a sparse scatter over the panel colour."""
    w, h = 480, 960
    rnd = random.Random(seed)
    shapes = []
    for _ in range(46):
        x, y = rnd.uniform(10, w - 10), rnd.uniform(10, h - 10)
        kind = rnd.random()
        color = rnd.choice([p["accent"], p["stripe"], p["blush"]])
        if kind < 0.35:
            shapes.append(star(x, y, rnd.uniform(6, 12), color, 0.45))
        elif kind < 0.6:
            shapes.append(heart(x, y, rnd.uniform(5, 9), color, 0.4))
        else:
            shapes.append(ellipse(x, y, rnd.uniform(2.5, 5), rnd.uniform(2.5, 5), color, opacity=0.35))
    return svg(w, h, shapes)


def wallpaper(p, seed):
    """Desktop wallpaper (16:9): a pastel sky, a soft hill, clouds, the
    scatter of stars and hearts, and the character standing on the hill."""
    w, h = 1920, 1080
    rnd = random.Random(seed)
    defs = (
        '<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{p["surface2"]}"/><stop offset="1" stop-color="{p["background"]}"/>'
        "</linearGradient></defs>"
    )
    body = [defs, f'<rect width="{w}" height="{h}" fill="url(#sky)"/>']
    # big soft light circles
    for cx, cy, r in ((360, 260, 300), (1560, 180, 220), (980, 560, 380)):
        body.append(ellipse(cx, cy, r, r, "#ffffff", opacity=0.35))
    # clouds: overlapping white ellipses
    for cx, cy, sc in ((300, 200, 1.0), (1180, 150, 0.8), (1700, 330, 0.7)):
        for dx, dy, rx, ry in ((0, 0, 70, 44), (-60, 14, 50, 32), (60, 12, 56, 36), (18, -26, 44, 34)):
            body.append(ellipse(cx + dx * sc, cy + dy * sc, rx * sc, ry * sc, "#ffffff", opacity=0.9))
    for _ in range(60):
        x, y = rnd.uniform(20, w - 20), rnd.uniform(20, h * 0.72)
        color = rnd.choice([p["accent"], p["stripe"], p["blush"]])
        k = rnd.random()
        if k < 0.35:
            body.append(star(x, y, rnd.uniform(8, 18), color, 0.55))
        elif k < 0.6:
            body.append(heart(x, y, rnd.uniform(7, 14), color, 0.5))
        else:
            body.append(ellipse(x, y, rnd.uniform(3, 7), rnd.uniform(3, 7), color, opacity=0.45))
    # the hill, and the character on it (the GIF's first frame, scaled)
    body.append(ellipse(1340, 1180, 900, 330, p["surface4"]))
    body.append(ellipse(1340, 1200, 860, 300, p["surface3"], opacity=0.7))
    body.append(ellipse(1400, 882, 290, 22, p["line"], opacity=0.12))
    cw, ch = (x * 1.45 for x in CHARACTER_SIZE)
    body.append(f'<image x="{f(1400 - cw / 2)}" y="{f(892 - ch)}" width="{f(cw)}" height="{f(ch)}" href="{CHARACTER}"/>')
    return svg(w, h, body)


def main():
    themes = json.load(open(THEMES, encoding="utf-8"))["themes"]
    variants = next(t for t in themes if t["id"] == "chiikawa")["variants"]
    for i, v in enumerate(variants):
        p = v["palette"]
        with open(os.path.join(HERE, f"{v['id']}-tall.svg"), "w", encoding="utf-8") as out:
            out.write(pattern(p, seed=i + 1))
        with open(os.path.join(HERE, f"{v['id']}-wallpaper.svg"), "w", encoding="utf-8") as out:
            out.write(wallpaper(p, seed=i + 11))


if __name__ == "__main__":
    main()
