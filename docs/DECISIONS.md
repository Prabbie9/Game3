# Decisions log

- 2026-10-22 — Engine Godot 4.7.2 Forward+; physics engine **Jolt** (built-in since 4.4): faster, more stable vehicles/ragdolls.
- 2026-10-22 — Setting: fictional coastal city "Port Solano" (see ART_DIRECTION.md). Realistic PBR look; stylised low-poly kits excluded from visible world so Mixamo characters don't clash.
- 2026-10-22 — Releases via GitHub Actions on version tags (proxy blocks direct release API writes).
- 2026-10-22 — Mixamo clips are retargeted at import to `SkeletonProfileHumanoid` (BoneMap) so every character shares every animation; locomotion clips are made in-place and their native stride speed is recorded to drive playback speed (no foot sliding).
- 2026-10-22 — Repo is **public**, so Mixamo FBX files are NOT committed (brief: "keep them out of any public location" overrides "track used files in LFS"). `assets/mixamo_manifest.json` lists the used files; `tools/fetch_mixamo.py` downloads them from the owner's shared link locally and in CI. `assets/source/mixamo/` is git-ignored.
- 2026-10-22 — Buildings are procedural boxes with a facade shader (tiled Poly Haven PBR wall + procedural windows with interior mapping, lit shops) instead of modular kits: coherent look, few draw calls, night-lit windows for free.
- 2026-10-22 — Cars: Sketchfab "Generic passenger car pack" (CC-BY, 10 unbranded body types, separate wheels) split at runtime by CarLibrary; VehicleBody3D with our -Z forward (negative engine force).
- 2026-10-22 — Fan palms composed from a trunk mesh + the young fan-palm model as the crown (no CC mature Washingtonia found).
- 2026-10-22 — Wine can't run the Windows build in this container; smoke tests run the identical .pck on the Linux release template.
- 2026-10-22 — Only the player character is shipped until pedestrians (M6) to keep the pck small (345 MB); character textures capped at 2K.
- 2026-10-22 — The proxy returns 403 for tag pushes, so releases are cut by committing release.txt on main; the workflow tags and publishes with GITHUB_TOKEN.
- 2026-10-22 — v0.1.0 shipped an untextured player: the CI cache of assets/source/mixamo restored stale *.import files over the committed ones. CI now caches only *.fbx. Character textures are also embedded at import (Basis Universal) rather than extracted to PNGs, which is simpler and reproducible.
- 2026-10-22 — Traversal: vault/climb clips are fitted to the real obstacle by a vertical offset curve per clip
  (bump for vaults, ramp for the jump to hang, constant for the braced climb) plus a start placement from the
  measured hand-plant distance, instead of scaling the motion; root yaw isn't extracted for these clips (hip twist
  stays in the pose). Chest-high ledges use "Climb Wall From Braced Hang To Crouch"; higher ones chain
  "Jump To A Braced Hang" into it (same braced pose, no blend).
- 2026-10-22 — Mixamo's cover set is authored with the character turned around relative to its root, so the root faces
  the wall (FACING = PI) and lateral input maps to -tangent. Verified with front/side/back pose renders.
- 2026-10-22 — Street props get simple collision (cylinders for poles/hydrants/bins, bounds boxes otherwise) on layer 16;
  Poly Haven kits that stack clean + weathered variants keep one per instance (separate RNG so the layout is stable).
- 2026-10-22 — Gamepad: A = sprint, X = jump (GTA layout); keyboard shoulder swap moved to MMB since Q is cover.
