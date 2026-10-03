#!/usr/bin/env python3
"""Draw the Ghibli theme's art for each variant, from its palette in
modules/common/themes.json:

  <variant>-wallpaper.svg  the default wallpaper (16:9, themes.json `wallpaper`)
  <variant>-tall.svg       a sparse pattern for the sidebars' background
  <variant>-spirit.svg     the variant's spirit (the sidebars' corner, the
                           cut-in, the loading screen)

  totoro    a summer afternoon: towering clouds over blue hills, rice
            paddies, the great camphor tree on its hill with the grey forest
            spirit sitting under it; leaves, acorns and soot sprites
  spirited  the bathhouse at nightfall: a dusk sky over the flooded plain,
            the sea train on its rails, the lit bathhouse and its lanterns
            mirrored in the water, the masked spirit waiting on the rails;
            paper birds and lanterns
  mononoke  the ancient forest: cedar trunks fading into the mist, shafts of
            light, moss, and kodama everywhere among the roots; fireflies

Soft edges are Gaussian blurs (resvg renders them). No text. Seeded:
rerunning gives the same pictures; rerun after changing the palettes:
  python3 generate.py
qml.nix rasterises the SVGs to PNG with resvg when the package is built.
"""
import json
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
THEMES = os.path.join(HERE, "..", "..", "modules", "common", "themes.json")
W, H = 1920, 1080


def f(x):
    return f"{x:.1f}".rstrip("0").rstrip(".")


def svg(w, h, body, defs=()):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'viewBox="0 0 {w} {h}" width="{w}" height="{h}"><defs>' + "".join(defs) + "</defs>"
            + "".join(body) + "</svg>\n")


def blur(id_, sd):
    return (f'<filter id="{id_}" x="-50%" y="-50%" width="200%" height="200%">'
            f'<feGaussianBlur stdDeviation="{sd}"/></filter>')


def lgrad(id_, stops, x2=0, y2=1):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<linearGradient id="{id_}" x1="0" y1="0" x2="{x2}" y2="{y2}">{s}</linearGradient>'


def rgrad(id_, stops, cx=0.5, cy=0.5, r=0.5):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{id_}" cx="{cx}" cy="{cy}" r="{r}">{s}</radialGradient>'


def attrs(fill="none", stroke=None, width=None, opacity=None, filt=None, extra=""):
    a = f' fill="{fill}"'
    if stroke:
        a += f' stroke="{stroke}" stroke-width="{f(width or 1)}" stroke-linecap="round" stroke-linejoin="round"'
    if opacity is not None:
        a += f' opacity="{f(opacity) if opacity < 1 else 1}"'
    if filt:
        a += f' filter="url(#{filt})"'
    return a + extra


def circle(cx, cy, r, **kw):
    return f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}"{attrs(**kw)}/>'


def ellipse(cx, cy, rx, ry, rot=0, **kw):
    t = f' transform="rotate({f(rot)} {f(cx)} {f(cy)})"' if rot else ""
    return f'<ellipse cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}"{attrs(**kw)}{t}/>'


def rect(x, y, w, h, rx=0, **kw):
    return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(rx)}"{attrs(**kw)}/>'


def path(d, **kw):
    return f'<path d="{d}"{attrs(**kw)}/>'


def g(body, transform="", opacity=None, filt=None):
    a = ""
    if transform:
        a += f' transform="{transform}"'
    if opacity is not None:
        a += f' opacity="{f(opacity)}"'
    if filt:
        a += f' filter="url(#{filt})"'
    return f"<g{a}>" + "".join(body) + "</g>"


def smooth(points, closed_to=None):
    """A smooth path through `points` (Catmull-Rom as cubic Béziers);
    closed_to=y closes it down to that height (a filled ridge)."""
    d = f"M{f(points[0][0])} {f(points[0][1])}"
    for i in range(len(points) - 1):
        p0 = points[max(0, i - 1)]
        p1, p2 = points[i], points[i + 1]
        p3 = points[min(len(points) - 1, i + 2)]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f" C{f(c1[0])} {f(c1[1])} {f(c2[0])} {f(c2[1])} {f(p2[0])} {f(p2[1])}"
    if closed_to is not None:
        d += f" L{f(points[-1][0])} {f(closed_to)} L{f(points[0][0])} {f(closed_to)} Z"
    return d


def ridge(rnd, y, amp, step, x0=-40, x1=W + 40, rough=0.5):
    pts = []
    x = x0
    h = 0.0
    while x <= x1 + step:
        h = h * rough + (rnd.random() - 0.5) * amp
        pts.append((x, y + h))
        x += step
    return pts


def mix(c1, c2, t):
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(a, b))


