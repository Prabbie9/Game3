#!/usr/bin/env python3
"""Force correct 3D import settings on PBR textures that are assigned to materials from code
(Godot can't auto-detect those): VRAM compression, mipmaps, normal-map flag, size limit.
Run before `godot --import`; idempotent."""
import glob, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["assets/textures/**/*.jpg", "assets/textures/**/*.png", "assets/models/**/*.png", "assets/models/**/*.jpg",
        "assets/models/**/*.jpeg"]
LIMIT = {"assets/models/sketchfab/pistol": 1024}


def params(path):
    rel = os.path.relpath(path, ROOT)
    normal = re.search(r"(normal|nor_gl|_n\.)", os.path.basename(path).lower()) is not None
    limit = next((v for k, v in LIMIT.items() if rel.startswith(k)), 0)
    return {
        "compress/mode": "2", "compress/high_quality": "false", "compress/lossy_quality": "0.7",
        "compress/normal_map": "1" if normal else "0", "compress/channel_pack": "0",
        "mipmaps/generate": "true", "mipmaps/limit": "-1",
        "roughness/mode": "0", "process/size_limit": str(limit),
        "detect_3d/compress_to": "0",
    }


def main():
    n = 0
    for pat in DIRS:
        for f in glob.glob(os.path.join(ROOT, pat), recursive=True):
            imp = f + ".import"
            want = params(f)
            if os.path.exists(imp):
                text = open(imp).read()
                changed = False
                for k, v in want.items():
                    new, c = re.subn(rf"^{re.escape(k)}=.*$", f"{k}={v}", text, flags=re.M)
                    if c == 0:
                        new = text.replace("[params]\n", f"[params]\n\n{k}={v}", 1) if "[params]" in text else text
                    if new != text:
                        text, changed = new, True
                if changed:
                    # drop cached dest so Godot reimports with the new params
                    text = re.sub(r"^valid=false\n", "", text, flags=re.M)
                    open(imp, "w").write(text)
                    n += 1
            else:
                body = "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[deps]\n\nsource_file=\"res://%s\"\n\n[params]\n\n" % os.path.relpath(f, ROOT)
                body += "\n".join(f"{k}={v}" for k, v in want.items()) + "\n"
                open(imp, "w").write(body)
                n += 1
    print(f"[texture_import] updated {n} texture import files")


if __name__ == "__main__":
    main()
