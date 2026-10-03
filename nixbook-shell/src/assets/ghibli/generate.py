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


# ================================================================== Totoro
def cloud(cx, cy, s, rnd, shade, top="#ffffff"):
    """A towering summer cumulus: stacked puffs, shaded underneath."""
    puffs = []
    for k in range(34):
        level = rnd.random()
        x = cx + (rnd.random() - 0.5) * 520 * s * (1 - 0.55 * level)
        y = cy - level * 420 * s
        r = (90 - 40 * level + rnd.random() * 40) * s
        puffs.append((x, y, r))
    puffs.sort(key=lambda q: -q[1])
    shadow = [circle(x + 10 * s, y + 22 * s, r, fill=shade) for x, y, r in puffs]
    body = [circle(x, y, r * 0.96, fill="url(#puff)") for x, y, r in puffs]
    light = [circle(x - r * 0.25, y - r * 0.3, r * 0.5, fill="#ffffff") for x, y, r in puffs if y < cy - 120 * s]
    base = rect(cx - 330 * s, cy + 30 * s, 660 * s, 70 * s, rx=35 * s, fill=shade)
    return [g(shadow + [base], filt="soft"), g(body, filt="soft"), g(light, opacity=0.45, filt="soft")]


def camphor(cx, base, s, rnd, p):
    """The great camphor tree: a thick trunk and a huge rounded crown."""
    leaf, dark = p["leaf"], mix(p["leaf"], "#0d2412", 0.55)
    light = mix(p["leaf"], "#e8f5c8", 0.35)
    out = [path(f"M{f(cx - 60 * s)} {f(base)} C{f(cx - 40 * s)} {f(base - 120 * s)} {f(cx - 50 * s)} {f(base - 230 * s)} "
                f"{f(cx - 20 * s)} {f(base - 330 * s)} L{f(cx + 30 * s)} {f(base - 330 * s)} C{f(cx + 50 * s)} {f(base - 230 * s)} "
                f"{f(cx + 45 * s)} {f(base - 120 * s)} {f(cx + 75 * s)} {f(base)} Z", fill="#4b3a2c")]
    for side in (-1, 1):
        out.append(path(f"M{f(cx)} {f(base - 260 * s)} Q{f(cx + side * 120 * s)} {f(base - 330 * s)} {f(cx + side * 220 * s)} {f(base - 360 * s)}",
                        stroke="#4b3a2c", width=26 * s))
    blobs = []
    for k in range(70):
        a = rnd.random() * math.pi
        rr = rnd.random() ** 0.6
        x = cx + math.cos(a) * 420 * s * rr * (1 if rnd.random() < 0.5 else -1) * 0.95
        y = base - 420 * s - math.sin(a) * 300 * s * rr
        blobs.append((x, y, (70 + rnd.random() * 60) * s))
    out.append(g([circle(x + 8 * s, y + 18 * s, r, fill=dark) for x, y, r in blobs], filt="soft"))
    out.append(g([circle(x, y, r * 0.9, fill=leaf) for x, y, r in blobs], filt="soft"))
    out.append(g([circle(x - r * 0.3, y - r * 0.35, r * 0.45, fill=light) for x, y, r in blobs if y < base - 450 * s],
                 opacity=0.75, filt="soft"))
    return out


