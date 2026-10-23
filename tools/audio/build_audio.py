#!/usr/bin/env python3
"""Fetch the game's CC0 / CC-BY sound sources and process them into assets/audio/.

Sources are cached in assets/source/audio_src/ (git-ignored); the processed files are committed.
Processing: mono, peak normalisation, silence trim + short fade on one-shots, crossfaded seamless loops.
Every source is credited in ASSET_CREDITS.md (this script prints the table with --credits).

    python3 tools/audio/build_audio.py [--credits]
"""
import io, os, subprocess, sys, urllib.request, zipfile, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, "assets/source/audio_src")
OUT = os.path.join(ROOT, "assets/audio")
OGA = "https://opengameart.org/sites/default/files/"
SR = 44100

# pack id -> (url, author, license, page); zips are unpacked into CACHE/<id>/
PACKS = {
    "race": (None, "domasx2", "CC0", "https://opengameart.org/content/racing-car-engine-sound-loops"),
    "carpack": (OGA + "car_sound_effects_pack.zip", "GGBotNet", "CC0", "https://opengameart.org/content/car-sound-effects-pack-low-quality"),
    "heavy": (None, "Nayckron", "CC-BY 3.0", "https://opengameart.org/content/engine-loop-heavy-vehicletank"),
    "squeal": (OGA + "tires_squal_loop.wav", "qubodup", "CC-BY 3.0", "https://opengameart.org/content/car-tire-squeal-skid-loop"),
    "blinker": (OGA + "blinker01.wav", "looneybits", "CC0", "https://opengameart.org/content/car-blinker-sfx"),
    "crash": (OGA + "qubodup-crash.ogg", "qubodup", "CC0", "https://opengameart.org/content/crash-collision"),
    "sfx100": (OGA + "100-CC0-SFX_0.zip", "rubberduck", "CC0", "https://opengameart.org/content/100-cc0-sfx"),
    "bfh": (OGA + "sfx_breaking_and_falling.zip", "rubberduck", "CC0", "https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx"),
    "kenney": ("https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip", "Kenney", "CC0", "https://kenney.nl/assets/impact-sounds"),
    "glass": (OGA + "glass_breaking.wav", "TinyWorlds", "CC0", "https://opengameart.org/content/glass-break"),
    "chunky": (OGA + "Chunky%20Explosion.mp3", "Joth", "CC0", "https://opengameart.org/content/chunky-explosion"),
    "fire": (OGA + "fire.wav", "PagDev", "CC0", "https://opengameart.org/content/fireplace-sound-loop"),
    "rain": (OGA + "amb_rain_loop_1.ogg", "Kresiek The Furry", "CC0", "https://opengameart.org/content/amb-rain-loop-1"),
    "heli": (OGA + "helicopter.mp3", "aquinn", "CC0", "https://opengameart.org/content/helicopter-sounds"),
    "siren": (OGA + "siren.mp3", "aquinn", "CC0", "https://opengameart.org/content/sirens-and-alarm-noise"),
    "tabasco": (OGA + "sounds.zip", "Tabasco", "CC0", "https://opengameart.org/content/gunshot-sounds"),
    "bart_ak": (OGA + "ak47.ogg", "bart", "CC0", "https://opengameart.org/content/the-free-firearm-sound-library"),
    "bart_sil": (OGA + "silencer.wav", "bart", "CC0", "https://opengameart.org/content/hollywood-style-pistol-silencer-sound-effect"),
    "reloads": (None, "SpringySpringo", "CC0", "https://opengameart.org/content/gun-reload-sounds"),
    "launch": (OGA + "la.mp3", "qubodup", "CC-BY 3.0", "https://opengameart.org/content/4-projectile-launches"),
    "explo4": (None, "EZduzziteh", "CC0", "https://opengameart.org/content/explosions-4"),
    "swish": (OGA + "swishes.zip", "artisticdude", "CC0", "https://opengameart.org/content/swishes-sound-pack"),
}
SINGLE_FILES = {
    "race": ["loop_0.wav", "loop_1_0.wav", "loop_2_0.wav", "loop_3_0.wav", "loop_4_0.wav", "loop_5_0.wav"],
    "heavy": ["engine_heavy_slow_loop_0.ogg", "engine_heavy_average_loop_0.ogg", "engine_heavy_fast_loop_0.ogg"],
    "reloads": ["assaultriflereload1_0.wav", "gunreload1.wav", "shotguncock_0.wav"],
    "explo4": ["explosion1_0.ogg", "explosion3.ogg"],
}

