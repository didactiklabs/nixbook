#!/usr/bin/env python3
"""Synthesize the Ghibli theme's sounds (themes.json `sounds`), five per
variant: <variant>-notification.wav (the chime), -critical.wav (critical
notifications and the cut-in), -focus.wav (a focus session or a break ends),
-countdown.wav (the countdown is done) and -alarm.wav (looped by the alarm).

Each one recreates, from scratch, a sound the films are remembered by,
fitted to what it announces; the tunes are original, only the instruments
and the idiom are borrowed (no sample, no melody from the films):

  totoro    notification  big raindrops falling on an umbrella ("pon… pon")
            critical      a gust through the camphor tree, a downpour of
                          drops and the forest spirit's roar
            focus         a glass wind chime (furin) in a summer breeze
            countdown     an ocarina phrase landing on the tonic, the chime
            alarm         an ocarina tune over a kalimba, evening cicadas
                          (higurashi) at the start of each loop
  spirited  notification  a temple rin bowl and a drop of water
            critical      the bathhouse drum calling the night in, the bell
            focus         the sea train: a crossing bell over lapping water
                          and the wheels' "ta-tan… ta-tan"
            countdown     a flutter of paper shikigami, then the rin
            alarm         a melancholy piano waltz with a koto
  mononoke  notification  a kodama turning its head (the wooden rattle)
            critical      the wolf's howl over a taiko and rattling kodama
            focus         the forest spirit's step: a soft thud, plants
                          blooming in a shimmer
            countdown     a chorus of kodama, a shakuhachi's last note
            alarm         a shakuhachi in the miyako-bushi scale over a
                          taiko heartbeat and a low drone

Built with ../synth.py (stereo, a small hall reverb). Standard library only
and seeded, so the package generates the same files every time it is built
(qml.nix): no audio file is kept in git.
Run: python3 sounds.py [out-dir]   (default: next to this script)
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from synth import (RATE, TAU, Mix, adsr, biquad, drop, kalimba, koto, membrane, modal, mono, noise,  # noqa: E402
                   note, ocarina, phrase, piano, rustle, scale, shakuhachi, shaped, run, taiko, voice, whoosh, wood, higurashi, n)


# ======================================================================= Totoro
def umbrella_drop(seed, big=1.0):
    """A big raindrop off the tree on a taut umbrella: a deep "pon", the
    splash, and a tiny plip of the water."""
    rnd = random.Random(seed)
    f = 165 + rnd.random() * 70
    pon = membrane(f, 0.5, drop=0.25, drop_rate=40, decay=9, hit=0.35, hit_f=1400, seed=seed,
                   modes=((1.0, 1.0), (1.72, 0.3), (2.41, 0.12)))
    splash = biquad(shaped(noise(0.08, seed + 1), lambda t: math.exp(-t * 90)), "hp", 3500)
    plip = drop(1500 + rnd.random() * 900, 0.07)
    return mono(scale(pon, big), scale(splash, 0.18 * big), [0.0] * n(0.006) + scale(plip, 0.22))


def totoro_notification():
    m = Mix()
    m.add(umbrella_drop(11), 0.0, 1.0, -0.15)
    m.add(umbrella_drop(12, 0.75), 0.24, 1.0, 0.2)
    return m.reverb(0.22, room=0.7, tail=0.9)


def roar(seed):
    """The forest spirit's great yawning roar: a deep buzz opening from "a"
    to "o", rough, rising then sinking."""
    dur = 1.7

    def f0(t):
        x = t / dur
        return 78 + 52 * math.sin(math.pi * min(1.0, x * 1.25)) ** 1.5

    def vowel(t):
        x = min(1.0, t / dur)
        f1 = 760 - 260 * x
        f2 = 1250 - 400 * x
        return [(f1, 4.0, 1.0), (f2, 5.0, 0.55), (2600, 6.0, 0.18), (140, 1.5, 0.5)]

    v = voice(dur, f0, vowel, seed=seed, rasp=1.0, breath=0.35)
    return shaped(v, lambda t: min(1.0, t / 0.18) * (math.sin(math.pi * min(1.0, t / dur)) ** 0.6))


def totoro_critical():
    m = Mix()
    m.add(whoosh(1.3, 21), 0.0, 0.55, -0.3)
    m.add(rustle(1.2, 22), 0.1, 0.25, 0.35)
    # The tree shakes off its rain.
    rnd = random.Random(23)
    for k in range(9):
        m.add(umbrella_drop(30 + k, 0.5 + 0.5 * rnd.random()), 0.32 + k * 0.055 + rnd.random() * 0.03,
              0.6, rnd.random() * 1.4 - 0.7)
    m.add(roar(24), 0.82, 1.0, 0.0)
    return m.reverb(0.35, room=0.84, tail=1.6)


def furin(f, seed, strikes=3):
    """A glass wind chime: the clapper touches it a few times as the paper
    strip catches the wind."""
    rnd = random.Random(seed)
    out = []
    t = 0.0
    sig = [0.0] * n(2.6)
    for k in range(strikes):
        g = (0.9 if k == 0 else 0.35 + 0.4 * rnd.random())
        ring = modal(f * (1 + 0.002 * k), 2.0, ((1.0, 1.0, 2.2, 1.6), (2.32, 0.45, 3.6, 2.4), (4.25, 0.25, 6.0, 0),
                                                (6.63, 0.12, 9.0, 0)), strike=0.08, strike_f=6000, seed=seed + k)
        o = n(t)
        for i, s in enumerate(ring):
            if o + i < len(sig):
                sig[o + i] += g * s
        t += 0.16 + rnd.random() * 0.22
    out = sig
    return out


def totoro_focus():
    m = Mix()
    m.add(whoosh(2.2, 41, bands=((500, 0.0), (1100, 0.2))), 0.0, 0.18, 0.4)
    m.add(furin(2637.0, 42, strikes=3), 0.15, 1.0, -0.2)
    m.add(furin(3136.0, 43, strikes=2), 0.62, 0.55, 0.3)
    return m.reverb(0.3, room=0.8, tail=1.2)


C5 = 12  # semitones above middle C



def totoro_countdown():
    m = Mix()
    oc = lambda f, d, s: ocarina(f, d, s, scoop=0.03)
    end = phrase(m, oc, [(2, 0.5), (4, 0.5), (7, 1), (4, 0.5), (7, 0.5), (12, 2.4)], 0.0, 0.17, base=C5, seed=50)
    m.add(kalimba(note(C5 - 12), 1.6), end - 2.4 * 0.17, 0.35, -0.3)
    m.add(kalimba(note(C5 - 5), 1.6), end - 2.4 * 0.17, 0.25, 0.3)
    m.add(furin(3136.0, 51, strikes=2), end - 0.1, 0.4, 0.4)
    return m.reverb(0.32, room=0.82, tail=1.3)


def totoro_alarm():
    m = Mix()
    beat = 0.5
    # Summer evening: a cicada starts, then the tune.
    m.add(higurashi(2.4, seed=60), 0.0, 0.16, 0.6)
    t0 = 0.6
    melody = [(4, 1), (7, 0.5), (9, 0.5), (7, 1), (4, 1),
              (2, 0.5), (4, 0.5), (7, 1), (2, 2),
              (9, 1), (12, 0.5), (9, 0.5), (7, 1), (4, 0.5), (7, 0.5),
              (2, 1), (4, 0.5), (2, 0.5), (0, 2)]
    oc = lambda f, d, s: ocarina(f, d, s, scoop=0.025)
    phrase(m, oc, melody, t0, beat, gain=1.0, pan=0.0, base=C5, seed=61)
    # Kalimba: C, Am, F, G (then C), arpeggios in eighths.
    chords = [(0, 7, 4, 7, 12, 7, 4, 7), (-3, 4, 0, 4, 9, 4, 0, 4),
              (-7, 0, -3, 0, 5, 0, -3, 0), (-5, 2, -1, 2, 7, 2, -1, 2)]
    for bar, arp in enumerate(chords):
        for k, semi in enumerate(arp):
            m.add(kalimba(note(semi)), t0 + (bar * 4 + k * 0.5) * beat, 0.32 if k % 4 == 0 else 0.22,
                  -0.35 + 0.1 * (k % 3))
    m.add(kalimba(note(-12), 2.0), t0 + 16 * beat, 0.35, -0.2)
    m.add(furin(2637.0, 62, strikes=2), t0 + 15 * beat, 0.3, 0.5)
    m.pad(t0 + 16 * beat + 1.0)
    return m.reverb(0.28, room=0.8, tail=1.0)


# ============================================================= Spirited Away
def rin(f=1046.5, seed=0, dur=3.2):
    """A temple rin bowl: a long shimmering tone with beating partials."""
    return modal(f, dur, ((1.0, 1.0, 0.9, 1.3), (2.71, 0.55, 1.6, 2.1), (5.15, 0.22, 3.0, 0),
                          (8.6, 0.08, 5.0, 0)), strike=0.05, strike_f=2500, seed=seed)


def spirited_notification():
    m = Mix()
    m.add(drop(1700, 0.08), 0.0, 0.35, 0.3)
    m.add(shaped(rin(1046.5, 70, 2.0), lambda t: adsr(t, 2.0, 0.001, 1.0)), 0.06, 1.0, -0.1)
    return m.reverb(0.28, room=0.8, tail=0.8)


def bonsho(f=98.0, seed=0, dur=4.0):
    """The great bell, struck by a wooden beam: a deep hum and a cloud of
    beating partials."""
    bell = modal(f, dur, ((0.5, 0.5, 0.45, 0.6), (1.0, 1.0, 0.6, 1.1), (1.19, 0.5, 0.8, 0), (1.5, 0.45, 0.9, 1.7),
                          (2.0, 0.35, 1.2, 0.9), (2.66, 0.25, 1.6, 0), (3.17, 0.15, 2.2, 2.3), (4.23, 0.1, 3.0, 0)))
    beam = membrane(58, 0.5, drop=0.1, decay=14, hit=0.6, hit_f=400, seed=seed)
    return mono(bell, scale(beam, 0.6))



def spirited_critical():
    m = Mix()
    # The drum calling the bathhouse awake: two slow strokes, a roll that
    # gathers, a last great stroke under the bell.
    times = [0.0, 0.62, 1.1, 1.36, 1.56, 1.72, 1.86]
    for k, t in enumerate(times):
        m.add(taiko(72 + (k % 2) * 4, 80 + k, 0.65 + 0.05 * k), t, 1.0, -0.15 + 0.3 * (k % 2))
    m.add(taiko(66, 90, 1.25), 2.1, 1.0, 0.0)
    m.add(shaped(bonsho(98.0, 91, 3.2), lambda t: adsr(t, 3.2, 0.001, 1.4)), 2.1, 0.55, 0.1)
    return m.reverb(0.38, room=0.86, tail=1.2)


def crossing_bell(f, seed):
    """One stroke of a level-crossing gong: "kan"."""
    return modal(f, 0.6, ((1.0, 1.0, 6.5, 0), (2.42, 0.55, 9.0, 0), (3.93, 0.35, 12.0, 0), (5.31, 0.18, 16.0, 0)),
                 strike=0.15, strike_f=4000, seed=seed)


def spirited_focus():
    m = Mix()
    dur = 3.4
    # Lapping water under the line.
    water = biquad(noise(dur, 100), "lp", 650)
    m.add(shaped(water, lambda t: (0.5 + 0.5 * math.sin(TAU * 0.6 * t) ** 2) * adsr(t, dur, 0.4, 0.8)), 0.0, 0.22, -0.4)
    # The crossing bell, a little far.
    for k in range(6):
        m.add(biquad(crossing_bell(740 if k % 2 == 0 else 690, 101 + k), "lp", 5000), 0.1 + k * 0.38, 0.5, 0.35)
    # The sea train passing: wheels on the rail joints, "ta-tan… ta-tan".
    rumble = biquad(noise(2.6, 102), "lp", 220)
    m.add(shaped(rumble, lambda t: math.sin(math.pi * min(1.0, t / 2.6)) ** 2), 0.8, 0.35, 0.0)
    for k in range(4):
        g = math.sin(math.pi * (k + 0.5) / 4) * 0.55
        pan = -0.6 + 0.4 * k
        for j, dt in enumerate((0.0, 0.13)):
            thump = membrane(62 + 8 * j, 0.25, drop=0.2, decay=22, hit=0.8, hit_f=1100, seed=110 + k * 2 + j)
            m.add(thump, 1.0 + k * 0.52 + dt, g, pan)
    return m.reverb(0.3, room=0.8, tail=1.2)


def flutter(dur, seed, density=70.0, pan_from=-0.8, pan_to=0.8):
    """Paper birds: many dry flaps of paper, a swarm passing across."""
    rnd = random.Random(seed)
    parts = []
    t = 0.0
    while t < dur:
        t += rnd.expovariate(density * (0.3 + math.sin(math.pi * min(1.0, t / dur))))
        f = 1600 + rnd.random() * 2400
        flap = biquad(noise(0.03, seed + int(t * 1000)), "bp", f, 1.6)
        flap = shaped(flap, lambda tt: min(1.0, tt / 0.003) * math.exp(-tt * 140))
        x = t / dur
        parts.append((t, flap, 0.4 + 0.6 * rnd.random(), pan_from + (pan_to - pan_from) * x + 0.2 * (rnd.random() - 0.5)))
    return parts


def spirited_countdown():
    m = Mix()
    for t, flap, g, pan in flutter(1.3, 120):
        m.add(flap, t, g * 0.55, pan)
    m.add(whoosh(1.4, 121, bands=((900, 0.0), (2000, 0.15))), 0.0, 0.22, 0.2)
    m.add(koto(note(9), 1.5, 122), 1.15, 0.45, -0.3)   # A4
    m.add(koto(note(16), 1.5, 123), 1.27, 0.45, -0.1)  # E5
    m.add(rin(1046.5, 124), 1.4, 0.9, 0.15)
    return m.reverb(0.32, room=0.84, tail=1.3)


A4 = 9


def spirited_alarm():
    m = Mix()
    beat = 0.46  # a slow waltz
    t0 = 0.05
    # Left hand: the bass on one, the chord on two and three.
    chords = [(-12, (0, 3, 7)), (-16, (-4, 0, 3)), (-14, (-2, 2, 5)), (-17, (-5, -2, 2)),
              (-16, (-4, 0, 3)), (-17, (-5, -1, 2))]  # Am F G Em F E
    for bar, (bass, chord) in enumerate(chords):
        t = t0 + bar * 3 * beat
        m.add(piano(note(A4 + bass), 2.4, 0.7), t, 0.55, -0.35)
        for j in (1, 2):
            for semi in chord:
                m.add(piano(note(A4 + semi), 1.4, 0.45), t + j * beat, 0.22, -0.15)
    melody = [(7, 2), (3, 1), (5, 1), (3, 1), (0, 1), (2, 1.5), (3, 0.5), (5, 1),
              (10, 2), (7, 1), (8, 1), (7, 1), (5, 1), (2, 2), (-1, 1)]
    t = t0
    for k, (semi, beats) in enumerate(melody):
        m.add(piano(note(A4 + 12 + semi - 12), 2.4, 0.85), t, 0.75, 0.2)
        t += beats * beat
    # A koto answers at the turn, the rin closes the loop.
    m.add(koto(note(A4 + 7 + 12), 1.4, 130), t0 + 9 * beat + beat * 1.5, 0.3, 0.55)
    m.add(koto(note(A4 + 3 + 12), 1.4, 131), t0 + 9 * beat + beat * 2.0, 0.3, 0.55)
    m.add(rin(880.0, 132), t0 + 17 * beat, 0.35, 0.4)
    m.pad(t0 + 18 * beat + 0.4)
    return m.reverb(0.33, room=0.85, tail=1.0)


# ================================================================== Mononoke
def kodama_rattle(seed, clicks=9, f=None, speed=1.0):
    """A kodama turning its head: a quick, uneven "karakarakara" of hollow
    wooden knocks, rushing then slowing."""
    rnd = random.Random(seed)
    base = f or (1150 + rnd.random() * 700)
    out = [0.0] * n(1.2)
    t = 0.0
    for k in range(clicks):
        x = k / max(1, clicks - 1)
        knock = wood(base * (1 + 0.08 * (rnd.random() - 0.5)), seed=seed * 31 + k)
        g = (0.55 + 0.45 * rnd.random()) * (1 - 0.35 * x)
        o = n(t)
        for i, s in enumerate(knock):
            if o + i < len(out):
                out[o + i] += g * s
        t += (0.032 + 0.03 * (abs(x - 0.35) * 1.6) + 0.012 * rnd.random()) / speed
    end = min(len(out), n(t + 0.12))
    return out[:end]


def mononoke_notification():
    m = Mix()
    m.add(kodama_rattle(140, clicks=8), 0.0, 1.0, -0.2)
    m.add(kodama_rattle(141, clicks=5), 0.2, 0.45, 0.45)
    return m.reverb(0.3, room=0.86, tail=1.2)


def howl(seed, dur=2.6, high=560.0):
    """A wolf's howl: a pure, rounded voice sliding up, holding, falling."""

    def f0(t):
        x = t / dur
        if x < 0.25:
            return 330 + (high - 330) * math.sin(math.pi / 2 * x / 0.25)
        if x < 0.7:
            return high * (1 - 0.06 * (x - 0.25) / 0.45)
        return high * 0.94 * (1 - 0.3 * ((x - 0.7) / 0.3) ** 1.5)

    def vowel(t):
        x = min(1.0, t / dur)
        return [(f0(t) * 1.02, 2.0, 1.0), (900 - 200 * x, 3.0, 0.35), (2400, 5.0, 0.05)]

    v = voice(dur, f0, vowel, seed=seed, rasp=0.15, breath=0.06, harsh=0.35)
    return shaped(v, lambda t: min(1.0, t / 0.25) * adsr(t, dur, 0.01, 0.6))


