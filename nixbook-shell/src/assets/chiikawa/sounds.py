#!/usr/bin/env python3
"""Synthesize the Chiikawa theme's sounds (themes.json `sounds`): per variant,
a short bubbly notification chime (<variant>-notification.wav), a playful
jingle for critical notifications (<variant>-critical.wav), and the timers':
a "pin-pon" when a focus session or a break ends (<variant>-focus.wav), a
"done!" when the countdown finishes (<variant>-countdown.wav) and a music-box
tune the alarm loops (<variant>-alarm.wav). Soft bell-like
tones (sine + a little second harmonic, fast attack, exponential decay) and
little pitch hops, nothing harsh — and over them the characters' own little
voices, made from scratch (formant speech at a tiny creature's pitch,
../synth.py speak()): Usagi's "yaha!", "ura!" and "pururururu", Chiikawa's
startled "wa!", Momonga's bossy "hya!". Standard library only, so the
package generates them when it is built (qml.nix): no audio file is kept in
git.
Run: python3 sounds.py [out-dir]   (default: next to this script)
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import synth as S  # noqa: E402

RATE = 44100


def tone(freq, dur, amp=0.5, glide=0.0, vibrato=0.0, attack=0.006, decay=6.0, harmonic=0.28):
    """A bell-ish note: `glide` bends the pitch by that ratio over the note,
    `vibrato` wobbles it (Hz), `decay` is the exponential fade rate."""
    out = []
    phase = 0.0
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        f = freq * (1 + glide * (t / dur))
        if vibrato:
            f *= 1 + 0.012 * math.sin(2 * math.pi * vibrato * t)
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / attack) * math.exp(-decay * t)
        s = math.sin(phase) + harmonic * math.sin(2 * phase) + 0.08 * math.sin(3 * phase)
        out.append(amp * env * s / (1 + harmonic + 0.08))
    return out


def silence(dur):
    return [0.0] * int(dur * RATE)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def seq(*parts, overlap=0.0):
    """Notes one after the other, each starting `overlap` s before the
    previous one ends (a little legato)."""
    out = []
    ov = int(overlap * RATE)
    for p in parts:
        start = max(0, len(out) - ov)
        out.extend([0.0] * max(0, start + len(p) - len(out)))
        for i, s in enumerate(p):
            out[start + i] += s
    return out


def chime(base, hop):
    """Two quick notes, the second hopping up with a tiny upward bend: "pyon"."""
    return seq(
        tone(base, 0.16, amp=0.55, decay=14),
        tone(base * hop, 0.34, amp=0.6, glide=0.03, decay=7),
        overlap=0.07,
    )


def jingle(base, vib):
    """A rising arpeggio played twice, the second time with a top note that
    wobbles: cheerful, clearly "look at me", still soft."""
    notes = [1.0, 1.26, 1.5]
    first = seq(*[tone(base * r, 0.14, amp=0.5, decay=12) for r in notes], overlap=0.03)
    second = seq(*[tone(base * r, 0.13, amp=0.5, decay=12) for r in notes],
                 tone(base * 2, 0.55, amp=0.6, vibrato=vib, decay=4), overlap=0.03)
    boing = tone(base / 2, 0.22, amp=0.35, glide=1.0, decay=10, harmonic=0.1)
    return mix(boing, seq(silence(0.06), first, silence(0.05), second))


def pinpon(base):
    """The two-note door chime, high then a fourth down, soft and round."""
    return seq(
        tone(base * 1.335, 0.5, amp=0.55, decay=4.5),
        tone(base, 0.9, amp=0.55, decay=3.5),
        overlap=0.18,
    )


def done(base, hop):
    """A quick tumble down a pentatonic scale, then the variant's hop up with
    a little wobble: "yatta!"."""
    run = seq(*[tone(base * r, 0.1, amp=0.45, decay=16) for r in (2.0, 1.682, 1.498, 1.335, 1.122)], overlap=0.02)
    return seq(run, silence(0.03), tone(base, 0.12, amp=0.5, decay=12),
               tone(base * hop, 0.6, amp=0.6, vibrato=6, decay=4.5), overlap=0.03)


def music_box(base, tune):
    """A music-box melody (high, plinky, fast decay) over soft low notes on
    the downbeats; ends with a rest so the loop breathes."""
    step = 0.2
    notes = [(k * step, tone(base * r, 0.45, amp=0.45, decay=7, harmonic=0.45)) for k, r in enumerate(tune)]
    lows = [(k * step * 4, tone(base / 2 * r, 0.8, amp=0.25, decay=3, harmonic=0.1))
            for k, r in enumerate((1.0, 1.335, 1.498, 1.0))]
    out = [0.0] * int((len(tune) * step + 0.35) * RATE)
    for start, samples in notes + lows:
        o = int(start * RATE)
        for i, s in enumerate(samples):
            if o + i < len(out):
                out[o + i] += s
    return out


# A little tune per character, as ratios of the base note (major pentatonic).
TUNES = {
    "chiikawa": (1, 1.122, 1.26, 1.498, 1.26, 1.122, 1, 0.749, 0.841, 1, 1.122, 1.26, 1.122, 1, 0.749, 1),
    "momonga": (1.498, 1.682, 2, 1.682, 1.498, 1.26, 1.498, 2, 2.245, 2, 1.682, 1.498, 1.26, 1.122, 1.26, 1.498),
    "usagi": (1, 1, 1.498, 1.498, 2, 1.498, 1.26, 1.498, 1, 1, 1.498, 1.682, 2, 2.245, 2, 1),
}

VARIANTS = {
    # sweet, mid (C6 / hop a fourth)
    "chiikawa": dict(chime=(1046.5, 1.335), jingle=(1046.5, 6.0)),
    # airy, higher (E6 / hop a fifth)
    "momonga": dict(chime=(1318.5, 1.5), jingle=(1318.5, 7.5)),
    # bouncy, lower (G5 / hop an octave: "yaha!")
    "usagi": dict(chime=(784.0, 2.0), jingle=(784.0, 5.0)),
}


# --------------------------------------------------------------- voices
# The characters' own little voices, built from scratch (formant speech at a
# tiny creature's pitch), over the chimes.
def yaha(f=720.0, long=False):
    """Usagi: "ya-ha!" — a shout jumping up."""
    return S.speak([dict(dur=0.13, f0=f, to=f * 1.08, v="a", frm="y", glide=0.5, gap=0.02),
                    dict(dur=0.42 if long else 0.2, f0=f * 1.2, to=f * (1.25 if long else 1.45), v="a", onset="h",
                         release=0.12 if long else 0.03)], size=1.45, seed=1, rasp=0.25)


def ura(f=700.0):
    """Usagi: "u-ra!"."""
    return S.speak([dict(dur=0.1, f0=f, to=f * 1.05, v="u", gap=0.0),
                    dict(dur=0.2, f0=f * 1.25, to=f * 1.45, v="a", frm="e", onset="r", glide=0.3, release=0.03)],
                   size=1.45, seed=2, rasp=0.3)


def pururu(f=700.0, dur=0.9):
    """Usagi: "pururururu" — a rolled r on a long u, wobbling."""
    return S.speak([dict(dur=dur, f0=f * 1.1, to=f * 0.95, v="u", onset="p", trill=26, release=0.1)],
                   size=1.45, seed=3, rasp=0.15)


def wa(f=900.0, soft=False):
    """Chiikawa: "wa!" — small, startled."""
    return S.speak([dict(dur=0.24 if soft else 0.2, f0=f, to=f * (1.08 if soft else 1.25), v="a", frm="w", glide=0.45,
                         release=0.09 if soft else 0.04)], size=1.6, seed=4, breath=0.25)


def hya(f=1000.0, long=False):
    """Momonga: "hya!" — high and bossy."""
    return S.speak([dict(dur=0.45 if long else 0.18, f0=f * 1.05, to=f * (1.4 if long else 1.2), v="a", frm="y",
                         onset="h", glide=0.4, release=0.15 if long else 0.03)], size=1.65, seed=5, rasp=0.35)


def hm(f, v="n", rise=1.2):
    """A little "hm?" / "un!": a short hum, rising (a question) or not."""
    return S.speak([dict(dur=0.2, f0=f, to=f * rise, v=v, release=0.06)], size=1.5, seed=6, breath=0.2)


def mixed(*parts, wet=0.16):
    m = S.Mix()
    for start, sig, gain, pan in parts:
        m.add(sig, start, gain, pan)
    return m.reverb(wet, room=0.7, tail=0.6)


def sounds(name):
    v = VARIANTS[name]
    base, hop = v["chime"]
    if name == "usagi":
        hello, shout, ask, cheer = yaha(), [(0.0, ura()), (0.36, ura(760)), (0.8, pururu())], hm(560, "a", 1.5), yaha(700, long=True)
    elif name == "chiikawa":
        hello, shout, ask, cheer = wa(), [(0.0, wa(880)), (0.42, wa(980))], hm(800, "n", 1.15), wa(950, soft=True)
    else:
        hello, shout, ask, cheer = hya(), [(0.0, hya(1000)), (0.3, hya(1050, long=True))], hm(900, "n", 1.3), hya(1050, long=True)
    alarm = music_box(base / 2, TUNES[name])
    return dict(
        notification=lambda: mixed((0.0, chime(*v["chime"]), 0.6, -0.15), (0.12, hello, 0.9, 0.15)),
        critical=lambda: mixed((0.0, jingle(*v["jingle"]), 0.6, -0.2), *[(t, s, 0.95, 0.15) for t, s in shout]),
        focus=lambda: mixed((0.0, pinpon(base / 2), 0.8, -0.1), (1.0, ask, 0.8, 0.2)),
        countdown=lambda: mixed((0.0, done(base / 2, hop), 0.75, -0.1), (0.75, cheer, 0.9, 0.2)),
        alarm=lambda: mixed((0.0, alarm, 0.85, 0.0), (len(alarm) / RATE - 0.55, hello, 0.6, 0.3), wet=0.12),
    )


def main():
    S.run({name: sounds(name) for name in VARIANTS})


if __name__ == "__main__":
    main()