# ================================================================== spirits
def totoro(cx, base, s, p, blink=False):
    """The grey forest spirit, sitting: a pear-shaped body, pointed ears, a
    cream belly with chevrons, round eyes, whiskers, a wide grin."""
    fur, belly, line = p["fur"], p["belly"], "#2a2f31"
    out = []
    out.append(ellipse(cx, base + 4 * s, 62 * s, 9 * s, fill="#000000", opacity=0.18))
    # Ears.
    for side in (-1, 1):
        out.append(path(f"M{f(cx + side * 22 * s)} {f(base - 140 * s)} Q{f(cx + side * 30 * s)} {f(base - 205 * s)} "
                        f"{f(cx + side * 38 * s)} {f(base - 200 * s)} Q{f(cx + side * 44 * s)} {f(base - 160 * s)} "
                        f"{f(cx + side * 40 * s)} {f(base - 132 * s)} Z", fill=fur))
    # Body.
    out.append(path(f"M{f(cx)} {f(base - 165 * s)} C{f(cx + 50 * s)} {f(base - 165 * s)} {f(cx + 70 * s)} {f(base - 90 * s)} "
                    f"{f(cx + 70 * s)} {f(base - 40 * s)} C{f(cx + 70 * s)} {f(base)} {f(cx + 40 * s)} {f(base)} {f(cx)} {f(base)} "
                    f"C{f(cx - 40 * s)} {f(base)} {f(cx - 70 * s)} {f(base)} {f(cx - 70 * s)} {f(base - 40 * s)} "
                    f"C{f(cx - 70 * s)} {f(base - 90 * s)} {f(cx - 50 * s)} {f(base - 165 * s)} {f(cx)} {f(base - 165 * s)} Z", fill=fur))
    # Belly and its chevrons.
    out.append(ellipse(cx, base - 48 * s, 50 * s, 46 * s, fill=belly))
    for row, n in ((0, 3), (1, 4)):
        for k in range(n):
            x = cx + (k - (n - 1) / 2) * 16 * s
            y = base - (78 - row * 14) * s
            out.append(path(f"M{f(x - 5 * s)} {f(y + 3 * s)} L{f(x)} {f(y - 2 * s)} L{f(x + 5 * s)} {f(y + 3 * s)}",
                            stroke=fur, width=3 * s))
    # Arms.
    for side in (-1, 1):
        out.append(ellipse(cx + side * 62 * s, base - 62 * s, 12 * s, 34 * s, rot=side * -12, fill=mix(fur, line, 0.15)))
    # Eyes.
    for side in (-1, 1):
        ex, ey = cx + side * 21 * s, base - 128 * s
        if blink:
            out.append(path(f"M{f(ex - 8 * s)} {f(ey)} Q{f(ex)} {f(ey + 5 * s)} {f(ex + 8 * s)} {f(ey)}", stroke=line, width=2.5 * s))
        else:
            out.append(circle(ex, ey, 9 * s, fill="#ffffff"))
            out.append(circle(ex, ey, 4 * s, fill=line))
    # Nose, whiskers, grin.
    out.append(ellipse(cx, base - 136 * s, 6 * s, 3 * s, fill=line))
    for side in (-1, 1):
        for k in (-1, 0, 1):
            out.append(path(f"M{f(cx + side * 30 * s)} {f(base - 118 * s + k * 5 * s)} L{f(cx + side * 58 * s)} {f(base - 121 * s + k * 9 * s)}",
                            stroke=line, width=1.6 * s))
    out.append(path(f"M{f(cx - 24 * s)} {f(base - 116 * s)} Q{f(cx)} {f(base - 100 * s)} {f(cx + 24 * s)} {f(base - 116 * s)}",
                    stroke=line, width=2.2 * s))
    # Feet.
    for side in (-1, 1):
        out.append(ellipse(cx + side * 30 * s, base - 4 * s, 20 * s, 8 * s, fill=mix(fur, line, 0.1)))
    return out


def noface(cx, base, s, p):
    """The masked spirit: a tall shadow, a white mask with violet marks."""
    body = "#151217"
    out = [ellipse(cx, base, 40 * s, 7 * s, fill="#000000", opacity=0.25)]
    out.append(path(f"M{f(cx - 34 * s)} {f(base)} C{f(cx - 42 * s)} {f(base - 120 * s)} {f(cx - 38 * s)} {f(base - 200 * s)} "
                    f"{f(cx)} {f(base - 215 * s)} C{f(cx + 38 * s)} {f(base - 200 * s)} {f(cx + 42 * s)} {f(base - 120 * s)} "
                    f"{f(cx + 34 * s)} {f(base)} Z", fill=body, opacity=0.92))
    my = base - 168 * s
    out.append(ellipse(cx, my, 19 * s, 26 * s, fill="#f4efe6"))
    for side in (-1, 1):
        ex = cx + side * 8 * s
        out.append(ellipse(ex, my - 6 * s, 3.6 * s, 2.2 * s, fill="#1a1a1a"))
        out.append(path(f"M{f(ex - 2 * s)} {f(my - 13 * s)} L{f(ex)} {f(my - 19 * s)} L{f(ex + 2 * s)} {f(my - 13 * s)} Z", fill="#7b4f8c"))
        out.append(path(f"M{f(ex - 2 * s)} {f(my - 1 * s)} L{f(ex)} {f(my + 7 * s)} L{f(ex + 2 * s)} {f(my - 1 * s)} Z", fill="#7b4f8c"))
    out.append(ellipse(cx, my + 14 * s, 4 * s, 1.6 * s, fill="#1a1a1a"))
    return out


def kodama(cx, base, s, tilt=0, p=None, glow=None):
    """A tree spirit: a pale, lumpy head with three dark holes, a small
    body; heads tilt every way."""
    white = (p or {}).get("fur", "#f2f0e6")
    hole = "#1f2620"
    out = []
    if glow:
        out.append(circle(cx, base - 34 * s, 40 * s, fill=glow, opacity=0.18, filt="soft"))
    out.append(path(f"M{f(cx - 8 * s)} {f(base)} Q{f(cx - 10 * s)} {f(base - 16 * s)} {f(cx - 6 * s)} {f(base - 26 * s)} "
                    f"L{f(cx + 6 * s)} {f(base - 26 * s)} Q{f(cx + 10 * s)} {f(base - 16 * s)} {f(cx + 8 * s)} {f(base)} Z", fill=white))
    for side in (-1, 1):  # little arms
        out.append(path(f"M{f(cx + side * 6 * s)} {f(base - 20 * s)} L{f(cx + side * 12 * s)} {f(base - 12 * s)}",
                        stroke=white, width=2.5 * s))
    head = [path(f"M{f(cx - 22 * s)} {f(base - 38 * s)} C{f(cx - 26 * s)} {f(base - 68 * s)} {f(cx + 4 * s)} {f(base - 72 * s)} "
                 f"{f(cx + 10 * s)} {f(base - 66 * s)} C{f(cx + 26 * s)} {f(base - 66 * s)} {f(cx + 25 * s)} {f(base - 44 * s)} "
                 f"{f(cx + 21 * s)} {f(base - 34 * s)} C{f(cx + 16 * s)} {f(base - 20 * s)} {f(cx - 18 * s)} {f(base - 20 * s)} "
                 f"{f(cx - 22 * s)} {f(base - 38 * s)} Z", fill=white),
            ellipse(cx - 9 * s, base - 46 * s, 3.6 * s, 4.2 * s, fill=hole),
            ellipse(cx + 8 * s, base - 47 * s, 3.4 * s, 4.0 * s, fill=hole),
            ellipse(cx, base - 32 * s, 3 * s, 4.2 * s, fill=hole)]
    out.append(g(head, transform=f"rotate({f(tilt)} {f(cx)} {f(base - 30 * s)})"))
    return out


