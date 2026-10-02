#!/usr/bin/env python3
"""Synthesize the Persona theme's timer sounds (themes.json `sounds`): per
variant, a cue when a focus session or a break ends (<variant>-focus.wav),
one when the countdown finishes (<variant>-countdown.wav) and a ringtone
the alarm loops (<variant>-alarm.wav). Original sounds in the spirit of each
game's music, no Atlus audio: P5 acid jazz (electric piano minor-ninth stabs,
walking bass, brushed hats), P3R calm (soft piano arpeggios in a minor key),
P4 bright funky pop (major-seventh stabs, octave bass, claps). Standard
library only, so the package generates them when it is built (qml.nix): no
audio file is kept in git. The notification chime and the cut-in keep the
registry's sounds (assets/sounds).
Run: python3 sounds.py [out-dir]   (default: next to this script)
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 44100
# The alarms' last notes ring out this long after the loop's final beat
# (TimerService replays them once they end).
RING_OUT = 0.5


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def epiano(freq, dur, amp=0.4, decay=3.5, bright=1.6):
    """A Rhodes-ish note: a sine carrier frequency-modulated by a sine whose
    depth fades fast (the bell-like attack), then a mellow body."""
    out = []
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        mod = bright * math.exp(-9 * t) * math.sin(2 * math.pi * freq * t)
        env = min(1.0, t / 0.004) * math.exp(-decay * t)
        out.append(amp * env * math.sin(2 * math.pi * freq * t + mod))
    return out


def piano(freq, dur, amp=0.4, decay=2.2):
    """A soft piano-ish note: a few harmonics, the higher ones fading faster."""
    out = []
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        s = (math.sin(2 * math.pi * freq * t)
             + 0.35 * math.exp(-3 * t) * math.sin(4 * math.pi * freq * t)
             + 0.12 * math.exp(-6 * t) * math.sin(6 * math.pi * freq * t))
        out.append(amp * min(1.0, t / 0.008) * math.exp(-decay * t) * s / 1.47)
    return out


def bass(freq, dur, amp=0.45, decay=5.0):
    """A plucked upright/electric bass: fundamental plus a fading second
    harmonic and a soft thump at the start."""
    out = []
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        s = math.sin(2 * math.pi * freq * t) + 0.4 * math.exp(-12 * t) * math.sin(4 * math.pi * freq * t)
        out.append(amp * min(1.0, t / 0.003) * math.exp(-decay * t) * s / 1.4)
    return out


def brass(freq, dur, amp=0.35, decay=4.0):
    """A short brass stab: a sawtooth-ish stack whose upper harmonics open up
    quickly then fade (a crude filter sweep)."""
    out = []
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        bright = min(1.0, t / 0.03) * math.exp(-6 * t)
        s = sum(math.sin(2 * math.pi * freq * k * t) / k * (1 if k == 1 else bright) for k in range(1, 7))
        out.append(amp * min(1.0, t / 0.01) * math.exp(-decay * t) * s / 1.8)
    return out


def hat(dur=0.05, amp=0.12, seed=0, decay=60.0):
    rnd = random.Random(seed)
    prev = 0.0
    out = []
    for i in range(int(dur * RATE)):
        x = rnd.random() * 2 - 1
        out.append(amp * math.exp(-decay * i / RATE) * (x - prev))  # high-passed noise
        prev = x
    return out


def clap(amp=0.3, seed=0):
    """Three quick noise bursts and a tail: a hand clap."""
    out = []
    for k, d in enumerate((0.008, 0.008, 0.12)):
        out += hat(d, amp, seed + k, decay=25 if d > 0.05 else 200)
    return out


def silence(dur):
    return [0.0] * int(dur * RATE)


def chord(voice, midis, dur, **kw):
    return mix(*[voice(hz(m), dur, **kw) for m in midis])


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def place(events, length):
    """Mixes (start seconds, samples) events into a track `length` s long."""
    out = [0.0] * int(length * RATE)
    for start, samples in events:
        o = int(start * RATE)
        for i, s in enumerate(samples):
            if o + i < len(out):
                out[o + i] += s
    return out


def write(path, samples, fade=0.03):
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


# ------------------------------------------------------------------ P5
# Acid jazz in D minor: Dm9 / Gm9 stabs, a walking bass, brushes.

def p5_focus():
    """A bass pickup into an electric piano Dm9 stab with a brass hit on top."""
    return place([
        (0.00, bass(hz(45), 0.18)), (0.16, bass(hz(48), 0.18)),
        (0.30, bass(hz(38), 0.7)),
        (0.30, chord(epiano, [50, 53, 57, 60, 64], 0.9, amp=0.22)),
        (0.30, chord(brass, [62, 65, 69], 0.35, amp=0.16)),
        (0.30, hat(0.08, seed=1)),
    ], 1.25)


def p5_countdown():
    """A chromatic run down on the electric piano, landing on a Gm9 brass
    stab: "time's up", with swagger."""
    run = [(0.11 * k, epiano(hz(m), 0.2, amp=0.3)) for k, m in enumerate([74, 73, 72, 70])]
    return place(run + [
        (0.48, chord(brass, [55, 58, 62, 65, 69], 0.5, amp=0.17)),
        (0.48, bass(hz(43), 0.6)),
        (0.48, hat(0.1, seed=2)),
        (0.78, chord(brass, [55, 58, 62, 65, 69], 0.6, amp=0.2)),
        (0.78, bass(hz(31), 0.7)),
    ], 1.5)


def p5_alarm():
    """A two-bar syncopated riff (Dm9 then Gm9 stabs) over a walking bass and
    swung hats; ends on the beat so it loops."""
    beat = 0.3
    events = []
    walk = [38, 41, 43, 45, 43, 46, 48, 49]
    for k, m in enumerate(walk):
        events.append((k * beat, bass(hz(m), beat * 0.95)))
        events.append((k * beat, hat(0.04, amp=0.1, seed=k)))
        events.append((k * beat + beat * 0.66, hat(0.03, amp=0.06, seed=k + 20)))
    for start, notes in [(0.0, [50, 53, 57, 60, 64]), (beat * 1.5, [50, 53, 57, 60, 64]),
                         (beat * 4, [55, 58, 62, 65, 69]), (beat * 5.5, [55, 58, 62, 65, 69]),
                         (beat * 7, [57, 61, 64, 67])]:
        events.append((start, chord(epiano, notes, beat * 1.2, amp=0.2, decay=5)))
    events.append((beat * 3, chord(brass, [62, 65, 69], 0.25, amp=0.14)))
    return place(events, beat * 8 + RING_OUT)


# ----------------------------------------------------------------- P3R
# Calm, in A minor: soft piano arpeggios (Am9, Fmaj7, Em7).

def p3r_focus():
    """A soft Am(add9) arpeggio upwards, the last note left to ring."""
    notes = [57, 64, 67, 71, 72]
    return place([(0.12 * k, piano(hz(m), 1.4 - 0.12 * k, amp=0.3)) for k, m in enumerate(notes)]
                 + [(0.0, piano(hz(45), 1.5, amp=0.25, decay=1.8))], 1.7)


def p3r_countdown():
    """A gentle phrase down, resolving onto an open Fmaj7(9): calm "done"."""
    phrase = [(0.18 * k, piano(hz(m), 0.6, amp=0.3)) for k, m in enumerate([76, 74, 72, 71])]
    return place(phrase + [
        (0.76, chord(piano, [53, 60, 64, 67, 69], 1.6, amp=0.18, decay=1.6)),
        (0.76, piano(hz(41), 1.6, amp=0.25, decay=1.4)),
    ], 2.4)


def p3r_alarm():
    """A flowing broken-chord ostinato, Am9 then Fmaj7 then Em7 then Am9, in
    even eighths: insistent but soft; ends where it starts so it loops."""
    step = 0.16
    patterns = [[45, 52, 59, 60, 64, 60, 59, 52],
                [41, 48, 55, 57, 64, 57, 55, 48],
                [40, 47, 55, 59, 62, 59, 55, 47]]
    events = []
    t = 0.0
    for pattern in patterns:
        for m in pattern:
            events.append((t, piano(hz(m), 0.7, amp=0.26 if m > 50 else 0.3, decay=3)))
            t += step
    events.append((t, piano(hz(69), 0.5, amp=0.25, decay=4)))
    return place(events, t + step * 2 + RING_OUT)


# ------------------------------------------------------------------ P4
# Bright funky pop in E major: Emaj7 / Amaj7 stabs, octave bass, claps.

def p4_focus():
    """Two quick Emaj7 stabs with a clap and an octave bass hop."""
    stab = [52, 56, 59, 63]
    return place([
        (0.00, chord(epiano, stab, 0.18, amp=0.22, decay=9, bright=2.2)),
        (0.00, bass(hz(40), 0.15)),
        (0.18, chord(epiano, stab, 0.6, amp=0.24, decay=4, bright=2.2)),
        (0.18, bass(hz(52), 0.5)),
        (0.18, clap(seed=3)),
    ], 0.9)


def p4_countdown():
    """"Ta-da": two bright stabs climbing, then an Amaj7 with the octave on
    top and a clap."""
    return place([
        (0.00, chord(brass, [56, 59, 63], 0.14, amp=0.18)),
        (0.15, chord(brass, [58, 61, 64], 0.14, amp=0.18)),
        (0.32, chord(brass, [57, 61, 64, 68, 69], 0.7, amp=0.2)),
        (0.32, chord(epiano, [69, 73, 76, 81], 0.8, amp=0.14, bright=2.4)),
        (0.32, bass(hz(45), 0.7)),
        (0.32, clap(seed=4)),
    ], 1.3)


def p4_alarm():
    """A one-bar funk loop played twice: octave-jumping bass, offbeat Emaj7 /
    Amaj7 stabs, claps on 2 and 4."""
    s = 0.125  # sixteenth
    events = []
    for bar in range(2):
        o = bar * 16 * s
        root = 40 if bar == 0 else 45
        for k, (pos, m) in enumerate([(0, root), (3, root + 12), (6, root), (8, root + 12), (11, root), (14, root + 12)]):
            events.append((o + pos * s, bass(hz(m), s * 1.6, decay=8)))
        notes = [52, 56, 59, 63] if bar == 0 else [57, 61, 64, 68]
        for pos in (2, 7, 10, 15):
            events.append((o + pos * s, chord(epiano, notes, s * 1.5, amp=0.18, decay=10, bright=2.2)))
        for pos in (4, 12):
            events.append((o + pos * s, clap(amp=0.22, seed=bar * 10 + pos)))
        for pos in range(0, 16, 2):
            events.append((o + pos * s, hat(0.03, amp=0.06, seed=pos + bar)))
    return place(events, 32 * s + RING_OUT)


VARIANTS = {
    "p5": dict(focus=p5_focus, countdown=p5_countdown, alarm=p5_alarm),
    "p3r": dict(focus=p3r_focus, countdown=p3r_countdown, alarm=p3r_alarm),
    "p4": dict(focus=p4_focus, countdown=p4_countdown, alarm=p4_alarm),
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    for name, sounds in VARIANTS.items():
        for kind, make in sounds.items():
            write(os.path.join(out, f"{name}-{kind}.wav"), make())


if __name__ == "__main__":
    main()
