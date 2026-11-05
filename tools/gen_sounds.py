#!/usr/bin/env python3
"""gen_sounds.py (v6.12.0): makes every sound effect and music loop of Track Rush.

Everything in assets/audio/ is synthesized here from code (noise, oscillators, filters, modal
resonances, a small sequencer): no recordings, no third-party packs, so nothing needs a licence
beyond the project's own. The engines are not here: they are synthesized live in the game
(audio/engine_voice.gd).

    python3 tools/gen_sounds.py [--only sfx|music] [--out assets/audio] [--names a,b] [--wav-music]

Needs Python 3.9+ and numpy; the music is written as Ogg Vorbis with ffmpeg (libvorbis) on the PATH.
Deterministic: every sound has its own fixed random seed, so a run writes the same files.

Effects (assets/audio/sfx/, 16-bit mono WAV, 44.1 kHz): loops are built in the frequency domain
or placed circularly, so they repeat without a seam (the game loops them whole); one-shots end in
silence. Music (assets/audio/music/, Ogg Vorbis q5 stereo): four loops of whole bars whose reverb
and delay tails wrap round to the start, so they loop cleanly as well.
"""
import argparse
import os
import shutil
import subprocess
import sys
import wave

import numpy as np

SR = 44100
TAU = 2 * np.pi


# ------------------------------------------------------------------ helpers

def rng(seed):
    return np.random.default_rng(seed)


def t_axis(n):
    return np.arange(n) / SR


def secs(s):
    return int(round(s * SR))


def db(x):
    return 10 ** (x / 20.0)


def norm_peak(x, peak_db):
    m = np.max(np.abs(x))
    return x if m == 0 else x * (db(peak_db) / m)


def norm_rms(x, rms_db, peak_db=None):
    """Scale to an RMS level; with peak_db, no louder than that peak either (loops: -1 dBFS)."""
    r = np.sqrt(np.mean(x ** 2))
    if r == 0:
        return x
    g = db(rms_db) / r
    if peak_db is not None:
        g = min(g, db(peak_db) / np.max(np.abs(x)))
    return x * g


def spectral(n, shape, r, periodic=True):
    """Noise of length n with magnitude spectrum shape(f) (f in Hz, numpy array) and random phase.
    Periodic over n samples: a seamless loop."""
    f = np.fft.rfftfreq(n, 1 / SR)
    mag = shape(f)
    ph = r.uniform(0, TAU, len(f))
    spec = mag * np.exp(1j * ph)
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.max(np.abs(x)) + 1e-12)


def fft_filter(x, resp, circular=False):
    """Zero-phase filter by multiplying the spectrum with resp(f). Pads (one-shots) unless circular (loops)."""
    n = len(x)
    m = n if circular else int(2 ** np.ceil(np.log2(n * 2)))
    X = np.fft.rfft(x, m)
    f = np.fft.rfftfreq(m, 1 / SR)
    y = np.fft.irfft(X * resp(f), m)
    return y[:n]


def bp_shape(fc, bw, order=2):
    """Band-pass magnitude response (Hz centre, bandwidth Hz)."""
    return lambda f: 1.0 / (1.0 + ((f - fc) / (bw / 2.0)) ** (2 * order)) ** 0.5


def lp_shape(fc, order=2):
    return lambda f: 1.0 / (1.0 + (f / fc) ** (2 * order)) ** 0.5


def hp_shape(fc, order=2):
    return lambda f: 1.0 / (1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order)) ** 0.5


def peaks_shape(peaks, floor=0.0):
    """Sum of resonant peaks [(Hz, bandwidth Hz, gain)] plus a floor."""
    def s(f):
        out = np.full_like(f, floor)
        for fc, bw, g in peaks:
            out += g / (1.0 + ((f - fc) / (bw / 2.0)) ** 2)
        return out
    return s


def env_ad(n, attack, decay, curve=1.0):
    """Attack (s) then exponential-ish decay to silence over `decay` s."""
    t = t_axis(n)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-5) * 5.0) ** curve
    return a * d


def fade_tail(x, s=0.02):
    n = min(len(x), secs(s))
    if n > 0:
        x[-n:] *= np.linspace(1, 0, n) ** 2
    return x


def fade_head(x, s=0.002):
    n = min(len(x), secs(s))
    if n > 0:
        x[:n] *= np.linspace(0, 1, n)
    return x


def modes(n, freqs, decays, gains, r=None, jitter=0.0):
    """Sum of exponentially decaying sines (modal synthesis): freq Hz, decay s (to -43 dB), gain."""
    t = t_axis(n)
    out = np.zeros(n)
    for f, d, g in zip(freqs, decays, gains):
        ph = 0 if r is None else r.uniform(0, TAU)
        fj = f * (1 + (r.uniform(-jitter, jitter) if r is not None and jitter else 0))
        out += g * np.sin(TAU * fj * t + ph) * np.exp(-t / d * 5.0)
    return out


def place_circular(n, grains, r):
    """Place grains (arrays) at random circular positions in a buffer of n (for loops)."""
    out = np.zeros(n)
    for g in grains:
        p = r.integers(0, n)
        k = len(g)
        end = p + k
        if end <= n:
            out[p:end] += g
        else:
            out[p:] += g[:n - p]
            out[:end - n] += g[n - p:]
    return out


def lp1(x, fc):
    """One-pole low-pass (time domain; used on short signals)."""
    k = 1 - np.exp(-TAU * fc / SR)
    y = np.empty_like(x)
    s = 0.0
    for i, v in enumerate(x):
        s += (v - s) * k
        y[i] = s
    return y


