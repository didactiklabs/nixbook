#!/usr/bin/env python3
"""Synthesize the Persona theme's sounds (themes.json `sounds`): per variant,
a cue when a focus session or a break ends (<variant>-focus.wav), one when
the countdown finishes (<variant>-countdown.wav) and a ringtone the alarm
loops (<variant>-alarm.wav); P3R and P4 also get their own notification
chime and critical sound (P5 keeps the registry's, assets/sounds). Each is
built from scratch around a sound the game is remembered by, over music in
the spirit of its soundtrack (original tunes, no Atlus audio):

  p5   acid jazz (electric piano minor-ninth stabs, walking bass, brushes);
       the calendar flipping to the next day, the calling card thrown and
       sticking, the phone buzzing before the riff
  p3r  calm piano in a minor key; the Velvet Room's blue butterfly (a glassy
       chime), the Evoker (the click, the shot, glass shattering into the
       summon), the Dark Hour (the clock ticking, then the bell)
  p4   bright funky pop (major-seventh stabs, octave bass, claps); the
       Midnight Channel (a TV blipping, switching on into static), the
       Persona card shattering, the school chime (the Westminster Quarters,
       public domain)

Standard library only (with ../synth.py), so the package generates them
when it is built (qml.nix): no audio file is kept in git.
Run: python3 sounds.py [out-dir]   (default: next to this script)
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import synth as S  # noqa: E402

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


# ------------------------------------------------------- the games' sounds
def paper_snap(seed, f=2500.0):
    return S.biquad(S.shaped(S.noise(0.05, seed), lambda t: math.exp(-t * 110)), "bp", f, 1.0)


def stereo(*parts, wet=0.18, room=0.72, tail=0.6):
    """(start, mono samples, gain, pan) parts on a stereo Mix, with a room;
    each part's full length is kept (the alarms' RING_OUT)."""
    m = S.Mix()
    for start, sig, gain, pan in parts:
        m.add(sig, start, gain, pan)
        m.pad(start + len(sig) / RATE)
    return m.reverb(wet, room=room, tail=tail)


def p5_focus_mix():
    """The calendar flips to the next day (a page swept off, a snap), then
    the stab."""
    return stereo((0.0, S.swoosh(0.35, 501, 600, 7000, q=1.5), 0.45, -0.4),
                  (0.3, paper_snap(502), 0.5, 0.2),
                  (0.32, p5_focus(), 1.0, 0.0))


def p5_countdown_mix():
    """The calling card: flicked through the air, stuck with a thwack, then
    the run and the stab with a cymbal."""
    return stereo((0.0, S.swoosh(0.28, 510, 1500, 9000, q=3.0), 0.45, 0.5),
                  (0.26, S.membrane(190, 0.25, decay=28, hit=0.9, hit_f=2600, seed=511), 0.55, 0.3),
                  (0.42, p5_countdown(), 1.0, 0.0),
                  (0.42 + 0.78, S.crash(1.4, 512), 0.18, -0.3))


def p5_alarm_mix():
    """The phone buzzing on the desk, then the riff."""
    return stereo((0.0, S.vibrate(1.0, 520, ((0.0, 0.32), (0.45, 0.32))), 0.55, -0.2),
                  (0.95, p5_alarm(), 1.0, 0.0), wet=0.12)


def p3r_notification():
    """The blue butterfly: two glassy chimes a fifth apart and a few glints
    fluttering up, in a large, quiet room."""
    glints = [(0.12 + 0.07 * k, S.fm_bell(S.note(24 + r), 0.5, index=0.8, ratio=3.0, decay=7), 0.18, -0.6 + 0.3 * k)
              for k, r in enumerate((7, 11, 14, 19, 23))]
    return stereo((0.0, S.fm_bell(1046.5, 1.8, index=1.6, ratio=2.0, decay=2.4), 0.8, -0.15),
                  (0.09, S.fm_bell(1568.0, 1.6, index=1.2, ratio=2.0, decay=2.8), 0.6, 0.2),
                  *glints, wet=0.4, room=0.88, tail=1.4)


def p3r_critical():
    """The Evoker: the hammer cocking, the shot, the glass of the mind
    shattering, and the summon rising from below."""
    swell = S.shaped(S.swoosh(1.2, 531, 150, 2500, q=1.2), lambda t: (t / 1.2) ** 1.5 * 2)
    return stereo((0.0, S.tick(1700, 530), 0.6, 0.0),
                  (0.06, S.tick(1300, 532, tock=True), 0.4, 0.0),
                  (0.3, S.gunshot(533), 1.0, 0.0),
                  (0.31, S.glass(1.6, 534), 0.75, 0.15),
                  (0.45, swell, 0.45, -0.2),
                  (1.5, chord(piano, [33, 45, 52, 57, 60, 64], 3.6, amp=0.25, decay=1.4), 0.75, 0.0),
                  wet=0.35, room=0.86, tail=1.6)


def p3r_focus_mix():
    """The Dark Hour: the clock ticks, stops, a deep bell; then the piano."""
    ticks = [(0.45 * k, S.tick(2400, 540 + k, tock=k % 2 == 1), 0.5, 0.25 if k % 2 else -0.25) for k in range(4)]
    return stereo(*ticks,
                  (1.95, S.tubular(110.0, 3.0, 545), 0.8, 0.0),
                  (1.95, S.shaped(S.modal(55.0, 3.0, ((1.0, 1.0, 0.7, 0.4),)), lambda t: 1.0), 0.4, 0.0),
                  (2.25, p3r_focus(), 0.75, 0.15), wet=0.35, room=0.86, tail=1.4)


def p3r_countdown_mix():
    """Midnight strikes (two deep strokes, a shimmer of glass), then the
    phrase resolving."""
    return stereo((0.0, S.tubular(146.8, 2.6, 550), 0.8, -0.1),
                  (0.0, S.glass(0.9, 551, density=40, low=4000), 0.15, 0.4),
                  (0.95, S.tubular(146.8, 2.6, 552), 0.7, 0.1),
                  (1.5, p3r_countdown(), 0.9, 0.0), wet=0.32, room=0.86, tail=1.2)


def p3r_alarm_mix():
    """The ostinato over the clock's ticking."""
    alarm = p3r_alarm()
    dur = len(alarm) / RATE
    ticks = [(k * 0.32, S.tick(2400, 560 + k, tock=k % 2 == 1), 0.22, 0.3 if k % 2 else -0.3)
             for k in range(int(dur / 0.32))]
    return stereo((0.0, alarm, 1.0, 0.0), *ticks, wet=0.22, room=0.8, tail=0.5)


