#!/usr/bin/env python3
"""Street-furniture sounds for Milestone 9 (breakables, vending machines, payphones, hydrants, cash).
Takes CC0 clips from the packs tools/audio/build_audio.py already fetched (assets/source/audio_src: Kenney impact
sounds, rubberduck's 100 CC0 SFX and 75 breaking/falling/hit SFX) and synthesises the rest (water jet loop, coins,
payphone tones). Writes assets/audio/world/*.ogg and adds the credits. Run: python3 tools/audio/build_world_sfx.py"""
import glob, os, subprocess
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "source", "audio_src")
OUT = os.path.join(ROOT, "assets", "audio", "world")
RATE = 44100
COPY = {
    "metal_fall_0.ogg": ("bfh", "bfh1_metal_falling_01.ogg"), "metal_fall_1.ogg": ("bfh", "bfh1_metal_falling_02.ogg"),
    "metal_hit_0.ogg": ("bfh", "bfh1_metal_hit_01.ogg"), "metal_hit_1.ogg": ("bfh", "bfh1_metal_hit_02.ogg"),
    "bin_0.ogg": ("kenney", "impactTin_medium_000.ogg"), "bin_1.ogg": ("kenney", "impactTin_medium_001.ogg"),
    "bin_2.ogg": ("kenney", "impactTin_medium_002.ogg"),
    "machine_0.ogg": ("sfx100", "machine_01.ogg"), "can_drop.ogg": ("sfx100", "slam_01.ogg"),
    "glass_break.ogg": ("bfh", "bfh1_glass_breaking_02.ogg"),
}
CREDIT = {"bfh": ("rubberduck", "https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx"),
          "sfx100": ("rubberduck", "https://opengameart.org/content/100-cc0-sfx"),
          "kenney": ("Kenney", "https://kenney.nl/assets/impact-sounds")}


def find(pack, name):
    hits = glob.glob(os.path.join(SRC, pack, "**", name), recursive=True)
    if not hits:
        raise SystemExit(f"missing {pack}/{name}: run tools/audio/build_audio.py first")
    return hits[0]


def write(name, x):
    x = np.clip(x, -1, 1)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-c:a", "libvorbis",
                    "-q:a", "4", os.path.join(OUT, name)], input=(x * 32767).astype(np.int16).tobytes(), check=True)


def band(n, lo, hi, seed):
    rng = np.random.default_rng(seed)
    f = np.fft.rfft(rng.standard_normal(n))
    fr = np.fft.rfftfreq(n, 1.0 / RATE)
    f[(fr < lo) | (fr > hi)] = 0
    x = np.fft.irfft(f, n)
    return x / np.abs(x).max()


def water_loop():
    # a pressurised jet: broadband hiss with a slow surge; 4 s, ends where it starts (crossfaded)
    n = 4 * RATE
    x = band(n + RATE // 2, 250, 9000, 3) * 0.6 + band(n + RATE // 2, 80, 600, 4) * 0.4
    t = np.arange(len(x)) / RATE
    x *= 0.85 + 0.15 * np.sin(2 * np.pi * 0.5 * t)
    fade = RATE // 2
    out = x[:n].copy()
    ramp = np.linspace(0, 1, fade)
    out[:fade] = out[:fade] * ramp + x[n:n + fade] * (1 - ramp)
    return out * 0.5


def coins():
    out = np.zeros(int(0.6 * RATE))
    rng = np.random.default_rng(9)
    for k in range(7):
        start = int(rng.uniform(0, 0.35) * RATE)
        f = rng.uniform(2800, 5200)
        n = int(0.22 * RATE)
        t = np.arange(n) / RATE
        ping = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.76 * t)) * np.exp(-t / 0.05)
        out[start:start + n] += ping * rng.uniform(0.2, 0.4)
    return out * 0.6


def dial():
    # off-hook dial tone then a few touch tones
    t = np.arange(int(0.8 * RATE)) / RATE
    x = (np.sin(2 * np.pi * 350 * t) + np.sin(2 * np.pi * 440 * t)) * 0.18
    for i, (a, b) in enumerate([(697, 1209), (770, 1336), (852, 1477)]):
        tt = np.arange(int(0.12 * RATE)) / RATE
        x = np.concatenate([x, np.zeros(int(0.06 * RATE)), (np.sin(2 * np.pi * a * tt) + np.sin(2 * np.pi * b * tt)) * 0.2])
    return x


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = {}
    for out, (pack, name) in COPY.items():
        subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-i", find(pack, name), "-ac", "1", "-ar", str(RATE), "-af", "loudnorm=I=-18",
                        "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, out)], check=True)
        rows.setdefault(pack, []).append(out)
    write("water_jet.ogg", water_loop())
    write("coins.ogg", coins())
    write("payphone.ogg", dial())
    path = os.path.join(ROOT, "ASSET_CREDITS.md")
    text = open(path).read()
    for pack, files in rows.items():
        row = "| %s | %s | CC0 | %s |" % (", ".join(files), CREDIT[pack][0], CREDIT[pack][1])
        if row not in text:
            text = text.rstrip("\n") + "\n" + row + "\n"
    synth = "| water_jet.ogg, coins.ogg, payphone.ogg (assets/audio/world) | synthesised by tools/audio/build_world_sfx.py | own work | — |"
    if synth not in text:
        text = text.rstrip("\n") + "\n" + synth + "\n"
    open(path, "w").write(text)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
