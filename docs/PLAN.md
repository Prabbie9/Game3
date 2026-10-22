# Plan — "Port Solano" open-world crime sandbox (Godot 4.7.2, Forward+)

Each milestone ends with a tagged Windows build (`vX.Y.0`, built by `.github/workflows/release.yml`).
Status lives in `PROGRESS.md`; this file only changes when scope/order changes.

| # | Milestone | Done when (player-visible) | Tag |
|---|-----------|----------------------------|-----|
| 1 | Playable vertical slice | One lit city block; Mixamo player walks/runs/jumps without sliding; one enterable drivable car; one pistol that shoots; basic HUD; perf overlay + benchmark; Windows build boots | v0.1.0 |
| 2 | Player polish | Full locomotion (start/stop, turn, crouch, vault/climb, swim, ragdoll fall), foot IK + pelvis, hand IK, camera modes (aim zoom, shoulder swap), cover, melee | v0.2.0 |
| 3 | World expansion | Districts (downtown, suburbs, docks, beach, hills), road network + highway, terrain, ocean, day/night, weather, chunk streaming, LOD/HLOD, occluders; perf budget met | v0.3.0 |
| 4 | Vehicles | All classes (compact…helicopter, boat, bike), per-class handling, enter/exit/passenger/carjack anims, damage, lights/indicators, skid marks, engine audio, vehicle cameras | v0.4.0 |
| 5 | Combat | 9 weapon types, weapon wheel, recoil/spread, hand IK grip, per-surface impacts, decals, ragdoll deaths, headshots, pickups, gun shop, drive-by | v0.5.0 |
| 6 | Population | Pedestrians (varied, navmesh sidewalks, crossings, idle behaviours, reactions/panic), traffic on lane graph with lights, emergency services | v0.6.0 |
| 7 | Police | 5-star wanted, crimes, LOS search, escalation (foot → cars → roadblocks → SWAT → heli), busted/wasted, respray | v0.7.0 |
| 8 | UI/UX | Themed HUD, minimap + full map + GPS, main/pause menus, settings (graphics presets, audio, rebinding, gameplay, display), gamepad prompts, save/load | v0.8.0 |
| 9 | Interactivity & life | Breakables, hydrants, physics props, interiors (shop, safehouse, diner), ATMs/vending/phone booths/benches/doors, money & collectibles, ambient life, radio | v0.9.0 |
| 10 | Polish & optimisation | Bug list cleared, animation/audio/visual consistency passes, perf pass on all presets, final export | v1.0.0 |

After v1.0.0: iterate on the weakest-looking / weakest-feeling areas (screenshot reviews), deepen systems.

## Per-session routine
1. `tools/setup_env.sh` (installs Godot 4.7.2 + templates, lavapipe, Xvfb, gdown).
2. Read `PROGRESS.md`, this file, `git log --oneline -20`.
3. If Mixamo source clips are needed and `assets/source/mixamo_raw/` is empty: `tools/fetch_mixamo.sh`.
4. Work → `tools/screenshots.sh` → look at the PNGs → commit/push → update `PROGRESS.md`.
5. Milestone end: `tools/export_windows.sh` + smoke test, write `vX.Y.0` to `release.txt` + update `release_notes.md`, push to main (the proxy blocks tag pushes; the workflow creates the tag + Release), check `gh run list`.
