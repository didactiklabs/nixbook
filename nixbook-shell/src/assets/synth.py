"""A small sound synthesizer for the themes' sounds (assets/<theme>/sounds.py):
a stereo mix with a hall reverb, filters, and instruments built from
scratch — struck resonators (bells, bowls, bars, drum skins), plucked and
blown voices, a creature's voice through moving formants, noise textures.
Standard library only and seeded: the package runs the scripts when it is
built (qml.nix), the same files every time, no audio file kept in git.
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 44100
LOUDNESS = 0.16  # rms of the sounding part, full scale = 1
TAU = 2 * math.pi


def n(dur):
    return int(dur * RATE)


def note(semitones, base=261.6256):
    """The frequency `semitones` above `base` (middle C)."""
    return base * 2 ** (semitones / 12)


# --------------------------------------------------------------------- mixing
class Mix:
    """A stereo buffer that grows as sounds are placed in it."""

    def __init__(self):
        self.L = []
        self.R = []
        # write() never trims below this: a rest a loop must keep.
        self.min_len = 0

    def pad(self, dur, keep=True):
        """Grow to `dur` s; keep=True: a rest the file keeps (an alarm's
        breath before it loops), else room for a tail that write() may trim."""
        if keep:
            self.min_len = max(self.min_len, n(dur))
        need = n(dur) - len(self.L)
        if need > 0:
            self.L.extend([0.0] * need)
            self.R.extend([0.0] * need)
        return self

    def add(self, sig, t=0.0, gain=1.0, pan=0.0):
        o = n(t)
        self.pad((o + len(sig)) / RATE + 1 / RATE, keep=False)
        a = (max(-1.0, min(1.0, pan)) + 1) * math.pi / 4
        gl, gr = gain * math.cos(a), gain * math.sin(a)
        L, R = self.L, self.R
        for i, s in enumerate(sig):
            L[o + i] += s * gl
            R[o + i] += s * gr
        return self

    def reverb(self, wet=0.3, room=0.82, damp=0.35, tail=1.6, predelay=0.018):
        """A Freeverb-style hall: parallel damped combs, then allpasses, a
        slightly different set per channel; `wet` is the reverb's peak
        relative to the dry signal's."""
        self.pad(len(self.L) / RATE + tail, keep=False)
        send = [0.0] * n(predelay) + [(l + r) * 0.5 for l, r in zip(self.L, self.R)]
        send = send[: len(self.L)]
        dry_peak = max(1e-9, max(max(abs(v) for v in self.L), max(abs(v) for v in self.R)))
        outs = []
        for spread in (0, 23):
            acc = [0.0] * len(send)
            for d in (1116, 1188, 1277, 1356, 1422, 1491):
                c = _comb(send, d + spread, room, damp)
                for i, v in enumerate(c):
                    acc[i] += v
            for d in (556, 441, 341):
                acc = _allpass(acc, d + spread)
            outs.append(acc)
        wet_peak = max(1e-9, max(max(abs(v) for v in o) for o in outs))
        g = wet * dry_peak / wet_peak
        for dst, src in ((self.L, outs[0]), (self.R, outs[1])):
            for i, v in enumerate(src):
                dst[i] += v * g
        return self

    def tape(self, drive=1.6, tone=11000.0):
        """A warm master: soft tape saturation (gentle compression of the
        peaks, a little harmonic warmth) and the top end rounded off."""
        peak = max(1e-9, max(max(abs(v) for v in self.L), max(abs(v) for v in self.R)))
        a = 1 - math.exp(-TAU * tone / RATE)
        norm = math.tanh(drive)
        for ch in (self.L, self.R):
            y = 0.0
            for i, v in enumerate(ch):
                x = math.tanh(drive * v / peak) / norm
                y += a * (x - y)
                ch[i] = y
        return self


def _comb(x, d, fb, damp):
    out = [0.0] * len(x)
    buf = [0.0] * d
    idx = 0
    store = 0.0
    for i, v in enumerate(x):
        y = buf[idx]
        out[i] = y
        store = y * (1 - damp) + store * damp
        buf[idx] = v + store * fb
        idx += 1
        if idx == d:
            idx = 0
    return out


