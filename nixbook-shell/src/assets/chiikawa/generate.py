#!/usr/bin/env python3
"""Generate the Chiikawa theme's art: each variant's character (<variant>.svg,
the mascot on the loading screen and the sidebars) and a scattered pattern of
tiny stars, hearts and dots for the sidebars' background (<variant>-tall.svg).

Simple fan-art shapes drawn from scratch (ellipses and paths, no external
artwork). Colours come from each variant's palette in
modules/common/themes.json (body, fur, blush, line, accent, stripe), so the
art follows the theme's single definition. Only plain shapes are used, so
resvg (qml.nix rasterises the SVGs to PNG) and Qt draw them the same.
Run: python3 generate.py
"""
import json
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
THEMES = os.path.join(HERE, "..", "..", "modules", "common", "themes.json")
LINE = 5  # outline width, in the 200x200 character viewBox


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


# ------------------------------------------------------------------ faces
def eyes(p, y=96, dx=24, big=False):
    rx, ry = (8.5, 10.5) if big else (6.5, 8)
    out = []
    for x in (100 - dx, 100 + dx):
        out.append(ellipse(x, y, rx, ry, p["line"]))
        out.append(ellipse(x + 2, y - 3.5, rx * 0.38, ry * 0.34, "#ffffff"))
        if big:
            out.append(ellipse(x - 2.5, y + 4, rx * 0.2, ry * 0.18, "#ffffff"))
    return out


def blush(p, y=113, dx=42):
    out = []
    for x in (100 - dx, 100 + dx):
        out.append(ellipse(x, y, 12, 6.5, p["blush"], opacity=0.85))
        # the little hatch lines on the cheeks
        for i in (-5, 0, 5):
            out.append(path(f"M{f(x + i - 2)} {f(y + 2.5)} L{f(x + i + 2)} {f(y - 2.5)}", stroke=p["line"], width=1.6, opacity=0.45))
    return out


def body(p, fill):
    # Stubby round body, arms and feet under the big head.
    return [
        ellipse(72, 186, 17, 9, fill, p["line"]),
        ellipse(128, 186, 17, 9, fill, p["line"]),
        ellipse(100, 156, 50, 34, fill, p["line"]),
        ellipse(52, 150, 11, 15, fill, p["line"], rot=28),
        ellipse(148, 150, 11, 15, fill, p["line"], rot=-28),
    ]


def chiikawa(p):
    """The small white one: round ears, dot eyes, pink blush, a tiny "w"."""
    return [
        *body(p, p["body"]),
        ellipse(54, 52, 15, 14, p["body"], p["line"]),
        ellipse(146, 52, 15, 14, p["body"], p["line"]),
        ellipse(100, 98, 68, 56, p["body"], p["line"]),
        *blush(p),
        *eyes(p),
        path("M91 111 Q95.5 117 100 111 Q104.5 117 109 111", stroke=p["line"], width=3.2),
    ]


def usagi(p):
    """The rabbit: long ears, yellow fur, a wide open laugh."""
    ear = p["fur"]
    return [
        *body(p, p["body"]),
        ellipse(76, 42, 13, 35, p["body"], p["line"], rot=-8),
        ellipse(124, 42, 13, 35, p["body"], p["line"], rot=8),
        ellipse(76, 45, 5.5, 23, ear, rot=-8),
        ellipse(124, 45, 5.5, 23, ear, rot=8),
        ellipse(100, 100, 66, 54, p["body"], p["line"]),
        *blush(p, y=112, dx=44),
        *eyes(p, y=92, dx=26),
        # "Yaha!": open mouth with its tongue
        path("M84 108 Q100 138 116 108 Z", fill="#b8424f", stroke=p["line"], width=3.5),
        path("M92 124 Q100 116 108 124 Q100 131 92 124 Z", fill="#f59aa6"),
    ]


def momonga(p):
    """The flying squirrel: big fluffy tail, pointed ears, sparkly eyes."""
    return [
        # tail behind, curling up on the right
        path("M138 176 C196 176 206 112 178 82 C162 66 146 84 158 100 C176 124 162 150 132 156 Z",
             fill=p["fur"], stroke=p["line"]),
        *body(p, p["body"]),
        path("M44 70 L50 24 L84 52 Z", fill=p["body"], stroke=p["line"]),
        path("M156 70 L150 24 L116 52 Z", fill=p["body"], stroke=p["line"]),
        path("M54 58 L56 36 L72 50 Z", fill=p["blush"], opacity=0.7),
        path("M146 58 L144 36 L128 50 Z", fill=p["blush"], opacity=0.7),
        ellipse(100, 98, 66, 56, p["body"], p["line"]),
        *blush(p, y=116, dx=44),
        *eyes(p, y=98, dx=25, big=True),
        path("M93 116 Q96.5 120 100 116 Q103.5 120 107 116", stroke=p["line"], width=3),
    ]


DRAW = {"chiikawa": chiikawa, "usagi": usagi, "momonga": momonga}


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


def main():
    themes = json.load(open(THEMES, encoding="utf-8"))["themes"]
    variants = next(t for t in themes if t["id"] == "chiikawa")["variants"]
    for i, v in enumerate(variants):
        p = v["palette"]
        with open(os.path.join(HERE, f"{v['id']}.svg"), "w", encoding="utf-8") as out:
            out.write(svg(200, 200, DRAW[v["id"]](p)))
        with open(os.path.join(HERE, f"{v['id']}-tall.svg"), "w", encoding="utf-8") as out:
            out.write(pattern(p, seed=i + 1))


if __name__ == "__main__":
    main()