def mononoke_critical():
    m = Mix()
    m.add(taiko(64, 150, 1.0), 0.0, 0.8, 0.0)
    m.add(howl(151), 0.15, 1.0, -0.15)
    m.add(howl(152, dur=2.1, high=500.0), 0.75, 0.35, 0.6)
    for k in range(4):
        m.add(kodama_rattle(153 + k, clicks=7 + k), 1.4 + k * 0.22, 0.35, -0.8 + 0.5 * k)
    return m.reverb(0.42, room=0.88, tail=2.0)


def bloom(seed, dur=2.2):
    """Life springing up where the spirit steps: soft sine voices in a
    pentatonic cloud, each sliding up into place, staggered, over a breath
    of air."""
    rnd = random.Random(seed)
    ratios = [1, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2, 9 / 4, 5 / 2, 3, 10 / 3, 4]
    out = [0.0] * n(dur)
    sin, exp = math.sin, math.exp
    for k, r in enumerate(ratios):
        f = 392.0 * r
        start = 0.03 * k + 0.02 * rnd.random()
        d = dur - start
        phase = 0.0
        o = n(start)
        for i in range(n(d)):
            t = i / RATE
            phase += TAU * f * (1 - 0.04 * exp(-t * 12)) / RATE
            e = min(1.0, t / 0.04) * exp(-t * (1.6 + 0.15 * k)) / (1 + 0.25 * k)
            out[o + i] += e * sin(phase)
    air = biquad(noise(dur, seed), "bp", 3000, 0.8)
    for i, s in enumerate(air):
        t = i / RATE
        out[i] += 0.12 * s * min(1.0, t / 0.15) * exp(-t * 2.2)
    return out


