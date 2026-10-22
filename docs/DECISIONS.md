# Decisions log

- 2026-10-22 — Engine Godot 4.7.2 Forward+; physics engine **Jolt** (built-in since 4.4): faster, more stable vehicles/ragdolls.
- 2026-10-22 — Setting: fictional coastal city "Port Solano" (see ART_DIRECTION.md). Realistic PBR look; stylised low-poly kits excluded from visible world so Mixamo characters don't clash.
- 2026-10-22 — Releases via GitHub Actions on version tags (proxy blocks direct release API writes).
- 2026-10-22 — Mixamo clips are retargeted at import to `SkeletonProfileHumanoid` (BoneMap) so every character shares every animation; locomotion clips are made in-place and their native stride speed is recorded to drive playback speed (no foot sliding).
- 2026-10-22 — Repo is **public**, so Mixamo FBX files are NOT committed (brief: "keep them out of any public location" overrides "track used files in LFS"). `assets/mixamo_manifest.json` lists the used files; `tools/fetch_mixamo.py` downloads them from the owner's shared link locally and in CI. `assets/source/mixamo/` is git-ignored.
