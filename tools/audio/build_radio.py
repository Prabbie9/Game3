#!/usr/bin/env python3
"""Car radio stations for Milestone 9: royalty-free music (Kevin MacLeod / incompetech.com, CC-BY 4.0; a few CC0
tracks from OpenGameArt), fetched into assets/source/audio_src/music (git-ignored), trimmed to at most 3.5 min
with a fade, loudness-matched (EBU R128, -16 LUFS) and encoded to Ogg Vorbis. Each station also gets a short
synthesised ident (a chord sting and a sweep, no voice) and there is a tuning-static burst.
Writes assets/audio/radio/<station>/*.ogg and assets/audio/radio/stations.json (read by scripts/audio/radio.gd).
Run: python3 tools/audio/build_radio.py [--credits]"""
import json, os, subprocess, sys, urllib.parse, urllib.request
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, "assets", "source", "audio_src", "music")
OUT = os.path.join(ROOT, "assets", "audio", "radio")
KM = "https://incompetech.com/music/royalty-free/mp3-royaltyfree/%s.mp3"
KM_PAGE = "https://incompetech.com/music/royalty-free/music.html"
OGA = "https://opengameart.org/sites/default/files/"
CC_BY = "CC-BY 4.0"
RATE = 44100
MAX_LEN = 210.0

# station id -> (name, tagline, ident chord root Hz, tracks); track = (title, artist, license, url, page)
def km(title):
    return (title, "Kevin MacLeod", CC_BY, KM % urllib.parse.quote(title), KM_PAGE)


STATIONS = {
    "vibe": ("VIBE 94.1", "Funk & Soul", 220.0, [km("Funkorama"), km("Funky Chunk"), km("Groove Grove"), km("Vibe Ace"),
                                                 km("Disco con Tutti")]),
    "costa": ("COSTA 101.3", "Latin Sounds", 293.7, [km("Bossa Antigua"), km("Samba Isobel"), km("Latin Industries"),
                                                     km("Arroz Con Pollo")]),
    "reef": ("THE REEF 88.5", "Rock Radio", 164.8, [km("Big Rock"), km("Volatile Reaction"), km("Severe Tire Damage"),
                                                    km("Movement Proposition"), km("Cut and Run")]),
    "night": ("NIGHT SHIFT 103.7", "Electronic", 196.0, [
        ("Midnight Drive", "congusbongus", "CC0", OGA + "midnight_drive.ogg", "https://opengameart.org/content/midnight-drive"),
        km("Cyborg Ninja"), km("Ouroboros"),
        ("Midnight Cruiser", "Zane Little Music", "CC0", OGA + "midnight_cruiser.mp3", "https://opengameart.org/content/midnight-cruiser"),
        km("Club Diver")]),
    "lowtide": ("LOW TIDE 99.9", "Lounge & Lo-fi", 246.9, [km("Night on the Docks - Sax"), km("Smooth Lovin"),
        ("Chill Lofi", "omfgdude", "CC0", OGA + "ChillLofi.ogg", "https://opengameart.org/content/chill-lofi-inspired"),
        km("Dirt Rhodes"), km("Bass Walker")]),
}


def fetch(url: str) -> str:
    os.makedirs(CACHE, exist_ok=True)
    p = os.path.join(CACHE, urllib.parse.unquote(url.rsplit("/", 1)[1]))
    if not os.path.exists(p):
        print("  fetch", url)
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 PortSolano-build"})
        with urllib.request.urlopen(req, timeout=180) as r, open(p + ".part", "wb") as fh:
            fh.write(r.read())
        os.replace(p + ".part", p)
    return p


def encode_track(src: str, dst: str) -> float:
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", src],
                               capture_output=True, text=True, check=True).stdout.strip())
    length = min(dur, MAX_LEN)
    fade = 4.0 if dur > MAX_LEN else 0.5
    af = "loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=out:st=%.2f:d=%.2f" % (length - fade, fade)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-i", src, "-t", "%.2f" % length, "-af", af, "-ac", "2", "-ar", str(RATE),
                    "-c:a", "libvorbis", "-q:a", "2", dst], check=True)
    return length


