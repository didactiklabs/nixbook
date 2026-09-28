#!/usr/bin/env python3
"""Synthesize the Chiikawa theme's sounds (themes.json `sounds`): per variant,
a short bubbly notification chime (<variant>-notification.wav) and a playful
jingle for critical notifications (<variant>-critical.wav). Soft bell-like
tones (sine + a little second harmonic, fast attack, exponential decay) and
little pitch hops; nothing harsh. Standard library only, so the package
generates them when it is built (qml.nix): no audio file is kept in git.
Run: python3 sounds.py [out-dir]   (default: next to this script)
"""
import math
import os
import struct
import sys
import wave

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


def write(path, samples, fade=0.02):
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = 0.8 / peak
    n = len(samples)
    fn = int(fade * RATE)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for i, s in enumerate(samples):
            g = gain * (min(1.0, (n - i) / fn) if fn else 1.0)
            frames += struct.pack("<h", int(max(-1, min(1, s * g)) * 32767))
        w.writeframes(bytes(frames))


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


VARIANTS = {
    # sweet, mid (C6 / hop a fourth)
    "chiikawa": dict(chime=(1046.5, 1.335), jingle=(1046.5, 6.0)),
    # airy, higher (E6 / hop a fifth)
    "momonga": dict(chime=(1318.5, 1.5), jingle=(1318.5, 7.5)),
    # bouncy, lower (G5 / hop an octave: "yaha!")
    "usagi": dict(chime=(784.0, 2.0), jingle=(784.0, 5.0)),
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    for name, v in VARIANTS.items():
        write(os.path.join(out, f"{name}-notification.wav"), chime(*v["chime"]))
        write(os.path.join(out, f"{name}-critical.wav"), jingle(*v["jingle"]))


if __name__ == "__main__":
    main()