def p4_notification():
    """The TV changing channel: a burst of static and the set's "pip"."""
    pip = S.shaped([math.sin(S.TAU * 1000 * i / RATE) for i in range(S.n(0.16))], lambda t: S.adsr(t, 0.16, 0.003, 0.03))
    return stereo((0.0, S.shaped(S.static(0.14, 570), lambda t: S.adsr(t, 0.14, 0.003, 0.04)), 0.5, -0.1),
                  (0.13, pip, 0.55, 0.1),
                  (0.33, [v * 0.8 for v in pip], 0.45, 0.1), wet=0.1, room=0.6, tail=0.3)


def card_shatter(seed):
    """The tarot card bursting: a quick upward rush, a crack, glass shards."""
    return S.mono(S.scale(S.swoosh(0.25, seed, 800, 8000, q=2.5), 0.6),
                  [0.0] * S.n(0.22) + S.scale(S.glass(1.2, seed + 1, density=150), 0.9))


def p4_critical():
    """The Midnight Channel: the TV switches on into static, then the
    Persona card shatters over a bright stab."""
    return stereo((0.0, S.tv_on(580), 0.9, 0.0),
                  (0.9, card_shatter(581), 0.85, 0.15),
                  (1.12, chord(brass, [52, 56, 59, 64], 0.7, amp=0.2), 0.9, -0.1),
                  (1.12, bass(hz(40), 0.8), 0.9, 0.0),
                  (1.12, S.crash(1.6, 582), 0.25, 0.3), wet=0.2, room=0.78, tail=0.9)


def p4_focus_mix():
    """The school chime: the first two changes of the Westminster Quarters
    on tubular bells."""
    parts = [(t * 0.68, S.tubular(f, 2.2, 590 + k), 0.7, -0.3 + 0.2 * (k % 4))
             for k, (t, f) in enumerate(S.chime_westminster(beat=0.62, base=S.note(4))[:8])]
    return stereo(*parts, wet=0.38, room=0.86, tail=1.2)


def p4_countdown_mix():
    return stereo((0.0, card_shatter(600), 0.8, 0.15), (0.3, p4_countdown(), 1.0, 0.0), wet=0.15)


def p4_alarm_mix():
    """The funk loop, the Midnight Channel's hiss under it, a blip on top."""
    alarm = p4_alarm()
    dur = len(alarm) / RATE
    hiss = S.shaped(S.static(dur, 610), lambda t: 0.6 + 0.4 * math.sin(math.pi * t / dur))
    return stereo((0.0, alarm, 1.0, 0.0), (0.0, hiss, 0.08, 0.0), wet=0.1)


VARIANTS = {
    "p5": dict(focus=p5_focus_mix, countdown=p5_countdown_mix, alarm=p5_alarm_mix),
    "p3r": dict(notification=p3r_notification, critical=p3r_critical, focus=p3r_focus_mix,
                countdown=p3r_countdown_mix, alarm=p3r_alarm_mix),
    "p4": dict(notification=p4_notification, critical=p4_critical, focus=p4_focus_mix,
               countdown=p4_countdown_mix, alarm=p4_alarm_mix),
}


def main():
    S.run(VARIANTS)


if __name__ == "__main__":
    main()
