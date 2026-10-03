#!/usr/bin/env python3
"""Synthesize the Cyberpunk 2077 theme's sounds (themes.json `sounds`): per
variant, a short digital HUD blip for notifications (<variant>-notification.wav, an
incoming text), the Relic malfunctioning for critical ones and the cut-in
(<variant>-critical.wav: the heartbeat, a warped overdriven drone, glitch
tears, a tinnitus whine), and the timers': the Sandevistan kicking in when a
focus session or a break ends (<variant>-focus.wav: a deep whoom as time
slows, a chirp back to speed), breach protocol complete when the countdown
finishes (<variant>-countdown.wav) and a holocall ring the alarm loops
(<variant>-alarm.wav). Made from scratch to sound like the game's own
(band-limited square-ish tones, bit-crushed glitches, noise; ../synth.py for
the mix and the room), no CD Projekt audio. Standard library only, so
the package generates them when it is built (qml.nix): no audio file is kept
in git.
Run: python3 sounds.py [out-dir]   (default: next to this script)
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import synth as S  # noqa: E402

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


def blip(base):
    """Two short HUD blips, the second a fifth up, and a tiny crushed tail."""
    return seq(
        tone(base, 0.05, amp=0.5, decay=40, harmonics=3),
        silence(0.025),
        tone(base * 1.5, 0.09, amp=0.55, decay=28, harmonics=3),
        tone(base * 3, 0.06, amp=0.18, glide=-0.5, decay=40, crush=6),
    )


def holocall(base, seed):
    """The holocall ringing: two bursts of four fast buzzy pulses, each burst
    opened by a glitch, over a low drone; a short gap so the loop pulses."""
    rnd = random.Random(seed)
    out = []
    for burst in range(2):
        for k in range(3):
            out += noise(0.012 + rnd.random() * 0.015, amp=0.3, seed=seed + burst * 10 + k) + silence(0.008)
        pulses = []
        for k in range(4):
            pulses += tone(base * (1.0 if k % 2 == 0 else 1.335), 0.07, amp=0.5, decay=10, harmonics=5) + silence(0.035)
        out += mix(pulses, tone(base / 4, len(pulses) / RATE, amp=0.2, decay=1.5, harmonics=3))
        out += silence(0.18)
    return out + silence(0.3)


# ------------------------------------------------------- the game's sounds
def heartbeat(seed, bpm=72, beats=2):
    """Lub-dub: two muffled low thumps per beat."""
    out = [0.0] * S.n(beats * 60 / bpm + 0.4)
    for b in range(beats):
        for k, (dt, g) in enumerate(((0.0, 1.0), (0.17, 0.7))):
            thump = S.biquad(S.membrane(52 - 6 * k, 0.35, drop=0.3, decay=16, hit=0.2, hit_f=200, seed=seed + b * 2 + k), "lp", 300)
            o = S.n(b * 60 / bpm + dt)
            for i, v in enumerate(thump):
                if o + i < len(out):
                    out[o + i] += g * v
    return out


def distort(sig, drive=4.0):
    return [math.tanh(drive * v) for v in sig]


def relic(base, seed):
    """The Relic malfunctioning: the heartbeat, a warped, overdriven low
    drone, glitch tears, then a tinnitus whine left ringing."""
    rnd = random.Random(seed)
    dur = 2.4
    drone = []
    phase = 0.0
    for i in range(S.n(dur)):
        t = i / RATE
        f = base / 8 * (1 + 0.25 * math.sin(S.TAU * 0.9 * t) + 0.08 * math.sin(S.TAU * 13 * t))
        phase += S.TAU * f / RATE
        drone.append((math.sin(phase) + 0.6 * math.sin(2.01 * phase) + 0.4 * math.sin(3.03 * phase)) * S.adsr(t, dur, 0.25, 0.5))
    drone = S.biquad(distort(drone, 5.0), "lp", 1800)
    tears = []
    t = 0.3
    while t < dur - 0.3:
        d = 0.02 + rnd.random() * 0.07
        part = tone(base * (0.5 + 2 * rnd.random()), d, amp=0.6, glide=(rnd.random() - 0.5) * 3, decay=4, crush=3) \
            if rnd.random() < 0.5 else noise(d, amp=0.5, seed=seed + int(t * 100), decay=8)
        tears.append((t, part, 0.5 + 0.5 * rnd.random(), rnd.random() * 1.6 - 0.8))
        t += d + rnd.random() * 0.12
    whine = [0.05 * math.sin(S.TAU * 6400 * i / RATE) * min(1.0, i / RATE / 0.4) * math.exp(-max(0.0, i / RATE - 0.8) * 1.4)
             for i in range(S.n(2.6))]
    m = S.Mix()
    m.add(heartbeat(seed, beats=2), 0.0, 0.9, 0.0)
    m.add(drone, 0.2, 0.5, 0.0)
    for start, part, g, pan in tears:
        m.add(part, start, g * 0.6, pan)
    m.add(whine, 1.5, 0.7, 0.2)
    return m.reverb(0.18, room=0.75, tail=0.8)


def text_ping(base, seed):
    """An incoming message: a crisp two-step digital chirp and a tiny glitch
    tick, a soft sub under it."""
    m = S.Mix()
    m.add(blip(base), 0.0, 1.0, 0.0)
    m.add(tone(base * 4, 0.025, amp=0.3, decay=60, crush=4), 0.24, 0.6, 0.6)
    m.add(tone(base / 4, 0.18, amp=0.5, decay=14, harmonics=1), 0.0, 0.5, 0.0)
    return m.reverb(0.12, room=0.6, tail=0.4)


def sandevistan(base, seed):
    """The Sandevistan kicking in: a deep "whoom" dropping in pitch as time
    slows (a heartbeat stretched under it), then a crisp chirp back to
    speed."""
    dur = 1.4
    whoom = []
    phase = 0.0
    for i in range(S.n(dur)):
        t = i / RATE
        f = 180 * (0.25 + 0.75 * math.exp(-t * 3.2))
        phase += S.TAU * f / RATE
        whoom.append((math.sin(phase) + 0.3 * math.sin(2 * phase)) * min(1.0, t / 0.02) * math.exp(-t * 1.6))
    air = S.shaped(S.swoosh(dur, seed, 6000, 250, q=1.4), lambda t: 1.0)
    m = S.Mix()
    m.add(S.scale(air, 0.6), 0.0, 1.0, -0.3)
    m.add(whoom, 0.0, 0.9, 0.0)
    m.add(heartbeat(seed + 5, bpm=40, beats=1), 0.25, 0.7, 0.0)
    m.add(tone(base, 0.05, amp=0.5, glide=1.0, decay=30, harmonics=3), 1.45, 0.7, 0.2)
    m.add(tone(base * 2, 0.12, amp=0.5, decay=20, harmonics=3), 1.52, 0.7, 0.2)
    return m.reverb(0.22, room=0.78, tail=0.8)


def breach(base, seed):
    """Breach protocol complete: six quick hex-entry beeps climbing, a
    glitch, and the success tone (a fifth, held)."""
    rnd = random.Random(seed)
    m = S.Mix()
    steps = (0, 3, 5, 7, 10, 12)
    for k, st in enumerate(steps):
        m.add(tone(base * 2 ** (st / 12), 0.045, amp=0.5, decay=35, harmonics=3), k * 0.075, 0.8, -0.5 + 0.2 * k)
    t = len(steps) * 0.075 + 0.04
    for k in range(4):
        m.add(noise(0.012 + rnd.random() * 0.02, amp=0.35, seed=seed + k), t + k * 0.03, 0.6, rnd.random() - 0.5)
    t += 0.16
    m.add(tone(base * 2, 0.5, amp=0.45, decay=4, harmonics=4), t, 0.8, -0.15)
    m.add(tone(base * 3, 0.5, amp=0.35, decay=4, harmonics=4), t, 0.8, 0.15)
    m.add(tone(base / 2, 0.5, amp=0.35, decay=5, harmonics=2), t, 0.8, 0.0)
    return m.reverb(0.15, room=0.7, tail=0.6)


def holocall_mix(base, seed):
    m = S.Mix()
    ring = holocall(base, seed)
    m.add(ring, 0.0, 1.0, 0.0)
    m.pad(len(ring) / RATE)  # keep its rest: the ring pulses when looped
    return m.reverb(0.1, room=0.6, tail=0.3)


VARIANTS = {
    # bright (A5)
    "yellow": dict(blip=880.0, alarm=(880.0, 2077)),
    # lower, harsher (E5)
    "red": dict(blip=659.3, alarm=(659.3, 1337)),
}


def main():
    S.run({name: dict(notification=lambda v=v: text_ping(v["blip"], 7),
                      critical=lambda v=v: relic(*v["alarm"]),
                      focus=lambda v=v: sandevistan(v["blip"], 31),
                      countdown=lambda v=v: breach(v["blip"], 41),
                      alarm=lambda v=v: holocall_mix(*v["alarm"]))
           for name, v in VARIANTS.items()})


if __name__ == "__main__":
    main()
