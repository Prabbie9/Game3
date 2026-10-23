#!/usr/bin/env python3
"""Synthesise police radio chatter (no recordings needed, so nothing to credit): a squelch click, band-passed
static, a garbled voice-like burble (formant-filtered noise with a syllable rhythm) and the closing squelch tone.
Writes assets/audio/police/radio_0..5.ogg. Run: python3 tools/audio/synth_radio.py"""
import os, subprocess
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio", "police")
RATE = 22050


def bandpass(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1.0 / RATE)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(x))


def formant_voice(dur, rng):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    # glottal-ish buzz with a wandering pitch
    pitch = 110 + 25 * np.sin(2 * np.pi * rng.uniform(0.3, 0.8) * t) + rng.uniform(-10, 20)
    phase = np.cumsum(pitch / RATE)
    buzz = (phase % 1.0) * 2 - 1
    buzz += rng.normal(0, 0.35, n)
    out = np.zeros(n)
    # syllables: alternating formant pairs, ~6 per second
    syl = int(RATE / rng.uniform(5.0, 7.5))
    for s0 in range(0, n, syl):
        seg = buzz[s0:s0 + syl]
        f1, f2 = rng.choice([(700, 1200), (400, 2000), (300, 900), (550, 1700), (450, 1000)])
        a = bandpass(seg, f1 - 120, f1 + 120) + 0.6 * bandpass(seg, f2 - 200, f2 + 200)
        env = np.sin(np.linspace(0, np.pi, len(seg))) ** 0.6
        if rng.random() < 0.15:
            env *= 0.1  # pauses between words
        out[s0:s0 + syl] = a * env
    return out


def squelch(dur, rng):
    n = int(dur * RATE)
    return bandpass(rng.normal(0, 1, n), 800, 3200) * np.linspace(1, 0, n) ** 2


def clip(seed):
    rng = np.random.default_rng(seed)
    parts = [squelch(0.08, rng) * 0.8]
    parts.append(formant_voice(rng.uniform(1.2, 2.6), rng))
    tone = np.sin(2 * np.pi * 1250 * np.arange(int(0.12 * RATE)) / RATE) * 0.35
    parts += [squelch(0.05, rng) * 0.5, tone, squelch(0.12, rng) * 0.9]
    x = np.concatenate(parts)
    # radio: narrow band, a bit of hiss and saturation
    x = bandpass(x, 350, 3000) + rng.normal(0, 0.03, len(x))
    x = np.tanh(x * 2.5 / (np.max(np.abs(x)) + 1e-6))
    return x / np.max(np.abs(x)) * 0.8


def main():
    os.makedirs(OUT, exist_ok=True)
    for i in range(6):
        x = clip(1000 + i)
        pcm = (x * 32767).astype(np.int16).tobytes()
        subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                        "-c:a", "libvorbis", "-q:a", "3", os.path.join(OUT, "radio_%d.ogg" % i)], input=pcm, check=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
