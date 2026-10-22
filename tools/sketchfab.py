#!/usr/bin/env python3
"""Sketchfab Data API helper (credentials are injected by the network proxy; nothing to configure).

  sketchfab.py search "QUERY" [cc0|by] [max_faces]  -> list downloadable models
  sketchfab.py get UID DEST_DIR "used for"          -> download glTF zip, unzip, record credit
Only CC0 / CC-BY models are allowed (never NC/ND/Store).
"""
import io, json, os, sys, urllib.parse, urllib.request, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.sketchfab.com/v3"
ALLOWED = {"cc0": "CC0", "by": "CC-BY 4.0"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "PortSolano/1.0"}), timeout=180) as r:
        return r.read()


def search(q, lic="cc0", max_faces=200000):
    out = []
    for lic_ in ([lic] if lic in ALLOWED else list(ALLOWED)):
        p = urllib.parse.urlencode({"type": "models", "q": q, "downloadable": "true", "license": lic_, "count": 24,
                                    "max_face_count": max_faces, "sort_by": "-likeCount"})
        for m in json.loads(get(f"{API}/search?{p}"))["results"]:
            gl = (m.get("archives") or {}).get("gltf") or {}
            out.append((m["likeCount"], m["faceCount"], m["uid"], lic_, m["user"]["username"], (gl.get("size") or 0) // 1024, m["name"]))
    for row in sorted(out, reverse=True):
        print("%5d likes %7d faces %s %-4s %-20s %7d KB  %s" % row)


def get_model(uid, dest, used_for):
    info = json.loads(get(f"{API}/models/{uid}"))
    lic = info["license"]["slug"] if isinstance(info.get("license"), dict) else ""
    if lic not in ALLOWED:
        sys.exit(f"license {lic!r} not allowed")
    dl = json.loads(get(f"{API}/models/{uid}/download"))
    data = get(dl["gltf"]["url"])
    d = os.path.join(ROOT, dest)
    os.makedirs(d, exist_ok=True)
    zipfile.ZipFile(io.BytesIO(data)).extractall(d)
    path = os.path.join(ROOT, "ASSET_CREDITS.md")
    url = info["viewerUrl"]
    if url not in open(path).read():
        with open(path, "a") as f:
            f.write(f"| {info['name']} (Sketchfab) | {used_for} | {info['user']['displayName']} ({info['user']['username']}) | {url} | {ALLOWED[lic]} |\n")
    print(f"{info['name']}: {info['faceCount']} faces, license {ALLOWED[lic]} -> {dest}")


if __name__ == "__main__":
    if sys.argv[1] == "search":
        search(sys.argv[2], *(sys.argv[3:4] or ["any"]), *( [int(sys.argv[4])] if len(sys.argv) > 4 else []))
    else:
        get_model(sys.argv[2], sys.argv[3], sys.argv[4])
