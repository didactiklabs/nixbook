#!/usr/bin/env python3
"""Draw the Cyberpunk 2077 theme's wallpapers (<variant>-wallpaper.svg,
1920x1080) from the variants' palettes in modules/common/themes.json: a Night
City skyline with lit windows over a perspective grid, a hazard-striped band,
torn glitch bars in the RGB-split colours and HUD brackets. No text (the
package rasterises them with resvg, without fonts: qml.nix).

  yellow  the key art: a signature yellow sky, the city in black
  red     the HUD: a red-black night, the city outlined in neon red

Seeded: rerunning gives the same pictures. Run after changing the palettes:
  python3 generate.py
"""
import json
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1920, 1080
HORIZON = 760


def palettes():
    with open(os.path.join(HERE, "../../modules/common/themes.json"), encoding="utf-8") as f:
        registry = json.load(f)
    theme = next(t for t in registry["themes"] if t["id"] == "cyberpunk")
    return {v["id"]: v["palette"] for v in theme["variants"]}


def rect(x, y, w, h, fill, opacity=1.0, extra=""):
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" fill="{fill}" opacity="{opacity:.2f}"{extra}/>'


def wallpaper(vid, p):
    rnd = random.Random(2077)
    bright = vid == "yellow"
    sky_top, sky_bottom = (p["primary"], "#c9bd00") if bright else (p["background"], p["surface3"])
    city = p["background"]
    edge = p["background"] if bright else p["primary"]
    lit = [p["background"], p["secondary"]] if bright else [p["primary"], p["secondary"], p["tertiary"]]
    grid = p["background"] if bright else p["primary"]

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
           "<defs>",
           f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{sky_top}"/><stop offset="1" stop-color="{sky_bottom}"/></linearGradient>',
           f'<radialGradient id="glow" cx="0.62" cy="0.7" r="0.6"><stop offset="0" stop-color="{p["primary"]}" stop-opacity="{0.0 if bright else 0.35}"/><stop offset="1" stop-color="{p["primary"]}" stop-opacity="0"/></radialGradient>',
           f'<pattern id="hazard" width="40" height="40" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="20" height="40" fill="{p["background"]}"/></pattern>',
           f'<pattern id="scan" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="4" height="2" fill="#000000" opacity="0.10"/></pattern>',
           "</defs>",
           rect(0, 0, W, H, "url(#sky)"),
           rect(0, 0, W, H, "url(#glow)")]

    # A huge sun-like disc behind the city, cut by horizontal slits.
    cx, cy, r = 1240, HORIZON - 120, 300
    disc = p["tertiary"] if bright else p["primary"]
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{disc}" opacity="{0.9 if bright else 0.55}"/>')
    for k in range(9):
        y = cy + 30 + k * 30
        out.append(rect(cx - r, y, 2 * r, 4 + k * 1.6, sky_bottom if bright else p["surface3"]))

    # Far skyline (faint), then the near one with windows and antennas.
    for layer, (base, hmin, hmax, op) in enumerate([(HORIZON, 120, 360, 0.45), (HORIZON + 20, 160, 560, 1.0)]):
        x = -20
        while x < W:
            bw = rnd.randint(50, 150)
            bh = rnd.randint(hmin, hmax)
            if layer == 1 and 700 < x < 980:  # a tower (Arasaka-ish) in the middle
                bw, bh = 150, 640
            top = base - bh
            out.append(rect(x, top, bw, H - top, city, op))
            if layer == 1:
                out.append(rect(x, top, bw, 2, edge, 0.9))
                out.append(rect(x, top, 2, bh, edge, 0.5))
                if rnd.random() < 0.35:
                    ax = x + rnd.randint(10, bw - 10)
                    out.append(rect(ax, top - 60, 3, 60, city))
                    out.append(rect(ax - 2, top - 64, 7, 5, p["tertiary"] if not bright else p["secondary"]))
                for wy in range(top + 14, base - 10, 16):
                    for wx in range(x + 8, x + bw - 10, 14):
                        if rnd.random() < 0.18:
                            out.append(rect(wx, wy, 7, 4, rnd.choice(lit), 0.55 + rnd.random() * 0.4))
            x += bw + rnd.randint(-10, 6)

    # Perspective grid floor.
    floor = HORIZON + 20
    out.append(rect(0, floor, W, H - floor, city))
    for k in range(1, 14):
        y = floor + (H - floor) * (k / 13) ** 1.8
        out.append(rect(0, y, W, 1.5, grid if not bright else p["primary"], 0.35))
    for k in range(-24, 25):
        x2 = W / 2 + k * 160
        out.append(f'<line x1="{W / 2 + k * 18:.1f}" y1="{floor}" x2="{x2:.1f}" y2="{H}" stroke="{p["primary"]}" stroke-width="1.5" opacity="0.3"/>')

    # Hazard band across the bottom left: a slanted accent slab, then black
    # stripes on the accent.
    out.append(f'<polygon points="0,{H - 170} 620,{H - 170} 560,{H - 120} 0,{H - 120}" fill="{p["primary"]}" opacity="0.95"/>')
    out.append(f'<polygon points="0,{H - 110} 540,{H - 110} 500,{H - 80} 0,{H - 80}" fill="{p["primary"]}"/>')
    out.append(f'<polygon points="0,{H - 110} 540,{H - 110} 500,{H - 80} 0,{H - 80}" fill="url(#hazard)"/>')

    # Torn glitch bars in the split colours.
    for k in range(16):
        y = rnd.randint(40, H - 40)
        x = rnd.randint(-100, W - 200)
        out.append(rect(x, y, rnd.randint(120, 700), rnd.choice([2, 3, 5, 8, 14]),
                        rnd.choice([p["secondary"], p["tertiary"], p["primary"]]), 0.35 + rnd.random() * 0.45))

    # HUD brackets and a barcode, top left and bottom right.
    ink = p["background"] if bright else p["primary"]
    # (the bottom one is on the dark floor: in the accent)
    for (x, y, sx, sy, c) in [(60, 60, 1, 1, ink), (W - 60, H - 60, -1, -1, p["primary"])]:
        out.append(f'<path d="M{x},{y + 90 * sy} L{x},{y} L{x + 90 * sx},{y}" fill="none" stroke="{c}" stroke-width="5"/>')
    bx = 90
    for k, w in enumerate([3, 1, 2, 1, 4, 1, 1, 3, 2, 1, 1, 4, 2, 1, 3, 1, 2, 2, 1, 3]):
        out.append(rect(bx, 90, w * 2, 36, ink, 0.85))
        bx += w * 2 + 3
    out.append(rect(90, 134, 240, 4, p["secondary"], 0.9))

    out.append(rect(0, 0, W, H, "url(#scan)"))
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main():
    for vid, p in palettes().items():
        with open(os.path.join(HERE, f"{vid}-wallpaper.svg"), "w", encoding="utf-8") as f:
            f.write(wallpaper(vid, p))


if __name__ == "__main__":
    main()