def totoro_wallpaper(p):
    rnd = random.Random(1988)
    sky = p["sky"]
    defs = [lgrad("sky", [(0, mix(sky, "#2f6fb0", 0.45), 1), (0.55, sky, 1), (1, "#eef5ea", 1)]),
            lgrad("field", [(0, mix(p["leaf"], "#c9e39a", 0.5), 1), (1, mix(p["leaf"], "#14361a", 0.35), 1)]),
            rgrad("sun", [(0, "#fffbe6", 0.9), (1, "#fffbe6", 0)], 0.25, 0.1, 0.45),
            rgrad("puff", [(0, "#ffffff", 1), (0.55, "#f7f9fc", 1), (0.85, "#d5e1ee", 1), (1, "#b9cbe0", 1)], 0.38, 0.3, 0.7),
            blur("soft", 6), blur("softer", 2.5), blur("haze", 18)]
    body = [rect(0, 0, W, H, fill="url(#sky)"), rect(0, 0, W, H, fill="url(#sun)")]
    body += cloud(560, 640, 1.25, rnd, "#c4d6e6")
    body += cloud(1500, 560, 0.7, rnd, "#c9d9e8")
    body.append(g([ellipse(1100, 230, 260, 28, fill="#ffffff", opacity=0.7), ellipse(260, 180, 200, 22, fill="#ffffff", opacity=0.6)],
                  filt="haze"))
    # Hills, far to near.
    for k, (y, amp, c) in enumerate(((640, 50, mix(sky, "#4a6f8a", 0.45)), (680, 40, mix(p["leaf"], "#7fa0b5", 0.55)),
                                     (712, 26, mix(p["leaf"], "#24502a", 0.35)))):
        body.append(path(smooth(ridge(rnd, y, amp, 80, rough=0.7), closed_to=H), fill=c, filt="softer" if k < 2 else None))
    # Rice paddies: bands widening toward us, water glinting between.
    y = 735
    k = 0
    body.append(rect(0, 730, W, H - 730, fill="url(#field)"))
    while y < H:
        hgt = 6 + (y - 730) * 0.09
        c = mix(p["leaf"], "#d6eda8", 0.35 + 0.12 * rnd.random()) if k % 2 == 0 else mix(p["leaf"], "#1f4d25", 0.1 + 0.15 * rnd.random())
        body.append(path(f"M-20 {f(y)} Q{W / 2} {f(y - 6 - k)} {W + 20} {f(y + 4)} L{W + 20} {f(y + hgt)} Q{W / 2} {f(y + hgt - 6 - k)} -20 {f(y + hgt)} Z",
                         fill=c, opacity=0.85))
        body.append(path(f"M-20 {f(y + hgt)} Q{W / 2} {f(y + hgt - 6 - k)} {W + 20} {f(y + hgt + 4)}",
                         stroke=mix(p["leaf"], "#e8e2b0", 0.5), width=1 + hgt * 0.12, opacity=0.5))
        if k % 3 == 1:
            body.append(path(f"M{f(200 + rnd.random() * 300)} {f(y + hgt * 0.5)} l{f(120 + rnd.random() * 200)} -2",
                             stroke="#e9f6ff", width=1.5 + hgt * 0.08, opacity=0.55))
        y += hgt
        k += 1
    # The tree's hill, the tree, the spirit under it.
    body.append(path(smooth([(700, 1000), (980, 900), (1250, 790), (1520, 745), (1780, 755), (2000, 800)], closed_to=H + 10),
                     fill=mix(p["leaf"], "#2c5a26", 0.3)))
    body.append(path(smooth([(980, 905), (1250, 795), (1520, 750), (1780, 760)]), stroke=mix(p["leaf"], "#d6eda8", 0.4),
                     width=4, opacity=0.5, filt="softer"))
    body += camphor(1560, 765, 0.78, rnd, p)
    body += totoro(1400, 815, 0.85, p)
    # Foreground grass.
    blades = []
    for _ in range(260):
        x = rnd.random() * W
        hgt = 30 + rnd.random() * 80
        lean = (rnd.random() - 0.5) * 40
        c = mix(p["leaf"], "#0f2e14", 0.3 + 0.4 * rnd.random())
        blades.append(path(f"M{f(x - 4)} {H + 4} Q{f(x + lean * 0.3)} {f(H - hgt * 0.6)} {f(x + lean)} {f(H - hgt)} Q{f(x + lean * 0.2)} {f(H - hgt * 0.5)} {f(x + 4)} {H + 4} Z",
                           fill=c))
    body.append(g(blades, filt="softer"))
    return svg(W, H, body, defs)