def soot(cx, cy, r, rnd, eyes=True):
    """A soot sprite: a black fuzzball with two white eyes."""
    spikes = []
    n = 26
    for k in range(n):
        a = TAU * k / n + rnd.random() * 0.1
        rr = r * (1.25 + 0.25 * rnd.random())
        spikes.append(f"{f(cx + math.cos(a) * rr)} {f(cy + math.sin(a) * rr)}")
        a2 = a + TAU / n / 2
        spikes.append(f"{f(cx + math.cos(a2) * r * 0.95)} {f(cy + math.sin(a2) * r * 0.95)}")
    out = [path("M" + " L".join(spikes) + " Z", fill="#121212"), circle(cx, cy, r, fill="#121212")]
    if eyes:
        for side in (-1, 1):
            out.append(circle(cx + side * r * 0.38, cy - r * 0.12, r * 0.3, fill="#ffffff"))
            out.append(circle(cx + side * r * 0.38, cy - r * 0.1, r * 0.13, fill="#121212"))
    return out


TAU = 2 * math.pi


# ================================================================ finishing
# The modern painted look: light that blooms (screen-blended blurred
# copies), haze for depth, a colour grade (soft light), film grain and a
# vignette over everything.
FINISH_DEFS = [
    '<filter id="grain" x="0" y="0" width="100%" height="100%">'
    '<feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="7"/>'
    '<feColorMatrix type="matrix" values="0 0 0 0 0.5  0 0 0 0 0.5  0 0 0 0 0.5  0 0 0 0.9 0"/></filter>',
    rgrad("vignette", [(0.55, "#000000", 0), (1, "#000000", 0.55)], 0.5, 0.5, 0.75),
]


def finish(grade_top, grade_bottom, grade=0.35, vignette=0.6, grain=0.07):
    """The grade (a soft-light wash from one tint to another), the grain and
    the vignette, laid over the whole picture."""
    return [
        f'<defs>{lgrad("grade", [(0, grade_top, 1), (1, grade_bottom, 1)], x2=1, y2=1)}</defs>',
        rect(0, 0, W, H, fill="url(#grade)", opacity=grade, extra=' style="mix-blend-mode:soft-light"'),
        rect(0, 0, W, H, fill="#808080", opacity=grain, filt="grain", extra=' style="mix-blend-mode:overlay"'),
        rect(0, 0, W, H, fill="url(#vignette)", opacity=vignette),
    ]


def screen(body, opacity=1.0, filt=None):
    """Light added on top (bloom, rays, glows)."""
    a = f' opacity="{f(opacity)}"' if opacity < 1 else ""
    fl = f' filter="url(#{filt})"' if filt else ""
    return f'<g style="mix-blend-mode:screen"{a}{fl}>' + "".join(body) + "</g>"


def bokeh(rnd, n_, x0, x1, y0, y1, r0, r1, color, opacity, filt="bokeh"):
    """Out-of-focus light: soft discs of various sizes."""
    return screen([circle(rnd.uniform(x0, x1), rnd.uniform(y0, y1), rnd.uniform(r0, r1), fill=color,
                          opacity=opacity * (0.4 + 0.6 * rnd.random())) for _ in range(n_)], filt=filt)


# ================================================================== Totoro
def cloud(cx, cy, s, rnd, p):
    """A towering summer cumulus, painted as one soft mass: a blue-grey body,
    the sunlit top laid over it (offset toward the sun and blurred, so the
    light turns gradually into shadow), a warm rim, the flat base."""
    puffs = []
    for _ in range(46):
        level = rnd.random() ** 0.8
        x = cx + (rnd.random() - 0.5) * 560 * s * (1 - 0.6 * level)
        y = cy - level * 440 * s
        r = (95 - 45 * level + rnd.random() * 45) * s
        puffs.append((x, y, r))
    base = path(f"M{f(cx - 340 * s)} {f(cy + 70 * s)} Q{f(cx)} {f(cy + 34 * s)} {f(cx + 340 * s)} {f(cy + 70 * s)} "
                f"L{f(cx + 300 * s)} {f(cy + 10 * s)} L{f(cx - 300 * s)} {f(cy + 10 * s)} Z", fill="#9db3cf")
    shadow = [base] + [circle(x, y, r, fill="#a9bdd8") for x, y, r in puffs]
    mid = [circle(x - r * 0.14, y - r * 0.16, r * 0.8, fill="#d6e2f0") for x, y, r in puffs]
    lit = [circle(x - r * 0.3, y - r * 0.34, r * 0.5, fill="#ffffff") for x, y, r in puffs]
    rim = [circle(x - r * 0.32, y - r * 0.36, r * 0.42, fill="#fff3d6") for x, y, r in puffs if y < cy - 120 * s]
    return [g(shadow, filt="softer"), g(mid, filt="soft"), g(lit, filt="cloudlight"), screen(rim, 0.35, "cloudlight")]


