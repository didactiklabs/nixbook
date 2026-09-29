#!/usr/bin/env python3
"""Synthesize the Cyberpunk 2077 theme's sounds (themes.json `sounds`): per
variant, a short digital HUD blip for notifications (<variant>-notification.wav)
and a glitchy incoming-call alarm for critical ones and the cut-in
(<variant>-critical.wav). Band-limited square-ish tones, a stutter of noise
bursts, a bit-crushed downward chirp; short and dry. Standard library only, so
the package generates them when it is built (qml.nix): no audio file is kept
in git.
Run: python3 sounds.py [out-dir]   (default: next to this script)
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 44100


def tone(freq, dur, amp=0.5, glide=0.0, decay=10.0, harmonics=5, crush=0):
    """A buzzy note: odd harmonics (a softened square), `glide` bends the
    pitch by that ratio over the note, `crush` quantizes the samples to that
    many levels (0: off) for the 8-bit edge."""
    out = []
    phase = 0.0
    n = int(dur * RATE)
    norm = sum(1 / k for k in range(1, 2 * harmonics, 2))
    for i in range(n):
        t = i / RATE
        f = freq * (1 + glide * (t / dur))
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / 0.003) * math.exp(-decay * t)
        s = sum(math.sin(k * phase) / k for k in range(1, 2 * harmonics, 2)) / norm
        if crush:
            s = round(s * crush) / crush
        out.append(amp * env * s)
    return out


def noise(dur, amp=0.3, seed=0, decay=30.0):
    rnd = random.Random(seed)
    return [amp * math.exp(-decay * i / RATE) * (rnd.random() * 2 - 1) for i in range(int(dur * RATE))]


def silence(dur):
    return [0.0] * int(dur * RATE)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def write(path, samples, fade=0.01):
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = 0.75 / peak
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


def blip(base):
    """Two short HUD blips, the second a fifth up, and a tiny crushed tail."""
    return seq(
        tone(base, 0.05, amp=0.5, decay=40, harmonics=3),
        silence(0.025),
        tone(base * 1.5, 0.09, amp=0.55, decay=28, harmonics=3),
        tone(base * 3, 0.06, amp=0.18, glide=-0.5, decay=40, crush=6),
    )


def alarm(base, seed):
    """The holocall: a stutter of glitch (noise and crushed buzz slices), a
    fast rising sweep, then three ringing beeps, the last one held."""
    stutter = []
    rnd = random.Random(seed)
    for k in range(6):
        d = 0.018 + rnd.random() * 0.03
        part = noise(d, amp=0.35, seed=seed + k) if k % 2 == 0 else tone(base * (0.5 + rnd.random()), d, amp=0.4, decay=5, crush=4)
        stutter += part + silence(0.012 + rnd.random() * 0.02)
    sweep = tone(base / 2, 0.16, amp=0.4, glide=2.0, decay=4, harmonics=4, crush=10)
    beeps = seq(
        tone(base, 0.08, amp=0.5, decay=14), silence(0.05),
        tone(base, 0.08, amp=0.5, decay=14), silence(0.05),
        tone(base * 1.335, 0.32, amp=0.55, decay=5),
    )
    sub = tone(base / 4, 0.5, amp=0.25, decay=6, harmonics=2)
    return seq(stutter, sweep, silence(0.03), mix(beeps, sub))


VARIANTS = {
    # bright (A5)
    "yellow": dict(blip=880.0, alarm=(880.0, 2077)),
    # lower, harsher (E5)
    "red": dict(blip=659.3, alarm=(659.3, 1337)),
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    for name, v in VARIANTS.items():
        write(os.path.join(out, f"{name}-notification.wav"), blip(v["blip"]))
        write(os.path.join(out, f"{name}-critical.wav"), alarm(*v["alarm"]))


if __name__ == "__main__":
    main()