# output (relative to assets/audio, .wav = 16-bit PCM, .ogg = Vorbis) -> (pack, file in pack, options)
# options: start/dur (s), loop (crossfade s), peak (dBFS), fade (s, one-shot tail fade), rate
JOBS = {
    "vehicles/engine_idle.wav": ("race", "loop_0.wav", {"loop": 0, "peak": -3}),
    "vehicles/engine_low.wav": ("race", "loop_2_0.wav", {"loop": 0, "peak": -3}),
    "vehicles/engine_high.wav": ("race", "loop_5_0.wav", {"loop": 0, "peak": -3}),
    "vehicles/heavy_slow.wav": ("heavy", "engine_heavy_slow_loop_0.ogg", {"loop": 0, "peak": -3}),
    "vehicles/heavy_mid.wav": ("heavy", "engine_heavy_average_loop_0.ogg", {"loop": 0, "peak": -3}),
    "vehicles/heavy_fast.wav": ("heavy", "engine_heavy_fast_loop_0.ogg", {"loop": 0, "peak": -3}),
    "vehicles/tyre_squeal.wav": ("squeal", "tires_squal_loop.wav", {"loop": 0.35, "peak": -3}),
    "vehicles/horn.wav": ("carpack", "Car_Horn.ogg", {"start": 0.08, "dur": 0.34, "loop": 0.08, "peak": -2}),
    "vehicles/engine_start.ogg": ("carpack", "Car_Engine_Start_Up.ogg", {"peak": -2, "fade": 0.15}),
    "vehicles/engine_stop.ogg": ("carpack", "Car_Engine_Turning_Off.ogg", {"peak": -4, "fade": 0.2}),
    "vehicles/door_open.ogg": ("carpack", "Car_Door_Open.ogg", {"peak": -3, "fade": 0.05}),
    "vehicles/door_close.ogg": ("carpack", "Car_Door_Close.ogg", {"peak": -2, "fade": 0.08}),
    "vehicles/indicator.wav": ("blinker", "blinker01.wav", {"peak": -8}),
    "vehicles/crash_0.ogg": ("crash", "qubodup-crash.ogg", {"peak": -1, "fade": 0.08}),
    "vehicles/crash_1.ogg": ("sfx100", "slam_02.ogg", {"peak": -1, "fade": 0.08}),
    "vehicles/crash_2.ogg": ("sfx100", "metal_05.ogg", {"peak": -2, "fade": 0.1}),
    "vehicles/crash_3.ogg": ("bfh", "bfh1_metal_hit_02.ogg", {"peak": -2, "fade": 0.08}),
    "vehicles/bump_0.ogg": ("kenney", "Audio/impactPlate_heavy_001.ogg", {"peak": -3, "fade": 0.06}),
    "vehicles/bump_1.ogg": ("kenney", "Audio/impactPlate_heavy_000.ogg", {"peak": -3, "fade": 0.06}),
    "vehicles/bump_2.ogg": ("kenney", "Audio/impactMetal_heavy_001.ogg", {"peak": -4, "fade": 0.06}),
    "vehicles/glass_0.ogg": ("glass", "glass_breaking.wav", {"peak": -2, "fade": 0.1}),
    "vehicles/glass_1.ogg": ("bfh", "bfh1_glass_breaking_01.ogg", {"peak": -2, "fade": 0.1}),
    "vehicles/explosion_0.ogg": ("chunky", "Chunky%20Explosion.mp3", {"peak": -1, "fade": 0.6}),
    "vehicles/explosion_1.ogg": ("sfx100", "explosion.ogg", {"peak": -1, "fade": 0.1}),
    "vehicles/fire_loop.ogg": ("fire", "fire.wav", {"start": 4.0, "dur": 9.0, "loop": 1.0, "peak": -4, "rate": 32000}),
    "vehicles/heli_loop.ogg": ("heli", "helicopter.mp3", {"start": 8.0, "dur": 8.0, "loop": 0.8, "peak": -2}),
    "vehicles/siren_loop.ogg": ("siren", "siren.mp3", {"start": 4.0, "dur": 12.0, "loop": 0.6, "peak": -2}),
    "world/rain_loop.ogg": ("rain", "amb_rain_loop_1.ogg", {"start": 2.0, "dur": 40.0, "loop": 2.0, "peak": -6, "rate": 32000}),
    "player/step_concrete_0.ogg": ("kenney", "Audio/footstep_concrete_000.ogg", {"peak": -6, "fade": 0.03}),
    "player/step_concrete_1.ogg": ("kenney", "Audio/footstep_concrete_001.ogg", {"peak": -6, "fade": 0.03}),
    "player/step_concrete_2.ogg": ("kenney", "Audio/footstep_concrete_002.ogg", {"peak": -6, "fade": 0.03}),
    "player/step_concrete_3.ogg": ("kenney", "Audio/footstep_concrete_003.ogg", {"peak": -6, "fade": 0.03}),
    "player/step_concrete_4.ogg": ("kenney", "Audio/footstep_concrete_004.ogg", {"peak": -6, "fade": 0.03}),
    "player/step_grass_0.ogg": ("kenney", "Audio/footstep_grass_000.ogg", {"peak": -7, "fade": 0.03}),
    "player/step_grass_1.ogg": ("kenney", "Audio/footstep_grass_001.ogg", {"peak": -7, "fade": 0.03}),
    "player/step_grass_2.ogg": ("kenney", "Audio/footstep_grass_002.ogg", {"peak": -7, "fade": 0.03}),
    "player/step_grass_3.ogg": ("kenney", "Audio/footstep_grass_003.ogg", {"peak": -7, "fade": 0.03}),
    "player/step_wood_0.ogg": ("kenney", "Audio/footstep_wood_000.ogg", {"peak": -6, "fade": 0.03}),
    "player/step_wood_1.ogg": ("kenney", "Audio/footstep_wood_001.ogg", {"peak": -6, "fade": 0.03}),
    "player/step_wood_2.ogg": ("kenney", "Audio/footstep_wood_002.ogg", {"peak": -6, "fade": 0.03}),
    "player/step_wood_3.ogg": ("kenney", "Audio/footstep_wood_003.ogg", {"peak": -6, "fade": 0.03}),
    "player/step_sand_0.ogg": ("kenney", "Audio/footstep_snow_000.ogg", {"peak": -9, "fade": 0.04}),
    "player/step_sand_1.ogg": ("kenney", "Audio/footstep_snow_001.ogg", {"peak": -9, "fade": 0.04}),
    "player/step_sand_2.ogg": ("kenney", "Audio/footstep_snow_002.ogg", {"peak": -9, "fade": 0.04}),
    "player/step_sand_3.ogg": ("kenney", "Audio/footstep_snow_003.ogg", {"peak": -9, "fade": 0.04}),
    "player/punch_0.ogg": ("kenney", "Audio/impactPunch_medium_000.ogg", {"peak": -3, "fade": 0.04}),
    "player/punch_1.ogg": ("kenney", "Audio/impactPunch_medium_002.ogg", {"peak": -3, "fade": 0.04}),
    "player/punch_2.ogg": ("kenney", "Audio/impactPunch_heavy_000.ogg", {"peak": -2, "fade": 0.04}),
    "player/body_fall.ogg": ("kenney", "Audio/impactSoft_heavy_001.ogg", {"peak": -3, "fade": 0.05}),
    "player/splash.ogg": ("sfx100", "splash_01.ogg", {"peak": -3, "fade": 0.1}),
    # weapons: single shots cut from multi-shot recordings (start/dur), tails faded
    "weapons/pistol_0.ogg": ("tabasco", "cz.wav", {"start": 0.21, "dur": 0.9, "peak": -1, "fade": 0.35}),
    "weapons/pistol_1.ogg": ("tabasco", "cz.wav", {"start": 2.80, "dur": 0.9, "peak": -1, "fade": 0.35}),
    "weapons/smg_0.ogg": ("bart_sil", "silencer.wav", {"start": 0.0, "dur": 0.55, "peak": -2, "fade": 0.2}),
    "weapons/rifle_0.ogg": ("bart_ak", "ak47.ogg", {"start": 0.25, "dur": 0.55, "peak": -1, "fade": 0.3}),
    "weapons/rifle_1.ogg": ("bart_ak", "ak47.ogg", {"start": 5.73, "dur": 0.55, "peak": -1, "fade": 0.3}),
    "weapons/shotgun_0.ogg": ("tabasco", "shotty.wav", {"peak": -1, "fade": 0.25}),
    "weapons/sniper_0.ogg": ("tabasco", "mosin.wav", {"start": 0.42, "dur": 1.3, "peak": -1, "fade": 0.6}),
    "weapons/launcher_0.ogg": ("launch", "la.mp3", {"start": 0.08, "dur": 1.3, "peak": -1, "fade": 0.5}),
    "weapons/explosion_0.ogg": ("explo4", "explosion1_0.ogg", {"peak": -1, "fade": 0.8}),
    "weapons/explosion_1.ogg": ("explo4", "explosion3.ogg", {"peak": -1, "fade": 0.4}),
    "weapons/reload_rifle.ogg": ("reloads", "assaultriflereload1_0.wav", {"peak": -4, "fade": 0.05}),
    "weapons/reload_pistol.ogg": ("reloads", "gunreload1.wav", {"peak": -4, "fade": 0.05}),
    "weapons/pump.ogg": ("reloads", "shotguncock_0.wav", {"peak": -4, "fade": 0.05}),
    "weapons/swing_0.ogg": ("swish", "swish-1.wav", {"peak": -4, "fade": 0.03}),
    "weapons/swing_1.ogg": ("swish", "swish-4.wav", {"peak": -4, "fade": 0.03}),
    "weapons/swing_2.ogg": ("swish", "swish-8.wav", {"peak": -4, "fade": 0.03}),
    "weapons/bullet_metal_0.ogg": ("kenney", "Audio/impactMetal_light_000.ogg", {"peak": -6, "fade": 0.04}),
    "weapons/bullet_metal_1.ogg": ("kenney", "Audio/impactMetal_light_003.ogg", {"peak": -6, "fade": 0.04}),
    "weapons/bullet_hard_0.ogg": ("kenney", "Audio/impactGeneric_light_000.ogg", {"peak": -7, "fade": 0.04}),
    "weapons/bullet_hard_1.ogg": ("kenney", "Audio/impactGeneric_light_002.ogg", {"peak": -7, "fade": 0.04}),
    "weapons/bullet_flesh_0.ogg": ("kenney", "Audio/impactSoft_medium_000.ogg", {"peak": -5, "fade": 0.04}),
    "weapons/bullet_flesh_1.ogg": ("kenney", "Audio/impactSoft_medium_002.ogg", {"peak": -5, "fade": 0.04}),
    "weapons/dry_fire.ogg": ("reloads", "gunreload1.wav", {"start": 1.27, "dur": 0.12, "peak": -10, "fade": 0.03}),
}