def camphor(cx, base, s, rnd, p):
    """The great camphor tree: a thick shaded trunk, a huge crown of leaf
    clumps lit from the upper left, sun dapples."""
    leaf = p["leaf"]
    dark, deep = mix(leaf, "#0b2a1a", 0.55), mix(leaf, "#05140c", 0.75)
    out = [path(f"M{f(cx - 64 * s)} {f(base)} C{f(cx - 40 * s)} {f(base - 120 * s)} {f(cx - 52 * s)} {f(base - 230 * s)} "
                f"{f(cx - 22 * s)} {f(base - 340 * s)} L{f(cx + 32 * s)} {f(base - 340 * s)} C{f(cx + 52 * s)} {f(base - 230 * s)} "
                f"{f(cx + 46 * s)} {f(base - 120 * s)} {f(cx + 80 * s)} {f(base)} Z", fill="url(#bark)")]
    for side in (-1, 1):
        out.append(path(f"M{f(cx)} {f(base - 270 * s)} Q{f(cx + side * 130 * s)} {f(base - 340 * s)} {f(cx + side * 230 * s)} {f(base - 370 * s)}",
                        stroke="#3d2f25", width=24 * s))
    clumps = []
    for _ in range(85):
        a = rnd.random() * math.pi
        rr = rnd.random() ** 0.6
        x = cx + math.cos(a) * 440 * s * rr * (1 if rnd.random() < 0.5 else -1) * 0.95
        y = base - 430 * s - math.sin(a) * 310 * s * rr
        clumps.append((x, y, (64 + rnd.random() * 62) * s))
    clumps.sort(key=lambda c: c[1])
    out.append(g([circle(x + 6 * s, y + 14 * s, r, fill=deep) for x, y, r in clumps], filt="softer"))
    out.append(g([circle(x - r * 0.08, y - r * 0.1, r * 0.82, fill=dark) for x, y, r in clumps], filt="softer"))
    out.append(g([circle(x - r * 0.2, y - r * 0.25, r * 0.6, fill=leaf) for x, y, r in clumps], filt="soft"))
    out.append(g([circle(x - r * 0.32, y - r * 0.38, r * 0.34, fill=mix(leaf, "#d8f08a", 0.5)) for x, y, r in clumps
                  if rnd.random() < 0.7], filt="soft"))
    out.append(screen([circle(x - r * 0.38, y - r * 0.44, r * 0.16, fill="#f6ffc8") for x, y, r in clumps
                       if y < base - 470 * s and rnd.random() < 0.5], 0.5, "softer"))
    return out


def totoro_wallpaper(p):
    rnd = random.Random(1988)
    leaf = p["leaf"]
    defs = FINISH_DEFS + [
        lgrad("sky", [(0, "#1f6fc4", 1), (0.45, "#5aaee8", 1), (0.78, "#a9d8f2", 1), (1, "#fdf0d2", 1)]),
        rgrad("sun", [(0, "#fffbe8", 1), (0.12, "#fff3c4", 0.9), (0.45, "#ffe7a0", 0.25), (1, "#ffe7a0", 0)], 0.12, 0.06, 0.6),
        rgrad("puff", [(0, "#ffffff", 1), (0.5, "#fbfcff", 1), (0.78, "#d9e5f2", 1), (1, "#a7bcd6", 1)], 0.32, 0.26, 0.75),
        rgrad("foliage", [(0, mix(leaf, "#d8f08a", 0.45), 1), (0.55, leaf, 1), (1, mix(leaf, "#0b2a1a", 0.5), 1)], 0.3, 0.25, 0.8),
        lgrad("bark", [(0, "#6b5442", 1), (0.5, "#4a3a2e", 1), (1, "#2a1f19", 1)], x2=1, y2=0),
        lgrad("far", [(0, "#7fa8cc", 1), (1, "#b9d6e6", 1)]),
        lgrad("mid", [(0, mix(leaf, "#6c96b0", 0.5), 1), (1, mix(leaf, "#b9d6e6", 0.35), 1)]),
        lgrad("near", [(0, mix(leaf, "#9cc96b", 0.2), 1), (1, mix(leaf, "#1d4a24", 0.35), 1)]),
        lgrad("water", [(0, "#cfe9f7", 0.9), (1, "#7fb7dc", 0.9)]),
        lgrad("hill", [(0, mix(leaf, "#b8dc72", 0.3), 1), (1, mix(leaf, "#123a1c", 0.45), 1)], x2=1, y2=1),
        lgrad("ray", [(0, "#fff6d0", 0.5), (1, "#fff6d0", 0)], x2=0.6, y2=1),
        lgrad("field", [(0, mix(leaf, "#bfe28a", 0.35), 1), (1, mix(leaf, "#2c6a2c", 0.2), 1)]),
        blur("soft", 5), blur("softer", 2), blur("cloudlight", 9), blur("haze", 22), blur("bokeh", 6), blur("near", 4)]
    body = [rect(0, 0, W, H, fill="url(#sky)"), rect(0, 0, W, H, fill="url(#sun)")]
    # Sun rays fanning down from the upper left.
    body.append(screen([path(f"M{f(150 + k * 30)} -40 L{f(260 + k * 40)} -40 L{f(700 + k * 260)} {H} L{f(560 + k * 230)} {H} Z",
                             fill="url(#ray)") for k in range(5)], 0.35, "haze"))
    body += cloud(560, 640, 1.3, rnd, p)
    body += cloud(1540, 590, 0.75, rnd, p)
    body.append(screen([ellipse(1150, 250, 300, 26, fill="#ffffff", opacity=0.75), ellipse(300, 190, 220, 20, fill="#ffffff", opacity=0.6),
                        ellipse(1700, 140, 180, 14, fill="#ffffff", opacity=0.5)], filt="haze"))
    # Hills, far to near, fading into haze.
    for k, (y, amp, fill) in enumerate(((636, 56, "url(#far)"), (676, 40, "url(#mid)"), (708, 28, "url(#near)"))):
        body.append(path(smooth(ridge(rnd, y, amp, 80, rough=0.7), closed_to=H), fill=fill, filt="softer" if k < 2 else None))
        body.append(rect(0, y - 30, W, 70, fill="#e7f2f4", opacity=0.22 - 0.06 * k, filt="haze"))
    # Rice paddies: a green field whose rows recede to the horizon, the
    # sky glinting in the water between the young rice.
    body.append(rect(0, 724, W, H - 724, fill="url(#field)"))
    vp = (980, 600)
    rows = []
    for k in range(-40, 41):
        x = vp[0] + k * 70
        rows.append(path(f"M{f(vp[0] + (x - vp[0]) * 0.18)} 726 L{f(x)} {H}", stroke=mix(leaf, "#173f1c", 0.5), width=1.2, opacity=0.35))
    body.append(g(rows))
    y = 730
    k = 0
    dykes = []
    while y < H:
        dykes.append(path(f"M-20 {f(y)} Q{W / 2} {f(y - 4 - k * 0.5)} {W + 20} {f(y + 2)}", stroke=mix(leaf, "#e2e6a8", 0.45),
                          width=1 + (y - 726) * 0.012, opacity=0.55))
        y += 10 + (y - 726) * 0.35
        k += 1
    body.append(g(dykes, filt="softer"))
    body.append(screen([ellipse(rnd.uniform(0, 1150), rnd.uniform(740, 1000), rnd.uniform(30, 140), 3,
                                fill="#d8efff", opacity=0.6) for _ in range(46)], filt="softer"))
    # The hill, the tree's shadow on it, the tree, the spirit in the shade.
    body.append(path(smooth([(820, H + 20), (980, 930), (1150, 830), (1350, 770), (1560, 748), (1780, 756), (2000, 790)], closed_to=H + 20),
                     fill="url(#hill)"))
    body.append(screen([path(smooth([(1000, 925), (1170, 828), (1360, 770), (1560, 750)]), stroke="#e8f7a8", width=10, opacity=0.4)],
                       filt="soft"))
    body.append(ellipse(1540, 790, 360, 46, fill="#0d2a14", opacity=0.35, filt="soft"))
    body += camphor(1570, 765, 0.8, rnd, p)
    body += totoro(1395, 818, 0.88, p)
    body.append(ellipse(1395, 760, 90, 80, fill="#0d2a14", opacity=0.12, filt="haze"))
    # Pollen drifting in the light.
    body.append(bokeh(rnd, 50, 0, W, 80, 900, 2, 7, "#fff6d0", 0.8, filt="softer"))
    # Foreground grass, out of focus, and a few big bokeh discs.
    blades = []
    for _ in range(300):
        x = rnd.random() * W
        hgt = 40 + rnd.random() * 120
        lean = (rnd.random() - 0.5) * 50
        c = mix(leaf, "#0a2412", 0.35 + 0.45 * rnd.random())
        blades.append(path(f"M{f(x - 5)} {H + 4} Q{f(x + lean * 0.3)} {f(H - hgt * 0.6)} {f(x + lean)} {f(H - hgt)} Q{f(x + lean * 0.2)} {f(H - hgt * 0.5)} {f(x + 5)} {H + 4} Z",
                           fill=c))
    body.append(g(blades, filt="near"))
    body.append(bokeh(rnd, 9, 0, W, 900, 1080, 20, 46, "#fffbe0", 0.35))
    body += finish("#ffd27a", "#3a6fa8", grade=0.3, vignette=0.45)
    return svg(W, H, body, defs)


