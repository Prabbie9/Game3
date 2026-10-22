#!/usr/bin/env python3
"""Download Mixamo source files from the owner's shared Google Drive folder (public link).

The repo is public and Mixamo raw files must not be redistributed, so FBX files are never committed.
  tools/fetch_mixamo.py            -> fetch the files the game uses (assets/mixamo_manifest.json)
                                      into assets/source/mixamo/{characters,animations}/
  tools/fetch_mixamo.py --all      -> mirror the whole library into assets/source/mixamo_raw/
  tools/fetch_mixamo.py --grep TXT -> list library animation names containing TXT
Folder link: see tools/mixamo_index.json ("folder_url").
"""
import concurrent.futures as cf, json, os, re, shutil, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX = json.load(open(os.path.join(ROOT, "tools", "mixamo_index.json")))
RAW = os.path.join(ROOT, "assets", "source", "mixamo_raw")
USED = os.path.join(ROOT, "assets", "source", "mixamo")
URL = "https://drive.usercontent.google.com/download?id={}&export=download&confirm=t"


def snake(name):
    base = os.path.splitext(name)[0]
    base = re.sub(r"[^A-Za-z0-9]+", "_", base).strip("_").lower()
    return base + ".fbx"


def download(file_id, size, dest):
    if os.path.exists(dest) and (not size or os.path.getsize(dest) == size):
        return dest, "cached"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    last = None
    for attempt in range(5):
        try:
            tmp = dest + ".part"
            with urllib.request.urlopen(URL.format(file_id), timeout=120) as r, open(tmp, "wb") as f:
                shutil.copyfileobj(r, f, 1 << 20)
            with open(tmp, "rb") as f:
                head = f.read(20)
            if not head.startswith(b"Kaydara FBX"):
                raise IOError("not an FBX (Drive returned %r)" % head[:15])
            if size and os.path.getsize(tmp) != size:
                raise IOError("size mismatch %d != %d" % (os.path.getsize(tmp), size))
            os.replace(tmp, dest)
            return dest, "downloaded"
        except Exception as e:  # network hiccup or Drive throttling: back off and retry
            last = e
            time.sleep(2 ** attempt)
    raise RuntimeError("failed %s: %s" % (dest, last))


def fetch(jobs, workers=6):
    with cf.ThreadPoolExecutor(workers) as ex:
        futs = [ex.submit(download, *j) for j in jobs]
        done = 0
        for fu in cf.as_completed(futs):
            fu.result()
            done += 1
            if done % 100 == 0 or done == len(futs):
                print(f"  {done}/{len(futs)}", flush=True)


def main():
    if "--grep" in sys.argv:
        q = sys.argv[sys.argv.index("--grep") + 1].lower()
        for k in sorted(INDEX["animations"]):
            if q in k.lower():
                print(k)
        return
    if "--all" in sys.argv:
        jobs = [(i, s, os.path.join(RAW, "characters", n)) for n, (i, s) in INDEX["characters"].items()]
        jobs += [(i, s, os.path.join(RAW, "animations", n)) for n, (i, s) in INDEX["animations"].items()]
        fetch(jobs)
        return
    manifest = json.load(open(os.path.join(ROOT, "assets", "mixamo_manifest.json")))
    jobs = []
    for kind in ("characters", "animations"):
        for name in manifest[kind]:
            fid, size = INDEX[kind][name]
            dest = os.path.join(USED, kind, snake(name))
            raw = os.path.join(RAW, kind, name)
            if os.path.exists(raw) and os.path.getsize(raw) == size and not os.path.exists(dest):
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copy2(raw, dest)
            jobs.append((fid, size, dest))
    fetch(jobs)
    print(f"[fetch_mixamo] {len(jobs)} files ready in {os.path.relpath(USED, ROOT)}")


if __name__ == "__main__":
    main()