def mononoke_focus():
    m = Mix()
    step = membrane(46, 1.0, drop=0.15, decay=6, hit=0.25, hit_f=300, seed=160)
    m.add(step, 0.0, 0.8, 0.0)
    m.add(bloom(161), 0.05, 0.7, -0.25)
    m.add(bloom(162), 0.12, 0.45, 0.35)
    return m.reverb(0.45, room=0.88, tail=1.8)


D4 = 2  # semitones above middle C


def mononoke_countdown():
    m = Mix()
    for k in range(5):
        m.add(kodama_rattle(170 + k, clicks=6 + k % 3, speed=1.1), k * 0.13, 0.5, -0.8 + 0.4 * k)
    sh = lambda f, d, s: shakuhachi(f, d, s)
    phrase(m, sh, [(7, 0.6), (5, 0.45), (12, 1.8)], 0.55, 0.42, gain=0.8, base=D4, seed=175)
    return m.reverb(0.4, room=0.87, tail=1.6)


def mononoke_alarm():
    m = Mix()
    beat = 0.86  # a slow heartbeat
    total = 10 * beat
    # Low drone on D and A.
    drone = mono(modal(note(D4 - 24), total, ((1.0, 1.0, 0.05, 0.3),)),
                 modal(note(D4 - 17), total, ((1.0, 0.45, 0.06, 0.2),)))
    m.add(shaped(drone, lambda t: adsr(t, total, 1.2, 1.5)), 0.0, 0.35, 0.0)
    # Taiko heartbeat: "don-don", rest.
    for k in range(10):
        if k % 2 == 0:
            m.add(taiko(64, 180 + k, 0.8), k * beat, 0.6, -0.1)
            m.add(taiko(70, 190 + k, 0.5), k * beat + 0.22, 0.6, 0.1)
    # Shakuhachi in miyako-bushi on D (D Eb G A Bb): an original phrase.
    sh = lambda f, d, s: shakuhachi(f, d, s)
    tune = [(7, 2.0), (8, 0.6), (7, 0.6), (5, 1.3), (None, 0.4),
            (12, 1.2), (7, 0.6), (5, 0.6), (1, 0.7), (0, 2.2)]
    phrase(m, sh, tune, 0.5, 0.75, gain=0.9, base=D4, seed=200, legato=1.02)
    # Kodama answering here and there.
    m.add(kodama_rattle(210, clicks=6), 2.7, 0.3, 0.75)
    m.add(kodama_rattle(211, clicks=7), 6.3, 0.3, -0.75)
    m.pad(total + 0.4)
    return m.reverb(0.4, room=0.87, tail=1.2)


VARIANTS = {
    "totoro": dict(notification=totoro_notification, critical=totoro_critical, focus=totoro_focus,
                   countdown=totoro_countdown, alarm=totoro_alarm),
    "spirited": dict(notification=spirited_notification, critical=spirited_critical, focus=spirited_focus,
                     countdown=spirited_countdown, alarm=spirited_alarm),
    "mononoke": dict(notification=mononoke_notification, critical=mononoke_critical, focus=mononoke_focus,
                     countdown=mononoke_countdown, alarm=mononoke_alarm),
}



def main():
    run(VARIANTS)


if __name__ == "__main__":
    main()