def fetch(pack: str) -> str:
    url = PACKS[pack][0]
    d = os.path.join(CACHE, pack)
    os.makedirs(d, exist_ok=True)
    files = SINGLE_FILES.get(pack)
    if files:
        base = PACKS[pack][3].replace("/content/" + PACKS[pack][3].rsplit("/", 1)[1], "/sites/default/files/")
        for f in files:
            p = os.path.join(d, f)
            if not os.path.exists(p):
                _get(OGA + f, p)
        return d
    name = url.rsplit("/", 1)[1]
    p = os.path.join(d, name)
    if not os.path.exists(p):
        _get(url, p)
        if name.endswith(".zip"):
            with zipfile.ZipFile(p) as z:
                for m in z.namelist():
                    if m.endswith("/"):
                        continue
                    # flatten one leading folder (packs differ) but keep Kenney's Audio/
                    rel = m.split("/", 1)[1] if pack in ("sfx100", "bfh", "carpack") and "/" in m else m
                    out = os.path.join(d, rel)
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    with open(out, "wb") as fh:
                        fh.write(z.read(m))
    return d


def _get(url: str, path: str) -> None:
    print("  fetch", url)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 PortSolano-build"})
    with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as fh:
        fh.write(r.read())


def find(d: str, name: str) -> str:
    p = os.path.join(d, name)
    if os.path.exists(p):
        return p
    want = os.path.basename(name).replace("%20", " ").lower()
    for root, _, files in os.walk(d):
        for f in files:
            if f.lower() == want or f.lower() == os.path.basename(name).lower():
                return os.path.join(root, f)
    raise FileNotFoundError(f"{name} in {d}")


