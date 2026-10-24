#!/usr/bin/env python3
"""Ambient soundscape for Milestone 9: the city bed, surf, day birds and night crickets, a construction site, room
tone for interiors, gull cries, a distant airliner, a far-off siren, a ship's horn, wind on the hills and pigeons taking off.
Fetches the CC0 / CC-BY sources into assets/source/audio_src/amb (git-ignored), processes them (mono, filtered,
peak-normalised, crossfaded seamless loops) and synthesises the rest. Writes assets/audio/ambience/*.ogg.
Credits are in ASSET_CREDITS.md. Run: python3 tools/audio/build_ambience.py"""
import os, subprocess, urllib.request, zipfile
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "source", "audio_src")
CACHE = os.path.join(SRC, "amb")
OUT = os.path.join(ROOT, "assets", "audio", "ambience")
OGA = "https://opengameart.org/sites/default/files/"
RATE = 44100

FILES = ["sfx_100_v2.zip", "Seagull Ambient 1.wav", "Seagull Ambient 2.wav", "Seagull Ambient 3.wav",
         "Seagull Ambient 4.wav", "Seagull Ambient 5.wav", "wave_01_cc0-18363__jasinski__alkaibeach.flac",
         "wave_02_cc0-18363__jasinski__alkaibeach.flac", "wave_03_cc0-18363__jasinski__alkaibeach.flac",
         "wave_04_cc0-18363__jasinski__alkaibeach.flac", "birds-isaiah658_0.ogg", "crickets_1.mp3",
         "LAX Aiport Landing Sound Two.ogg"]


def fetch() -> None:
    os.makedirs(CACHE, exist_ok=True)
    for f in FILES:
        p = os.path.join(CACHE, f)
        if os.path.exists(p):
            continue
        print("  fetch", f)
        req = urllib.request.Request(OGA + urllib.request.quote(f), headers={"User-Agent": "Mozilla/5.0 PortSolano-build"})
        with urllib.request.urlopen(req, timeout=120) as r, open(p, "wb") as fh:
            fh.write(r.read())
    z = os.path.join(CACHE, "sfx_100_v2.zip")
    if not os.path.isdir(os.path.join(CACHE, "sfx100v2")):
        with zipfile.ZipFile(z) as zz:
            zz.extractall(os.path.join(CACHE, "sfx100v2"))


def decode(name: str) -> np.ndarray:
    path = name if os.path.isabs(name) else os.path.join(CACHE, name)
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def filt(x: np.ndarray, lo: float = 0.0, hi: float = 1e9, soft: float = 0.0) -> np.ndarray:
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1.0 / RATE)
    g = np.ones_like(fr)
    if soft > 0:   # gentle slopes (one-pole-ish) rather than brick walls
        g = 1.0 / np.sqrt(1.0 + (fr / hi) ** (2 * soft)) if hi < 1e9 else g
        if lo > 0:
            g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(fr, 1.0)) ** (2 * soft))
    else:
        g[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f * g, len(x))


def norm(x: np.ndarray, peak_db: float) -> np.ndarray:
    return x / (np.abs(x).max() + 1e-9) * 10 ** (peak_db / 20)


def loop(x: np.ndarray, xf: float) -> np.ndarray:
    """Seamless loop: the tail is crossfaded (equal power) into the head."""
    n = int(xf * RATE)
    body = x[:-n].copy()
    t = np.linspace(0, np.pi / 2, n)
    body[:n] = body[:n] * np.sin(t) + x[-n:] * np.cos(t)
    return body


def fades(x: np.ndarray, fin: float, fout: float) -> np.ndarray:
    x = x.copy()
    a, b = int(fin * RATE), int(fout * RATE)
    if a:
        x[:a] *= np.linspace(0, 1, a) ** 2
    if b:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def write(name: str, x: np.ndarray, q: int = 4) -> None:
    os.makedirs(OUT, exist_ok=True)
    x = np.clip(x, -1, 1)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-c:a", "libvorbis",
                    "-q:a", str(q), os.path.join(OUT, name)], input=(x * 32767).astype(np.int16).tobytes(), check=True)
    print("  wrote", name, "%.1f s" % (len(x) / RATE))