def _allpass(x, d, g=0.5):
    out = [0.0] * len(x)
    buf = [0.0] * d
    idx = 0
    for i, v in enumerate(x):
        b = buf[idx]
        out[i] = b - v
        buf[idx] = v + b * g
        idx += 1
        if idx == d:
            idx = 0
    return out


def write(path, mix, fade=0.03):
    """16-bit stereo, normalized, with a short fade out (no click)."""
    L, R = mix.L, mix.R
    # Drop the silent end of the reverb tail.
    end = len(L)
    while end > mix.min_len and abs(L[end - 1]) < 1e-5 and abs(R[end - 1]) < 1e-5:
        end -= 1
    L, R = L[:end], R[:end]
    # Level: the loudness of the sounding part (above -40 dB) brought to
    # the same mark for every file, so a soft chime and a drum roll play
    # about as loud; the peak never clips.
    peak = max(1e-9, max(max(abs(v) for v in L), max(abs(v) for v in R)))
    floor = peak * 0.01
    active = [v for v in L[::5] + R[::5] if abs(v) > floor] or [peak]
    rms = math.sqrt(sum(v * v for v in active) / len(active))
    gain = min(0.89 / peak, LOUDNESS / rms)
    fn = n(fade)
    frames = bytearray()
    for i in range(end):
        g = gain * min(1.0, (end - i) / fn)
        frames += struct.pack("<hh", int(max(-1, min(1, L[i] * g)) * 32767), int(max(-1, min(1, R[i] * g)) * 32767))
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