# ============================================================ Spirited Away
def bathhouse(x0, base, s, p, rnd):
    """The bathhouse: tiers of vermilion walls under flared jade roofs, a
    tall chimney, rows of warm windows, lanterns."""
    wall, roof, glow = mix(p["accent"], "#1a0a10", 0.45), mix(p["leaf"], "#0b1a1c", 0.55), p["glow"]
    out = []
    tiers = [(0, 520, 150), (40, 440, 120), (80, 360, 110), (120, 280, 100), (165, 190, 90)]
    y = base
    lights = []
    for k, (inset, width, height) in enumerate(tiers):
        x = x0 + inset * s
        w, h = width * s, height * s
        out.append(rect(x, y - h, w, h, fill=wall))
        # Windows.
        cols = int(w / (34 * s))
        for c in range(cols):
            for r in range(2):
                if rnd.random() < 0.82:
                    wx = x + 12 * s + c * (w - 24 * s) / cols
                    wy = y - h + 22 * s + r * h * 0.42
                    lights.append(rect(wx, wy, 16 * s, 22 * s, fill=glow, opacity=0.85 + 0.15 * rnd.random()))
        # Roof.
        ry = y - h
        out.append(path(f"M{f(x - 40 * s)} {f(ry + 6 * s)} Q{f(x + w * 0.1)} {f(ry - 10 * s)} {f(x + w * 0.2)} {f(ry - 30 * s)} "
                        f"L{f(x + w * 0.8)} {f(ry - 30 * s)} Q{f(x + w * 0.9)} {f(ry - 10 * s)} {f(x + w + 40 * s)} {f(ry + 6 * s)} Z",
                        fill=roof))
        y = ry - 30 * s
    # Chimney and its smoke.
    cx = x0 + 470 * s
    chimney_top = base - 560 * s
    out.insert(0, rect(cx, chimney_top, 30 * s, 400 * s, fill=mix(wall, "#0b0710", 0.35)))
    smoke = [circle(cx + 15 * s + k * 22 * s, chimney_top - 20 * s - k * 34 * s, (14 + k * 10) * s, fill="#d9cfe0",
                    opacity=0.35 - k * 0.035) for k in range(9)]
    out.insert(0, g(smoke, filt="soft"))
    out.append(g(lights, filt=None))
    # Glow around the lit windows.
    out.append(g(lights, opacity=0.8, filt="glow"))
    # Lanterns along the bridge.
    for k in range(9):
        lx = x0 - 260 * s + k * 40 * s
        out.append(circle(lx, base - 34 * s, 16 * s, fill=glow, opacity=0.5, filt="glow"))
        out.append(ellipse(lx, base - 34 * s, 6 * s, 8 * s, fill=p["accent"]))
    out.append(rect(x0 - 280 * s, base - 14 * s, 300 * s, 10 * s, fill=wall))
    return out