def noise(n: int, lo: float, hi: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return norm(filt(rng.standard_normal(n), lo, hi, 2.0), 0)


def city() -> np.ndarray:
    # distant traffic: the highway loop, two copies offset so passing cars don't repeat on a short cycle,
    # low-passed (it is heard over rooftops), with a low urban rumble underneath
    h = decode("sfx100v2/sfx100v2_loop_highway.ogg")
    n = len(h)
    x = h + np.roll(h, n // 2) * 0.7 + np.roll(h[::-1], n // 3) * 0.4
    x = filt(x, 40, 1800, 2.0)
    x += noise(n, 30, 160, 11) * np.abs(x).max() * 0.35
    return norm(loop(np.concatenate([x, x[:int(2.0 * RATE)]]), 2.0), -6)


def surf() -> np.ndarray:
    # waves breaking on the beach: the four recorded breakers scattered around a 36 s cycle (wrapped, so it loops)
    # over a soft wash of filtered noise
    n = 36 * RATE
    out = noise(n, 120, 2500, 5) * 0.08
    rng = np.random.default_rng(21)
    waves = [decode("wave_%02d_cc0-18363__jasinski__alkaibeach.flac" % i) for i in (1, 2, 3, 4)]
    t = 0.0
    while t < 36.0:
        w = waves[rng.integers(4)] * rng.uniform(0.55, 1.0)
        s = int(t * RATE)
        idx = (np.arange(len(w)) + s) % n
        np.add.at(out, idx, w)
        t += rng.uniform(4.5, 8.0)
    return norm(filt(out, 50, 7000, 2.0), -5)


def birds() -> np.ndarray:
    return norm(loop(filt(decode("birds-isaiah658_0.ogg"), 600, 12000, 2.0), 2.5), -7)


def crickets() -> np.ndarray:
    return norm(loop(filt(decode("crickets_1.mp3"), 1500, 12000, 2.0), 1.5), -9)


def construction() -> np.ndarray:
    return norm(loop(filt(decode("sfx100v2/sfx100v2_loop_construction_site.ogg"), 60, 9000, 2.0), 1.5), -3)


def room() -> np.ndarray:
    # interior room tone: the low air-handling hum, quiet and dark
    return norm(loop(filt(decode("sfx100v2/sfx100v2_loop_ambient_04.ogg"), 40, 900, 2.0), 1.5), -10)


def gull(i: int) -> np.ndarray:
    x = filt(decode("Seagull Ambient %d.wav" % i), 400, 10000, 2.0)
    a = np.abs(x)
    keep = np.where(a > a.max() * 0.03)[0]
    x = x[max(0, keep[0] - 400): keep[-1] + 2000]
    return norm(fades(x, 0.01, 0.15), -2)


def plane() -> np.ndarray:
    # an airliner high overhead: the landing recording's loudest 28 s, low-passed for distance, long fades
    x = decode("LAX Aiport Landing Sound Two.ogg")
    env = np.convolve(np.abs(x), np.ones(RATE) / RATE, "same")
    mid = int(np.argmax(env))
    a = max(0, mid - 16 * RATE)
    x = x[a: a + 28 * RATE]
    x = filt(x, 40, 2200, 2.0)
    return norm(fades(x, 8.0, 10.0), -3)


def siren_far() -> np.ndarray:
    # a siren somewhere across town: the wail, muffled by distance, swelling in and fading away (with a slight
    # downward pitch drift as it passes)
    x = decode(os.path.join(SRC, "siren", "siren.mp3"))[int(4.0 * RATE): int(18.0 * RATE)]
    drift = np.linspace(1.0, 0.94, len(x))
    pos = np.cumsum(drift)
    pos = pos[pos < len(x) - 1]
    x = np.interp(pos, np.arange(len(x)), x)
    x = filt(x, 200, 1500, 2.0)
    env = np.sin(np.linspace(0, np.pi, len(x))) ** 1.5
    return norm(x * env, -3)


def ship_horn() -> np.ndarray:
    # a ship's horn in the port: a low two-note chord with a slow onset, a little vibrato and a long tail
    n = int(4.5 * RATE)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for f, a in ((73.4, 1.0), (110.0, 0.6)):
        ph = 2 * np.pi * f * t + 0.6 * np.sin(2 * np.pi * 5.0 * t)
        for k in range(1, 9):
            x += a * np.sin(k * ph) / k ** 1.2
    env = np.clip(t / 0.35, 0, 1) * np.clip((3.6 - t) / 0.9, 0, 1)
    x = filt(x * env, 50, 900, 2.0)
    echo = np.zeros(n + RATE)
    echo[:n] += x
    echo[int(0.45 * RATE): int(0.45 * RATE) + n] += x * 0.3
    return norm(fades(echo, 0.0, 0.8), -2)


def flutter() -> np.ndarray:
    # pigeons taking off: a flurry of wing claps (short filtered-noise bursts, a few birds out of step)
    n = int(1.4 * RATE)
    out = np.zeros(n)
    rng = np.random.default_rng(17)
    for bird in range(6):
        t = rng.uniform(0.0, 0.25)
        rate = rng.uniform(9.0, 13.0)
        amp = rng.uniform(0.5, 1.0)
        while t < 1.2:
            s = int(t * RATE)
            m = int(0.035 * RATE)
            clap = noise(m, 300, 5000, int(rng.integers(1 << 30))) * np.exp(-np.arange(m) / (0.008 * RATE))
            out[s:s + m] += clap[: max(0, min(m, n - s))] * amp * (1.0 - t / 1.4)
            t += 1.0 / rate * rng.uniform(0.9, 1.1)
    return norm(fades(out, 0.0, 0.3), -3)


def wind() -> np.ndarray:
    # wind on the hills: band noise with slow gusts, 24 s, seamless
    n = 26 * RATE
    x = noise(n, 80, 1400, 8) * 0.7 + noise(n, 900, 4000, 9) * 0.15
    t = np.arange(n) / RATE
    rng = np.random.default_rng(4)
    g = sum(rng.uniform(0.2, 0.5) * np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) for f in (0.05, 0.11, 0.23))
    x *= 0.6 + 0.4 * (g - g.min()) / (g.max() - g.min())
    return norm(loop(x, 2.0), -8)


def main() -> None:
    fetch()
    write("city_loop.ogg", city())
    write("surf_loop.ogg", surf())
    write("birds_loop.ogg", birds())
    write("crickets_loop.ogg", crickets())
    write("construction_loop.ogg", construction())
    write("room_tone.ogg", room())
    write("wind_loop.ogg", wind())
    for i in range(1, 6):
        write("gull_%d.ogg" % (i - 1), gull(i))
    write("plane.ogg", plane())
    write("siren_far.ogg", siren_far())
    write("ship_horn.ogg", ship_horn())
    write("flutter.ogg", flutter())


if __name__ == "__main__":
    main()