# -------------------------------------------------------------------- filters
def biquad(x, kind, f, q=0.707):
    """RBJ biquad: "lp", "hp" or "bp" (0 dB peak)."""
    w = TAU * min(f, RATE * 0.45) / RATE
    c, s = math.cos(w), math.sin(w)
    a = s / (2 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    else:
        b0, b1, b2 = a, 0.0, -a
    a0, a1, a2 = 1 + a, -2 * c, 1 - a
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, y
        out[i] = y
    return out


def formants(x, fn, block=256):
    """Parallel band-passes whose (frequency, q, gain) list `fn(t)` changes
    over time (recomputed every `block` samples, filter state kept): a
    vowel that moves."""
    out = [0.0] * len(x)
    states = {}
    for start in range(0, len(x), block):
        for k, (f, q, gain) in enumerate(fn(start / RATE)):
            w = TAU * min(f, RATE * 0.45) / RATE
            c, s = math.cos(w), math.sin(w)
            a = s / (2 * q)
            a0 = 1 + a
            b0, b2, a1, a2 = a / a0, -a / a0, -2 * c / a0, (1 - a) / a0
            x1, x2, y1, y2 = states.get(k, (0.0, 0.0, 0.0, 0.0))
            for i in range(start, min(len(x), start + block)):
                v = x[i]
                y = b0 * v + b2 * x2 - a1 * y1 - a2 * y2
                x2, x1, y2, y1 = x1, v, y1, y
                out[i] += gain * y
            states[k] = (x1, x2, y1, y2)
    return out


def noise(dur, seed, amp=1.0):
    rnd = random.Random(seed)
    return [amp * (rnd.random() * 2 - 1) for _ in range(n(dur))]


def shaped(sig, fn):
    """`sig` times the envelope fn(t)."""
    return [s * fn(i / RATE) for i, s in enumerate(sig)]


def scale(sig, g):
    return [s * g for s in sig]


def mono(*parts):
    """Sum mono signals (the longest wins the length)."""
    out = [0.0] * max(len(p) for p in parts)
    for p in parts:
        for i, s in enumerate(p):
            out[i] += s
    return out


def adsr(t, dur, attack, release):
    if t < attack:
        return t / attack
    if t > dur - release:
        return max(0.0, (dur - t) / release)
    return 1.0


# ---------------------------------------------------------------- instruments
def modal(f, dur, modes, strike=0.0, strike_f=3000.0, seed=0):
    """A struck resonator (bell, bowl, bar): `modes` are (ratio, amp, decay
    per second, beating Hz). `strike` adds the mallet's click."""
    N = n(dur)
    out = [0.0] * N
    sin, exp, cos = math.sin, math.exp, math.cos
    for ratio, amp, decay, beat in modes:
        fr = f * ratio
        if fr > RATE * 0.45:
            continue
        w = TAU * fr / RATE
        for i in range(N):
            t = i / RATE
            e = amp * exp(-decay * t)
            if e < 1e-5:
                break
            if beat:
                e *= 0.75 + 0.25 * cos(TAU * beat * t)
            out[i] += e * sin(w * i) * min(1.0, t / 0.0015)
    if strike:
        click = biquad(shaped(noise(0.03, seed), lambda t: exp(-t * 180)), "bp", strike_f, 1.2)
        for i, s in enumerate(click):
            out[i] += strike * s
    return out


def membrane(f, dur, drop=0.5, drop_rate=25.0, decay=8.0, hit=0.4, hit_f=900.0, seed=0,
             modes=((1.0, 1.0), (1.59, 0.35), (2.14, 0.18), (2.65, 0.08))):
    """A drum skin (taiko, an umbrella's canopy): modes whose pitch falls
    just after the hit, and the stick's noise."""
    N = n(dur)
    out = [0.0] * N
    sin, exp = math.sin, math.exp
    for ratio, amp in modes:
        phase = 0.0
        d = decay * ratio ** 0.6
        for i in range(N):
            t = i / RATE
            e = amp * exp(-d * t)
            if e < 1e-5:
                break
            phase += TAU * f * ratio * (1 + drop * exp(-drop_rate * t)) / RATE
            out[i] += e * sin(phase) * min(1.0, t / 0.001)
    if hit:
        click = biquad(shaped(noise(0.08, seed), lambda t: exp(-t * 70)), "bp", hit_f, 0.8)
        for i, s in enumerate(click):
            out[i] += hit * s
    return out


def drop(f0, dur=0.08, rise=1.6, decay=50.0):
    """A water drop's bubble: a sine sweeping up as it fades ("plip")."""
    out = []
    phase = 0.0
    for i in range(n(dur)):
        t = i / RATE
        phase += TAU * f0 * (1 + rise * t / dur) / RATE
        out.append(math.sin(phase) * math.exp(-decay * t) * min(1.0, t / 0.001))
    return out


def wood(f, decay=60.0, seed=0):
    """A small hollow wooden knock (the kodama's head)."""
    return modal(f, 0.12, ((1.0, 1.0, decay, 0), (2.76, 0.45, decay * 1.7, 0), (4.1, 0.2, decay * 2.4, 0)),
                 strike=0.5, strike_f=f * 2.2, seed=seed)


def ocarina(f, dur, seed=0, scoop=0.0, vibrato=0.006):
    """A near-pure flute tone, a little breath, a vibrato that blooms on long
    notes; `scoop` slides into the note from below."""
    N = n(dur)
    out = [0.0] * N
    phase = 0.0
    sin, exp = math.sin, math.exp
    for i in range(N):
        t = i / RATE
        vib = vibrato * min(1.0, max(0.0, (t - 0.18) / 0.35)) * sin(TAU * 5.3 * t)
        phase += TAU * f * (1 + vib) * (1 - scoop * exp(-t * 28)) / RATE
        e = adsr(t, dur, 0.045, min(0.12, dur * 0.4))
        out[i] = e * (sin(phase) + 0.07 * sin(2 * phase) + 0.03 * sin(3 * phase))
    breath = biquad(noise(dur, seed), "bp", f * 2, 1.5)
    for i, s in enumerate(breath):
        out[i] += 0.05 * s * adsr(i / RATE, dur, 0.02, 0.1)
    return out


def shakuhachi(f, dur, seed=0, bend=0.045, muraiki=0.6):
    """The bamboo flute: a reedy tone carried on a lot of breath, slid up
    into the note (meri-kari), a slow head-shake vibrato (yuri) and the
    breath burst of the attack (muraiki)."""
    N = n(dur)
    out = [0.0] * N
    phase = 0.0
    sin, exp = math.sin, math.exp
    for i in range(N):
        t = i / RATE
        yuri = 0.011 * min(1.0, max(0.0, (t - 0.35) / 0.5)) * sin(TAU * 4.2 * t)
        phase += TAU * f * (1 - bend * exp(-t * 9) + yuri) / RATE
        e = adsr(t, dur, 0.09, min(0.25, dur * 0.35)) * (1 + 0.08 * sin(TAU * 5.5 * t))
        out[i] = e * (sin(phase) + 0.32 * sin(2 * phase) + 0.12 * sin(3 * phase) + 0.05 * sin(4 * phase))
    air = noise(dur, seed)
    breath = mono(scale(biquad(air, "bp", f, 5.0), 0.9), scale(biquad(air, "bp", f * 2, 4.0), 0.4),
                  scale(biquad(air, "hp", 2500), 0.08))
    for i, s in enumerate(breath):
        t = i / RATE
        e = adsr(t, dur, 0.06, min(0.25, dur * 0.35))
        out[i] += s * e * (0.35 + muraiki * exp(-t * 14))
    return out


def koto(f, dur, seed=0, bright=0.6):
    """A plucked silk string (Karplus-Strong), with the pick's attack."""
    rnd = random.Random(seed)
    period = max(2, int(round(RATE / f)))
    buf = [rnd.random() * 2 - 1 for _ in range(period)]
    prev = 0.0
    for i in range(period):  # soften the pluck
        prev = buf[i] = bright * buf[i] + (1 - bright) * prev
    out = [0.0] * n(dur)
    idx = 0
    for i in range(len(out)):
        y = buf[idx]
        nxt = buf[(idx + 1) % period]
        buf[idx] = 0.997 * 0.5 * (y + nxt)
        out[i] = y
        idx = (idx + 1) % period
    body = modal(f, dur, ((1.0, 0.25, 2.5, 0),))
    return mono(out, body)


def kalimba(f, dur=1.4, seed=0):
    return modal(f, dur, ((1.0, 1.0, 3.2, 0), (5.93, 0.18, 14.0, 0), (13.4, 0.05, 30.0, 0)),
                 strike=0.12, strike_f=f * 4, seed=seed)


_piano_cache = {}


def piano(f, dur=2.2, vel=0.8):
    """A soft upright: slightly stretched partials, the high ones fading
    first, a gentle beating between strings, the felt hammer's thump."""
    key = (round(f, 3), dur, vel)
    if key in _piano_cache:
        return _piano_cache[key]
    N = n(dur)
    out = [0.0] * N
    sin, exp, cos = math.sin, math.exp, math.cos
    for k in range(1, 8):
        fk = k * f * math.sqrt(1 + 0.00035 * k * k)
        if fk > RATE * 0.45:
            break
        amp = vel ** (0.5 + 0.25 * k) / k ** 1.15
        d = 0.9 + 0.55 * k + f / 900
        w = TAU * fk / RATE
        for i in range(N):
            t = i / RATE
            e = amp * exp(-d * t)
            if e < 1e-5:
                break
            out[i] += e * sin(w * i) * (0.85 + 0.15 * cos(TAU * 0.9 * k * t)) * min(1.0, t / 0.002)
    thump = biquad(shaped(noise(0.04, int(f)), lambda t: exp(-t * 120)), "lp", 700)
    for i, s in enumerate(thump):
        out[i] += 0.12 * vel * s
    _piano_cache[key] = out
    return out


def voice(dur, f0, vowel, seed=0, rasp=0.0, breath=0.15, harsh=1.0):
    """A creature's voice: a glottal buzz at pitch f0(t), roughened by
    `rasp` (jitter and a subharmonic flutter), through the moving vowel
    `vowel(t)` -> [(formant Hz, q, gain)]."""
    rnd = random.Random(seed)
    N = n(dur)
    src = [0.0] * N
    phase = 0.0
    jitter = 0.0
    sin = math.sin
    for i in range(N):
        t = i / RATE
        if i % 64 == 0:
            jitter = 0.7 * jitter + 0.3 * (rnd.random() * 2 - 1)
        f = f0(t) * (1 + rasp * 0.05 * jitter)
        phase = (phase + f / RATE) % 1.0
        saw = 2 * phase - 1
        flutter = 1 - rasp * 0.5 * (0.5 + 0.5 * sin(TAU * f * 0.5 * t))
        src[i] = (harsh * saw + (1 - harsh) * sin(TAU * phase)) * flutter + breath * (rnd.random() * 2 - 1)
    return formants(src, vowel)


def whoosh(dur, seed, bands=((350, 0.0), (800, 0.12), (1700, 0.24)), q=1.2, pan_sweep=False):
    """A gust: noise in a few bands, each swelling a little later than the
    one below (the gust's pitch rises through the leaves)."""
    air = noise(dur, seed)
    out = [0.0] * len(air)
    for f, lag in bands:
        band = biquad(air, "bp", f, q)
        for i, s in enumerate(band):
            t = i / RATE - lag
            x = t / max(1e-3, dur - lag - 0.05)
            e = math.sin(math.pi * x) ** 2 if 0 < x < 1 else 0.0
            out[i] += s * e
    return out


def rustle(dur, seed, density=180.0):
    """Leaves: a crackle of tiny high noise grains."""
    rnd = random.Random(seed)
    out = [0.0] * n(dur)
    t = 0.0
    while t < dur:
        t += rnd.expovariate(density)
        o = n(t)
        g = rnd.random() * math.sin(math.pi * min(1.0, t / dur))
        for i in range(n(0.006)):
            if o + i < len(out):
                out[o + i] += g * (rnd.random() * 2 - 1) * math.exp(-i / RATE * 600)
    return biquad(out, "hp", 2200)


def higurashi(dur, f=4300.0, seed=0):
    """The evening cicada's "kana-kana-kana": a pulsed high tone, fast then
    slowing and falling, swelling in and fading."""
    rnd = random.Random(seed)
    out = [0.0] * n(dur)
    t = 0.05
    sin, exp = math.sin, math.exp
    while t < dur - 0.06:
        x = t / dur
        rate = 22 - 12 * x
        pitch = f * (1 - 0.06 * x) * (1 + 0.01 * (rnd.random() - 0.5))
        g = sin(math.pi * x) ** 0.7 * (0.8 + 0.2 * rnd.random())
        o = n(t)
        for i in range(n(0.04)):
            if o + i >= len(out):
                break
            tt = i / RATE
            e = g * min(1.0, tt / 0.004) * exp(-tt * 70)
            ph = TAU * pitch * tt
            out[o + i] += e * (sin(ph + 0.8 * sin(TAU * 180 * tt)) + 0.3 * sin(2 * ph))
        t += 1 / rate
    return out


def phrase(m, inst, notes, t0, beat, gain=1.0, pan=0.0, base=0, legato=1.08, seed=0):
    """Place (semitones, beats) notes one after the other; None is a rest."""
    t = t0
    for k, (semi, beats) in enumerate(notes):
        if semi is not None:
            m.add(inst(note(base + semi), beats * beat * legato + 0.05, seed + k), t, gain, pan)
        t += beats * beat
    return t


def taiko(f=72.0, seed=0, big=1.0):
    """A big drum: "don"."""
    return scale(membrane(f, 1.2, drop=0.55, drop_rate=22, decay=5.5, hit=0.45, hit_f=600, seed=seed), big)


# ------------------------------------------------------------ modern
def pad(freqs, dur, seed=0, bright=2.4, attack=0.7, release=1.2, detune=0.006):
    """A warm string/synth pad: per note three slightly detuned saws and a
    sine an octave down, through a soft low-pass that breathes; slow attack,
    long release. Returns (left, right): each side detuned its own way, for
    width."""
    rnd = random.Random(seed)
    sides = []
    for side in range(2):
        out = [0.0] * n(dur)
        for f in freqs:
            phases = [rnd.random() for _ in range(3)]
            ratios = [1.0, 1 + detune * (0.6 + 0.4 * rnd.random()), 1 - detune * (0.6 + 0.4 * rnd.random())]
            y = 0.0
            sub = 0.0
            for i in range(len(out)):
                t = i / RATE
                saw = 0.0
                for k in range(3):
                    phases[k] = (phases[k] + f * ratios[k] / RATE) % 1.0
                    saw += 2 * phases[k] - 1
                sub += TAU * f * 0.5 / RATE
                cutoff = f * (bright + 0.6 * math.sin(TAU * 0.13 * t + side))
                a = 1 - math.exp(-TAU * cutoff / RATE)
                y += a * (saw / 3 - y)
                out[i] += (y + 0.35 * math.sin(sub)) * adsr(t, dur, attack, release)
        sides.append([v / max(1, len(freqs)) for v in out])
    return sides


def add_pad(mix, freqs, t, dur, gain=0.3, seed=0, **kw):
    """Place a stereo pad (pad()) in `mix`."""
    left, right = pad(freqs, dur, seed=seed, **kw)
    mix.add(left, t, gain, -0.7)
    mix.add(right, t, gain, 0.7)
    return mix


def felt_piano(f, dur=2.4, vel=0.7):
    """A soft felt piano (the muted, intimate modern piano): the piano,
    darker, with a slower hammer."""
    tone = biquad(piano(f, dur, vel), "lp", 1400 + f * 1.5, 0.6)
    return shaped(tone, lambda t: min(1.0, t / 0.006))


def sub_boom(f=45.0, dur=1.6):
    """A cinematic sub drop under a hit."""
    out = []
    phase = 0.0
    for i in range(n(dur)):
        t = i / RATE
        phase += TAU * f * (1 + 0.8 * math.exp(-t * 9)) / RATE
        out.append(math.sin(phase) * min(1.0, t / 0.004) * math.exp(-t * 2.6))
    return out


def riser(dur, seed=0, f_from=200.0, f_to=5000.0):
    """A swelling cinematic riser: noise sweeping up, getting louder, into a
    hit."""
    return shaped(swoosh(dur, seed, f_from, f_to, q=1.6, swell=False), lambda t: (t / dur) ** 2.2)


# -------------------------------------------------------------- speech
# Vowel formants (Hz) of an adult voice; speak() scales them for a smaller
# creature. Japanese u is unrounded (a higher second formant).
VOWELS = {
    "a": (800, 1250, 2600), "i": (300, 2300, 3000), "u": (350, 1300, 2400),
    "e": (480, 1900, 2600), "o": (480, 850, 2500), "w": (300, 650, 2300), "y": (280, 2400, 3000),
    "n": (260, 1500, 2600),
}


def speak(syllables, size=1.4, seed=0, rasp=0.0, breath=0.12):
    """A little creature saying something: `syllables` are dicts with
    dur (s), f0 (start Hz), to (end Hz), v (vowel), frm (vowel it glides in
    from), onset ("h" breathy, "p" a lip pop, "r" a tap), trill (Hz: a
    rolled r, "pururu"), gap (s of silence after). `size` scales the
    formants up (a smaller body)."""
    out = []
    for k, syl in enumerate(syllables):
        dur = syl["dur"]
        f_a, f_b = syl["f0"], syl.get("to", syl["f0"])
        target = VOWELS[syl["v"]]
        start = VOWELS[syl.get("frm", syl["v"])]
        glide = syl.get("glide", 0.35)

        def vowel(t, start=start, target=target, dur=dur, glide=glide):
            x = min(1.0, t / max(1e-3, dur * glide))
            x = x * x * (3 - 2 * x)
            fs = [(a + (b - a) * x) * size for a, b in zip(start, target)]
            return [(fs[0], 3.5, 1.0), (fs[1], 5.0, 0.6), (fs[2], 7.0, 0.25)]

        def f0(t, f_a=f_a, f_b=f_b, dur=dur):
            x = min(1.0, t / dur)
            return f_a * (f_b / f_a) ** (x ** 0.8)

        sig = voice(dur, f0, vowel, seed=seed + k, rasp=rasp, breath=breath, harsh=0.55)
        trill = syl.get("trill")
        rel = syl.get("release", 0.04)
        sig = shaped(sig, lambda t, dur=dur, trill=trill, rel=rel: adsr(t, dur, 0.012, rel)
                     * (0.35 + 0.65 * (0.5 + 0.5 * math.cos(TAU * trill * t)) if trill else 1.0))
        onset = syl.get("onset")
        if onset == "h":
            hiss = formants(noise(0.07, seed + 100 + k), lambda t, v=vowel: v(0.0))
            out.extend(shaped(hiss, lambda t: math.sin(math.pi * t / 0.07) * 0.9))
        elif onset == "p":
            out.extend(biquad(shaped(noise(0.012, seed + 200 + k), lambda t: math.exp(-t * 400)), "lp", 1500))
        elif onset == "r":
            sig = shaped(sig, lambda t: 0.3 if 0.01 < t < 0.028 else 1.0)
        out.extend(sig)
        out.extend([0.0] * n(syl.get("gap", 0.0)))
    return out


# -------------------------------------------------------------- effects
def glass(dur, seed, density=90.0, low=2200.0, high=9000.0):
    """Glass breaking: a crack, then a shower of tiny bright shards (each a
    short inharmonic ping) thinning out as they fall."""
    rnd = random.Random(seed)
    out = [0.0] * n(dur)
    crack = biquad(shaped(noise(0.05, seed), lambda t: math.exp(-t * 90)), "hp", 1800)
    for i, v in enumerate(crack):
        out[i] += 0.9 * v
    t = 0.0
    while t < dur - 0.05:
        t += rnd.expovariate(density * math.exp(-t * 3.5) + 4)
        f = low + (high - low) * rnd.random() ** 1.5
        shard = modal(f, 0.12, ((1.0, 1.0, 45, 0), (1.73, 0.5, 60, 0), (2.91, 0.3, 80, 0)))
        g = (0.25 + 0.75 * rnd.random()) * math.exp(-t * 2.2)
        o = n(t)
        for i, v in enumerate(shard):
            if o + i < len(out):
                out[o + i] += g * v
    return out


def gunshot(seed, body=110.0):
    """A sharp crack with a chesty thump under it and a short ringing tail."""
    crack = shaped(noise(0.25, seed), lambda t: min(1.0, t / 0.0004) * math.exp(-t * 55))
    crack = mono(scale(biquad(crack, "hp", 900), 1.0), scale(biquad(crack, "lp", 600), 0.8))
    thump = membrane(body, 0.3, drop=1.2, drop_rate=60, decay=18, hit=0.0)
    return mono(crack, scale(thump, 0.9))


def tick(f=2600.0, seed=0, tock=False):
    """A clock's escapement: a tiny metallic tick (a lower tock)."""
    return modal(f * (0.8 if tock else 1.0), 0.06, ((1.0, 1.0, 120, 0), (2.4, 0.5, 160, 0), (4.1, 0.3, 220, 0)),
                 strike=0.6, strike_f=f * 1.6, seed=seed)


def static(dur, seed, crackle=0.3):
    """TV static: band-limited hiss with a buzzy 60 Hz roughness and
    crackles."""
    rnd = random.Random(seed)
    hiss = biquad(biquad(noise(dur, seed), "hp", 500), "lp", 7000)
    out = []
    for i, v in enumerate(hiss):
        t = i / RATE
        buzz = 0.85 + 0.15 * math.sin(TAU * 60 * t)
        c = (rnd.random() * 2 - 1) * 3 if rnd.random() < crackle * 0.002 else 0.0
        out.append(v * buzz + c)
    return out


def tv_on(seed):
    """An old CRT switching on: a relay thunk, the degauss hum swelling and
    dying, the tube's whine sliding up, then static."""
    thunk = membrane(70, 0.35, drop=0.4, decay=14, hit=0.5, hit_f=500, seed=seed)
    hum = [math.sin(TAU * 60 * i / RATE) * 0.6 + 0.4 * math.sin(TAU * 120 * i / RATE) for i in range(n(0.9))]
    hum = shaped(hum, lambda t: min(1.0, t / 0.05) * math.exp(-t * 4.5))
    whine = []
    phase = 0.0
    for i in range(n(1.0)):
        t = i / RATE
        phase += TAU * (2000 + 5800 * min(1.0, t / 0.4)) / RATE
        whine.append(0.06 * math.sin(phase) * min(1.0, t / 0.05) * math.exp(-t * 1.5))
    hiss = shaped(static(1.0, seed + 1), lambda t: min(1.0, max(0.0, (t - 0.15) / 0.3)) * math.exp(-max(0.0, t - 0.6) * 4))
    return mono(thunk, scale(hum, 0.5), whine, scale(hiss, 0.35))


def vibrate(dur, seed=0, pulses=((0.0, 0.4), (0.55, 0.4))):
    """A phone buzzing on a desk: a rough low motor tone, in pulses."""
    rnd = random.Random(seed)
    out = [0.0] * n(dur)
    for start, d in pulses:
        o = n(start)
        phase = 0.0
        for i in range(n(d)):
            t = i / RATE
            phase += TAU * (165 + 6 * math.sin(TAU * 7 * t)) / RATE
            sq = 1.0 if math.sin(phase) > 0 else -1.0
            rattle = 1 + 0.4 * (rnd.random() - 0.5)
            if o + i < len(out):
                out[o + i] += 0.5 * sq * rattle * adsr(t, d, 0.01, 0.03)
    return biquad(out, "lp", 1200)


def swoosh(dur, seed, f_from=400.0, f_to=6000.0, q=2.0, swell=True):
    """A whoosh sweeping from f_from to f_to (a blade, a card, a cape);
    swell=False: the bare sweep, no rise and fall."""
    air = noise(dur, seed)
    out = [0.0] * len(air)
    x1 = x2 = y1 = y2 = 0.0
    for start in range(0, len(air), 128):
        x = start / max(1, len(air))
        f = f_from * (f_to / f_from) ** x
        w = TAU * min(f, RATE * 0.45) / RATE
        c, s_ = math.cos(w), math.sin(w)
        a = s_ / (2 * q)
        a0 = 1 + a
        b0, b2, a1, a2 = a / a0, -a / a0, -2 * c / a0, (1 - a) / a0
        for i in range(start, min(len(air), start + 128)):
            v = air[i]
            y = b0 * v + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, v, y1, y
            out[i] = y * (math.sin(math.pi * i / len(air)) ** 2 if swell else 1.0)
    return out


def brass(f, dur, seed=0, bright=1.0):
    """A brass section stab: a buzzy stack whose top opens with the attack
    (a filter sweep), a little growl."""
    rnd = random.Random(seed)
    src = []
    phase = 0.0
    for i in range(n(dur)):
        t = i / RATE
        phase = (phase + f * (1 + 0.003 * (rnd.random() - 0.5)) / RATE) % 1.0
        src.append(2 * phase - 1)
    out = [0.0] * len(src)
    y = 0.0
    for i, v in enumerate(src):
        t = i / RATE
        cutoff = f * (1.5 + 7 * bright * math.exp(-t * 6) * min(1.0, t / 0.03))
        a = 1 - math.exp(-TAU * cutoff / RATE)
        y += a * (v - y)
        out[i] = y * adsr(t, dur, 0.02, min(0.15, dur * 0.4))
    return out


def crash(dur=2.0, seed=0):
    """A crash cymbal: bright metallic noise with a long shimmering decay."""
    hiss = biquad(noise(dur, seed), "hp", 4000)
    metal = modal(420, dur, tuple((r, 0.2, 2.5 + r, 0) for r in (1.0, 1.47, 2.09, 2.56, 3.33, 4.17, 5.43, 6.8)))
    return shaped(mono(hiss, scale(metal, 0.3)), lambda t: min(1.0, t / 0.002) * math.exp(-t * 2.4))


def chime_westminster(beat=0.62, base=note(4)):
    """The Westminster Quarters (public domain, 1793) on tubular school
    bells — the Japanese school chime: the four changes."""
    tune = [(4, 0, 2, -5), (-5, 2, 4, 0), (4, 2, 0, -5), (-5, 2, 4, 0)]  # E C D G, G D E C, E D C G, G D E C
    notes = []
    for bar, phrase_ in enumerate(tune):
        for k, semi in enumerate(phrase_):
            notes.append(((bar * 4 + k) * beat + bar * beat * 0.6, note(semi + 12)))
    return notes


def tubular(f, dur=2.4, seed=0):
    """A tubular bell."""
    return modal(f, dur, ((1.0, 1.0, 1.2, 0.8), (2.76, 0.5, 2.0, 0), (5.4, 0.3, 3.0, 1.3), (8.9, 0.12, 4.5, 0)),
                 strike=0.1, strike_f=3500, seed=seed)


def fm_bell(f, dur, index=2.0, ratio=1.4, decay=3.0):
    """A glassy FM bell (a game menu's ping)."""
    out = []
    for i in range(n(dur)):
        t = i / RATE
        m = index * math.exp(-t * 6) * math.sin(TAU * f * ratio * t)
        out.append(math.sin(TAU * f * t + m) * min(1.0, t / 0.002) * math.exp(-decay * t))
    return out


# ----------------------------------------------------------------------- main
def run(variants):
    """sounds.py [out-dir] [variant | variant-kind ...]: write
    <variant>-<kind>.wav for every `variants[variant][kind]()` mix, into
    out-dir (default: next to the calling script); names after it pick a
    few (for quick listening)."""
    import __main__
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__main__.__file__))
    os.makedirs(out, exist_ok=True)
    only = sys.argv[2:]
    for name, kinds in variants.items():
        for kind, make in kinds.items():
            if only and name not in only and f"{name}-{kind}" not in only:
                continue
            write(os.path.join(out, f"{name}-{kind}.wav"), make())
