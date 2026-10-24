#!/usr/bin/env python3
"""Synthesise the menu sounds (no recordings, nothing to credit): a soft tick for moving/changing, a brighter
two-note blip for confirming, a lower falling blip for going back, and a short whoosh for opening a screen.
Writes assets/audio/ui/*.ogg. Run: python3 tools/audio/synth_ui.py"""
import os, subprocess
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio", "ui")
RATE = 44100


def env(n, attack, decay):
    t = np.arange(n) / RATE
    return np.minimum(t / attack, 1.0) * np.exp(-t / decay)


def tone(freq, dur, decay, harm=0.25):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    x = np.sin(2 * np.pi * freq * t) + harm * np.sin(2 * np.pi * freq * 2.01 * t)
    return x * env(n, 0.002, decay)


def click():
    x = tone(1850, 0.06, 0.012, 0.4)
    return x * 0.5


def select():
    a = tone(880, 0.07, 0.03)
    b = tone(1320, 0.12, 0.05)
    out = np.zeros(int(0.17 * RATE))
    out[:len(a)] += a
    out[int(0.05 * RATE):int(0.05 * RATE) + len(b)] += b
    return out * 0.45


def back():
    a = tone(990, 0.07, 0.03)
    b = tone(660, 0.12, 0.05)
    out = np.zeros(int(0.17 * RATE))
    out[:len(a)] += a
    out[int(0.05 * RATE):int(0.05 * RATE) + len(b)] += b
    return out * 0.4


def whoosh():
    n = int(0.28 * RATE)
    rng = np.random.default_rng(7)
    noise = rng.standard_normal(n)
    f = np.fft.rfft(noise)
    fr = np.fft.rfftfreq(n, 1.0 / RATE)
    f[(fr < 300) | (fr > 4000)] = 0
    x = np.fft.irfft(f, n)
    t = np.arange(n) / n
    x *= np.sin(np.pi * t) ** 2
    return x / np.abs(x).max() * 0.25


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in {"click": click, "select": select, "back": back, "open": whoosh}.items():
        x = np.clip(fn(), -1, 1)
        pcm = (x * 32767).astype(np.int16).tobytes()
        subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                        "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, name + ".ogg")], input=pcm, check=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