def spirited_wallpaper(p):
    rnd = random.Random(2001)
    horizon = 690
    defs = [lgrad("sky", [(0, "#120f26", 1), (0.45, p["sky"], 1), (0.8, mix(p["cloud"], p["sky"], 0.35), 1), (1, p["cloud"], 1)]),
            lgrad("sea", [(0, mix(p["cloud"], p["sky"], 0.55), 1), (0.25, mix(p["sky"], "#0b0f1e", 0.4), 1), (1, "#07070f", 1)]),
            rgrad("moon", [(0, "#fff6e0", 0.55), (1, "#fff6e0", 0)]),
            blur("soft", 7), blur("softer", 2), blur("glow", 9), blur("haze", 22), blur("ripple", 3.5)]
    body = [rect(0, 0, W, H, fill="url(#sky)")]
    body.append(g([circle(rnd.random() * W, rnd.random() * 420, 0.6 + rnd.random() * 1.4, fill="#fff8e8",
                          opacity=0.3 + rnd.random() * 0.6) for _ in range(140)]))
    body.append(circle(330, 210, 220, fill="url(#moon)"))
    body.append(circle(330, 210, 46, fill="#fbf1dc", opacity=0.95))
    # Long dusk clouds.
    body.append(g([ellipse(300 + k * 360 + rnd.random() * 100, 470 + rnd.random() * 120, 240 + rnd.random() * 120, 14 + rnd.random() * 10,
                           fill=mix(p["cloud"], "#ffffff", 0.2), opacity=0.45) for k in range(6)], filt="haze"))
    # Far islands.
    body.append(path(smooth(ridge(rnd, horizon - 18, 26, 70, rough=0.6), closed_to=horizon + 2), fill=mix(p["sky"], "#0b0a18", 0.45),
                     filt="softer"))
    house = bathhouse(1240, horizon + 4, 1.0, p, rnd)
    scene = []
    # The rails just under the water line, posts, the train.
    rail_y = horizon + 70
    scene.append(rect(-10, rail_y, W + 20, 5, fill="#1b1622"))
    for k in range(-1, 26):
        x = k * 82
        scene.append(rect(x, rail_y - 26, 5, 36, fill="#1b1622"))
    tx = 300
    scene.append(rect(tx, rail_y - 58, 300, 54, rx=10, fill="#3f5b73"))
    scene.append(rect(tx, rail_y - 64, 300, 10, rx=5, fill="#2b3d50"))
    for k in range(7):
        scene.append(rect(tx + 14 + k * 40, rail_y - 48, 28, 22, rx=3, fill=p["glow"], opacity=0.9))
    scene.append(rect(tx + 14, rail_y - 48, 270, 22, fill=p["glow"], opacity=0.25, filt="glow"))
    scene += noface(860, rail_y + 2, 0.42, p)
    # The sea, the scene mirrored in it (the bathhouse about the water
    # line, the train about its rails), then the scene itself.
    body.append(rect(0, horizon + 4, W, H - horizon, fill="url(#sea)"))
    body.append(g([g(house, transform=f"translate(0 {2 * (horizon + 4)}) scale(1 -1)", opacity=0.45),
                   g(scene, transform=f"translate(0 {2 * rail_y}) scale(1 -1)", opacity=0.4)], filt="ripple"))
    body.append(g(house))
    body.append(g(scene))
    body.append(rect(0, horizon + 4, W, 3, fill=p["cloud"], opacity=0.25))
    # Ripples.
    ripples = []
    for _ in range(140):
        y = horizon + 20 + rnd.random() ** 1.6 * (H - horizon)
        x = rnd.random() * W
        w = 20 + (y - horizon) * 0.4 * rnd.random()
        ripples.append(path(f"M{f(x)} {f(y)} l{f(w)} 0", stroke=mix(p["glow"], "#ffffff", 0.3), width=1 + (y - horizon) * 0.004,
                            opacity=0.12 + 0.2 * rnd.random()))
    body.append(g(ripples))
    # The near rail in front of the water.
    body.append(rect(-10, rail_y + 3, W + 20, 3, fill="#0f0c14", opacity=0.6))
    return svg(W, H, body, defs)