# ============================================================ Spirited Away
def bathhouse(x0, base, s, p, rnd):
    """The bathhouse: tiers of lacquered walls lit from below by their
    lanterns, flared jade roofs with moonlit edges, rows of glowing windows,
    the tall chimney smoking."""
    glow = p["glow"]
    out, lights, rims = [], [], []
    tiers = [(0, 540, 150), (40, 460, 122), (82, 376, 112), (122, 296, 102), (166, 208, 92)]
    y = base
    chimney_top = base - 590 * s
    cx = x0 + 480 * s
    out.append(g([circle(cx + 15 * s + k * 26 * s, chimney_top - 24 * s - k * 36 * s, (16 + k * 11) * s, fill="#d9cfe0",
                         opacity=0.3 - k * 0.03) for k in range(9)], filt="soft"))
    out.append(rect(cx, chimney_top, 32 * s, 420 * s, fill="url(#chimney)"))
    for k, (inset, width, height) in enumerate(tiers):
        x = x0 + inset * s
        w, h = width * s, height * s
        out.append(rect(x, y - h, w, h, fill="url(#wall)"))
        cols = int(w / (34 * s))
        for c in range(cols):
            for r in range(2):
                if rnd.random() < 0.85:
                    wx = x + 12 * s + c * (w - 24 * s) / cols
                    wy = y - h + 22 * s + r * h * 0.42
                    lights.append(rect(wx, wy, 16 * s, 22 * s, rx=2, fill=mix(glow, "#fff2c8", 0.3 * rnd.random())))
        ry = y - h
        roof = (f"M{f(x - 44 * s)} {f(ry + 6 * s)} Q{f(x + w * 0.1)} {f(ry - 10 * s)} {f(x + w * 0.2)} {f(ry - 32 * s)} "
                f"L{f(x + w * 0.8)} {f(ry - 32 * s)} Q{f(x + w * 0.9)} {f(ry - 10 * s)} {f(x + w + 44 * s)} {f(ry + 6 * s)} Z")
        out.append(path(roof, fill="url(#roof)"))
        rims.append(path(f"M{f(x + w * 0.2)} {f(ry - 32 * s)} L{f(x + w * 0.8)} {f(ry - 32 * s)}", stroke="#cfe6ff", width=2.2 * s))
        rims.append(path(f"M{f(x - 44 * s)} {f(ry + 6 * s)} Q{f(x + w * 0.1)} {f(ry - 10 * s)} {f(x + w * 0.2)} {f(ry - 32 * s)}",
                         stroke="#cfe6ff", width=1.6 * s))
        y = ry - 32 * s
    out += lights
    out.append(screen(lights, 0.9, "glow"))
    out.append(screen(rims, 0.55))
    # Lanterns along the bridge, and their halo.
    lanterns = []
    for k in range(10):
        lx = x0 - 280 * s + k * 38 * s
        lanterns.append(ellipse(lx, base - 34 * s, 6 * s, 8.5 * s, fill="#ffb15c"))
    out.append(rect(x0 - 300 * s, base - 14 * s, 320 * s, 10 * s, fill="url(#wall)"))
    out += lanterns
    out.append(screen([circle(x0 - 280 * s + k * 38 * s, base - 34 * s, 26 * s, fill=glow, opacity=0.7) for k in range(10)], filt="glow"))
    return out


