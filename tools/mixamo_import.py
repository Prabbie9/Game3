#!/usr/bin/env python3
"""Write Godot .import settings for every Mixamo FBX in assets/source/mixamo/.

Each file gets a BoneMap (per bone-name prefix, e.g. mixamorig7_) to SkeletonProfileHumanoid, so all
characters share one humanoid skeleton ("GeneralSkeleton") and every clip plays on every character.
Characters import as scenes, animations as AnimationLibrary resources. Run before `godot --import`.
"""
import os, re, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIGS = os.path.join(ROOT, "assets", "rigs")

# Mixamo bone (without prefix) -> SkeletonProfileHumanoid bone
MAP = {"Hips": "Hips", "Spine": "Spine", "Spine1": "Chest", "Spine2": "UpperChest", "Neck": "Neck", "Head": "Head"}
for s in ("Left", "Right"):
    MAP.update({
        f"{s}Shoulder": f"{s}Shoulder", f"{s}Arm": f"{s}UpperArm", f"{s}ForeArm": f"{s}LowerArm", f"{s}Hand": f"{s}Hand",
        f"{s}UpLeg": f"{s}UpperLeg", f"{s}Leg": f"{s}LowerLeg", f"{s}Foot": f"{s}Foot", f"{s}ToeBase": f"{s}Toes",
        f"{s}HandThumb1": f"{s}ThumbMetacarpal", f"{s}HandThumb2": f"{s}ThumbProximal", f"{s}HandThumb3": f"{s}ThumbDistal",
    })
    for mx, hp in (("Index", "Index"), ("Middle", "Middle"), ("Ring", "Ring"), ("Pinky", "Little")):
        MAP.update({f"{s}Hand{mx}1": f"{s}{hp}Proximal", f"{s}Hand{mx}2": f"{s}{hp}Intermediate", f"{s}Hand{mx}3": f"{s}{hp}Distal"})


def bonemap_for(prefix):
    path = os.path.join(RIGS, f"bonemap_{prefix}.tres")
    if not os.path.exists(path):
        os.makedirs(RIGS, exist_ok=True)
        lines = ['[gd_resource type="BoneMap" load_steps=2 format=3]', "",
                 '[sub_resource type="SkeletonProfileHumanoid" id="SkeletonProfileHumanoid_1"]', "", "[resource]",
                 'profile = SubResource("SkeletonProfileHumanoid_1")']
        for mx, hp in MAP.items():
            lines.append(f'bone_map/{hp} = &"{prefix}_{mx}"')
        open(path, "w").write("\n".join(lines) + "\n")
    return "res://" + os.path.relpath(path, ROOT)


def detect_prefix(fbx):
    data = open(fbx, "rb").read()
    m = re.search(rb"(mixamorig\d*):Hips", data)
    return m.group(1).decode() if m else "mixamorig"


def write_import(fbx, kind):
    rel = "res://" + os.path.relpath(fbx, ROOT)
    bm = bonemap_for(detect_prefix(fbx))
    is_anim = kind == "animations"
    imp = fbx + ".import"
    uid = None
    if os.path.exists(imp):
        m = re.search(r'uid="(uid://[a-z0-9]+)"', open(imp).read())
        uid = m.group(1) if m else None
    out = ["[remap]", "", f'importer="{"animation_library" if is_anim else "scene"}"', "importer_version=1",
           f'type="{"AnimationLibrary" if is_anim else "PackedScene"}"']
    if uid:
        out.append(f'uid="{uid}"')
    out += ["", "[deps]", "", f'source_file="{rel}"', "", "[params]", "",
            'nodes/root_type=""', 'nodes/root_name=""', "nodes/apply_root_scale=true", "nodes/root_scale=1.0",
            "nodes/import_as_skeleton_bones=false", "nodes/use_name_suffixes=true", "nodes/use_node_type_suffixes=true",
            "meshes/ensure_tangents=true", f"meshes/generate_lods={'false' if is_anim else 'true'}",
            "meshes/create_shadow_meshes=true", "meshes/light_baking=1", "meshes/lightmap_texel_size=0.2",
            "meshes/force_disable_compression=false", "skins/use_named_skins=true",
            "animation/import=true", "animation/fps=30", "animation/trimming=true",
            "animation/remove_immutable_tracks=true", "animation/import_rest_as_RESET=false",
            'import_script/path=""', "materials/extract=0", "materials/extract_format=0", 'materials/extract_path=""',
            '_subresources={', '"nodes": {', '"PATH:Skeleton3D": {',
            f'"retarget/bone_map": Resource("{bm}"),',
            '"retarget/bone_renamer/unique_node/skeleton_name": "GeneralSkeleton"',
            '}', '}', '}',
            "fbx/importer=0", "fbx/allow_geometry_helper_nodes=false",
            # embed textures (Basis Universal) instead of extracting PNGs: extraction does not happen on a fresh
            # checkout (CI), which shipped an untextured player in v0.1.0
            f"fbx/embedded_image_handling={0 if is_anim else 2}", "fbx/naming_version=2", ""]
    new = "\n".join(out)
    if not os.path.exists(imp) or "retarget/bone_map" not in open(imp).read() or "embedded_image_handling=1" in open(imp).read():
        open(imp, "w").write(new)
        return True
    return False


def main():
    changed = 0
    for kind in ("characters", "animations"):
        for fbx in sorted(glob.glob(os.path.join(ROOT, "assets", "source", "mixamo", kind, "*.fbx"))):
            changed += write_import(fbx, kind)
    print(f"[mixamo_import] wrote {changed} import settings")


if __name__ == "__main__":
    main()
