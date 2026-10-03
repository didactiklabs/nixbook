#!/usr/bin/env python3
"""Make friends.gif: Momonga (momonga.gif, every frame pasted as is, not
redrawn) with Chiikawa swaying on his left and Usagi hopping on his right,
drawn here in the same line art (Momonga's own ink and blush) and animated
on the GIF's 22 frames (50 ms each: a 1.1 s loop).

Momonga's pixels keep their exact colours: the friends are drawn from
Momonga's palette plus a few yellows for Usagi, so the frames are not
requantized. Committed, not built: rerun after changing the drawing
(needs Pillow and resvg on PATH):
  nix shell nixpkgs#resvg --impure --expr \\
    'with import (builtins.getFlake "nixpkgs") {}; python3.withPackages (p: [p.pillow])' \\
    -c python3 friends.py
"""
import math
import os
import subprocess
import tempfile

from PIL import Image, ImageSequence

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = 26          # headroom above Momonga's frame, for Usagi's ears mid-hop
W, H = 460, 151 + TOP
MOMONGA_X = 130   # where Momonga's 200x151 frame goes (at y = TOP)
GROUND = 143 + TOP  # Momonga's feet

INK = "#44242c"
WHITE = "#fef7fc"
BLUSH = "#efaec3"
BLUSH_LINE = "#e29ab1"
MOUTH = "#ca7290"
YELLOW = "#f9eeb2"
YELLOW_SHADE = "#f2df8a"
LINE = 3.0


def f(x):
    return f"{x:.2f}".rstrip("0").rstrip(".")


def ellipse(cx, cy, rx, ry, fill, stroke=True, rot=0):
    t = f' transform="rotate({f(rot)} {f(cx)} {f(cy)})"' if rot else ""
    s = f' stroke="{INK}" stroke-width="{LINE}"' if stroke else ""
    return f'<ellipse cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}" fill="{fill}"{s}{t}/>'


def path(d, fill="none", stroke=INK, width=LINE):
    s = f' stroke="{stroke}" stroke-width="{f(width)}" stroke-linecap="round" stroke-linejoin="round"' if stroke else ""
    return f'<path d="{d}" fill="{fill}"{s}/>'


def group(body, transform):
    return f'<g transform="{transform}">' + "".join(body) + "</g>"


def blush(cx, cy):
    """A pink cheek with the three little hatch lines."""
    out = [ellipse(cx, cy, 7, 4.2, BLUSH, stroke=False)]
    for k in (-1, 0, 1):
        x = cx + k * 3.6
        out.append(path(f"M{f(x - 1.2)} {f(cy + 1.8)} L{f(x + 1.2)} {f(cy - 1.8)}", stroke=BLUSH_LINE, width=1.1))
    return out


def chiikawa(k):
    """Chiikawa: a round white mochi with small round ears, sways from side
    to side, bounces a little and waves."""
    phase = math.tau * k / 22
    cx, gy = 68, GROUND
    sway = 5 * math.sin(phase)
    bounce = -3 * abs(math.sin(phase))
    wave = 28 * math.sin(2 * phase)
    out = []
    # Feet.
    for side in (-1, 1):
        out.append(ellipse(cx + side * 12, gy - 4, 9, 5, WHITE))
    body = []
    # Arms (behind the body): the right one waves.
    body.append(group([ellipse(cx - 27, gy - 32, 6, 10, WHITE)], f"rotate(20 {f(cx - 24)} {f(gy - 38)})"))
    body.append(group([ellipse(cx + 27, gy - 36, 6, 10, WHITE)], f"rotate({f(-30 + wave)} {f(cx + 24)} {f(gy - 40)})"))
    # Ears, body, head; then fills again without lines to merge them.
    for side in (-1, 1):
        body.append(ellipse(cx + side * 22, gy - 96, 9, 9, WHITE))
    body.append(ellipse(cx, gy - 28, 26, 23, WHITE))
    body.append(ellipse(cx, gy - 68, 38, 31, WHITE))
    body.append(ellipse(cx, gy - 28, 24.5, 21.5, WHITE, stroke=False))
    body.append(ellipse(cx, gy - 68, 36.5, 29.5, WHITE, stroke=False))
    # Face.
    for side in (-1, 1):
        body.append(ellipse(cx + side * 13, gy - 70, 3.4, 4.4, INK, stroke=False))
        body.append(ellipse(cx + side * 13 + 1.1, gy - 71.8, 1.1, 1.3, "#ffffff", stroke=False))
        body += blush(cx + side * 24, gy - 59)
    body.append(path(f"M{f(cx - 4)} {f(gy - 59)} Q{f(cx - 2)} {f(gy - 56.5)} {f(cx)} {f(gy - 59)} "
                     f"Q{f(cx + 2)} {f(gy - 56.5)} {f(cx + 4)} {f(gy - 59)}", width=1.8))
    out.append(group(body, f"translate(0 {f(bounce)}) rotate({f(sway)} {f(cx)} {f(gy)})"))
    return out