def spirited_wallpaper(p):
    rnd = random.Random(2001)
    horizon = 690
    glow = p["glow"]
    defs = FINISH_DEFS + [
        lgrad("sky", [(0, "#070a22", 1), (0.35, "#1b1d4e", 1), (0.66, "#4a3a78", 1), (0.86, "#b8607a", 1), (1, "#f0a77e", 1)]),
        lgrad("sea", [(0, "#8a5a7a", 1), (0.08, "#2c2a55", 1), (0.5, "#12122c", 1), (1, "#06060f", 1)]),
        rgrad("moon", [(0, "#fff6e0", 0.7), (0.25, "#ffe9c8", 0.25), (1, "#ffe9c8", 0)]),
        lgrad("wall", [(0, mix(p["accent"], "#1a0a12", 0.55), 1), (1, mix(p["accent"], "#ff9a5a", 0.15), 1)]),
        lgrad("roof", [(0, mix(p["leaf"], "#0b1a1c", 0.35), 1), (1, mix(p["leaf"], "#05090c", 0.7), 1)]),
        lgrad("chimney", [(0, "#2a1418", 1), (0.5, "#4a2028", 1), (1, "#1a0c10", 1)], x2=1, y2=0),
        lgrad("train", [(0, "#5d7f9c", 1), (1, "#2b3d52", 1)]),
        lgrad("streak", [(0, glow, 0.7), (1, glow, 0)]),
        blur("soft", 7), blur("softer", 2), blur("glow", 10), blur("haze", 24), blur("ripple", 3), blur("bokeh", 5)]
    body = [rect(0, 0, W, H, fill="url(#sky)")]
    stars = [circle(rnd.random() * W, rnd.random() * 460, 0.5 + rnd.random() * 1.3, fill="#fff8e8", opacity=0.3 + rnd.random() * 0.7)
             for _ in range(220)]
    body.append(g(stars))
    for _ in range(7):  # a few bright stars with a cross glint
        x, y = rnd.random() * W, rnd.random() * 380
        body.append(screen([path(f"M{f(x - 9)} {f(y)} L{f(x + 9)} {f(y)} M{f(x)} {f(y - 9)} L{f(x)} {f(y + 9)}", stroke="#fff8e8", width=1),
                            circle(x, y, 4, fill="#fff8e8", opacity=0.8)], 0.8, "softer"))
    body.append(circle(330, 210, 300, fill="url(#moon)"))
    body.append(circle(330, 210, 48, fill="#fbf1dc"))
    body.append(circle(318, 200, 48, fill="#fffaf0", opacity=0.5, filt="softer"))
    # Long dusk clouds, lit pink from below.
    body.append(g([ellipse(260 + k * 330 + rnd.random() * 120, 450 + rnd.random() * 150, 260 + rnd.random() * 160, 12 + rnd.random() * 9,
                           fill=mix("#f3a6a0", "#ffffff", 0.2), opacity=0.5) for k in range(7)], filt="haze"))
    body.append(path(smooth(ridge(rnd, horizon - 22, 30, 70, rough=0.6), closed_to=horizon + 2), fill="#2a2148", opacity=0.9, filt="softer"))
    body.append(rect(0, horizon - 40, W, 60, fill="#f0a77e", opacity=0.25, filt="haze"))
    house = bathhouse(1220, horizon + 4, 1.0, p, rnd)
    rail_y = horizon + 70
    scene = [rect(-10, rail_y, W + 20, 5, fill="#140f1c")]
    for k in range(-1, 26):
        scene.append(rect(k * 82, rail_y - 26, 5, 36, fill="#140f1c"))
    tx = 290
    scene.append(rect(tx, rail_y - 58, 310, 54, rx=12, fill="url(#train)"))
    scene.append(rect(tx, rail_y - 64, 310, 10, rx=5, fill="#22324a"))
    windows = [rect(tx + 16 + k * 40, rail_y - 48, 28, 22, rx=3, fill="#ffd9a0") for k in range(7)]
    scene += windows
    scene.append(screen(windows, 0.9, "glow"))
    scene.append(screen([path(f"M{tx + 310} {rail_y - 30} L{tx + 620} {rail_y - 60} L{tx + 620} {rail_y + 10} Z", fill="#fff0c8", opacity=0.25)],
                        filt="haze"))
    scene += noface(870, rail_y + 2, 0.42, p)
    # The sea, mirrored scene, light streaks, then the scene itself.
    body.append(rect(0, horizon + 4, W, H - horizon, fill="url(#sea)"))
    body.append(g([g(house, transform=f"translate(0 {2 * (horizon + 4)}) scale(1 -1)", opacity=0.42),
                   g(scene, transform=f"translate(0 {2 * rail_y}) scale(1 -1)", opacity=0.36)], filt="ripple"))
    streaks = [rect(x - 9, horizon + 10, 18, 300 + rnd.random() * 120, fill="url(#streak)")
               for x in [1220 - 280 + k * 38 for k in range(10)] + [tx + 30 + k * 40 for k in range(7)]]
    body.append(screen(streaks, 0.5, "softer"))
    body.append(g(house))
    body.append(g(scene))
    ripples = []
    for _ in range(170):
        y = horizon + 18 + rnd.random() ** 1.6 * (H - horizon)
        x = rnd.random() * W
        w = 18 + (y - horizon) * 0.45 * rnd.random()
        ripples.append(path(f"M{f(x)} {f(y)} l{f(w)} 0", stroke=mix(glow, "#ffffff", 0.3), width=1 + (y - horizon) * 0.004,
                            opacity=0.1 + 0.22 * rnd.random()))
    body.append(screen(ripples))
    body.append(rect(0, horizon - 10, W, 50, fill="#c9a8d8", opacity=0.18, filt="haze"))
    body.append(bokeh(rnd, 14, 900, W, 520, 760, 6, 16, glow, 0.5))
    body += finish("#5a3fa0", "#ff9a5a", grade=0.28, vignette=0.6)
    return svg(W, H, body, defs)