# ================================================================== Mononoke
def mononoke_wallpaper(p):
    rnd = random.Random(1997)
    defs = [lgrad("air", [(0, mix(p["sky"], "#a9c9a0", 0.35), 1), (0.6, p["sky"], 1), (1, "#070c08", 1)]),
            lgrad("ray", [(0, "#f4ffd8", 0.35), (1, "#f4ffd8", 0)]),
            blur("soft", 6), blur("softer", 2), blur("mist", 26), blur("far", 10), blur("glow", 6)]
    body = [rect(0, 0, W, H, fill="url(#air)")]
    # Shafts of light through the canopy.
    rays = []
    for k in range(6):
        x = 700 + k * 190 + rnd.random() * 80
        w = 40 + rnd.random() * 70
        rays.append(path(f"M{f(x)} -20 L{f(x + w)} -20 L{f(x - 260 + w * 2)} {H} L{f(x - 360)} {H} Z", fill="url(#ray)"))
    body.append(g(rays, filt="mist"))

    def trunks(n, depth, rnd):
        out = []
        for _ in range(n):
            x = rnd.random() * (W + 200) - 100
            w = (30 + rnd.random() * 40) * (0.4 + depth * 1.6)
            base = 760 + depth * 300
            col = mix(mix(p["sky"], "#a7bfa2", 0.4), "#1e1d15", depth ** 0.7)
            moss = mix(p["leaf"], col, 0.4 + 0.5 * (1 - depth))
            lean = (rnd.random() - 0.5) * 30
            out.append(path(f"M{f(x - w / 2 + lean)} -20 L{f(x + w / 2 + lean)} -20 L{f(x + w / 2)} {f(base - w * 0.6)} "
                            f"Q{f(x + w * 0.9)} {f(base)} {f(x + w * 1.5)} {f(base + 6)} L{f(x - w * 1.5)} {f(base + 6)} "
                            f"Q{f(x - w * 0.9)} {f(base)} {f(x - w / 2)} {f(base - w * 0.6)} Z", fill=col))
            out.append(path(f"M{f(x - w / 2)} {f(base - w * 0.6)} Q{f(x - w * 0.2)} {f(base - w * 2.5)} {f(x - w / 2 + lean * 0.5)} {f(base - w * 6)}",
                            stroke=moss, width=w * 0.25, opacity=0.6))
        return out

    body.append(g(trunks(16, 0.1, rnd), filt="far", opacity=0.55))
    body.append(g([ellipse(W / 2, 700, 1300, 110, fill="#d6e8d0", opacity=0.22)], filt="mist"))
    body.append(g(trunks(10, 0.4, rnd), filt="softer", opacity=0.85))
    body.append(g([ellipse(W / 2 + 200, 860, 1200, 90, fill="#cfe3c8", opacity=0.18)], filt="mist"))
    # The forest floor.
    body.append(path(smooth(ridge(rnd, 900, 40, 90, rough=0.6), closed_to=H + 10), fill=mix(p["leaf"], "#0c1a0d", 0.6)))
    body.append(g(trunks(5, 0.85, rnd)))
    # Ferns.
    ferns = []
    for _ in range(40):
        x, y = rnd.random() * W, 930 + rnd.random() * 160
        for k in range(5):
            a = -math.pi / 2 + (k - 2) * 0.45
            ln = 40 + rnd.random() * 50
            ferns.append(path(f"M{f(x)} {f(y)} Q{f(x + math.cos(a) * ln * 0.5)} {f(y + math.sin(a) * ln * 0.8)} {f(x + math.cos(a) * ln)} {f(y + math.sin(a) * ln * 0.6)}",
                              stroke=mix(p["leaf"], "#0b1a0b", 0.3 + 0.3 * rnd.random()), width=4))
    body.append(g(ferns, filt="softer"))
    # Kodama among the roots and on the moss, near ones bigger.
    spirits = []
    for _ in range(26):
        y = 820 + rnd.random() ** 0.8 * 240
        s = 0.3 + (y - 820) / 240 * 0.8
        x = rnd.random() * W
        spirits += kodama(x, y, s, tilt=(rnd.random() - 0.5) * 70, p=p, glow=p["glow"])
    body.append(g(spirits))
    # Fireflies and spores.
    body.append(g([circle(rnd.random() * W, 300 + rnd.random() * 760, 2 + rnd.random() * 3, fill=p["glow"], opacity=0.5 + 0.5 * rnd.random())
                   for _ in range(70)], filt="glow"))
    body.append(g([circle(rnd.random() * W, 300 + rnd.random() * 760, 1.2, fill="#ffffff", opacity=0.8) for _ in range(60)]))
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