def usagi(k):
    """Usagi: a pale yellow rabbit, long ears, mouth wide open, arms up,
    hopping twice per loop (squashing a little when it lands)."""
    phase = math.tau * k / 11
    cx, gy = 392, GROUND
    air = max(0.0, math.sin(phase))
    lift = -13 * air
    squash = 1 - 0.07 * (1 - air) * (1 if math.sin(phase) < 0.15 else 0)
    ear_lag = 7 * math.cos(phase)
    arms = 18 * air
    out = []
    for side in (-1, 1):
        out.append(ellipse(cx + side * 12, gy - 4 + lift * 0.6, 9, 5, YELLOW))
    body = []
    # Ears, flopping behind the hop.
    for side in (-1, 1):
        body.append(group([ellipse(cx + side * 12, gy - 108, 8.5, 25, YELLOW),
                           ellipse(cx + side * 12, gy - 104, 3.2, 16, YELLOW_SHADE, stroke=False)],
                          f"rotate({f(side * (8 + ear_lag))} {f(cx + side * 12)} {f(gy - 86)})"))
    # Arms up (behind the body), higher in the air.
    for side in (-1, 1):
        body.append(group([ellipse(cx + side * 27, gy - 44, 6, 11, YELLOW)],
                          f"rotate({f(side * (40 + arms))} {f(cx + side * 22)} {f(gy - 36)})"))
    body.append(ellipse(cx, gy - 28, 25, 23, YELLOW))
    body.append(ellipse(cx, gy - 66, 34, 28, YELLOW))
    body.append(ellipse(cx, gy - 28, 23.5, 21.5, YELLOW, stroke=False))
    body.append(ellipse(cx, gy - 66, 32.5, 26.5, YELLOW, stroke=False))
    # Face: dot eyes, the big open mouth, blush.
    for side in (-1, 1):
        body.append(ellipse(cx + side * 11, gy - 70, 3, 3.4, INK, stroke=False))
        body += blush(cx + side * 22, gy - 59)
    open_ = 9 + 3 * air
    body.append(path(f"M{f(cx - 10)} {f(gy - 61)} L{f(cx + 10)} {f(gy - 61)} "
                     f"Q{f(cx + 9)} {f(gy - 61 + open_)} {f(cx)} {f(gy - 61 + open_)} "
                     f"Q{f(cx - 9)} {f(gy - 61 + open_)} {f(cx - 10)} {f(gy - 61)} Z", fill=MOUTH, width=2))
    out.append(group(body, f"translate(0 {f(lift)}) translate({f(cx)} {f(gy)}) scale(1 {f(squash)}) translate({f(-cx)} {f(-gy)})"))
    return out


def svg(k):
    body = chiikawa(k) + usagi(k)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">' + "".join(body) + "</svg>\n"


def hexrgb(c):
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def main():
    src = Image.open(os.path.join(HERE, "momonga.gif"))
    frames = [fr.convert("RGBA") for fr in ImageSequence.Iterator(src)]
    duration = src.info.get("duration", 50)

    # The palette: Momonga's colours as they are, Usagi's yellows (and their
    # blends with the ink), and a key colour for the transparency.
    colours = []
    for fr in frames:
        for _, c in fr.getcolors(1 << 20):
            if c[3] and c[:3] not in colours:
                colours.append(c[:3])
    extra = [hexrgb(YELLOW), hexrgb(YELLOW_SHADE)]
    for t in (0.25, 0.5, 0.75):
        a, b = hexrgb(YELLOW), hexrgb(INK)
        extra.append(tuple(round(x + (y - x) * t) for x, y in zip(a, b)))
    colours += [c for c in extra if c not in colours]
    key = (0, 255, 0)
    colours.append(key)
    assert len(colours) <= 256, len(colours)
    pal = Image.new("P", (1, 1))
    flat = [v for c in colours for v in c]
    pal.putpalette(flat + [0] * (768 - len(flat)))
    key_index = len(colours) - 1
    exact = {c: i for i, c in enumerate(colours)}

    def index_of(c):
        """Exact colours keep their entry (all of Momonga's); a friend's
        anti-aliased edge takes the nearest colour (not the key)."""
        if c not in exact:
            exact[c] = min(range(len(colours) - 1), key=lambda i: sum((a - b) ** 2 for a, b in zip(c, colours[i])))
        return exact[c]

    out = []
    with tempfile.TemporaryDirectory() as tmp:
        for k, momonga in enumerate(frames):
            svg_path = os.path.join(tmp, f"{k}.svg")
            png_path = os.path.join(tmp, f"{k}.png")
            with open(svg_path, "w", encoding="utf-8") as fh:
                fh.write(svg(k))
            subprocess.run(["resvg", svg_path, png_path], check=True)
            friends = Image.open(png_path).convert("RGBA")
            # Hard edges like Momonga's: half-covered pixels are drawn.
            alpha = friends.getchannel("A").point(lambda a: 255 if a >= 110 else 0)
            canvas = Image.new("RGB", (W, H), key)
            canvas.paste(friends.convert("RGB"), (0, 0), alpha)
            # Momonga on top: his own pixels.
            canvas.paste(momonga.convert("RGB"), (MOMONGA_X, TOP), momonga.getchannel("A"))
            frame = Image.new("P", (W, H))
            frame.putpalette(pal.getpalette())
            frame.putdata([index_of(c) for c in canvas.get_flattened_data()])
            out.append(frame)
    out[0].save(os.path.join(HERE, "friends.gif"), save_all=True, append_images=out[1:], duration=duration,
                loop=0, transparency=key_index, disposal=2, optimize=False)

    # Check: Momonga is untouched.
    check = Image.open(os.path.join(HERE, "friends.gif"))
    for k, fr in enumerate(ImageSequence.Iterator(check)):
        got = fr.convert("RGBA").crop((MOMONGA_X, TOP, MOMONGA_X + 200, H))
        want = frames[k]
        for (g, w) in zip(got.get_flattened_data(), want.get_flattened_data()):
            if w[3] and g != w:
                raise SystemExit(f"frame {k}: Momonga changed ({w} -> {g})")
    print(f"friends.gif: {len(out)} frames, {len(colours)} colours, Momonga untouched")


if __name__ == "__main__":
    main()