def decode(path: str, rate: int) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(rate), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def process(x: np.ndarray, o: dict, rate: int) -> np.ndarray:
    if "start" in o:
        s = int(o["start"] * rate)
        x = x[s:s + int(o.get("dur", 1e9) * rate)] if "dur" in o else x[s:]
    x = x - np.mean(x)
    if "loop" in o:
        f = int(o["loop"] * rate)
        if f > 0:
            # equal-power crossfade of the tail into the head: the result loops without a click
            t = np.linspace(0, 1, f)
            head = x[:f] * np.sqrt(t) + x[-f:] * np.sqrt(1 - t)
            x = np.concatenate([head, x[f:-f]])
    else:
        # one-shot: trim leading silence, fade the tail
        thr = np.max(np.abs(x)) * 0.02
        nz = np.nonzero(np.abs(x) > thr)[0]
        if len(nz):
            x = x[max(nz[0] - int(0.004 * rate), 0):]
        fd = int(o.get("fade", 0.02) * rate)
        if fd > 0 and fd < len(x):
            x[-fd:] *= np.linspace(1, 0, fd) ** 2
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x / peak * 10 ** (o.get("peak", -1) / 20)
    return x


def write(path: str, x: np.ndarray, rate: int) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    if path.endswith(".wav"):
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(pcm)
    else:
        subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(rate), "-ac", "1", "-i", "-",
                        "-c:a", "libvorbis", "-q:a", "5", path], input=pcm, check=True)


def credits() -> None:
    used = sorted({j[0] for j in JOBS.values()})
    print("| Sound | Author | License | Source |\n|---|---|---|---|")
    for p in used:
        url, author, lic, page = PACKS[p]
        outs = ", ".join(sorted(os.path.basename(k) for k, v in JOBS.items() if v[0] == p))
        print(f"| {outs} | {author} | {lic} | {page} |")


def main() -> None:
    if "--credits" in sys.argv:
        credits()
        return
    os.makedirs(CACHE, exist_ok=True)
    open(os.path.join(CACHE, ".gdignore"), "w").close()  # raw sources: Godot shouldn't import them
    for out, (pack, name, o) in JOBS.items():
        d = fetch(pack)
        rate = o.get("rate", SR)
        x = process(decode(find(d, name), rate), o, rate)
        write(os.path.join(OUT, out), x, rate)
        print(f"{out:34s} {len(x) / rate:6.2f} s")


if __name__ == "__main__":
    main()