def write_wav(path, x, rate=SR):
    x = np.asarray(x)
    if x.ndim == 1:
        ch = 1
        data = x
    else:
        ch = x.shape[1]
        data = x.reshape(-1)
    pk = np.max(np.abs(data)) if len(data) else 0
    if pk > 1.0:
        print(f"  warning: {os.path.basename(path)} peaks at {pk:.3f}: limited", file=sys.stderr)
        data = np.tanh(data)
    pcm = np.clip(np.round(data * 32767), -32768, 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def stats(x):
    x = np.asarray(x)
    pk = np.max(np.abs(x))
    rms = np.sqrt(np.mean(x ** 2))
    return f"peak {20 * np.log10(pk + 1e-12):6.1f} dBFS, rms {20 * np.log10(rms + 1e-12):6.1f} dBFS, {len(x) / SR:5.2f} s"


# ------------------------------------------------------------------ car loops (seamless)

def sfx_tyre_squeal():
    """Tyre squeal: a wavering, tonal screech (narrow noise bands, harmonics), 2 s loop."""
    r = rng(11)
    n = secs(2.0)
    f0 = 1050.0
    peaks = [(f0, 70, 1.0), (f0 * 1.52, 90, 0.35), (f0 * 2.03, 120, 0.4), (f0 * 2.9, 160, 0.15), (f0 * 0.5, 50, 0.12)]
    x = spectral(n, peaks_shape(peaks, 0.004), r)
    # a little roughness: amplitude flutter at a few Hz (periodic over the loop)
    t = t_axis(n)
    am = 1.0 + 0.18 * np.sin(TAU * 7 * t / 2.0 * 2.0) + 0.1 * np.sin(TAU * 13 * t + 1.0)
    x = x * am
    x += 0.15 * spectral(n, bp_shape(3000, 3000), r)
    return norm_rms(x, -14, -1.0), True


def sfx_gravel():
    """Gravel under the tyres: dense crunching grains and a hiss bed, 2 s loop."""
    r = rng(12)
    n = secs(2.0)
    grains = []
    for _ in range(1400):
        k = r.integers(secs(0.0008), secs(0.004))
        g = r.standard_normal(k) * np.exp(-np.linspace(0, r.uniform(3, 8), k)) * r.uniform(0.2, 1.0) ** 2
        grains.append(g)
    x = place_circular(n, grains, r)
    x = fft_filter(x, lambda f: bp_shape(2200, 4200)(f) * (0.6 + 0.4 * lp_shape(6000)(f)), circular=True)
    # bigger stones: a few lower thocks
    stones = []
    for _ in range(90):
        k = secs(r.uniform(0.006, 0.02))
        tt = np.arange(k) / SR
        fr = r.uniform(250, 900)
        stones.append(np.sin(TAU * fr * tt) * np.exp(-tt * r.uniform(150, 400)) * r.uniform(0.3, 1.0))
    x = x / (np.max(np.abs(x)) + 1e-9) + 0.5 * place_circular(n, stones, r)
    x += 0.35 * spectral(n, bp_shape(1500, 2500), r)
    return norm_rms(x, -15, -1.0), True


def sfx_snow():
    """Packed snow: soft, squeaky crunch (lower, rounder grains), 2 s loop."""
    r = rng(13)
    n = secs(2.0)
    grains = []
    for _ in range(700):
        k = r.integers(secs(0.003), secs(0.012))
        tt = np.arange(k) / SR
        # a compressing crystal: a short burst of noise with a squeak resonance
        g = r.standard_normal(k) * np.sin(np.pi * np.arange(k) / k) ** 2
        g += 0.6 * np.sin(TAU * r.uniform(500, 1400) * tt) * np.sin(np.pi * np.arange(k) / k)
        grains.append(g * r.uniform(0.2, 1.0) ** 2)
    x = place_circular(n, grains, r)
    x = fft_filter(x, lambda f: bp_shape(1100, 2400)(f) * lp_shape(3500, 3)(f), circular=True)
    x = x / (np.max(np.abs(x)) + 1e-9) + 0.4 * spectral(n, lambda f: bp_shape(700, 1200)(f), r)
    return norm_rms(x, -16, -1.0), True


def sfx_road():
    """Tyre roar on asphalt: low, rolling noise, 2 s loop."""
    r = rng(14)
    n = secs(2.0)
    x = spectral(n, lambda f: lp_shape(500, 2)(f) * hp_shape(40, 2)(f) * (1 / np.sqrt(np.maximum(f, 20) / 20)), r)
    x += 0.25 * spectral(n, bp_shape(1200, 1200), r)
    return norm_rms(x, -16, -1.0), True


def sfx_wind():
    """Wind at speed: a broad rush with a slow swell, 4 s loop."""
    r = rng(15)
    n = secs(4.0)
    x = spectral(n, lambda f: bp_shape(700, 1600, 1)(f) * (1 / np.sqrt(np.maximum(f, 30) / 30)), r)
    x2 = spectral(n, bp_shape(2400, 2600, 1), r)
    t = t_axis(n)
    swell = 1.0 + 0.25 * np.sin(TAU * t / 4.0) + 0.12 * np.sin(TAU * 3 * t / 4.0 + 1.3)
    swell2 = 1.0 + 0.3 * np.sin(TAU * 2 * t / 4.0 + 0.5)
    x = x * swell + 0.35 * x2 * swell2
    return norm_rms(x, -16, -1.0), True


def sfx_scrape():
    """Scraping along a steel barrier: grit with stick-slip bursts ringing the rail's modes, 1.5 s loop."""
    r = rng(16)
    n = secs(1.5)
    rail = [(612, 25, 1.0), (1180, 30, 0.8), (1740, 40, 0.7), (2390, 50, 0.6), (3320, 70, 0.45), (4410, 90, 0.3), (5600, 120, 0.2)]
    ring = spectral(n, peaks_shape(rail, 0.02), r)
    grit = spectral(n, bp_shape(3500, 5000), r)
    # stick-slip: a train of bursts at irregular spacing, placed circularly
    am = np.zeros(n)
    pos = 0
    while pos < n:
        k = secs(r.uniform(0.008, 0.03))
        burst = np.exp(-np.linspace(0, 4, k)) * r.uniform(0.4, 1.0)
        end = min(n, pos + k)
        am[pos:end] += burst[:end - pos]
        pos += secs(r.uniform(0.012, 0.05))
    am = fft_filter(am, lp_shape(60), circular=True)
    am = 0.35 + am / (np.max(am) + 1e-9)
    x = (0.8 * ring + 0.5 * grit) * am
    return norm_rms(x, -15, -1.0), True


def sfx_nitro():
    """Nitro burning: a jet rush with a roar under it and a flutter, 2 s loop."""
    r = rng(17)
    n = secs(2.0)
    jet = spectral(n, lambda f: hp_shape(500, 1)(f) * lp_shape(9000, 1)(f) * (np.maximum(f, 200) / 2000) ** 0.15, r)
    roar = spectral(n, bp_shape(180, 260), r)
    t = t_axis(n)
    flutter = 1.0 + 0.12 * np.sin(TAU * 31 * t) + 0.08 * np.sin(TAU * 47 * t + 0.7)
    x = (0.7 * jet + 0.6 * roar) * flutter
    return norm_rms(x, -15, -1.0), True


# ------------------------------------------------------------------ car one-shots

def hit(size, seed):
    """A car body against a barrier: thump, crunch of panels, rail ring, a little debris."""
    r = rng(seed)
    dur = {0: 0.45, 1: 0.8, 2: 1.3}[size]
    n = secs(dur)
    t = t_axis(n)
    f_thump = [120, 85, 62][size]
    thump = np.sin(TAU * (f_thump * t + 30 * (1 - np.exp(-t * 30)) / 30)) * np.exp(-t * [40, 25, 16][size])
    crunch = r.standard_normal(n) * np.exp(-t * [45, 22, 12][size])
    crunch = fft_filter(crunch, lambda f: bp_shape([2600, 1900, 1500][size], [4000, 3800, 3500][size])(f))
    rail = modes(n, [612, 1180, 1740, 2390, 3320, 4410], [0.35, 0.3, 0.25, 0.2, 0.15, 0.1],
                 [0.5, 0.45, 0.35, 0.3, 0.2, 0.12], r, 0.03) * [0.35, 0.55, 0.7][size]
    body = modes(n, [210, 340, 520, 760], [0.12, 0.1, 0.08, 0.06], [0.6, 0.5, 0.35, 0.25], r, 0.05) * [0.3, 0.5, 0.7][size]
    debris = np.zeros(n)
    for _ in range([2, 6, 12][size]):
        p = r.integers(secs(0.04), max(secs(0.05), n - secs(0.05)))
        k = secs(r.uniform(0.004, 0.015))
        g = r.standard_normal(k) * np.exp(-np.linspace(0, 6, k)) * r.uniform(0.1, 0.4)
        debris[p:p + k] += g[:max(0, min(k, n - p))]
    debris = fft_filter(debris, hp_shape(1500))
    x = 0.9 * thump + 0.8 * crunch + rail + body + debris
    x = fade_tail(fade_head(x, 0.0005), 0.05)
    return norm_peak(x, [-6, -3, -1][size]), False


def sfx_land():
    """Landing after a jump: a deep thud, the suspension's clunk and a tyre chirp."""
    r = rng(21)
    n = secs(0.6)
    t = t_axis(n)
    thud = np.sin(TAU * (55 * t + 40 * (1 - np.exp(-t * 25)) / 25)) * np.exp(-t * 12)
    clunk = modes(n, [180, 290, 470], [0.08, 0.06, 0.05], [0.5, 0.35, 0.2], r)
    knock = r.standard_normal(n) * np.exp(-t * 60)
    knock = fft_filter(knock, bp_shape(900, 1400))
    chirp = np.zeros(n)
    k = secs(0.07)
    tt = t_axis(k)
    chirp[secs(0.01):secs(0.01) + k] = np.sin(TAU * 1100 * tt) * np.sin(np.pi * np.arange(k) / k) * 0.15
    x = thud + 0.6 * clunk + 0.4 * knock + chirp
    return norm_peak(fade_tail(fade_head(x, 0.001)), -3), False


def sfx_nitro_on():
    """The nitro lights: a rising whoosh and a low fwoomp."""
    r = rng(22)
    n = secs(0.7)
    t = t_axis(n)
    nz = r.standard_normal(n)
    # sweeping band-pass: render in chunks with rising centre
    out = np.zeros(n)
    chunk = secs(0.02)
    for s in range(0, n, chunk):
        fc = 600 + 5000 * min(1.0, s / secs(0.35))
        seg = nz[max(0, s - chunk):s + chunk * 2]
        y = fft_filter(seg, bp_shape(fc, fc * 1.2))
        a = s - max(0, s - chunk)
        out[s:s + chunk] = y[a:a + min(chunk, n - s)]
    env = np.clip(t / 0.06, 0, 1) * np.exp(-np.maximum(t - 0.12, 0) * 6)
    fw = np.sin(TAU * (70 * t + 60 * t * t)) * np.exp(-t * 7) * np.clip(t / 0.02, 0, 1)
    x = out * env + 0.7 * fw
    return norm_peak(fade_tail(x, 0.1), -4), False


def sfx_blowoff():
    """A turbo blow-off valve: pssh-tsh, a burst of air falling in pitch with a flutter at its start."""
    r = rng(23)
    n = secs(0.55)
    t = t_axis(n)
    nz = r.standard_normal(n)
    out = np.zeros(n)
    chunk = secs(0.015)
    for s in range(0, n, chunk):
        fc = 4200 * np.exp(-s / SR * 2.2) + 900
        seg = nz[max(0, s - chunk):s + chunk * 2]
        y = fft_filter(seg, bp_shape(fc, fc * 0.9))
        a = s - max(0, s - chunk)
        out[s:s + chunk] = y[a:a + min(chunk, n - s)]
    flutter = 1.0 - 0.6 * (np.sin(TAU * 28 * t) > 0.3) * np.exp(-t * 9)
    env = np.clip(t / 0.01, 0, 1) * np.exp(-t * 6.5)
    x = out * env * flutter
    return norm_peak(fade_tail(x, 0.08), -5), False


def sfx_respawn():
    """Back on the road: a short airy swish."""
    r = rng(24)
    n = secs(0.35)
    t = t_axis(n)
    x = fft_filter(r.standard_normal(n), bp_shape(2500, 3500)) * np.sin(np.pi * t / t[-1]) ** 2
    x += 0.3 * np.sin(TAU * (900 * t + 1800 * t * t)) * np.sin(np.pi * t / t[-1]) ** 3
    return norm_peak(x, -8), False


# ------------------------------------------------------------------ race and menu cues

def tone(n, f, harm=((1, 1.0),), decay=0.3, attack=0.003, vib=0.0):
    t = t_axis(n)
    out = np.zeros(n)
    for k, g in harm:
        out += g * np.sin(TAU * f * k * t + vib * np.sin(TAU * 5 * t))
    return out * env_ad(n, attack, decay)


def bell(n, f, decay=0.8, bright=1.0, r=None):
    """FM-ish bell: inharmonic partials with faster decays up high."""
    parts = [(1.0, 1.0, 1.0), (2.0, 0.5, 0.7), (2.76, 0.35 * bright, 0.5), (4.07, 0.2 * bright, 0.35), (5.4, 0.12 * bright, 0.25)]
    t = t_axis(n)
    out = np.zeros(n)
    for ratio, g, dk in parts:
        out += g * np.sin(TAU * f * ratio * t) * np.exp(-t / (decay * dk) * 5.0)
    return out * np.clip(t / 0.002, 0, 1)


def note_hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def sfx_count():
    """Countdown beep (3, 2, 1)."""
    n = secs(0.32)
    x = tone(n, 880, ((1, 1.0), (2, 0.25), (3, 0.12)), decay=0.28, attack=0.004)
    return norm_peak(fade_tail(x, 0.03), -5), False


def sfx_go():
    """GO!: a higher, longer beep with a shine."""
    n = secs(0.8)
    x = tone(n, 1760, ((1, 1.0), (2, 0.3), (3, 0.15), (4, 0.06)), decay=0.7, attack=0.004)
    x += 0.5 * tone(n, 880, ((1, 1.0), (2, 0.2)), decay=0.5)
    return norm_peak(fade_tail(x, 0.08), -4), False


def sfx_checkpoint():
    """Checkpoint: two quick bright bell notes (E6, B6)."""
    r = rng(31)
    n = secs(0.7)
    x = np.zeros(n)
    for i, m in enumerate([88, 95]):
        p = secs(0.06 * i)
        k = n - p
        x[p:] += bell(k, note_hz(m), 0.45, 0.8) * (0.8 if i == 0 else 1.0)
    return norm_peak(fade_tail(x, 0.05), -6), False


def sfx_lap():
    """A new lap: a rising three-note chime."""
    n = secs(1.0)
    x = np.zeros(n)
    for i, m in enumerate([84, 88, 91, 96]):
        p = secs(0.07 * i)
        x[p:] += bell(n - p, note_hz(m), 0.6, 0.9) * (0.7 + 0.1 * i)
    return norm_peak(fade_tail(x, 0.08), -5), False


def chord_stab(n, midis, r, bright=1.0, decay=0.9, detune=0.006):
    t = t_axis(n)
    out = np.zeros(n)
    for m in midis:
        f = note_hz(m)
        for d in (-detune, 0, detune):
            ph = r.uniform(0, TAU)
            # band-limited saw by additive partials
            k = 1
            while f * k < 12000 and k < 40:
                g = (1.0 / k) * np.exp(-k * 0.08 / bright)
                out += g * np.sin(TAU * f * (1 + d) * k * t + ph * k)
                k += 1
    return out * env_ad(n, 0.004, decay)


def sfx_finish():
    """The finish line: a whoosh into a bright major chord."""
    r = rng(33)
    n = secs(1.8)
    t = t_axis(n)
    sweep = fft_filter(r.standard_normal(n), bp_shape(3500, 6000)) * np.exp(-t * 4) * np.clip(t / 0.02, 0, 1)
    x = 0.5 * sweep + chord_stab(n, [72, 76, 79, 84], r, 1.0, 1.4)
    for i, m in enumerate([84, 88, 91, 96]):
        p = secs(0.05 + 0.06 * i)
        x[p:] += 0.5 * bell(n - p, note_hz(m), 0.9, 0.7)
    return norm_peak(fade_tail(x, 0.2), -2), False


def sfx_medal():
    """A medal: an ascending arpeggio with sparkle, landing on a held chord."""
    r = rng(34)
    n = secs(2.2)
    x = np.zeros(n)
    for i, m in enumerate([67, 71, 74, 79, 83, 86]):
        p = secs(0.075 * i)
        x[p:] += bell(n - p, note_hz(m + 12), 0.5, 0.8) * 0.6
    p = secs(0.45)
    x[p:] += chord_stab(n - p, [67, 71, 74, 79], r, 1.2, 1.6) * 0.6
    sparkle = np.zeros(n)
    for _ in range(22):
        q = r.integers(secs(0.3), secs(1.6))
        k = secs(0.25)
        sparkle[q:q + k] += bell(min(k, n - q), r.uniform(3500, 7000), 0.2, 0.4)[:max(0, min(k, n - q))] * r.uniform(0.05, 0.15)
    x += sparkle
    return norm_peak(fade_tail(x, 0.25), -2), False


def sfx_best():
    """A new personal best: a quick upward run and a shining two-chord answer."""
    r = rng(35)
    n = secs(1.6)
    x = np.zeros(n)
    for i, m in enumerate([76, 79, 83, 88]):
        p = secs(0.055 * i)
        x[p:] += bell(n - p, note_hz(m + 12), 0.35, 0.9) * 0.55
    p1 = secs(0.26)
    x[p1:] += chord_stab(n - p1, [65, 69, 72, 77], r, 1.0, 0.4) * 0.45
    p2 = secs(0.5)
    x[p2:] += chord_stab(n - p2, [67, 71, 74, 79, 83], r, 1.3, 1.2) * 0.55
    return norm_peak(fade_tail(x, 0.2), -2), False


def sfx_ui_move():
    """Menu move: a tiny soft tick."""
    n = secs(0.05)
    t = t_axis(n)
    x = np.sin(TAU * 2400 * t) * np.exp(-t * 180) + 0.5 * np.sin(TAU * 1200 * t) * np.exp(-t * 120)
    return norm_peak(fade_tail(fade_head(x, 0.0005), 0.01), -14), False


def sfx_ui_confirm():
    """Menu confirm: two quick rising blips."""
    n = secs(0.16)
    x = np.zeros(n)
    for i, f in enumerate([1320, 1980]):
        p = secs(0.045 * i)
        k = secs(0.09)
        tt = t_axis(k)
        g = (np.sin(TAU * f * tt) + 0.25 * np.sin(TAU * 2 * f * tt)) * np.exp(-tt * 45) * np.clip(tt / 0.002, 0, 1)
        x[p:p + k] += g[:max(0, min(k, n - p))]
    return norm_peak(fade_tail(x, 0.02), -9), False


def sfx_ui_back():
    """Menu back / close: one falling blip."""
    n = secs(0.12)
    t = t_axis(n)
    f = 1400 * np.exp(-t * 6)
    ph = TAU * np.cumsum(f) / SR
    x = (np.sin(ph) + 0.2 * np.sin(2 * ph)) * np.exp(-t * 35) * np.clip(t / 0.002, 0, 1)
    return norm_peak(fade_tail(x, 0.02), -11), False


def sfx_ui_error():
    """Refused (locked, not enough money): a low double buzz."""
    n = secs(0.3)
    t = t_axis(n)
    x = np.zeros(n)
    for p0 in (0.0, 0.13):
        p = secs(p0)
        k = secs(0.11)
        tt = t_axis(k)
        sq = np.sign(np.sin(TAU * 196 * tt)) * 0.5 + np.sin(TAU * 196 * tt)
        g = fft_filter(sq, lp_shape(1800)) * np.exp(-tt * 18) * np.clip(tt / 0.003, 0, 1)
        x[p:p + k] += g
    return norm_peak(fade_tail(x, 0.02), -9), False


def sfx_cash():
    """Bought: a cash register (a drawer clunk, the bell) and coins."""
    r = rng(41)
    n = secs(1.1)
    t = t_axis(n)
    clunk = modes(n, [160, 260, 410], [0.06, 0.05, 0.04], [0.8, 0.5, 0.3], r) + \
        0.4 * fft_filter(r.standard_normal(n), bp_shape(1200, 1500)) * np.exp(-t * 70)
    ding = np.zeros(n)
    p = secs(0.06)
    ding[p:] = bell(n - p, 2637, 0.9, 0.7) * 0.9 + bell(n - p, 3520, 0.7, 0.5) * 0.5
    coins = np.zeros(n)
    for i in range(9):
        q = secs(0.12 + 0.05 * i + r.uniform(-0.015, 0.015))
        k = secs(0.18)
        f = r.uniform(4200, 6500)
        c = modes(k, [f, f * 1.47, f * 2.13], [0.12, 0.09, 0.06], [0.5, 0.3, 0.2], r)
        coins[q:q + k] += c[:max(0, min(k, n - q))] * (0.5 * 0.85 ** i)
    x = 0.8 * clunk + ding + coins
    return norm_peak(fade_tail(x, 0.15), -3), False


def sfx_unlock():
    """A track opens: a rising shimmer into a bright chime."""
    r = rng(42)
    n = secs(1.5)
    t = t_axis(n)
    riser = fft_filter(r.standard_normal(n), bp_shape(5000, 6000)) * np.clip(t / 0.4, 0, 1) ** 2 * np.exp(-np.maximum(t - 0.4, 0) * 8)
    x = 0.35 * riser
    for i, m in enumerate([79, 83, 86, 91, 95, 98]):
        p = secs(0.05 * i)
        x[p:] += bell(n - p, note_hz(m), 0.5, 0.8) * 0.35
    p = secs(0.38)
    x[p:] += bell(n - p, note_hz(91), 1.2, 1.0) * 0.8 + bell(n - p, note_hz(98), 1.0, 0.8) * 0.5
    return norm_peak(fade_tail(x, 0.2), -3), False


def sfx_key(seed):
    """A terminal key: a short mechanical click with a little body."""
    r = rng(seed)
    n = secs(0.06)
    t = t_axis(n)
    click = fft_filter(r.standard_normal(n), bp_shape(r.uniform(3500, 5000), 4000)) * np.exp(-t * 400)
    thock = modes(n, [r.uniform(300, 420), r.uniform(900, 1200)], [0.025, 0.015], [0.6, 0.3], r)
    bottom = np.zeros(n)
    p = secs(r.uniform(0.008, 0.014))
    k = n - p
    bottom[p:] = fft_filter(r.standard_normal(k), bp_shape(2000, 2500)) * np.exp(-t_axis(k) * 300) * 0.4
    x = click + 0.7 * thock + bottom
    return norm_peak(fade_tail(fade_head(x, 0.0003), 0.01), -12), False


def sfx_key_enter():
    r = rng(55)
    x, _ = sfx_key(56)
    n = secs(0.09)
    y = np.zeros(n)
    y[:len(x)] += x
    t = t_axis(n)
    y += 0.4 * modes(n, [220, 640], [0.04, 0.03], [0.5, 0.3], r)
    return norm_peak(fade_tail(y, 0.015), -10), False


SFX = {
    # car loops
    "tyre_squeal": sfx_tyre_squeal, "gravel": sfx_gravel, "snow": sfx_snow, "road": sfx_road, "wind": sfx_wind,
    "scrape": sfx_scrape, "nitro": sfx_nitro,
    # car one-shots
    "hit_light": lambda: hit(0, 1), "hit_medium": lambda: hit(1, 2), "hit_heavy": lambda: hit(2, 3), "land": sfx_land,
    "nitro_on": sfx_nitro_on, "blowoff": sfx_blowoff, "respawn": sfx_respawn,
    # race cues
    "count": sfx_count, "go": sfx_go, "checkpoint": sfx_checkpoint, "lap": sfx_lap, "finish": sfx_finish,
    "medal": sfx_medal, "best": sfx_best,
    # menus, shop, terminal
    "ui_move": sfx_ui_move, "ui_confirm": sfx_ui_confirm, "ui_back": sfx_ui_back, "ui_error": sfx_ui_error,
    "cash": sfx_cash, "unlock": sfx_unlock,
    "key1": lambda: sfx_key(51), "key2": lambda: sfx_key(52), "key3": lambda: sfx_key(53), "key4": lambda: sfx_key(54),
    "key_enter": sfx_key_enter,
}


# ------------------------------------------------------------------ music: instruments

WT = 4096  # wavetable size


def wave_tables(f, wave, cutoffs, q=0.75, poles=4):
    """One period of a band-limited `wave` at pitch f, low-passed at each cutoff (Hz): list of tables."""
    H = int(max(1, min(0.45 * SR / f, WT // 2 - 2)))
    k = np.arange(1, H + 1)
    if wave == "saw":
        base = 1.0 / k
    elif wave == "square":
        base = np.where(k % 2 == 1, 1.0 / k, 0.0)
    elif wave == "pulse":  # 25 % pulse
        base = np.abs(np.sin(np.pi * k * 0.25)) / k
    elif wave == "tri":
        base = np.where(k % 2 == 1, 1.0 / k ** 2, 0.0) * np.where((k // 2) % 2 == 0, 1.0, -1.0)
    else:  # sine
        base = np.where(k == 1, 1.0, 0.0)
    out = []
    for c in np.atleast_1d(cutoffs):
        x = k * f / c
        lp = 1.0 / np.sqrt((1 - x ** 2) ** 2 + (x / q) ** 2)
        lp = lp ** (poles / 2)
        spec = np.zeros(WT // 2 + 1, dtype=complex)
        spec[1:H + 1] = base * lp * -1j
        out.append(np.fft.irfft(spec, WT) * (WT / 2))
    return out


def osc(n, f, wave="saw", cut=None, q=0.75, poles=4, phase=0.0, vib=0.0, vib_hz=5.0, glide_from=None, glide_s=0.05):
    """A band-limited oscillator note of n samples. cut: None (no filter), a number (Hz) or an array of n
    cutoffs (filter envelope; interpolated between 10 tables). f may glide from glide_from."""
    t = t_axis(n)
    if glide_from:
        fr = f + (glide_from - f) * np.exp(-t / glide_s)
    else:
        fr = np.full(n, float(f))
    if vib:
        fr = fr * (1 + vib * np.sin(TAU * vib_hz * t))
    ph = (phase + np.cumsum(fr) / SR) % 1.0
    pos = ph * WT
    i0 = pos.astype(int) % WT
    i1 = (i0 + 1) % WT
    fr_ = pos - np.floor(pos)
    if cut is None or np.isscalar(cut):
        tb = wave_tables(f, wave, [cut if cut is not None else 0.45 * SR], q, poles if cut is not None else 0)[0]
        return tb[i0] + (tb[i1] - tb[i0]) * fr_
    cut = np.asarray(cut, dtype=float)
    lo, hi = max(40.0, cut.min()), max(cut.max(), cut.min() * 1.01 + 1)
    levels = np.geomspace(lo, hi, 10)
    tbs = wave_tables(f, wave, levels, q, poles)
    ci = np.clip(np.log(np.maximum(cut, lo) / lo) / np.log(hi / lo) * 9, 0, 9)
    j0 = np.floor(ci).astype(int)
    j1 = np.minimum(j0 + 1, 9)
    w = ci - j0
    vals = np.stack([tb[i0] + (tb[i1] - tb[i0]) * fr_ for tb in tbs])
    idx = np.arange(n)
    return vals[j0, idx] * (1 - w) + vals[j1, idx] * w


def adsr(n, a, d, s, r_, gate):
    """ADSR envelope: attack a, decay d to level s while the gate (s) is held, release r_ after."""
    t = t_axis(n)
    e = np.where(t < a, t / max(a, 1e-5), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-5) * 3))
    rel = np.where(t > gate, np.exp(-(t - gate) / max(r_, 1e-5) * 5), 1.0)
    return e * rel


def kick(r, punch=1.0, length=0.38, f_hi=170.0, f_lo=47.0):
    n = secs(length)
    t = t_axis(n)
    f = f_lo + (f_hi - f_lo) * np.exp(-t * 28)
    ph = TAU * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 6.5) ** 1.2
    click = fft_filter(r.standard_normal(n), bp_shape(3500, 4000)) * np.exp(-t * 300) * 0.35 * punch
    x = np.tanh(1.4 * body) + click
    return fade_tail(x, 0.03) * 0.95


def snare(r, tone_hz=190.0, length=0.25, bright=1.0):
    n = secs(length)
    t = t_axis(n)
    body = np.sin(TAU * tone_hz * t) * np.exp(-t * 28) * 0.6
    nz = fft_filter(r.standard_normal(n), lambda f: bp_shape(3800, 6500)(f) * (0.6 + 0.4 * bright)) * np.exp(-t * 18)
    return fade_tail(body + nz, 0.02) * 0.8


def clap(r, length=0.3):
    n = secs(length)
    t = t_axis(n)
    e = np.zeros(n)
    for off in (0.0, 0.009, 0.019, 0.03):
        p = secs(off)
        e[p:] += np.exp(-(t[:n - p]) * (120 if off < 0.03 else 14))
    nz = fft_filter(r.standard_normal(n), bp_shape(1500, 1800)) * e
    return fade_tail(nz, 0.03) * 0.8


def hat(r, open_=False):
    n = secs(0.3 if open_ else 0.06)
    t = t_axis(n)
    nz = fft_filter(r.standard_normal(n), lambda f: hp_shape(7500, 3)(f) * lp_shape(15000)(f))
    metal = sum(np.sign(np.sin(TAU * fr * t)) for fr in (3000, 4130, 5270, 6400)) * 0.08
    metal = fft_filter(metal, hp_shape(6000, 2))
    x = (nz + metal) * np.exp(-t * (11 if open_ else 70))
    return fade_tail(x, 0.01) * (0.32 if open_ else 0.28)


def crash(r):
    n = secs(2.2)
    t = t_axis(n)
    nz = fft_filter(r.standard_normal(n), lambda f: hp_shape(3500, 2)(f) * lp_shape(14000)(f))
    return fade_tail(nz * np.exp(-t * 2.3) * np.clip(t / 0.003, 0, 1), 0.2) * 0.35


def riser(r, length):
    n = secs(length)
    t = t_axis(n)
    nz = r.standard_normal(n)
    out = np.zeros(n)
    chunk = secs(0.05)
    for s in range(0, n, chunk):
        fc = 400 * (12000 / 400) ** (s / n)
        seg = nz[s:s + chunk]
        out[s:s + chunk] = fft_filter(seg, bp_shape(fc, fc))[:len(seg)]
    return out * (t / t[-1]) ** 2 * 0.25


def epiano(n, f, r, vel=1.0):
    """FM electric piano: a sine carrier with a decaying 1:1 modulator, plus a bell tine."""
    t = t_axis(n)
    idx = 1.6 * vel * np.exp(-t * 6)
    mod = np.sin(TAU * f * t) * idx
    car = np.sin(TAU * f * t + mod)
    tine = np.sin(TAU * f * 14 * t) * np.exp(-t * 40) * 0.08
    env = np.exp(-t * 1.8) * np.clip(t / 0.002, 0, 1)
    return (car + tine) * env * (1 + 0.08 * np.sin(TAU * 4.5 * t))


# ------------------------------------------------------------------ music: sequencer and mix

class Song:
    def __init__(self, name, bpm, bars, seed):
        self.name = name
        self.bpm = bpm
        self.bars = bars
        self.r = rng(seed)
        self.step = 60.0 / bpm / 4.0  # a 16th note (s)
        self.n = secs(self.step * 16 * bars)
        self.buses = {}
        self.kicks = []

    def at(self, bar, step):
        return secs((bar * 16 + step) * self.step)

    def add(self, bus, pos, sig, pan=0.0):
        """Add mono (or stereo) sig at sample pos, wrapping round the loop; pan -1..1 for mono."""
        if bus not in self.buses:
            self.buses[bus] = np.zeros((self.n, 2))
        b = self.buses[bus]
        if sig.ndim == 1:
            gl = np.cos((pan + 1) * np.pi / 4) * np.sqrt(2)
            gr = np.sin((pan + 1) * np.pi / 4) * np.sqrt(2)
            sig = np.stack([sig * gl, sig * gr], axis=1)
        pos %= self.n
        k = len(sig)
        while k > 0:
            m = min(k, self.n - pos)
            b[pos:pos + m] += sig[:m]
            sig = sig[m:]
            k -= m
            pos = 0

    def kick(self, bar, step, **kw):
        self.kicks.append(self.at(bar, step))
        self.add("drums", self.at(bar, step), kick(self.r, **kw))

    def sidechain(self, depth=0.6, release=0.16):
        g = np.ones(self.n)
        L = secs(release * 2.5)
        t = t_axis(L)
        curve = 1 - depth * np.exp(-t / release * 2.2) * np.clip(1 - t / (release * 2.5), 0, 1) ** 0.3
        for p in self.kicks:
            idx = (p + np.arange(L)) % self.n
            g[idx] = np.minimum(g[idx], curve)
        return g

    def render(self, sends, sc_buses=(), sc_depth=0.55, master_rms=-15.5):
        """Mix the buses: sends {bus: (gain, reverb send, delay send)}; sidechain the sc_buses."""
        sc = self.sidechain(sc_depth) if self.kicks else np.ones(self.n)
        dry = np.zeros((self.n, 2))
        rev_in = np.zeros((self.n, 2))
        dly_in = np.zeros((self.n, 2))
        for bus, sig in self.buses.items():
            g, rv, dl = sends.get(bus, (1.0, 0.0, 0.0))
            s = sig * g
            if bus in sc_buses:
                s = s * sc[:, None]
            dry += s
            rev_in += s * rv
            dly_in += s * dl
        wet_d = circular_delay(dly_in, secs(self.step * 3), 0.38)
        wet_r = circular_reverb(rev_in + wet_d * 0.4, self.r)
        mix = dry + wet_d + wet_r
        mix = mix - mix.mean(axis=0)
        mix = norm_rms(mix, master_rms)
        # soft limiter for the few peaks above -1 dBFS
        ceil = db(-1.0)
        mix = np.where(np.abs(mix) > ceil * 0.8, np.sign(mix) * (ceil * 0.8 + ceil * 0.2 * np.tanh((np.abs(mix) - ceil * 0.8) / (ceil * 0.2))), mix)
        return mix


def circular_delay(x, d, fb, taps=6):
    out = np.zeros_like(x)
    y = x.copy()
    for k in range(1, taps + 1):
        y = np.roll(y, d, axis=0) * fb
        y[:, 0], y[:, 1] = y[:, 1].copy(), y[:, 0].copy()  # ping-pong
        out += y
    return fft_filter_st(out, lp_shape(4500), circular=True)


def fft_filter_st(x, resp, circular=True):
    return np.stack([fft_filter(x[:, c], resp, circular) for c in range(x.shape[1])], axis=1)


def circular_reverb(x, r, length=2.4):
    """Convolution with a synthetic hall (frequency-dependent decay), circular over the loop."""
    n = len(x)
    L = secs(length)
    t = t_axis(L)
    ir = np.zeros((L, 2))
    bands = [(lp_shape(400, 2), 2.6), (lambda f: bp_shape(1500, 2400, 1)(f), 1.9), (lambda f: hp_shape(3500, 2)(f), 1.1)]
    for c in range(2):
        for resp, rt in bands:
            nz = fft_filter(r.standard_normal(L), resp)
            ir[:, c] += nz * np.exp(-t / rt * 6.9)
        ir[:secs(0.012), c] = 0
        for e in range(6):  # a few early reflections
            p = secs(r.uniform(0.012, 0.06))
            ir[p, c] += r.uniform(0.3, 0.6) * (1 if r.random() > 0.5 else -1)
    ir /= np.sqrt(np.sum(ir ** 2) / 2)
    out = np.zeros_like(x)
    for c in range(2):
        X = np.fft.rfft(x[:, c])
        h = np.zeros(n)
        h[:min(L, n)] = ir[:min(L, n), c]
        out[:, c] = np.fft.irfft(X * np.fft.rfft(h), n)
    return out * 0.32


def supersaw(n, f, r, voices=5, spread=0.012, cut=3000, q=0.7, wave="saw"):
    """Detuned saws spread across the stereo field: (n, 2)."""
    out = np.zeros((n, 2))
    for v in range(voices):
        d = (v - (voices - 1) / 2) / max(1, (voices - 1) / 2) * spread
        s = osc(n, f * (1 + d), wave, cut, q, phase=r.uniform())
        pan = (v - (voices - 1) / 2) / max(1, (voices - 1) / 2) * 0.8
        out[:, 0] += s * np.cos((pan + 1) * np.pi / 4)
        out[:, 1] += s * np.sin((pan + 1) * np.pi / 4)
    return out / np.sqrt(voices)


def pluck(n, f, r, wave="saw", c0=6000, c1=500, decay=0.18, q=0.9, amp_decay=0.35):
    t = t_axis(n)
    cut = c1 + (c0 - c1) * np.exp(-t / decay * 3)
    x = osc(n, f, wave, cut, q, phase=r.uniform())
    return x * np.exp(-t / amp_decay * 3) * np.clip(t / 0.002, 0, 1)


def bass_note(n, f, r, wave="saw", c0=1600, c1=250, decay=0.12, q=0.95, sub=0.6, gate=None):
    t = t_axis(n)
    cut = c1 + (c0 - c1) * np.exp(-t / decay * 3)
    x = osc(n, f, wave, cut, q, phase=0.0) * 0.6 + sub * osc(n, f, "sine")
    g = gate if gate is not None else t[-1] - 0.01
    env = adsr(n, 0.004, 0.25, 0.75, 0.03, g)
    return x * env


def pat(s):
    """Steps of a 16-step pattern string ('x' or digit hits)."""
    return [i for i, ch in enumerate(s) if ch != '.']


# ------------------------------------------------------------------ music: the four loops

def song_overdrive():
    """Race music 1, 'Overdrive': bright electro house, 128 BPM, A minor (Am F C G), 32 bars."""
    s = Song("overdrive", 128, 32, 101)
    r = s.r
    chords = [[57, 60, 64, 69], [57, 60, 65, 69], [55, 60, 64, 67], [55, 59, 62, 67]]
    roots = [33, 29, 36, 31]
    hook = [  # (bar in 4, step, midi, length in steps)
        (0, 0, 76, 2), (0, 3, 81, 1), (0, 4, 79, 2), (0, 6, 76, 2), (0, 8, 74, 2), (0, 10, 76, 4),
        (1, 0, 72, 2), (1, 3, 74, 1), (1, 4, 76, 2), (1, 6, 77, 2), (1, 8, 76, 2), (1, 10, 72, 4),
        (2, 0, 79, 2), (2, 3, 76, 1), (2, 4, 79, 2), (2, 6, 81, 2), (2, 8, 79, 2), (2, 10, 76, 2), (2, 12, 74, 2),
        (3, 0, 74, 2), (3, 3, 71, 1), (3, 4, 74, 2), (3, 6, 79, 4), (3, 12, 76, 4),
    ]
    for bar in range(32):
        c = bar % 4
        sec = bar // 8  # 0 A, 1 B, 2 C (breakdown), 3 D
        st = s.step
        # drums
        if sec != 2 or bar >= 22:
            for k in pat("x...x...x...x..."):
                s.kick(bar, k)
        elif bar % 2 == 0:
            s.kick(bar, 0)
        if sec != 2:
            for k in pat("....x.......x..."):
                s.add("drums", s.at(bar, k), clap(r), 0.0)
            for k in range(16):
                v = 0.55 if k % 4 == 2 else 0.3
                s.add("hats", s.at(bar, k), hat(r) * v, 0.25)
            for k in pat("..x...x...x...x."):
                s.add("hats", s.at(bar, k), hat(r, True) * 0.55, -0.2)
        if bar in (22, 23):  # build: snare roll
            steps = range(0, 16, 2) if bar == 22 else range(16)
            for k in steps:
                s.add("drums", s.at(bar, k), snare(r) * (0.4 + 0.5 * (k / 16 if bar == 23 else 0)), 0.0)
        if bar % 8 == 0:
            s.add("drums", s.at(bar, 0), crash(r), 0.1)
        if bar == 20:
            s.add("fx", s.at(bar, 0), riser(r, st * 16 * 4))
        # bass: off-beat octave bass (not in the first half of the breakdown)
        if not (sec == 2 and bar < 22):
            for k in pat("..x...x...x...x."):
                f = note_hz(roots[c] + (12 if k in (6, 14) else 0))
                s.add("bass", s.at(bar, k), bass_note(secs(st * 1.8), f, r, c0=2200, c1=300, decay=0.1, sub=0.5))
        else:
            s.add("bass", s.at(bar, 0), bass_note(secs(st * 15.5), note_hz(roots[c]), r, wave="sine", c0=400, c1=200, sub=0.8) * 0.8)
        # pads: supersaw chords
        cut = 1800 if sec == 0 else (3200 if sec != 2 else 1300 + 300 * (bar - 16))
        for m in chords[c]:
            p = supersaw(secs(st * 16), note_hz(m), r, 5, 0.011, cut)
            env = adsr(len(p), 0.02, 0.4, 0.85, 0.08, st * 15.6)
            s.add("pad", s.at(bar, 0), p * env[:, None] * 0.32)
        # arpeggio in the breakdown and the last section
        if sec >= 2:
            tones = [chords[c][1] + 12, chords[c][2] + 12, chords[c][3] + 12, chords[c][2] + 24]
            for k in range(16):
                f = note_hz(tones[k % 4])
                s.add("arp", s.at(bar, k), pluck(secs(st * 1.5), f, r, "square", 5000, 700, 0.06, 0.8, 0.12) * 0.32, 0.35 if k % 2 else -0.35)
        # the hook (sections B and D; D adds a third below)
        if sec in (1, 3):
            for (hb, k, m, ln) in hook:
                if hb != c:
                    continue
                n = secs(st * ln + 0.06)
                v = supersaw(n, note_hz(m), r, 3, 0.006, 4200, 0.9)
                env = adsr(n, 0.004, 0.18, 0.7, 0.06, st * ln)
                s.add("lead", s.at(bar, k), v * env[:, None] * 0.5)
                if sec == 3:
                    v2 = supersaw(n, note_hz(m - (3 if m in (72, 76, 79, 81) else 4)), r, 3, 0.006, 3500, 0.9)
                    s.add("lead", s.at(bar, k), v2 * env[:, None] * 0.25)
    return s.render({"drums": (1.0, 0.08, 0.0), "hats": (0.8, 0.05, 0.0), "bass": (0.9, 0.0, 0.0), "pad": (0.55, 0.35, 0.0),
                     "arp": (0.5, 0.25, 0.3), "lead": (0.6, 0.25, 0.25), "fx": (0.6, 0.4, 0.0)},
                    sc_buses=("bass", "pad", "arp"), sc_depth=0.6)


def song_neon():
    """Race music 2, 'Neon Rush': driving trance, 138 BPM, F minor (Fm Db Ab Eb), 32 bars."""
    s = Song("neon", 138, 32, 202)
    r = s.r
    chords = [[53, 56, 60, 65], [53, 56, 61, 65], [51, 56, 60, 63], [51, 55, 58, 63]]
    roots = [41, 37, 44, 39]
    melody = [  # long lead notes in the breakdown and the last section
        (0, 0, 84, 6), (0, 6, 80, 2), (0, 8, 82, 4), (0, 12, 84, 4),
        (1, 0, 85, 8), (1, 8, 84, 4), (1, 12, 80, 4),
        (2, 0, 84, 6), (2, 6, 87, 2), (2, 8, 84, 4), (2, 12, 80, 4),
        (3, 0, 82, 8), (3, 8, 79, 4), (3, 12, 82, 4),
    ]
    gate = pat("x.xx.x.xx.xx.x.x")
    for bar in range(32):
        c = bar % 4
        sec = bar // 8
        st = s.step
        if sec != 2:
            for k in pat("x...x...x...x..."):
                s.kick(bar, k, f_hi=180, f_lo=50)
            for k in pat("....x.......x..."):
                s.add("drums", s.at(bar, k), clap(r) * 0.9)
            for k in pat("..x...x...x...x."):
                s.add("hats", s.at(bar, k), hat(r, True) * 0.6, 0.2)
            if sec >= 1:
                for k in range(16):
                    s.add("hats", s.at(bar, k), hat(r) * (0.35 if k % 2 else 0.2), -0.3)
        elif bar >= 22:
            for k in range(0, 16, 4 if bar == 22 else 2):
                s.kick(bar, k, f_hi=180, f_lo=50)
            if bar == 23:
                for k in range(16):
                    s.add("drums", s.at(bar, k), snare(r, 210, 0.15) * (0.25 + 0.6 * k / 16))
        if bar % 8 == 0:
            s.add("drums", s.at(bar, 0), crash(r), -0.1)
        if bar == 20:
            s.add("fx", s.at(bar, 0), riser(r, st * 16 * 4))
        # rolling bass (between the kicks)
        if sec != 2:
            for k in pat(".xxx.xxx.xxx.xxx"):
                s.add("bass", s.at(bar, k), bass_note(secs(st * 0.95), note_hz(roots[c]), r, c0=2600, c1=350, decay=0.07, q=1.1, sub=0.45))
        # pluck arpeggio (everywhere but the start of the breakdown)
        if not (sec == 2 and bar < 20):
            seq = [0, 1, 2, 3, 2, 1, 2, 3]
            for k in range(0, 16):
                if k % 2 == 1 and sec == 0:
                    continue
                m = chords[c][seq[k % 8]] + 12
                s.add("arp", s.at(bar, k), pluck(secs(st * 2), note_hz(m), r, "saw", 7000, 600, 0.05, 1.0, 0.15) * 0.3, 0.3 if k % 2 else -0.3)
        # pad: a trance gate in sections B and D, held in the breakdown
        if sec >= 1:
            n = secs(st * 16)
            g = np.zeros(n)
            if sec == 2:
                g[:] = adsr(n, 0.3, 1.0, 1.0, 0.1, st * 15.8)
            else:
                for k in gate:
                    a, b = secs(st * k), secs(st * (k + 0.8))
                    seg = b - a
                    g[a:b] = np.minimum(1.0, np.linspace(1.0, 0.6, seg)) * np.clip(np.arange(seg) / secs(0.004), 0, 1)
            for m in chords[c]:
                p = supersaw(n, note_hz(m + 12), r, 5, 0.012, 3600 if sec != 2 else 2400)
                s.add("pad", s.at(bar, 0), p * g[:, None] * 0.24)
        # the lead melody
        if sec in (2, 3):
            for (mb, k, m, ln) in melody:
                if mb != c:
                    continue
                n = secs(st * ln + 0.08)
                v = supersaw(n, note_hz(m), r, 5, 0.008, 5000, 0.8)
                v = v + supersaw(n, note_hz(m - 12), r, 3, 0.006, 3000, 0.8) * 0.4
                env = adsr(n, 0.01, 0.4, 0.8, 0.1, st * ln)
                s.add("lead", s.at(bar, k), v * env[:, None] * 0.38)
    return s.render({"drums": (1.0, 0.07, 0.0), "hats": (0.75, 0.05, 0.0), "bass": (0.85, 0.0, 0.0), "pad": (0.5, 0.3, 0.1),
                     "arp": (0.55, 0.2, 0.4), "lead": (0.55, 0.35, 0.3), "fx": (0.6, 0.4, 0.0)},
                    sc_buses=("bass", "pad", "arp", "lead"), sc_depth=0.55)


def song_dust():
    """Race music 3, 'Dust Devil': rally breakbeat, 164 BPM, D minor (Dm Bb Gm A), 32 bars."""
    s = Song("dust", 164, 32, 303)
    r = s.r
    chords = [[50, 53, 57, 62], [50, 53, 58, 62], [50, 55, 58, 62], [49, 52, 57, 61]]
    roots = [38, 34, 31, 33]
    riff = [62, 65, 69, 74, 72, 69, 65, 64]
    riffs = [[0, 3, 7, 12, 10, 7, 3, 2], [-2, 2, 5, 10, 9, 5, 2, 0], [-7, -2, 2, 7, 5, 2, -2, -4], [-5, -1, 2, 7, 6, 2, -1, -3]]
    for bar in range(32):
        c = bar % 4
        sec = bar // 8
        st = s.step
        half = sec == 2 and bar < 22
        # two-step break
        if not half:
            for k in pat("x.........x....."):
                s.kick(bar, k, f_hi=150, f_lo=45, length=0.3)
            if bar % 2 == 1:
                s.kick(bar, 7, f_hi=150, f_lo=45, length=0.25)
            for k in pat("....x.......x..."):
                s.add("drums", s.at(bar, k), snare(r, 200, 0.28, 1.2))
            for k in pat("..........x...x.") if bar % 4 == 3 else []:
                s.add("drums", s.at(bar, k + 1), snare(r, 220, 0.12) * 0.3)
            for k in range(0, 16, 2):
                s.add("hats", s.at(bar, k), hat(r) * (0.45 if k % 4 == 2 else 0.25), 0.25)
            for k in range(1, 16, 4):
                s.add("hats", s.at(bar, k + 2), hat(r) * 0.15, -0.25)
        else:
            s.kick(bar, 0, f_hi=150, f_lo=45)
            s.add("drums", s.at(bar, 8), snare(r, 200, 0.3) * 0.7)
            for k in range(0, 16, 4):
                s.add("hats", s.at(bar, k), hat(r, True) * 0.3, 0.2)
        if bar in (22, 23):
            for k in range(0, 16, 2 if bar == 22 else 1):
                s.add("drums", s.at(bar, k), snare(r, 210, 0.12) * (0.3 + 0.5 * (k / 16)))
        if bar % 8 == 0:
            s.add("drums", s.at(bar, 0), crash(r), 0.0)
        if bar == 20:
            s.add("fx", s.at(bar, 0), riser(r, st * 16 * 4))
        # reese bass: two detuned saws, slowly opening filter, plus sub
        if not half:
            for (k, ln, iv) in ((0, 6, 0), (6, 4, 0), (10, 6, 7 if c in (0, 2) else 0)):
                n = secs(st * ln)
                f = note_hz(roots[c] + iv)
                t = t_axis(n)
                cut = 380 + 500 * np.sin(np.pi * t / t[-1])
                v = (osc(n, f * 1.007, "saw", cut, 0.8, phase=r.uniform()) + osc(n, f * 0.993, "saw", cut, 0.8, phase=r.uniform())) * 0.4
                v += 0.6 * osc(n, f, "sine")
                s.add("bass", s.at(bar, k), v * adsr(n, 0.006, 0.4, 0.8, 0.02, st * ln - 0.02))
        # stabs on the off-beats (B and D)
        if sec in (1, 3):
            for k in (6, 14):
                for m in chords[c]:
                    n = secs(st * 2)
                    v = supersaw(n, note_hz(m + 12), r, 3, 0.01, 5000, 0.8)
                    s.add("stab", s.at(bar, k), v * np.exp(-t_axis(n) * 14)[:, None] * 0.3)
        # pads in A and the breakdown
        if sec in (0, 2):
            for m in chords[c]:
                p = supersaw(secs(st * 16), note_hz(m), r, 4, 0.01, 1600 if sec == 0 else 2200)
                env = adsr(len(p), 0.25, 1.0, 0.9, 0.2, st * 15.5)
                s.add("pad", s.at(bar, 0), p * env[:, None] * 0.3)
        # the riff (D section and the end of B)
        if sec == 3 or (sec == 1 and bar >= 12) or (sec == 2 and bar >= 20):
            for k in range(0, 16, 2):
                m = 62 + riffs[c][k // 2]
                n = secs(st * 2)
                v = pluck(n, note_hz(m + 12), r, "square", 4500, 800, 0.08, 1.1, 0.22)
                v = np.tanh(v * 2.0) * 0.6
                s.add("lead", s.at(bar, k), v * 0.55, 0.0)
    return s.render({"drums": (1.0, 0.12, 0.0), "hats": (0.7, 0.06, 0.0), "bass": (0.8, 0.0, 0.0), "pad": (0.5, 0.35, 0.0),
                     "stab": (0.55, 0.3, 0.25), "lead": (0.6, 0.2, 0.35), "fx": (0.6, 0.4, 0.0)},
                    sc_buses=("bass", "pad"), sc_depth=0.4)


def song_menu():
    """Menu music, 'Pit Lane': warm, laid-back house, 108 BPM, D minor / F (Dm9 Bbmaj7 Fmaj7 C6), 16 bars."""
    s = Song("menu", 108, 16, 404)
    r = s.r
    chords = [[53, 57, 60, 64], [53, 57, 58, 62], [52, 57, 60, 64], [52, 55, 57, 60]]
    roots = [38, 34, 41, 36]
    tune = [  # a gentle bell melody in the second half
        (0, 0, 76, 3), (0, 4, 74, 2), (0, 6, 72, 2), (0, 10, 69, 6),
        (1, 2, 72, 2), (1, 4, 74, 4), (1, 10, 77, 6),
        (2, 0, 76, 3), (2, 4, 72, 2), (2, 6, 69, 4), (2, 12, 67, 4),
        (3, 2, 69, 2), (3, 4, 72, 3), (3, 8, 74, 8),
    ]
    swing = 0.18
    for bar in range(16):
        c = bar % 4
        st = s.step
        half = bar // 8

        def sw(k):
            return s.at(bar, k) + (secs(st * swing) if k % 2 == 1 else 0)
        for k in pat("x.......x.....x."):
            s.kick(bar, k, punch=0.5, f_hi=140, f_lo=48, length=0.32)
        for k in pat("....x.......x..."):
            s.add("drums", s.at(bar, k), clap(r) * 0.55, 0.05)
        for k in range(16):
            v = [0.3, 0.12, 0.22, 0.12][k % 4]
            s.add("hats", sw(k), hat(r) * v, 0.3)
        for k in pat("..x...x...x...x."):
            s.add("hats", s.at(bar, k), hat(r, True) * 0.18, -0.25)
        if bar % 8 == 0:
            s.add("drums", s.at(bar, 0), crash(r) * 0.5, 0.0)
        # bass: round, syncopated
        for (k, ln, iv) in ((0, 3, 0), (3, 3, 0), (6, 2, 12), (10, 2, 7), (14, 2, 0)):
            n = secs(st * ln)
            s.add("bass", sw(k), bass_note(n, note_hz(roots[c] + iv), r, "tri", 900, 300, 0.1, 0.7, 0.7) * 0.9)
        # electric piano chords on the off-beats
        for k in pat("..x....x..x....."):
            n = secs(st * 6)
            v = sum(epiano(n, note_hz(m), r, 1.15) for m in chords[c]) * 0.15
            s.add("keys", sw(k), np.stack([v * 0.9, v * 1.1], axis=1))
        # warm pad underneath
        for m in chords[c]:
            p = supersaw(secs(st * 16), note_hz(m - 12 if m > 56 else m), r, 4, 0.007, 2600, 0.7, "saw")
            env = adsr(len(p), 0.5, 1.0, 1.0, 0.3, st * 15.5)
            s.add("pad", s.at(bar, 0), p * env[:, None] * 0.3)
        # a shaker on the 16ths and a high shimmer: arpeggiated chord tones two octaves up, every bar
        for k in range(1, 16, 2):
            s.add("hats", sw(k), hat(r) * 0.16, -0.4)
        for k in pat("x..x..x...x..x.."):
            m = chords[c][(k // 3) % 4] + 24
            s.add("shine", sw(k), bell(secs(st * 3), note_hz(m), 0.35, 1.0) * 0.12, 0.5 if k % 2 else -0.5)
        # the bell tune (second half)
        if half == 1:
            for (tb, k, m, ln) in tune:
                if tb != c:
                    continue
                n = secs(st * ln + 0.6)
                s.add("lead", sw(k), bell(n, note_hz(m), 0.9, 0.5) * 0.4, 0.1)
    return s.render({"drums": (0.8, 0.12, 0.0), "hats": (2.2, 0.1, 0.0), "bass": (0.6, 0.0, 0.0), "pad": (0.45, 0.4, 0.0),
                     "keys": (1.1, 0.35, 0.2), "lead": (0.8, 0.45, 0.4), "shine": (1.0, 0.5, 0.3)},
                    sc_buses=("pad", "keys"), sc_depth=0.25, master_rms=-17.0)


MUSIC = {"menu": song_menu, "overdrive": song_overdrive, "neon": song_neon, "dust": song_dust}


# ------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--only", choices=["sfx", "music"], default=None)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio"))
    ap.add_argument("--names", default="", help="comma-separated names to make (default: all)")
    ap.add_argument("--wav-music", action="store_true", help="also keep the music as WAV (analysis)")
    a = ap.parse_args()
    names = set(x for x in a.names.split(",") if x)
    out = os.path.abspath(a.out)
    if a.only in (None, "sfx"):
        d = os.path.join(out, "sfx")
        os.makedirs(d, exist_ok=True)
        for name, fn in SFX.items():
            if names and name not in names:
                continue
            x, loop = fn()
            x = np.asarray(x, dtype=float)
            write_wav(os.path.join(d, name + ".wav"), x)
            print(f"sfx   {name:12s} {'loop' if loop else 'once'}  {stats(x)}")
    if a.only in (None, "music"):
        d = os.path.join(out, "music")
        os.makedirs(d, exist_ok=True)
        ff = shutil.which("ffmpeg")
        for name, fn in MUSIC.items():
            if names and name not in names:
                continue
            x = fn()
            wav = os.path.join(d, name + ".wav")
            write_wav(wav, x)
            print(f"music {name:12s} loop  {stats(x)}")
            if ff:
                ogg = os.path.join(d, name + ".ogg")
                subprocess.run([ff, "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
                if not a.wav_music:
                    os.remove(wav)
            else:
                print("  ffmpeg not found: kept the WAV", file=sys.stderr)


if __name__ == "__main__":
    main()
