# PROGRESS — read this first every session

**Mixamo library (owner's shared Drive folder — download over this link with `tools/fetch_mixamo.py` / gdown):**
https://drive.google.com/drive/folders/1EEE9K89wnqsCae86tSGU-OfidZIGW-bW?usp=sharing
(`tools/mixamo_index.json` maps every file name → Drive id; `python3 tools/fetch_mixamo.py --grep walk` searches names.)

## Session start
1. `tools/setup_env.sh` (Godot 4.7.2 + templates, lavapipe, Xvfb, gdown).
2. Read this file, `docs/PLAN.md`, `git log --oneline -20`.
3. `python3 tools/fetch_mixamo.py` → fetches the Mixamo files listed in `assets/mixamo_manifest.json`
   (FBX/PNG are git-ignored: public repo). Then `python3 tools/mixamo_import.py && python3 tools/texture_import.py && godot --headless --import --path .`
   (first import of characters takes ~2 min each — only the player character is in the manifest right now).

## Checks (run after relevant changes)
- `godot --headless --path . res://tests/runner.tscn -- res://tools/dev/check_scripts.gd` — every script compiles.
- `... -- res://tests/grounding_check.gd` — feet on ground at all gaits, pistol in hand, wheels on road.
- `... -- res://tests/drive_check.gd` — enter car, accelerate, brake, steer, stay upright, exit.
- `tools/screenshots.sh OUT [day,aim,wide,enter,car,night,rain,pause,menu]` — software-rendered review shots
  (+ draw-call/primitive stats in the log). ~1 min per shot.
- `tools/export_windows.sh` then smoke test: copy `~/.local/share/godot/export_templates/4.7.2.stable/linux_release.x86_64`
  as `PortSolano.x86_64` next to a symlink of `build/PortSolano/PortSolano.pck` and run
  `xvfb-run -a ./PortSolano.x86_64 -- --smoke` (must print `SMOKE TEST PASSED`, exit 0). Wine 9 crashes on start-up
  in this container (page fault inside ntdll), so the Linux template + same .pck is the boot check.
- Never use `pkill -f <pattern>` in the same shell command line that contains the pattern (kills itself); use `pat[t]ern`.

## Status
**Milestone 1 — Playable vertical slice: DONE (v0.1.0)**
- Player: Mixamo Ch08 retargeted to SkeletonProfileHumanoid; AnimationTree (locomotion blendspace at native clip speeds,
  pistol aim strafe 2D, jump/fall/land with timed windows, car enter/drive/exit). Walk 1.0, run 4.2, sprint 6.4 m/s.
- Camera rig (on-foot / aim / vehicle, collision, shoulder swap Q).
- City: 3x3 road grid (±110 m), procedural road markings/crosswalks/stop lines, curbs with ramp collision, 4 blocks +
  outer ring of facade-shaded buildings (interior-mapped windows, lit shops), palms (composed fan palms + date palms),
  Poly Haven street props, distant skyline, road-end barriers.
- Vehicles: 6 parked cars from the generic car pack (10 body types available), enter/exit with Mixamo clips aligned to
  the door via root-motion displacement, arcade handling (speed-sensitive steering, anti-roll, handbrake), headlights (L).
- Pistol (M1911): hit-scan, recoil, spread, reload, muzzle flash light, tracers, pooled decals/impact particles.
- HUD: vector minimap, health/armor, money, weapon/ammo, crosshair, speedometer, vehicle toast, notifications, prompts.
- Main menu over live city, pause menu, graphics presets (Low/Medium/High/Ultra) persisted, F3 perf overlay,
  benchmark mode (menu or `-- --benchmark`) writing report + CSV next to the exe.
- Perf (software-rendered measurement of draw calls only): street view 532 draws (+1249 shadow), 2.3 M prims.

**Next: Milestone 2 — Player polish** (see docs/PLAN.md): foot IK + pelvis, left-hand IK on the pistol, start/stop &
turn-in-place, crouch, vault/climb, swimming, ragdoll, cover, melee; more camera polish.

### Known issues / debt
- Car doors don't open during entry (car pack has no separate door meshes) — character passes through the door.
- Night lighting not done (no street-light lights yet) — Milestone 3 day/night.
- Wheels sit ~4 cm low on the road (suspension/visual offset) — check in M4 handling pass.
- Pistol aim pose has no left-hand support yet (hand IK in M2).
- Default branch is still `claude/tmp-push-test` (proxy blocks changing it) → owner checklist item.

### Builds
| Tag | Milestone | Where |
|---|---|---|
| v0.1.0 | 1 — vertical slice | GitHub Release (Actions workflow on tag) |