# ================================================================== Mononoke
def mononoke_wallpaper(p):
    rnd = random.Random(1997)
    leaf, glow = p["leaf"], p["glow"]
    defs = FINISH_DEFS + [
        lgrad("air", [(0, "#cfe7c8", 1), (0.35, "#5f8f6d", 1), (0.7, "#1d3a2a", 1), (1, "#07120b", 1)]),
        lgrad("ray", [(0, "#f6ffd8", 0.55), (1, "#f6ffd8", 0)]),
        lgrad("ground", [(0, mix(leaf, "#2f5a2a", 0.4), 1), (1, "#06100a", 1)]),
        blur("soft", 6), blur("softer", 2), blur("mist", 28), blur("far", 9), blur("mid", 3.5), blur("glow", 7), blur("bokeh", 9)]
    for k, depth in enumerate((0.15, 0.45, 0.9)):
        dark = mix("#a7c4a0", "#0f1a12", depth ** 0.6)
        light = mix("#e8f3d8", "#3e5a3c", depth ** 0.6)
        defs.append(lgrad(f"trunk{k}", [(0, dark, 1), (0.35, light, 1), (0.6, mix(light, dark, 0.4), 1), (1, dark, 1)], x2=1, y2=0))
        defs.append(lgrad(f"moss{k}", [(0, mix(leaf, light, 0.3), 0), (1, mix(leaf, dark, 0.2), 0.9)]))
    body = [rect(0, 0, W, H, fill="url(#air)")]
    body.append(screen([path(f"M{f(x)} -20 L{f(x + w)} -20 L{f(x - 280 + w * 2)} {H} L{f(x - 380)} {H} Z", fill="url(#ray)")
                        for x, w in ((640 + k * 180 + rnd.random() * 90, 40 + rnd.random() * 80) for k in range(7))], 0.8, "mist"))

    def trunks(n_, k, depth):
        out = []
        for _ in range(n_):
            x = rnd.random() * (W + 200) - 100
            w = (30 + rnd.random() * 44) * (0.4 + depth * 1.7)
            base = 760 + depth * 300
            lean = (rnd.random() - 0.5) * 30
            out.append(path(f"M{f(x - w / 2 + lean)} -20 L{f(x + w / 2 + lean)} -20 L{f(x + w / 2)} {f(base - w * 0.6)} "
                            f"Q{f(x + w * 0.9)} {f(base)} {f(x + w * 1.6)} {f(base + 8)} L{f(x - w * 1.6)} {f(base + 8)} "
                            f"Q{f(x - w * 0.9)} {f(base)} {f(x - w / 2)} {f(base - w * 0.6)} Z", fill=f"url(#trunk{k})"))
            out.append(rect(x - w * 0.6, base - w * 4, w * 1.2, w * 4 + 8, fill=f"url(#moss{k})"))
        return out

    body.append(g(trunks(18, 0, 0.15), filt="far", opacity=0.7))
    body.append(screen([ellipse(W / 2, 690, 1300, 120, fill="#dff0d6", opacity=0.35)], filt="mist"))
    body.append(g(trunks(10, 1, 0.45), filt="mid"))
    body.append(screen([ellipse(W / 2 + 200, 860, 1200, 100, fill="#cfe6c6", opacity=0.25)], filt="mist"))
    body.append(path(smooth(ridge(rnd, 905, 40, 90, rough=0.6), closed_to=H + 10), fill="url(#ground)"))
    ferns = []
    for _ in range(46):
        x, y = rnd.random() * W, 930 + rnd.random() * 160
        for k in range(5):
            a = -math.pi / 2 + (k - 2) * 0.45
            ln = 44 + rnd.random() * 56
            ferns.append(path(f"M{f(x)} {f(y)} Q{f(x + math.cos(a) * ln * 0.5)} {f(y + math.sin(a) * ln * 0.8)} {f(x + math.cos(a) * ln)} {f(y + math.sin(a) * ln * 0.6)}",
                              stroke=mix(leaf, "#0b1a0b", 0.25 + 0.35 * rnd.random()), width=4))
    body.append(g(ferns, filt="softer"))
    # Kodama among the roots and on the moss, near ones bigger, glowing.
    spirits, halos = [], []
    for _ in range(26):
        y = 830 + rnd.random() ** 0.8 * 230
        s = 0.3 + (y - 830) / 230 * 0.85
        x = rnd.random() * W
        spirits += kodama(x, y, s, tilt=(rnd.random() - 0.5) * 70, p=p)
        halos.append(circle(x, y - 36 * s, 34 * s, fill=glow, opacity=0.5))
    body.append(screen(halos, 0.8, "glow"))
    body.append(g(spirits))
    body.append(g(trunks(4, 2, 0.9), filt="softer"))
    # Fireflies near and far: sharp sparks and big out-of-focus discs.
    body.append(bokeh(rnd, 60, 0, W, 300, 1000, 1.5, 4, glow, 0.9, filt="softer"))
    body.append(bokeh(rnd, 12, 0, W, 200, 1080, 18, 40, glow, 0.35))
    body += finish("#f2ffd0", "#0a2a2a", grade=0.3, vignette=0.65)
    return svg(W, H, body, defs)


