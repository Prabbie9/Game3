#!/usr/bin/env python3
"""Fetch CC0 assets from Poly Haven (api.polyhaven.com).

  fetch_polyhaven.py model NAME [RES]      -> assets/models/polyhaven/NAME/ (glTF + textures)
  fetch_polyhaven.py texture NAME [RES]    -> assets/textures/polyhaven/NAME/{albedo,normal,rough,ao,arm}.jpg
  fetch_polyhaven.py hdri NAME [RES]       -> assets/textures/hdri/NAME.hdr
Records each asset in ASSET_CREDITS.md (author from the API) if not already listed.
"""
import json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.polyhaven.com"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "PortSolano-asset-fetch/1.0 (Godot game project)"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def save(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if not os.path.exists(dest):
        open(dest, "wb").write(get(url))


def credit(name, kind, used_for):
    info = json.loads(get(f"{API}/info/{name}"))
    authors = ", ".join(info.get("authors", {}).keys()) or "Poly Haven"
    path = os.path.join(ROOT, "ASSET_CREDITS.md")
    text = open(path).read()
    url = f"https://polyhaven.com/a/{name}"
    if url not in text:
        with open(path, "a") as f:
            f.write(f"| {info.get('name', name)} ({kind}) | {used_for} | {authors} | {url} | CC0 |\n")


def model(name, res="1k"):
    files = json.loads(get(f"{API}/files/{name}"))
    g = files["gltf"].get(res) or files["gltf"][sorted(files["gltf"])[0]]
    g = g["gltf"]
    d = os.path.join(ROOT, "assets", "models", "polyhaven", name)
    save(g["url"], os.path.join(d, os.path.basename(g["url"])))
    for rel, inc in g.get("include", {}).items():
        save(inc["url"], os.path.join(d, rel))
    credit(name, "model", "city props")
    print("model", name, "->", os.path.relpath(d, ROOT))


def texture(name, res="2k"):
    files = json.loads(get(f"{API}/files/{name}"))
    d = os.path.join(ROOT, "assets", "textures", "polyhaven", name)
    wanted = {"Diffuse": "albedo", "nor_gl": "normal", "arm": "arm"}  # arm = AO/rough/metal (ORMMaterial3D)
    for key, out in wanted.items():
        if key in files and res in files[key]:
            fmt = "jpg" if "jpg" in files[key][res] else "png"
            save(files[key][res][fmt]["url"], os.path.join(d, f"{out}.{fmt}"))
    credit(name, "texture", "surfaces")
    print("texture", name, "->", os.path.relpath(d, ROOT))


def hdri(name, res="2k"):
    files = json.loads(get(f"{API}/files/{name}"))
    save(files["hdri"][res]["hdr"]["url"], os.path.join(ROOT, "assets", "textures", "hdri", f"{name}.hdr"))
    credit(name, "HDRI", "sky / reflections")
    print("hdri", name)


if __name__ == "__main__":
    kind, name = sys.argv[1], sys.argv[2]
    res = sys.argv[3] if len(sys.argv) > 3 else None
    {"model": model, "texture": texture, "hdri": hdri}[kind](name, *( [res] if res else []))
