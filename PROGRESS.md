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
- `... -- res://tests/abilities_check.gd [SHOT_DIR]` — drives every on-foot ability headless (crouch, vaults/climbs with
  hand-to-top distance, cover, punch, fall→ragdoll→get up, swim + climb out, run stop, turn in place). With a
  SHOT_DIR under `xvfb-run` it also saves a side-view picture of each pose.
- `... -- res://tools/dev/pose_sheet.gd OUT.png TIME clip…` — front/side/back render of library clips (orientation checks);
  `... -- res://tools/dev/action_trace.gd ACTION` — root path + hand/feet positions through a root-motion action.
- `tools/screenshots.sh OUT [day,aim,wide,pool,enter,car,night,rain,pause,menu]` — software-rendered review shots
  (+ draw-call/primitive stats in the log). ~1 min per shot.
- `tools/export_windows.sh` then smoke test: copy `~/.local/share/godot/export_templates/4.7.2.stable/linux_release.x86_64`
  as `PortSolano.x86_64` next to a symlink of `build/PortSolano/PortSolano.pck` and run
  `xvfb-run -a ./PortSolano.x86_64 -- --smoke` (must print `SMOKE TEST PASSED`, exit 0). Wine 9 crashes on start-up
  in this container (page fault inside ntdll), so the Linux template + same .pck is the boot check.
- `... -- res://tests/asset_check.gd` — characters textured, all clips resolve (also runs in CI before export).
- After a release: download the zip (`gh api repos/Prabbie9/Game3/releases/tags/vX`), smoke-test its pck, and compare
  `tools/pck_list.py` against the local build.
- Never use `pkill -f <pattern>` in the same shell command line that contains the pattern (kills itself); use `pat[t]ern`.

## Status
**Milestone 1 — Playable vertical slice: DONE (v0.1.1; v0.1.0 shipped an untextured player — fixed by embedding character textures)**
- Player: Mixamo Ch08 retargeted to SkeletonProfileHumanoid; AnimationTree (locomotion blendspace at native clip speeds,
  pistol aim strafe 2D, jump/fall/land with timed windows, car enter/drive/exit). Walk 1.0, run 4.2, sprint 6.4 m/s.
- Camera rig (on-foot / aim / vehicle, collision, shoulder swap).
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

**Milestone 2 — Player polish: DONE (v0.2.0)**
- Foot IK (raycast feet + pelvis drop, TwoBoneIK legs, foot alignment) and left-hand IK on the pistol grip.
- Crouch (toggle C / L3, crouch walk at clip speed, camera lowers), run stop clip after letting go at a run, turn on
  the spot for sharp reversals from standstill.
- Traversal (Space / X at an obstacle): one-handed vault < 0.95 m, two-handed vault up to 1.35 m (thin obstacles),
  braced climb for 1.0–1.55 m ledges, jump-to-braced-hang + climb for 1.55–2.4 m. Clips are offset to the real
  obstacle height so the hands land on the top surface (checked in abilities_check).
- Cover (Q / RB): snaps the back to a wall, high/low cover, slides along it with the sneak clips, stops at the edge.
- Fists (mouse wheel / D-pad toggles fists ↔ pistol): jab/cross/hook combo, hits bodies, knocks props.
- Swimming in water volumes (plaza pool), treading water / swimming, climb out over an edge (jump or keep pushing).
- Long falls ragdoll in mid-air (Jolt PhysicalBones, damage from predicted impact speed), get up from back/front;
  hard landings; death → respawn.
- Camera: follows the pelvis during vaults/climbs/ragdoll, wider FOV when sprinting, lower in crouch/low cover,
  hides the character when squeezed against it; shoulder swap moved to MMB / R3.
- World: sunken public pool in the plaza (procedural mosaic tiles + caustics, refractive water shader), benches
  assembled from the modular kit, street props now solid (collision layer 16) with one weathering variant each.
- Pause menu lists the controls for the current device; gamepad jump moved to X (A = sprint).

**Next: Milestone 3 — World expansion** (see docs/PLAN.md): districts, road network + highway, terrain, ocean,
day/night with street lights, weather, chunk streaming, LOD/HLOD, occluders; hit the perf budget.

### Known issues / debt
- Car doors don't open during entry (car pack has no separate door meshes) — character passes through the door.
- Night lighting not done (no street-light lights yet) — Milestone 3 day/night.
- Wheels sit ~4 cm low on the road (suspension/visual offset) — check in M4 handling pass.
- Swimming uses Mixamo's "Swimming Underwater" for surface swimming and "Floating" for treading water: the shared
  library has no freestyle/treading-water clips (owner checklist asks for them).
- Props are solid but not breakable yet (Milestone 9).
- Default branch is still `claude/tmp-push-test` (proxy blocks changing it) → owner checklist item.

### Builds
| Tag | Milestone | Where |
|---|---|---|
| v0.1.0 | 1 — vertical slice (player untextured — superseded) | GitHub Release |
| v0.1.1 | 1 — vertical slice hotfix | GitHub Release (workflow runs on release.txt change) |
| v0.2.0 | 2 — player polish | GitHub Release |