def write_mono(path: str, x: np.ndarray) -> None:
    x = np.clip(x, -1, 1)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-c:a", "libvorbis",
                    "-q:a", "4", path], input=(x * 32767).astype(np.int16).tobytes(), check=True)


def ident(root: float, seed: int) -> np.ndarray:
    # a station sting: a rising sweep into a bright major-seventh chord with a little delay
    rng = np.random.default_rng(seed)
    n = int(2.6 * RATE)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    sweep = rng.standard_normal(int(0.6 * RATE))
    f = np.fft.rfft(sweep)
    fr = np.fft.rfftfreq(len(sweep), 1.0 / RATE)
    f[(fr < 1500) | (fr > 9000)] = 0
    sweep = np.fft.irfft(f, len(sweep))
    sweep *= np.linspace(0, 1, len(sweep)) ** 2 * 0.25 / (np.abs(sweep).max() + 1e-9)
    x[:len(sweep)] += sweep
    s = int(0.55 * RATE)
    for i, ratio in enumerate([1.0, 1.25, 1.5, 1.875, 2.0]):
        on = s + int(i * 0.06 * RATE)
        tt = t[: n - on]
        fq = root * ratio
        tone = (np.sin(2 * np.pi * fq * tt) + 0.35 * np.sin(2 * np.pi * fq * 2 * tt) + 0.15 * np.sin(2 * np.pi * fq * 3 * tt))
        x[on:] += tone * np.exp(-tt / 0.7) * 0.16
    d = int(0.18 * RATE)
    x[d:] += x[:-d] * 0.35
    x *= np.clip((2.6 - t) / 0.5, 0, 1)
    return x / np.abs(x).max() * 0.7


def static() -> np.ndarray:
    # tuning between stations: crackly band-limited noise with a whistle
    rng = np.random.default_rng(3)
    n = int(0.45 * RATE)
    x = rng.standard_normal(n)
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(n, 1.0 / RATE)
    f[(fr < 300) | (fr > 6000)] = 0
    x = np.fft.irfft(f, n)
    x /= np.abs(x).max()
    x *= (rng.random(n) > 0.002) * 0.6 + 0.4
    t = np.arange(n) / RATE
    x += 0.15 * np.sin(2 * np.pi * (2400 - 1800 * t / t[-1]) * t)
    x *= np.minimum(1.0, np.minimum(t / 0.02, (t[-1] - t) / 0.12))
    return x * 0.35


def credits() -> None:
    print("| Track | Artist | License | Source |\n|---|---|---|---|")
    for sid, (name, tag, _, tracks) in STATIONS.items():
        for title, artist, lic, url, page in tracks:
            print("| %s (%s) | %s | %s | %s |" % (title, name, artist, lic, page if "incompetech" not in url else url))


def main() -> None:
    if "--credits" in sys.argv:
        credits()
        return
    os.makedirs(OUT, exist_ok=True)
    meta = []
    for k, (sid, (name, tag, root, tracks)) in enumerate(STATIONS.items()):
        d = os.path.join(OUT, sid)
        os.makedirs(d, exist_ok=True)
        entry = {"id": sid, "name": name, "tag": tag, "ident": "radio/%s/ident.ogg" % sid, "tracks": []}
        for i, (title, artist, lic, url, page) in enumerate(tracks):
            dst = os.path.join(d, "%02d.ogg" % i)
            length = encode_track(fetch(url), dst)
            entry["tracks"].append({"file": "radio/%s/%02d.ogg" % (sid, i), "title": title, "artist": artist, "length": round(length, 2)})
            print("  %s %02d %-28s %5.1f s %4d KB" % (sid, i, title, length, os.path.getsize(dst) // 1024))
        write_mono(os.path.join(d, "ident.ogg"), ident(root, k))
        meta.append(entry)
    write_mono(os.path.join(OUT, "static.ogg"), static())
    with open(os.path.join(OUT, "stations.json"), "w") as fh:
        json.dump(meta, fh, indent=1)


if __name__ == "__main__":
    main()