# ================================================================ patterns
def leaf(cx, cy, s, rot, color, opacity):
    d = (f"M{f(cx)} {f(cy - 14 * s)} C{f(cx + 9 * s)} {f(cy - 6 * s)} {f(cx + 8 * s)} {f(cy + 8 * s)} {f(cx)} {f(cy + 14 * s)} "
         f"C{f(cx - 8 * s)} {f(cy + 8 * s)} {f(cx - 9 * s)} {f(cy - 6 * s)} {f(cx)} {f(cy - 14 * s)} Z")
    vein = f"M{f(cx)} {f(cy - 12 * s)} L{f(cx)} {f(cy + 16 * s)}"
    return g([path(d, fill=color), path(vein, stroke="#ffffff", width=0.8 * s, opacity=0.5)],
             transform=f"rotate({f(rot)} {f(cx)} {f(cy)})", opacity=opacity)


def acorn(cx, cy, s, rot, opacity):
    return g([ellipse(cx, cy + 4 * s, 6 * s, 8 * s, fill="#a8743f"), path(
        f"M{f(cx - 7 * s)} {f(cy)} Q{f(cx)} {f(cy - 9 * s)} {f(cx + 7 * s)} {f(cy)} Z", fill="#6b4a2b"),
        rect(cx - 0.8 * s, cy - 9 * s, 1.6 * s, 4 * s, fill="#6b4a2b")],
        transform=f"rotate({f(rot)} {f(cx)} {f(cy)})", opacity=opacity)


def shikigami(cx, cy, s, rot, opacity):
    """A paper bird: a little paper doll cut-out."""
    d = (f"M{f(cx)} {f(cy - 10 * s)} L{f(cx + 4 * s)} {f(cy - 4 * s)} L{f(cx + 14 * s)} {f(cy - 2 * s)} L{f(cx + 5 * s)} {f(cy + 2 * s)} "
         f"L{f(cx + 6 * s)} {f(cy + 14 * s)} L{f(cx)} {f(cy + 8 * s)} L{f(cx - 6 * s)} {f(cy + 14 * s)} L{f(cx - 5 * s)} {f(cy + 2 * s)} "
         f"L{f(cx - 14 * s)} {f(cy - 2 * s)} L{f(cx - 4 * s)} {f(cy - 4 * s)} Z")
    return g([path(d, fill="#f6f1e4"), circle(cx, cy - 10 * s, 4 * s, fill="#f6f1e4")],
             transform=f"rotate({f(rot)} {f(cx)} {f(cy)})", opacity=opacity)


def pattern(vid, p, seed):
    """Sidebar background (1:2): a sparse scatter, faint over the panel."""
    w, h = 480, 960
    rnd = random.Random(seed)
    defs = [blur("soft", 4), blur("glow", 6)]
    shapes = []
    if vid == "totoro":
        for _ in range(26):
            shapes.append(leaf(rnd.uniform(10, w - 10), rnd.uniform(10, h - 10), rnd.uniform(0.9, 1.6), rnd.uniform(0, 360),
                               rnd.choice([p["leaf"], p["stripe"], p["primary"]]), 0.4))
        for _ in range(9):
            shapes.append(acorn(rnd.uniform(10, w - 10), rnd.uniform(10, h - 10), rnd.uniform(0.9, 1.3), rnd.uniform(-30, 30), 0.45))
        for _ in range(7):
            shapes.append(g(soot(rnd.uniform(20, w - 20), rnd.uniform(20, h - 20), rnd.uniform(5, 9), rnd), opacity=0.5))
    elif vid == "spirited":
        for _ in range(12):
            shapes.append(circle(rnd.uniform(0, w), rnd.uniform(0, h), rnd.uniform(14, 30), fill=p["glow"], opacity=0.16, filt="glow"))
        for _ in range(16):
            shapes.append(shikigami(rnd.uniform(10, w - 10), rnd.uniform(10, h - 10), rnd.uniform(0.8, 1.4), rnd.uniform(-40, 40), 0.3))
        for _ in range(8):  # seigaiha wave crests
            x, y = rnd.uniform(0, w), rnd.uniform(0, h)
            for k in range(3):
                shapes.append(path(f"M{f(x - 18 + k * 5)} {f(y)} A{f(18 - k * 5)} {f(18 - k * 5)} 0 0 1 {f(x + 18 - k * 5)} {f(y)}",
                                   stroke=p["secondary"], width=1.5, opacity=0.25))
    else:
        for _ in range(9):
            x, y = rnd.uniform(20, w - 20), rnd.uniform(40, h - 10)
            shapes.append(g(kodama(x, y, rnd.uniform(0.5, 0.8), tilt=rnd.uniform(-40, 40), p=p), opacity=0.32))
        for _ in range(18):
            shapes.append(leaf(rnd.uniform(10, w - 10), rnd.uniform(10, h - 10), rnd.uniform(0.8, 1.3), rnd.uniform(0, 360),
                               rnd.choice([p["leaf"], p["primary"]]), 0.3))
        for _ in range(24):
            shapes.append(circle(rnd.uniform(0, w), rnd.uniform(0, h), rnd.uniform(1.5, 3), fill=p["glow"], opacity=0.55, filt="soft"))
    return svg(w, h, shapes, defs)


def spirit(vid, p):
    """The variant's spirit alone (1:1, transparent)."""
    defs = [blur("soft", 8)]
    if vid == "totoro":
        body = totoro(200, 380, 1.75, p)
    elif vid == "spirited":
        body = noface(200, 390, 1.7, p)
    else:
        body = kodama(200, 385, 4.6, tilt=-12, p=p)
    return svg(400, 400, body, defs)


def main():
    themes = json.load(open(THEMES, encoding="utf-8"))["themes"]
    variants = next(t for t in themes if t["id"] == "ghibli")["variants"]
    draw = {"totoro": totoro_wallpaper, "spirited": spirited_wallpaper, "mononoke": mononoke_wallpaper}
    for i, v in enumerate(variants):
        p = v["palette"]
        for kind, content in (("wallpaper", draw[v["id"]](p)), ("tall", pattern(v["id"], p, seed=i + 1)),
                              ("spirit", spirit(v["id"], p))):
            with open(os.path.join(HERE, f"{v['id']}-{kind}.svg"), "w", encoding="utf-8") as out:
                out.write(content)


if __name__ == "__main__":
    main()
